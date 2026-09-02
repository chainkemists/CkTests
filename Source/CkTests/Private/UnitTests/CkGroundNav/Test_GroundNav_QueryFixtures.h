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
}

// --------------------------------------------------------------------------------------------------------------------
