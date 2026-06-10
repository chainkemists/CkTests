// CkSnapshot StateMachine-Parity GATES — strict round-trip of a replicated StateMachine's decision record
// ({RunStatus, CurrentStateClass}) through a listen-server SEAMLESS ServerTravel reload, asserted on BOTH worlds.
//
// The server transitions the SM away from its initial state (A -> B) before save; post-reload both worlds must
// report CurrentState == B and RunStatus == Running. SM replication is event-driven history replay (not value
// rep), so the restore path is the RE-DRIVE design (docs/superpowers/specs/2026-06-10-CkSnapshot-StateMachine-
// restore-design.md, Option A replay-through): the server re-runs Setup (container + relay re-attach), Starts
// into InitialState, then transitions into the saved state; the fresh post-travel client converges through the
// completely ordinary replication path (WithHistory: run-status mirror + FirstSync initial entry + replay ring;
// WithoutHistory: snap-to-current).
//
// Per the SM replication contract, the client never observes Enter(InitialState) as a replay event — both gates
// assert only on the transitioned-INTO state (B) via Get_CurrentStateClass, never on recorder Enter(A) counts.
//
// Two gates, one per replication model:
//   Ck.Snapshot.Parity.StateMachine_MPReload            (WithHistory — replay-ring convergence)
//   Ck.Snapshot.Parity.StateMachineNoHistory_MPReload   (WithoutHistory — snap-to-current convergence)

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Engine/GameInstance.h"
#include "EngineUtils.h"               // TActorIterator
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel

#include "CkStateMachine/StateMachine/CkStateMachine_Utils.h"
#include "CkStateMachine/StateMachine/CkStateMachine_Fragment_Data.h"

#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/OwningActor/CkOwningActor_Utils.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "CkTests/Net/CkAutoTest_NetSubject_StateMachine.h"
#include "CkTests/Net/CkAutoTest_Sm_RecordingState.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

namespace
{
    constexpr auto SmParity_MapPath = TEXT("/Engine/Maps/Entry");

    static TWeakObjectPtr<UWorld> GSmParity_PreServerWorld;
    static TWeakObjectPtr<UWorld> GSmParity_PreClientWorld;

    auto SmParity_MapNameOf(UWorld* InWorld) -> FString
    {
        return InWorld != nullptr ? InWorld->RemovePIEPrefix(InWorld->GetOutermost()->GetName()) : FString{};
    }

    auto SmParity_Subsystem(UWorld* InWorld) -> UCk_Snapshot_Subsystem_UE*
    {
        if (InWorld == nullptr || InWorld->GetGameInstance() == nullptr) { return nullptr; }
        return InWorld->GetGameInstance()->GetSubsystem<UCk_Snapshot_Subsystem_UE>();
    }

    // Base-class iteration deliberately covers both subject flavours — each gate's PIE session only
    // ever spawns one of them.
    auto SmParity_FindSubject(UWorld* InWorld) -> ACk_AutoTest_NetSubject_StateMachine_UE*
    {
        if (InWorld == nullptr) { return nullptr; }
        for (auto It = TActorIterator<ACk_AutoTest_NetSubject_StateMachine_UE>(InWorld); It; ++It) { return *It; }
        return nullptr;
    }

    // Resolution goes through the entity (TryGet_ActorEntityHandle -> Has/Cast), never the actor's
    // `_TestStateMachine` stash — restored-actor stashes are empty (Construct abstains on restore).
    auto SmParity_ResolveSm(AActor* InSubject) -> FCk_Handle_StateMachine
    {
        if (InSubject == nullptr) { return {}; }
        auto Entity = UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(InSubject);
        if (ck::Is_NOT_Valid(Entity)) { return {}; }
        if (NOT UCk_Utils_StateMachine_UE::Has(Entity)) { return {}; }
        return UCk_Utils_StateMachine_UE::Cast(Entity);
    }

    auto SmParity_IsRunningIn(UWorld* InWorld, TSubclassOf<UCk_SmState_EntityScript> InStateClass) -> bool
    {
        auto Sm = SmParity_ResolveSm(SmParity_FindSubject(InWorld));
        if (ck::Is_NOT_Valid(Sm)) { return false; }
        return UCk_Utils_StateMachine_UE::Get_RunStatus(Sm) == ECk_SmRunStatus::Running
            && UCk_Utils_StateMachine_UE::Get_CurrentStateClass(Sm).Get() == InStateClass.Get();
    }
}

// --------------------------------------------------------------------------------------------------------------------
// Shared gate body — parameterized on the subject class (WithHistory vs WithoutHistory flavour) and the save slot.
// --------------------------------------------------------------------------------------------------------------------

namespace
{
    auto SmParity_RunGate(
        FAutomationTestBase* InTest,
        TSubclassOf<ACk_AutoTest_NetSubject_StateMachine_UE> InSubjectClass,
        const FName InSlotName) -> void
    {
        constexpr auto NumPIEClients = 2;        // server window + 1 connected client
        constexpr auto ExpectedTotalWorlds = 2;
        constexpr auto ReadyTimeoutSeconds = 30.0f;
        constexpr auto FramesPerSettle = 30;
        constexpr auto ReloadTimeoutSeconds = 60.0f;
        constexpr auto FramesPostReconnect = 60;

        const auto TargetStateClass =
            TSubclassOf<UCk_SmState_EntityScript>{UCk_AutoTest_Sm_RecordingState_B::StaticClass()};

        GSmParity_PreServerWorld = nullptr;
        GSmParity_PreClientWorld = nullptr;

        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, FString{SmParity_MapPath}));
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

        // Stage 1 — open the PIE seamless gate + spawn the SM-flavoured replicated subject on the server.
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
            FCk_NetAutoTest_ServerAction::CreateLambda([InTest, InSubjectClass](UWorld* InServer) -> void
            {
                if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
                { CVar->Set(1, ECVF_SetByCode); }

                auto SpawnInfo = FActorSpawnParameters{};
                SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
                auto* Subject = InServer->SpawnActor<ACk_AutoTest_NetSubject_StateMachine_UE>(
                    InSubjectClass.Get(), FTransform{FVector{100.0, 200.0, 300.0}}, SpawnInfo);
                if (Subject == nullptr) { InTest->AddError(TEXT("Stage 1: SM subject spawn returned null")); }
            })));
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

        // Stage 2 — pre-reload sanity: the CLIENT resolves the SM and sees it Running (run-status mirror works).
        // WithoutHistory clients may legitimately show <none> for the current state until the first transition
        // replicates, so only Running is required here.
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
            FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
            {
                auto* Client = ck::auto_test::net::Get_ClientWorld(0);
                if (Client == nullptr) { return false; }
                auto Sm = SmParity_ResolveSm(SmParity_FindSubject(Client));
                if (ck::Is_NOT_Valid(Sm)) { return false; }
                return UCk_Utils_StateMachine_UE::Get_RunStatus(Sm) == ECk_SmRunStatus::Running;
            }),
            ReadyTimeoutSeconds));

        // Stage 3 — server transitions A -> B (the away-from-Construct-default mutation the reload must preserve).
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
            FCk_NetAutoTest_ServerAction::CreateLambda([InTest, TargetStateClass](UWorld* InServer) -> void
            {
                auto Sm = SmParity_ResolveSm(SmParity_FindSubject(InServer));
                if (ck::Is_NOT_Valid(Sm)) { InTest->AddError(TEXT("Stage 3: server SM unresolved")); return; }
                UCk_Utils_StateMachine_UE::Request_Transition(Sm, TargetStateClass);
            })));
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

        // Stage 3b — live replication sanity: the client converged on B BEFORE the save (proves the
        // post-reload client assert exercises the restore path, not a still-broken live path).
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
            FCk_NetAutoTest_Assertion::CreateLambda([TargetStateClass]() -> bool
            {
                return SmParity_IsRunningIn(ck::auto_test::net::Get_ClientWorld(0), TargetStateClass);
            }),
            ReadyTimeoutSeconds));

        // Stage 3c — assert the SERVER holds Running+B before saving.
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
            FCk_NetAutoTest_ServerAction::CreateLambda([InTest, TargetStateClass](UWorld* InServer) -> void
            {
                InTest->TestTrue(TEXT("pre-save server: SM Running in B"),
                    SmParity_IsRunningIn(InServer, TargetStateClass));
            })));

        // Stage 4 — Save on the server; stash pre-travel worlds.
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
            FCk_NetAutoTest_ServerAction::CreateLambda([InTest, InSlotName](UWorld* InServer) -> void
            {
                GSmParity_PreServerWorld = InServer;
                GSmParity_PreClientWorld = ck::auto_test::net::Get_ClientWorld(0);
                auto* Sub = SmParity_Subsystem(InServer);
                if (Sub == nullptr) { InTest->AddError(TEXT("Stage 4: no snapshot subsystem")); return; }
                Sub->Request_Save(InSlotName, FCk_Delegate_OnSaveComplete{});
            })));
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

        // Stage 5 — fire async Load (triggers seamless ServerTravel) + assert non-blocking.
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
            FCk_NetAutoTest_ServerAction::CreateLambda([InTest, InSlotName](UWorld* InServer) -> void
            {
                auto* Sub = SmParity_Subsystem(InServer);
                if (Sub == nullptr) { InTest->AddError(TEXT("Stage 5: no snapshot subsystem")); return; }
                Sub->Request_Load(InSlotName, FCk_Delegate_OnLoadComplete{});
                InTest->TestTrue(TEXT("Stage 5: Request_Load non-blocking"), Sub->Get_IsLoadInProgress());
            })));

        // Stage 6 — poll until the server finished the load AND the client rode the travel AND the SM
        // CONVERGED to Running+B on the client (re-drive on the server, ordinary replication to the client).
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
            FCk_NetAutoTest_Assertion::CreateLambda([TargetStateClass]() -> bool
            {
                auto* Server = ck::auto_test::net::Get_ServerWorld();
                if (Server == nullptr || Server == GSmParity_PreServerWorld.Get() || !Server->HasBegunPlay()) { return false; }
                if (SmParity_MapNameOf(Server) != SmParity_MapPath) { return false; }
                auto* Sub = SmParity_Subsystem(Server);
                if (Sub == nullptr || Sub->Get_IsLoadInProgress()) { return false; }
                if (SmParity_FindSubject(Server) == nullptr) { return false; }

                auto* Client = ck::auto_test::net::Get_ClientWorld(0);
                if (Client == nullptr || Client == GSmParity_PreClientWorld.Get() || !Client->HasBegunPlay()) { return false; }
                if (SmParity_MapNameOf(Client) != SmParity_MapPath) { return false; }

                return SmParity_IsRunningIn(Client, TargetStateClass);
            }),
            ReloadTimeoutSeconds));
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPostReconnect));

        // Stage 7 — parity assertions on BOTH worlds: Running + CurrentState == B survived the round-trip
        // (NOT the freshly-Constructed default of Running-in-A).
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(InTest,
            FCk_NetAutoTest_Assertion::CreateLambda([InTest, TargetStateClass]() -> bool
            {
                auto* Server = ck::auto_test::net::Get_ServerWorld();
                auto ServerSm = SmParity_ResolveSm(SmParity_FindSubject(Server));
                if (ck::Is_NOT_Valid(ServerSm))
                { InTest->AddError(TEXT("Stage 7: server SM unresolved post-reload")); return false; }

                InTest->TestTrue(TEXT("server: SM Running post-reload"),
                    UCk_Utils_StateMachine_UE::Get_RunStatus(ServerSm) == ECk_SmRunStatus::Running);
                InTest->TestEqual(TEXT("server: SM re-drove into the saved state (B, not InitialState A)"),
                    UCk_Utils_StateMachine_UE::Get_CurrentStateClass(ServerSm).Get(), TargetStateClass.Get());

                auto* Client = ck::auto_test::net::Get_ClientWorld(0);
                if (Client == nullptr) { InTest->AddError(TEXT("Stage 7: no post-travel client world")); return false; }

                auto ClientSm = SmParity_ResolveSm(SmParity_FindSubject(Client));
                if (ck::Is_NOT_Valid(ClientSm))
                { InTest->AddError(TEXT("Stage 7: client SM unresolved post-reload")); return false; }

                InTest->TestTrue(TEXT("client: SM Running post-reload"),
                    UCk_Utils_StateMachine_UE::Get_RunStatus(ClientSm) == ECk_SmRunStatus::Running);
                InTest->TestEqual(TEXT("client: SM converged on the saved state (B) through normal replication"),
                    UCk_Utils_StateMachine_UE::Get_CurrentStateClass(ClientSm).Get(), TargetStateClass.Get());
                return true;
            }),
            TEXT("StateMachine parity: saved {Running, B} survives save -> seamless reload -> client convergence")));

        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_StateMachineParity_MPReload_Gate,
    "Ck.Snapshot.Parity.StateMachine_MPReload",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_StateMachineParity_MPReload_Gate::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    SmParity_RunGate(this,
        ACk_AutoTest_NetSubject_StateMachine_UE::StaticClass(),
        FName{TEXT("CkSnapshot_SmParity_WithHistory_GateSlot")});
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_StateMachineNoHistoryParity_MPReload_Gate,
    "Ck.Snapshot.Parity.StateMachineNoHistory_MPReload",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_StateMachineNoHistoryParity_MPReload_Gate::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    SmParity_RunGate(this,
        ACk_AutoTest_NetSubject_StateMachineNoHistory_UE::StaticClass(),
        FName{TEXT("CkSnapshot_SmParity_NoHistory_GateSlot")});
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
