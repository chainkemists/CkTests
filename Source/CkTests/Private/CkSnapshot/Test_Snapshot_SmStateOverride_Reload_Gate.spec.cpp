// CkSnapshot StateMachine RUNTIME-OVERRIDE persistence GATE (Phase 3.4). Pins that a runtime
// UCk_Utils_StateMachine_UE::Request_AddOverrideState survives a snapshot Save -> real OpenLevel reload:
// the override list rides inside the SM RepData as a save-only field (Produce fills it, HydrationApply
// re-installs it), and after the reload transitioning into the overridden state instantiates the OVERRIDE
// class rather than the requested one.
//
// Surface in Session Frontend: Ck.Snapshot.SmStateOverride_Reload
//
// Single-world (NumPIEClients = 1) authority-only harness — the override list is authority-local
// (ck::FFragment_Sm_StateOverrides is a C++-only, NON-replicated fragment), so there is no client to
// converge; the whole contract lives on the loading authority. Mirrors the M2b LevelReload gate's
// OpenLevel-reload structure (post-OpenLevel the world is NM_Standalone, so Get_ServerWorld() is null and
// the post-travel world is enumerated from the PIE world contexts).
//
// Scenario (prompt Phase 3.4): initial state A -> install an override targeting the AS Target state ->
// transition into B (a NON-overridden state) -> Save -> Load(OpenLevel). Post-reload: the SM re-drives to
// B (base hydration unaffected by the restored override), THEN a fresh transition into the overridden
// Target resolves to the Replacement class — proving the override both SURVIVED and is FUNCTIONALLY applied.
//
// The Target / Replacement override states are AngelScript-authored (an override class must override
// DoGet_StatesToOverride, a BlueprintImplementableEvent — impossible in plain C++) and resolved by package
// path, the same idiom CkAutoTest_NetSubject_StateMachineEntityScript uses for its AS-authored sub-SM states.

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Engine/GameInstance.h"
#include "EngineUtils.h" // TActorIterator
#include "UObject/SoftObjectPath.h"

#include "CkStateMachine/StateMachine/CkStateMachine_Utils.h"
#include "CkStateMachine/StateMachine/CkStateMachine_Fragment_Data.h"
#include "CkStateMachine/State/EntityScripts/CkSmState_EntityScript.h"

#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/OwningActor/CkOwningActor_Utils.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "CkTests/Net/CkAutoTest_NetSubject_StateMachine.h"
#include "CkTests/Net/CkAutoTest_Sm_RecordingState.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

namespace
{
    constexpr auto SmOvr_MapPath = TEXT("/Engine/Maps/Entry");
    const auto     SmOvr_SlotName = FName{TEXT("CkSnapshot_SmStateOverride_GateSlot")};

    // AS-authored override states, resolved by package path (leading 'U' stripped, per the
    // /Script/Angelscript.<Name> convention). Null if the AS topology failed to compile.
    const auto SmOvr_TargetPath      = TEXT("/Script/Angelscript.Ck_SmOvrPersist_Target");
    const auto SmOvr_ReplacementPath = TEXT("/Script/Angelscript.Ck_SmOvrPersist_Replacement");

    static TWeakObjectPtr<UWorld> GSmOvr_PreTravelWorld;

    auto SmOvr_LoadAsClass(const TCHAR* InPath) -> TSubclassOf<UCk_SmState_EntityScript>
    {
        return FSoftClassPath{InPath}.TryLoadClass<UCk_SmState_EntityScript>();
    }

    // Post-OpenLevel the world is NM_Standalone, so the net harness's Get_ServerWorld() returns null.
    // Enumerate PIE worlds instead: the post-travel world is the PIE world that HasBegunPlay and is NOT
    // the stashed pre-travel world (mirrors the M2b gate's M2b_PostTravelWorld).
    auto SmOvr_PostTravelWorld() -> UWorld*
    {
        if (GEngine == nullptr) { return nullptr; }
        auto* Best = static_cast<UWorld*>(nullptr);
        for (const auto& Context : GEngine->GetWorldContexts())
        {
            if (Context.WorldType != EWorldType::PIE) { continue; }
            auto* World = Context.World();
            if (World == nullptr) { continue; }
            if (World != GSmOvr_PreTravelWorld.Get() && World->HasBegunPlay())
            { Best = World; }
        }
        return Best;
    }

    auto SmOvr_Subsystem(UWorld* InWorld) -> UCk_Snapshot_Subsystem_UE*
    {
        if (InWorld == nullptr || InWorld->GetGameInstance() == nullptr) { return nullptr; }
        return InWorld->GetGameInstance()->GetSubsystem<UCk_Snapshot_Subsystem_UE>();
    }

    auto SmOvr_FindSubject(UWorld* InWorld) -> ACk_AutoTest_NetSubject_StateMachine_UE*
    {
        if (InWorld == nullptr) { return nullptr; }
        for (auto It = TActorIterator<ACk_AutoTest_NetSubject_StateMachine_UE>(InWorld); It; ++It) { return *It; }
        return nullptr;
    }

    // Resolve through the entity (never the actor's _TestStateMachine stash — restored-actor stashes are
    // empty because Construct abstains on restore).
    auto SmOvr_ResolveSm(AActor* InSubject) -> FCk_Handle_StateMachine
    {
        if (InSubject == nullptr) { return {}; }
        const auto Entity = UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(InSubject);
        if (ck::Is_NOT_Valid(Entity)) { return {}; }
        if (NOT UCk_Utils_StateMachine_UE::Has(Entity)) { return {}; }
        return UCk_Utils_StateMachine_UE::Cast(Entity);
    }

    auto SmOvr_IsRunningIn(UWorld* InWorld, TSubclassOf<UCk_SmState_EntityScript> InStateClass) -> bool
    {
        auto Sm = SmOvr_ResolveSm(SmOvr_FindSubject(InWorld));
        if (ck::Is_NOT_Valid(Sm)) { return false; }
        return UCk_Utils_StateMachine_UE::Get_RunStatus(Sm) == ECk_SmRunStatus::Running
            && UCk_Utils_StateMachine_UE::Get_CurrentStateClass(Sm).Get() == InStateClass.Get();
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_SmStateOverride_Reload_Gate,
    "Ck.Snapshot.SmStateOverride_Reload",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_SmStateOverride_Reload_Gate::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 1;        // single listen-server window, no remote client
    constexpr auto ExpectedTotalWorlds = 1;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesPerSettle = 30;
    constexpr auto FramesForReload = 240;    // teardown + OpenLevel + rebuild + hydrate + resume + quiescence
    constexpr auto ReloadTimeoutSeconds = 60.0f;

    const auto NonOverriddenState =
        TSubclassOf<UCk_SmState_EntityScript>{UCk_AutoTest_Sm_RecordingState_B::StaticClass()};
    const auto TargetClass      = SmOvr_LoadAsClass(SmOvr_TargetPath);
    const auto ReplacementClass = SmOvr_LoadAsClass(SmOvr_ReplacementPath);

    // Fail loud + early if the AS override states didn't compile — otherwise Request_AddOverrideState would
    // ensure on an invalid class and the failure cause would be buried downstream.
    if (TargetClass.Get() == nullptr || ReplacementClass.Get() == nullptr)
    {
        AddError(FString::Printf(TEXT("AS override states unresolved (Target=%p Replacement=%p) — did %s / %s compile?"),
            TargetClass.Get(), ReplacementClass.Get(), SmOvr_TargetPath, SmOvr_ReplacementPath));
        return true;
    }

    GSmOvr_PreTravelWorld = nullptr;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, FString{SmOvr_MapPath}));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // Stage 1 — spawn the snapshot-respawnable SM subject (ServerAuth / WithHistory / initial state A).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
            auto* Subject = InServer->SpawnActor<ACk_AutoTest_NetSubject_StateMachine_UE>(
                ACk_AutoTest_NetSubject_StateMachine_UE::StaticClass(), FTransform{FVector{100.0, 200.0, 300.0}}, SpawnInfo);
            if (Subject == nullptr) { AddError(TEXT("Stage 1: SM subject spawn returned null")); }
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle)); // AutoStart -> Running in A

    // Stage 2 — install the runtime override (Replacement overrides Target's tag), then transition into B,
    // a NON-overridden state. The override is registered but NOT yet triggered (B != Target).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, ReplacementClass, NonOverriddenState](UWorld* InServer) -> void
        {
            auto Sm = SmOvr_ResolveSm(SmOvr_FindSubject(InServer));
            if (ck::Is_NOT_Valid(Sm)) { AddError(TEXT("Stage 2: server SM unresolved")); return; }
            UCk_Utils_StateMachine_UE::Request_AddOverrideState(Sm, ReplacementClass);
            UCk_Utils_StateMachine_UE::Request_Transition(Sm, NonOverriddenState);
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 3 — pre-save sanity: Running in B (the away-from-initial mutation the reload must preserve) and
    // NOT in Target (the override is untriggered) — then stash the pre-travel world and Save.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, NonOverriddenState](UWorld* InServer) -> void
        {
            TestTrue(TEXT("pre-save: SM Running in the non-overridden state B"),
                SmOvr_IsRunningIn(InServer, NonOverriddenState));

            GSmOvr_PreTravelWorld = InServer;

            auto* Sub = SmOvr_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 3: no snapshot subsystem")); return; }
            Sub->Request_Save(SmOvr_SlotName, FCk_Delegate_OnSaveComplete{});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 4 — fire the async Load (real OpenLevel reload) + assert non-blocking.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Sub = SmOvr_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 4: no snapshot subsystem")); return; }
            Sub->Request_Load(SmOvr_SlotName, FCk_Delegate_OnLoadComplete{});
            TestTrue(TEXT("Stage 4: Request_Load non-blocking"), Sub->Get_IsLoadInProgress());
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesForReload));

    // Stage 5 — wait until the reload converged: a NEW world, load flag cleared, SM re-drove to B. Re-driving
    // to B (not Target, not the initial A) proves the restored override did NOT corrupt base hydration.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Assertion::CreateLambda([NonOverriddenState]() -> bool
        {
            auto* Server = SmOvr_PostTravelWorld();
            if (Server == nullptr || Server == GSmOvr_PreTravelWorld.Get() || NOT Server->HasBegunPlay()) { return false; }
            auto* Sub = SmOvr_Subsystem(Server);
            if (Sub == nullptr || Sub->Get_IsLoadInProgress()) { return false; }
            return SmOvr_IsRunningIn(Server, NonOverriddenState);
        }),
        ReloadTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle)); // let the resume ladder finalize

    // Stage 6 — the functional override proof: transition the reloaded SM into the OVERRIDDEN Target. If the
    // override survived + was re-installed, Get_ResolvedStateClass swaps Target -> Replacement at entry. This
    // step both asserts the pre-transition state (still B) and drives the transition (a driver-in-assert step,
    // since the post-OpenLevel Standalone world isn't reachable via FCk_Latent_RunOnServer).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, NonOverriddenState, TargetClass]() -> bool
        {
            auto* Server = SmOvr_PostTravelWorld();
            if (Server == nullptr) { AddError(TEXT("Stage 6: no post-travel world")); return false; }

            TestTrue(TEXT("post-reload: SM settled in the saved non-overridden state B"),
                SmOvr_IsRunningIn(Server, NonOverriddenState));

            auto Sm = SmOvr_ResolveSm(SmOvr_FindSubject(Server));
            if (ck::Is_NOT_Valid(Sm)) { AddError(TEXT("Stage 6: post-reload SM unresolved")); return false; }
            UCk_Utils_StateMachine_UE::Request_Transition(Sm, TargetClass);
            return true;
        }),
        TEXT("post-reload: drive a transition into the overridden Target state")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 7 — the override SURVIVED and is FUNCTIONALLY applied: the transition into Target resolved to the
    // Replacement class (Get_ResolvedStateClass swapped it), NOT the requested Target. If the override had been
    // lost across the reload, the current state would be Target.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, TargetClass, ReplacementClass]() -> bool
        {
            auto* Server = SmOvr_PostTravelWorld();
            if (Server == nullptr) { AddError(TEXT("Stage 7: no post-travel world")); return false; }

            auto Sm = SmOvr_ResolveSm(SmOvr_FindSubject(Server));
            if (ck::Is_NOT_Valid(Sm)) { AddError(TEXT("Stage 7: post-reload SM unresolved")); return false; }

            const auto Resolved = UCk_Utils_StateMachine_UE::Get_CurrentStateClass(Sm);
            TestEqual(TEXT("restored override applied: transition into Target resolved to the Replacement class"),
                Resolved.Get(), ReplacementClass.Get());
            TestTrue(TEXT("restored override applied: current state is NOT the un-overridden Target"),
                Resolved.Get() != TargetClass.Get());
            return true;
        }),
        TEXT("SM runtime state-override survived save -> OpenLevel reload and is functionally applied")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
