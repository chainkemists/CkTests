// P4 moderation matrix (Gate_4 work item 5): the moderation axes composed, each proven by
// arrival-counter deltas at the recipients' RPC boundary with differential controls - a frozen
// counter next to a growing one is the gate, not the harness:
//
//   1. Baseline: member talker delivers to BOTH listeners (positive control for every act).
//   2. CanTalk=Disable on the talker - NOBODY receives; re-enable restores delivery.
//   3. CanHear=Disable on listener B - B freezes while C keeps growing; re-enable restores B.
//   4. Server-mute - nobody receives.
//   5. Composition, direction 1: listener B ALSO mutes the talker locally, then the server
//      UNMUTES - C resumes, B stays frozen (the listener exclusion holds on its own).
//   6. Composition, direction 2: B unmutes - B resumes (both moderation layers now lifted).
//
// Server-mute-survives-leave/rejoin is pinned by the local membership spec since P3
// (Ck.VoiceChat.Channel.MembershipAndIdx) and is deliberately not duplicated here.
//
// Surface in Session Frontend: Ck.VoiceChat.Net.ModerationMatrix

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

namespace ck_voice_moderation_spec
{
    const auto TalkerALocation = FVector{100.0, 0.0, 0.0};
    const auto ListenerBLocation = FVector{200.0, 0.0, 0.0};
    const auto ListenerCLocation = FVector{300.0, 0.0, 0.0};

    struct FModerationSpecState
    {
        int32 Client0PlayerId = 0;
        uint8 ChannelIdx = 255;
        uint16 NextSeq = 1;

        uint64 ArrivalsAtB = 0;
        uint64 ArrivalsAtC = 0;

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

    auto Read_Arrivals(UWorld* InWorld, const FVector& InSubjectLocation, uint64& OutArrivals) -> bool
    {
        auto* Subject = Find_SubjectNear(InWorld, InSubjectLocation);

        if (Subject == nullptr || ck::Is_NOT_Valid(Subject->_TestTalker))
        { return false; }

        OutArrivals = UCk_Utils_VoiceTalker_UE::Debug_Get_ReceiveArrivedBundles(Subject->_TestTalker);
        return true;
    }

    // Every act injects through the identical seam: talker A's bundle, correct sender, valid idx.
    // The moderation state under test is the ONLY variable between acts.
    auto Inject_FromTalkerA(FAutomationTestBase* InTest, UWorld* InServer,
        const TSharedRef<FModerationSpecState, ESPMode::ThreadSafe>& InState) -> void
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

    auto Snapshot_Arrivals(FAutomationTestBase* InTest,
        const TSharedRef<FModerationSpecState, ESPMode::ThreadSafe>& InState) -> bool
    {
        auto* ClientB = ck::auto_test::net::Get_ClientWorld(1);
        auto* ClientC = ck::auto_test::net::Get_ClientWorld(2);

        if (ClientB == nullptr || NOT Read_Arrivals(ClientB, TalkerALocation, InState->ArrivalsAtB))
        {
            InTest->AddError(TEXT("talker-A replica missing in client B's world at snapshot"));
            return false;
        }

        if (ClientC == nullptr || NOT Read_Arrivals(ClientC, TalkerALocation, InState->ArrivalsAtC))
        {
            InTest->AddError(TEXT("talker-A replica missing in client C's world at snapshot"));
            return false;
        }

        return true;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkVoiceChatNet_ModerationMatrix,
    "Ck.VoiceChat.Net.ModerationMatrix",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkVoiceChatNet_ModerationMatrix::RunTest(const FString& Parameters)
{
    using namespace ck_voice_moderation_spec;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};
    const auto State = MakeShared<FModerationSpecState, ESPMode::ThreadSafe>();

    // 4 PIE instances = listen server + THREE remote clients (talker-A owner, listener B,
    // listener C) - the count is total instances, not remote clients.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(4, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(4, 30.0f));

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
            auto RemoteControllers = TArray<APlayerController*>{};
            for (auto It = InServer->GetPlayerControllerIterator(); It; ++It)
            {
                if (auto* Controller = It->Get();
                    Controller != nullptr && NOT Controller->IsLocalController() && Controller != Client0Controller)
                { RemoteControllers.Add(Controller); }
            }

            if (Client0Controller == nullptr || RemoteControllers.Num() < 2)
            {
                AddError(TEXT("could not resolve all three remote PlayerControllers on the server"));
                return;
            }

            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;

            SpawnInfo.Owner = Client0Controller;
            if (InServer->SpawnActor<ACk_AutoTest_NetSubject_VoiceChat_UE>(
                    ACk_AutoTest_NetSubject_VoiceChat_UE::StaticClass(), FTransform{TalkerALocation}, SpawnInfo) == nullptr)
            { AddError(TEXT("spawn of the talker-A subject failed")); }

            SpawnInfo.Owner = RemoteControllers[0];
            if (InServer->SpawnActor<ACk_AutoTest_NetSubject_VoiceChat_UE>(
                    ACk_AutoTest_NetSubject_VoiceChat_UE::StaticClass(), FTransform{ListenerBLocation}, SpawnInfo) == nullptr)
            { AddError(TEXT("spawn of the listener-B subject failed")); }

            SpawnInfo.Owner = RemoteControllers[1];
            if (InServer->SpawnActor<ACk_AutoTest_NetSubject_VoiceChat_UE>(
                    ACk_AutoTest_NetSubject_VoiceChat_UE::StaticClass(), FTransform{ListenerCLocation}, SpawnInfo) == nullptr)
            { AddError(TEXT("spawn of the listener-C subject failed")); }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(40));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InServer) -> void
        {
            auto* TalkerA = Find_SubjectNear(InServer, TalkerALocation);
            auto* ListenerB = Find_SubjectNear(InServer, ListenerBLocation);
            auto* ListenerC = Find_SubjectNear(InServer, ListenerCLocation);

            if (TalkerA == nullptr || ListenerB == nullptr || ListenerC == nullptr)
            {
                AddError(TEXT("subjects missing on the server at join time"));
                return;
            }

            UCk_Utils_VoiceChannel_UE::Request_Join(TalkerA->_TestChannel,
                FCk_Request_VoiceChannel_Join{TalkerA->_TestTalker}, {});
            UCk_Utils_VoiceChannel_UE::Request_Join(TalkerA->_TestChannel,
                FCk_Request_VoiceChannel_Join{ListenerB->_TestTalker}, {});
            UCk_Utils_VoiceChannel_UE::Request_Join(TalkerA->_TestChannel,
                FCk_Request_VoiceChannel_Join{ListenerC->_TestTalker}, {});

            State->ChannelIdx = UCk_Utils_VoiceChannel_UE::Get_ChannelIdx(TalkerA->_TestChannel);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(30));

    // Listener B's local ears exist from the start; they mute nothing until act 5.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(1,
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InClient) -> void
        {
            auto* AnySubject = Find_SubjectNear(InClient, TalkerALocation);
            if (AnySubject == nullptr || ck::Is_NOT_Valid(AnySubject->_TestTalker))
            {
                AddError(TEXT("talker-A replica missing in client B's world at ears setup"));
                return;
            }

            auto TransientEntity = UCk_Utils_EntityLifetime_UE::Get_TransientEntity(AnySubject->_TestTalker);
            auto EarsEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(TransientEntity);
            State->ClientBListener = UCk_Utils_VoiceListener_UE::Add(EarsEntity);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(20));

    // Act 1 - baseline: delivery to BOTH listeners proves the arena before any moderation.
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

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(30));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            if (NOT Snapshot_Arrivals(this, State))
            { return false; }

            TestTrue(TEXT("baseline: listener B receives"), State->ArrivalsAtB > 0);
            TestTrue(TEXT("baseline: listener C receives"), State->ArrivalsAtC > 0);
            return true;
        }),
        TEXT("baseline delivers to both")));

    // Act 2 - CanTalk=Disable on the talker: a member who may not SPEAK reaches nobody.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InServer) -> void
        {
            auto* TalkerA = Find_SubjectNear(InServer, TalkerALocation);
            if (TalkerA == nullptr)
            { AddError(TEXT("talker A missing at act 2")); return; }

            UCk_Utils_VoiceChannel_UE::Request_SetMemberFlags(TalkerA->_TestChannel,
                FCk_Request_VoiceChannel_SetMemberFlags{TalkerA->_TestTalker,
                    FCk_VoiceChat_MemberFlags{}.Set_CanTalk(ECk_EnableDisable::Disable)}, {});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(20));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InServer) -> void
        {
            Inject_FromTalkerA(this, InServer, State);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(30));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            const auto PriorB = State->ArrivalsAtB;
            const auto PriorC = State->ArrivalsAtC;

            if (NOT Snapshot_Arrivals(this, State))
            { return false; }

            TestEqual(TEXT("CanTalk=Disable: listener B frozen"), State->ArrivalsAtB, PriorB);
            TestEqual(TEXT("CanTalk=Disable: listener C frozen"), State->ArrivalsAtC, PriorC);
            return true;
        }),
        TEXT("CanTalk disable silences the talker")));

    // Act 3 - restore CanTalk; CanHear=Disable on B: B freezes while C keeps receiving.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InServer) -> void
        {
            auto* TalkerA = Find_SubjectNear(InServer, TalkerALocation);
            auto* ListenerB = Find_SubjectNear(InServer, ListenerBLocation);
            if (TalkerA == nullptr || ListenerB == nullptr)
            { AddError(TEXT("subjects missing at act 3")); return; }

            UCk_Utils_VoiceChannel_UE::Request_SetMemberFlags(TalkerA->_TestChannel,
                FCk_Request_VoiceChannel_SetMemberFlags{TalkerA->_TestTalker,
                    FCk_VoiceChat_MemberFlags{}}, {});
            UCk_Utils_VoiceChannel_UE::Request_SetMemberFlags(TalkerA->_TestChannel,
                FCk_Request_VoiceChannel_SetMemberFlags{ListenerB->_TestTalker,
                    FCk_VoiceChat_MemberFlags{}.Set_CanHear(ECk_EnableDisable::Disable)}, {});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(20));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InServer) -> void
        {
            Inject_FromTalkerA(this, InServer, State);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(30));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            const auto PriorB = State->ArrivalsAtB;
            const auto PriorC = State->ArrivalsAtC;

            if (NOT Snapshot_Arrivals(this, State))
            { return false; }

            TestEqual(TEXT("CanHear=Disable: listener B frozen"), State->ArrivalsAtB, PriorB);
            TestTrue(TEXT("CanHear=Disable: listener C still receives (differential control)"),
                State->ArrivalsAtC > PriorC);
            return true;
        }),
        TEXT("CanHear disable excludes exactly one recipient")));

    // Act 4 - restore B's hearing; SERVER-mute the talker: nobody receives.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InServer) -> void
        {
            auto* TalkerA = Find_SubjectNear(InServer, TalkerALocation);
            auto* ListenerB = Find_SubjectNear(InServer, ListenerBLocation);
            if (TalkerA == nullptr || ListenerB == nullptr)
            { AddError(TEXT("subjects missing at act 4")); return; }

            UCk_Utils_VoiceChannel_UE::Request_SetMemberFlags(TalkerA->_TestChannel,
                FCk_Request_VoiceChannel_SetMemberFlags{ListenerB->_TestTalker,
                    FCk_VoiceChat_MemberFlags{}}, {});
            UCk_Utils_VoiceChannel_UE::Request_ServerMute(TalkerA->_TestChannel,
                FCk_Request_VoiceChannel_ServerMute{TalkerA->_TestTalker}, {});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(20));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InServer) -> void
        {
            Inject_FromTalkerA(this, InServer, State);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(30));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            const auto PriorB = State->ArrivalsAtB;
            const auto PriorC = State->ArrivalsAtC;

            if (NOT Snapshot_Arrivals(this, State))
            { return false; }

            TestEqual(TEXT("server-mute: listener B frozen"), State->ArrivalsAtB, PriorB);
            TestEqual(TEXT("server-mute: listener C frozen"), State->ArrivalsAtC, PriorC);
            return true;
        }),
        TEXT("server mute silences the talker for everyone")));

    // Act 5 - composition, direction 1: B listener-mutes the talker WHILE server-muted, then the
    // server unmutes. C resumes; B stays frozen - the listener exclusion holds on its own.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(1,
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InClient) -> void
        {
            auto* ClientTalkerA = Find_SubjectNear(InClient, TalkerALocation);
            if (ClientTalkerA == nullptr || ck::Is_NOT_Valid(ClientTalkerA->_TestTalker) ||
                ck::Is_NOT_Valid(State->ClientBListener))
            {
                AddError(TEXT("talker-A replica or B's ears missing at act 5"));
                return;
            }

            UCk_Utils_VoiceListener_UE::Request_MuteTalker(State->ClientBListener,
                FCk_Request_VoiceListener_MuteTalker{ClientTalkerA->_TestTalker}, {});
        })));

    // The listener mute rides the reliable control relay - give it time to land in the server
    // matrix before the server unmute.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(30));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InServer) -> void
        {
            auto* TalkerA = Find_SubjectNear(InServer, TalkerALocation);
            if (TalkerA == nullptr)
            { AddError(TEXT("talker A missing at act 5 unmute")); return; }

            UCk_Utils_VoiceChannel_UE::Request_ServerUnmute(TalkerA->_TestChannel,
                FCk_Request_VoiceChannel_ServerUnmute{TalkerA->_TestTalker}, {});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(20));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InServer) -> void
        {
            Inject_FromTalkerA(this, InServer, State);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(30));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            const auto PriorB = State->ArrivalsAtB;
            const auto PriorC = State->ArrivalsAtC;

            if (NOT Snapshot_Arrivals(this, State))
            { return false; }

            TestEqual(TEXT("server-unmute + listener-mute: B stays frozen"), State->ArrivalsAtB, PriorB);
            TestTrue(TEXT("server-unmute + listener-mute: C resumes"), State->ArrivalsAtC > PriorC);
            return true;
        }),
        TEXT("listener mute holds after server unmute")));

    // Act 6 - composition, direction 2: B unmutes; with both layers lifted, B resumes.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(1,
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InClient) -> void
        {
            auto* ClientTalkerA = Find_SubjectNear(InClient, TalkerALocation);
            if (ClientTalkerA == nullptr || ck::Is_NOT_Valid(ClientTalkerA->_TestTalker) ||
                ck::Is_NOT_Valid(State->ClientBListener))
            {
                AddError(TEXT("talker-A replica or B's ears missing at act 6"));
                return;
            }

            UCk_Utils_VoiceListener_UE::Request_UnmuteTalker(State->ClientBListener,
                FCk_Request_VoiceListener_UnmuteTalker{ClientTalkerA->_TestTalker}, {});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(30));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InServer) -> void
        {
            Inject_FromTalkerA(this, InServer, State);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(30));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            const auto PriorB = State->ArrivalsAtB;

            if (NOT Snapshot_Arrivals(this, State))
            { return false; }

            TestTrue(TEXT("both layers lifted: listener B resumes"), State->ArrivalsAtB > PriorB);
            return true;
        }),
        TEXT("unmute restores delivery")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
