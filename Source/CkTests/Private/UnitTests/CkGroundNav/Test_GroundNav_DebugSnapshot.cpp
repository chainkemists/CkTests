// The debug snapshot boundary.
//
// A snapshot exists so a viewer can draw a bake without holding anything that produced it. The
// assertions here are about that boundary — that the copy is complete, that capping the drawn cells
// does not corrupt the reported counts, and that a viewer can tell an empty region from a failed one.

#include "CkGroundNav/Bake/CkGroundNav_Clearance.h"
#include "CkGroundNav/Bake/CkGroundNav_Plates.h"
#include "CkGroundNav/Bake/CkGroundNav_Portals.h"
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
    using ck::groundnav::DoExtract_Portals;
    using ck::groundnav::DoFilter_Walkability;
    using ck::groundnav::DoRasterizeSpans;
    using ck::groundnav::EDebugSnapshotStatus;
    using ck::groundnav::FCk_GroundNav_ClearanceField;
    using ck::groundnav::FCk_GroundNav_ConnectionField;
    using ck::groundnav::FCk_GroundNav_DebugLink;
    using ck::groundnav::FCk_GroundNav_DebugSnapshot;
    using ck::groundnav::FCk_GroundNav_LayerField;
    using ck::groundnav::FCk_GroundNav_PlateField;
    using ck::groundnav::FCk_GroundNav_PortalField;
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
        DoCompute_Clearance(Layers, Connections, kCellSize, Clearance);

        auto Plates = FCk_GroundNav_PlateField{};
        DoDecompose_Plates(Spans, Layers, FCk_GroundNav_MergeTunables{}, Plates);

        auto Portals = FCk_GroundNav_PortalField{};
        DoExtract_Portals(Spans, Layers, Connections, Plates, Clearance, Portals);

        OutWalkableSpans = Layers.Get_AssignedSpanCount();
        OutPlates = Plates._Plates.Num();

        return Make_DebugSnapshot(Spans, Layers, Clearance, Plates, Portals, Region, InMaxCells);
    }

    // --------------------------------------------------------------------------------------------------

    constexpr auto kDisabledLinkId = 3;
    constexpr auto kUnresolvedLinkId = 11;

    const auto kLadderFoot = FVector{100.0, 200.0, 0.0};
    const auto kLadderTop = FVector{100.0, 200.0, 400.0};
    const auto kOverTheHole = FVector{900.0, 900.0, 0.0};

    // Resolved at both ends and switched off by its author. A viewer must not read this as missing
    // ground: the two are fixed in entirely different places, and one of them cannot be fixed at all.
    auto Make_DisabledLink() -> FCk_GroundNav_DebugLink
    {
        auto Link = FCk_GroundNav_DebugLink{};

        Link._Start = kLadderFoot;
        Link._End = kLadderTop;
        Link._AreaTagName = FName{TEXT("Nav.Area.Ladder")};
        Link._UserTypeTagName = FName{TEXT("Nav.Link.Ladder")};
        Link._Id = kDisabledLinkId;
        Link._StartFlatPlate = 4;
        Link._EndFlatPlate = 9;
        Link._CostMultiplierForward = 2.5f;
        Link._CostMultiplierBackward = 1.25f;
        Link._ClearanceUu = 45.0f;
        Link._Direction = ECk_GroundNav_LinkDirection::Bidirectional;
        Link._StartStatus = ECk_NavSurface_QueryStatus::Success;
        Link._EndStatus = ECk_NavSurface_QueryStatus::Success;
        Link._Enabled = false;
        Link._Live = false;

        return Link;
    }

    // One end with no ground under it. The authored record is HELD either way, so the snapshot carries
    // the failure as a per-end status rather than by leaving the link out - a link nobody drew and a
    // link nobody authored look identical, and those are the two a viewer must tell apart.
    auto Make_UnresolvedLink() -> FCk_GroundNav_DebugLink
    {
        auto Link = FCk_GroundNav_DebugLink{};

        Link._Start = kLadderFoot;
        Link._End = kOverTheHole;
        Link._AreaTagName = FName{TEXT("Nav.Area.Drop")};
        Link._Id = kUnresolvedLinkId;
        Link._StartFlatPlate = 4;
        Link._Direction = ECk_GroundNav_LinkDirection::Forward;
        Link._StartStatus = ECk_NavSurface_QueryStatus::Success;
        Link._EndStatus = ECk_NavSurface_QueryStatus::NoSurface;
        Link._Enabled = true;
        Link._Live = false;

        return Link;
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

    // Two floors with no way between them. A portal here would mean the snapshot invented a route,
    // and a route the world does not have is the one error a path consumer cannot detect for itself.
    TestEqual(TEXT("and nothing claims to cross between them"), Snapshot.Get_PortalCount(), 0);
    TestEqual(TEXT("so the tightest crossing reads as none"), Snapshot.Get_NarrowestPortalUu(), 0.0f);

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
    FCkTest_GroundNav_Snapshot_CellCountCannotExceedTheLattice,
    "CkTests.UnitTests.CkGroundNav.Bake.Snapshot_CellCountCannotExceedTheLattice",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Snapshot_CellCountCannotExceedTheLattice::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_snapshot;

    auto WalkableSpans = 0;
    auto PlateCount = 0;

    const auto Snapshot = Make_TwoStoreySnapshot(TNumericLimits<int32>::Max(), WalkableSpans, PlateCount);

    TestTrue(TEXT("the snapshot reports the lattice it was built on"),
        Snapshot._LatticeSizeX > 0 && Snapshot._LatticeSizeY > 0);

    // The lattice is a function of the region and the cell size and nothing else, so a mismatch here
    // means the field was built against different bounds than the ones the snapshot reports — which
    // would make every world-space position it carries wrong by the same amount.
    // CeilToInt on a double widens to int64, which makes TestEqual ambiguous against the int32 the
    // field actually holds — narrow here rather than at each call site.
    const auto ExpectedSizeX = static_cast<int32>(
        FMath::CeilToInt(Snapshot._Region.GetSize().X / Snapshot._CellSizeUu));
    const auto ExpectedSizeY = static_cast<int32>(
        FMath::CeilToInt(Snapshot._Region.GetSize().Y / Snapshot._CellSizeUu));

    TestEqual(TEXT("lattice width follows the region and the cell size"),
        Snapshot._LatticeSizeX, ExpectedSizeX);
    TestEqual(TEXT("lattice height does too"),
        Snapshot._LatticeSizeY, ExpectedSizeY);

    // One surface per column per layer is the whole premise of a layered field: a count above that
    // ceiling is not a big bake, it is a count of something other than cells, and every per-cell
    // figure derived from it (the plate collapse ratio) is wrong by the same factor.
    const auto CellSlots = Snapshot._LatticeSizeX * Snapshot._LatticeSizeY * Snapshot._LayerCount;

    if (Snapshot._WalkableCellCount > CellSlots)
    {
        AddError(FString::Printf(
            TEXT("reported %d walkable cells on a %d x %d lattice of %d layer(s), which holds at most %d"),
            Snapshot._WalkableCellCount, Snapshot._LatticeSizeX, Snapshot._LatticeSizeY,
            Snapshot._LayerCount, CellSlots));
        return false;
    }

    TestTrue(TEXT("the drawn cells never outnumber the counted ones"),
        Snapshot._Cells.Num() <= Snapshot._WalkableCellCount);

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

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Snapshot_CarriesLinksAsValuesOnly,
    "CkTests.UnitTests.CkGroundNav.Bake.Snapshot_CarriesLinksAsValuesOnly",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Snapshot_CarriesLinksAsValuesOnly::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_snapshot;

    auto Survivor = FCk_GroundNav_DebugSnapshot{};

    {
        auto Producer = MakeUnique<FCk_GroundNav_DebugSnapshot>();

        Producer->_Status = EDebugSnapshotStatus::Current;
        Producer->_Links.Emplace(Make_DisabledLink());
        Producer->_Links.Emplace(Make_UnresolvedLink());

        Survivor = *Producer;

        Producer.Reset();
    }

    // Everything below reads a snapshot whose producer no longer exists. If anything a link carries
    // reached back into it - a handle, a field pointer, a tag looked up on demand - the copy would be
    // reading a corpse, which is exactly what a viewer drawing a frame later would be doing.
    if (NOT TestEqual(TEXT("both links survive their producer"), Survivor._Links.Num(), 2))
    { return false; }

    const auto& Disabled = Survivor._Links[0];

    TestEqual(TEXT("the disabled link keeps its id"), Disabled._Id, kDisabledLinkId);
    TestTrue(TEXT("and its endpoints"),
        Disabled._Start == kLadderFoot && Disabled._End == kLadderTop);
    TestEqual(TEXT("and its area tag, as a name"),
        Disabled._AreaTagName, FName{TEXT("Nav.Area.Ladder")});
    TestEqual(TEXT("and its user type tag"),
        Disabled._UserTypeTagName, FName{TEXT("Nav.Link.Ladder")});
    TestEqual(TEXT("and the plate its start resolved to"), Disabled._StartFlatPlate, 4);
    TestEqual(TEXT("and the plate its end resolved to"), Disabled._EndFlatPlate, 9);
    TestEqual(TEXT("and what it costs forward"), Disabled._CostMultiplierForward, 2.5f);
    TestEqual(TEXT("and backward"), Disabled._CostMultiplierBackward, 1.25f);
    TestEqual(TEXT("and the clearance it admits"), Disabled._ClearanceUu, 45.0f);
    TestEqual(TEXT("and which ways it may be walked"),
        Disabled._Direction, ECk_GroundNav_LinkDirection::Bidirectional);

    // Both ends found ground: a viewer reading this as unresolved would send a developer looking for
    // a hole in the world instead of at the switch that is actually off.
    TestEqual(TEXT("its start end resolved"),
        Disabled._StartStatus, ECk_NavSurface_QueryStatus::Success);
    TestEqual(TEXT("and so did its far end"),
        Disabled._EndStatus, ECk_NavSurface_QueryStatus::Success);

    TestFalse(TEXT("and it reads as switched off"), Disabled._Enabled);
    TestFalse(TEXT("and therefore not live"), Disabled._Live);

    const auto& Unresolved = Survivor._Links[1];

    TestEqual(TEXT("the unresolved link keeps its id too"), Unresolved._Id, kUnresolvedLinkId);
    TestTrue(TEXT("and the endpoints its AUTHOR gave it, not what they resolved to"),
        Unresolved._Start == kLadderFoot && Unresolved._End == kOverTheHole);
    TestEqual(TEXT("its start still landed on a plate"), Unresolved._StartFlatPlate, 4);

    // The far end is the whole of the case: no ground, so no plate, and a status saying which of the
    // two reasons it is - ground that is missing rather than ground nobody has baked.
    TestEqual(TEXT("its far end found no ground"),
        Unresolved._EndStatus, ECk_NavSurface_QueryStatus::NoSurface);
    TestTrue(TEXT("so it resolved to no plate"), Unresolved._EndFlatPlate == INDEX_NONE);

    TestTrue(TEXT("and it is enabled, which is a different thing from resolved"), Unresolved._Enabled);
    TestFalse(TEXT("and not live, because a link that did not resolve is not there"), Unresolved._Live);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
