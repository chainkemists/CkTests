// The debug snapshot boundary.
//
// A snapshot exists so a viewer can draw a bake without holding anything that produced it. The
// assertions here are about that boundary — that the copy is complete, that capping the drawn cells
// does not corrupt the reported counts, that a viewer can tell an empty region from a failed one,
// that a capture survives the field AND the world it was taken from, and that the cache beside it
// hands back one whole capture or none.

#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkGroundNav/Backend/CkGroundNav_GeometryBackend_Stub.h"
#include "CkGroundNav/Bake/CkGroundNav_Clearance.h"
#include "CkGroundNav/Bake/CkGroundNav_Plates.h"
#include "CkGroundNav/Bake/CkGroundNav_Portals.h"
#include "CkGroundNav/Bake/CkGroundNav_Rasterize.h"
#include "CkGroundNav/Debug/CkGroundNav_DebugDraw.h"
#include "CkGroundNav/Debug/CkGroundNav_DebugSnapshot.h"
#include "CkGroundNav/Facade/CkGroundNav_WorldFieldRegistry.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"

#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

#include <Engine/World.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_snapshot
{
    using ck::groundnav::DoCompute_Clearance;
    using ck::groundnav::DoDecompose_Plates;
    using ck::groundnav::DoExtract_Layers;
    using ck::groundnav::DoExtract_Portals;
    using ck::groundnav::DoFilter_Walkability;
    using ck::groundnav::DoBake_Field;
    using ck::groundnav::DoRasterizeSpans;
    using ck::groundnav::EDebugSnapshotStatus;
    using ck::groundnav::FCk_GroundNav_ClearanceField;
    using ck::groundnav::FCk_GroundNav_ConnectionField;
    using ck::groundnav::FCk_GroundNav_DebugCorridor;
    using ck::groundnav::FCk_GroundNav_DebugLink;
    using ck::groundnav::FCk_GroundNav_DebugMarkup;
    using ck::groundnav::FCk_GroundNav_DebugSnapshot;
    using ck::groundnav::FCk_GroundNav_DebugSnapshotCache;
    using ck::groundnav::FCk_GroundNav_DebugSnapshotCacheKey;
    using ck::groundnav::FCk_GroundNav_Epoch;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldParams;
    using ck::groundnav::FCk_GroundNav_FieldPtr;
    using ck::groundnav::FCk_GroundNav_DebugBakeParams;
    using ck::groundnav::FCk_GroundNav_GeometryBackend_Stub;
    using ck::groundnav::ICk_GroundNav_GeometryBackend;
    using ck::groundnav::Make_DebugSnapshotFromBackend;
    using ck::groundnav::FCk_GroundNav_LayerField;
    using ck::groundnav::FCk_GroundNav_PlateField;
    using ck::groundnav::FCk_GroundNav_PortalField;
    using ck::groundnav::FCk_GroundNav_SpanField;
    using ck::groundnav::Make_DebugSnapshot;
    using ck::groundnav::Make_DebugSnapshotFromField;

    namespace world_fields = ck::groundnav::world_fields;

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

    // --------------------------------------------------------------------------------------------------

    constexpr auto kCellHeight = 10.0f;
    constexpr auto kTileSize = 400.0f;
    constexpr auto kMaxClearance = 100.0f;

    constexpr auto kUncapped = TNumericLimits<int32>::Max();

    // 2x2 tiles of 400uu from the origin - the same field shape the publish and repair pins bake.
    auto Make_FieldParams() -> FCk_GroundNav_FieldParams
    {
        auto Config = FCk_GroundNav_BakeConfig{kCellSize, kCellHeight};
        Config.Set_TileSizeUu(kTileSize);

        auto Profile = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{70.0f, 20.0f}}};
        Profile.Set_LedgeSensitivity(0.0f);

        auto Params = FCk_GroundNav_FieldParams{};

        Params._OriginXY = FVector2D::ZeroVector;
        Params._Divisions = FIntPoint{2, 2};
        Params._MinZUu = -50.0f;
        Params._MaxZUu = 300.0f;
        Params._Config = Config;
        Params._Profile = Profile;
        Params._MaxClearanceUu = kMaxClearance;

        return Params;
    }

    // Ground reaching past the lattice on every side, so every tile's halo has real world in it.
    auto Make_WholeGround() -> TArray<FBox>
    {
        return TArray<FBox>{FBox{FVector{-400.0, -400.0, -10.0}, FVector{1200.0, 1200.0, 0.0}}};
    }

    // The same ground with a chasm through the middle: a rebuild against this MOVES tiles rather than
    // merely restamping them, which is what a cache key has to notice.
    auto Make_GroundWithChasm() -> TArray<FBox>
    {
        return TArray<FBox>{
            FBox{FVector{-400.0, -400.0, -10.0}, FVector{1200.0, 300.0, 0.0}},
            FBox{FVector{-400.0, 500.0, -10.0}, FVector{1200.0, 1200.0, 0.0}}};
    }

    auto Bake_Field(
        const TArray<FBox>&        InBoxes,
        const FCk_GroundNav_Epoch& InEpoch) -> TSharedPtr<FCk_GroundNav_Field>
    {
        const auto Backend = FCk_GroundNav_GeometryBackend_Stub{InBoxes};

        auto Field = TSharedPtr<FCk_GroundNav_Field>{MakeShared<FCk_GroundNav_Field>()};

        if (NOT DoBake_Field(Backend, Make_FieldParams(), InEpoch, *Field).Get_IsCompleted())
        { return {}; }

        return Field;
    }

    // --------------------------------------------------------------------------------------------------

    // The arrays a field bake never fills, because they are collected from the WORLD rather than from
    // the field: a markup, the two links above, and one agent's corridor. Those carry the members a
    // capture most easily gets wrong - a tag reduced to a name, an agent reduced to its printed name -
    // so the teardown pin walks them too rather than walking empty arrays that would survive anything.
    auto Do_StampWorldCollectedValues(
        FCk_GroundNav_DebugSnapshot& InOutSnapshot) -> void
    {
        auto Markup = FCk_GroundNav_DebugMarkup{};

        Markup._Bounds = FBox{FVector{100.0, 100.0, -10.0}, FVector{300.0, 300.0, 90.0}};
        Markup._AreaTagName = FName{TEXT("Nav.Area.Mud")};
        Markup._RecordId = 2;
        Markup._CostMultiplier = 3.0f;
        Markup._RequestedAtEpoch = 3;
        Markup._IsEnabled = true;
        Markup._IsLive = true;

        InOutSnapshot._Markups.Emplace(Markup);

        InOutSnapshot._Links.Emplace(Make_DisabledLink());
        InOutSnapshot._Links.Emplace(Make_UnresolvedLink());

        auto Corridor = FCk_GroundNav_DebugCorridor{};

        Corridor._Bounds = FBox{FVector{0.0, 0.0, -10.0}, FVector{800.0, 800.0, 90.0}};
        Corridor._PathName = TEXT("GroundNavPath_Fixture");
        Corridor._InflationUu = 50.0f;
        Corridor._CorridorEpoch = 3;
        Corridor._FieldEpoch = 4;
        Corridor._HasField = true;

        InOutSnapshot._Corridors.Emplace(Corridor);

        InOutSnapshot._ChangedBounds.Emplace(
            FBox{FVector{0.0, 0.0, -10.0}, FVector{400.0, 400.0, 90.0}});

        InOutSnapshot._RepairInProgress = true;
        InOutSnapshot._RepairDirtyBounds = FBox{FVector{0.0, 0.0, -10.0}, FVector{200.0, 200.0, 90.0}};
        InOutSnapshot._RepairTileIndices.Emplace(0);
        InOutSnapshot._RepairTileBounds.Emplace(
            FBox{FVector{0.0, 0.0, -50.0}, FVector{400.0, 400.0, 300.0}});
    }

    // --------------------------------------------------------------------------------------------------

    constexpr auto InformEngineOfWorld = false;

    struct FWorldFixture
    {
        UWorld* _World = nullptr;
        FCk_Handle _WorldEntity;
    };

    auto Make_WorldFixture(
        const TCHAR* InWorldName) -> FWorldFixture
    {
        auto Fixture = FWorldFixture{};

        Fixture._World = UWorld::CreateWorld(EWorldType::Game, InformEngineOfWorld, FName{InWorldName});

        if (Fixture._World == nullptr)
        { return Fixture; }

        Fixture._WorldEntity = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(Fixture._World);

        if (ck::Is_NOT_Valid(Fixture._WorldEntity))
        { return Fixture; }

        return Fixture;
    }

    auto Get_IsReady(
        const FWorldFixture& InFixture) -> bool
    {
        return InFixture._World != nullptr && ck::IsValid(InFixture._WorldEntity);
    }

    auto Destroy_WorldFixture(
        FWorldFixture& InFixture) -> void
    {
        if (InFixture._World != nullptr)
        { InFixture._World->DestroyWorld(InformEngineOfWorld); }

        InFixture._World = nullptr;
    }

    // --------------------------------------------------------------------------------------------------

    constexpr auto kSurfaceRevision = int64{4200};

    // A key names the volume by VALUES only, so a test builds one the same way a producer would: the
    // world by the name its UWorld answers to, and the entity by the whole of its id. The world's own
    // transient entity stands in for a volume here - what a key reads off it is an id, and an id is an
    // id whatever entity carries it.
    auto Make_Key(
        const FCk_GroundNav_DebugSnapshot& InSnapshot,
        const FWorldFixture&               InFixture,
        int64                              InSurfaceRevision) -> FCk_GroundNav_DebugSnapshotCacheKey
    {
        auto Key = FCk_GroundNav_DebugSnapshotCacheKey{};

        const auto Entity = InFixture._WorldEntity.Get_Entity();

        Key._WorldName = InFixture._World != nullptr ? InFixture._World->GetFName() : FName{};
        Key._VolumeEntityNumber = static_cast<int32>(Entity.Get_EntityNumber());
        Key._VolumeEntityVersion = static_cast<int32>(Entity.Get_VersionNumber());
        Key._NewestTileEpoch = InSnapshot.Get_NewestTileEpoch();
        Key._SurfaceRevision = InSurfaceRevision;

        return Key;
    }

    // --------------------------------------------------------------------------------------------------

    /**
     * Everything a viewer reads off a capture, folded from every array and every getter it offers.
     *
     * Taken twice - once while the field and the world stand, once after both are gone - because a
     * member that had kept a pointer, a handle or an index it resolved on demand would answer a
     * DIFFERENT number the second time rather than failing outright.
     */
    struct FSnapshotTally
    {
        int32 _OpenBodies = 0;
        int32 _OpenEdgePoints = 0;
        int32 _OpenBodyDescriptionChars = 0;

        int32 _Cells = 0;
        int32 _CellLayerSum = 0;

        int32 _RejectedCells = 0;
        int32 _RejectedCellLayerSum = 0;

        int32 _Plates = 0;
        double _PlateHeightSum = 0.0;

        int32 _Portals = 0;
        int32 _CrossLayerPortals = 0;

        int32 _Tiles = 0;
        int64 _TileEpochSum = 0;

        int32 _Seams = 0;
        double _SeamClearanceSum = 0.0;

        int32 _BoundaryRuns = 0;
        int32 _TileRimRuns = 0;

        int32 _Markups = 0;
        int32 _NamedMarkups = 0;

        int32 _Links = 0;
        int32 _NamedLinks = 0;
        int32 _LinkIdSum = 0;

        int32 _Corridors = 0;
        int32 _CorridorNameChars = 0;

        int32 _ChangedBounds = 0;
        int32 _RepairTileIndices = 0;
        int32 _RepairTileBounds = 0;

        int32 _PlateCount = 0;
        int32 _PortalCount = 0;
        int32 _TileCount = 0;
        int32 _SeamCount = 0;
        int32 _BoundaryCount = 0;
        int32 _BuiltTileCount = 0;
        int32 _RepairTileCount = 0;
        int32 _OpenBodyCount = 0;

        int64 _NewestTileEpoch = 0;
        float _NarrowestPortalUu = 0.0f;
        bool _IsDrawable = false;

        auto operator==(const FSnapshotTally&) const -> bool = default;
    };

    auto Make_Tally(
        const FCk_GroundNav_DebugSnapshot& InSnapshot) -> FSnapshotTally
    {
        auto Result = FSnapshotTally{};

        for (const auto& OpenBody : InSnapshot._OpenBodies)
        {
            ++Result._OpenBodies;
            Result._OpenEdgePoints += OpenBody._OpenEdgePoints.Num();
            Result._OpenBodyDescriptionChars += OpenBody._Description.Len();
        }

        for (const auto& Cell : InSnapshot._Cells)
        {
            ++Result._Cells;
            Result._CellLayerSum += Cell._LayerIndex;
        }

        for (const auto& Plate : InSnapshot._Plates)
        {
            ++Result._Plates;
            Result._PlateHeightSum += static_cast<double>(Plate._HeightRangeUu);
        }

        for (const auto& Portal : InSnapshot._Portals)
        {
            ++Result._Portals;
            Result._CrossLayerPortals += Portal._IsCrossLayer ? 1 : 0;
        }

        for (const auto& Tile : InSnapshot._Tiles)
        {
            ++Result._Tiles;
            Result._TileEpochSum += Tile._Epoch;
        }

        for (const auto& Seam : InSnapshot._Seams)
        {
            ++Result._Seams;
            Result._SeamClearanceSum += static_cast<double>(Seam._TraversalClearanceUu);
        }

        for (const auto& Run : InSnapshot._Boundary)
        {
            ++Result._BoundaryRuns;
            Result._TileRimRuns += Run._IsTileRim ? 1 : 0;
        }

        for (const auto& Cell : InSnapshot._RejectedCells)
        {
            ++Result._RejectedCells;
            Result._RejectedCellLayerSum += Cell._LayerIndex;
        }

        for (const auto& Markup : InSnapshot._Markups)
        {
            ++Result._Markups;
            Result._NamedMarkups += Markup._AreaTagName.IsNone() ? 0 : 1;
        }

        for (const auto& Link : InSnapshot._Links)
        {
            ++Result._Links;
            Result._NamedLinks += Link._AreaTagName.IsNone() ? 0 : 1;
            Result._LinkIdSum += Link._Id;
        }

        for (const auto& Corridor : InSnapshot._Corridors)
        {
            ++Result._Corridors;
            Result._CorridorNameChars += Corridor._PathName.Len();
        }

        for (const auto& Bounds : InSnapshot._ChangedBounds)
        { Result._ChangedBounds += Bounds.IsValid != 0 ? 1 : 0; }

        for (const auto& TileIndex : InSnapshot._RepairTileIndices)
        { Result._RepairTileIndices += TileIndex >= 0 ? 1 : 0; }

        for (const auto& Bounds : InSnapshot._RepairTileBounds)
        { Result._RepairTileBounds += Bounds.IsValid != 0 ? 1 : 0; }

        Result._PlateCount = InSnapshot.Get_PlateCount();
        Result._PortalCount = InSnapshot.Get_PortalCount();
        Result._TileCount = InSnapshot.Get_TileCount();
        Result._SeamCount = InSnapshot.Get_SeamCount();
        Result._BoundaryCount = InSnapshot.Get_BoundaryCount();
        Result._BuiltTileCount = InSnapshot.Get_BuiltTileCount();
        Result._RepairTileCount = InSnapshot.Get_RepairTileCount();
        Result._OpenBodyCount = InSnapshot.Get_OpenBodyCount();
        Result._NewestTileEpoch = InSnapshot.Get_NewestTileEpoch();
        Result._NarrowestPortalUu = InSnapshot.Get_NarrowestPortalUu();
        Result._IsDrawable = InSnapshot.Get_IsDrawable();

        return Result;
    }

    // --------------------------------------------------------------------------------------------------

    /**
     * A backend that answers "I cannot" and nothing else.
     *
     * The Jolt backend reaches BackendUnavailable the same way - Get_IsValid() false - but it can only
     * be driven there by handing it no world context, which trips a harness-escalated ensure
     * (CkGroundNav_GeometryBackend_Jolt.cpp:37-41). The status is produced through the interface entry
     * point instead, which is the seam that exists precisely so a bake can be driven without one.
     */
    class FUnusableBackend final : public ICk_GroundNav_GeometryBackend
    {
    public:
        auto Get_IsValid() const -> bool override
        { return false; }

        auto Get_HasGeometryInBounds(const FBox&) const -> bool override
        { return false; }

        auto Get_StaticBodiesInBounds(const FBox&, TArray<ck::groundnav::FCk_GroundNav_BodyRef>& OutBodies) const -> int32 override
        {
            OutBodies.Reset();
            return 0;
        }

        auto Get_TrianglesInBounds(const FBox&, FCk_GroundNav_GeometryBatch&) const -> int32 override
        { return 0; }

        auto Get_WorldRevision() const -> uint64 override
        { return 0; }

        auto Get_BodyKind(const ck::groundnav::FCk_GroundNav_BodyRef&) const -> ck::groundnav::ECk_GroundNav_BodyKind override
        { return ck::groundnav::ECk_GroundNav_BodyKind::Solid; }

        auto Get_BodyBounds(const ck::groundnav::FCk_GroundNav_BodyRef&) const -> FBox override
        { return FBox{ForceInit}; }

        auto Get_BodyTriangles(const ck::groundnav::FCk_GroundNav_BodyRef&, FCk_GroundNav_GeometryBatch&) const -> int32 override
        { return 0; }

        auto Get_BodyDescription(const ck::groundnav::FCk_GroundNav_BodyRef&) const -> FString override
        { return FString{TEXT("no backend")}; }
    };

    // A region well clear of anything a fixture authors, so "no geometry here" is the scene rather
    // than a near miss.
    auto Make_RegionBakeParams() -> FCk_GroundNav_DebugBakeParams
    {
        auto Params = FCk_GroundNav_DebugBakeParams{};

        Params._Centre = FVector{0.0, 0.0, 0.0};
        Params._Extent = FVector{200.0, 200.0, 100.0};
        Params._Config = FCk_GroundNav_BakeConfig{kCellSize, kCellHeight};
        Params._Profile = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{70.0f, 20.0f}}};
        Params._MaxCells = kUncapped;

        return Params;
    }

    auto Do_AssertFailureStatusIsReadable(
        FAutomationTestBase&               InTest,
        const FCk_GroundNav_DebugSnapshot& InSnapshot,
        EDebugSnapshotStatus               InExpected) -> void
    {
        InTest.TestEqual(TEXT("the derivation answers the status the failure earned"),
            InSnapshot._Status, InExpected);

        InTest.TestFalse(TEXT("and a capture that is not Current is not drawable"),
            InSnapshot.Get_IsDrawable());

        // The summary is how a developer READS the status, so a status nobody can print is a status
        // nobody has.
        InTest.TestTrue(TEXT("and the summary says so rather than being empty"),
            NOT ck::groundnav::Get_DebugSnapshotSummary(InSnapshot).IsEmpty());
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

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Snapshot_OutlivesItsProducer,
    "CkTests.UnitTests.CkGroundNav.Bake.Snapshot_OutlivesItsProducer",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Snapshot_OutlivesItsProducer::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_snapshot;

    auto Fixture = Make_WorldFixture(TEXT("CkTest_GroundNav_SnapshotOutlivesItsProducer"));

    if (NOT TestNotNull(TEXT("the fixture world stands"), Fixture._World))
    { return false; }

    auto Snapshot = FCk_GroundNav_DebugSnapshot{};
    auto WhileStanding = FSnapshotTally{};

    {
        auto Field = Bake_Field(Make_WholeGround(), FCk_GroundNav_Epoch{4});

        if (NOT Field.IsValid())
        {
            AddError(TEXT("the fixture field did not bake, so there is no producer to outlive"));
            Destroy_WorldFixture(Fixture);
            return false;
        }

        auto Published = FCk_GroundNav_FieldPtr{Field};

        world_fields::Publish(Fixture._World, Fixture._WorldEntity, Published, {});

        Snapshot = Make_DebugSnapshotFromField(*Published, kUncapped);
        Do_StampWorldCollectedValues(Snapshot);

        WhileStanding = Make_Tally(Snapshot);

        // A field with real tiles, plates and cells in it, so what follows is an enumeration of
        // something rather than a walk over empty arrays that would survive anything.
        TestTrue(TEXT("the capture has tiles"), WhileStanding._Tiles > 0);
        TestTrue(TEXT("and built ones"), WhileStanding._BuiltTileCount > 0);
        TestTrue(TEXT("and plates"), WhileStanding._Plates > 0);
        TestTrue(TEXT("and cells"), WhileStanding._Cells > 0);
        TestTrue(TEXT("and the world-collected values that carry names"), WhileStanding._NamedLinks > 0);

        world_fields::Unpublish(Fixture._World, Fixture._WorldEntity);

        Published.Reset();
        Field.Reset();
    }

    Destroy_WorldFixture(Fixture);

    // Everything below reads a capture whose field, registry entry and WORLD are all gone. A member
    // that had kept a pointer, a handle or an index it resolved on demand would either fire an ensure
    // here or answer a different number - which is exactly what a viewer drawing a frame after a
    // level teardown would be doing.
    const auto AfterTeardown = Make_Tally(Snapshot);

    TestTrue(TEXT("every count and every getter answers what it answered before the teardown"),
        AfterTeardown == WhileStanding);

    TestEqual(TEXT("and the status came through unchanged"),
        Snapshot._Status, EDebugSnapshotStatus::Current);

    TestTrue(TEXT("and a capture of a completed bake is still drawable"), Snapshot.Get_IsDrawable());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Snapshot_CacheKeyFollowsTheField,
    "CkTests.UnitTests.CkGroundNav.Bake.Snapshot_CacheKeyFollowsTheField",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Snapshot_CacheKeyFollowsTheField::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_snapshot;

    auto Fixture = Make_WorldFixture(TEXT("CkTest_GroundNav_SnapshotCacheKey"));
    auto SecondWorld = Make_WorldFixture(TEXT("CkTest_GroundNav_SnapshotCacheKey_Elsewhere"));

    if (NOT TestTrue(TEXT("both fixture worlds stand and answer an entity"),
        Get_IsReady(Fixture) && Get_IsReady(SecondWorld)))
    {
        Destroy_WorldFixture(SecondWorld);
        Destroy_WorldFixture(Fixture);
        return false;
    }

    const auto FirstField = Bake_Field(Make_WholeGround(), FCk_GroundNav_Epoch{4});
    const auto RebuiltField = Bake_Field(Make_GroundWithChasm(), FCk_GroundNav_Epoch{5});

    if (NOT FirstField.IsValid() || NOT RebuiltField.IsValid())
    {
        AddError(TEXT("a fixture field did not bake, so there is no key to derive"));
        Destroy_WorldFixture(SecondWorld);
        Destroy_WorldFixture(Fixture);
        return false;
    }

    const auto FirstSnapshot = Make_DebugSnapshotFromField(*FirstField, kUncapped);
    const auto RebuiltSnapshot = Make_DebugSnapshotFromField(*RebuiltField, kUncapped);

    // Derived twice from the same field. A key that folded in an address, a build time or anything
    // else the capture merely happened to observe would already differ here, and every staleness
    // decision made against it downstream would be a coin toss.
    const auto FirstKey = Make_Key(FirstSnapshot, Fixture, kSurfaceRevision);
    const auto SameFieldAgain = Make_Key(FirstSnapshot, Fixture, kSurfaceRevision);

    TestTrue(TEXT("the same field derives the same key"), FirstKey.Get_IsEqual(SameFieldAgain));

    TestTrue(TEXT("and the rebuild carries a newer tile epoch"),
        RebuiltSnapshot.Get_NewestTileEpoch() != FirstSnapshot.Get_NewestTileEpoch());

    const auto RebuiltKey = Make_Key(RebuiltSnapshot, Fixture, kSurfaceRevision);

    TestFalse(TEXT("so the rebuilt field derives a different key"), FirstKey.Get_IsEqual(RebuiltKey));

    // The world's revision moves when ANOTHER of its volumes publishes, which changes nothing about
    // this field and everything about whether a viewer is looking at a current world.
    const auto ElsewhereKey = Make_Key(FirstSnapshot, Fixture, kSurfaceRevision + 1);

    TestFalse(TEXT("and a surface revision that moved elsewhere is a different key too"),
        FirstKey.Get_IsEqual(ElsewhereKey));

    // The same field, at the same epoch, named in a SECOND world. The volume id is held equal on
    // purpose so the world's name is the only thing that differs: entity numbers are handed out per
    // registry, so two worlds running at once genuinely do hold the same ones, and a key without the
    // world would let one world's capture answer for the other's.
    auto OtherWorldKey = Make_Key(FirstSnapshot, SecondWorld, kSurfaceRevision);

    OtherWorldKey._VolumeEntityNumber = FirstKey._VolumeEntityNumber;
    OtherWorldKey._VolumeEntityVersion = FirstKey._VolumeEntityVersion;

    TestFalse(TEXT("and the same field at the same epoch under another world's name is a different key"),
        FirstKey.Get_IsEqual(OtherWorldKey));

    // A number is a SLOT: destroy the volume holding it and the next entity created inherits it under
    // a new version. A key naming only the number would call the newcomer's field the old one's.
    auto RecycledNumberKey = FirstKey;

    RecycledNumberKey._VolumeEntityVersion = FirstKey._VolumeEntityVersion + 1;

    TestFalse(TEXT("and the same number handed out again under a newer version is a different key"),
        FirstKey.Get_IsEqual(RecycledNumberKey));

    Destroy_WorldFixture(SecondWorld);
    Destroy_WorldFixture(Fixture);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Snapshot_CacheReplacesTheWholeValue,
    "CkTests.UnitTests.CkGroundNav.Bake.Snapshot_CacheReplacesTheWholeValue",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Snapshot_CacheReplacesTheWholeValue::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_snapshot;

    auto Fixture = Make_WorldFixture(TEXT("CkTest_GroundNav_SnapshotCacheReplace"));

    if (NOT TestTrue(TEXT("the fixture world stands and answers an entity"), Get_IsReady(Fixture)))
    {
        Destroy_WorldFixture(Fixture);
        return false;
    }

    const auto FirstField = Bake_Field(Make_WholeGround(), FCk_GroundNav_Epoch{4});
    const auto RebuiltField = Bake_Field(Make_GroundWithChasm(), FCk_GroundNav_Epoch{5});

    if (NOT FirstField.IsValid() || NOT RebuiltField.IsValid())
    {
        AddError(TEXT("a fixture field did not bake, so there is nothing to cache"));
        Destroy_WorldFixture(Fixture);
        return false;
    }

    const auto FirstSnapshot = Make_DebugSnapshotFromField(*FirstField, kUncapped);
    const auto RebuiltSnapshot = Make_DebugSnapshotFromField(*RebuiltField, kUncapped);

    const auto FirstKey = Make_Key(FirstSnapshot, Fixture, kSurfaceRevision);
    const auto RebuiltKey = Make_Key(RebuiltSnapshot, Fixture, kSurfaceRevision);

    auto Cache = FCk_GroundNav_DebugSnapshotCache{};

    TestFalse(TEXT("an empty cache answers no key"), Cache.TryGet_Current(FirstKey).IsValid());

    Cache.Replace(FirstKey, FirstSnapshot);

    TestTrue(TEXT("and reports the key it now holds"), Cache.Get_Key().Get_IsEqual(FirstKey));

    const auto Held = Cache.TryGet_Current(FirstKey);

    if (NOT TestTrue(TEXT("which hands the capture back"), Held.IsValid()))
    { return false; }

    TestFalse(TEXT("while a key it was not captured under gets nothing"),
        Cache.TryGet_Current(RebuiltKey).IsValid());

    // The two captures have to be measurably different bakes, or a replace that quietly kept half of
    // the old value would pass every assertion below.
    TestTrue(TEXT("the rebuild walks over different ground"),
        RebuiltSnapshot._WalkableCellCount != FirstSnapshot._WalkableCellCount);

    Cache.Replace(RebuiltKey, RebuiltSnapshot);

    const auto Replaced = Cache.TryGet_Current(RebuiltKey);

    if (NOT TestTrue(TEXT("the replacement is what the new key answers"), Replaced.IsValid()))
    { return false; }

    TestEqual(TEXT("the held cells are the replacement's"),
        Replaced->_Cells.Num(), RebuiltSnapshot._Cells.Num());

    TestEqual(TEXT("and its plates"), Replaced->Get_PlateCount(), RebuiltSnapshot.Get_PlateCount());
    TestEqual(TEXT("and its tiles"), Replaced->Get_TileCount(), RebuiltSnapshot.Get_TileCount());

    TestEqual(TEXT("and the counted total, which never came from the value it replaced"),
        Replaced->_WalkableCellCount, RebuiltSnapshot._WalkableCellCount);

    TestEqual(TEXT("and the epoch"),
        Replaced->Get_NewestTileEpoch(), RebuiltSnapshot.Get_NewestTileEpoch());

    TestFalse(TEXT("and the superseded key now answers null"),
        Cache.TryGet_Current(FirstKey).IsValid());

    // A reference taken BEFORE the replace still reads the value it was handed, which is what keeps a
    // reader mid-draw from being torn by a publish landing under it.
    TestEqual(TEXT("while the reference taken before it still reads the capture it took"),
        Held->_WalkableCellCount, FirstSnapshot._WalkableCellCount);

    Destroy_WorldFixture(Fixture);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Snapshot_BackendThatCannotAnswerIsBackendUnavailable,
    "CkTests.UnitTests.CkGroundNav.Bake.Snapshot_BackendThatCannotAnswerIsBackendUnavailable",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Snapshot_BackendThatCannotAnswerIsBackendUnavailable::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_snapshot;

    const auto Backend = FUnusableBackend{};

    const auto Snapshot = Make_DebugSnapshotFromBackend(Backend, Make_RegionBakeParams());

    Do_AssertFailureStatusIsReadable(*this, Snapshot, EDebugSnapshotStatus::BackendUnavailable);

    // The region is stamped BEFORE the backend is consulted, so a viewer pointed at a world with no
    // physics still knows which ground it was asking about.
    TestTrue(TEXT("and the capture still names the region it was asked for"),
        Snapshot._Region.IsValid != 0);

    TestEqual(TEXT("while nothing was baked"), Snapshot._Cells.Num(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Snapshot_RegionWithNoGeometryIsNoGeometryInRegion,
    "CkTests.UnitTests.CkGroundNav.Bake.Snapshot_RegionWithNoGeometryIsNoGeometryInRegion",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Snapshot_RegionWithNoGeometryIsNoGeometryInRegion::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_snapshot;

    // A usable backend holding nothing. This is the distinction the whole status vocabulary exists
    // for: the bake RAN and found no world here, which is not the same as a bake that could not run.
    const auto Backend = FCk_GroundNav_GeometryBackend_Stub{TArray<FBox>{}};

    const auto Snapshot = Make_DebugSnapshotFromBackend(Backend, Make_RegionBakeParams());

    Do_AssertFailureStatusIsReadable(*this, Snapshot, EDebugSnapshotStatus::NoGeometryInRegion);

    TestEqual(TEXT("and no triangle was found to bake from"), Snapshot._SourceTriangleCount, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Snapshot_RefusedStageIsFailed,
    "CkTests.UnitTests.CkGroundNav.Bake.Snapshot_RefusedStageIsFailed",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Snapshot_RefusedStageIsFailed::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_snapshot;

    // Real geometry, so the bake gets past the empty-region answer and into the stages.
    const auto Backend = FCk_GroundNav_GeometryBackend_Stub{
        TArray<FBox>{FBox{FVector{-300.0, -300.0, -10.0}, FVector{300.0, 300.0, 0.0}}}};

    auto Params = Make_RegionBakeParams();

    // Half-unit cells over a 400uu square region is 800 columns per side, so 640,000 columns - past
    // FCk_GroundNav_BakeConfig's own MaxColumnsPerTile ceiling of 262,144, which the rasterizer
    // refuses with LimitExceeded (CkGroundNav_Rasterize.cpp:218-222) BEFORE it allocates anything. A
    // stage that refused its inputs is what Failed means.
    Params._Config = FCk_GroundNav_BakeConfig{0.5f, kCellHeight};

    const auto Snapshot = Make_DebugSnapshotFromBackend(Backend, Params);

    Do_AssertFailureStatusIsReadable(*this, Snapshot, EDebugSnapshotStatus::Failed);

    // The triangles the backend DID hand over are still reported: a refused stage is not a refusal to
    // say what reached it.
    TestTrue(TEXT("and the geometry that reached the refused stage is still counted"),
        Snapshot._SourceTriangleCount > 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Snapshot_CompletedBakeIsCurrent,
    "CkTests.UnitTests.CkGroundNav.Bake.Snapshot_CompletedBakeIsCurrent",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Snapshot_CompletedBakeIsCurrent::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_snapshot;

    // The same derivation, the same backend seam, with a scene it can actually bake. Without this the
    // three failure pins above would pass equally well against a derivation that never succeeds.
    const auto Backend = FCk_GroundNav_GeometryBackend_Stub{
        TArray<FBox>{FBox{FVector{-300.0, -300.0, -10.0}, FVector{300.0, 300.0, 0.0}}}};

    const auto Snapshot = Make_DebugSnapshotFromBackend(Backend, Make_RegionBakeParams());

    TestEqual(TEXT("a bake that ran to the end is Current"),
        Snapshot._Status, EDebugSnapshotStatus::Current);

    TestTrue(TEXT("and drawable"), Snapshot.Get_IsDrawable());

    TestTrue(TEXT("and it walked over something"), Snapshot._Cells.Num() > 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
