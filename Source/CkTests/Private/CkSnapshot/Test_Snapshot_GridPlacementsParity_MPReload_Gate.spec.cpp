// CkSnapshot 2dGridPlacements-Parity GATE — a grid + occupant placement riding the actor-bridged REPLICATED
// top-level entity survives a listen-server SEAMLESS ServerTravel reload, asserted on BOTH worlds. The grid
// subject's Construct adds a Ck2dGridSystem directly on the bridged InHandle plus a 1x1 GridObject occupant;
// the server stamps a placement at a NON-DEFAULT cell pre-save; post-reload both worlds must report that cell
// Occupied — proving:
//   - the restored server re-composed the grid's PRIVATE nested cell registry: the snapshot can never capture
//     the live FFragment_2dGridSystem_Current's TUniquePtr<FEcsWorld>, so the bridged actor's Construct RE-RUNS
//     on load and re-composes it (the grid carries its compose-only debug name post-travel),
//   - the grid's placement RECORD — NOT re-created by Construct (it was a runtime Request_AddPlacement) — is
//     rebuilt on the AUTHORITY host by the 2dGridOccupancy Apply handler's load-hydration branch, which
//     re-drives Request_AddPlacement per restored payload entry (occupant handle remapped through
//     FSnapshotContext; a save-transient occupant restores invalid, tolerated by design),
//   - Request_AddPlacement re-arms MayRequireReplication so the AuthorityOnly Replicate pass pushes the rebuilt
//     set and the fresh post-travel client converges through the ordinary placement-record SyncReplication path.
//
// History: this gate was long documented as a "latent engine death" (the editor self-terminating ~4s into the
// post-travel ECS boot). That no longer reproduces — the controlled teardown-drain before travel mitigated it.
// The remaining failure was a restore-logic gap (no authority-side occupancy re-drive), fixed by the Apply
// hydration branch above. Its registry-level round-trip twin was removed with Model A, so this parity spec is
// now the only grid save/load coverage.
//
// Surface in Session Frontend: Ck.Snapshot.Parity.GridPlacements_MPReload

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Engine/GameInstance.h"
#include "EngineUtils.h"               // TActorIterator
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel

#include "CkGrid/2dGridSystem/Grid/Ck2dGridSystem_Utils.h"
#include "CkGrid/2dGridSystem/Occupancy/Ck2dGridOccupancy_Utils.h"

#include "CkCore/Enums/CkEnums.h"      // ECk_CardinalRotation

#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/OwningActor/CkOwningActor_Utils.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "CkTests/Net/CkAutoTest_NetSubject_Grid.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

namespace
{
    constexpr auto GridParity_MapPath    = TEXT("/Engine/Maps/Entry");
    const auto     GridParity_SlotName   = FName{TEXT("CkSnapshot_GridParity_GateSlot")};
    const auto     GridParity_Coordinate = FIntPoint{2, 2};                  // != auto / origin
    constexpr auto GridParity_Rotation   = ECk_CardinalRotation::None;       // 1x1 occupant — rotation-invariant

    static TWeakObjectPtr<UWorld> GGridParity_PreServerWorld;
    static TWeakObjectPtr<UWorld> GGridParity_PreClientWorld;

    auto GridParity_MapNameOf(UWorld* InWorld) -> FString
    {
        return InWorld != nullptr ? InWorld->RemovePIEPrefix(InWorld->GetOutermost()->GetName()) : FString{};
    }

    auto GridParity_Subsystem(UWorld* InWorld) -> UCk_Snapshot_Subsystem_UE*
    {
        if (InWorld == nullptr || InWorld->GetGameInstance() == nullptr) { return nullptr; }
        return InWorld->GetGameInstance()->GetSubsystem<UCk_Snapshot_Subsystem_UE>();
    }

    auto GridParity_FindProbe(UWorld* InWorld) -> ACk_AutoTest_NetSubject_Grid_UE*
    {
        if (InWorld == nullptr) { return nullptr; }
        for (auto It = TActorIterator<ACk_AutoTest_NetSubject_Grid_UE>(InWorld); It; ++It) { return *It; }
        return nullptr;
    }

    // Resolve the grid through the actor's ENTITY (the grid is added directly on the bridged InHandle, not as a
    // child), NOT through the actor's _TestGrid stash — Construct RE-RUNS on the restored server world (a fresh
    // grid instance), so the stash is stale post-reload.
    auto GridParity_ResolveGrid(AActor* InProbe) -> FCk_Handle_2dGridSystem
    {
        if (InProbe == nullptr) { return {}; }
        auto Entity = UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(InProbe);
        if (ck::Is_NOT_Valid(Entity)) { return {}; }
        if (NOT UCk_Utils_2dGridSystem_UE::Has(Entity)) { return {}; }
        return UCk_Utils_2dGridSystem_UE::Cast(Entity);
    }

    // True when the world's grid reports the expected cell Occupied. A restored grid whose nested registry has
    // not (yet) been re-composed must read as "not converged", not crash.
    auto GridParity_CellOccupied(UWorld* InWorld) -> bool
    {
        auto Grid = GridParity_ResolveGrid(GridParity_FindProbe(InWorld));
        if (ck::Is_NOT_Valid(Grid)) { return false; }
        return UCk_Utils_2dGridOccupancy_UE::Get_IsOccupied(Grid, GridParity_Coordinate);
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_GridPlacementsParity_MPReload_Gate,
    "Ck.Snapshot.Parity.GridPlacements_MPReload",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_GridPlacementsParity_MPReload_Gate::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;        // server window + 1 connected client
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesPerSettle = 30;
    constexpr auto ReloadTimeoutSeconds = 60.0f;
    constexpr auto FramesPostReconnect = 60;

    GGridParity_PreServerWorld = nullptr;
    GGridParity_PreClientWorld = nullptr;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, FString{GridParity_MapPath}));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // Stage 1 — open the PIE seamless gate + spawn the replicated grid subject on the server.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
            { CVar->Set(1, ECVF_SetByCode); }

            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
            auto* Probe = InServer->SpawnActor<ACk_AutoTest_NetSubject_Grid_UE>(
                ACk_AutoTest_NetSubject_Grid_UE::StaticClass(), FTransform{FVector{100.0, 200.0, 300.0}}, SpawnInfo);
            if (Probe == nullptr) { AddError(TEXT("Stage 1: grid subject spawn returned null")); }
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 2 — pre-reload sanity: the grid resolves on BOTH worlds (Construct ran on each).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Server == nullptr || Client == nullptr) { return false; }
            return ck::IsValid(GridParity_ResolveGrid(GridParity_FindProbe(Server))) &&
                   ck::IsValid(GridParity_ResolveGrid(GridParity_FindProbe(Client)));
        }),
        ReadyTimeoutSeconds));

    // Stage 3 — server stamps a placement for its occupant at the non-default cell. The occupant + grid are
    // read from the actor stash (Construct ran live here pre-travel). Deferred request; the settle covers
    // handling + placement-record replication.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Probe = GridParity_FindProbe(InServer);
            if (Probe == nullptr) { AddError(TEXT("Stage 3: server grid subject not found")); return; }

            auto Grid     = Probe->_TestGrid;
            auto Occupant = Probe->_TestOccupant;
            if (ck::Is_NOT_Valid(Grid) || ck::Is_NOT_Valid(Occupant))
            { AddError(TEXT("Stage 3: server grid/occupant handles unresolved")); return; }

            UCk_Utils_2dGridOccupancy_UE::Request_AddPlacement(
                Grid, Occupant, GridParity_Coordinate, GridParity_Rotation,
                TArray<FIntPoint>{GridParity_Coordinate}, {});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 3b — pre-save parity on BOTH worlds (the live path must already deliver the occupancy to the
    // client — otherwise the post-reload assert wouldn't isolate the restore path).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            return GridParity_CellOccupied(ck::auto_test::net::Get_ServerWorld())
                && GridParity_CellOccupied(ck::auto_test::net::Get_ClientWorld(0));
        }),
        ReadyTimeoutSeconds));

    // Stage 4 — Save on the server; stash pre-travel worlds.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            GGridParity_PreServerWorld = InServer;
            GGridParity_PreClientWorld = ck::auto_test::net::Get_ClientWorld(0);
            auto* Sub = GridParity_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 4: no snapshot subsystem")); return; }
            Sub->Request_Save(GridParity_SlotName, FCk_Delegate_OnSaveComplete{});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 5 — fire async Load (triggers seamless ServerTravel) + assert non-blocking.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Sub = GridParity_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 5: no snapshot subsystem")); return; }
            Sub->Request_Load(GridParity_SlotName, FCk_Delegate_OnLoadComplete{});
            TestTrue(TEXT("Stage 5: Request_Load non-blocking"), Sub->Get_IsLoadInProgress());
        })));

    // Stage 6 — poll until server finished load AND client rode the travel AND the occupancy CONVERGED on the
    // client (re-drive on the server, ordinary placement-record SyncReplication to the client).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            if (Server == nullptr || Server == GGridParity_PreServerWorld.Get() || !Server->HasBegunPlay()) { return false; }
            if (GridParity_MapNameOf(Server) != GridParity_MapPath) { return false; }
            auto* Sub = GridParity_Subsystem(Server);
            if (Sub == nullptr || Sub->Get_IsLoadInProgress()) { return false; }
            if (GridParity_FindProbe(Server) == nullptr) { return false; }

            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr || Client == GGridParity_PreClientWorld.Get() || !Client->HasBegunPlay()) { return false; }
            if (GridParity_MapNameOf(Client) != GridParity_MapPath) { return false; }

            return GridParity_CellOccupied(Client);
        }),
        ReloadTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPostReconnect));

    // Stage 7 — parity assertions on BOTH worlds: the placement's occupancy survived (NOT an empty
    // Construct-default grid).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            TestTrue(TEXT("server: cell (2,2) Occupied post-reload (grid re-composed + placement re-stamped)"),
                GridParity_CellOccupied(Server));

            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr) { AddError(TEXT("Stage 7: no post-travel client world")); return false; }
            TestTrue(TEXT("client: cell (2,2) Occupied post-reload (placement round-tripped + replicated)"),
                GridParity_CellOccupied(Client));
            return true;
        }),
        TEXT("2dGridPlacements parity: grid occupancy survives save -> seamless reload -> client convergence")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
