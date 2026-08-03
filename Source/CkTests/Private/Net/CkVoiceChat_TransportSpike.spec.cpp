// CkVoiceChat P0 transport spike (THROWAWAY — delete with the campaign's P0 artifacts).
//
// Measures the composite the voice design leans on but nothing in production exercises yet:
// sustained-rate Unreliable unicast Client-direction RPCs on a per-player replicated actor under
// the fork's Iris stack (net.Iris.UseIrisReplication=1 in the host project).
//
//   1. UnreliableUnicast_DeliveryUnderLoad — four measured windows on one channel actor owned by
//      the remote client's PlayerState: idle (wire-byte baseline), 1 bundle/tick x 300 (voice
//      cadence proxy), 8 bundles/tick x 300 (MaxAudibleSpeakers worth of streams), and
//      8 bundles/tick x 300 while a pressure actor rewrites a 64 KB replicated payload every tick
//      (state saturation). Reliable control RPCs ride alongside as the delivery yardstick.
//      All numbers land in the log under the [VoiceSpike] prefix for the spike memo.
//
//   2. UnresolvedTarget_SilentDrop — 20 unreliable + 5 reliable Client RPCs fired the same frame
//      the channel actor is spawned (creation not yet replicated). Asserts the client does not
//      produce a per-RPC LogNet/LogIris warning/error storm, and records what actually arrives.
//
// Surface in Session Frontend: Ck.VoiceChat.Spike.*

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkCore/Macros/CkMacros.h"

#include "Engine/NetConnection.h"
#include "Engine/NetDriver.h"
#include "Engine/World.h"
#include "GameFramework/PlayerController.h"
#include "GameFramework/PlayerState.h"
#include "Misc/OutputDevice.h"
#include "Misc/ScopeLock.h"

#include "CkTests/Net/CkAutoTest_VoiceSpike.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include <atomic>

// --------------------------------------------------------------------------------------------------------------------

namespace ck_voice_spike_spec
{
    constexpr auto BundleBytes = 190;          // 3 x 60 B Opus frames + 7 B header (spec wire format)
    constexpr auto PhaseTicks = 300;
    constexpr auto SendWindowSlackTicks = 5;   // config lands between frames; budget needs a hair over PhaseTicks to drain
    constexpr auto DrainTimeoutSeconds = 90.0;
    constexpr auto IdleTicks = 120;
    constexpr auto ControlCadenceTicks = 10;
    constexpr auto PressureChurnBytes = 60000; // Iris FArrayPropertyNetSerializer caps arrays at 65535 elements

    struct FVoiceSpikeResults
    {
        // per-phase deltas
        int64 IdleWireBytes = -1;
        int64 PhaseWireBytes[3] = {-1, -1, -1};
        int32 PhaseSent[3] = {};
        int32 PhaseRecv[3] = {};
        int32 PhaseOutOfOrder[3] = {};
        int32 PhaseCtrlSent[3] = {};
        int32 PhaseCtrlRecv[3] = {};
        int32 PhaseLagMin[3] = {};
        int32 PhaseLagMax[3] = {};
        float PhaseLagAvg[3] = {};

        // scratch marks taken at each phase boundary
        int64 WireBytesMark = -1;
        int32 SentMark = 0;
        int32 CtrlSentMark = 0;
        int32 RecvMark = 0;
        int32 CtrlRecvMark = 0;
        int32 OutOfOrderMark = 0;
        int64 LagSumMark = 0;
    };

    auto Get_RemoteConnectionOutTotalBytes(UWorld* InServer) -> int64
    {
        auto* Driver = InServer->GetNetDriver();
        if (Driver == nullptr || Driver->ClientConnections.Num() == 0 || Driver->ClientConnections[0] == nullptr)
        { return -1; }

        return Driver->ClientConnections[0]->OutTotalBytes;
    }

    auto SpawnChannelOwnedByRemoteClient(FAutomationTestBase* InTest, UWorld* InServer) -> ACk_AutoTest_VoiceSpikeChannel_UE*
    {
        auto* RemotePC = ck::auto_test::net::Get_RemoteClientPlayerController(InServer, 0);
        if (RemotePC == nullptr || RemotePC->PlayerState == nullptr)
        { InTest->AddError(TEXT("remote client PlayerController/PlayerState unavailable")); return nullptr; }

        auto SpawnInfo = FActorSpawnParameters{};
        SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;

        auto* Channel = InServer->SpawnActor<ACk_AutoTest_VoiceSpikeChannel_UE>(
            ACk_AutoTest_VoiceSpikeChannel_UE::StaticClass(), FTransform::Identity, SpawnInfo);
        if (Channel == nullptr)
        { InTest->AddError(TEXT("SpawnActor of ACk_AutoTest_VoiceSpikeChannel_UE returned null")); return nullptr; }

        // same ownership shape the relay group subsystem gives per-player channels
        Channel->SetOwner(RemotePC->PlayerState);
        return Channel;
    }

    // Counts Warning-or-worse log output from the net stack (LogIris*/LogNet*) so "no log storm"
    // is a measured number instead of an impression. Static storage: registration with GLog must
    // not dangle if a latent chain aborts early.
    class FNetLogCounter : public FOutputDevice
    {
    public:
        auto Serialize(const TCHAR* InText, ELogVerbosity::Type InVerbosity, const FName& InCategory) -> void override
        {
            if (InVerbosity == ELogVerbosity::NoLogging || InVerbosity > ELogVerbosity::Warning)
            { return; }

            const auto CategoryStr = InCategory.ToString();
            if (NOT (CategoryStr.StartsWith(TEXT("LogIris")) || CategoryStr.StartsWith(TEXT("LogNet"))))
            { return; }

            _Count.fetch_add(1);

            FScopeLock Lock{&_SamplesCs};
            if (_Samples.Num() < 10)
            { _Samples.Add(FString::Printf(TEXT("[%s] %s"), *CategoryStr, InText)); }
        }

        auto Reset() -> void
        {
            _Count.store(0);
            FScopeLock Lock{&_SamplesCs};
            _Samples.Reset();
        }

        std::atomic<int32> _Count{0};
        FCriticalSection _SamplesCs;
        TArray<FString> _Samples;
    };

    static FNetLogCounter GNetLogCounter;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkVoiceChatSpike_UnreliableUnicast_DeliveryUnderLoad,
    "Ck.VoiceChat.Spike.UnreliableUnicast_DeliveryUnderLoad",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkVoiceChatSpike_UnreliableUnicast_DeliveryUnderLoad::RunTest(const FString& Parameters)
{
    using namespace ck_voice_spike_spec;

    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};
    const auto Results = MakeShared<FVoiceSpikeResults, ESPMode::ThreadSafe>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(2, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(2, 30.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            SpawnChannelOwnedByRemoteClient(this, InServer);

            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
            InServer->SpawnActor<ACk_AutoTest_VoiceSpikePressure_UE>(
                ACk_AutoTest_VoiceSpikePressure_UE::StaticClass(), FTransform::Identity, SpawnInfo);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            return ACk_AutoTest_VoiceSpikeChannel_UE::Find(Client) != nullptr &&
                   ACk_AutoTest_VoiceSpikePressure_UE::Find(Client) != nullptr;
        }), 15.0, TEXT("client resolved spike channel + pressure actors")));

    // ---- window 0: idle wire-byte baseline ------------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([Results](UWorld* InServer) -> void
        {
            Results->WireBytesMark = Get_RemoteConnectionOutTotalBytes(InServer);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(IdleTicks));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([Results](UWorld* InServer) -> void
        {
            Results->IdleWireBytes = Get_RemoteConnectionOutTotalBytes(InServer) - Results->WireBytesMark;
        })));

    // ---- windows 1-3: {1/tick}, {8/tick}, {8/tick + 64KB/tick state churn} ----------------------

    struct FPhaseConfig
    {
        int32 BundlesPerTick = 0;
        int32 ChurnBytes = 0;
    };
    const FPhaseConfig Phases[3] = {
        {1, 0},
        {8, 0},
        {8, PressureChurnBytes},
    };

    for (auto PhaseIdx = 0; PhaseIdx < 3; ++PhaseIdx)
    {
        const auto Config = Phases[PhaseIdx];

        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(0,
            FCk_NetAutoTest_ServerAction::CreateLambda([Results](UWorld* InClient) -> void
            {
                auto* Channel = ACk_AutoTest_VoiceSpikeChannel_UE::Find(InClient);
                if (Channel == nullptr) { return; }
                Results->RecvMark = Channel->_ReceivedBundles;
                Results->CtrlRecvMark = Channel->_ReceivedControls;
                Results->OutOfOrderMark = Channel->_OutOfOrderArrivals;
                Results->LagSumMark = Channel->_LagTicksSum;
                Channel->_LagTicksMax = MIN_int32;
                Channel->_LagTicksMin = MAX_int32;
            })));

        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
            FCk_NetAutoTest_ServerAction::CreateLambda([Results, Config](UWorld* InServer) -> void
            {
                auto* Channel = ACk_AutoTest_VoiceSpikeChannel_UE::Find(InServer);
                auto* Pressure = ACk_AutoTest_VoiceSpikePressure_UE::Find(InServer);
                if (Channel == nullptr || Pressure == nullptr) { return; }

                Results->WireBytesMark = Get_RemoteConnectionOutTotalBytes(InServer);
                Results->SentMark = Channel->_SentBundles;
                Results->CtrlSentMark = Channel->_SentControls;

                Channel->_BundleBytes = BundleBytes;
                Channel->_BundlesPerTick = Config.BundlesPerTick;
                Channel->_RemainingBundleBudget = Config.BundlesPerTick * PhaseTicks;
                Channel->_ControlEveryNTicks = ControlCadenceTicks;
                Pressure->_ChurnBytesPerTick = Config.ChurnBytes;
            })));

        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(PhaseTicks + SendWindowSlackTicks));

        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
            FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
            {
                auto* Channel = ACk_AutoTest_VoiceSpikeChannel_UE::Find(InServer);
                auto* Pressure = ACk_AutoTest_VoiceSpikePressure_UE::Find(InServer);
                if (Channel == nullptr || Pressure == nullptr) { return; }

                Channel->_BundlesPerTick = 0;
                Channel->_ControlEveryNTicks = 0;
                Pressure->_ChurnBytesPerTick = 0;
            })));

        // In-process delivery is lossless on the ordered path, so "recv == sent" is the drain
        // criterion; the interesting pressure metric is how LONG the drain takes (lag max).
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
            FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
            {
                auto* ServerChannel = ACk_AutoTest_VoiceSpikeChannel_UE::Find(ck::auto_test::net::Get_ServerWorld());
                auto* ClientChannel = ACk_AutoTest_VoiceSpikeChannel_UE::Find(ck::auto_test::net::Get_ClientWorld(0));
                if (ServerChannel == nullptr || ClientChannel == nullptr) { return false; }
                return ClientChannel->_ReceivedBundles >= ServerChannel->_SentBundles &&
                       ClientChannel->_ReceivedControls >= ServerChannel->_SentControls;
            }), DrainTimeoutSeconds, TEXT("phase queue fully drained to the client")));

        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(10));

        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
            FCk_NetAutoTest_ServerAction::CreateLambda([Results, PhaseIdx](UWorld* InServer) -> void
            {
                auto* Channel = ACk_AutoTest_VoiceSpikeChannel_UE::Find(InServer);
                if (Channel == nullptr) { return; }
                Results->PhaseWireBytes[PhaseIdx] = Get_RemoteConnectionOutTotalBytes(InServer) - Results->WireBytesMark;
                Results->PhaseSent[PhaseIdx] = Channel->_SentBundles - Results->SentMark;
                Results->PhaseCtrlSent[PhaseIdx] = Channel->_SentControls - Results->CtrlSentMark;
            })));

        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(0,
            FCk_NetAutoTest_ServerAction::CreateLambda([Results, PhaseIdx](UWorld* InClient) -> void
            {
                auto* Channel = ACk_AutoTest_VoiceSpikeChannel_UE::Find(InClient);
                if (Channel == nullptr) { return; }
                Results->PhaseRecv[PhaseIdx] = Channel->_ReceivedBundles - Results->RecvMark;
                Results->PhaseCtrlRecv[PhaseIdx] = Channel->_ReceivedControls - Results->CtrlRecvMark;
                Results->PhaseOutOfOrder[PhaseIdx] = Channel->_OutOfOrderArrivals - Results->OutOfOrderMark;
                Results->PhaseLagMin[PhaseIdx] = Channel->_LagTicksMin;
                Results->PhaseLagMax[PhaseIdx] = Channel->_LagTicksMax;
                Results->PhaseLagAvg[PhaseIdx] = Results->PhaseRecv[PhaseIdx] > 0
                    ? static_cast<float>(Channel->_LagTicksSum - Results->LagSumMark) / Results->PhaseRecv[PhaseIdx]
                    : 0.0f;
            })));
    }

    // ---- report + sanity assertions --------------------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, Results]() -> bool
        {
            const TCHAR* const PhaseName[3] = {TEXT("A_1PerTick"), TEXT("B_8PerTick"), TEXT("C_8PerTick_Saturated")};

            UE_LOG(LogTemp, Display, TEXT("[VoiceSpike] Idle window: %d ticks, %lld wire bytes"),
                IdleTicks, Results->IdleWireBytes);

            for (auto PhaseIdx = 0; PhaseIdx < 3; ++PhaseIdx)
            {
                const auto PhaseStats = FString::Printf(
                    TEXT("sent=%d recv=%d (%.1f%%) outOfOrder=%d ctrlSent=%d ctrlRecv=%d wireBytes=%lld lagTicks(min/avg/max)=%d/%.1f/%d"),
                    Results->PhaseSent[PhaseIdx], Results->PhaseRecv[PhaseIdx],
                    Results->PhaseSent[PhaseIdx] > 0 ? 100.0f * Results->PhaseRecv[PhaseIdx] / Results->PhaseSent[PhaseIdx] : 0.0f,
                    Results->PhaseOutOfOrder[PhaseIdx],
                    Results->PhaseCtrlSent[PhaseIdx], Results->PhaseCtrlRecv[PhaseIdx],
                    Results->PhaseWireBytes[PhaseIdx],
                    Results->PhaseLagMin[PhaseIdx], Results->PhaseLagAvg[PhaseIdx], Results->PhaseLagMax[PhaseIdx]);

                UE_LOG(LogTemp, Display, TEXT("[VoiceSpike] Phase %s: %s"), PhaseName[PhaseIdx], *PhaseStats);
            }

            TestEqual(TEXT("Phase A sent the full budget"), Results->PhaseSent[0], PhaseTicks);

            for (auto PhaseIdx = 0; PhaseIdx < 3; ++PhaseIdx)
            {
                // A drain timeout (recv < sent here) is the ADR-4 STOP condition: it would mean
                // the ordered-unreliable path genuinely lost or indefinitely starved traffic.
                TestEqual(FString::Printf(TEXT("Phase %s: every unreliable bundle drained to the client"), PhaseName[PhaseIdx]),
                    Results->PhaseRecv[PhaseIdx], Results->PhaseSent[PhaseIdx]);
                TestEqual(FString::Printf(TEXT("Phase %s: reliable control fully delivered"), PhaseName[PhaseIdx]),
                    Results->PhaseCtrlRecv[PhaseIdx], Results->PhaseCtrlSent[PhaseIdx]);
            }

            return true;
        }), TEXT("[VoiceSpike] delivery/overhead report")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkVoiceChatSpike_UnresolvedTarget_SilentDrop,
    "Ck.VoiceChat.Spike.UnresolvedTarget_SilentDrop",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkVoiceChatSpike_UnresolvedTarget_SilentDrop::RunTest(const FString& Parameters)
{
    using namespace ck_voice_spike_spec;

    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};
    constexpr auto UnreliableBurst = 20;
    constexpr auto ReliableBurst = 5;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(2, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(2, 30.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            GNetLogCounter.Reset();
            GLog->AddOutputDevice(&GNetLogCounter);

            auto* Channel = SpawnChannelOwnedByRemoteClient(this, InServer);
            if (Channel == nullptr) { return; }

            // fired the same frame as the spawn: the client cannot have the actor yet
            for (auto Seq = 0; Seq < UnreliableBurst; ++Seq)
            {
                auto Payload = TArray<uint8>{};
                Payload.SetNumZeroed(BundleBytes);
                Channel->Client_ReceiveVoiceBundle(Seq, Payload);
                ++Channel->_SentBundles;
            }
            for (auto Seq = 0; Seq < ReliableBurst; ++Seq)
            {
                Channel->Client_ReceiveControl(Seq);
                ++Channel->_SentControls;
            }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(90));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            GLog->RemoveOutputDevice(&GNetLogCounter);

            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            auto* Channel = ACk_AutoTest_VoiceSpikeChannel_UE::Find(Client);

            const auto Received = Channel != nullptr ? Channel->_ReceivedBundles : -1;
            const auto ReceivedCtrl = Channel != nullptr ? Channel->_ReceivedControls : -1;
            const auto NetLogCount = GNetLogCounter._Count.load();

            UE_LOG(LogTemp, Display,
                TEXT("[VoiceSpike] Unresolved-target burst: unreliableSent=%d unreliableRecv=%d reliableSent=%d reliableRecv=%d netWarningsOrWorse=%d"),
                UnreliableBurst, Received, ReliableBurst, ReceivedCtrl, NetLogCount);

            {
                FScopeLock Lock{&GNetLogCounter._SamplesCs};
                for (const auto& Sample : GNetLogCounter._Samples)
                { UE_LOG(LogTemp, Display, TEXT("[VoiceSpike] net-log sample: %s"), *Sample); }
            }

            TestTrue(TEXT("client resolved the channel actor after the burst"), Channel != nullptr);
            TestTrue(TEXT("no per-RPC net log storm (warnings-or-worse < burst size)"),
                NetLogCount < UnreliableBurst);
            TestEqual(TEXT("reliable burst fully delivered once the actor resolved"),
                ReceivedCtrl, ReliableBurst);

            return true;
        }), TEXT("[VoiceSpike] unresolved-target report")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
