// The closed-collision contract, and the check that enforces it.
//
// A Solid body the bake reads must be a closed mesh. The bake sees faces and never an interior, so a
// wall with no underside presents nothing in the columns beneath it and bakes as OPEN GROUND — the
// field is confidently wrong there and nothing downstream can tell. These tests pin both halves: the
// edge arithmetic that decides closure, and the bake's promise to name an open body once per build
// while still publishing the field around it.

#include "CkGroundNav/Backend/CkGroundNav_GeometryBackend_Stub.h"
#include "CkGroundNav/Bake/CkGroundNav_MeshClosure.h"
#include "CkGroundNav/Field/CkGroundNav_FieldBuild.h"

#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_closure
{
    using ck::groundnav::DoBake_Field;
    using ck::groundnav::ECk_GroundNav_BodyKind;
    using ck::groundnav::FCk_GroundNav_Epoch;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldBuildState;
    using ck::groundnav::FCk_GroundNav_FieldParams;
    using ck::groundnav::FCk_GroundNav_GeometryBackend_Stub;
    using ck::groundnav::FCk_GroundNav_OpenBody;
    using ck::groundnav::Get_CompletedField;
    using ck::groundnav::Get_MeshClosure;
    using ck::groundnav::kMeshClosureWeldToleranceUu;
    using ck::groundnav::Request_AdvanceBuild;
    using ck::groundnav::Request_BeginBuild;

    // Enough to record every open edge any fixture here produces, so a cap never silently truncates a
    // count the test is reading.
    constexpr auto kRecordEverything = 64;

    struct FTriangle
    {
        FVector _A = FVector::ZeroVector;
        FVector _B = FVector::ZeroVector;
        FVector _C = FVector::ZeroVector;
    };

    /**
     * The same twelve triangles FCk_GroundNav_GeometryBatch::Add_Box emits, written out by hand so a
     * test can drop one of them or move a single corner OCCURRENCE without touching the other three
     * triangles that share it. That is the only way to author a mesh whose closure hangs on the weld.
     */
    auto Get_BoxTriangles() -> TArray<FTriangle>
    {
        constexpr auto Lo = 0.0;
        constexpr auto Hi = 100.0;

        const auto LLL = FVector{Lo, Lo, Lo};
        const auto HLL = FVector{Hi, Lo, Lo};
        const auto HHL = FVector{Hi, Hi, Lo};
        const auto LHL = FVector{Lo, Hi, Lo};
        const auto LLH = FVector{Lo, Lo, Hi};
        const auto HLH = FVector{Hi, Lo, Hi};
        const auto HHH = FVector{Hi, Hi, Hi};
        const auto LHH = FVector{Lo, Hi, Hi};

        return TArray<FTriangle>{
            FTriangle{LLH, HLH, HHH}, FTriangle{LLH, HHH, LHH},  // +Z
            FTriangle{LHL, HHL, HLL}, FTriangle{LHL, HLL, LLL},  // -Z
            FTriangle{LLL, HLL, HLH}, FTriangle{LLL, HLH, LLH},  // -Y
            FTriangle{HHL, LHL, LHH}, FTriangle{HHL, LHH, HHH},  // +Y
            FTriangle{HLL, HHL, HHH}, FTriangle{HLL, HHH, HLH},  // +X
            FTriangle{LHL, LLL, LLH}, FTriangle{LHL, LLH, LHH}}; // -X
    }

    // Index into Get_BoxTriangles(): the first -Y triangle, whose FIRST corner is the box's (0,0,0) —
    // a corner three other triangles also name, which is what makes moving this one occurrence a test
    // of the weld rather than of a differently-shaped box.
    constexpr auto kTriangleOwningTheSharedCorner = 4;

    // Index into Get_BoxTriangles(): the second +Z triangle. Dropping it leaves its three edges used
    // once each.
    constexpr auto kTriangleToDrop = 1;

    auto Add_BoxByHand(
        FCk_GroundNav_GeometryBatch& OutBatch,
        int32                        InSkipTriangle,
        int32                        InPerturbTriangle,
        const FVector&               InPerturbOffset) -> void
    {
        const auto Triangles = Get_BoxTriangles();

        for (auto Index = 0; Index < Triangles.Num(); ++Index)
        {
            if (Index == InSkipTriangle)
            { continue; }

            const auto& Triangle = Triangles[Index];
            const auto Offset = Index == InPerturbTriangle ? InPerturbOffset : FVector::ZeroVector;

            OutBatch.Add_Triangle(Triangle._A + Offset, Triangle._B, Triangle._C);
        }
    }

    /** Two triangles making one quad: an open fixture with no other faces, exactly what a fence is. */
    auto Make_OpenQuad() -> FCk_GroundNav_GeometryBatch
    {
        auto Batch = FCk_GroundNav_GeometryBatch{};

        const auto CornerA = FVector{0.0, 0.0, 0.0};
        const auto CornerB = FVector{100.0, 0.0, 0.0};
        const auto CornerC = FVector{100.0, 0.0, 100.0};
        const auto CornerD = FVector{0.0, 0.0, 100.0};

        Batch.Add_Triangle(CornerA, CornerB, CornerC);
        Batch.Add_Triangle(CornerA, CornerC, CornerD);

        return Batch;
    }

    // ----------------------------------------------------------------------------------------------------------------

    constexpr auto kCellSize = 25.0f;
    constexpr auto kCellHeight = 10.0f;
    constexpr auto kTileSize = 300.0f;
    constexpr auto kMaxClearance = 100.0f;
    constexpr auto kDivisions = 2;

    auto Make_Params() -> FCk_GroundNav_FieldParams
    {
        auto Config = FCk_GroundNav_BakeConfig{kCellSize, kCellHeight};
        Config.Set_TileSizeUu(kTileSize);

        auto Profile = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{70.0f, 20.0f}}};
        Profile.Set_LedgeSensitivity(0.0f);

        auto Params = FCk_GroundNav_FieldParams{};

        Params._OriginXY = FVector2D::ZeroVector;
        Params._Divisions = FIntPoint{kDivisions, kDivisions};
        Params._MinZUu = -50.0f;
        Params._MaxZUu = 300.0f;
        Params._Config = Config;
        Params._Profile = Profile;
        Params._MaxClearanceUu = kMaxClearance;

        return Params;
    }

    auto Make_Floor() -> FBox
    {
        return FBox{FVector{-200.0, -200.0, -10.0}, FVector{800.0, 800.0, 0.0}};
    }

    // A vertical quad standing on the floor and reaching into every tile's halo, so a build that
    // checked bodies per tile rather than per build would report it more than once.
    constexpr auto kPanelMinX = 100.0;
    constexpr auto kPanelMaxX = 500.0;
    constexpr auto kPanelY = 300.0;
    constexpr auto kPanelTopZ = 150.0;

    auto Do_AddPanel(
        FCk_GroundNav_GeometryBackend_Stub& OutBackend,
        ECk_GroundNav_BodyKind              InKind) -> void
    {
        OutBackend.Add_Panel(
            FVector{kPanelMinX, kPanelY, 0.0},
            FVector{kPanelMaxX, kPanelY, 0.0},
            FVector{kPanelMaxX, kPanelY, kPanelTopZ},
            FVector{kPanelMinX, kPanelY, kPanelTopZ},
            InKind);
    }

    auto Get_PanelBounds() -> FBox
    {
        return FBox{
            FVector{kPanelMinX, kPanelY, 0.0},
            FVector{kPanelMaxX, kPanelY, kPanelTopZ}};
    }

    auto Get_PanelMidpoint() -> FVector
    {
        return FVector{0.5 * (kPanelMinX + kPanelMaxX), kPanelY, 0.0};
    }

    // The plain-string form deliberately: the warning carries brackets and parentheses, and
    // AddExpectedError compiles its pattern as a REGEX.
    constexpr auto kOpenBodyWarningFragment = TEXT("with OPEN collision");
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Closure_AClosedBoxHasNoOpenEdges,
    "CkTests.UnitTests.CkGroundNav.Bake.Closure_AClosedBoxHasNoOpenEdges",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Closure_AClosedBoxHasNoOpenEdges::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_closure;

    auto Batch = FCk_GroundNav_GeometryBatch{};
    Batch.Add_Box(FBox{FVector{0.0, 0.0, 0.0}, FVector{100.0, 100.0, 100.0}});

    auto Probes = 0;
    const auto Closure = Get_MeshClosure(Batch, 0, Batch.Get_TriangleCount(), kRecordEverything, Probes);

    TestTrue(TEXT("a box authored by Add_Box is a closed mesh"), Closure.Get_IsClosed());

    TestEqual(TEXT("with no edge used by only one triangle"), Closure._OpenEdgeCount, 0);

    TestEqual(TEXT("and no open edge recorded to draw"), Closure._OpenEdgePoints.Num(), 0);

    TestEqual(TEXT("read as the twelve triangles a box has"), Closure._TriangleCount, 12);

    // One probe per triangle read, the same innermost-read unit every other bake stage bills.
    TestEqual(TEXT("costing one probe per triangle"), Probes, 12);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Closure_AnOpenQuadHasFourOpenEdges,
    "CkTests.UnitTests.CkGroundNav.Bake.Closure_AnOpenQuadHasFourOpenEdges",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Closure_AnOpenQuadHasFourOpenEdges::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_closure;

    const auto Batch = Make_OpenQuad();

    auto Probes = 0;
    const auto Closure = Get_MeshClosure(Batch, 0, Batch.Get_TriangleCount(), kRecordEverything, Probes);

    TestFalse(TEXT("a quad of two triangles is not a closed mesh"), Closure.Get_IsClosed());

    // Its four rim edges are each used once; the diagonal the two triangles share is used twice and is
    // therefore not one of them.
    TestEqual(TEXT("its four rim edges are open, and the shared diagonal is not"),
        Closure._OpenEdgeCount, 4);

    TestEqual(TEXT("with all four recorded as endpoint pairs"), Closure._OpenEdgePoints.Num(), 8);

    TestEqual(TEXT("over the two triangles it holds"), Closure._TriangleCount, 2);

    TestEqual(TEXT("costing one probe per triangle"), Probes, 2);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Closure_ABoxMissingOneTriangleHasThreeOpenEdges,
    "CkTests.UnitTests.CkGroundNav.Bake.Closure_ABoxMissingOneTriangleHasThreeOpenEdges",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Closure_ABoxMissingOneTriangleHasThreeOpenEdges::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_closure;

    auto Batch = FCk_GroundNav_GeometryBatch{};
    Add_BoxByHand(Batch, kTriangleToDrop, INDEX_NONE, FVector::ZeroVector);

    auto Probes = 0;
    const auto Closure = Get_MeshClosure(Batch, 0, Batch.Get_TriangleCount(), kRecordEverything, Probes);

    TestEqual(TEXT("eleven of a box's twelve triangles is eleven triangles"), Closure._TriangleCount, 11);

    TestFalse(TEXT("and no longer a closed mesh"), Closure.Get_IsClosed());

    // The dropped triangle's three edges each lose their second user: the top face's diagonal, and the
    // two rim edges it shared with the +Y and -X faces.
    TestEqual(TEXT("the three edges the missing triangle used are each left with one user"),
        Closure._OpenEdgeCount, 3);

    TestEqual(TEXT("all three recorded as endpoint pairs"), Closure._OpenEdgePoints.Num(), 6);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Closure_VerticesWithinToleranceWeld,
    "CkTests.UnitTests.CkGroundNav.Bake.Closure_VerticesWithinToleranceWeld",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Closure_VerticesWithinToleranceWeld::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_closure;

    // Well inside the tolerance. A backend may decode one shared vertex twice through different
    // compression blocks, so an exact comparison here would call every real mesh open.
    constexpr auto WithinTolerance = 0.04;

    // Well outside it. A gap this wide is a real hole and must read as one.
    constexpr auto BeyondTolerance = 0.5;

    TestTrue(TEXT("the fixture's small offset really is inside the weld tolerance"),
        WithinTolerance < kMeshClosureWeldToleranceUu);

    TestTrue(TEXT("and its large offset really is outside it"),
        BeyondTolerance > kMeshClosureWeldToleranceUu);

    {
        auto Batch = FCk_GroundNav_GeometryBatch{};
        Add_BoxByHand(Batch, INDEX_NONE, kTriangleOwningTheSharedCorner,
            FVector{WithinTolerance, 0.0, 0.0});

        auto Probes = 0;
        const auto Closure = Get_MeshClosure(
            Batch, 0, Batch.Get_TriangleCount(), kRecordEverything, Probes);

        TestTrue(TEXT("one corner moved less than the tolerance welds, leaving the box closed"),
            Closure.Get_IsClosed());

        TestEqual(TEXT("with all twelve triangles still read"), Closure._TriangleCount, 12);
    }

    {
        auto Batch = FCk_GroundNav_GeometryBatch{};
        Add_BoxByHand(Batch, INDEX_NONE, kTriangleOwningTheSharedCorner,
            FVector{BeyondTolerance, 0.0, 0.0});

        auto Probes = 0;
        const auto Closure = Get_MeshClosure(
            Batch, 0, Batch.Get_TriangleCount(), kRecordEverything, Probes);

        TestFalse(TEXT("the same corner moved further than the tolerance does not weld"),
            Closure.Get_IsClosed());

        // Four, derived by hand: the moved triangle's two edges into the displaced corner are new and
        // used once each, and the two edges the ORIGINAL corner still has (to the box's (100,0,0) and
        // (100,0,100)) are left with one user apiece. The third edge of the moved triangle runs between
        // two untouched corners and keeps its second user on the +X face.
        TestEqual(TEXT("leaving four open edges: two new ones at the displaced corner, and two the ")
                  TEXT("original corner lost their second user on"),
            Closure._OpenEdgeCount, 4);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Closure_RecordedEdgesAreCapped,
    "CkTests.UnitTests.CkGroundNav.Bake.Closure_RecordedEdgesAreCapped",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Closure_RecordedEdgesAreCapped::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_closure;

    const auto Batch = Make_OpenQuad();

    constexpr auto RecordOneEdge = 1;

    auto Probes = 0;
    const auto Closure = Get_MeshClosure(Batch, 0, Batch.Get_TriangleCount(), RecordOneEdge, Probes);

    // The cap bounds what is DRAWN, never what is counted: a mesh with ten thousand open edges must
    // still say so, or the number stops being a measure of how bad the asset is.
    TestEqual(TEXT("the open-edge count is the true total whatever the record cap is"),
        Closure._OpenEdgeCount, 4);

    TestEqual(TEXT("while only the capped number of edges is recorded as points"),
        Closure._OpenEdgePoints.Num(), 2);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Closure_AFieldBakeReportsAnOpenPanelOnce,
    "CkTests.UnitTests.CkGroundNav.Bake.Closure_AFieldBakeReportsAnOpenPanelOnce",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Closure_AFieldBakeReportsAnOpenPanelOnce::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_closure;

    // The warning is the point of the contract, and the harness escalates warnings to failures — so the
    // test declares the one it is deliberately provoking, exactly once for the one build it runs.
    AddExpectedErrorPlain(kOpenBodyWarningFragment, EAutomationExpectedErrorFlags::Contains, 1);

    auto Backend = FCk_GroundNav_GeometryBackend_Stub{TArray<FBox>{Make_Floor()}};
    Do_AddPanel(Backend, ECk_GroundNav_BodyKind::Solid);

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the bake completes and publishes despite the open body"),
        DoBake_Field(Backend, Make_Params(), FCk_GroundNav_Epoch{1}, Field).Get_IsCompleted()))
    { return false; }

    // Once, though the panel reaches into all four tiles' halos. A body is fetched and judged per
    // BUILD, not per tile.
    if (NOT TestEqual(TEXT("exactly one open body is recorded on the field"),
        Field.Get_OpenBodyCount(), 1))
    { return false; }

    const auto& OpenBody = Field._OpenBodies[0];

    TestEqual(TEXT("named as the panel the fixture authored"), OpenBody._Description,
        FString{TEXT("Stub panel 1")});

    TestEqual(TEXT("with the four open edges a quad has"), OpenBody._OpenEdgeCount, 4);

    TestEqual(TEXT("over the two triangles it is made of"), OpenBody._TriangleCount, 2);

    TestTrue(TEXT("and the panel's own bounds captured for the viewer"),
        OpenBody._Bounds == Get_PanelBounds());

    // The reason the contract exists, asserted rather than described: the panel presents no face in the
    // columns beneath it, so the field under it is walkable ground and an agent WILL path through it.
    const auto Midpoint = Get_PanelMidpoint();
    const auto* Tile = Field.Get_TileAt(Midpoint);

    if (NOT TestTrue(TEXT("the panel's midpoint falls in a tile of the field"), Tile != nullptr))
    { return false; }

    if (NOT TestTrue(TEXT("and that tile is built"), Tile->Get_IsBuilt()))
    { return false; }

    const auto CellX = FMath::FloorToInt32((Midpoint.X - Tile->_Origin.X) / Tile->_CellSizeUu);
    const auto CellY = FMath::FloorToInt32((Midpoint.Y - Tile->_Origin.Y) / Tile->_CellSizeUu);

    TestTrue(TEXT("the floor under the open panel is walkable, which is exactly the failure the ")
             TEXT("contract exists to catch"),
        Tile->Get_HasSurfaceAt(CellX, CellY, 0));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Closure_ASurfacePanelIsExempt,
    "CkTests.UnitTests.CkGroundNav.Bake.Closure_ASurfacePanelIsExempt",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Closure_ASurfacePanelIsExempt::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_closure;

    // No expected warning is declared: a Surface body must produce none, and the harness escalating
    // warnings to failures is what makes that assertion real rather than decorative.
    auto Backend = FCk_GroundNav_GeometryBackend_Stub{TArray<FBox>{Make_Floor()}};
    Do_AddPanel(Backend, ECk_GroundNav_BodyKind::Surface);

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the bake completes"),
        DoBake_Field(Backend, Make_Params(), FCk_GroundNav_Epoch{1}, Field).Get_IsCompleted()))
    { return false; }

    // A heightfield is open by construction, has no interior to describe, and a hole in it is a hole in
    // the world. Judging it against the closure contract would name every terrain in the level.
    TestEqual(TEXT("a Surface body is exempt from the closure contract and is not reported"),
        Field.Get_OpenBodyCount(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Closure_ASlicedBuildChecksEachBodyOnce,
    "CkTests.UnitTests.CkGroundNav.Bake.Closure_ASlicedBuildChecksEachBodyOnce",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Closure_ASlicedBuildChecksEachBodyOnce::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_closure;

    // Two builds over the same open fixture, so two warnings: one per build is the contract.
    AddExpectedErrorPlain(kOpenBodyWarningFragment, EAutomationExpectedErrorFlags::Contains, 2);

    auto Backend = FCk_GroundNav_GeometryBackend_Stub{TArray<FBox>{Make_Floor()}};
    Do_AddPanel(Backend, ECk_GroundNav_BodyKind::Solid);

    auto OneShotProbes = 0;

    {
        auto Field = FCk_GroundNav_Field{};
        const auto Result = DoBake_Field(Backend, Make_Params(), FCk_GroundNav_Epoch{1}, Field);

        if (NOT TestTrue(TEXT("the one-shot bake completes"), Result.Get_IsCompleted()))
        { return false; }

        OneShotProbes = Result.Get_ProbesSpent();
    }

    auto State = FCk_GroundNav_FieldBuildState{};

    if (NOT TestTrue(TEXT("the sliced build begins"),
        Request_BeginBuild(Make_Params(), FCk_GroundNav_Epoch{1}, State).Get_IsCompleted()))
    { return false; }

    // A budget of one probe forces the smallest slice the builder allows, which is one tile.
    constexpr auto SmallestBudget = 1;
    constexpr auto MaxSlices = 64;

    auto SliceCount = 0;
    auto Completed = false;

    while (SliceCount < MaxSlices)
    {
        const auto Result = Request_AdvanceBuild(Backend, SmallestBudget, State);
        ++SliceCount;

        if (Result.Get_Status() == ECk_GroundNav_BakeStatus::BudgetExhausted)
        { continue; }

        Completed = Result.Get_IsCompleted();
        break;
    }

    if (NOT TestTrue(TEXT("and runs to completion one tile at a time"), Completed))
    { return false; }

    if (NOT TestTrue(TEXT("over more than one slice"), SliceCount > 1))
    { return false; }

    const auto* Sliced = Get_CompletedField(State);

    if (NOT TestTrue(TEXT("yielding a field"), Sliced != nullptr))
    { return false; }

    // The panel straddles every tile of the field, so a check that ran per tile rather than per build
    // would bill its probes four times and report it four times. Both numbers say it ran once.
    TestEqual(TEXT("the sliced build spends exactly the probes the one-shot bake does, closure ")
              TEXT("included"),
        State._ProbesSpent, OneShotProbes);

    TestEqual(TEXT("and records the open panel exactly once"), Sliced->Get_OpenBodyCount(), 1);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
