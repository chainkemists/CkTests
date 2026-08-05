// P4 HybridRadio near/far render STATE (Gate_4 item 4 machine half): the per-recipient distance
// decision with the module hysteresis asymmetry, pinned through the debug seam. Four placements
// of the talker relative to listener B's audio listener, each followed by a delivery on a
// HybridRadio channel (range 500, margin 100):
//
//   1. 300 cm (inside range)            -> near
//   2. 550 cm (inside range + margin)   -> STAYS near  (held by the margin)
//   3. 700 cm (beyond range + margin)   -> far
//   4. 550 cm again                     -> STAYS far   (the asymmetry: re-entry needs < range)
//
// The audible 3D-vs-radio render is [EDITOR-VERIFY] - no audio device exists here; the STATE is
// the machine-assertable half (computed from the owning actor's position by design).
//
// Surface in Session Frontend: Ck.VoiceChat.Net.HybridRenderMode

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "EngineUtils.h"

#include "CkCore/GameplayTag/CkGameplayTag_Utils.h"

#include "CkVoiceChat/Codec/CkVoiceChat_Codec.h"
#include "CkVoiceChat/VoiceChannel/CkVoiceChannel_Utils.h"
#include "CkVoiceChat/VoiceTalker/CkVoiceTalker_Utils.h"

#include "CkTests/Net/CkAutoTest_NetSubject_VoiceChat.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include <GameFramework/PlayerController.h>
#include <GameFramework/PlayerState.h>

// --------------------------------------------------------------------------------------------------------------------

namespace ck_voice_hybrid_render_spec
{
    const auto TalkerALocation = FVector{100.0, 0.0, 0.0};
    const auto ListenerBLocation = FVector{200.0, 0.0, 0.0};

    // Range + margin small enough that every placement is comfortably inside the harness map.
    constexpr auto HybridRangeCm = 500.0f;

    struct FHybridSpecState
    {
        int32 Client0PlayerId = 0;
        uint8 HybridChannelIdx = 255;
        uint16 NextSeq = 1;

        FVector ListenerBAudioLocation = FVector::ZeroVector;
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

    // After act 1 the talker moves - identify its replica by ownership-agnostic uniqueness
    // instead: it is the only subject in B's world that is NOT B's own.
    auto Find_TalkerAReplica(UWorld* InClientB) -> ACk_AutoTest_NetSubject_VoiceChat_UE*
    {
        for (TActorIterator<ACk_AutoTest_NetSubject_VoiceChat_UE> It{InClientB}; It; ++It)
        {
            if (FVector::Dist(It->GetActorLocation(), ListenerBLocation) > 50.0)
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

    auto Make_HybridChannelParams() -> FCk_Fragment_VoiceChannel_ParamsData
    {
        return FCk_Fragment_VoiceChannel_ParamsData{
            UCk_Utils_GameplayTag_UE::ResolveGameplayTag(TEXT("VoiceChat.Channel.TestHybrid"))}
            .Set_SpatializationPolicy(ECk_VoiceChat_SpatializationPolicy::HybridRadio)
            .Set_AudibleRange(HybridRangeCm);
    }

    auto Make_Bundle(uint16 InSeq, uint8 InChannelIdx) -> TArray<uint8>
    {
        auto Frame = TArray<uint8>{};
        Frame.Init(0x42, 60);

        constexpr auto AmplitudeQ8 = uint8{128};
        return ck::voice_chat::codec::Pack_Bundle(
            FCk_VoiceChat_BundleHeader{InSeq, InChannelIdx, AmplitudeQ8}, TArray<TArray<uint8>>{Frame});
    }

    // One placement-then-delivery beat: move the talker to InDistanceCm from B's audio listener
    // (server-side, replicates), let the move land, inject, let the drain evaluate.
    auto Add_PlacementBeat(FAutomationTestBase* InTest,
        const TSharedRef<FHybridSpecState, ESPMode::ThreadSafe>& InState, float InDistanceCm) -> void
    {
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
            FCk_NetAutoTest_ServerAction::CreateLambda([InTest, InState, InDistanceCm](UWorld* InServer) -> void
            {
                // Placement varies per beat - identify the talker as the one subject NOT at B.
                auto* TalkerA = static_cast<ACk_AutoTest_NetSubject_VoiceChat_UE*>(nullptr);

                for (TActorIterator<ACk_AutoTest_NetSubject_VoiceChat_UE> It{InServer}; It; ++It)
                {
                    if (FVector::Dist(It->GetActorLocation(), ListenerBLocation) > 50.0)
                    { TalkerA = *It; }
                }

                if (TalkerA == nullptr)
                {
                    InTest->AddError(TEXT("talker A missing at placement"));
                    return;
                }

                TalkerA->SetActorLocation(InState->ListenerBAudioLocation + FVector{InDistanceCm, 0.0, 0.0});
            })));

        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(20));

        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
            FCk_NetAutoTest_ServerAction::CreateLambda([InTest, InState](UWorld* InServer) -> void
            {
                auto* TalkerA = static_cast<ACk_AutoTest_NetSubject_VoiceChat_UE*>(nullptr);
                for (TActorIterator<ACk_AutoTest_NetSubject_VoiceChat_UE> It{InServer}; It; ++It)
                {
                    if (FVector::Dist(It->GetActorLocation(), ListenerBLocation) > 50.0)
                    { TalkerA = *It; }
                }

                auto* Client0Controller = Find_ControllerByPlayerId(InServer, InState->Client0PlayerId);

                if (TalkerA == nullptr || Client0Controller == nullptr || Client0Controller->PlayerState == nullptr)
                {
                    InTest->AddError(TEXT("talker A or client 0's PlayerState missing at inject"));
                    return;
                }

                UCk_Utils_VoiceTalker_UE::Debug_InjectInboundBundle(
                    TalkerA->_TestTalker, Make_Bundle(InState->NextSeq++, InState->HybridChannelIdx),
                    Client0Controller->PlayerState);
            })));

        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(30));
    }

    auto Add_NearAssert(FAutomationTestBase* InTest, bool InExpectedNear, const TCHAR* InWhat) -> void
    {
        const auto What = FString{InWhat};

        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(InTest,
            FCk_NetAutoTest_Assertion::CreateLambda([InTest, InExpectedNear, What]() -> bool
            {
                auto* ClientB = ck::auto_test::net::Get_ClientWorld(1);
                auto* ClientTalkerA = ClientB != nullptr ? Find_TalkerAReplica(ClientB) : nullptr;

                if (ClientTalkerA == nullptr || ck::Is_NOT_Valid(ClientTalkerA->_TestTalker))
                {
                    InTest->AddError(TEXT("talker-A replica missing in client B's world at near-assert"));
                    return false;
                }

                const auto RenderNear = UCk_Utils_VoiceTalker_UE::Debug_Get_HybridRenderNear(
                    ClientTalkerA->_TestTalker);

                InTest->TestTrue(What + TEXT(": the near/far state was evaluated"), RenderNear.IsSet());

                if (RenderNear.IsSet())
                { InTest->TestEqual(What + TEXT(": near/far state"), RenderNear.GetValue(), InExpectedNear); }

                return true;
            }),
            *What));
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkVoiceChatNet_HybridRenderMode,
    "Ck.VoiceChat.Net.HybridRenderMode",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkVoiceChatNet_HybridRenderMode::RunTest(const FString& Parameters)
{
    using namespace ck_voice_hybrid_render_spec;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};
    const auto State = MakeShared<FHybridSpecState, ESPMode::ThreadSafe>();

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

    // Symmetric composition of the hybrid channel on every world (the control-plane contract:
    // NotReady until every named channel composes locally) - each world adds the SAME-tag
    // channel to its talker-A subject entity.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InServer) -> void
        {
            auto* TalkerA = Find_SubjectNear(InServer, TalkerALocation);
            if (TalkerA == nullptr || ck::Is_NOT_Valid(TalkerA->_TestTalker))
            {
                AddError(TEXT("talker A missing at hybrid channel composition (server)"));
                return;
            }

            auto SubjectEntity = TalkerA->_TestTalker.ConvertToHandle();
            auto HybridChannel = UCk_Utils_VoiceChannel_UE::Add(SubjectEntity, Make_HybridChannelParams());

            UCk_Utils_VoiceChannel_UE::Request_Join(HybridChannel,
                FCk_Request_VoiceChannel_Join{TalkerA->_TestTalker}, {});

            auto* ListenerB = Find_SubjectNear(InServer, ListenerBLocation);
            if (ListenerB == nullptr)
            {
                AddError(TEXT("listener B missing at hybrid join"));
                return;
            }

            UCk_Utils_VoiceChannel_UE::Request_Join(HybridChannel,
                FCk_Request_VoiceChannel_Join{ListenerB->_TestTalker}, {});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(0,
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InClient) -> void
        {
            auto* ClientTalkerA = Find_SubjectNear(InClient, TalkerALocation);
            if (ClientTalkerA == nullptr || ck::Is_NOT_Valid(ClientTalkerA->_TestTalker))
            {
                AddError(TEXT("talker-A replica missing in client 0's world at hybrid composition"));
                return;
            }

            auto SubjectEntity = ClientTalkerA->_TestTalker.ConvertToHandle();
            UCk_Utils_VoiceChannel_UE::Add(SubjectEntity, Make_HybridChannelParams());
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(1,
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InClient) -> void
        {
            auto* ClientTalkerA = Find_SubjectNear(InClient, TalkerALocation);
            if (ClientTalkerA == nullptr || ck::Is_NOT_Valid(ClientTalkerA->_TestTalker))
            {
                AddError(TEXT("talker-A replica missing in client B's world at hybrid composition"));
                return;
            }

            auto SubjectEntity = ClientTalkerA->_TestTalker.ConvertToHandle();
            UCk_Utils_VoiceChannel_UE::Add(SubjectEntity, Make_HybridChannelParams());

            // B's audio listener anchors every placement below - read it where it lives.
            auto* LocalController = InClient->GetFirstPlayerController();
            if (LocalController == nullptr)
            {
                AddError(TEXT("client B has no local PlayerController"));
                return;
            }

            auto Front = FVector{};
            auto Right = FVector{};
            LocalController->GetAudioListenerPosition(State->ListenerBAudioLocation, Front, Right);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(40));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InServer) -> void
        {
            auto* TalkerA = Find_SubjectNear(InServer, TalkerALocation);
            if (TalkerA == nullptr)
            {
                AddError(TEXT("talker A missing at idx read"));
                return;
            }

            const auto HybridChannel = UCk_Utils_VoiceChannel_UE::TryGet_VoiceChannel(
                TalkerA->_TestTalker,
                UCk_Utils_GameplayTag_UE::ResolveGameplayTag(TEXT("VoiceChat.Channel.TestHybrid")));

            if (ck::Is_NOT_Valid(HybridChannel))
            {
                AddError(TEXT("hybrid channel did not compose on the server"));
                return;
            }

            State->HybridChannelIdx = UCk_Utils_VoiceChannel_UE::Get_ChannelIdx(HybridChannel);

            if (State->HybridChannelIdx == 255)
            { AddError(TEXT("hybrid channel has no assigned idx")); }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(20));

    // The four beats: near, held-near, far, held-far.
    Add_PlacementBeat(this, State, 300.0f);
    Add_NearAssert(this, true, TEXT("inside range (300)"));

    Add_PlacementBeat(this, State, 550.0f);
    Add_NearAssert(this, true, TEXT("inside range+margin while near (550)"));

    Add_PlacementBeat(this, State, 700.0f);
    Add_NearAssert(this, false, TEXT("beyond range+margin (700)"));

    Add_PlacementBeat(this, State, 550.0f);
    Add_NearAssert(this, false, TEXT("re-entry into the margin band stays far (550)"));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
