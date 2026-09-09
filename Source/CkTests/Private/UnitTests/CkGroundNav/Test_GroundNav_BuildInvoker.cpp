// Pure build-invoker scope selection. These rows deliberately exercise the field lattice without
// constructing ECS entities: aggregation, publication, and target build scheduling consume this
// deterministic result later, while this layer owns the geometric and hysteresis contract itself.

#include "CkGroundNav/Field/CkGroundNav_BuildInvoker.h"

#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

#include <Algo/Reverse.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_buildinvoker
{
    using ck::groundnav::FCk_GroundNav_BuildInvokerBox;
    using ck::groundnav::FCk_GroundNav_BuildInvokerPoint;
    using ck::groundnav::FCk_GroundNav_BuildInvokerSelection;
    using ck::groundnav::FCk_GroundNav_FieldParams;
    using ck::groundnav::Request_ComputeBuildInvokerSelection;

    auto Make_Params(int32 InWidth = 4) -> FCk_GroundNav_FieldParams
    {
        auto Config = FCk_GroundNav_BakeConfig{10.0f, 10.0f};
        Config.Set_TileSizeUu(100.0f);

        auto Params = FCk_GroundNav_FieldParams{};
        Params._OriginXY = FVector2D{0.0, 0.0};
        Params._Divisions = FIntPoint{InWidth, 1};
        Params._MinZUu = 0.0f;
        Params._MaxZUu = 100.0f;
        Params._Config = Config;
        Params._Profile = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{25.0f, 10.0f}}};
        return Params;
    }

    auto Get_ArraysMatch(const TArray<int32>& InActual, std::initializer_list<int32> InExpected) -> bool
    {
        return InActual == TArray<int32>{InExpected};
    }

    auto Get_SelectionsMatch(
        const FCk_GroundNav_BuildInvokerSelection& InLeft,
        const FCk_GroundNav_BuildInvokerSelection& InRight) -> bool
    {
        return InLeft._GenerateTileIndices == InRight._GenerateTileIndices &&
               InLeft._RetainTileIndices == InRight._RetainTileIndices &&
               InLeft._BuildTileIndices == InRight._BuildTileIndices &&
               InLeft._PurgeTileIndices == InRight._PurgeTileIndices;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_BuildInvoker_OrderOverlapAndClosedBoundary,
    "CkTests.UnitTests.CkGroundNav.StreamingAcceptance.BuildInvoker.OrderOverlapAndClosedBoundary",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_BuildInvoker_OrderOverlapAndClosedBoundary::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_buildinvoker;

    const auto Params = Make_Params();
    const auto Points = TArray<FCk_GroundNav_BuildInvokerPoint>{
        FCk_GroundNav_BuildInvokerPoint{FVector{200.0, 50.0, 0.0}, 100.0f, 125.0f},
        FCk_GroundNav_BuildInvokerPoint{FVector{50.0, 50.0, 0.0}, 60.0f, 160.0f}};
    const auto Boxes = TArray<FCk_GroundNav_BuildInvokerBox>{
        FCk_GroundNav_BuildInvokerBox{FBox{FVector{100.0, 0.0, 0.0}, FVector{250.0, 100.0, 50.0}}, 50.0f}};

    auto First = FCk_GroundNav_BuildInvokerSelection{};
    if (NOT TestTrue(TEXT("the first ordering selects"), Request_ComputeBuildInvokerSelection(
        Params, Points, Boxes, TArray<int32>{0, 0, 3}, First)))
    { return false; }

    auto ReversePoints = Points;
    auto ReverseBoxes = Boxes;
    Algo::Reverse(ReversePoints);
    Algo::Reverse(ReverseBoxes);

    auto Second = FCk_GroundNav_BuildInvokerSelection{};
    if (NOT TestTrue(TEXT("the permuted ordering selects"), Request_ComputeBuildInvokerSelection(
        Params, ReversePoints, ReverseBoxes, TArray<int32>{3, 0}, Second)))
    { return false; }

    TestTrue(TEXT("permuting descriptors and built-set order cannot change the result"),
        Get_SelectionsMatch(First, Second));
    TestTrue(TEXT("overlapping sources deduplicate into row-major generation"),
        Get_ArraysMatch(First._GenerateTileIndices, {0, 1, 2, 3}));
    TestTrue(TEXT("the outer unions are also sorted and unique"),
        Get_ArraysMatch(First._RetainTileIndices, {0, 1, 2, 3}));
    TestTrue(TEXT("a point exactly one radius from both outer tiles includes those closed boundaries"),
        Get_ArraysMatch(First._BuildTileIndices, {1, 2}));
    TestTrue(TEXT("retained built tiles do not purge"), First._PurgeTileIndices.IsEmpty());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_BuildInvoker_HysteresisHasExactTransitions,
    "CkTests.UnitTests.CkGroundNav.StreamingAcceptance.BuildInvoker.HysteresisHasExactTransitions",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_BuildInvoker_HysteresisHasExactTransitions::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_buildinvoker;

    const auto Params = Make_Params(3);
    auto Built = TArray<int32>{};
    auto TotalBuilds = 0;
    auto TotalPurges = 0;

    for (const auto LocationX : {50.0, 150.0, 170.0, 150.0, 170.0, 150.0})
    {
        const auto Point = FCk_GroundNav_BuildInvokerPoint{FVector{LocationX, 50.0, 0.0}, 20.0f, 100.0f};
        auto Selection = FCk_GroundNav_BuildInvokerSelection{};

        if (NOT TestTrue(TEXT("each repeated hysteresis input selects"), Request_ComputeBuildInvokerSelection(
            Params, TArray<FCk_GroundNav_BuildInvokerPoint>{Point}, {}, Built, Selection)))
        { return false; }

        TotalBuilds += Selection._BuildTileIndices.Num();
        TotalPurges += Selection._PurgeTileIndices.Num();
        Built.Append(Selection._BuildTileIndices);

        for (const auto TileIndex : Selection._PurgeTileIndices)
        { Built.Remove(TileIndex); }
    }

    TestEqual(TEXT("the oscillation builds exactly the two entered tiles"), TotalBuilds, 2);
    TestEqual(TEXT("the outer band prevents every repeated purge"), TotalPurges, 0);
    TestTrue(TEXT("the final built set remains the two hysteresis-retained tiles"),
        Get_ArraysMatch(Built, {0, 1}));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_BuildInvoker_PurgesOnlyOutsideRetention,
    "CkTests.UnitTests.CkGroundNav.StreamingAcceptance.BuildInvoker.PurgesOnlyOutsideRetention",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_BuildInvoker_PurgesOnlyOutsideRetention::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_buildinvoker;

    auto Selection = FCk_GroundNav_BuildInvokerSelection{};
    const auto Point = FCk_GroundNav_BuildInvokerPoint{FVector{50.0, 50.0, 0.0}, 0.0f, 60.0f};

    if (NOT TestTrue(TEXT("the purge selection succeeds"), Request_ComputeBuildInvokerSelection(
        Make_Params(), TArray<FCk_GroundNav_BuildInvokerPoint>{Point}, {}, TArray<int32>{0, 1, 2, 3}, Selection)))
    { return false; }

    TestTrue(TEXT("generation retains the point's containing tile"),
        Get_ArraysMatch(Selection._GenerateTileIndices, {0}));
    TestTrue(TEXT("retention keeps exactly the adjacent tile within the outer radius"),
        Get_ArraysMatch(Selection._RetainTileIndices, {0, 1}));
    TestTrue(TEXT("no already-built retained tile rebuilds"), Selection._BuildTileIndices.IsEmpty());
    TestTrue(TEXT("purge removes exactly tiles outside every retention source"),
        Get_ArraysMatch(Selection._PurgeTileIndices, {2, 3}));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_BuildInvoker_InvalidDescriptorsAreIgnored,
    "CkTests.UnitTests.CkGroundNav.StreamingAcceptance.BuildInvoker.InvalidDescriptorsAreIgnored",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_BuildInvoker_InvalidDescriptorsAreIgnored::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_buildinvoker;

    auto InvalidPoint = FCk_GroundNav_BuildInvokerPoint{FVector{50.0, 50.0, 0.0}, 100.0f, 50.0f};
    const auto ValidPoint = FCk_GroundNav_BuildInvokerPoint{FVector{50.0, 50.0, 0.0}, 0.0f, 0.0f};
    auto Output = FCk_GroundNav_BuildInvokerSelection{};

    AddExpectedError(TEXT("GroundNav build invoker ignores an invalid point descriptor"),
        EAutomationExpectedErrorFlags::Contains, 2);
    if (NOT TestTrue(TEXT("an invalid point does not block a valid peer"), Request_ComputeBuildInvokerSelection(
        Make_Params(), TArray<FCk_GroundNav_BuildInvokerPoint>{InvalidPoint, ValidPoint}, {}, {}, Output)))
    { return false; }
    TestTrue(TEXT("the valid peer is the only generation contributor"),
        Get_ArraysMatch(Output._GenerateTileIndices, {0}) && Get_ArraysMatch(Output._BuildTileIndices, {0}));

    auto InvalidBox = FCk_GroundNav_BuildInvokerBox{FBox{ForceInit}, 0.0f};
    AddExpectedError(TEXT("GroundNav build invoker ignores an invalid box descriptor"),
        EAutomationExpectedErrorFlags::Contains, 2);
    if (NOT TestTrue(TEXT("an invalid box contributes no tiles"), Request_ComputeBuildInvokerSelection(
        Make_Params(), {}, TArray<FCk_GroundNav_BuildInvokerBox>{InvalidBox}, TArray<int32>{0}, Output)))
    { return false; }
    TestTrue(TEXT("a lone invalid box leaves no retain set and purges existing work"),
        Output._GenerateTileIndices.IsEmpty() && Output._RetainTileIndices.IsEmpty() &&
        Output._BuildTileIndices.IsEmpty() && Get_ArraysMatch(Output._PurgeTileIndices, {0}));

    const auto Sentinel = FCk_GroundNav_BuildInvokerSelection{
        TArray<int32>{7}, TArray<int32>{8}, TArray<int32>{9}, TArray<int32>{10}};
    Output = Sentinel;
    auto InvalidParams = Make_Params();
    InvalidParams._Divisions.X = 0;
    AddExpectedError(TEXT("GroundNav build invoker selection requires a valid lattice and built tile indices"),
        EAutomationExpectedErrorFlags::Contains, 2);
    TestFalse(TEXT("an invalid lattice is refused"), Request_ComputeBuildInvokerSelection(
        InvalidParams, TArray<FCk_GroundNav_BuildInvokerPoint>{ValidPoint}, {}, {}, Output));
    TestTrue(TEXT("a refused lattice leaves caller output untouched"), Get_SelectionsMatch(Output, Sentinel));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
