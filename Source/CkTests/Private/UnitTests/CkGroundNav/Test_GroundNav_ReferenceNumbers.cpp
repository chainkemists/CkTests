// The reference fixture, and the numbers the phase records against it.
//
// A tracked number is PINNED here rather than printed somewhere: a probe count that drifts is either a
// bake that changed or a fixture that changed, and both are things a reader of this file should be
// told about loudly rather than have to notice. The exact values are asserted, so a change to any bake
// stage that moves them fails here first and has to be explained.
//
// The fixture is deliberately not a gym scene or a level. It is a fixed piece of geometry defined in
// this file, so the numbers mean the same thing on every machine and in every checkout.

#include "CkGroundNav/Backend/CkGroundNav_GeometryBackend_Stub.h"
#include "CkGroundNav/CkGroundNav_Log.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"

#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_reference
{
    using ck::groundnav::DoBake_Field;
    using ck::groundnav::FCk_GroundNav_Epoch;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldParams;
    using ck::groundnav::FCk_GroundNav_GeometryBackend_Stub;

    constexpr auto kCellSize = 25.0f;
    constexpr auto kCellHeight = 10.0f;
    constexpr auto kTileSize = 800.0f;
    constexpr auto kMaxClearance = 200.0f;

    /**
     * The reference scene: a 2400 uu floor with two rooms partitioned off it, a corridor joining them,
     * a raised platform reached over a step, and a pillar in the open.
     *
     * Chosen to exercise every stage rather than to be large — it has layers, a pinch, plates of very
     * different sizes, and crossings both within and between tiles.
     */
    auto Make_ReferenceScene() -> TArray<FBox>
    {
        auto Boxes = TArray<FBox>{};

        // The ground, reaching past the field so every tile halo has real world in it.
        Boxes.Emplace(FBox{FVector{-400.0, -400.0, -10.0}, FVector{2800.0, 2800.0, 0.0}});

        // Two dividing walls with a gap between them: the pinch every route between the halves uses.
        Boxes.Emplace(FBox{FVector{1150.0, 0.0, 0.0}, FVector{1250.0, 1000.0, 300.0}});
        Boxes.Emplace(FBox{FVector{1150.0, 1400.0, 0.0}, FVector{1250.0, 2400.0, 300.0}});

        // A raised platform over part of the floor: two layers where it overhangs.
        Boxes.Emplace(FBox{FVector{1600.0, 1600.0, 240.0}, FVector{2200.0, 2200.0, 260.0}});

        // A pillar in the open, so clearance varies away from every wall.
        Boxes.Emplace(FBox{FVector{500.0, 1800.0, 0.0}, FVector{700.0, 2000.0, 300.0}});

        return Boxes;
    }

    auto Make_Params() -> FCk_GroundNav_FieldParams
    {
        auto Config = FCk_GroundNav_BakeConfig{kCellSize, kCellHeight};
        Config.Set_TileSizeUu(kTileSize);

        auto Profile = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{70.0f, 20.0f}}};
        Profile.Set_LedgeSensitivity(0.0f);

        auto Params = FCk_GroundNav_FieldParams{};

        Params._OriginXY = FVector2D::ZeroVector;
        Params._Divisions = FIntPoint{3, 3};
        Params._MinZUu = -50.0f;
        Params._MaxZUu = 400.0f;
        Params._Config = Config;
        Params._Profile = Profile;
        Params._MaxClearanceUu = kMaxClearance;

        return Params;
    }

    // Pinned from a green run against the fixture above. If any of these moves, a bake stage changed
    // what it produces for the same input, and the failure names the whole set so the change can be
    // read rather than guessed at. Every re-pin must explain its delta in the commit.
    //
    // The probe count is in the unit FCk_GroundNav_BakeStageResult defines: one innermost cell or span
    // read, billed identically by every stage. It was 117962 when the stages each billed something of
    // their own — triangles, spans, a plate count — and the sum measured nothing.
    // 825978 before the closure check, + 60 for it: the scene's 5 boxes are each 12 triangles, every
    // one of them overlaps at least one tile's halo, and a body's whole mesh is read once per BUILD —
    // so 5 * 12 = 60 probes, whatever tiling or slicing produced them.
    // 826038 before the clearance transform started consulting the connection field: every relax now
    // reads whether the neighbour is linked (one read straight, up to four around a diagonal), which is
    // what makes a wall top or a ledge an obstacle instead of open ground. + 252422 for those reads.
    // 1078460 before boundary runs were derived at bake: every cell along every plate side is visited
    // once to decide whether a crossing covers it. + 1824 for those visits.
    constexpr auto kReferenceProbes = 1080284;
    constexpr auto kReferenceWalkableCells = 9792;
    constexpr auto kReferencePlates = 22;
    constexpr auto kReferencePortals = 6;
    constexpr auto kReferenceSeams = 17;
    constexpr auto kReferenceComponents = 5;

    struct FReferenceNumbers
    {
        int32 _ProbesSpent = 0;
        int32 _WalkableCells = 0;
        int32 _Plates = 0;
        int32 _Portals = 0;
        int32 _Seams = 0;
        int32 _Components = 0;
        float _CollapseRatio = 0.0f;

        // The bake's cost, both halves. Bytes are exact and deterministic for a fixture, so they are
        // pinned; wall time is a measurement of this machine and is only ever reported.
        int64 _FieldBytes = 0;
        double _BakeMilliseconds = 0.0;
    };

    auto Bake_Reference(FReferenceNumbers& OutNumbers) -> bool
    {
        const auto Backend = FCk_GroundNav_GeometryBackend_Stub{Make_ReferenceScene()};

        auto Field = FCk_GroundNav_Field{};

        const auto StartedAt = FPlatformTime::Seconds();
        const auto Result = DoBake_Field(Backend, Make_Params(), FCk_GroundNav_Epoch{1}, Field);
        const auto ElapsedMilliseconds = (FPlatformTime::Seconds() - StartedAt) * 1000.0;

        if (NOT Result.Get_IsCompleted())
        { return false; }

        OutNumbers = FReferenceNumbers{};
        OutNumbers._ProbesSpent = Result.Get_ProbesSpent();
        OutNumbers._FieldBytes = static_cast<int64>(Field.Get_AllocatedSize());
        OutNumbers._BakeMilliseconds = ElapsedMilliseconds;
        OutNumbers._Seams = Field.Get_SeamPortalCount();
        OutNumbers._Components = Field.Get_ReachabilityComponentCount();

        for (const auto& Tile : Field._Tiles)
        {
            OutNumbers._WalkableCells += Tile.Get_WalkableCellCount();
            OutNumbers._Plates += Tile._Plates._Plates.Num();
            OutNumbers._Portals += Tile._Portals.Get_PortalCount();
        }

        OutNumbers._CollapseRatio = OutNumbers._Plates > 0
            ? static_cast<float>(OutNumbers._WalkableCells) / static_cast<float>(OutNumbers._Plates)
            : 0.0f;

        return true;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Reference_NumbersAreStableAndRecorded,
    "CkTests.UnitTests.CkGroundNav.Bake.Reference_NumbersAreStableAndRecorded",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Reference_NumbersAreStableAndRecorded::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_reference;

    auto Numbers = FReferenceNumbers{};

    if (NOT TestTrue(TEXT("the reference scene bakes"), Bake_Reference(Numbers)))
    { return false; }

    // Reported through the failure channel deliberately: these are the phase's tracked numbers, and the
    // point of the message is that it names them all when any one of them moves.
    const auto Report = FString::Printf(
        TEXT("reference: probes %d, walkable cells %d, plates %d (collapse %.2f), portals %d, seams %d, components %d, field %lld bytes, %.2f ms"),
        Numbers._ProbesSpent, Numbers._WalkableCells, Numbers._Plates, Numbers._CollapseRatio,
        Numbers._Portals, Numbers._Seams, Numbers._Components, Numbers._FieldBytes, Numbers._BakeMilliseconds);

    // The wall time is this machine's and is never asserted; it is written to the log so the phase
    // can record a measured bake cost beside the numbers it pins.
    ck::groundnav::Display(TEXT("{}"), Report);

    // The scene has to be worth measuring before any number from it means anything.
    if (NOT TestTrue(FString::Printf(TEXT("the reference scene has ground, plates and crossings [%s]"), *Report),
        Numbers._WalkableCells > 0 && Numbers._Plates > 0 && Numbers._Portals > 0))
    { return false; }

    TestTrue(FString::Printf(TEXT("with crossings between its tiles too [%s]"), *Report), Numbers._Seams > 0);

    // Determinism is what makes a probe count assertable at all: the same fixture and config must spend
    // the same probes every run, or no budget expressed in probes could be held to.
    auto Repeat = FReferenceNumbers{};

    if (NOT TestTrue(TEXT("the reference scene bakes again"), Bake_Reference(Repeat)))
    { return false; }

    TestEqual(TEXT("the probe count is identical across runs"), Repeat._ProbesSpent, Numbers._ProbesSpent);
    TestEqual(TEXT("and so is every product count"), Repeat._Plates, Numbers._Plates);
    TestEqual(TEXT("including the crossings"), Repeat._Portals, Numbers._Portals);
    TestEqual(TEXT("and the seams"), Repeat._Seams, Numbers._Seams);

    // The pinned values. A change to any bake stage that moves one of these fails HERE, with the whole
    // set named, rather than somewhere downstream with a number nobody recorded.
    TestEqual(FString::Printf(TEXT("probes spent on the reference scene [%s]"), *Report),
        Numbers._ProbesSpent, kReferenceProbes);

    TestEqual(FString::Printf(TEXT("walkable cells on the reference scene [%s]"), *Report),
        Numbers._WalkableCells, kReferenceWalkableCells);

    TestEqual(FString::Printf(TEXT("plates on the reference scene [%s]"), *Report),
        Numbers._Plates, kReferencePlates);

    TestEqual(FString::Printf(TEXT("crossings within tiles on the reference scene [%s]"), *Report),
        Numbers._Portals, kReferencePortals);

    TestEqual(FString::Printf(TEXT("seams between tiles on the reference scene [%s]"), *Report),
        Numbers._Seams, kReferenceSeams);

    TestEqual(FString::Printf(TEXT("reachability components on the reference scene [%s]"), *Report),
        Numbers._Components, kReferenceComponents);

    TestEqual(TEXT("the field's footprint is identical across runs"), Repeat._FieldBytes, Numbers._FieldBytes);

    TestTrue(FString::Printf(TEXT("the published field holds its tiles on the heap [%s]"), *Report),
        Numbers._FieldBytes > 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
