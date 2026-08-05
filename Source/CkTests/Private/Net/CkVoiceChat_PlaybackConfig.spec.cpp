// P4 playback-config seams (Gate_4 items 2/6/7 machine halves), one flow:
//
//   1. Selection: bundles delivered on a channel set the recipient-side talker's
//      _PlaybackConfigChannel to THAT channel (asserted by wire idx through the debug seam).
//   2. Amplitude release: while bundles arrive the header amplitude mirrors (>0); once the
//      stream idles past the sender's stale-drop age the remote amplitude releases to ZERO -
//      a remote talker never reads as speaking forever.
//   3. EndPlay prune: after the talker's listener-mute and forwards have populated the
//      world-scoped authority maps (entries > 0 proven first), destroying the talker sweeps
//      its entries to ZERO.
//
// The render application half (attenuation/effect chain audibly applied) is [EDITOR-VERIFY] -
// no audio device exists here.
//
// Surface in Session Frontend: Ck.VoiceChat.Net.PlaybackConfig

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "EngineUtils.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"

#include "CkVoiceChat/Codec/CkVoiceChat_Codec.h"
#include "CkVoiceChat/VoiceChannel/CkVoiceChannel_Utils.h"
#include "CkVoiceChat/VoiceListener/CkVoiceListener_Utils.h"
#include "CkVoiceChat/VoiceTalker/CkVoiceTalker_Utils.h"

#include "CkTests/Net/CkAutoTest_NetSubject_VoiceChat.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include <GameFramework/PlayerController.h>
#include <GameFramework/PlayerState.h>

// --------------------------------------------------------------------------------------------------------------------

namespace ck_voice_playback_config_spec
{
    const auto TalkerALocation = FVector{100.0, 0.0, 0.0};
    const auto ListenerBLocation = FVector{200.0, 0.0, 0.0};

    struct FPlaybackConfigSpecState
    {
        int32 Client0PlayerId = 0;
        uint8 ChannelIdx = 255;
        uint16 NextSeq = 1;

        // Listener B's server-side talker anchors the post-destroy map reads: talker A's own
        // handle is a tombstone after its destroy and cannot anchor (nor safely key) a lookup.
        FCk_Handle_VoiceTalker ServerAnchorB;
        FCk_Handle_VoiceListener ClientBListener;
    };

    auto Find_SubjectNear(UWorld* InWorld, const FVector& InLocation) -> ACk_AutoTest_NetSubject_VoiceChat_UE*
    {
        for (TActorIterator<ACk_AutoTest_NetSubject_VoiceChat_UE> It{InWorld}; It; ++It)
        {
            if (FVector::Dist(It->GetActorLocation(), InLocation) < 50.0)
            { return *It; }
        }

        return nullptr;
    }

    auto Find_ControllerByPlayerId(UWorld* InServer, int32 InPlayerId) -> APlayerController*
    {
        for (auto It = InServer->GetPlayerControllerIterator(); It; ++It)
        {
            if (auto* Controller = It->Get();
                Controller != nullptr && Controller->PlayerState != nullptr &&
                Controller->PlayerState->GetPlayerId() == InPlayerId)
            { return Controller; }
        }

        return nullptr;
    }

    auto Make_Bundle(uint16 InSeq, uint8 InChannelIdx) -> TArray<uint8>
    {
        auto Frame = TArray<uint8>{};
        Frame.Init(0x42, 60);

        constexpr auto AmplitudeQ8 = uint8{128};
        return ck::voice_chat::codec::Pack_Bundle(
            FCk_VoiceChat_BundleHeader{InSeq, InChannelIdx, AmplitudeQ8}, TArray<TArray<uint8>>{Frame});
    }

    auto Inject_FromTalkerA(FAutomationTestBase* InTest, UWorld* InServer,
        const TSharedRef<FPlaybackConfigSpecState, ESPMode::ThreadSafe>& InState) -> void
    {
        auto* TalkerA = Find_SubjectNear(InServer, TalkerALocation);
        auto* Client0Controller = Find_ControllerByPlayerId(InServer, InState->Client0PlayerId);

        if (TalkerA == nullptr || Client0Controller == nullptr || Client0Controller->PlayerState == nullptr)
        {
            InTest->AddError(TEXT("talker A or client 0's PlayerState missing at inject"));
            return;
        }

        UCk_Utils_VoiceTalker_UE::Debug_InjectInboundBundle(
            TalkerA->_TestTalker, Make_Bundle(InState->NextSeq++, InState->ChannelIdx),
            Client0Controller->PlayerState);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkVoiceChatNet_PlaybackConfig,
    "Ck.VoiceChat.Net.PlaybackConfig",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkVoiceChatNet_PlaybackConfig::RunTest(const FString& Parameters)
{
    using namespace ck_voice_playback_config_spec;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};
    const auto State = MakeShared<FPlaybackConfigSpecState, ESPMode::ThreadSafe>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(3, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(3, 30.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(30));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(0,
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InClient) -> void
        {
            const auto* LocalController = InClient->GetFirstPlayerController();
            if (LocalController == nullptr || LocalController->PlayerState == nullptr)
            {
                AddError(TEXT("client 0 has no local PlayerState"));
                return;
            }

            State->Client0PlayerId = LocalController->PlayerState->GetPlayerId();
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InServer) -> void
        {
            auto* Client0Controller = Find_ControllerByPlayerId(InServer, State->Client0PlayerId);
            auto* Client1Controller = static_cast<APlayerController*>(nullptr);
            for (auto It = InServer->GetPlayerControllerIterator(); It; ++It)
            {
                if (auto* Controller = It->Get();
                    Controller != nullptr && NOT Controller->IsLocalController() && Controller != Client0Controller)
                { Client1Controller = Controller; }
            }

            if (Client0Controller == nullptr || Client1Controller == nullptr)
            {
                AddError(TEXT("could not resolve both remote PlayerControllers on the server"));
                return;
            }

            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;

            SpawnInfo.Owner = Client0Controller;
            if (InServer->SpawnActor<ACk_AutoTest_NetSubject_VoiceChat_UE>(
                    ACk_AutoTest_NetSubject_VoiceChat_UE::StaticClass(), FTransform{TalkerALocation}, SpawnInfo) == nullptr)
            { AddError(TEXT("spawn of the talker-A subject failed")); }

            SpawnInfo.Owner = Client1Controller;
            if (InServer->SpawnActor<ACk_AutoTest_NetSubject_VoiceChat_UE>(
                    ACk_AutoTest_NetSubject_VoiceChat_UE::StaticClass(), FTransform{ListenerBLocation}, SpawnInfo) == nullptr)
            { AddError(TEXT("spawn of the listener-B subject failed")); }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(40));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InServer) -> void
        {
            auto* TalkerA = Find_SubjectNear(InServer, TalkerALocation);
            auto* ListenerB = Find_SubjectNear(InServer, ListenerBLocation);

            if (TalkerA == nullptr || ListenerB == nullptr)
            {
                AddError(TEXT("subjects missing on the server at join time"));
                return;
            }

            State->ServerAnchorB = ListenerB->_TestTalker;

            UCk_Utils_VoiceChannel_UE::Request_Join(TalkerA->_TestChannel,
                FCk_Request_VoiceChannel_Join{TalkerA->_TestTalker}, {});
            UCk_Utils_VoiceChannel_UE::Request_Join(TalkerA->_TestChannel,
                FCk_Request_VoiceChannel_Join{ListenerB->_TestTalker}, {});

            State->ChannelIdx = UCk_Utils_VoiceChannel_UE::Get_ChannelIdx(TalkerA->_TestChannel);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(30));

    // Act 1 - selection + amplitude mirror while the stream flows.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InServer) -> void
        {
            if (State->ChannelIdx == 255)
            {
                AddError(TEXT("channel has no assigned idx - control plane did not settle"));
                return;
            }

            Inject_FromTalkerA(this, InServer, State);
        })));

    // The mirror is transient BY DESIGN (it releases 0.15s after the last arrival), so a fixed
    // settle races it on slow-tick hosts - poll for the >0 window instead (the exit sweep's
    // first run caught exactly that race).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            auto* ClientB = ck::auto_test::net::Get_ClientWorld(1);
            auto* ClientTalkerA = ClientB != nullptr ? Find_SubjectNear(ClientB, TalkerALocation) : nullptr;

            return ClientTalkerA != nullptr && ck::IsValid(ClientTalkerA->_TestTalker) &&
                UCk_Utils_VoiceTalker_UE::Get_CurrentAmplitude(ClientTalkerA->_TestTalker) > 0.0f;
        }),
        10.0,
        TEXT("amplitude mirrors the header while the stream flows")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            auto* ClientB = ck::auto_test::net::Get_ClientWorld(1);
            auto* ClientTalkerA = ClientB != nullptr ? Find_SubjectNear(ClientB, TalkerALocation) : nullptr;

            if (ClientTalkerA == nullptr || ck::Is_NOT_Valid(ClientTalkerA->_TestTalker))
            {
                AddError(TEXT("talker-A replica missing in client B's world at act 1"));
                return false;
            }

            const auto ConfigChannel = UCk_Utils_VoiceTalker_UE::Debug_Get_PlaybackConfigChannel(
                ClientTalkerA->_TestTalker);

            TestTrue(TEXT("selection: the delivering channel was selected"), ck::IsValid(ConfigChannel));

            if (ck::IsValid(ConfigChannel))
            {
                TestEqual(TEXT("selection: the selected channel carries the delivering wire idx"),
                    UCk_Utils_VoiceChannel_UE::Get_ChannelIdx(ConfigChannel), State->ChannelIdx);
            }

            return true;
        }),
        TEXT("selection")));

    // Act 2 - the stream idles past the sender's stale-drop age: amplitude releases to zero,
    // the selection persists (config is sticky; silence does not deselect).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            auto* ClientB = ck::auto_test::net::Get_ClientWorld(1);
            auto* ClientTalkerA = ClientB != nullptr ? Find_SubjectNear(ClientB, TalkerALocation) : nullptr;

            return ClientTalkerA != nullptr && ck::IsValid(ClientTalkerA->_TestTalker) &&
                UCk_Utils_VoiceTalker_UE::Get_CurrentAmplitude(ClientTalkerA->_TestTalker) == 0.0f;
        }),
        10.0,
        TEXT("amplitude releases to zero after the spurt")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* ClientB = ck::auto_test::net::Get_ClientWorld(1);
            auto* ClientTalkerA = ClientB != nullptr ? Find_SubjectNear(ClientB, TalkerALocation) : nullptr;

            if (ClientTalkerA == nullptr || ck::Is_NOT_Valid(ClientTalkerA->_TestTalker))
            {
                AddError(TEXT("talker-A replica missing in client B's world at act 2"));
                return false;
            }

            TestTrue(TEXT("the selection persists through silence"),
                ck::IsValid(UCk_Utils_VoiceTalker_UE::Debug_Get_PlaybackConfigChannel(
                    ClientTalkerA->_TestTalker)));

            return true;
        }),
        TEXT("sticky selection")));

    // Act 3 - prune: B's listener-mute populates the mute matrix, the earlier forwards populated
    // the serve history; both proven non-empty for talker A, then the talker's destroy sweeps
    // its entries to zero.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(1,
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InClient) -> void
        {
            auto* ClientTalkerA = Find_SubjectNear(InClient, TalkerALocation);
            if (ClientTalkerA == nullptr || ck::Is_NOT_Valid(ClientTalkerA->_TestTalker))
            {
                AddError(TEXT("talker-A replica missing in client B's world at act 3 mute"));
                return;
            }

            auto TransientEntity = UCk_Utils_EntityLifetime_UE::Get_TransientEntity(ClientTalkerA->_TestTalker);
            auto EarsEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(TransientEntity);
            State->ClientBListener = UCk_Utils_VoiceListener_UE::Add(EarsEntity);

            UCk_Utils_VoiceListener_UE::Request_MuteTalker(State->ClientBListener,
                FCk_Request_VoiceListener_MuteTalker{ClientTalkerA->_TestTalker}, {});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(30));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            if (ck::Is_NOT_Valid(State->ServerAnchorB))
            {
                AddError(TEXT("server anchor handle was never captured"));
                return false;
            }

            TestTrue(TEXT("the authority maps track talker A before its destroy (prune precondition)"),
                UCk_Utils_VoiceTalker_UE::Debug_Get_WorldMapTalkerEntryCount(State->ServerAnchorB) > 0);
            return true;
        }),
        TEXT("maps populated pre-destroy")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InServer) -> void
        {
            auto* TalkerA = Find_SubjectNear(InServer, TalkerALocation);
            if (TalkerA == nullptr)
            {
                AddError(TEXT("talker A missing at destroy"));
                return;
            }

            TalkerA->Destroy();
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(30));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            TestEqual(TEXT("the EndPlay sweep pruned every entry naming the destroyed talker"),
                UCk_Utils_VoiceTalker_UE::Debug_Get_WorldMapTalkerEntryCount(State->ServerAnchorB), 0);
            return true;
        }),
        TEXT("maps pruned post-destroy")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
