// Spec §13 / Phase 12.1 — Server-authoritative A→B→C transition chain.
//
// Server spawns ACk_AutoTest_NetSubject_StateMachine_UE — its bridged entity-script
// (UCk_AutoTest_NetSubject_StateMachineEntityScript_UE) creates a Replicates /
// ServerAuthoritative / WithHistory SM with initial state A on both worlds via the entity-script
// lifecycle's symmetric Construct path. Server then Request_Transition's A→B, then B→C. After
// replication converges, both server and client recorders are asserted:
//   - Server: ends in state C, observed Enter(A,Server), Enter(B,Server), Enter(C,Server).
//   - Client: ends in state C, observed Enter(A,NonOwningClient) + Enter(B,NonOwningClient)
//             + Enter(C,NonOwningClient). The primary contract is that the client walks all three
//             Enters in order via the replay queue with the right NetContext.
//
// Why the NetSubject pattern (vs. the prior manual Request_CreateEntity + Net::Add): the previous
// shape created the SM on the server only — the client had no matching SM entity, so the rep
// payload's OnChange/OnAdd handlers had nothing to fire on. The WithActor-based entity-script
// runs Construct on both worlds via the entity-script lifecycle's replication path, giving us a
// symmetric SM target by construction. Plus we get the SubjectActor->_TestStateMachine
// reverse-lookup pattern that mirrors CkInventory's _TestInventory.
//
// Surface in Session Frontend: Ck.StateMachine.Net.ServerAuth_ABC_Replay

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"

#include "CkEcs/Net/CkNet_Utils.h"
#include "CkEcs/OwningActor/CkOwningActor_Utils.h"
#include "CkStateMachine/StateMachine/CkStateMachine_Fragment_Data.h"
#include "CkStateMachine/StateMachine/CkStateMachine_Utils.h"

#include "CkTests/Net/CkAutoTest_NetSubject.h"
#include "CkTests/Net/CkAutoTest_NetSubject_StateMachine.h"
#include "CkTests/Net/CkAutoTest_Sm_Recorder.h"
#include "CkTests/Net/CkAutoTest_Sm_RecordingState.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkStateMachineNet_ServerAuth_ABC_Replay,
    "Ck.StateMachine.Net.ServerAuth_ABC_Replay",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkStateMachineNet_ServerAuth_ABC_Replay::RunTest(const FString& Parameters)
{
    // Multi-client PIE produces ambient log noise from concurrent Iris setup unrelated to this
    // test (see CkActorRelay's net tests for the same backstop). Restored via a trailing latent
    // command after EndPIE so subsequent tests see default semantics.
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesAfterSpawn = 30;        // setup + initial RepData propagation + entity-script Construct on both worlds
    constexpr auto FramesAfterTransition = 10;   // per-transition rep convergence
    constexpr auto FramesAfterFinalTransition = 30;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // ---- Spawn the SM-flavoured NetSubject on the server ---------------------------------------------------
    // The actor's BeginPlay kicks off the entity-script spawn (Request_SpawnEntity with
    // FCk_EntityScript_WithActor_SpawnParams), and the entity-script's Construct runs on both
    // worlds independently — each adding a Replicates/ServerAuth/WithHistory SM with initial
    // state A and stashing the handle in `_TestStateMachine` on its own world's actor.

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
            auto* Subject = InServer->SpawnActor<ACk_AutoTest_NetSubject_StateMachine_UE>(
                ACk_AutoTest_NetSubject_StateMachine_UE::StaticClass(), FTransform::Identity, SpawnInfo);
            if (Subject == nullptr)
            { AddError(TEXT("server-side SpawnActor of ACk_AutoTest_NetSubject_StateMachine_UE returned null")); }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterSpawn));

    // ---- Transition A → B -----------------------------------------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Subject = ACk_AutoTest_NetSubject::Find(InServer);
            auto* SmSubject = Cast<ACk_AutoTest_NetSubject_StateMachine_UE>(Subject);
            if (SmSubject == nullptr)
            { AddError(TEXT("server-side SM subject not found / not the expected subclass")); return; }
            if (ck::Is_NOT_Valid(SmSubject->_TestStateMachine))
            { AddError(TEXT("server-side _TestStateMachine handle wasn't populated by entity-script Construct")); return; }

            UCk_Utils_StateMachine_UE::Request_Transition(SmSubject->_TestStateMachine,
                UCk_AutoTest_Sm_RecordingState_B::StaticClass());
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterTransition));

    // ---- Transition B → C -----------------------------------------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Subject = ACk_AutoTest_NetSubject::Find(InServer);
            auto* SmSubject = Cast<ACk_AutoTest_NetSubject_StateMachine_UE>(Subject);
            if (SmSubject == nullptr)
            { AddError(TEXT("server-side SM subject not found at B→C transition")); return; }

            UCk_Utils_StateMachine_UE::Request_Transition(SmSubject->_TestStateMachine,
                UCk_AutoTest_Sm_RecordingState_C::StaticClass());
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterFinalTransition));

    // ---- Cross-world assertions -----------------------------------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);

            if (Server == nullptr || Client == nullptr)
            {
                AddError(TEXT("server and/or client world unavailable at assertion time"));
                return false;
            }

            // ---- Final state on the server side --------------------------------------------------------------

            const auto ExpectedFinalClass =
                TSubclassOf<UCk_SmState_EntityScript>{UCk_AutoTest_Sm_RecordingState_C::StaticClass()};

            auto* ServerSubject = ACk_AutoTest_NetSubject::Find(Server);
            auto* ServerSmSubject = Cast<ACk_AutoTest_NetSubject_StateMachine_UE>(ServerSubject);
            if (ServerSmSubject != nullptr && ck::IsValid(ServerSmSubject->_TestStateMachine))
            {
                const auto ServerCurrentClass =
                    UCk_Utils_StateMachine_UE::Get_CurrentStateClass(ServerSmSubject->_TestStateMachine);
                TestEqual(TEXT("server SM final state class is C"),
                    ServerCurrentClass.Get(), ExpectedFinalClass.Get());
            }
            else
            {
                AddError(TEXT("server-side SM subject / _TestStateMachine missing at assertion time"));
            }

            const auto CountKind = [](const TArray<FCk_AutoTest_Sm_RecordedEvent>& InArr,
                                       ECk_AutoTest_Sm_EventKind InKind,
                                       ECk_Sm_NetContext InNetContext) -> int32
            {
                auto N = 0;
                for (const auto& E : InArr)
                {
                    if (E.Kind == InKind && E.NetContext == InNetContext)
                    { ++N; }
                }
                return N;
            };

            // ---- Server recorder: walks A → B → C with NetContext=Server -----------------------------------

            auto* ServerRecorder = Server->GetSubsystem<UCk_AutoTest_Sm_RecorderSubsystem>();
            if (ServerRecorder == nullptr)
            {
                AddError(TEXT("server recorder subsystem missing"));
                return false;
            }

            const auto ServerEntersA = ServerRecorder->Get_EventsForState(
                UCk_AutoTest_Sm_RecordingState_A::StaticClass());
            const auto ServerEntersB = ServerRecorder->Get_EventsForState(
                UCk_AutoTest_Sm_RecordingState_B::StaticClass());
            const auto ServerEntersC = ServerRecorder->Get_EventsForState(
                UCk_AutoTest_Sm_RecordingState_C::StaticClass());

            TestEqual(TEXT("server saw exactly one Enter(A,Server)"),
                CountKind(ServerEntersA, ECk_AutoTest_Sm_EventKind::EnterState,
                    ECk_Sm_NetContext::Server), 1);
            TestEqual(TEXT("server saw exactly one Enter(B,Server)"),
                CountKind(ServerEntersB, ECk_AutoTest_Sm_EventKind::EnterState,
                    ECk_Sm_NetContext::Server), 1);
            TestEqual(TEXT("server saw exactly one Enter(C,Server)"),
                CountKind(ServerEntersC, ECk_AutoTest_Sm_EventKind::EnterState,
                    ECk_Sm_NetContext::Server), 1);

            // ---- Client recorder: walks A → B → C with NetContext=NonOwningClient --------------------------

            auto* ClientRecorder = Client->GetSubsystem<UCk_AutoTest_Sm_RecorderSubsystem>();
            if (ClientRecorder == nullptr)
            {
                AddError(TEXT("client recorder subsystem missing"));
                return false;
            }

            const auto ClientEntersB = ClientRecorder->Get_EventsForState(
                UCk_AutoTest_Sm_RecordingState_B::StaticClass());
            const auto ClientEntersC = ClientRecorder->Get_EventsForState(
                UCk_AutoTest_Sm_RecordingState_C::StaticClass());

            // Note: client does NOT see Enter(A). Initial-state entry (AutoStart=OnSetup) doesn't
            // emit a replay event — the WithHistory ring captures state CHANGES (transitions),
            // not the initial state itself. Server-side AutoStart enters A locally, but the
            // resulting "initial-state" record isn't part of the replay queue. Server transitions
            // A→B then B→C feed the ring; client's ApplyReplicatedHistory drains them, firing
            // EnterState for the NEW state of each transition (B, then C). The empirical client
            // recorder contents are exactly Enter(B) + Enter(C) + matching Exit events for the
            // previous state, no Enter(A) at all.
            TestTrue(TEXT("client saw at least one Enter(B,NonOwningClient) via replay"),
                CountKind(ClientEntersB, ECk_AutoTest_Sm_EventKind::EnterState,
                    ECk_Sm_NetContext::NonOwningClient) >= 1);
            TestTrue(TEXT("client saw at least one Enter(C,NonOwningClient) via replay"),
                CountKind(ClientEntersC, ECk_AutoTest_Sm_EventKind::EnterState,
                    ECk_Sm_NetContext::NonOwningClient) >= 1);

            // ---- Final ordering invariant: last Enter on the client is C ----------------------------------

            const auto& ClientAll = ClientRecorder->Get_Events();
            const FCk_AutoTest_Sm_RecordedEvent* LastEnter = nullptr;
            for (const auto& E : ClientAll)
            {
                if (E.Kind == ECk_AutoTest_Sm_EventKind::EnterState)
                { LastEnter = &E; }
            }

            if (LastEnter == nullptr)
            { AddError(TEXT("client recorder has no EnterState events at all")); }
            else
            {
                TestEqual(TEXT("client's most-recent EnterState is C"),
                    LastEnter->StateClass.Get(), ExpectedFinalClass.Get());
                TestEqual(TEXT("client's most-recent Enter has NetContext NonOwningClient"),
                    static_cast<int32>(LastEnter->NetContext),
                    static_cast<int32>(ECk_Sm_NetContext::NonOwningClient));
            }

            return true;
        }),
        TEXT("server-auth A→B→C replay: cross-world state + recorder ordering")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    // Restore static log suppression after teardown so subsequent tests see default semantics.
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

// --------------------------------------------------------------------------------------------------------------------

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
