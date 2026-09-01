// The debug snapshot boundary.
//
// A snapshot exists so a viewer can draw a bake without holding anything that produced it. The
// assertions here are about that boundary — that the copy is complete, that capping the drawn cells
// does not corrupt the reported counts, and that a viewer can tell an empty region from a failed one.

#include "CkGroundNav/Bake/CkGroundNav_Clearance.h"
#include "CkGroundNav/Bake/CkGroundNav_Plates.h"
#include "CkGroundNav/Bake/CkGroundNav_Rasterize.h"
#include "CkGroundNav/Debug/CkGroundNav_DebugSnapshot.h"

#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_snapshot
{
    using ck::groundnav::DoCompute_Clearance;
    using ck::groundnav::DoDecompose_Plates;
    using ck::groundnav::DoExtract_Layers;
    using ck::groundnav::DoFilter_Walkability;
    using ck::groundnav::DoRasterizeSpans;
    using ck::groundnav::EDebugSnapshotStatus;
    using ck::groundnav::FCk_GroundNav_ClearanceField;
    using ck::groundnav::FCk_GroundNav_ConnectionField;
    using ck::groundnav::FCk_GroundNav_DebugSnapshot;
    using ck::groundnav::FCk_GroundNav_LayerField;
    using ck::groundnav::FCk_GroundNav_PlateField;
    using ck::groundnav::FCk_GroundNav_SpanField;
    using ck::groundnav::Make_DebugSnapshot;

    constexpr auto kCellSize = 25.0f;

    // Two floors over one footprint, so the snapshot has to carry more than one layer and the cells
    // of each have to keep their own layer index.
    auto Make_TwoStoreySnapshot(int32 InMaxCells, int32& OutWalkableSpans, int32& OutPlates)
        -> FCk_GroundNav_DebugSnapshot
    {
        auto Geometry = FCk_GroundNav_GeometryBatch{};
        Geometry.Add_Box(FBox{FVector{0.0, 0.0, 0.0}, FVector{500.0, 500.0, 10.0}});
        Geometry.Add_Box(FBox{FVector{0.0, 0.0, 300.0}, FVector{500.0, 500.0, 310.0}});

        const auto Region = FBox{FVector{0.0, 0.0, -50.0}, FVector{500.0, 500.0, 600.0}};

        auto Profile = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{70.0f, 20.0f}}};
        Profile.Set_LedgeSensitivity(0.0f);

        auto Spans = FCk_GroundNav_SpanField{};
        DoRasterizeSpans(Geometry, Region, FCk_GroundNav_BakeConfig{kCellSize, 10.0f}, Profile, Spans);

        auto Connections = FCk_GroundNav_ConnectionField{};
        DoFilter_Walkability(Profile, Spans, Connections);

        auto Layers = FCk_GroundNav_LayerField{};
        DoExtract_Layers(Spans, Connections, Layers);

        auto Clearance = FCk_GroundNav_ClearanceField{};
        DoCompute_Clearance(Layers, kCellSize, Clearance);

        auto Plates = FCk_GroundNav_PlateField{};
        DoDecompose_Plates(Spans, Layers, FCk_GroundNav_MergeTunables{}, Plates);

        OutWalkableSpans = Layers.Get_AssignedSpanCount();
        OutPlates = Plates._Plates.Num();

        return Make_DebugSnapshot(Spans, Layers, Clearance, Plates, Region, InMaxCells);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Snapshot_CarriesTheWholeBake,
    "CkTests.UnitTests.CkGroundNav.Bake.Snapshot_CarriesTheWholeBake",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Snapshot_CarriesTheWholeBake::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_snapshot;

    auto WalkableSpans = 0;
    auto PlateCount = 0;

    const auto Snapshot = Make_TwoStoreySnapshot(TNumericLimits<int32>::Max(), WalkableSpans, PlateCount);

    TestTrue(TEXT("a completed bake snapshots as drawable"), Snapshot.Get_IsDrawable());
    TestEqual(TEXT("status is Current"), Snapshot._Status, EDebugSnapshotStatus::Current);

    TestEqual(TEXT("every walkable cell reaches the snapshot"),
        Snapshot._Cells.Num(), WalkableSpans);

    TestEqual(TEXT("and the reported count agrees"),
        Snapshot._WalkableCellCount, WalkableSpans);

    TestEqual(TEXT("every plate reaches it too"), Snapshot.Get_PlateCount(), PlateCount);

    TestEqual(TEXT("both storeys are represented"), Snapshot._LayerCount, 2);
    TestFalse(TEXT("nothing was capped"), Snapshot._CellsWereTruncated);

    // Cells arrive in world space, already positioned. A viewer that had to reconstruct this from a
    // lattice index would need the span field, which is exactly what the snapshot exists to avoid.
    auto LowCells = 0;
    auto HighCells = 0;

    for (const auto& Cell : Snapshot._Cells)
    {
        if (NOT Snapshot._Region.IsInsideOrOn(Cell._SurfaceCentre))
        {
            AddError(FString::Printf(TEXT("cell at %s falls outside the snapshot region"),
                *Cell._SurfaceCentre.ToString()));
            return false;
        }

        if (FMath::IsNearlyEqual(Cell._SurfaceCentre.Z, 10.0, 1.0))
        { ++LowCells; }

        if (FMath::IsNearlyEqual(Cell._SurfaceCentre.Z, 310.0, 1.0))
        { ++HighCells; }
    }

    TestEqual(TEXT("the ground floor sits at its own height"), LowCells, 20 * 20);
    TestEqual(TEXT("and the upper floor at its own"), HighCells, 20 * 20);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Snapshot_CappingCellsKeepsCountsExact,
    "CkTests.UnitTests.CkGroundNav.Bake.Snapshot_CappingCellsKeepsCountsExact",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Snapshot_CappingCellsKeepsCountsExact::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_snapshot;

    auto WalkableSpans = 0;
    auto PlateCount = 0;

    constexpr auto Cap = 50;

    const auto Snapshot = Make_TwoStoreySnapshot(Cap, WalkableSpans, PlateCount);

    TestEqual(TEXT("the drawn cells are capped"), Snapshot._Cells.Num(), Cap);
    TestTrue(TEXT("and the snapshot says so"), Snapshot._CellsWereTruncated);

    // The whole point of the flag: a capped snapshot still reports what the bake actually found, so a
    // viewer never reads a draw budget as a smaller world.
    TestEqual(TEXT("but the reported total is still the true total"),
        Snapshot._WalkableCellCount, WalkableSpans);

    TestTrue(TEXT("and the cap is genuinely smaller than that total"), Cap < WalkableSpans);

    TestEqual(TEXT("plates are not capped with the cells"), Snapshot.Get_PlateCount(), PlateCount);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Snapshot_EveryStatusIsNameable,
    "CkTests.UnitTests.CkGroundNav.Bake.Snapshot_EveryStatusIsNameable",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Snapshot_EveryStatusIsNameable::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_snapshot;

    // A default snapshot must not read as an empty world. This is the distinction that keeps a
    // viewer from reporting "no floor here" when the truth is "the bake never ran".
    const auto Untouched = FCk_GroundNav_DebugSnapshot{};

    TestEqual(TEXT("a snapshot nobody filled in is NeverBuilt"),
        Untouched._Status, EDebugSnapshotStatus::NeverBuilt);

    TestFalse(TEXT("and is not drawable"), Untouched.Get_IsDrawable());

    const EDebugSnapshotStatus AllStatuses[] = {
        EDebugSnapshotStatus::NeverBuilt,
        EDebugSnapshotStatus::BackendUnavailable,
        EDebugSnapshotStatus::NoGeometryInRegion,
        EDebugSnapshotStatus::Failed,
        EDebugSnapshotStatus::Current};

    for (const auto& Status : AllStatuses)
    {
        const auto Name = FString{ck::groundnav::Get_StatusName(Status)};

        if (NOT Name.IsEmpty() && Name != TEXT("Unknown"))
        { continue; }

        AddError(FString::Printf(TEXT("status %d has no name, so a viewer cannot report it"),
            static_cast<int32>(Status)));
        return false;
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
