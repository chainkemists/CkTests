// Vertical layer extraction — one column, one span, per layer.
//
// This is the property multi-storey navigation rests on: once a layer holds at most one span per
// column, a query against it is a 2D grid lookup instead of a search. The fixtures below check the
// property directly rather than trusting the layer count, because the right count with the wrong
// occupancy is the failure that would survive to runtime.

#include "CkGroundNav/Bake/CkGroundNav_Layers.h"
#include "CkGroundNav/Bake/CkGroundNav_Rasterize.h"

#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_layers
{
    using ck::groundnav::DoExtract_Layers;
    using ck::groundnav::DoFilter_Walkability;
    using ck::groundnav::DoFind_ConnectedComponents;
    using ck::groundnav::DoRasterizeSpans;
    using ck::groundnav::FCk_GroundNav_Component;
    using ck::groundnav::FCk_GroundNav_ConnectionField;
    using ck::groundnav::FCk_GroundNav_LayerField;
    using ck::groundnav::FCk_GroundNav_SpanField;

    constexpr auto kCellSize = 25.0f;

    auto Make_Profile(float InStandingHeightUu = 180.0f) -> FCk_GroundNav_AgentProfile
    {
        constexpr auto Radius = 20.0f;
        const auto HalfHeight = (InStandingHeightUu * 0.5f) - Radius;

        return FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{HalfHeight, Radius}}};
    }

    struct FBakeResult
    {
        FCk_GroundNav_SpanField _Spans;
        FCk_GroundNav_ConnectionField _Connections;
        FCk_GroundNav_LayerField _Layers;
        TArray<FCk_GroundNav_Component> _Components;
        bool _Completed = false;
    };

    auto Bake(
        const FCk_GroundNav_GeometryBatch& InGeometry,
        const FBox&                        InRegion,
        const FCk_GroundNav_AgentProfile&  InProfile) -> FBakeResult
    {
        auto Result = FBakeResult{};

        const auto Config = FCk_GroundNav_BakeConfig{kCellSize, 10.0f};

        if (NOT DoRasterizeSpans(InGeometry, InRegion, Config, InProfile, Result._Spans).Get_IsCompleted())
        { return Result; }

        if (NOT DoFilter_Walkability(InProfile, Result._Spans, Result._Connections).Get_IsCompleted())
        { return Result; }

        DoFind_ConnectedComponents(Result._Spans, Result._Connections, Result._Components);

        Result._Completed = DoExtract_Layers(
            Result._Spans, Result._Connections, Result._Layers).Get_IsCompleted();

        return Result;
    }

    auto Get_WalkableSpanCount(const FCk_GroundNav_SpanField& InField) -> int32
    {
        auto Count = 0;

        for (const auto& Column : InField._Columns)
        {
            for (const auto& Span : Column)
            {
                if (Span._IsWalkable)
                { ++Count; }
            }
        }

        return Count;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Layers_FlatPlaneIsOneLayer,
    "CkTests.UnitTests.CkGroundNav.Bake.Layers_FlatPlaneIsOneLayer",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Layers_FlatPlaneIsOneLayer::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_layers;

    auto Geometry = FCk_GroundNav_GeometryBatch{};
    Geometry.Add_Box(FBox{FVector{0.0, 0.0, 0.0}, FVector{500.0, 500.0, 10.0}});

    const auto Baked = Bake(Geometry,
        FBox{FVector{0.0, 0.0, -50.0}, FVector{500.0, 500.0, 400.0}}, Make_Profile());

    if (NOT TestTrue(TEXT("the flat fixture bakes"), Baked._Completed))
    { return false; }

    TestEqual(TEXT("one continuous floor is one component"), Baked._Components.Num(), 1);
    TestEqual(TEXT("and one layer"), Baked._Layers._LayerCount, 1);

    TestEqual(TEXT("with every walkable span assigned to it"),
        Baked._Layers.Get_AssignedSpanCount(), Get_WalkableSpanCount(Baked._Spans));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Layers_TwoStoreysAreTwoDisjointLayers,
    "CkTests.UnitTests.CkGroundNav.Bake.Layers_TwoStoreysAreTwoDisjointLayers",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Layers_TwoStoreysAreTwoDisjointLayers::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_layers;

    // Two floors of the same building, 290 uu of headroom apart.
    auto Geometry = FCk_GroundNav_GeometryBatch{};
    Geometry.Add_Box(FBox{FVector{0.0, 0.0, 0.0}, FVector{500.0, 500.0, 10.0}});
    Geometry.Add_Box(FBox{FVector{0.0, 0.0, 300.0}, FVector{500.0, 500.0, 310.0}});

    const auto Baked = Bake(Geometry,
        FBox{FVector{0.0, 0.0, -50.0}, FVector{500.0, 500.0, 600.0}}, Make_Profile());

    if (NOT TestTrue(TEXT("the two-storey fixture bakes"), Baked._Completed))
    { return false; }

    TestEqual(TEXT("the storeys are two separate components"), Baked._Components.Num(), 2);
    TestEqual(TEXT("and land on two layers"), Baked._Layers._LayerCount, 2);

    TestEqual(TEXT("with nothing dropped"),
        Baked._Layers.Get_AssignedSpanCount(), Get_WalkableSpanCount(Baked._Spans));

    // The defining property: within a layer, a column carries at most one span. A count of 2 here
    // would mean a query against that layer has two answers for the same XY.
    for (auto Y = 0; Y < Baked._Layers._SizeY; ++Y)
    {
        for (auto X = 0; X < Baked._Layers._SizeX; ++X)
        {
            for (auto LayerIndex = 0; LayerIndex < Baked._Layers._LayerCount; ++LayerIndex)
            {
                if (Baked._Layers.Get_OccupancyAt(X, Y, LayerIndex) <= 1)
                { continue; }

                AddError(FString::Printf(
                    TEXT("column (%d,%d) carries more than one span on layer %d"), X, Y, LayerIndex));
                return false;
            }
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Layers_RampOverItselfSplitsWithoutSevering,
    "CkTests.UnitTests.CkGroundNav.Bake.Layers_RampOverItselfSplitsWithoutSevering",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Layers_RampOverItselfSplitsWithoutSevering::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_layers;

    // A deck, a ramp beside it climbing the full length, and a second deck directly above the first,
    // reached from the top of the ramp. The two decks share every column, so no single layer can
    // hold the walk — but it is one continuous walk and must stay one component across the split.
    constexpr auto Length = 1000.0;
    constexpr auto DeckDepth = 100.0;
    constexpr auto UpperZ = 300.0;

    auto Geometry = FCk_GroundNav_GeometryBatch{};
    Geometry.Add_Box(FBox{FVector{0.0, 0.0, 0.0}, FVector{Length, DeckDepth, 10.0}});
    Geometry.Add_Box(FBox{FVector{0.0, 0.0, UpperZ}, FVector{Length, DeckDepth, UpperZ + 10.0}});

    // The ramp occupies the strip behind the decks, rising from deck height to upper-deck height.
    {
        const auto A = FVector{0.0, DeckDepth, 10.0};
        const auto B = FVector{Length, DeckDepth, UpperZ + 10.0};
        const auto C = FVector{Length, DeckDepth * 2.0, UpperZ + 10.0};
        const auto D = FVector{0.0, DeckDepth * 2.0, 10.0};

        Geometry.Add_Triangle(A, B, C);
        Geometry.Add_Triangle(A, C, D);
    }

    const auto Baked = Bake(Geometry,
        FBox{FVector{0.0, 0.0, -50.0}, FVector{Length, DeckDepth * 2.0, 600.0}}, Make_Profile());

    if (NOT TestTrue(TEXT("the ramp fixture bakes"), Baked._Completed))
    { return false; }

    TestEqual(TEXT("deck, ramp and upper deck are one continuous walk"), Baked._Components.Num(), 1);

    TestTrue(TEXT("and that one component overlaps itself, so no single layer can hold it"),
        Baked._Components.Num() == 1 && Baked._Components[0]._OverlapsItself);

    TestTrue(TEXT("so it splits across at least two layers"), Baked._Layers._LayerCount >= 2);

    // Splitting must not lose anything — the point of opening a new layer instead of dropping.
    TestEqual(TEXT("without dropping a single span"),
        Baked._Layers.Get_AssignedSpanCount(), Get_WalkableSpanCount(Baked._Spans));

    for (auto Y = 0; Y < Baked._Layers._SizeY; ++Y)
    {
        for (auto X = 0; X < Baked._Layers._SizeX; ++X)
        {
            for (auto LayerIndex = 0; LayerIndex < Baked._Layers._LayerCount; ++LayerIndex)
            {
                if (Baked._Layers.Get_OccupancyAt(X, Y, LayerIndex) <= 1)
                { continue; }

                AddError(FString::Printf(
                    TEXT("column (%d,%d) carries more than one span on layer %d"), X, Y, LayerIndex));
                return false;
            }
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
