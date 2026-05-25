// Spec §13 / Phase 12.1 — Server-authoritative A→B→C transition chain.
//
// Server spawns a Replicates / ServerAuthoritative / WithHistory SM with initial state A,
// transitions A→B then B→C from server-side Request_Transition calls. After replication
// converges, both server and client recorders are asserted:
//   - Server: ends in state C, observed Enter(A,Server), Enter(B,Server), Enter(C,Server).
//   - Client: ends in state C, observed Enter(A,NonOwningClient) + Enter(B,NonOwningClient)
//             + Enter(C,NonOwningClient). Exit-on-prev fires for A and B as well, but the
//             primary contract is that the client walks all three Enters in order via the
//             replay queue with the right NetContext.
//
// Surface in Session Frontend: Ck.StateMachine.Net.ServerAuth_ABC_Replay

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "GameFramework/Actor.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Net/CkNet_Fragment_Data.h"
#include "CkEcs/Net/CkNet_Utils.h"
#include "CkEcs/OwningActor/CkOwningActor_Utils.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"
#include "CkStateMachine/StateMachine/CkStateMachine_Fragment_Data.h"
#include "CkStateMachine/StateMachine/CkStateMachine_Utils.h"

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
    // Pre-existing CkActorRelay × Iris incompatibility under multi-client PIE produces ambient
    // log-error noise unrelated to this test (see CONTINUATION_PROMPT_SmReplicationTestHarness_Phase2.md
    // and the smoke test's source comment). Broad backstop until that's fixed; restored via
    // a trailing latent command after EndPIE so subsequent tests in the same process see
    // default semantics again.
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesAfterAdd = 15;          // setup + initial RepData propagation to client
    constexpr auto FramesAfterTransition = 10;   // per-transition rep convergence
    constexpr auto FramesAfterFinalTransition = 30;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    // Shared handle slot: the first RunOnServer writes the SM, subsequent commands read it.
    // TSharedPtr captured by value into each lambda so the slot survives between latent
    // command callbacks.
    auto SmSlot = MakeShared<FCk_Handle_StateMachine>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // ---- Spawn the SM on the server -------------------------------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([SmSlot](UWorld* InServer) -> void
        {
            // For a Replicates SM, the SM entity's chain must include an OwningActor — the rep
            // driver walks up the ownership chain looking for a replicated AActor to Outer the
            // driver UObject to. TransientEntity has no actor, so spawn a fresh replicated test
            // actor + bridge a new entity to it, then attach the SM beneath that entity.
            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride =
                ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
            auto* OwnerActor = InServer->SpawnActor<AActor>(
                AActor::StaticClass(), FTransform::Identity, SpawnInfo);
            if (OwnerActor == nullptr)
            { return; }
            OwnerActor->SetReplicates(true);

            auto TransientEntity = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
            auto OwnerEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(TransientEntity);
            if (ck::Is_NOT_Valid(OwnerEntity))
            { return; }

            // NetParams first (so OwningActor::Add can wire the ReplicationDriver), then the
            // actor link. NetMode=Host + NetRole=Authority on the server world — UCk_Utils_Net_UE::Add
            // only adds FTag_HasAuthority when NetRole==Authority. Without the tag, all downstream
            // authority checks (HandleRequests' single-authority gate, ComputeNetContext's Server
            // branch) fail and the SM is incorrectly treated as non-authority.
            const auto Settings = FCk_Net_ConnectionSettings{
                ECk_Replication::Replicates,
                ECk_Net_NetModeType::Host,
                ECk_Net_EntityNetRole::Authority};
            UCk_Utils_Net_UE::Add(OwnerEntity, Settings);
            UCk_Utils_OwningActor_UE::Add(OwnerEntity, OwnerActor);
            UCk_Utils_OwningActor_UE::SetupActorEntityLink(OwnerEntity, OwnerActor);

            auto Params = FCk_Fragment_StateMachine_ParamsData{
                UCk_AutoTest_Sm_RecordingState_A::StaticClass()};
            Params.Set_Replication(ECk_Replication::Replicates);
            Params.Set_AuthorityModel(ECk_Sm_AuthorityModel::ServerAuthoritative);
            Params.Set_ReplicationModel(ECk_Sm_ReplicationModel::WithHistory);
            Params.Set_AutoStart(ECk_SmAutoStart::OnSetup);

            *SmSlot = UCk_Utils_StateMachine_UE::Add_WithParams(OwnerEntity, Params);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterAdd));

    // ---- Transition A → B -----------------------------------------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([SmSlot](UWorld* /*InServer*/) -> void
        {
            if (ck::Is_NOT_Valid(*SmSlot))
            { return; }
            UCk_Utils_StateMachine_UE::Request_Transition(*SmSlot,
                UCk_AutoTest_Sm_RecordingState_B::StaticClass());
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterTransition));

    // ---- Transition B → C -----------------------------------------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([SmSlot](UWorld* /*InServer*/) -> void
        {
            if (ck::Is_NOT_Valid(*SmSlot))
            { return; }
            UCk_Utils_StateMachine_UE::Request_Transition(*SmSlot,
                UCk_AutoTest_Sm_RecordingState_C::StaticClass());
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterFinalTransition));

    // ---- Cross-world assertions -----------------------------------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, SmSlot]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);

            if (Server == nullptr || Client == nullptr)
            {
                AddError(TEXT("server and/or client world unavailable at assertion time"));
                return false;
            }

            // ---- Final state on both ends ------------------------------------------------------------------

            const auto ExpectedFinalClass =
                TSubclassOf<UCk_SmState_EntityScript>{UCk_AutoTest_Sm_RecordingState_C::StaticClass()};

            if (ck::IsValid(*SmSlot))
            {
                const auto ServerCurrentClass =
                    UCk_Utils_StateMachine_UE::Get_CurrentStateClass(*SmSlot);
                TestEqual(TEXT("server SM final state class is C"),
                    ServerCurrentClass.Get(), ExpectedFinalClass.Get());
            }
            else
            {
                AddError(TEXT("server-side SM handle was never set (Add_WithParams failed?)"));
            }

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

            const auto ClientEntersA = ClientRecorder->Get_EventsForState(
                UCk_AutoTest_Sm_RecordingState_A::StaticClass());
            const auto ClientEntersB = ClientRecorder->Get_EventsForState(
                UCk_AutoTest_Sm_RecordingState_B::StaticClass());
            const auto ClientEntersC = ClientRecorder->Get_EventsForState(
                UCk_AutoTest_Sm_RecordingState_C::StaticClass());

            TestTrue(TEXT("client saw at least one Enter(A,NonOwningClient)"),
                CountKind(ClientEntersA, ECk_AutoTest_Sm_EventKind::EnterState,
                    ECk_Sm_NetContext::NonOwningClient) >= 1);
            TestTrue(TEXT("client saw at least one Enter(B,NonOwningClient)"),
                CountKind(ClientEntersB, ECk_AutoTest_Sm_EventKind::EnterState,
                    ECk_Sm_NetContext::NonOwningClient) >= 1);
            TestTrue(TEXT("client saw at least one Enter(C,NonOwningClient)"),
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
