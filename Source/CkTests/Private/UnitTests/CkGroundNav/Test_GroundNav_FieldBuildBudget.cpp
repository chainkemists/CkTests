// Building a field in slices, and the one property that makes a budget assertable at all.
//
// Probe count is the budget, not wall time, because it is deterministic for a given fixture and
// config where time is not. That only holds if the resume point cannot re-probe — so the tests here
// pin the probe total against the slice size, and the sliced result against the one-shot result, byte
// for byte. A sliced bake that merely resembled the whole one would hide exactly the defect the
// budgeting mechanism can introduce.

#include "CkGroundNav/Backend/CkGroundNav_GeometryBackend_Stub.h"
#include "CkGroundNav/Field/CkGroundNav_FieldBuild.h"

#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_budget
{
    using ck::groundnav::DoBake_Field;
    using ck::groundnav::FCk_GroundNav_Epoch;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldBuildState;
    using ck::groundnav::FCk_GroundNav_FieldParams;
    using ck::groundnav::FCk_GroundNav_GeometryBackend_Stub;
    using ck::groundnav::FCk_GroundNav_Tile;
    using ck::groundnav::Get_CompletedField;
    using ck::groundnav::Request_AdvanceBuild;
    using ck::groundnav::Request_BeginBuild;
    using ck::groundnav::Request_ReleaseCompletedField;

    constexpr auto kCellSize = 25.0f;
    constexpr auto kCellHeight = 10.0f;
    constexpr auto kTileSize = 200.0f;
    constexpr auto kMaxClearance = 100.0f;
    constexpr auto kDivisions = 3;

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

    // Ground under the whole field with obstacles in it, so the tiles differ from one another and a
    // slice boundary has something to get wrong.
    auto Make_Ground() -> TArray<FBox>
    {
        auto Boxes = TArray<FBox>{
            FBox{FVector{-200.0, -200.0, -10.0}, FVector{800.0, 800.0, 0.0}}};

        // Blocks standing on the floor: the cells beneath them lose their headroom and drop out.
        Boxes.Emplace(FBox{FVector{150.0, 150.0, 0.0}, FVector{250.0, 250.0, 200.0}});
        Boxes.Emplace(FBox{FVector{400.0, 100.0, 0.0}, FVector{450.0, 500.0, 200.0}});

        return Boxes;
    }

    auto Get_TilesMatch(const FCk_GroundNav_Tile& InLeft, const FCk_GroundNav_Tile& InRight) -> bool
    {
        if (InLeft._Status != InRight._Status ||
            InLeft._SizeX != InRight._SizeX || InLeft._SizeY != InRight._SizeY ||
            InLeft._LayerCount != InRight._LayerCount ||
            InLeft._Origin != InRight._Origin ||
            InLeft._SurfaceZ != InRight._SurfaceZ ||
            InLeft._Clearance._Cells != InRight._Clearance._Cells ||
            InLeft._Plates._CellToPlate != InRight._Plates._CellToPlate ||
            InLeft._Plates._Plates.Num() != InRight._Plates._Plates.Num() ||
            InLeft._Portals._Portals.Num() != InRight._Portals._Portals.Num() ||
            InLeft._SeamStubs.Num() != InRight._SeamStubs.Num())
        { return false; }

        for (auto Index = 0; Index < InLeft._Plates._Plates.Num(); ++Index)
        {
            const auto& A = InLeft._Plates._Plates[Index];
            const auto& B = InRight._Plates._Plates[Index];

            if (A._MinX != B._MinX || A._MinY != B._MinY || A._MaxX != B._MaxX || A._MaxY != B._MaxY ||
                A._LayerIndex != B._LayerIndex ||
                A._MaxPlaneResidualUu != B._MaxPlaneResidualUu ||
                A._HeightRangeUu != B._HeightRangeUu)
            { return false; }
        }

        for (auto Index = 0; Index < InLeft._Portals._Portals.Num(); ++Index)
        {
            const auto& A = InLeft._Portals._Portals[Index];
            const auto& B = InRight._Portals._Portals[Index];

            if (A._PlateA != B._PlateA || A._PlateB != B._PlateB || A._Direction != B._Direction ||
                A._FromMin != B._FromMin || A._FromMax != B._FromMax ||
                A._TraversalClearanceUu != B._TraversalClearanceUu)
            { return false; }
        }

        for (auto Index = 0; Index < InLeft._SeamStubs.Num(); ++Index)
        {
            const auto& A = InLeft._SeamStubs[Index];
            const auto& B = InRight._SeamStubs[Index];

            if (A._Direction != B._Direction || A._AlongIndex != B._AlongIndex ||
                A._PlateIndex != B._PlateIndex ||
                A._NearSurfaceZUu != B._NearSurfaceZUu || A._FarSurfaceZUu != B._FarSurfaceZUu ||
                A._ClearanceUu != B._ClearanceUu)
            { return false; }
        }

        return true;
    }

    auto Get_FieldsMatch(const FCk_GroundNav_Field& InLeft, const FCk_GroundNav_Field& InRight) -> bool
    {
        if (InLeft.Get_TileCount() != InRight.Get_TileCount() ||
            InLeft._SeamPortals.Num() != InRight._SeamPortals.Num() ||
            InLeft._ReachabilityLabels != InRight._ReachabilityLabels ||
            InLeft._TilePlateOffsets != InRight._TilePlateOffsets)
        { return false; }

        for (auto Index = 0; Index < InLeft.Get_TileCount(); ++Index)
        {
            if (NOT Get_TilesMatch(InLeft._Tiles[Index], InRight._Tiles[Index]))
            { return false; }
        }

        for (auto Index = 0; Index < InLeft._SeamPortals.Num(); ++Index)
        {
            const auto& A = InLeft._SeamPortals[Index];
            const auto& B = InRight._SeamPortals[Index];

            if (A._TileIndexA != B._TileIndexA || A._TileIndexB != B._TileIndexB ||
                A._PlateA != B._PlateA || A._PlateB != B._PlateB ||
                A._AlongMin != B._AlongMin || A._AlongMax != B._AlongMax ||
                A._TraversalClearanceUu != B._TraversalClearanceUu)
            { return false; }
        }

        return true;
    }

    /** Run a whole build at the given budget, reporting how many slices it took. */
    auto Build_Sliced(int32 InProbeBudget, FCk_GroundNav_FieldBuildState& OutState, int32& OutSliceCount) -> bool
    {
        const auto Backend = FCk_GroundNav_GeometryBackend_Stub{Make_Ground()};

        if (NOT Request_BeginBuild(Make_Params(), FCk_GroundNav_Epoch{1}, OutState).Get_IsCompleted())
        { return false; }

        OutSliceCount = 0;

        // Bounded so a build that failed to advance ends the test rather than the process.
        constexpr auto MaxSlices = 256;

        while (OutSliceCount < MaxSlices)
        {
            const auto Result = Request_AdvanceBuild(Backend, InProbeBudget, OutState);
            ++OutSliceCount;

            if (Result.Get_Status() == ECk_GroundNav_BakeStatus::BudgetExhausted)
            { continue; }

            return Result.Get_IsCompleted();
        }

        return false;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Budget_SlicedBakeMatchesOneShotBake,
    "CkTests.UnitTests.CkGroundNav.Bake.Budget_SlicedBakeMatchesOneShotBake",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Budget_SlicedBakeMatchesOneShotBake::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_budget;

    auto OneShot = FCk_GroundNav_Field{};

    {
        const auto Backend = FCk_GroundNav_GeometryBackend_Stub{Make_Ground()};

        if (NOT TestTrue(TEXT("the one-shot bake completes"),
            DoBake_Field(Backend, Make_Params(), FCk_GroundNav_Epoch{1}, OneShot).Get_IsCompleted()))
        { return false; }
    }

    auto State = FCk_GroundNav_FieldBuildState{};
    auto SliceCount = 0;

    // A budget of one probe forces the smallest slice the builder allows, which is one tile.
    if (NOT TestTrue(TEXT("the sliced build completes"), Build_Sliced(1, State, SliceCount)))
    { return false; }

    if (NOT TestTrue(FString::Printf(TEXT("in more than five slices (took %d)"), SliceCount),
        SliceCount >= 5))
    { return false; }

    const auto* Sliced = Get_CompletedField(State);

    if (NOT TestTrue(TEXT("and yields a field"), Sliced != nullptr))
    { return false; }

    // Byte for byte, not approximately. Every number the sliced build produced has to be the number
    // the whole one did, or the resume point changed an answer somewhere.
    TestTrue(TEXT("identical to the one-shot bake"), Get_FieldsMatch(OneShot, *Sliced));

    TestEqual(TEXT("with the same tiles built"), Sliced->Get_BuiltTileCount(),
        OneShot.Get_BuiltTileCount());

    TestEqual(TEXT("and the same components found"), Sliced->Get_ReachabilityComponentCount(),
        OneShot.Get_ReachabilityComponentCount());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Budget_ProbeCountIsIndependentOfSliceSize,
    "CkTests.UnitTests.CkGroundNav.Bake.Budget_ProbeCountIsIndependentOfSliceSize",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Budget_ProbeCountIsIndependentOfSliceSize::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_budget;

    auto OneShotProbes = 0;

    {
        const auto Backend = FCk_GroundNav_GeometryBackend_Stub{Make_Ground()};

        auto Field = FCk_GroundNav_Field{};
        const auto Result = DoBake_Field(Backend, Make_Params(), FCk_GroundNav_Epoch{1}, Field);

        if (NOT TestTrue(TEXT("the one-shot bake completes"), Result.Get_IsCompleted()))
        { return false; }

        OneShotProbes = Result.Get_ProbesSpent();
    }

    if (NOT TestTrue(TEXT("and spends probes worth counting"), OneShotProbes > 0))
    { return false; }

    // The property the whole budgeting contract rests on: a probe count that moved with the slice size
    // would mean the resume point was re-probing, and no budget expressed in probes could be asserted
    // against it afterwards.
    for (const auto Budget : {1, OneShotProbes / 4, OneShotProbes, OneShotProbes * 10})
    {
        auto State = FCk_GroundNav_FieldBuildState{};
        auto SliceCount = 0;

        if (NOT TestTrue(FString::Printf(TEXT("the build at budget %d completes"), Budget),
            Build_Sliced(Budget, State, SliceCount)))
        { return false; }

        if (State._ProbesSpent != OneShotProbes)
        {
            AddError(FString::Printf(
                TEXT("budget %d spent %d probes over %d slices against %d in one shot"),
                Budget, State._ProbesSpent, SliceCount, OneShotProbes));
            return false;
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Budget_NothingIsReachableUntilTheBuildIsWhole,
    "CkTests.UnitTests.CkGroundNav.Bake.Budget_NothingIsReachableUntilTheBuildIsWhole",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Budget_NothingIsReachableUntilTheBuildIsWhole::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_budget;

    const auto Backend = FCk_GroundNav_GeometryBackend_Stub{Make_Ground()};

    auto State = FCk_GroundNav_FieldBuildState{};

    if (NOT TestTrue(TEXT("the build begins"),
        Request_BeginBuild(Make_Params(), FCk_GroundNav_Epoch{1}, State).Get_IsCompleted()))
    { return false; }

    TestEqual(TEXT("with every tile still to bake"), State._NextTileIndex, 0);
    TestTrue(TEXT("and nothing reachable yet"), Get_CompletedField(State) == nullptr);

    const auto FirstSlice = Request_AdvanceBuild(Backend, 1, State);

    if (NOT TestEqual(TEXT("one slice at the smallest budget pauses rather than finishing"),
        FirstSlice.Get_Status(), ECk_GroundNav_BakeStatus::BudgetExhausted))
    { return false; }

    TestTrue(TEXT("having baked at least one tile"), State._NextTileIndex > 0);
    TestTrue(TEXT("but not all of them"), State._NextTileIndex < State.Get_TileCount());

    // A half-baked field reads exactly like a world whose missing tiles have no floor, so it is not
    // reachable at all rather than reachable-and-incomplete.
    TestTrue(TEXT("and still nothing reachable mid-build"), Get_CompletedField(State) == nullptr);
    TestFalse(TEXT("with the build not claiming to be complete"), State.Get_IsComplete());

    auto SliceCount = 1;

    while (Request_AdvanceBuild(Backend, 1, State).Get_Status() == ECk_GroundNav_BakeStatus::BudgetExhausted)
    {
        ++SliceCount;

        if (SliceCount > 256)
        { break; }

        TestTrue(TEXT("nothing is reachable at any point mid-build"), Get_CompletedField(State) == nullptr);
    }

    TestTrue(TEXT("the finished build is reachable"), Get_CompletedField(State) != nullptr);
    TestTrue(TEXT("and says it is complete"), State.Get_IsComplete());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Budget_AWorldChangeBetweenSlicesFailsClosed,
    "CkTests.UnitTests.CkGroundNav.Bake.Budget_AWorldChangeBetweenSlicesFailsClosed",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Budget_AWorldChangeBetweenSlicesFailsClosed::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_budget;

    // Non-const, unlike every other backend here: this is the one test that moves the world.
    auto Backend = FCk_GroundNav_GeometryBackend_Stub{Make_Ground()};

    auto State = FCk_GroundNav_FieldBuildState{};

    if (NOT TestTrue(TEXT("the build begins"),
        Request_BeginBuild(Make_Params(), FCk_GroundNav_Epoch{1}, State).Get_IsCompleted()))
    { return false; }

    // A budget of one probe forces the smallest slice the builder allows, which is one tile.
    const auto FirstSlice = Request_AdvanceBuild(Backend, 1, State);

    if (NOT TestEqual(TEXT("the first slice pauses with tiles left to bake"),
        FirstSlice.Get_Status(), ECk_GroundNav_BakeStatus::BudgetExhausted))
    { return false; }

    const auto TilesBakedBeforeTheChange = State._NextTileIndex;

    // The world moves under the half-finished build. The BOXES are untouched, so the only thing the
    // builder can be reacting to is the revision — and the tiles it would go on to bake would still be
    // byte-identical. Fail-closed means it refuses anyway: the token is all the evidence there is.
    Backend.Request_BumpWorldRevision();

    const auto NextSlice = Request_AdvanceBuild(Backend, 1, State);

    TestEqual(TEXT("the next slice refuses rather than baking against a world it cannot vouch for"),
        NextSlice.Get_Status(), ECk_GroundNav_BakeStatus::StaleGeometry);

    TestEqual(TEXT("without baking another tile"), State._NextTileIndex, TilesBakedBeforeTheChange);

    TestEqual(TEXT("and the build records the failure"), State._Status,
        ECk_GroundNav_BuildStatus::Failed);

    TestFalse(TEXT("so it does not claim to be complete"), State.Get_IsComplete());
    TestTrue(TEXT("and publishes nothing"), Get_CompletedField(State) == nullptr);

    // A build that failed closed STAYS failed. Re-driving it must not launder a field out of tiles
    // baked either side of the change, whatever the world settles at afterwards.
    const auto AfterFailure = Request_AdvanceBuild(Backend, 1, State);

    TestEqual(TEXT("and re-driving it refuses on the same grounds"),
        AfterFailure.Get_Status(), ECk_GroundNav_BakeStatus::StaleGeometry);

    TestTrue(TEXT("still publishing nothing"), Get_CompletedField(State) == nullptr);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Budget_AReleasedBuildIsSpent,
    "CkTests.UnitTests.CkGroundNav.Bake.Budget_AReleasedBuildIsSpent",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Budget_AReleasedBuildIsSpent::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_budget;

    auto State = FCk_GroundNav_FieldBuildState{};
    auto SliceCount = 0;

    if (NOT TestTrue(TEXT("the sliced build completes"), Build_Sliced(1, State, SliceCount)))
    { return false; }

    const auto ExpectedTileCount = kDivisions * kDivisions;

    const auto Released = Request_ReleaseCompletedField(State);

    if (NOT TestTrue(TEXT("releasing a finished build hands over a field"), Released.IsValid()))
    { return false; }

    TestEqual(TEXT("with every tile in it"), Released->Get_TileCount(), ExpectedTileCount);

    // The build is SPENT. Without this the moved-from partial would still report complete, and a second
    // release would hand back a non-null EMPTY field — which reads exactly like a world whose tiles have
    // no floor, and would be answered confidently by every query.
    const auto SecondRelease = Request_ReleaseCompletedField(State);

    TestFalse(TEXT("a second release hands over nothing"), SecondRelease.IsValid());

    TestTrue(TEXT("and the spent build is no longer reachable"), Get_CompletedField(State) == nullptr);
    TestFalse(TEXT("nor does it claim to be complete"), State.Get_IsComplete());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
