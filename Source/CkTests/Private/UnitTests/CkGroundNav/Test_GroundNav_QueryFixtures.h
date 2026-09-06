#pragma once

// The scenes every ground-query test asks its questions of, and the small amount of arithmetic those
// questions need. Held in one header rather than repeated per file because the query contracts are
// stated against ONE world — a projection, an is-navigable lookup and an attributes read of the same
// point have to be answered from the same ground or the agreements between them mean nothing. Every
// function here is inline and lives in a named namespace: the test .cpp files that include it land in
// the same unity blob, and an anonymous namespace or a non-inline definition would collide there.

#include "CkGroundNav/Backend/CkGroundNav_GeometryBackend_Stub.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Field/CkGroundNav_FieldTypes.h"

#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include <CoreMinimal.h>
#include <Math/RandomStream.h>

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_groundnav_queryfixtures
{
    using ck::groundnav::DoBake_Field;
    using ck::groundnav::DoDerive_SeamPortals;
    using ck::groundnav::DoLabel_Reachability;
    using ck::groundnav::FCk_GroundNav_Epoch;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldParams;
    using ck::groundnav::FCk_GroundNav_GeometryBackend_Stub;

    inline constexpr auto kCellSize = 25.0f;
    inline constexpr auto kCellHeight = 10.0f;
    inline constexpr auto kTileSize = 800.0f;
    inline constexpr auto kMaxClearance = 200.0f;

    inline constexpr auto kMinZ = -50.0f;
    inline constexpr auto kMaxZ = 400.0f;

    // The profile's own step height, which is what the projection buckets vertical distance by.
    inline constexpr auto kStepHeight = 40.0f;

    // The 2x2 field spans this much world in each axis from the origin.
    inline constexpr auto kFieldSpan = 1600.0;

    // The square of missing floor, and the ground either side of the dividing wall.
    inline constexpr auto kHoleMin = 1000.0;
    inline constexpr auto kHoleMax = 1200.0;

    inline constexpr auto kWallMinX = 700.0;
    inline constexpr auto kWallMaxX = 800.0;

    // The raised deck and the ground underneath it: the column with two floors in it.
    inline constexpr auto kDeckTopZ = 260.0;
    inline constexpr auto kDeckColumnX = 1250.0;
    inline constexpr auto kDeckColumnY = 450.0;
    inline constexpr auto kGroundZ = 0.0;

    // A column in the far tile, used where a test needs a tile it can take away.
    inline constexpr auto kFarTileProbeX = 1400.0;
    inline constexpr auto kFarTileProbeY = 1400.0;

    // Just outside the hole's east rim: one cell from ground that is not there, so the cell's own
    // clearance is one cell size and a wide body cannot stand on it.
    inline constexpr auto kNarrowProbeX = 1215.0;
    inline constexpr auto kNarrowProbeY = 1100.0;

    // A point inside the flat scene's floor that is interior to its cell rather than on a corner, so
    // the clamp into the answering cell has only one answer.
    inline constexpr auto kFlatProbeX = 410.0;
    inline constexpr auto kFlatProbeY = 410.0;

    inline constexpr auto kRampAngleDegrees = 20.0;
    inline constexpr auto kRampMinX = -100.0;
    inline constexpr auto kRampMaxX = 900.0;
    inline constexpr auto kRampBaseZ = 10.0;

    // ----------------------------------------------------------------------------------------------------------------

    inline auto Make_Params(
        const FIntPoint& InDivisions) -> FCk_GroundNav_FieldParams
    {
        auto Config = FCk_GroundNav_BakeConfig{kCellSize, kCellHeight};
        Config.Set_TileSizeUu(kTileSize);

        auto Profile = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{70.0f, 20.0f}}};
        Profile.Set_LedgeSensitivity(0.0f);
        Profile.Set_StepHeightUu(kStepHeight);

        auto Params = FCk_GroundNav_FieldParams{};

        Params._OriginXY = FVector2D::ZeroVector;
        Params._Divisions = InDivisions;
        Params._MinZUu = kMinZ;
        Params._MaxZUu = kMaxZ;
        Params._Config = Config;
        Params._Profile = Profile;
        Params._MaxClearanceUu = kMaxClearance;

        return Params;
    }

    inline auto Make_QueryParams() -> FCk_GroundNav_FieldParams
    {
        return Make_Params(FIntPoint{2, 2});
    }

    inline auto Make_FlatParams() -> FCk_GroundNav_FieldParams
    {
        return Make_Params(FIntPoint{1, 1});
    }

    inline auto Make_RampParams() -> FCk_GroundNav_FieldParams
    {
        return Make_Params(FIntPoint{1, 1});
    }

    // ----------------------------------------------------------------------------------------------------------------

    /**
     * The scene every projection, is-navigable and attributes test shares.
     *
     * Four things, each answering a different question. A square hole so a point can be over nothing
     * with ground a known distance away in every direction; a dividing wall with floor on both sides so
     * a horizontal search has two candidates at known unequal distances; a raised deck over standing
     * ground so one column carries two floors far enough apart to sit in different vertical buckets;
     * and a pillar so the world is not one flat plate.
     *
     * The floor reaches well past the field in every direction, so every tile's halo has real ground in
     * it and no border cell is answering about the edge of the fixture instead of the edge of the field.
     */
    inline auto Make_QueryScene() -> TArray<FBox>
    {
        auto Boxes = TArray<FBox>{};

        Boxes.Emplace(FBox{FVector{-400.0, -400.0, -10.0}, FVector{2000.0, kHoleMin, kGroundZ}});
        Boxes.Emplace(FBox{FVector{-400.0, kHoleMax, -10.0}, FVector{2000.0, 2000.0, kGroundZ}});
        Boxes.Emplace(FBox{FVector{-400.0, kHoleMin, -10.0}, FVector{kHoleMin, kHoleMax, kGroundZ}});
        Boxes.Emplace(FBox{FVector{kHoleMax, kHoleMin, -10.0}, FVector{2000.0, kHoleMax, kGroundZ}});

        Boxes.Emplace(FBox{FVector{kWallMinX, 0.0, 0.0}, FVector{kWallMaxX, kFieldSpan, 300.0}});

        Boxes.Emplace(FBox{FVector{1000.0, 200.0, 240.0}, FVector{1500.0, 700.0, kDeckTopZ}});

        Boxes.Emplace(FBox{FVector{300.0, 1300.0, 0.0}, FVector{400.0, 1400.0, 300.0}});

        return Boxes;
    }

    /** One floor and nothing else, for the cases whose answer must not depend on anything nearby. */
    inline auto Make_FlatScene() -> TArray<FBox>
    {
        return TArray<FBox>{
            FBox{FVector{-400.0, -400.0, -10.0}, FVector{1200.0, 1200.0, kGroundZ}}};
    }

    // ----------------------------------------------------------------------------------------------------------------

    inline auto Bake(
        const TArray<FBox>&              InBoxes,
        const FCk_GroundNav_FieldParams& InParams,
        FCk_GroundNav_Field&             OutField) -> bool
    {
        const auto Backend = FCk_GroundNav_GeometryBackend_Stub{InBoxes};

        return DoBake_Field(Backend, InParams, FCk_GroundNav_Epoch{1}, OutField).Get_IsCompleted();
    }

    inline auto Bake_QueryScene(
        FCk_GroundNav_Field& OutField) -> bool
    {
        return Bake(Make_QueryScene(), Make_QueryParams(), OutField);
    }

    inline auto Bake_FlatScene(
        FCk_GroundNav_Field& OutField) -> bool
    {
        return Bake(Make_FlatScene(), Make_FlatParams(), OutField);
    }

    // ----------------------------------------------------------------------------------------------------------------

    /** Rise of the ramp over its whole run, from the authored angle. */
    inline auto Get_RampRise() -> double
    {
        return (kRampMaxX - kRampMinX) * FMath::Tan(FMath::DegreesToRadians(kRampAngleDegrees));
    }

    /**
     * The plane a query is expected to recover: the ramp climbs along +X only, so its normal leans back
     * along -X by exactly the ramp angle.
     */
    inline auto Get_RampNormal() -> FVector
    {
        const auto Radians = FMath::DegreesToRadians(kRampAngleDegrees);

        return FVector{-FMath::Sin(Radians), 0.0, FMath::Cos(Radians)};
    }

    /**
     * A single sloped quad covering the whole field and its halo.
     *
     * Authored as a Surface panel rather than a box because a box cannot be tilted: the stub's boxes are
     * axis-aligned, and its panels are the only primitive that can express a plane at an angle. Surface
     * is the exempt kind, so an open quad here is not a closure violation.
     */
    inline auto Bake_RampScene(
        FCk_GroundNav_Field& OutField) -> bool
    {
        const auto Rise = Get_RampRise();

        auto Backend = FCk_GroundNav_GeometryBackend_Stub{};

        Backend.Add_Panel(
            FVector{kRampMinX, kRampMinX, kRampBaseZ},
            FVector{kRampMaxX, kRampMinX, kRampBaseZ + Rise},
            FVector{kRampMaxX, kRampMaxX, kRampBaseZ + Rise},
            FVector{kRampMinX, kRampMaxX, kRampBaseZ},
            ck::groundnav::ECk_GroundNav_BodyKind::Surface);

        return DoBake_Field(Backend, Make_RampParams(), FCk_GroundNav_Epoch{1}, OutField).Get_IsCompleted();
    }

    // ----------------------------------------------------------------------------------------------------------------

    /**
     * Points spread over the field's own footprint, from a named seed so a failing element can be found
     * again. The vertical spread is the field's whole slab, so the set contains points above the ground,
     * between two floors and under everything.
     */
    inline auto Make_RandomPointsOverField(
        const FCk_GroundNav_Field& InField,
        int32                      InCount,
        int32                      InSeed) -> TArray<FVector>
    {
        const auto Bounds = InField._Params.Get_Bounds();

        auto Stream = FRandomStream{InSeed};

        auto Points = TArray<FVector>{};
        Points.Reserve(InCount);

        for (auto Index = 0; Index < InCount; ++Index)
        {
            const auto FractionX = static_cast<double>(Stream.GetFraction());
            const auto FractionY = static_cast<double>(Stream.GetFraction());
            const auto FractionZ = static_cast<double>(Stream.GetFraction());

            Points.Emplace(FVector{
                FMath::Lerp(Bounds.Min.X, Bounds.Max.X, FractionX),
                FMath::Lerp(Bounds.Min.Y, Bounds.Max.Y, FractionY),
                FMath::Lerp(static_cast<double>(kMinZ), static_cast<double>(kMaxZ), FractionZ)});
        }

        return Points;
    }

    // ----------------------------------------------------------------------------------------------------------------

    inline auto Get_TileIndexAt(
        const FCk_GroundNav_Field& InField,
        const FVector&             InLocation) -> int32
    {
        return ck::groundnav::Get_TileIndex(
            InField._Params._Divisions, InField._Params.Get_TileCoordAt(InLocation));
    }

    /**
     * Take the tile under a position away, and re-derive everything that depended on it.
     *
     * The seam portals and the component labels are both products of which tiles are built, so a status
     * changed without re-deriving them leaves a field that answers about ground it no longer has.
     * Returns the tile index taken, or INDEX_NONE if no tile covers the position.
     */
    inline auto Do_MakeTileUnbuiltAt(
        FCk_GroundNav_Field& InOutField,
        const FVector&       InLocation) -> int32
    {
        const auto TileIndex = Get_TileIndexAt(InOutField, InLocation);

        if (NOT InOutField._Tiles.IsValidIndex(TileIndex))
        { return INDEX_NONE; }

        InOutField._Tiles[TileIndex]._Status = ECk_GroundNav_BuildStatus::Unbuilt;

        DoDerive_SeamPortals(InOutField);
        DoLabel_Reachability(InOutField);

        return TileIndex;
    }

    inline auto Do_MakeEveryTileUnbuilt(
        FCk_GroundNav_Field& InOutField) -> void
    {
        for (auto& Tile : InOutField._Tiles)
        { Tile._Status = ECk_GroundNav_BuildStatus::Unbuilt; }

        DoDerive_SeamPortals(InOutField);
        DoLabel_Reachability(InOutField);
    }

    // ----------------------------------------------------------------------------------------------------------------

    /** The world centre of one tile, at ground height, for a test that has to name every tile. */
    inline auto Get_TileCentre(
        const FCk_GroundNav_Field& InField,
        int32                      InTileIndex) -> FVector
    {
        const auto Coord = ck::groundnav::Get_TileCoord(InField._Params._Divisions, InTileIndex);
        const auto SpanUu = InField._Params.Get_TileSpanUu();

        return FVector{
            InField._Params._OriginXY.X + ((static_cast<double>(Coord._X) + 0.5) * SpanUu),
            InField._Params._OriginXY.Y + ((static_cast<double>(Coord._Y) + 0.5) * SpanUu),
            kGroundZ};
    }

    /** The square of missing floor, as a rectangle a test can measure distances against. */
    inline auto Get_HoleRectXY() -> FBox
    {
        return FBox{
            FVector{kHoleMin, kHoleMin, static_cast<double>(kMinZ)},
            FVector{kHoleMax, kHoleMax, static_cast<double>(kMaxZ)}};
    }

    /** Distance in XY from a point to a rectangle: zero inside it, the gap to its nearest edge outside. */
    inline auto Get_DistanceToRectXY(
        const FBox&    InRect,
        const FVector& InPoint) -> double
    {
        const auto Nearest = FVector2D{
            FMath::Clamp(InPoint.X, InRect.Min.X, InRect.Max.X),
            FMath::Clamp(InPoint.Y, InRect.Min.Y, InRect.Max.Y)};

        return FVector2D::Distance(FVector2D{InPoint.X, InPoint.Y}, Nearest);
    }

    /** Angle between two unit vectors, in degrees, for an assertion stated the way a normal is read. */
    inline auto Get_AngleBetweenDegrees(
        const FVector& InLeft,
        const FVector& InRight) -> double
    {
        return FMath::RadiansToDegrees(
            FMath::Acos(FMath::Clamp(FVector::DotProduct(InLeft, InRight), -1.0, 1.0)));
    }

    // ----------------------------------------------------------------------------------------------------------------

    // The L: a 100-wide corridor running +X along y in [0, 100] as far as x = 500, then a +Y leg in
    // x [400, 500]. Its inside corner is the one reflex corner of the free space and therefore the only
    // place a shortest string can bend, and it is placed where the hand-authored portal sequence the
    // funnel is pinned against puts it, so the two speak of one shape.
    inline constexpr auto kLCorridorCornerX = 400.0;
    inline constexpr auto kLCorridorCornerY = 100.0;
    inline constexpr auto kLCorridorEastX = 500.0;
    inline constexpr auto kLCorridorNorthY = 700.0;

    // On the centre line of each leg, half the corridor clear of both its walls.
    inline const auto kLCorridorStart = FVector{50.0, 50.0, kGroundZ};
    inline const auto kLCorridorGoal = FVector{450.0, 600.0, kGroundZ};

    // A second point on the SAME leg as the start, so the string between the two bends nowhere.
    inline const auto kLCorridorStraightGoal = FVector{350.0, 50.0, kGroundZ};

    // Where the two legs' centre lines meet. The chain through it is a route the corridor admits for a
    // body of any radius under half the width, so its length is an upper bound the shortest one holds to.
    inline const auto kLCorridorCentreXY = FVector2D{450.0, 50.0};

    /**
     * The L corridor with ground under it, so a boundary distance can be asked of it.
     *
     * The hand-authored portal list the funnel is pinned against carries no field, and a claim about how
     * far a waypoint sits from a wall has nothing to read without one. Same shape, baked.
     */
    inline auto Make_LCorridorScene() -> TArray<FBox>
    {
        auto Boxes = TArray<FBox>{};

        Boxes.Emplace(FBox{FVector{-400.0, -400.0, -10.0}, FVector{1200.0, 1200.0, kGroundZ}});

        Boxes.Emplace(FBox{FVector{-400.0, -400.0, 0.0}, FVector{1200.0, 0.0, 300.0}});
        Boxes.Emplace(FBox{FVector{-400.0, -400.0, 0.0}, FVector{0.0, 1200.0, 300.0}});

        Boxes.Emplace(FBox{
            FVector{-400.0, kLCorridorCornerY, 0.0}, FVector{kLCorridorCornerX, 1200.0, 300.0}});

        Boxes.Emplace(FBox{FVector{kLCorridorEastX, -400.0, 0.0}, FVector{1200.0, 1200.0, 300.0}});

        Boxes.Emplace(FBox{
            FVector{kLCorridorCornerX, kLCorridorNorthY, 0.0}, FVector{kLCorridorEastX, 1200.0, 300.0}});

        return Boxes;
    }

    inline auto Bake_LCorridorScene(
        FCk_GroundNav_Field& OutField) -> bool
    {
        return Bake(Make_LCorridorScene(), Make_Params(FIntPoint{1, 1}), OutField);
    }

    /** The chain through the two legs' centre lines: a feasible route, and so a bound on the shortest. */
    inline auto Get_LCorridorCentreChainLengthUu(
        const FVector& InStart,
        const FVector& InGoal) -> double
    {
        const auto StartXY = FVector2D{InStart.X, InStart.Y};
        const auto GoalXY = FVector2D{InGoal.X, InGoal.Y};

        return FVector2D::Distance(StartXY, kLCorridorCentreXY) +
            FVector2D::Distance(kLCorridorCentreXY, GoalXY);
    }

    // ----------------------------------------------------------------------------------------------------------------

    // Two rooms and two ways between them: straight through a door low in the dividing wall, or the long
    // way over the wall's top. Each way is one homotopy class of the free space, so each has exactly one
    // taut string and the ratio between the two is a property of the geometry alone.
    inline constexpr auto kTwoRouteDividerMinX = 600.0;
    inline constexpr auto kTwoRouteDividerMaxX = 700.0;
    inline constexpr auto kTwoRouteDoorMinY = 150.0;
    inline constexpr auto kTwoRouteDoorMaxY = 250.0;
    inline constexpr auto kTwoRouteDividerTopY = 1275.0;

    inline constexpr auto kTwoRouteFreeMinX = 100.0;
    inline constexpr auto kTwoRouteFreeMaxX = 1200.0;
    inline constexpr auto kTwoRouteFreeMinY = 100.0;
    inline constexpr auto kTwoRouteFreeMaxY = 1375.0;

    // Placed the same distance from the divider on either side, which is what makes the two taut lengths
    // below closed forms rather than four separate legs.
    inline const auto kTwoRouteStart = FVector{300.0, 300.0, kGroundZ};
    inline const auto kTwoRouteGoal = FVector{1000.0, 300.0, kGroundZ};

    // Inside the door itself, on neither room's side of it.
    inline const auto kTwoRouteDirectProbe = FVector{650.0, 200.0, kGroundZ};

    inline auto Make_TwoRouteScene() -> TArray<FBox>
    {
        auto Boxes = TArray<FBox>{};

        Boxes.Emplace(FBox{FVector{-400.0, -400.0, -10.0}, FVector{2000.0, 2000.0, kGroundZ}});

        Boxes.Emplace(FBox{FVector{-400.0, -400.0, 0.0}, FVector{2000.0, kTwoRouteFreeMinY, 300.0}});
        Boxes.Emplace(FBox{FVector{-400.0, kTwoRouteFreeMaxY, 0.0}, FVector{2000.0, 2000.0, 300.0}});

        Boxes.Emplace(FBox{
            FVector{-400.0, kTwoRouteFreeMinY, 0.0},
            FVector{kTwoRouteFreeMinX, kTwoRouteFreeMaxY, 300.0}});

        Boxes.Emplace(FBox{
            FVector{kTwoRouteFreeMaxX, kTwoRouteFreeMinY, 0.0},
            FVector{2000.0, kTwoRouteFreeMaxY, 300.0}});

        Boxes.Emplace(FBox{
            FVector{kTwoRouteDividerMinX, kTwoRouteFreeMinY, 0.0},
            FVector{kTwoRouteDividerMaxX, kTwoRouteDoorMinY, 300.0}});

        Boxes.Emplace(FBox{
            FVector{kTwoRouteDividerMinX, kTwoRouteDoorMaxY, 0.0},
            FVector{kTwoRouteDividerMaxX, kTwoRouteDividerTopY, 300.0}});

        return Boxes;
    }

    inline auto Bake_TwoRouteScene(
        FCk_GroundNav_Field& OutField) -> bool
    {
        return Bake(Make_TwoRouteScene(), Make_QueryParams(), OutField);
    }

    /** Down through the door and back up, bending on its two upper corners. */
    inline auto Get_TwoRouteDirectLengthUu() -> double
    {
        const auto ReachX = kTwoRouteDividerMinX - kTwoRouteStart.X;
        const auto DropY = kTwoRouteStart.Y - kTwoRouteDoorMaxY;

        return (2.0 * FMath::Sqrt((ReachX * ReachX) + (DropY * DropY))) +
            (kTwoRouteDividerMaxX - kTwoRouteDividerMinX);
    }

    /** Up and over the divider's top, bending on its two upper corners. */
    inline auto Get_TwoRouteDetourLengthUu() -> double
    {
        const auto ReachX = kTwoRouteDividerMinX - kTwoRouteStart.X;
        const auto ClimbY = kTwoRouteDividerTopY - kTwoRouteStart.Y;

        return (2.0 * FMath::Sqrt((ReachX * ReachX) + (ClimbY * ClimbY))) +
            (kTwoRouteDividerMaxX - kTwoRouteDividerMinX);
    }

    inline auto Get_TwoRouteLengthRatio() -> double
    {
        return Get_TwoRouteDetourLengthUu() / Get_TwoRouteDirectLengthUu();
    }

    // ----------------------------------------------------------------------------------------------------------------

    // A wall across the middle of a room with a gap at each end. The short way around is the east gap,
    // which stands on the ramp panel; the long way around is the west gap, which stands on flat floor.
    // So the shorter route is the sloped one, and a slope penalty has something to trade against length.
    inline constexpr auto kRampVsLevelRampStartX = 900.0;
    inline constexpr auto kRampVsLevelRampEndX = 1500.0;

    inline constexpr auto kRampVsLevelDividerMinX = 350.0;
    inline constexpr auto kRampVsLevelDividerMaxX = 1050.0;
    inline constexpr auto kRampVsLevelDividerMinY = 700.0;
    inline constexpr auto kRampVsLevelDividerMaxY = 800.0;

    inline constexpr auto kRampVsLevelFreeMinX = 100.0;
    inline constexpr auto kRampVsLevelFreeMaxX = 1300.0;
    inline constexpr auto kRampVsLevelFreeMinY = 100.0;
    inline constexpr auto kRampVsLevelFreeMaxY = 1300.0;

    // Nearer the east gap than the west one, and both on the flat half so the two ends themselves owe
    // the slope nothing.
    inline const auto kRampVsLevelStart = FVector{850.0, 400.0, kGroundZ};
    inline const auto kRampVsLevelGoal = FVector{850.0, 1000.0, kGroundZ};

    inline constexpr auto kRampVsLevelRampProbeX = 1150.0;
    inline constexpr auto kRampVsLevelLevelProbeX = 200.0;

    /** The panel climbs along +X only, so height is a function of X and is flat west of the panel. */
    inline auto Get_RampVsLevelSurfaceZ(
        double InX) -> double
    {
        if (InX <= kRampVsLevelRampStartX)
        { return kGroundZ; }

        return (InX - kRampVsLevelRampStartX) * FMath::Tan(FMath::DegreesToRadians(kRampAngleDegrees));
    }

    inline auto Get_RampVsLevelRampProbe() -> FVector
    {
        return FVector{
            kRampVsLevelRampProbeX,
            (kRampVsLevelDividerMinY + kRampVsLevelDividerMaxY) * 0.5,
            Get_RampVsLevelSurfaceZ(kRampVsLevelRampProbeX)};
    }

    inline auto Get_RampVsLevelLevelProbe() -> FVector
    {
        return FVector{
            kRampVsLevelLevelProbeX,
            (kRampVsLevelDividerMinY + kRampVsLevelDividerMaxY) * 0.5,
            Get_RampVsLevelSurfaceZ(kRampVsLevelLevelProbeX)};
    }

    inline auto Get_RampVsLevelGapLengthUu(
        double InReachX) -> double
    {
        const auto ToNearY = kRampVsLevelDividerMinY - kRampVsLevelStart.Y;
        const auto ToFarY = kRampVsLevelGoal.Y - kRampVsLevelDividerMaxY;

        return FMath::Sqrt((InReachX * InReachX) + (ToNearY * ToNearY)) +
            (kRampVsLevelDividerMaxY - kRampVsLevelDividerMinY) +
            FMath::Sqrt((InReachX * InReachX) + (ToFarY * ToFarY));
    }

    inline auto Get_RampVsLevelLevelLengthUu() -> double
    {
        return Get_RampVsLevelGapLengthUu(kRampVsLevelStart.X - kRampVsLevelDividerMinX);
    }

    /** Flat floor as far as the panel's foot, and nothing under the panel: one storey throughout. */
    inline auto Make_RampVsLevelScene() -> TArray<FBox>
    {
        auto Boxes = TArray<FBox>{};

        Boxes.Emplace(FBox{
            FVector{-400.0, -400.0, -10.0}, FVector{kRampVsLevelRampStartX, 2000.0, kGroundZ}});

        Boxes.Emplace(FBox{FVector{-400.0, -400.0, 0.0}, FVector{2000.0, kRampVsLevelFreeMinY, 300.0}});
        Boxes.Emplace(FBox{FVector{-400.0, kRampVsLevelFreeMaxY, 0.0}, FVector{2000.0, 2000.0, 300.0}});

        Boxes.Emplace(FBox{
            FVector{-400.0, kRampVsLevelFreeMinY, 0.0},
            FVector{kRampVsLevelFreeMinX, kRampVsLevelFreeMaxY, 300.0}});

        Boxes.Emplace(FBox{
            FVector{kRampVsLevelFreeMaxX, kRampVsLevelFreeMinY, 0.0},
            FVector{2000.0, kRampVsLevelFreeMaxY, 300.0}});

        Boxes.Emplace(FBox{
            FVector{kRampVsLevelDividerMinX, kRampVsLevelDividerMinY, 0.0},
            FVector{kRampVsLevelDividerMaxX, kRampVsLevelDividerMaxY, 300.0}});

        return Boxes;
    }

    inline auto Bake_RampVsLevelScene(
        FCk_GroundNav_Field& OutField) -> bool
    {
        auto Backend = FCk_GroundNav_GeometryBackend_Stub{Make_RampVsLevelScene()};

        const auto RiseUu = (kRampVsLevelRampEndX - kRampVsLevelRampStartX) *
            FMath::Tan(FMath::DegreesToRadians(kRampAngleDegrees));

        Backend.Add_Panel(
            FVector{kRampVsLevelRampStartX, -400.0, kGroundZ},
            FVector{kRampVsLevelRampEndX, -400.0, kGroundZ + RiseUu},
            FVector{kRampVsLevelRampEndX, 2000.0, kGroundZ + RiseUu},
            FVector{kRampVsLevelRampStartX, 2000.0, kGroundZ},
            ck::groundnav::ECk_GroundNav_BodyKind::Surface);

        return DoBake_Field(Backend, Make_QueryParams(), FCk_GroundNav_Epoch{1}, OutField).Get_IsCompleted();
    }

    // ----------------------------------------------------------------------------------------------------------------

    // One wall between two rooms, pierced twice: a tight door on the line the two ends already stand on,
    // and a wide opening well off it. The tight one is the shorter route and the wide one the roomier,
    // which is the only trade a clearance bias can make — it cannot move a string within a plate.
    inline constexpr auto kTwoDoorDividerMinX = 550.0;
    inline constexpr auto kTwoDoorDividerMaxX = 650.0;

    inline constexpr auto kTwoDoorTightMinY = 270.0;
    inline constexpr auto kTwoDoorTightMaxY = 330.0;
    inline constexpr auto kTwoDoorWideMinY = 700.0;
    inline constexpr auto kTwoDoorWideMaxY = 1000.0;

    inline constexpr auto kTwoDoorFreeMinX = 100.0;
    inline constexpr auto kTwoDoorFreeMaxX = 1100.0;
    inline constexpr auto kTwoDoorFreeMinY = 100.0;
    inline constexpr auto kTwoDoorFreeMaxY = 1100.0;

    inline const auto kTwoDoorStart = FVector{300.0, 300.0, kGroundZ};
    inline const auto kTwoDoorGoal = FVector{900.0, 300.0, kGroundZ};

    inline const auto kTwoDoorTightProbe = FVector{600.0, 300.0, kGroundZ};
    inline const auto kTwoDoorWideProbe = FVector{600.0, 850.0, kGroundZ};

    inline auto Make_TwoDoorScene() -> TArray<FBox>
    {
        auto Boxes = TArray<FBox>{};

        Boxes.Emplace(FBox{FVector{-400.0, -400.0, -10.0}, FVector{2000.0, 2000.0, kGroundZ}});

        Boxes.Emplace(FBox{FVector{-400.0, -400.0, 0.0}, FVector{2000.0, kTwoDoorFreeMinY, 300.0}});
        Boxes.Emplace(FBox{FVector{-400.0, kTwoDoorFreeMaxY, 0.0}, FVector{2000.0, 2000.0, 300.0}});

        Boxes.Emplace(FBox{
            FVector{-400.0, kTwoDoorFreeMinY, 0.0},
            FVector{kTwoDoorFreeMinX, kTwoDoorFreeMaxY, 300.0}});

        Boxes.Emplace(FBox{
            FVector{kTwoDoorFreeMaxX, kTwoDoorFreeMinY, 0.0},
            FVector{2000.0, kTwoDoorFreeMaxY, 300.0}});

        Boxes.Emplace(FBox{
            FVector{kTwoDoorDividerMinX, kTwoDoorFreeMinY, 0.0},
            FVector{kTwoDoorDividerMaxX, kTwoDoorTightMinY, 300.0}});

        Boxes.Emplace(FBox{
            FVector{kTwoDoorDividerMinX, kTwoDoorTightMaxY, 0.0},
            FVector{kTwoDoorDividerMaxX, kTwoDoorWideMinY, 300.0}});

        Boxes.Emplace(FBox{
            FVector{kTwoDoorDividerMinX, kTwoDoorWideMaxY, 0.0},
            FVector{kTwoDoorDividerMaxX, kTwoDoorFreeMaxY, 300.0}});

        return Boxes;
    }

    inline auto Bake_TwoDoorScene(
        FCk_GroundNav_Field& OutField) -> bool
    {
        return Bake(Make_TwoDoorScene(), Make_QueryParams(), OutField);
    }

    /** Straight: the two ends stand on the tight door's own centre line, so nothing bends. */
    inline auto Get_TwoDoorTightLengthUu() -> double
    {
        return kTwoDoorGoal.X - kTwoDoorStart.X;
    }

    /** Out to the wide opening and back, bending on its two near corners. */
    inline auto Get_TwoDoorWideLengthUu() -> double
    {
        const auto ReachX = kTwoDoorDividerMinX - kTwoDoorStart.X;
        const auto ClimbY = kTwoDoorWideMinY - kTwoDoorStart.Y;

        return (2.0 * FMath::Sqrt((ReachX * ReachX) + (ClimbY * ClimbY))) +
            (kTwoDoorDividerMaxX - kTwoDoorDividerMinX);
    }

    // ----------------------------------------------------------------------------------------------------------------

    // The Walk gym's crossing scene, restated as stub geometry.
    //
    // Every number below is the gym's own: the 3600 x 2400 slab and the four 150 x 150 x 300 pillars of
    // Script/CkGroundNav/CkGroundNavGym_Walk_PlayerController.as:16-28, W0's two posts at :65-66, and
    // the 25 / 10 lattice under the 34 uu / 180 uu body at :85-89. Restated rather than referenced
    // because the gym spawns actors into a world and this bakes boxes through the stub backend - two
    // ways of authoring one scene, which is only worth having when the numbers are the same numbers.
    //
    // The four pillars straddle the west-east lane at Y 0 by different amounts, so a crossing has to
    // weave past all of them. Four staggered rectangles on open floor is the shape whose plate
    // decomposition offers the most rectangle corners that are not obstacle corners.

    // The gym spawns unit boxes scaled 36 x 24 x 2 about a centre at Z -100, so the slab's top face is
    // the scene's Z 0 and it reaches X +/-1800 and Y +/-1200.
    inline constexpr auto kFourPillarSlabHalfXUu = 1800.0;
    inline constexpr auto kFourPillarSlabHalfYUu = 1200.0;
    inline constexpr auto kFourPillarSlabBottomZ = -200.0;

    // 1.5 x 1.5 x 3.0 unit boxes standing on the slab: 150 wide and 300 tall.
    inline constexpr auto kFourPillarHalfWidthUu = 75.0;
    inline constexpr auto kFourPillarTopZ = 300.0;

    // The gym's body. The radius is a QUERY property and never bakes - one field answers every size -
    // so only the standing height reaches the profile, and the radius is what a query is asked for.
    inline constexpr auto kFourPillarAgentRadiusUu = 34.0f;
    inline constexpr auto kFourPillarAgentHalfHeightUu = 90.0f;

    // W0's two posts. The gym stands them at ground + 100, which is where a 180 uu body's CENTRE sits;
    // a query resolves its ends onto the surface under them within a vertical tolerance, so the route
    // is stated here at the ground the body stands on rather than at the height its middle occupies.
    inline constexpr auto kFourPillarPostXUu = 1650.0;

    inline const auto kFourPillarWestPost = FVector{-kFourPillarPostXUu, 0.0, kGroundZ};
    inline const auto kFourPillarEastPost = FVector{kFourPillarPostXUu, 0.0, kGroundZ};

    /** The four pillar centres in XY, west to east, in the order the gym authors them. */
    inline auto Get_FourPillarCentresXY() -> TArray<FVector2D>
    {
        return TArray<FVector2D>{
            FVector2D{-900.0, -60.0},
            FVector2D{-300.0, 120.0},
            FVector2D{300.0, -100.0},
            FVector2D{900.0, 80.0}};
    }

    /**
     * A field that covers the slab with margin on every side.
     *
     * The divisions are not the slab's own footprint on purpose: the slab ENDS inside the field, so its
     * rim is a boundary run like any other wall and no border cell is answering about the edge of the
     * fixture instead of the edge of the field. The vertical slab starts at the slab's underside so a
     * box 200 uu thick is rasterized whole rather than clipped.
     *
     * The ledge filter is off for the reason the gym switches it off: at the conservative default a
     * slab that ends inside the volume loses its entire perimeter.
     */
    inline auto Make_FourPillarParams() -> FCk_GroundNav_FieldParams
    {
        auto Config = FCk_GroundNav_BakeConfig{kCellSize, kCellHeight};
        Config.Set_TileSizeUu(kTileSize);

        auto Profile = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{
                kFourPillarAgentHalfHeightUu, kFourPillarAgentRadiusUu}}};
        Profile.Set_LedgeSensitivity(0.0f);
        Profile.Set_StepHeightUu(kStepHeight);

        auto Params = FCk_GroundNav_FieldParams{};

        Params._OriginXY = FVector2D{-2000.0, -1600.0};
        Params._Divisions = FIntPoint{5, 4};
        Params._MinZUu = static_cast<float>(kFourPillarSlabBottomZ);
        Params._MaxZUu = kMaxZ;
        Params._Config = Config;
        Params._Profile = Profile;
        Params._MaxClearanceUu = kMaxClearance;

        return Params;
    }

    inline auto Make_FourPillarSlabScene() -> TArray<FBox>
    {
        auto Boxes = TArray<FBox>{};

        Boxes.Emplace(FBox{
            FVector{-kFourPillarSlabHalfXUu, -kFourPillarSlabHalfYUu, kFourPillarSlabBottomZ},
            FVector{kFourPillarSlabHalfXUu, kFourPillarSlabHalfYUu, kGroundZ}});

        for (const auto& Centre : Get_FourPillarCentresXY())
        {
            Boxes.Emplace(FBox{
                FVector{
                    Centre.X - kFourPillarHalfWidthUu,
                    Centre.Y - kFourPillarHalfWidthUu,
                    kGroundZ},
                FVector{
                    Centre.X + kFourPillarHalfWidthUu,
                    Centre.Y + kFourPillarHalfWidthUu,
                    kFourPillarTopZ}});
        }

        return Boxes;
    }

    inline auto Bake_FourPillarSlabScene(
        FCk_GroundNav_Field& OutField) -> bool
    {
        return Bake(Make_FourPillarSlabScene(), Make_FourPillarParams(), OutField);
    }

    /** The same scene held the way a search takes one: by shared pointer, so nothing can take it away. */
    inline auto Bake_SharedFourPillarSlabScene(
        ck::groundnav::FCk_GroundNav_FieldPtr& OutField) -> bool
    {
        auto Baked = MakeShared<FCk_GroundNav_Field>();

        if (NOT Bake_FourPillarSlabScene(*Baked))
        { return false; }

        OutField = Baked;

        return true;
    }
}

// --------------------------------------------------------------------------------------------------------------------
