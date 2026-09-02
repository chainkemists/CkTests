// Walking a body along the ground, and the one guarantee every grounded agent's transform rests on.
//
// The walk is the single transform writer for grounded agents, so the property that matters is not
// where any one move ends but that NO move ever ends anywhere else: on Success the answering cell is
// admitted and the location lies inside that cell's closed square at that cell's surface height. That
// is pinned over ten thousand seeded moves at two radii rather than over a handful of hand-picked
// ones, because a move that leaks through a corner, off a ledge or across a seam is exactly what a
// hand-picked set does not contain. The remaining tests pin the shape of the walk around it: a concave
// corner terminates in two slides instead of oscillating, a move inside one plate is answered without
// stepping a cell, a walk crosses tiles, a start that is not on the surface is a STATUS and never a
// walk that went nowhere, and a walk into a wall stops at its face.

#include "CkGroundNav/CkGroundNav_Log.h"
#include "CkGroundNav/Query/CkGroundNav_QueryCore.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Projection.h"
#include "CkGroundNav/Query/CkGroundNav_Query_SurfaceWalk.h"

#include "../CkUnitTest_Common.h"

#include "Test_GroundNav_QueryFixtures.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_query_surfacewalk
{
    using ck::groundnav::FCk_GroundNav_CellAddress;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_IsNavigableQuery;
    using ck::groundnav::FCk_GroundNav_Plate;
    using ck::groundnav::FCk_GroundNav_ProjectionQuery;
    using ck::groundnav::FCk_GroundNav_SurfaceRef;
    using ck::groundnav::FCk_GroundNav_SurfaceWalkDiagnostics;
    using ck::groundnav::FCk_GroundNav_SurfaceWalkQuery;
    using ck::groundnav::FCk_GroundNav_SurfaceWalkResult;
    using ck::groundnav::Get_CellMinXY;
    using ck::groundnav::Get_CellsPerTile;
    using ck::groundnav::Get_IsNavigable;
    using ck::groundnav::Get_MoveAlongSurface;
    using ck::groundnav::Get_ProjectPoint;
    using ck::groundnav::Get_SurfaceAt;

    // The containment guarantee is exact by construction, so the only slack allowed is the gap between
    // the float a tile stores and the double this test computes from it.
    constexpr auto kContainmentTolerance = 1.0e-3;

    // Comfortably more than one cell height, so a start taken straight off a surface resolves to that
    // surface and to nothing else.
    constexpr auto kStartTolerance = 20.0f;

    constexpr auto kMoveCount = 10000;
    constexpr auto kPointSeed = 20260902;
    constexpr auto kOffsetSeed = 91117;

    // Most of a tile of travel in the worst case, so the sample contains moves that cross seams, walk
    // into the wall, run off the hole's rim and leave the field, not merely per-frame nudges.
    constexpr auto kOffsetExtentUu = 600.0f;

    // The projection that turns a random point in the slab into a place a body is actually standing.
    constexpr auto kStartSearchExtentUu = 100.0f;
    constexpr auto kStartSearchReachUu = 300.0f;

    // ----------------------------------------------------------------------------------------------------------------

    auto Make_Projection(
        const FVector& InLocation,
        float          InRadiusUu) -> FCk_GroundNav_ProjectionQuery
    {
        auto Query = FCk_GroundNav_ProjectionQuery{};

        Query._Location = InLocation;
        Query._HorizontalExtentUu = kStartSearchExtentUu;
        Query._UpExtentUu = kStartSearchReachUu;
        Query._DownExtentUu = kStartSearchReachUu;
        Query._Mode = ECk_NavSurface_ProjectionMode::Closest;
        Query._Agent._RadiusUu = InRadiusUu;

        return Query;
    }

    auto Make_Walk(
        const FVector& InStart,
        const FVector& InTarget,
        float          InRadiusUu) -> FCk_GroundNav_SurfaceWalkQuery
    {
        auto Query = FCk_GroundNav_SurfaceWalkQuery{};

        Query._Start = InStart;
        Query._Target = InTarget;
        Query._StartVerticalToleranceUu = kStartTolerance;
        Query._Agent._RadiusUu = InRadiusUu;

        return Query;
    }

    auto Make_ColumnQuery(
        const FVector& InLocation,
        float          InRadiusUu) -> FCk_GroundNav_IsNavigableQuery
    {
        auto Query = FCk_GroundNav_IsNavigableQuery{};

        Query._Location = InLocation;
        Query._VerticalToleranceUu = kStartTolerance;
        Query._Agent._RadiusUu = InRadiusUu;

        return Query;
    }

    auto Get_StatusName(
        ECk_NavSurface_QueryStatus InStatus) -> const TCHAR*
    {
        switch (InStatus)
        {
            case ECk_NavSurface_QueryStatus::Success:    return TEXT("Success");
            case ECk_NavSurface_QueryStatus::NoSurface:  return TEXT("NoSurface");
            case ECk_NavSurface_QueryStatus::Unbuilt:    return TEXT("Unbuilt");
            case ECk_NavSurface_QueryStatus::Blocked:    return TEXT("Blocked");
            case ECk_NavSurface_QueryStatus::NoProvider: return TEXT("NoProvider");
            default:                                     return TEXT("Unrecognised");
        }
    }

    // ----------------------------------------------------------------------------------------------------------------

    /**
     * The escape check: everything Get_MoveAlongSurface promises about where a move may end.
     *
     * The answering cell has to exist and be admitted — by its own clearance, or by being the start
     * cell, which a body is already standing in — and the location has to lie inside that cell's
     * CLOSED square at that cell's surface height. Anything else is a body outside the walkable set,
     * whatever the status said about it.
     */
    auto Get_IsOnWalkableSet(
        const FCk_GroundNav_Field&             InField,
        const FCk_GroundNav_SurfaceWalkResult& InResult,
        const FCk_GroundNav_SurfaceRef&        InStartSurface,
        float                                  InRadiusUu) -> bool
    {
        if (InResult._Status != ECk_NavSurface_QueryStatus::Success)
        { return false; }

        if (NOT InResult._Surface.Get_IsValid())
        { return false; }

        if (NOT InField._Tiles.IsValidIndex(InResult._Surface._TileIndex))
        { return false; }

        const auto Address = FCk_GroundNav_CellAddress{
            InResult._Surface._TileIndex, InResult._Surface._CellX, InResult._Surface._CellY};

        auto Surface = FCk_GroundNav_SurfaceRef{};
        auto SurfaceZ = 0.0f;
        auto Clearance = 0.0f;

        if (NOT Get_SurfaceAt(InField, Address, InResult._Surface._LayerIndex, Surface, SurfaceZ, Clearance))
        { return false; }

        const auto AdmitsTheBody =
            InRadiusUu <= 0.0f ||
            Clearance >= InRadiusUu ||
            InResult._Surface == InStartSurface;

        if (NOT AdmitsTheBody)
        { return false; }

        const auto& Tile = InField._Tiles[InResult._Surface._TileIndex];
        const auto CellsPerTile = Get_CellsPerTile(InField._Params);

        const auto FieldCell = FIntPoint{
            (Tile._Coord._X * CellsPerTile) + InResult._Surface._CellX,
            (Tile._Coord._Y * CellsPerTile) + InResult._Surface._CellY};

        const auto CellMin = Get_CellMinXY(InField._Params, FieldCell);
        const auto CellSize = static_cast<double>(Tile._CellSizeUu);

        const auto InsideTheCell =
            InResult._Location.X >= CellMin.X - kContainmentTolerance &&
            InResult._Location.X <= CellMin.X + CellSize + kContainmentTolerance &&
            InResult._Location.Y >= CellMin.Y - kContainmentTolerance &&
            InResult._Location.Y <= CellMin.Y + CellSize + kContainmentTolerance;

        if (NOT InsideTheCell)
        { return false; }

        return FMath::Abs(InResult._Location.Z - static_cast<double>(SurfaceZ)) <= kContainmentTolerance;
    }

    /** The failing move written out whole, so a red gate names the query that produced it. */
    auto Get_EscapeReport(
        const FVector&                         InStart,
        const FVector&                         InTarget,
        const FCk_GroundNav_SurfaceWalkResult& InResult) -> FString
    {
        return FString::Printf(
            TEXT(" | first escape: start (%.4f, %.4f, %.4f) target (%.4f, %.4f, %.4f) ended (%.4f, %.4f, %.4f) status %s surface tile %d layer %d cell (%d, %d) plate %d"),
            InStart.X, InStart.Y, InStart.Z,
            InTarget.X, InTarget.Y, InTarget.Z,
            InResult._Location.X, InResult._Location.Y, InResult._Location.Z,
            Get_StatusName(InResult._Status),
            InResult._Surface._TileIndex,
            InResult._Surface._LayerIndex,
            InResult._Surface._CellX,
            InResult._Surface._CellY,
            InResult._Surface._PlateIndex);
    }

    // ----------------------------------------------------------------------------------------------------------------

    /** A plate wide enough to move inside and pinched enough that a body can be refused entry to it. */
    struct FPinchedPlate
    {
        int32 _TileIndex = INDEX_NONE;
        int32 _PlateIndex = FCk_GroundNav_Plate::kNoPlate;
        int32 _LayerIndex = INDEX_NONE;

        float _MinClearanceUu = 0.0f;

        FVector _Start = FVector::ZeroVector;
        FVector _Target = FVector::ZeroVector;

        auto Get_IsValid() const -> bool { return _TileIndex != INDEX_NONE; }
    };

    /**
     * Found rather than hardcoded, because which plate is pinched is a product of the merge: moving a
     * fixture box would silently retarget a hardcoded point at an open plate, where the refusal this
     * test is about cannot happen and the assertion would pass for the wrong reason.
     */
    auto TryFind_PinchedPlate(
        const FCk_GroundNav_Field& InField) -> FPinchedPlate
    {
        constexpr auto kCellsApart = 2;
        constexpr auto kMinWidth = 7;
        constexpr auto kMinDepth = 3;

        for (auto TileIndex = 0; TileIndex < InField._Tiles.Num(); ++TileIndex)
        {
            const auto& Tile = InField._Tiles[TileIndex];

            if (NOT Tile.Get_IsBuilt())
            { continue; }

            for (auto PlateIndex = 0; PlateIndex < Tile._Plates._Plates.Num(); ++PlateIndex)
            {
                const auto& Plate = Tile._Plates._Plates[PlateIndex];

                const auto IsPinched =
                    Plate._MinClearanceUu > 0.0f && Plate._MinClearanceUu < Tile._MaxClearanceUu;

                const auto IsBigEnough = Plate.Get_Width() >= kMinWidth && Plate.Get_Depth() >= kMinDepth;

                if (NOT IsPinched || NOT IsBigEnough)
                { continue; }

                const auto CentreX = (Plate._MinX + Plate._MaxX) / 2;
                const auto CentreY = (Plate._MinY + Plate._MaxY) / 2;
                const auto FarX = CentreX + kCellsApart;

                const auto CentreOwner = Tile._Plates.Get_PlateIndexAt(CentreX, CentreY, Plate._LayerIndex);
                const auto FarOwner = Tile._Plates.Get_PlateIndexAt(FarX, CentreY, Plate._LayerIndex);

                if (CentreOwner != PlateIndex || FarOwner != PlateIndex)
                { continue; }

                auto Found = FPinchedPlate{};

                Found._TileIndex = TileIndex;
                Found._PlateIndex = PlateIndex;
                Found._LayerIndex = Plate._LayerIndex;
                Found._MinClearanceUu = Plate._MinClearanceUu;
                Found._Start = Tile.Get_CellCentre(CentreX, CentreY, Plate._LayerIndex);
                Found._Target = Tile.Get_CellCentre(FarX, CentreY, Plate._LayerIndex);

                return Found;
            }
        }

        return FPinchedPlate{};
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Query_SurfaceWalk_TenThousandRandomMovesNeverLeaveTheWalkableSet,
    "CkTests.UnitTests.CkGroundNav.Query.SurfaceWalk_TenThousandRandomMovesNeverLeaveTheWalkableSet",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Query_SurfaceWalk_TenThousandRandomMovesNeverLeaveTheWalkableSet::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_query_surfacewalk;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    const auto Points = Make_RandomPointsOverField(Field, kMoveCount, kPointSeed);

    // A point body and one wide enough for clearance to bind. The first pins containment alone, the
    // second pins containment AND admission, which are different failures wearing the same symptom.
    constexpr float Radii[] = {0.0f, 30.0f};

    for (const auto Radius : Radii)
    {
        auto Stream = FRandomStream{kOffsetSeed};

        auto MovesAttempted = 0;
        auto MovesRun = 0;
        auto ReachedCount = 0;
        auto SlideTotal = 0;
        auto EarlyOutTotal = 0;
        auto EscapeCount = 0;

        auto FirstEscape = FString{};

        for (const auto& Point : Points)
        {
            ++MovesAttempted;

            // Drawn before the skip, so which offsets a run uses does not depend on which starts
            // resolved and the two radii walk the same shapes wherever they both find ground.
            const auto OffsetX = static_cast<double>(Stream.FRandRange(-kOffsetExtentUu, kOffsetExtentUu));
            const auto OffsetY = static_cast<double>(Stream.FRandRange(-kOffsetExtentUu, kOffsetExtentUu));

            const auto Projected = Get_ProjectPoint(Field, Make_Projection(Point, Radius));

            if (NOT Projected.Get_IsSuccess())
            { continue; }

            ++MovesRun;

            const auto Start = Projected._Location;
            const auto Target = FVector{Start.X + OffsetX, Start.Y + OffsetY, Start.Z};

            auto Diagnostics = FCk_GroundNav_SurfaceWalkDiagnostics{};
            const auto Result = Get_MoveAlongSurface(Field, Make_Walk(Start, Target, Radius), Diagnostics);

            if (Result._ReachedTarget)
            { ++ReachedCount; }

            if (Diagnostics._TookPlateEarlyOut)
            { ++EarlyOutTotal; }

            SlideTotal += Diagnostics._SlideCount;

            if (Get_IsOnWalkableSet(Field, Result, Projected._Surface, Radius))
            { continue; }

            ++EscapeCount;

            if (FirstEscape.IsEmpty())
            { FirstEscape = Get_EscapeReport(Start, Target, Result); }
        }

        const auto Report = FString::Printf(
            TEXT("radius %.0f uu: %d moves attempted, %d run, %d reached target, %d slides, %d plate early-outs, %d escapes"),
            Radius, MovesAttempted, MovesRun, ReachedCount, SlideTotal, EarlyOutTotal, EscapeCount);

        ck::groundnav::Display(TEXT("{}"), Report);

        // A sample that never found ground would never leave the walkable set either, so the sample has
        // to be shown to be worth something before its silence means anything.
        if (NOT TestTrue(FString::Printf(TEXT("the sample actually stands somewhere [%s]"), *Report),
            MovesRun > 0))
        { return false; }

        TestEqual(FString::Printf(TEXT("no move leaves the walkable set [%s]%s"), *Report, *FirstEscape),
            EscapeCount, 0);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Query_SurfaceWalk_ConcaveCornerTerminates,
    "CkTests.UnitTests.CkGroundNav.Query.SurfaceWalk_ConcaveCornerTerminates",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Query_SurfaceWalk_ConcaveCornerTerminates::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_query_surfacewalk;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    // Floor just west of the wall and just north of the field's own south edge. Pushing south-east
    // loses +X to the wall and -Y to the edge, which is a concave corner built out of two different
    // kinds of refusal; oscillating between them is the failure this pins.
    const auto Start = FVector{650.0, 50.0, kGroundZ};
    const auto Target = FVector{900.0, -200.0, kGroundZ};

    auto Diagnostics = FCk_GroundNav_SurfaceWalkDiagnostics{};
    const auto Result = Get_MoveAlongSurface(Field, Make_Walk(Start, Target, 0.0f), Diagnostics);

    if (NOT TestEqual(TEXT("a walk starting on the floor beside the corner runs"),
        Result._Status, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    TestFalse(FString::Printf(
        TEXT("without reaching a target that is through a wall and off the field (%s)"),
        *Result._Location.ToString()),
        Result._ReachedTarget);

    TestTrue(FString::Printf(TEXT("sliding at most twice, once per blocked axis (%d)"), Diagnostics._SlideCount),
        Diagnostics._SlideCount <= 2);

    TestFalse(FString::Printf(
        TEXT("and terminating on the corner rather than on the iteration bound (%d cells stepped)"),
        Diagnostics._CellsStepped),
        Diagnostics._HitIterationBound);

    const auto StartColumn = Get_IsNavigable(Field, Make_ColumnQuery(Start, 0.0f));

    TestTrue(FString::Printf(TEXT("and ending on the walkable set (%s)"), *Result._Location.ToString()),
        Get_IsOnWalkableSet(Field, Result, StartColumn._Surface, 0.0f));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Query_SurfaceWalk_MoveInsideOnePlateTakesTheEarlyOut,
    "CkTests.UnitTests.CkGroundNav.Query.SurfaceWalk_MoveInsideOnePlateTakesTheEarlyOut",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Query_SurfaceWalk_MoveInsideOnePlateTakesTheEarlyOut::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_query_surfacewalk;

    auto FlatField = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the flat scene bakes"), Bake_FlatScene(FlatField)))
    { return false; }

    constexpr auto kMoveUu = 100.0;

    const auto StartColumn = Get_IsNavigable(FlatField, Make_ColumnQuery(
        FVector{kFlatProbeX, kFlatProbeY, kGroundZ}, 0.0f));

    if (NOT TestEqual(TEXT("the flat scene's probe point stands on ground"),
        StartColumn._Status, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    const auto Start = FVector{kFlatProbeX, kFlatProbeY, static_cast<double>(StartColumn._SurfaceZUu)};
    const auto Target = FVector{kFlatProbeX + kMoveUu, kFlatProbeY, Start.Z};

    const auto TargetColumn = Get_IsNavigable(FlatField, Make_ColumnQuery(Target, 0.0f));

    if (NOT TestEqual(TEXT("and so does the point 100 uu east of it"),
        TargetColumn._Status, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    // The early-out is a claim about ONE plate, so the premise is established rather than assumed: two
    // ends on different plates would be answered without stepping for an entirely different reason.
    if (NOT TestTrue(FString::Printf(
        TEXT("with both ends on the same plate (tile %d/%d, layer %d/%d, plate %d/%d)"),
        StartColumn._Surface._TileIndex, TargetColumn._Surface._TileIndex,
        StartColumn._Surface._LayerIndex, TargetColumn._Surface._LayerIndex,
        StartColumn._Surface._PlateIndex, TargetColumn._Surface._PlateIndex),
        StartColumn._Surface._TileIndex == TargetColumn._Surface._TileIndex &&
        StartColumn._Surface._LayerIndex == TargetColumn._Surface._LayerIndex &&
        StartColumn._Surface._PlateIndex == TargetColumn._Surface._PlateIndex))
    { return false; }

    auto Diagnostics = FCk_GroundNav_SurfaceWalkDiagnostics{};
    const auto Result = Get_MoveAlongSurface(FlatField, Make_Walk(Start, Target, 0.0f), Diagnostics);

    if (NOT TestEqual(TEXT("a move inside one plate succeeds"),
        Result._Status, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    TestTrue(TEXT("answered by the plate early-out"), Diagnostics._TookPlateEarlyOut);

    TestEqual(TEXT("without stepping a single cell"), Diagnostics._CellsStepped, 0);

    TestTrue(TEXT("reaching the target"), Result._ReachedTarget);

    TestTrue(FString::Printf(TEXT("and landing on the target's own XY (%s)"), *Result._Location.ToString()),
        FMath::Abs(Result._Location.X - Target.X) <= kContainmentTolerance &&
        FMath::Abs(Result._Location.Y - Target.Y) <= kContainmentTolerance);

    // The refusal half needs a plate whose minimum clearance is BELOW the field's ceiling. The flat
    // scene's halo is fully floored, so every one of its cells reads the ceiling and no answerable
    // radius could be refused there; the query scene's floor is pinched by the wall, the hole and the
    // pillar, so it has such plates.
    auto QueryField = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(QueryField)))
    { return false; }

    const auto Pinched = TryFind_PinchedPlate(QueryField);

    if (NOT TestTrue(TEXT("the query scene has a plate that is both wide and pinched"), Pinched.Get_IsValid()))
    { return false; }

    // Barely over the pinch, so every cell of the plate but its tightest still admits the body: the
    // walk has somewhere to step, and only the early-out's own claim is being refused.
    const auto RefusedRadius = Pinched._MinClearanceUu + 0.5f;

    auto WideDiagnostics = FCk_GroundNav_SurfaceWalkDiagnostics{};
    const auto Wide = Get_MoveAlongSurface(
        QueryField, Make_Walk(Pinched._Start, Pinched._Target, RefusedRadius), WideDiagnostics);

    const auto WideReport = FString::Printf(
        TEXT("tile %d plate %d has %.2f uu of room at its tightest, the body asks %.2f, the walk stepped %d cells and ended %s"),
        Pinched._TileIndex, Pinched._PlateIndex, Pinched._MinClearanceUu, RefusedRadius,
        WideDiagnostics._CellsStepped, *Wide._Location.ToString());

    ck::groundnav::Display(TEXT("{}"), WideReport);

    if (NOT TestEqual(FString::Printf(TEXT("the refused-early-out move still runs [%s]"), *WideReport),
        Wide._Status, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    TestFalse(FString::Printf(
        TEXT("a body wider than the plate's tightest cell is refused the early-out [%s]"), *WideReport),
        WideDiagnostics._TookPlateEarlyOut);

    TestTrue(FString::Printf(TEXT("and is walked cell by cell instead [%s]"), *WideReport),
        WideDiagnostics._CellsStepped > 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Query_SurfaceWalk_CrossesSeamsAndPortals,
    "CkTests.UnitTests.CkGroundNav.Query.SurfaceWalk_CrossesSeamsAndPortals",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Query_SurfaceWalk_CrossesSeamsAndPortals::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_query_surfacewalk;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    // The 2x2 field's tiles meet at y = 800, so a walk from 400 to 1200 in Y has to leave one tile and
    // enter another. A tile boundary is the crossing no single published tile can answer on its own,
    // which is why it is stated apart from the plate boundaries around it.
    const auto AcrossTheSeamStart = FVector{400.0, 400.0, kGroundZ};
    const auto AcrossTheSeamTarget = FVector{400.0, 1200.0, kGroundZ};

    auto SeamDiagnostics = FCk_GroundNav_SurfaceWalkDiagnostics{};
    const auto AcrossTheSeam = Get_MoveAlongSurface(
        Field, Make_Walk(AcrossTheSeamStart, AcrossTheSeamTarget, 0.0f), SeamDiagnostics);

    if (NOT TestEqual(TEXT("a walk from one tile into the next runs"),
        AcrossTheSeam._Status, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    TestTrue(FString::Printf(TEXT("and arrives (%s)"), *AcrossTheSeam._Location.ToString()),
        AcrossTheSeam._ReachedTarget);

    TestTrue(FString::Printf(TEXT("having crossed the tile seam at y = 800 (%d seam crossings)"),
        SeamDiagnostics._SeamCrossings),
        SeamDiagnostics._SeamCrossings >= 1);

    // A longer walk over the same seam, up the corridor between the wall and the field's west half.
    // Whether the ground either side is one plate or several is a product of the merge, so the
    // assertion is on the crossings TOGETHER rather than on which kind the merge happened to leave.
    const auto AlongTheWallStart = FVector{600.0, 100.0, kGroundZ};
    const auto AlongTheWallTarget = FVector{600.0, 1500.0, kGroundZ};

    auto CorridorDiagnostics = FCk_GroundNav_SurfaceWalkDiagnostics{};
    const auto AlongTheWall = Get_MoveAlongSurface(
        Field, Make_Walk(AlongTheWallStart, AlongTheWallTarget, 0.0f), CorridorDiagnostics);

    if (NOT TestEqual(TEXT("a walk the length of the corridor beside the wall runs"),
        AlongTheWall._Status, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    TestTrue(FString::Printf(TEXT("and arrives too (%s)"), *AlongTheWall._Location.ToString()),
        AlongTheWall._ReachedTarget);

    TestTrue(FString::Printf(TEXT("having crossed something on the way (%d portal, %d seam)"),
        CorridorDiagnostics._PortalCrossings, CorridorDiagnostics._SeamCrossings),
        CorridorDiagnostics._PortalCrossings + CorridorDiagnostics._SeamCrossings >= 1);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Query_SurfaceWalk_StartOffTheSurfaceIsAStatusNotAWalk,
    "CkTests.UnitTests.CkGroundNav.Query.SurfaceWalk_StartOffTheSurfaceIsAStatusNotAWalk",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Query_SurfaceWalk_StartOffTheSurfaceIsAStatusNotAWalk::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_query_surfacewalk;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    // Over the hole FIRST: the probe that takes a tile away shares tile (1,1) with it, so this point
    // would answer Unbuilt for the other reason once the tile is gone.
    const auto OverTheHole = FVector{0.5 * (kHoleMin + kHoleMax), 0.5 * (kHoleMin + kHoleMax), 50.0};

    auto HoleDiagnostics = FCk_GroundNav_SurfaceWalkDiagnostics{};
    const auto OverNothing = Get_MoveAlongSurface(
        Field, Make_Walk(OverTheHole, FVector{1400.0, 1100.0, 50.0}, 0.0f), HoleDiagnostics);

    TestEqual(TEXT("a walk starting over the hole has no surface to start on"),
        OverNothing._Status, ECk_NavSurface_QueryStatus::NoSurface);

    const auto OverTheTakenTile = FVector{kFarTileProbeX, kFarTileProbeY, kGroundZ};

    if (NOT TestTrue(TEXT("the far probe stands over a tile the field actually has"),
        Do_MakeTileUnbuiltAt(Field, OverTheTakenTile) != INDEX_NONE))
    { return false; }

    auto UnbuiltDiagnostics = FCk_GroundNav_SurfaceWalkDiagnostics{};
    const auto OverUnbuilt = Get_MoveAlongSurface(
        Field,
        Make_Walk(OverTheTakenTile, FVector{kFarTileProbeX - 200.0, kFarTileProbeY, kGroundZ}, 0.0f),
        UnbuiltDiagnostics);

    TestEqual(TEXT("a walk starting over an unbuilt tile says so, and never calls it NoSurface"),
        OverUnbuilt._Status, ECk_NavSurface_QueryStatus::Unbuilt);

    // Decided before the start is even resolved: no cell of a field baked to a 200 uu ceiling can be
    // shown to admit a 250 uu body, so the query refuses rather than mis-admitting.
    constexpr auto kOverTheCap = 250.0f;

    const auto OnGoodGround = FVector{400.0, 400.0, kGroundZ};

    auto BlockedDiagnostics = FCk_GroundNav_SurfaceWalkDiagnostics{};
    const auto TooWide = Get_MoveAlongSurface(
        Field, Make_Walk(OnGoodGround, FVector{500.0, 400.0, kGroundZ}, kOverTheCap), BlockedDiagnostics);

    TestEqual(TEXT("a body wider than the field's clearance ceiling is Blocked before it walks"),
        TooWide._Status, ECk_NavSurface_QueryStatus::Blocked);

    // The point of the whole set: three refusals a consumer acts on differently, and not one of them
    // dressed up as a walk that happened to go nowhere.
    TestTrue(TEXT("and none of the three is reported as a successful walk"),
        NOT OverNothing.Get_IsSuccess() && NOT OverUnbuilt.Get_IsSuccess() && NOT TooWide.Get_IsSuccess());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Query_SurfaceWalk_IntoTheWallStopsAtItsFace,
    "CkTests.UnitTests.CkGroundNav.Query.SurfaceWalk_IntoTheWallStopsAtItsFace",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Query_SurfaceWalk_IntoTheWallStopsAtItsFace::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_query_surfacewalk;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    const auto Start = FVector{600.0, 800.0, kGroundZ};
    const auto Target = FVector{900.0, 800.0, kGroundZ};

    auto Diagnostics = FCk_GroundNav_SurfaceWalkDiagnostics{};
    const auto Result = Get_MoveAlongSurface(Field, Make_Walk(Start, Target, 0.0f), Diagnostics);

    if (NOT TestEqual(TEXT("a walk driven straight into the wall still runs"),
        Result._Status, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    TestFalse(FString::Printf(TEXT("without reaching a target on the far side of it (%s)"),
        *Result._Location.ToString()),
        Result._ReachedTarget);

    // Stopped BY the wall, not short of it: the last walkable cell is the one whose east edge is the
    // wall's west face, so the answer lies in that single cell and nowhere else.
    TestTrue(FString::Printf(
        TEXT("stopping no further east than the wall's west face (%.4f)"), Result._Location.X),
        Result._Location.X <= kWallMinX + kContainmentTolerance);

    TestTrue(FString::Printf(TEXT("and within one cell of it (%.4f)"), Result._Location.X),
        Result._Location.X >= kWallMinX - static_cast<double>(kCellSize) - kContainmentTolerance);

    TestTrue(FString::Printf(TEXT("having slid off the blocked axis at least once (%d)"), Diagnostics._SlideCount),
        Diagnostics._SlideCount >= 1);

    const auto StartColumn = Get_IsNavigable(Field, Make_ColumnQuery(Start, 0.0f));

    TestTrue(FString::Printf(TEXT("and ending on the walkable set (%s)"), *Result._Location.ToString()),
        Get_IsOnWalkableSet(Field, Result, StartColumn._Surface, 0.0f));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
