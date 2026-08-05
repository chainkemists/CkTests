// P3 listener-mute gate: the mute is a PRIVACY property - after a client mutes a talker, that
// talker's audio stops ARRIVING at the muting client (the server excludes the pair from the
// send-set; nothing to discard locally). Unmuting restores the stream, proving the exclusion -
// not a broken pipe - was the cause. Three transmit cycles against the routing-spec topology:
//   1. baseline: decoded bytes grow;  2. muted: decoded bytes frozen;  3. unmuted: grow again.
//
// Surface in Session Frontend: Ck.VoiceChat.Net.ListenerMute_StopsForwarding

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "EngineUtils.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkVoiceChat/Capture/CkVoiceChat_CaptureSource.h"
#include "CkVoiceChat/VoiceChannel/CkVoiceChannel_Utils.h"
#include "CkVoiceChat/VoiceListener/CkVoiceListener_Utils.h"
#include "CkVoiceChat/VoiceTalker/CkVoiceTalker_Utils.h"

#include "CkTests/Net/CkAutoTest_NetSubject_VoiceChat.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include "Misc/ConfigCacheIni.h"
#include "Modules/ModuleManager.h"
#include "VoiceModule.h"

#include <GameFramework/PlayerController.h>

// --------------------------------------------------------------------------------------------------------------------

namespace ck_voice_mute_spec
{
    constexpr auto SampleRate = 48000;

    struct FMuteSpecState
    {
        FCk_Handle_VoiceListener ClientListener;

        int32 DecodedBytesAfterBaseline = 0;
        int32 DecodedBytesAfterMutedSpurt = 0;

        uint64 ArrivalsAfterBaseline = 0;
        uint64 ArrivalsAfterMutedSpurt = 0;

        bool HadOriginalVoiceKey = false;
        bool OriginalVoiceEnabled = false;
    };

    auto EnableEngineVoice(FMuteSpecState& InState) -> void
    {
        InState.HadOriginalVoiceKey = GConfig->GetBool(TEXT("Voice"), TEXT("bEnabled"), InState.OriginalVoiceEnabled, GEngineIni);
        GConfig->SetBool(TEXT("Voice"), TEXT("bEnabled"), true, GEngineIni);

        if (FModuleManager::Get().IsModuleLoaded(TEXT("Voice")) && NOT FVoiceModule::Get().IsVoiceEnabled())
        {
            FModuleManager::Get().UnloadModule(TEXT("Voice"));
        }
    }

    auto RestoreEngineVoice(const FMuteSpecState& InState) -> void
    {
        if (InState.HadOriginalVoiceKey)
        { GConfig->SetBool(TEXT("Voice"), TEXT("bEnabled"), InState.OriginalVoiceEnabled, GEngineIni); }
        else
        { GConfig->RemoveKey(TEXT("Voice"), TEXT("bEnabled"), GEngineIni); }
    }

    auto Find_Subject(UWorld* InWorld, bool InServerOwned) -> ACk_AutoTest_NetSubject_VoiceChat_UE*
    {
        for (TActorIterator<ACk_AutoTest_NetSubject_VoiceChat_UE> It{InWorld}; It; ++It)
        {
            const auto IsServerOwned = It->GetOwner() == nullptr;
            if (IsServerOwned == InServerOwned)
            { return *It; }
        }

        return nullptr;
    }

    auto Find_RemotePlayerController(UWorld* InServer) -> APlayerController*
    {
        for (auto It = InServer->GetPlayerControllerIterator(); It; ++It)
        {
            if (auto* Controller = It->Get();
                Controller != nullptr && NOT Controller->IsLocalController())
            { return Controller; }
        }

        return nullptr;
    }

    auto Transmit_Spurt(FAutomationTestBase* InTest, UWorld* InServer) -> void
    {
        auto* SubjectA = Find_Subject(InServer, true);
        if (SubjectA == nullptr || ck::Is_NOT_Valid(SubjectA->_TestTalker))
        {
            InTest->AddError(TEXT("server-side subject A missing at transmit time"));
            return;
        }

        const auto FakeSource = MakeShared<FCk_VoiceChat_CaptureSource_Fake>(SampleRate);
        FakeSource->Enqueue_Silence(FCk_Time{0.2f});
        FakeSource->Enqueue_Sine(FCk_Time{0.8f}, 0.4f, 300.0f);
        FakeSource->Enqueue_Silence(FCk_Time{0.5f});

        UCk_Utils_VoiceTalker_UE::Debug_InjectCaptureSource(SubjectA->_TestTalker, FakeSource);
        UCk_Utils_VoiceTalker_UE::Request_StartTransmit(SubjectA->_TestTalker, {}, {});
    }

    auto Stop_Transmit(UWorld* InServer) -> void
    {
        if (auto* SubjectA = Find_Subject(InServer, true); SubjectA != nullptr)
        {
            UCk_Utils_VoiceTalker_UE::Request_StopTransmit(SubjectA->_TestTalker, {});
        }
    }

    auto Get_ClientDecodedBytes(FAutomationTestBase* InTest) -> int32
    {
        auto* Client = ck::auto_test::net::Get_ClientWorld(0);
        auto* ClientSubjectA = Client != nullptr ? Find_Subject(Client, true) : nullptr;
        if (ClientSubjectA == nullptr || ck::Is_NOT_Valid(ClientSubjectA->_TestTalker))
        {
            InTest->AddError(TEXT("client-side subject A missing at read time"));
            return -1;
        }

        return UCk_Utils_VoiceTalker_UE::Debug_Get_LoopbackDecodedPcm(ClientSubjectA->_TestTalker).Num();
    }

    // The RPC-boundary arrival counter - counted BEFORE the local defense-in-depth mute gate, so
    // it distinguishes the server-side exclusion (bundles stop ARRIVING) from the local drop
    // (bundles arrive, playback stays silent). The decoded-bytes asserts alone cannot tell the
    // two apart - this counter is what proves the privacy property (Gate-3 audit condition 1).
    auto Get_ClientArrivedBundles(FAutomationTestBase* InTest) -> uint64
    {
        auto* Client = ck::auto_test::net::Get_ClientWorld(0);
        auto* ClientSubjectA = Client != nullptr ? Find_Subject(Client, true) : nullptr;
        if (ClientSubjectA == nullptr || ck::Is_NOT_Valid(ClientSubjectA->_TestTalker))
        {
            InTest->AddError(TEXT("client-side subject A missing at arrival-read time"));
            return 0;
        }

        return UCk_Utils_VoiceTalker_UE::Debug_Get_ReceiveArrivedBundles(ClientSubjectA->_TestTalker);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkVoiceChatNet_ListenerMuteStopsForwarding,
    "Ck.VoiceChat.Net.ListenerMute_StopsForwarding",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkVoiceChatNet_ListenerMuteStopsForwarding::RunTest(const FString& Parameters)
{
    using namespace ck_voice_mute_spec;

    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto SpurtTicks = 140;
    constexpr auto SettleTicks = 60;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};
    const auto State = MakeShared<FMuteSpecState, ESPMode::ThreadSafe>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InServer) -> void
        {
            EnableEngineVoice(*State);

            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;

            if (InServer->SpawnActor<ACk_AutoTest_NetSubject_VoiceChat_UE>(
                    ACk_AutoTest_NetSubject_VoiceChat_UE::StaticClass(), FTransform::Identity, SpawnInfo) == nullptr)
            { AddError(TEXT("server-side SpawnActor of subject A returned null")); }

            auto* RemoteController = Find_RemotePlayerController(InServer);
            if (RemoteController == nullptr)
            {
                AddError(TEXT("no remote (client) PlayerController found on the server"));
                return;
            }

            SpawnInfo.Owner = RemoteController;
            if (InServer->SpawnActor<ACk_AutoTest_NetSubject_VoiceChat_UE>(
                    ACk_AutoTest_NetSubject_VoiceChat_UE::StaticClass(), FTransform::Identity, SpawnInfo) == nullptr)
            { AddError(TEXT("server-side SpawnActor of subject B returned null")); }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(40));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* SubjectA = Find_Subject(InServer, true);
            auto* SubjectB = Find_Subject(InServer, false);
            if (SubjectA == nullptr || SubjectB == nullptr)
            {
                AddError(TEXT("subjects missing on the server at join time"));
                return;
            }

            UCk_Utils_VoiceChannel_UE::Request_Join(SubjectA->_TestChannel,
                FCk_Request_VoiceChannel_Join{SubjectA->_TestTalker}, {});
            UCk_Utils_VoiceChannel_UE::Request_Join(SubjectA->_TestChannel,
                FCk_Request_VoiceChannel_Join{SubjectB->_TestTalker}, {});

            Transmit_Spurt(this, InServer);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(SpurtTicks));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void { Stop_Transmit(InServer); })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(SettleTicks));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            State->DecodedBytesAfterBaseline = Get_ClientDecodedBytes(this);
            State->ArrivalsAfterBaseline = Get_ClientArrivedBundles(this);

            TestTrue(TEXT("baseline: the client decoded talker A's voice before any mute"),
                State->DecodedBytesAfterBaseline > 0);
            TestTrue(TEXT("baseline: bundles ARRIVED at the RPC boundary before any mute"),
                State->ArrivalsAfterBaseline > 0);

            return true;
        }),
        TEXT("baseline spurt decoded")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(0,
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InClient) -> void
        {
            auto* ClientSubjectA = Find_Subject(InClient, true);
            if (ClientSubjectA == nullptr || ck::Is_NOT_Valid(ClientSubjectA->_TestTalker))
            {
                AddError(TEXT("client-side subject A missing at mute time"));
                return;
            }

            auto TransientEntity = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InClient);
            auto EarsEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(TransientEntity);
            State->ClientListener = UCk_Utils_VoiceListener_UE::Add(EarsEntity);

            UCk_Utils_VoiceListener_UE::Request_MuteTalker(State->ClientListener,
                FCk_Request_VoiceListener_MuteTalker{ClientSubjectA->_TestTalker}, {});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(30));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            Transmit_Spurt(this, InServer);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(SpurtTicks));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void { Stop_Transmit(InServer); })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(SettleTicks));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            State->DecodedBytesAfterMutedSpurt = Get_ClientDecodedBytes(this);
            State->ArrivalsAfterMutedSpurt = Get_ClientArrivedBundles(this);

            TestEqual(TEXT("muted: playback stayed silent (decoded bytes frozen)"),
                State->DecodedBytesAfterMutedSpurt, State->DecodedBytesAfterBaseline);
            TestEqual(TEXT("muted: the second spurt never ARRIVED at the RPC boundary - the server stopped forwarding, not just the local gate"),
                State->ArrivalsAfterMutedSpurt, State->ArrivalsAfterBaseline);

            return true;
        }),
        TEXT("mute stops forwarding")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(0,
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InClient) -> void
        {
            auto* ClientSubjectA = Find_Subject(InClient, true);
            if (ClientSubjectA == nullptr || ck::Is_NOT_Valid(State->ClientListener))
            {
                AddError(TEXT("client-side subject A / listener missing at unmute time"));
                return;
            }

            UCk_Utils_VoiceListener_UE::Request_UnmuteTalker(State->ClientListener,
                FCk_Request_VoiceListener_UnmuteTalker{ClientSubjectA->_TestTalker}, {});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(30));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            Transmit_Spurt(this, InServer);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(SpurtTicks));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void { Stop_Transmit(InServer); })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(SettleTicks));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            RestoreEngineVoice(*State);

            TestTrue(TEXT("unmuted: the third spurt decodes again (the exclusion was the cause, not a broken pipe)"),
                Get_ClientDecodedBytes(this) > State->DecodedBytesAfterMutedSpurt);
            TestTrue(TEXT("unmuted: bundles ARRIVE again at the RPC boundary"),
                Get_ClientArrivedBundles(this) > State->ArrivalsAfterMutedSpurt);

            return true;
        }),
        TEXT("unmute restores the stream")));

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
