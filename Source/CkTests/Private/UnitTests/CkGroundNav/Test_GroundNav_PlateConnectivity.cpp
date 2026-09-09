// Plate interiors are only safe to treat as convex when every cardinal cell pair inside them is
// connected by walkability. This fixture pins the otherwise-hidden gap between merge tolerance and
// step height through the same rasterize -> walkability -> layers -> plates path a tile bake uses.

#include "CkGroundNav/Backend/CkGroundNav_GeometryBackend_Stub.h"
#include "CkGroundNav/Bake/CkGroundNav_Plates.h"
#include "CkGroundNav/Bake/CkGroundNav_Portals.h"
#include "CkGroundNav/Bake/CkGroundNav_Rasterize.h"
#include "CkGroundNav/Bake/CkGroundNav_Walkability.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Search/CkGroundNav_PathSearch.h"

#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_plateconnectivity
{
    using ck::groundnav::DoBake_Field;
    using ck::groundnav::DoCompute_Clearance;
    using ck::groundnav::DoDecompose_Plates;
    using ck::groundnav::DoExtract_Layers;
    using ck::groundnav::DoExtract_Portals;
    using ck::groundnav::DoFilter_Walkability;
    using ck::groundnav::DoRasterizeSpans;
    using ck::groundnav::FCk_GroundNav_ClearanceField;
    using ck::groundnav::FCk_GroundNav_ConnectionField;
    using ck::groundnav::FCk_GroundNav_Epoch;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldParams;
    using ck::groundnav::FCk_GroundNav_FieldPtr;
    using ck::groundnav::FCk_GroundNav_GeometryBackend_Stub;
    using ck::groundnav::FCk_GroundNav_LayerField;
    using ck::groundnav::FCk_GroundNav_PathQuery;
    using ck::groundnav::FCk_GroundNav_Plate;
    using ck::groundnav::FCk_GroundNav_PlateField;
    using ck::groundnav::FCk_GroundNav_PortalField;
    using ck::groundnav::FCk_GroundNav_SpanField;
    using ck::groundnav::Get_Path;

    constexpr auto kCellSizeUu = 100.0f;
    constexpr auto kCellHeightUu = 1.0f;
    constexpr auto kStepHeightUu = 5.0f;
    constexpr auto kMergeToleranceUu = 10.0f;
    constexpr auto kLowTopZUu = 0.0f;
    constexpr auto kHighTopZUu = 8.0f;

    struct FPipeline
    {
        FCk_GroundNav_SpanField _Spans;
        FCk_GroundNav_ConnectionField _Connections;
        FCk_GroundNav_LayerField _Layers;
        FCk_GroundNav_ClearanceField _Clearance;
        FCk_GroundNav_PlateField _Plates;
        FCk_GroundNav_PortalField _Portals;
    };

    auto Make_Profile() -> FCk_GroundNav_AgentProfile
    {
        auto Profile = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{70.0f, 20.0f}}};
        Profile.Set_StepHeightUu(kStepHeightUu);
        Profile.Set_LedgeSensitivity(0.0f);

        return Profile;
    }

    auto Make_Config() -> FCk_GroundNav_BakeConfig
    {
        auto Config = FCk_GroundNav_BakeConfig{kCellSizeUu, kCellHeightUu};
        Config.Set_TileSizeUu(2.0f * kCellSizeUu);

        return Config;
    }

    auto Make_Boxes(float InRightTopZUu) -> TArray<FBox>
    {
        return TArray<FBox>{
            FBox{FVector{0.0, 0.0, -10.0}, FVector{kCellSizeUu, kCellSizeUu, kLowTopZUu}},
            FBox{FVector{kCellSizeUu, 0.0, -10.0}, FVector{2.0f * kCellSizeUu, kCellSizeUu, InRightTopZUu}}};
    }

    auto Make_Region() -> FBox
    {
        return FBox{FVector{0.0, 0.0, -50.0}, FVector{2.0f * kCellSizeUu, kCellSizeUu, 200.0}};
    }

    auto Make_NewRowBoxes() -> TArray<FBox>
    {
        return TArray<FBox>{
            FBox{FVector{0.0, 0.0, -10.0}, FVector{kCellSizeUu, kCellSizeUu, 0.0}},
            FBox{FVector{kCellSizeUu, 0.0, -10.0}, FVector{2.0f * kCellSizeUu, kCellSizeUu, 4.0}},
            FBox{FVector{0.0, kCellSizeUu, -10.0}, FVector{kCellSizeUu, 2.0f * kCellSizeUu, 0.0}},
            FBox{FVector{kCellSizeUu, kCellSizeUu, -10.0}, FVector{2.0f * kCellSizeUu, 2.0f * kCellSizeUu, 8.0}}};
    }

    auto Make_NewRowRegion() -> FBox
    {
        return FBox{FVector{0.0, 0.0, -50.0}, FVector{2.0f * kCellSizeUu, 2.0f * kCellSizeUu, 200.0}};
    }

    auto Make_FieldParams() -> FCk_GroundNav_FieldParams
    {
        auto Params = FCk_GroundNav_FieldParams{};
        Params._OriginXY = FVector2D::ZeroVector;
        Params._Divisions = FIntPoint{1, 1};
        Params._MinZUu = -50.0f;
        Params._MaxZUu = 200.0f;
        Params._Config = Make_Config();
        Params._Profile = Make_Profile();
        Params._MergeTunables = FCk_GroundNav_MergeTunables{kMergeToleranceUu, 10.0f};
        Params._MaxClearanceUu = kCellSizeUu;

        return Params;
    }

    auto Bake_Pipeline(
        const TArray<FBox>& InBoxes,
        const FBox&         InRegion,
        FPipeline&          OutPipeline) -> bool
    {
        auto Geometry = FCk_GroundNav_GeometryBatch{};

        for (const auto& Box : InBoxes)
        { Geometry.Add_Box(Box); }

        const auto Profile = Make_Profile();

        if (NOT DoRasterizeSpans(Geometry, InRegion, Make_Config(), Profile, OutPipeline._Spans).Get_IsCompleted())
        { return false; }

        if (NOT DoFilter_Walkability(Profile, OutPipeline._Spans, OutPipeline._Connections).Get_IsCompleted())
        { return false; }

        if (NOT DoExtract_Layers(OutPipeline._Spans, OutPipeline._Connections, OutPipeline._Layers).Get_IsCompleted())
        { return false; }

        if (NOT DoCompute_Clearance(OutPipeline._Layers, OutPipeline._Connections, kCellSizeUu,
            OutPipeline._Clearance).Get_IsCompleted())
        { return false; }

        const auto Tunables = FCk_GroundNav_MergeTunables{kMergeToleranceUu, 10.0f};

        if (NOT DoDecompose_Plates(OutPipeline._Spans, OutPipeline._Layers, OutPipeline._Connections, Tunables,
            OutPipeline._Plates).Get_IsCompleted())
        { return false; }

        return DoExtract_Portals(OutPipeline._Spans, OutPipeline._Layers, OutPipeline._Connections,
            OutPipeline._Plates, OutPipeline._Clearance, OutPipeline._Portals).Get_IsCompleted();
    }

    auto Bake_Pipeline(float InRightTopZUu, FPipeline& OutPipeline) -> bool
    {
        return Bake_Pipeline(Make_Boxes(InRightTopZUu), Make_Region(), OutPipeline);
    }

    auto Get_SpanIndexForLayer(
        const FCk_GroundNav_LayerField& InLayers,
        int32                           InX,
        int32                           InY,
        int32                           InLayer) -> int32
    {
        const auto& Column = InLayers.Get_Column(InX, InY);

        for (auto SpanIndex = 0; SpanIndex < Column.Num(); ++SpanIndex)
        {
            if (Column[SpanIndex] == InLayer)
            { return SpanIndex; }
        }

        return INDEX_NONE;
    }

    auto Get_PathAcrossStep(float InRightTopZUu) -> ECk_GroundNav_PathStatus
    {
        auto MutableField = MakeShared<FCk_GroundNav_Field>();
        const auto Backend = FCk_GroundNav_GeometryBackend_Stub{Make_Boxes(InRightTopZUu)};

        if (NOT DoBake_Field(Backend, Make_FieldParams(), FCk_GroundNav_Epoch{1}, *MutableField).Get_IsCompleted())
        { return ECk_GroundNav_PathStatus::Unbuilt; }

        const FCk_GroundNav_FieldPtr Field = MutableField;
        auto Query = FCk_GroundNav_PathQuery{};
        Query._Start = FVector{0.5f * kCellSizeUu, 0.5f * kCellSizeUu, kLowTopZUu};
        Query._Goal = FVector{1.5f * kCellSizeUu, 0.5f * kCellSizeUu, InRightTopZUu};
        Query._VerticalToleranceUu = kStepHeightUu;

        return Get_Path(Field, Query)._Status;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_PlateConnectivity_RejectsAnUnconnectedStepInsideMergeTolerance,
    "CkTests.UnitTests.CkGroundNav.Bake.PlateConnectivity_RejectsAnUnconnectedStepInsideMergeTolerance",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_PlateConnectivity_RejectsAnUnconnectedStepInsideMergeTolerance::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_plateconnectivity;

    auto Disconnected = FPipeline{};

    if (NOT TestTrue(TEXT("the eight-uu step fixture completes every bake stage"),
        Bake_Pipeline(kHighTopZUu, Disconnected)))
    { return false; }

    TestEqual(TEXT("the disconnected two-cell fixture still occupies one extracted layer"),
        Disconnected._Layers._LayerCount, 1);

    const auto LeftSpan = Get_SpanIndexForLayer(Disconnected._Layers, 0, 0, 0);
    const auto RightSpan = Get_SpanIndexForLayer(Disconnected._Layers, 1, 0, 0);

    if (NOT TestTrue(TEXT("both cells retain a walkable layer surface"),
        LeftSpan != INDEX_NONE && RightSpan != INDEX_NONE))
    { return false; }

    TestFalse(TEXT("an eight-uu riser is not a five-uu step from left to right"),
        Disconnected._Connections.Get_Column(0, 0)[LeftSpan].Get_IsConnected(0));
    TestFalse(TEXT("the rejected step is absent in both directions"),
        Disconnected._Connections.Get_Column(1, 0)[RightSpan].Get_IsConnected(2));

    const auto LeftPlate = Disconnected._Plates.Get_PlateIndexAt(0, 0, 0);
    const auto RightPlate = Disconnected._Plates.Get_PlateIndexAt(1, 0, 0);

    TestNotEqual(TEXT("an absent cardinal connection must split the traversable plate"),
        LeftPlate, RightPlate);
    TestEqual(TEXT("the absent connection produces no portal that could bridge it"),
        Disconnected._Portals.Get_PortalCount(), 0);
    TestEqual(TEXT("a path may not bridge the rejected step through a shared plate"),
        Get_PathAcrossStep(kHighTopZUu), ECk_GroundNav_PathStatus::Unreachable);

    auto Connected = FPipeline{};

    if (NOT TestTrue(TEXT("the level control completes every bake stage"),
        Bake_Pipeline(kLowTopZUu, Connected)))
    { return false; }

    const auto ConnectedLeftSpan = Get_SpanIndexForLayer(Connected._Layers, 0, 0, 0);

    if (NOT TestTrue(TEXT("the level control retains its left surface"), ConnectedLeftSpan != INDEX_NONE))
    { return false; }

    TestTrue(TEXT("the level control keeps its cardinal connection"),
        Connected._Connections.Get_Column(0, 0)[ConnectedLeftSpan].Get_IsConnected(0));
    TestEqual(TEXT("a genuinely connected level pair may share one plate"),
        Connected._Plates.Get_PlateIndexAt(0, 0, 0), Connected._Plates.Get_PlateIndexAt(1, 0, 0));
    TestEqual(TEXT("the level control remains pathable"),
        Get_PathAcrossStep(kLowTopZUu), ECk_GroundNav_PathStatus::Ready);

    auto NewRow = FPipeline{};

    if (NOT TestTrue(TEXT("the new-row horizontal-gap fixture completes every bake stage"),
        Bake_Pipeline(Make_NewRowBoxes(), Make_NewRowRegion(), NewRow)))
    { return false; }

    const auto LowerLeftSpan = Get_SpanIndexForLayer(NewRow._Layers, 0, 0, 0);
    const auto LowerRightSpan = Get_SpanIndexForLayer(NewRow._Layers, 1, 0, 0);
    const auto UpperLeftSpan = Get_SpanIndexForLayer(NewRow._Layers, 0, 1, 0);
    const auto UpperRightSpan = Get_SpanIndexForLayer(NewRow._Layers, 1, 1, 0);

    if (NOT TestTrue(TEXT("the new-row fixture retains all four layer surfaces"),
        LowerLeftSpan != INDEX_NONE && LowerRightSpan != INDEX_NONE &&
        UpperLeftSpan != INDEX_NONE && UpperRightSpan != INDEX_NONE))
    { return false; }

    TestTrue(TEXT("the first row is connected"),
        NewRow._Connections.Get_Column(0, 0)[LowerLeftSpan].Get_IsConnected(0));
    TestTrue(TEXT("both new-row vertical joins are connected"),
        NewRow._Connections.Get_Column(0, 0)[LowerLeftSpan].Get_IsConnected(1) &&
        NewRow._Connections.Get_Column(1, 0)[LowerRightSpan].Get_IsConnected(1));
    TestFalse(TEXT("the new row's eight-uu horizontal riser is absent"),
        NewRow._Connections.Get_Column(0, 1)[UpperLeftSpan].Get_IsConnected(0));
    TestNotEqual(TEXT("a new row may not merge across its missing internal horizontal edge"),
        NewRow._Plates.Get_PlateIndexAt(0, 1, 0), NewRow._Plates.Get_PlateIndexAt(1, 1, 0));

    auto MalformedConnections = Connected._Connections;
    MalformedConnections._Columns[0][ConnectedLeftSpan]._Neighbours[0] = 99;
    auto PreservedOutput = Connected._Plates;
    const auto MalformedResult = DoDecompose_Plates(
        Connected._Spans, Connected._Layers, MalformedConnections,
        FCk_GroundNav_MergeTunables{kMergeToleranceUu, 10.0f}, PreservedOutput);

    TestEqual(TEXT("an out-of-range neighbour reference is invalid input"),
        MalformedResult.Get_Status(), ECk_GroundNav_BakeStatus::InvalidInput);
    TestEqual(TEXT("invalid topology leaves the prior plate output intact"),
        PreservedOutput.Get_PlateIndexAt(0, 0, 0), Connected._Plates.Get_PlateIndexAt(0, 0, 0));
    TestEqual(TEXT("invalid topology leaves every plate intact"),
        PreservedOutput._Plates.Num(), Connected._Plates._Plates.Num());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
