// The retained debug draw.
//
// A view makes one claim: that it drew the capture it was handed. The assertions here are about that
// claim - that each mode emits exactly as many outlines as the capture has things to outline, that a
// capture which is not drawable emits its status and nothing else, and that a field standing still
// costs one rebuild rather than one per frame.

#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkGroundNav/Backend/CkGroundNav_GeometryBackend_Stub.h"
#include "CkGroundNav/Debug/CkGroundNav_DebugDraw.h"
#include "CkGroundNav/Debug/CkGroundNav_DebugSnapshot.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"

#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

#include <Engine/World.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_debugdraw
{
    using ck::groundnav::DoBake_Field;
    using ck::groundnav::EDebugDrawGroup;
    using ck::groundnav::EDebugDrawMode;
    using ck::groundnav::EDebugSnapshotStatus;
    using ck::groundnav::FCk_GroundNav_DebugDrawSelection;
    using ck::groundnav::FCk_GroundNav_DebugLink;
    using ck::groundnav::FCk_GroundNav_DebugSnapshot;
    using ck::groundnav::FCk_GroundNav_DebugSnapshotCacheKey;
    using ck::groundnav::FCk_GroundNav_Epoch;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldParams;
    using ck::groundnav::FCk_GroundNav_GeometryBackend_Stub;
    using ck::groundnav::Make_DebugSnapshotDrawBuild;
    using ck::groundnav::Make_DebugSnapshotFromField;

    constexpr auto kCellSize = 25.0f;
    constexpr auto kCellHeight = 10.0f;
    constexpr auto kTileSize = 400.0f;
    constexpr auto kMaxClearance = 100.0f;

    constexpr auto kUncapped = TNumericLimits<int32>::Max();

    // The same 2x2 lattice of 400uu tiles the snapshot pins bake, so a count read here is comparable
    // with one read there.
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

    // The same ground with a chasm through the middle: baked at a later epoch it is a genuinely
    // different capture, which is what a key change has to be about.
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

    // Two links, stamped by hand for the same reason the snapshot pins stamp them: a field bake never
    // fills that array - it is collected from the world - and a draw that carried no links would pass
    // the per-mode counts by drawing nothing.
    auto Do_StampLinks(
        FCk_GroundNav_DebugSnapshot& InOutSnapshot) -> void
    {
        auto Resolved = FCk_GroundNav_DebugLink{};

        Resolved._Start = FVector{100.0, 200.0, 0.0};
        Resolved._End = FVector{100.0, 200.0, 400.0};
        Resolved._Id = 3;
        Resolved._Direction = ECk_GroundNav_LinkDirection::Bidirectional;
        Resolved._StartStatus = ECk_NavSurface_QueryStatus::Success;
        Resolved._EndStatus = ECk_NavSurface_QueryStatus::Success;
        Resolved._Enabled = true;

        InOutSnapshot._Links.Emplace(Resolved);

        // An end with no ground under it: it still draws, because nothing drawn and nothing authored
        // are the two states an investigation is trying to tell apart.
        auto Unresolved = FCk_GroundNav_DebugLink{};

        Unresolved._Start = FVector{900.0, 900.0, 0.0};
        Unresolved._End = FVector{900.0, 900.0, 300.0};
        Unresolved._Id = 11;
        Unresolved._Direction = ECk_GroundNav_LinkDirection::Forward;
        Unresolved._StartStatus = ECk_NavSurface_QueryStatus::Success;
        Unresolved._EndStatus = ECk_NavSurface_QueryStatus::NoSurface;
        Unresolved._Enabled = true;

        InOutSnapshot._Links.Emplace(Unresolved);
    }

    auto Make_FixtureCapture(
        const TArray<FBox>&        InBoxes,
        const FCk_GroundNav_Epoch& InEpoch,
        FCk_GroundNav_DebugSnapshot& OutSnapshot) -> bool
    {
        const auto Field = Bake_Field(InBoxes, InEpoch);

        if (NOT Field.IsValid())
        { return false; }

        OutSnapshot = Make_DebugSnapshotFromField(*Field, kUncapped);
        Do_StampLinks(OutSnapshot);

        return true;
    }

    auto Make_Selection(
        EDebugDrawMode InMode) -> FCk_GroundNav_DebugDrawSelection
    {
        auto Selection = FCk_GroundNav_DebugDrawSelection{};

        Selection._Mode = InMode;
        Selection._DrawLinks = true;

        return Selection;
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

    constexpr auto kSurfaceRevision = int64{4200};

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

    // Ten is enough to tell "once" from "once per frame" and short enough that a failure names the
    // frame it happened on rather than a number nobody reads.
    constexpr auto kFrameCount = 10;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_DebugDraw_StaticFieldRebuildsOnce,
    "CkTests.UnitTests.CkGroundNav.DebugDraw.StaticFieldRebuildsOnce",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_DebugDraw_StaticFieldRebuildsOnce::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_debugdraw;

    auto Fixture = Make_WorldFixture(TEXT("CkTest_GroundNav_DebugDrawStaticField"));

    if (NOT TestTrue(TEXT("the fixture world stands and answers an entity"), Get_IsReady(Fixture)))
    {
        Destroy_WorldFixture(Fixture);
        return false;
    }

    auto Snapshot = FCk_GroundNav_DebugSnapshot{};

    if (NOT Make_FixtureCapture(Make_WholeGround(), FCk_GroundNav_Epoch{4}, Snapshot))
    {
        AddError(TEXT("the fixture field did not bake, so there is nothing to draw"));
        Destroy_WorldFixture(Fixture);
        return false;
    }

    const auto Key = Make_Key(Snapshot, Fixture, kSurfaceRevision);
    const auto Selection = Make_Selection(EDebugDrawMode::Plates);

    for (auto Frame = 0; Frame < kFrameCount; ++Frame)
    {
        ck::groundnav::Do_UpdateRetainedDebugDraw(Fixture._World, Snapshot, Key, Selection);
    }

    // The whole point of the retained tier: a field nobody moved is emitted once and then costs
    // nothing, where an immediate draw re-emitted every one of these frames.
    TestEqual(TEXT("ten frames of a field that did not move cost one rebuild"),
        ck::groundnav::Get_RetainedDebugDrawRebuildCount(Fixture._World, EDebugDrawGroup::Field), 1);

    TestTrue(TEXT("and that rebuild left retained geometry standing"),
        ck::groundnav::Get_RetainedDebugDrawSetCount(Fixture._World, EDebugDrawGroup::Field) > 0);

    const auto Tally = ck::groundnav::Get_RetainedDebugDrawTally(Fixture._World, EDebugDrawGroup::Field);

    TestEqual(TEXT("holding the plates the capture found"), Tally._PlateBoxes, Snapshot.Get_PlateCount());

    ck::groundnav::Do_ReleaseRetainedDebugDraw(Fixture._World);

    TestEqual(TEXT("and releasing it drops every set"),
        ck::groundnav::Get_RetainedDebugDrawSetCount(Fixture._World, EDebugDrawGroup::Field), 0);

    Destroy_WorldFixture(Fixture);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_DebugDraw_KeyOrSelectionChangeRebuildsOnceMore,
    "CkTests.UnitTests.CkGroundNav.DebugDraw.KeyOrSelectionChangeRebuildsOnceMore",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_DebugDraw_KeyOrSelectionChangeRebuildsOnceMore::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_debugdraw;

    auto Fixture = Make_WorldFixture(TEXT("CkTest_GroundNav_DebugDrawKeyChange"));

    if (NOT TestTrue(TEXT("the fixture world stands and answers an entity"), Get_IsReady(Fixture)))
    {
        Destroy_WorldFixture(Fixture);
        return false;
    }

    auto First = FCk_GroundNav_DebugSnapshot{};
    auto Rebuilt = FCk_GroundNav_DebugSnapshot{};

    if (NOT Make_FixtureCapture(Make_WholeGround(), FCk_GroundNav_Epoch{4}, First) ||
        NOT Make_FixtureCapture(Make_GroundWithChasm(), FCk_GroundNav_Epoch{5}, Rebuilt))
    {
        AddError(TEXT("a fixture field did not bake, so there is nothing to redraw"));
        Destroy_WorldFixture(Fixture);
        return false;
    }

    const auto FirstKey = Make_Key(First, Fixture, kSurfaceRevision);
    const auto RebuiltKey = Make_Key(Rebuilt, Fixture, kSurfaceRevision);

    // The two captures have to be a measurably different bake, or a gate that never noticed anything
    // would pass this by rebuilding on the key alone.
    TestTrue(TEXT("the rebuild walks over different ground"),
        Rebuilt._WalkableCellCount != First._WalkableCellCount);

    const auto Plates = Make_Selection(EDebugDrawMode::Plates);

    for (auto Frame = 0; Frame < kFrameCount; ++Frame)
    {
        ck::groundnav::Do_UpdateRetainedDebugDraw(Fixture._World, First, FirstKey, Plates);
    }

    TestEqual(TEXT("the standing field cost one rebuild"),
        ck::groundnav::Get_RetainedDebugDrawRebuildCount(Fixture._World, EDebugDrawGroup::Field), 1);

    for (auto Frame = 0; Frame < kFrameCount; ++Frame)
    {
        ck::groundnav::Do_UpdateRetainedDebugDraw(Fixture._World, Rebuilt, RebuiltKey, Plates);
    }

    TestEqual(TEXT("a republished field costs exactly one more, not one per frame"),
        ck::groundnav::Get_RetainedDebugDrawRebuildCount(Fixture._World, EDebugDrawGroup::Field), 2);

    TestEqual(TEXT("and what stands is the REPLACEMENT's plates"),
        ck::groundnav::Get_RetainedDebugDrawTally(Fixture._World, EDebugDrawGroup::Field)._PlateBoxes,
        Rebuilt.Get_PlateCount());

    // A selection change moves nothing about the capture, and a gate reading only the key would miss
    // it - which is a viewer that answers the old question after the developer asked a new one.
    const auto Boundary = Make_Selection(EDebugDrawMode::Boundary);

    for (auto Frame = 0; Frame < kFrameCount; ++Frame)
    {
        ck::groundnav::Do_UpdateRetainedDebugDraw(Fixture._World, Rebuilt, RebuiltKey, Boundary);
    }

    TestEqual(TEXT("a mode change costs exactly one more"),
        ck::groundnav::Get_RetainedDebugDrawRebuildCount(Fixture._World, EDebugDrawGroup::Field), 3);

    TestEqual(TEXT("and what stands is the boundary, not the plates"),
        ck::groundnav::Get_RetainedDebugDrawTally(Fixture._World, EDebugDrawGroup::Field)._BoundarySegments,
        Rebuilt.Get_BoundaryCount());

    ck::groundnav::Do_ReleaseRetainedDebugDraw(Fixture._World);

    Destroy_WorldFixture(Fixture);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_DebugDraw_RetainedModesDrawTheCapturesOwnCounts,
    "CkTests.UnitTests.CkGroundNav.DebugDraw.RetainedModesDrawTheCapturesOwnCounts",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_DebugDraw_RetainedModesDrawTheCapturesOwnCounts::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_debugdraw;

    auto Snapshot = FCk_GroundNav_DebugSnapshot{};

    if (NOT Make_FixtureCapture(Make_WholeGround(), FCk_GroundNav_Epoch{4}, Snapshot))
    {
        AddError(TEXT("the fixture field did not bake, so there is nothing to count"));
        return false;
    }

    // A build is a pure function of the capture and the selection, so what a mode draws is asserted
    // with no world, no backend and no renderer in the way.
    //
    // The five modes with RETAINED line geometry are the five counted here. Clearance, Layers and
    // Rejected are per-cell POINT views drawn immediately - PMG's line sets carry no points - so they
    // emit nothing into a build and there is no tally of theirs to compare against.
    const auto Plates = Make_DebugSnapshotDrawBuild(Snapshot, Make_Selection(EDebugDrawMode::Plates));

    TestTrue(TEXT("the capture has plates to outline"), Snapshot.Get_PlateCount() > 0);

    TestEqual(TEXT("the plate view draws one outline per plate"),
        Plates._Tally._PlateBoxes, Snapshot.Get_PlateCount());

    TestEqual(TEXT("and the region box, on every status and in every mode"),
        Plates._Tally._RegionBoxes, 1);

    TestEqual(TEXT("and one span per link, which is overlaid in every mode"),
        Plates._Tally._LinkSegments, Snapshot._Links.Num());

    const auto Portals = Make_DebugSnapshotDrawBuild(Snapshot, Make_Selection(EDebugDrawMode::Portals));

    TestEqual(TEXT("the portal view draws one segment per crossing"),
        Portals._Tally._PortalSegments, Snapshot.Get_PortalCount());

    const auto Boundary = Make_DebugSnapshotDrawBuild(Snapshot, Make_Selection(EDebugDrawMode::Boundary));

    TestTrue(TEXT("the capture has boundary runs to draw"), Snapshot.Get_BoundaryCount() > 0);

    TestEqual(TEXT("the boundary view draws one segment per run"),
        Boundary._Tally._BoundarySegments, Snapshot.Get_BoundaryCount());

    const auto Tiles = Make_DebugSnapshotDrawBuild(Snapshot, Make_Selection(EDebugDrawMode::Tiles));

    TestEqual(TEXT("the tile view draws one box per tile, built or not"),
        Tiles._Tally._TileBoxes, Snapshot.Get_TileCount());

    TestEqual(TEXT("and one segment per seam"), Tiles._Tally._SeamSegments, Snapshot.Get_SeamCount());

    const auto Links = Make_DebugSnapshotDrawBuild(Snapshot, Make_Selection(EDebugDrawMode::Links));

    TestEqual(TEXT("the link view dims the plates rather than dropping them"),
        Links._Tally._PlateBoxes, Snapshot.Get_PlateCount());

    TestEqual(TEXT("and still draws every link"), Links._Tally._LinkSegments, Snapshot._Links.Num());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_DebugDraw_ACaptureThatIsNotCurrentDrawsOnlyItsStatus,
    "CkTests.UnitTests.CkGroundNav.DebugDraw.ACaptureThatIsNotCurrentDrawsOnlyItsStatus",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_DebugDraw_ACaptureThatIsNotCurrentDrawsOnlyItsStatus::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_debugdraw;

    auto Snapshot = FCk_GroundNav_DebugSnapshot{};

    if (NOT Make_FixtureCapture(Make_WholeGround(), FCk_GroundNav_Epoch{4}, Snapshot))
    {
        AddError(TEXT("the fixture field did not bake, so there is nothing to withhold"));
        return false;
    }

    // A capture carrying a whole field's geometry, told it is not Current. Everything below would
    // pass trivially on an empty capture; the point is that a FAILED status withholds geometry the
    // viewer is holding.
    TestTrue(TEXT("the capture has plates"), Snapshot.Get_PlateCount() > 0);
    TestTrue(TEXT("and tiles"), Snapshot.Get_TileCount() > 0);
    TestTrue(TEXT("and links"), Snapshot._Links.Num() > 0);

    const EDebugSnapshotStatus EveryFailingStatus[] = {
        EDebugSnapshotStatus::NeverBuilt,
        EDebugSnapshotStatus::BackendUnavailable,
        EDebugSnapshotStatus::NoGeometryInRegion,
        EDebugSnapshotStatus::Failed};

    for (const auto& Status : EveryFailingStatus)
    {
        auto Failing = Snapshot;
        Failing._Status = Status;

        const auto Build = Make_DebugSnapshotDrawBuild(Failing, Make_Selection(EDebugDrawMode::Plates));

        // The status element - the region box - and nothing else. Failure is a status, never an empty
        // scene, and never the geometry of a bake that did not happen.
        TestEqual(FString::Printf(TEXT("%s draws the region it was asked about"),
                ck::groundnav::Get_StatusName(Status)),
            Build._Tally._RegionBoxes, 1);

        TestEqual(FString::Printf(TEXT("%s draws nothing else"),
                ck::groundnav::Get_StatusName(Status)),
            Build.Get_ElementCount(), 1);

        TestEqual(FString::Printf(TEXT("%s draws no plate"), ck::groundnav::Get_StatusName(Status)),
            Build._Tally._PlateBoxes, 0);

        TestEqual(FString::Printf(TEXT("%s draws no link"), ck::groundnav::Get_StatusName(Status)),
            Build._Tally._LinkSegments, 0);
    }

    // The same capture left alone still draws, or the four above would be asserting that this mode
    // draws nothing at all.
    const auto Drawable = Make_DebugSnapshotDrawBuild(Snapshot, Make_Selection(EDebugDrawMode::Plates));

    TestTrue(TEXT("while the Current capture draws its whole field"), Drawable.Get_ElementCount() > 1);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
