// P3 S5 instrumentation (spike amendment S5 / Gate_3 item 9): MEASURE the per-connection drain
// rate of the unreliable relay path in this harness's PIE net config, so the default
// MaxVoiceBytesPerConnectionPerTick is set from observed numbers instead of optimism. The spike
// warning: the transport queues thousands of bundles silently, so a voice byte budget above the
// real drain rate converts loss into unbounded latency.
//
// Method: burst 2000 x 240 B payloads (0xFF fill - guaranteed to fail Unpack_Bundle client-side,
// so nothing touches the decoder) through Client_ReceiveVoiceBundle in ONE server-side call.
// Iris queues the burst; the connection drains it at its budgeted rate. The arrival totals
// (counted at the RPC boundary, before the inbox cap) sampled at tick marks give the drain
// slope directly. Numbers land in the log via AddInfo and are recorded in Gate_3.md - the
// assertions here are sanity only (delivery happened, totals are monotone), NOT thresholds:
// the rate is machine/config-dependent and this spec must not flake on a slower box.
//
// Surface in Session Frontend: Ck.VoiceChat.Net.DrainBudgetMeasure

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "EngineUtils.h"

#include "CkVoiceChat/Net/CkVoiceChatRelay_Actor.h"
#include "CkVoiceChat/Net/CkVoiceChatRelay_Subsystem.h"
#include "CkVoiceChat/VoiceTalker/CkVoiceTalker_Utils.h"

#include "CkTests/Net/CkAutoTest_NetSubject_VoiceChat.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include <GameFramework/PlayerController.h>
#include <GameFramework/PlayerState.h>

// --------------------------------------------------------------------------------------------------------------------

namespace ck_voice_drain_spec
{
    constexpr auto BurstBundles = 2000;
    constexpr auto BundleBytes = 240;      // MaxPackedBundleBytes - the representative wire size (S3)
    constexpr auto MarkOneTicks = 30;
    constexpr auto MarkWindowTicks = 60;

    struct FDrainSpecState
    {
        uint64 Bundles1 = 0; uint64 Bytes1 = 0;
        uint64 Bundles2 = 0; uint64 Bytes2 = 0;
        uint64 Bundles3 = 0; uint64 Bytes3 = 0;
    };

    auto Find_SpeakerReplica(UWorld* InWorld) -> ACk_AutoTest_NetSubject_VoiceChat_UE*
    {
        for (TActorIterator<ACk_AutoTest_NetSubject_VoiceChat_UE> It{InWorld}; It; ++It)
        { return *It; }

        return nullptr;
    }

    auto Read_ArrivalTotals(uint64& OutBundles, uint64& OutBytes) -> bool
    {
        auto* Client = ck::auto_test::net::Get_ClientWorld(0);
        auto* Speaker = Client != nullptr ? Find_SpeakerReplica(Client) : nullptr;

        if (Speaker == nullptr || ck::Is_NOT_Valid(Speaker->_TestTalker))
        { return false; }

        OutBundles = UCk_Utils_VoiceTalker_UE::Debug_Get_ReceiveArrivedBundles(Speaker->_TestTalker);
        OutBytes = UCk_Utils_VoiceTalker_UE::Debug_Get_ReceiveArrivedBytes(Speaker->_TestTalker);
        return true;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkVoiceChatNet_DrainBudgetMeasure,
    "Ck.VoiceChat.Net.DrainBudgetMeasure",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkVoiceChatNet_DrainBudgetMeasure::RunTest(const FString& Parameters)
{
    using namespace ck_voice_drain_spec;

    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};
    const auto State = MakeShared<FDrainSpecState, ESPMode::ThreadSafe>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(2, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(2, 30.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;

            if (InServer->SpawnActor<ACk_AutoTest_NetSubject_VoiceChat_UE>(
                    ACk_AutoTest_NetSubject_VoiceChat_UE::StaticClass(), FTransform::Identity, SpawnInfo) == nullptr)
            { AddError(TEXT("spawn of the speaker subject failed")); }
        })));

    // The subject replicates and its talker composes client-side; the relay channels for the
    // remote player exist from PostLogin.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(40));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Speaker = Find_SpeakerReplica(InServer);
            if (Speaker == nullptr || ck::Is_NOT_Valid(Speaker->_TestTalker))
            {
                AddError(TEXT("speaker subject missing on the server at flood time"));
                return;
            }

            auto* RemotePlayer = static_cast<APlayerState*>(nullptr);
            for (auto It = InServer->GetPlayerControllerIterator(); It; ++It)
            {
                if (auto* Controller = It->Get();
                    Controller != nullptr && NOT Controller->IsLocalController() && Controller->PlayerState != nullptr)
                { RemotePlayer = Controller->PlayerState; }
            }

            if (RemotePlayer == nullptr)
            {
                AddError(TEXT("no remote player on the server at flood time"));
                return;
            }

            auto* Subsystem = InServer->GetSubsystem<UCk_VoiceChatRelay_Subsystem_UE>();
            if (Subsystem == nullptr)
            {
                AddError(TEXT("voice relay subsystem missing on the server"));
                return;
            }

            auto Pending = Subsystem->Request_AcquireChannel_ForPlayer(RemotePlayer);
            const auto Result = Subsystem->Try_ResolvePending(Pending);
            auto* Relay = ::Cast<ACk_VoiceChatRelay_UE>(Result.Get_ChannelActor().Get());

            if (Relay == nullptr)
            {
                AddError(TEXT("the remote player's voice relay channel did not resolve at flood time"));
                return;
            }

            auto Payload = TArray<uint8>{};
            Payload.Init(0xFF, BundleBytes);

            for (auto Index = 0; Index < BurstBundles; ++Index)
            {
                Relay->Client_ReceiveVoiceBundle(Speaker->_TestTalker, Payload);
            }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(MarkOneTicks));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            if (NOT Read_ArrivalTotals(State->Bundles1, State->Bytes1))
            {
                AddError(TEXT("speaker replica missing client-side at mark 1"));
                return false;
            }

            return true;
        }),
        TEXT("mark 1 sampled")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(MarkWindowTicks));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            if (NOT Read_ArrivalTotals(State->Bundles2, State->Bytes2))
            {
                AddError(TEXT("speaker replica missing client-side at mark 2"));
                return false;
            }

            return true;
        }),
        TEXT("mark 2 sampled")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(MarkWindowTicks));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            if (NOT Read_ArrivalTotals(State->Bundles3, State->Bytes3))
            {
                AddError(TEXT("speaker replica missing client-side at mark 3"));
                return false;
            }

            const auto TotalSentBytes = static_cast<uint64>(BurstBundles) * BundleBytes;

            // LogTemp Display (the [VoiceSpike] canary precedent), not AddInfo - AddInfo events
            // don't reach the unattended runner's log, and these numbers ARE the deliverable.
            const auto Report = TArray<FString>{
                FString::Printf(TEXT("[S5] burst: %d bundles x %d B = %llu B queued in one server-side call"),
                    BurstBundles, BundleBytes, TotalSentBytes),
                FString::Printf(TEXT("[S5] mark1 (after %d ticks): %llu bundles / %llu B arrived"),
                    MarkOneTicks, State->Bundles1, State->Bytes1),
                FString::Printf(TEXT("[S5] mark2 (+%d ticks): %llu bundles / %llu B arrived -> window slope %.1f B/tick (%.2f bundles/tick)"),
                    MarkWindowTicks, State->Bundles2, State->Bytes2,
                    static_cast<double>(State->Bytes2 - State->Bytes1) / MarkWindowTicks,
                    static_cast<double>(State->Bundles2 - State->Bundles1) / MarkWindowTicks),
                FString::Printf(TEXT("[S5] mark3 (+%d ticks): %llu bundles / %llu B arrived -> window slope %.1f B/tick (%.2f bundles/tick)"),
                    MarkWindowTicks, State->Bundles3, State->Bytes3,
                    static_cast<double>(State->Bytes3 - State->Bytes2) / MarkWindowTicks,
                    static_cast<double>(State->Bundles3 - State->Bundles2) / MarkWindowTicks),
                State->Bundles3 < BurstBundles
                    ? FString{TEXT("[S5] queue still draining at mark 3 - the window slopes ARE the saturated drain rate")}
                    : FString::Printf(TEXT("[S5] queue fully drained before mark 3 - slopes are a LOWER bound; full burst landed within %d ticks"),
                        MarkOneTicks + 2 * MarkWindowTicks)};

            for (const auto& Line : Report)
            {
                UE_LOG(LogTemp, Display, TEXT("%s"), *Line);
                AddInfo(Line);
            }

            TestTrue(TEXT("the connection delivered part of the burst"), State->Bundles1 > 0);
            TestTrue(TEXT("arrival totals are monotone across marks"),
                State->Bundles2 >= State->Bundles1 && State->Bundles3 >= State->Bundles2);
            TestTrue(TEXT("nothing arrived beyond what was sent"), State->Bundles3 <= BurstBundles);

            return true;
        }),
        TEXT("S5 drain measurement reported")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            FAutomationTestBase::bSuppressLogErrors = false;
            FAutomationTestBase::bSuppressLogWarnings = false;
            return true;
        }),
        TEXT("restore log suppression statics")));

    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
