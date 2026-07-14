// CkSnapshot Transform-Parity GATE (G1) — strict WORLD-transform round-trip of a PURE-ECS RuntimeSpawned entity
// through a listen-server SEAMLESS ServerTravel reload, asserted on the SERVER (authority). This is the headless-
// pinnable half of G1: it exercises the new FCk_Snapshot_V3_EntityEntry::_SavedWorldTransform column and
// DoApply_SavedTransforms' PURE-ECS MOVER branch (Request_SetTransform), which no prior gate covered.
//
// Setup: a replicated bridged M2bProbe is the persisted OWNER (RuntimeSpawned, snapshot-respawnable — it re-bridges
// on load). AFTER the probe has begun play, the test spawns a pure-ECS Transform child under the probe entity via
// Request_SpawnEntity — so the child is RuntimeSpawned (owner already begun play => no ConstructSpawned stamp), not
// actor-bridged, and DoesNotReplicate (server-only, like the Timer gate). The child's Construct adds a Transform at
// IDENTITY (the construct default); the test then MOVES it to a distinct world transform (location+rotation+scale
// all off-default) and saves.
//
// The differentiator: on load the child is re-spawned from its recipe and its Construct re-adds the Transform at
// IDENTITY. Only DoApply_SavedTransforms re-drives it to the saved (moved) transform. Asserting the restored child
// reads at the MOVED transform — and is NOT at Identity — proves the _SavedWorldTransform column did the work, not
// Construct re-derivation (which would leave it at Identity).
//
// The bridged actor path (M2bProbe restored to its saved location) is already covered by Ck.Snapshot.M2b2a.
// ReplicatedRespawn via the pre-existing _ActorSpawnTransform seed; the EngineOwned player-pawn / SaveKey level-actor
// SetActorTransform branch of DoApply is [EDITOR-VERIFY] (needs editor-placed content the headless map lacks).
//
// Surface in Session Frontend: Ck.Snapshot.Parity.Transform_MPReload

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Engine/GameInstance.h"
#include "EngineUtils.h"               // TActorIterator
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel

#include "StructUtils/InstancedStruct.h"

#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Handle/CkHandle_Utils.h"                      // ck::MakeHandle
#include "CkEcs/OwningActor/CkOwningActor_Utils.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"
#include "CkEcs/EntityScript/CkEntityScript_Utils.h"          // Request_SpawnEntity
#include "CkEcs/EntityScript/CkEntityScript_SpawnRecipe.h"    // ck::FFragment_SpawnRecipe (raw-view resolve)

#include "CkEcsExt/Transform/CkTransform_Utils.h"
#include "CkEcsExt/Transform/CkTransform_Fragment_Data.h"     // FCk_Request_Transform_SetTransform

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "CkTests/Net/CkAutoTest_NetSubject_M2bProbe_Replicated.h"
#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkTests/Snapshot/CkAutoTest_Snapshot_TransformProbe_EntityScript.h"

namespace
{
    constexpr auto Transform_MapPath  = TEXT("/Engine/Maps/Entry");
    const auto     Transform_SlotName = FName{TEXT("CkSnapshot_TransformParity_GateSlot")};
    const auto     Transform_ProbeLoc = FVector{100.0, 200.0, 300.0};

    // The MOVED world transform (all three components off the Identity construct-default so a no-op restore is caught
    // on every axis). Deliberately unrelated to the probe's own actor location.
    const auto Transform_MovedXf = FTransform{
        FRotator{0.0, 90.0, 0.0},          // Pitch, Yaw, Roll
        FVector{525.0, 650.0, 775.0},      // translation
        FVector{2.0, 3.0, 4.0}};           // scale

    constexpr auto Transform_Tolerance = 0.5; // near-exact round-trip; small epsilon for the FTransform double path.

    static TWeakObjectPtr<UWorld> GTransform_PreServerWorld;

    auto Transform_MapNameOf(UWorld* InWorld) -> FString
    {
        return InWorld != nullptr ? InWorld->RemovePIEPrefix(InWorld->GetOutermost()->GetName()) : FString{};
    }

    auto Transform_Subsystem(UWorld* InWorld) -> UCk_Snapshot_Subsystem_UE*
    {
        if (InWorld == nullptr || InWorld->GetGameInstance() == nullptr) { return nullptr; }
        return InWorld->GetGameInstance()->GetSubsystem<UCk_Snapshot_Subsystem_UE>();
    }

    auto Transform_FindProbe(UWorld* InWorld) -> ACk_AutoTest_NetSubject_M2bProbe_Replicated*
    {
        if (InWorld == nullptr) { return nullptr; }
        for (auto It = TActorIterator<ACk_AutoTest_NetSubject_M2bProbe_Replicated>(InWorld); It; ++It) { return *It; }
        return nullptr;
    }

    auto Transform_ResolveProbeEntity(AActor* InProbe) -> FCk_Handle
    {
        if (InProbe == nullptr) { return {}; }
        return UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(InProbe);
    }

    // Resolve the pure-ECS Transform child by its RETAINED spawn recipe's script class — every RuntimeSpawned entity
    // carries FFragment_SpawnRecipe, and only our child was spawned from this class. Handle-independent across the
    // reload (the restored child is a fresh entity). Mirrors M2b2a's raw-view resolution.
    auto Transform_ResolveChild(UWorld* InWorld) -> FCk_Handle
    {
        if (InWorld == nullptr) { return {}; }
        auto* Ecs = InWorld->GetSubsystem<UCk_EcsWorld_Subsystem_UE>();
        if (ck::Is_NOT_Valid(Ecs)) { return {}; }

        auto& CkRegistry = Ecs->Get_Registry();
        auto* Raw = ck::registry_table::TryResolve(CkRegistry.Get_RegistryHandle());
        if (Raw == nullptr) { return {}; }

        for (const auto Entity : Raw->view<ck::FFragment_SpawnRecipe>())
        {
            auto Handle = ck::MakeHandle(FCk_Entity{Entity}, CkRegistry);
            if (ck::Is_NOT_Valid(Handle)) { continue; }
            if (Handle.Get<ck::FFragment_SpawnRecipe>().Get_ScriptClass().Get()
                == UCk_AutoTest_Snapshot_TransformProbe_EntityScript_UE::StaticClass())
            { return Handle; }
        }
        return {};
    }

    auto Transform_ChildWorldTransform(UWorld* InWorld, bool& OutResolved) -> FTransform
    {
        auto Child = Transform_ResolveChild(InWorld);
        OutResolved = ck::IsValid(Child);
        if (NOT OutResolved) { return FTransform::Identity; }
        return UCk_Utils_Transform_TypeUnsafe_UE::Get_EntityCurrentTransform(Child);
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_TransformParity_MPReload_Gate,
    "Ck.Snapshot.Parity.Transform_MPReload",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_TransformParity_MPReload_Gate::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;        // server window + 1 connected client
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesPerSettle = 30;
    constexpr auto ReloadTimeoutSeconds = 60.0f;
    constexpr auto FramesPostReconnect = 60;

    GTransform_PreServerWorld = nullptr;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, FString{Transform_MapPath}));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // Stage 1 — open the PIE seamless gate + spawn the replicated bridged probe (the persisted OWNER) on the server.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
            { CVar->Set(1, ECVF_SetByCode); }

            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
            auto* Probe = InServer->SpawnActor<ACk_AutoTest_NetSubject_M2bProbe_Replicated>(
                ACk_AutoTest_NetSubject_M2bProbe_Replicated::StaticClass(), FTransform{Transform_ProbeLoc}, SpawnInfo);
            if (Probe == nullptr) { AddError(TEXT("Stage 1: replicated probe spawn returned null")); }
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 2 — wait until the probe's bridged entity resolves (Construct + BeginPlay ran). Spawning the child only
    // AFTER the owner has begun play is what makes it RuntimeSpawned (owner-in-construction would stamp it
    // ConstructSpawned + unlabeled => save-transient).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            if (Server == nullptr) { return false; }
            return ck::IsValid(Transform_ResolveProbeEntity(Transform_FindProbe(Server)));
        }),
        ReadyTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 3 — spawn the pure-ECS Transform child under the probe entity (RuntimeSpawned, DoesNotReplicate). Its
    // Construct adds a Transform at IDENTITY.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto ProbeEntity = Transform_ResolveProbeEntity(Transform_FindProbe(InServer));
            if (ck::Is_NOT_Valid(ProbeEntity)) { AddError(TEXT("Stage 3: probe entity unresolved")); return; }

            UCk_Utils_EntityScript_UE::Request_SpawnEntity(
                ProbeEntity,
                UCk_AutoTest_Snapshot_TransformProbe_EntityScript_UE::StaticClass(),
                FInstancedStruct{});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 3b — wait until the child resolves, then MOVE it to the distinct world transform (deferred request).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            return ck::IsValid(Transform_ResolveChild(ck::auto_test::net::Get_ServerWorld()));
        }),
        ReadyTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto Child = Transform_ResolveChild(InServer);
            if (ck::Is_NOT_Valid(Child)) { AddError(TEXT("Stage 3b: child unresolved before move")); return; }

            UCk_Utils_Transform_TypeUnsafe_UE::Request_SetTransform(
                Child, FCk_Request_Transform_SetTransform{Transform_MovedXf});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 3c — pre-save sanity: the SERVER child holds the MOVED transform (failing here means the move didn't take,
    // not that snapshot broke).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto Resolved = false;
            const auto Xf = Transform_ChildWorldTransform(InServer, Resolved);
            if (NOT Resolved) { AddError(TEXT("Stage 3c: child unresolved pre-save")); return; }
            TestTrue(TEXT("pre-save: child at MOVED transform"), Xf.Equals(Transform_MovedXf, Transform_Tolerance));
            TestTrue(TEXT("pre-save: child NOT at Identity construct-default"),
                NOT Xf.Equals(FTransform::Identity, Transform_Tolerance));
        })));

    // Stage 4 — Save on the server; stash the pre-travel server world.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            GTransform_PreServerWorld = InServer;
            auto* Sub = Transform_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 4: no snapshot subsystem")); return; }
            Sub->Request_Save(Transform_SlotName, FCk_Delegate_OnSaveComplete{});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 5 — fire async Load (triggers seamless ServerTravel) + assert non-blocking.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Sub = Transform_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 5: no snapshot subsystem")); return; }
            Sub->Request_Load(Transform_SlotName, FCk_Delegate_OnLoadComplete{});
            TestTrue(TEXT("Stage 5: Request_Load non-blocking"), Sub->Get_IsLoadInProgress());
        })));

    // Stage 6 — poll until the server finished load, rode the travel, and the child re-resolved AND CONVERGED on the
    // MOVED transform (proves DoApply_SavedTransforms' pure-ECS mover completed, not just Construct re-derivation).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            if (Server == nullptr || Server == GTransform_PreServerWorld.Get() || !Server->HasBegunPlay()) { return false; }
            if (Transform_MapNameOf(Server) != Transform_MapPath) { return false; }
            auto* Sub = Transform_Subsystem(Server);
            if (Sub == nullptr || Sub->Get_IsLoadInProgress()) { return false; }

            auto Resolved = false;
            const auto Xf = Transform_ChildWorldTransform(Server, Resolved);
            return Resolved && Xf.Equals(Transform_MovedXf, Transform_Tolerance);
        }),
        ReloadTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPostReconnect));

    // Stage 7 — SERVER parity assertion: the pure-ECS entity's WORLD transform survived save -> seamless reload ->
    // DoApply_SavedTransforms (NOT the Identity Construct default).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            if (Server == nullptr) { AddError(TEXT("Stage 7: no post-travel server world")); return false; }

            auto Resolved = false;
            const auto Xf = Transform_ChildWorldTransform(Server, Resolved);
            TestTrue(TEXT("child re-resolves on the server post-reload"), Resolved);
            if (NOT Resolved) { return false; }

            AddInfo(FString::Printf(TEXT("DIAG Transform parity: restored child at %s (moved %s)"),
                *Xf.ToString(), *Transform_MovedXf.ToString()));

            TestTrue(TEXT("child transform round-tripped (MOVED, not Identity Construct default)"),
                Xf.Equals(Transform_MovedXf, Transform_Tolerance));
            TestTrue(TEXT("child is NOT at Identity (Construct-default would leave it there)"),
                NOT Xf.Equals(FTransform::Identity, Transform_Tolerance));
            return true;
        }),
        TEXT("Transform parity: pure-ECS RuntimeSpawned world transform survives save -> seamless reload -> DoApply")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
