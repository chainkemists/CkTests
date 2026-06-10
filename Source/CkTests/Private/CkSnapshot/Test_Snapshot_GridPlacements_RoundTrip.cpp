// Registry-level round-trip for the CkGrid 2dGridPlacements snapshot wiring (no UWorld / PIE).
//
// An MP parity gate is currently infeasible: a LATENT PRE-EXISTING bug silently kills the engine when a
// 2dGridSystem rides the actor-bridged entity through save + seamless travel (bisected: dies with the grid
// alone — no placements, no occupant — and dies identically on builds WITHOUT this snapshot wiring; the
// Spatial-inventory gate survives because its grids ride unreplicated CHILD entities). Until that engine
// death is fixed, this test covers the SNAPSHOT half: the grid's Tier-A params, the placement entity's
// Tier-B params (occupant/grid handles remapped through FSnapshotContext), the grid's placement record, and
// the occupant's back-ref must all survive capture -> wipe -> restore with cross-fragment handle CONSISTENCY
// (the restored record points at the restored placement; the restored placement points back at the restored
// grid + occupant). The re-drive half (RestoreRecompose + Occupancy ReplicateOnRestore) stays gate-pending.
//
// Surface in Session Frontend: Ck.Snapshot.GridPlacements.RoundTrip

#include "CkSnapshot/Snapshot/CkSnapshot_Capture.h"
#include "CkSnapshot/Snapshot/CkSnapshot_Restore.h"
#include "CkEcs/Snapshot/CkSnapshot_Context.h"
#include "CkSnapshot/SaveGame/CkSnapshot_Header.h"
#include "CkSnapshot/Snapshot/CkSnapshot_LoadReport.h"

#include "CkGrid/2dGridSystem/Grid/Ck2dGridSystem_Fragment.h"
#include "CkGrid/2dGridSystem/Occupancy/Ck2dGridOccupancy_Fragment.h"
#include "CkGrid/2dGridSystem/Placement/Ck2dGridPlacement_Fragment.h"

#include "CkEcs/World/CkEcsWorld.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"

#include "CkRecord/Record/CkRecord_Utils.h"

#include "CkCore/Macros/CkMacros.h"

#include "Serialization/BufferArchive.h"
#include "Serialization/MemoryReader.h"

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_GridPlacements_RoundTrip_Test,
    "Ck.Snapshot.GridPlacements.RoundTrip",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_GridPlacements_RoundTrip_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    // ---- Arrange: a grid entity, an occupant, and a placement connecting them -------------------------------------
    auto EcsWorld = ck::FEcsWorld{};

    auto* RawRegistry = ck::registry_table::TryResolve(EcsWorld.Get_Registry().Get_RegistryHandle());
    if (NOT TestNotNull(TEXT("Resolved raw entt registry from FEcsWorld"), RawRegistry))
    { return false; }

    auto GridEntity     = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(EcsWorld.Get_Registry());
    auto OccupantEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(EcsWorld.Get_Registry());
    auto PlacementEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(EcsWorld.Get_Registry());

    // Grid params: every persisted field NON-DEFAULT so a silent serialize-nothing regression
    // (the Tier-A inert-marker trap) cannot pass. The LIVE half (Current) is deliberately absent —
    // exactly the shape a restore produces before RestoreRecompose runs.
    auto SavedGridParams = FCk_Fragment_2dGridSystem_ParamsData{FIntPoint{7, 3}, FVector2D{50.0, 25.0}};
    SavedGridParams.Set_DefaultCellState(ECk_EnableDisable::Disable);
    SavedGridParams.Set_ExceptionCoordinates(TArray<FIntPoint>{{1, 1}});
    SavedGridParams.Set_Pivot(FTransform{FVector{10.0, 20.0, 30.0}});
    GridEntity.Add<ck::FFragment_2dGridSystem_Params>(SavedGridParams);

    const auto GridTyped = ck::StaticCast<FCk_Handle_2dGridSystem>(GridEntity);

    // Placement params: occupant + grid HANDLES (the Tier-B remap under test) + non-default values.
    const auto SavedAnchor   = FIntPoint{2, 1};
    const auto SavedCells    = TArray<FIntPoint>{{2, 1}, {3, 1}};
    constexpr auto SavedRotation = ECk_CardinalRotation::Half;

    auto PlacementParams = ck::FFragment_2dGridPlacement_Params{OccupantEntity, GridTyped, SavedAnchor, SavedCells};
    PlacementParams.Set_Rotation(SavedRotation);
    PlacementEntity.Add<ck::FFragment_2dGridPlacement_Params>(PlacementParams);

    auto PlacementTyped = ck::StaticCast<FCk_Handle_2dGridPlacement>(PlacementEntity);

    // Record + back-ref, mirroring what Request_AddPlacement wires up.
    ck::RecordOf_GridPlacements_Utils::AddIfMissing(GridEntity);
    ck::RecordOf_GridPlacements_Utils::Request_Connect(GridEntity, PlacementTyped, ECk_Record_LabelRequirementPolicy::Optional);
    OccupantEntity.Add<ck::FFragment_2dGridOccupant_PlacementRef>(PlacementTyped);

    // ---- Act: capture -> (registry is wiped by restore) -> restore ------------------------------------------------
    auto Buffer = FBufferArchive{};
    auto Header = FCk_Snapshot_Header{};

    const auto CaptureResult = ck::snapshot::Run_Capture_Registry(*RawRegistry, Buffer, Header);
    if (NOT TestEqual(TEXT("Capture result is Success"),
            static_cast<uint8>(CaptureResult), static_cast<uint8>(ECk_SnapshotResult::Success)))
    { return false; }

    auto Reader = FMemoryReader{Buffer, /*bIsPersistent=*/true};
    const auto Report = ck::snapshot::Run_Restore_Registry(*RawRegistry, Reader, Header);

    TestEqual(TEXT("Restore result is Success"),
        static_cast<uint8>(Report.Get_Result()), static_cast<uint8>(ECk_SnapshotResult::Success));

    // ---- Assert: grid params round-tripped (Tier-A with real SaveGame specifiers) ---------------------------------
    auto RestoredGrid = FCk_Handle{};
    {
        auto GridCount = 0;
        auto GridView = RawRegistry->view<ck::FFragment_2dGridSystem_Params>();

        for (const auto E : GridView)
        {
            ++GridCount;
            const auto& Restored = GridView.get<ck::FFragment_2dGridSystem_Params>(E);

            TestEqual(TEXT("Dimensions round-tripped (7x3)"), Restored.Get_Dimensions(), FIntPoint(7, 3));
            TestEqual(TEXT("CellSize round-tripped (50x25)"), Restored.Get_CellSize(), FVector2D(50.0, 25.0));
            TestTrue(TEXT("DefaultCellState round-tripped (Disable, not the Enable default)"),
                Restored.Get_DefaultCellState() == ECk_EnableDisable::Disable);
            TestEqual(TEXT("ExceptionCoordinates round-tripped"),
                Restored.Get_ExceptionCoordinates(), TArray<FIntPoint>{{1, 1}});
            TestTrue(TEXT("Pivot translation round-tripped"),
                Restored.Get_Pivot().GetTranslation().Equals(FVector(10.0, 20.0, 30.0)));

            RestoredGrid = FCk_Handle{FCk_Entity{E}, EcsWorld.Get_Registry().Get_RegistryHandle()};
        }

        TestEqual(TEXT("Exactly one entity carries the grid params post-restore"), GridCount, 1);
    }

    // ---- Assert: placement params round-tripped with REMAPPED handles ---------------------------------------------
    auto RestoredPlacement = FCk_Handle{};
    {
        auto PlacementCount = 0;
        auto PlacementView = RawRegistry->view<ck::FFragment_2dGridPlacement_Params>();

        for (const auto E : PlacementView)
        {
            ++PlacementCount;
            const auto& Restored = PlacementView.get<ck::FFragment_2dGridPlacement_Params>(E);

            TestEqual(TEXT("Anchor round-tripped"), Restored.Get_Anchor(), SavedAnchor);
            TestTrue(TEXT("Rotation round-tripped (Half, not the None default)"),
                Restored.Get_Rotation() == SavedRotation);
            TestEqual(TEXT("Cells round-tripped"), Restored.Get_Cells(), SavedCells);

            // Handle-remap consistency: the restored placement's grid handle must point at the SAME
            // entity that carries the restored grid params (not a stale save-time id). NOTE: id-based
            // comparisons throughout — the registry-only restore path has no live load target, so
            // restored handles deliberately keep an UNSET registry slot (ck::IsValid false by design);
            // the LIVE path re-homes them (FSnapshotContext + Set_Registry, proven by the MPReload gates).
            TestTrue(TEXT("Placement's grid handle remapped onto the restored grid entity"),
                Restored.Get_Grid().Get_Entity() == RestoredGrid.Get_Entity());

            RestoredPlacement = FCk_Handle{FCk_Entity{E}, EcsWorld.Get_Registry().Get_RegistryHandle()};
        }

        TestEqual(TEXT("Exactly one entity carries the placement params post-restore"), PlacementCount, 1);
    }

    // ---- Assert: the grid's record + the occupant's back-ref point at the restored placement ----------------------
    // Get_Entries (NOT Get_ValidEntries): the valid-filter requires re-homed registries, which the
    // registry-only restore path deliberately leaves unset — id comparison is the contract here.
    {
        const auto& Entries = ck::RecordOf_GridPlacements_Utils::Get_Entries(RestoredGrid);
        TestEqual(TEXT("Restored grid's placement record has exactly one entry"), Entries.Num(), 1);
        if (Entries.Num() == 1)
        {
            TestTrue(TEXT("Record entry remapped onto the restored placement entity"),
                Entries[0].Get_Entity() == RestoredPlacement.Get_Entity());
        }
    }

    {
        auto BackRefCount = 0;
        auto BackRefView = RawRegistry->view<ck::FFragment_2dGridOccupant_PlacementRef>();

        for (const auto E : BackRefView)
        {
            ++BackRefCount;
            const auto& Restored = BackRefView.get<ck::FFragment_2dGridOccupant_PlacementRef>(E);
            TestTrue(TEXT("Occupant back-ref remapped onto the restored placement entity"),
                Restored.Get_Placement().Get_Entity() == RestoredPlacement.Get_Entity());
        }

        TestEqual(TEXT("Exactly one entity carries the occupant back-ref post-restore"), BackRefCount, 1);
    }

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
