// A cost removal must restamp the derived immutable field without geometry probes. Late derives retain
// their existing plate topology; the initial-bake history below supplies the partitioned rotated AvoidIfPossible paint.

#include "CkGroundNav/Backend/CkGroundNav_GeometryBackend_Stub.h"
#include "CkGroundNav/Bake/CkGroundNav_MarkupTypes.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Field/CkGroundNav_FieldMarkupCost.h"
#include "CkGroundNav/Query/CkGroundNav_Query_SurfaceWalk.h"
#include "CkGroundNav/Search/CkGroundNav_PathPostProcess.h"
#include "CkGroundNav/Search/CkGroundNav_PathSearch.h"

#include "CkShapes/Box/CkShapeBox_Fragment_Data.h"
#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_costremovalstraightroute
{
    using ck::groundnav::DoBake_Field;
    using ck::groundnav::FCk_GroundNav_Epoch;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldParams;
    using ck::groundnav::FCk_GroundNav_FieldPtr;
    using ck::groundnav::FCk_GroundNav_GeometryBackend_Stub;
    using ck::groundnav::FCk_GroundNav_PathPostParams;
    using ck::groundnav::FCk_GroundNav_PathQuery;
    using ck::groundnav::FCk_GroundNav_PathSearch;
    using ck::groundnav::FCk_GroundNav_PathSliceParams;
    using ck::groundnav::FCk_GroundNav_QueryAgent;
    using ck::groundnav::FCk_GroundNav_RaycastQuery;
    using ck::groundnav::Get_FieldWithMarkupCost;
    using ck::groundnav::Get_PathPlan;
    using ck::groundnav::Get_SurfaceRaycast;

    constexpr auto kCellSizeUu = 25.0f;
    constexpr auto kCellHeightUu = 10.0f;
    // Mirrors FCkAutoTest_GroundNavFixture: a 2,000 uu square, origin -1,000, 500 uu tiles.
    constexpr auto kTileSizeUu = 500.0f;
    constexpr auto kAgentRadiusUu = 42.0f;
    constexpr auto kCostMultiplier = 100.0f;
    constexpr auto kStraightToleranceUu = 5.0f;

    const auto kStart = FVector{-700.0, 0.0, 0.0};
    const auto kGoal = FVector{700.0, 0.0, 0.0};

    auto Make_Params(TConstArrayView<FCk_GroundNav_MarkupRecord> InMarkups = {}) -> FCk_GroundNav_FieldParams
    {
        auto Config = FCk_GroundNav_BakeConfig{kCellSizeUu, kCellHeightUu};
        Config.Set_TileSizeUu(kTileSizeUu);

        auto Profile = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{96.0f, 42.0f}}};
        Profile.Set_LedgeSensitivity(0.0f);

        auto Params = FCk_GroundNav_FieldParams{};
        Params._OriginXY = FVector2D{-1000.0, -1000.0};
        Params._Divisions = FIntPoint{4, 4};
        Params._MinZUu = -100.0f;
        Params._MaxZUu = 400.0f;
        Params._Config = Config;
        Params._Profile = Profile;
        Params._MaxClearanceUu = 200.0f;
        Params._MarkupRecords = InMarkups;
        return Params;
    }

    auto Make_AvoidanceCostMarkup() -> FCk_GroundNav_MarkupRecord
    {
        // CkCrowd's setup expands the authored 220x90 volume by its 400 uu path-planning clearance
        // before it paints the NavSurface markup. The native pin feeds that exact transformed OBB to
        // GroundNav's cost derive, which is the real field-side operation the removal must undo.
        auto Record = FCk_GroundNav_MarkupRecord{
            1,
            FCk_AnyShape{FCk_ShapeBox_Dimensions{FVector{620.0f, 490.0f, 100.0f}}},
            FTransform{FRotator{0.0f, 35.0f, 0.0f}, FVector::ZeroVector, FVector::OneVector},
            ECk_GroundNav_MarkupKind::Cost};
        Record.Set_CostMultiplier(kCostMultiplier);
        return Record;
    }

    auto Bake_Field(
        TConstArrayView<FCk_GroundNav_MarkupRecord> InMarkups,
        FCk_GroundNav_Field& OutField) -> bool
    {
        const auto Backend = FCk_GroundNav_GeometryBackend_Stub{TArray<FBox>{
            FBox{FVector{-1600.0, -1600.0, -10.0}, FVector{1600.0, 1600.0, 0.0}}}};
        return DoBake_Field(Backend, Make_Params(InMarkups), FCk_GroundNav_Epoch{1}, OutField).Get_IsCompleted();
    }

    auto Make_Query() -> FCk_GroundNav_PathQuery
    {
        auto Query = FCk_GroundNav_PathQuery{};
        Query._Start = kStart;
        Query._Goal = kGoal;
        Query._VerticalToleranceUu = 100.0f;
        Query._Agent = FCk_GroundNav_QueryAgent{};
        Query._Agent._RadiusUu = kAgentRadiusUu;
        return Query;
    }

    auto Get_Plan(
        const FCk_GroundNav_FieldPtr& InField,
        TArray<FVector>&              OutWaypoints,
        FString&                      OutFailure) -> bool
    {
        auto Search = FCk_GroundNav_PathSearch{};
        Search.Request_Begin(InField, Make_Query());

        while (NOT Search.Get_IsTerminal())
        { Search.ContinueSearch(FCk_GroundNav_PathSliceParams{}); }

        if (Search.Get_Status() != ECk_GroundNav_PathStatus::Ready)
        {
            OutFailure = FString::Printf(TEXT("status %d"), static_cast<int32>(Search.Get_Status()));
            return false;
        }

        auto Post = FCk_GroundNav_PathPostParams{};
        Post._AgentLocation = kStart;
        Post._Agent._RadiusUu = kAgentRadiusUu;
        Post._VerticalToleranceUu = 100.0f;
        const auto Plan = Get_PathPlan(Search.Get_Result(), *InField, Post);
        OutWaypoints.Reset();
        for (const auto& Waypoint : Plan._Waypoints)
        { OutWaypoints.Add(Waypoint._Location); }
        return true;
    }

    auto Get_MaxLateralDeviation(TConstArrayView<FVector> InWaypoints) -> double
    {
        auto MaxDeviation = 0.0;
        for (const auto& Point : InWaypoints)
        { MaxDeviation = FMath::Max(MaxDeviation, FMath::Abs(Point.Y)); }
        return MaxDeviation;
    }

    auto Get_PlateCount(const FCk_GroundNav_Field& InField) -> int32
    {
        auto Count = 0;
        for (const auto& Tile : InField._Tiles)
        { Count += Tile._Plates._Plates.Num(); }
        return Count;
    }

    auto Get_HasOnlyDefaultPlateCosts(const FCk_GroundNav_Field& InField) -> bool
    {
        for (const auto& Tile : InField._Tiles)
        {
            for (const auto& Plate : Tile._Plates._Plates)
            {
                if (Plate._AreaPolicyIndex != INDEX_NONE || Plate._CostMultiplier != 1.0f)
                { return false; }
            }
        }
        return true;
    }


    auto Get_Raycast(const FCk_GroundNav_Field& InField) -> ck::groundnav::FCk_GroundNav_RaycastResult
    {
        auto Query = FCk_GroundNav_RaycastQuery{};
        Query._Start = kStart;
        Query._End = kGoal;
        Query._StartVerticalToleranceUu = 100.0f;
        Query._Agent._RadiusUu = kAgentRadiusUu;
        Query._UseBakedPlateCost = true;
        return Get_SurfaceRaycast(InField, Query);
    }

    auto Describe_Raycast(const ck::groundnav::FCk_GroundNav_RaycastResult& InRay) -> FString
    {
        return FString::Printf(TEXT("rayStatus=%d rayCost=%.3f stoppedOnCost=%d"),
            static_cast<int32>(InRay._Status), InRay._AccumulatedCost, InRay._StoppedOnCost);
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_CostRemovalStraightRoute,
    "CkTests.UnitTests.CkGroundNav.CostRemoval.StraightRouteAfterRotatedAvoidanceMarkupRemoval",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_CostRemovalStraightRoute::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_costremovalstraightroute;

    auto Base = FCk_GroundNav_Field{};
    if (NOT TestTrue(TEXT("the unpriced rotated-avoidance scene bakes"), Bake_Field({}, Base)))
    { return false; }

    const auto BaseField = MakeShared<const FCk_GroundNav_Field>(MoveTemp(Base));
    const auto Priced = Get_FieldWithMarkupCost(
        *BaseField, TArray<FCk_GroundNav_MarkupRecord>{Make_AvoidanceCostMarkup()}, FCk_GroundNav_Epoch{2});
    if (NOT TestTrue(TEXT("the initial avoidance cost derive completes"),
        Priced.Value.Get_IsCompleted() && Priced.Key.IsValid()))
    { return false; }
    TestEqual(TEXT("the initial cost derive consumes no geometry probes"), Priced.Value.Get_ProbesSpent(), 0);

    // This late derive does not re-decompose plates. It can price the direct ray (proved below) but cannot
    // promise a geometric detour; the initial-bake history is the matching split-topology reproduction.
    auto Failure = FString{};

    const auto Removed = Get_FieldWithMarkupCost(*Priced.Key, {}, FCk_GroundNav_Epoch{3});
    if (NOT TestTrue(TEXT("removing the avoidance cost derives a complete field"),
        Removed.Value.Get_IsCompleted() && Removed.Key.IsValid()))
    { return false; }
    TestEqual(TEXT("removing cost consumes no geometry probes"), Removed.Value.Get_ProbesSpent(), 0);
    TestTrue(TEXT("removing the cost restores the base pricing records"), Removed.Key->_Params._MarkupRecords.IsEmpty());

    TArray<FVector> RemovedWaypoints;
    Failure.Reset();
    if (NOT TestTrue(TEXT("the fresh field after removal finds a route"), Get_Plan(Removed.Key, RemovedWaypoints, Failure)))
    { AddError(FString::Printf(TEXT("cost removal route failed: %s"), *Failure)); return false; }

    const auto BaseRay = Get_Raycast(*BaseField);
    const auto PricedRay = Get_Raycast(*Priced.Key);
    const auto RemovedRay = Get_Raycast(*Removed.Key);
    AddInfo(FString::Printf(TEXT("[COST-REMOVAL-STRAIGHT] before=%s priced=%s removed=%s waypoints=%d maxLateral=%.3f"),
        *Describe_Raycast(BaseRay), *Describe_Raycast(PricedRay), *Describe_Raycast(RemovedRay),
        RemovedWaypoints.Num(), Get_MaxLateralDeviation(RemovedWaypoints)));

    TestTrue(TEXT("the initial cost derive raises direct surface-ray cost"),
        PricedRay._AccumulatedCost > BaseRay._AccumulatedCost);
    TestTrue(TEXT("the removal ray restores the baseline field status"), RemovedRay._Status == BaseRay._Status);
    TestTrue(TEXT("the removal ray restores the baseline field cost"),
        FMath::IsNearlyEqual(RemovedRay._AccumulatedCost, BaseRay._AccumulatedCost, 0.01f));

    TestTrue(TEXT("a new search after removal is straight within the product tolerance"),
        Get_MaxLateralDeviation(RemovedWaypoints) <= kStraightToleranceUu);

    // The runtime failure history: the original geometry publish already carried the Cost markup,
    // so plate decomposition has split on its OBB before removal. A later cost derive cannot re-merge
    // those plates; it must reset every retained partition and a new query must still take the direct route.
    auto InitiallyMarked = FCk_GroundNav_Field{};
    const auto Markup = Make_AvoidanceCostMarkup();
    if (NOT TestTrue(TEXT("the same scene bakes with the rotated cost markup at initial publish"),
        Bake_Field(TArray<FCk_GroundNav_MarkupRecord>{Markup}, InitiallyMarked)))
    { return false; }

    const auto InitiallyMarkedField = MakeShared<const FCk_GroundNav_Field>(MoveTemp(InitiallyMarked));
    const auto InitialPartitionCount = Get_PlateCount(*InitiallyMarkedField);
    TestTrue(TEXT("initial cost markup split at least one baked plate"),
        InitialPartitionCount > Get_PlateCount(*BaseField));

    TArray<FVector> InitiallyBakedWaypoints;
    Failure.Reset();
    if (NOT TestTrue(TEXT("the initial baked rotated-cost field finds a route"),
        Get_Plan(InitiallyMarkedField, InitiallyBakedWaypoints, Failure)))
    { AddError(FString::Printf(TEXT("initial baked cost route failed: %s"), *Failure)); return false; }
    TestTrue(TEXT("the initial baked rotated-cost field buys a real detour"),
        Get_MaxLateralDeviation(InitiallyBakedWaypoints) > kStraightToleranceUu);


    const auto RemovedInitialCost = Get_FieldWithMarkupCost(*InitiallyMarkedField, {}, FCk_GroundNav_Epoch{2});
    if (NOT TestTrue(TEXT("removing initial baked cost derives a complete field"),
        RemovedInitialCost.Value.Get_IsCompleted() && RemovedInitialCost.Key.IsValid()))
    { return false; }
    TestEqual(TEXT("removing initial baked cost consumes no geometry probes"), RemovedInitialCost.Value.Get_ProbesSpent(), 0);
    TestEqual(TEXT("cost removal preserves the original baked partition count"),
        Get_PlateCount(*RemovedInitialCost.Key), InitialPartitionCount);
    TestTrue(TEXT("cost removal restores the default price on every retained baked plate"),
        Get_HasOnlyDefaultPlateCosts(*RemovedInitialCost.Key));

    TArray<FVector> InitiallyBakedRemovalWaypoints;
    Failure.Reset();
    if (NOT TestTrue(TEXT("the fresh route after initial baked cost removal is Ready"),
        Get_Plan(RemovedInitialCost.Key, InitiallyBakedRemovalWaypoints, Failure)))
    { AddError(FString::Printf(TEXT("initial-baked cost removal route failed: %s"), *Failure)); return false; }

    const auto InitialBakedRemovedRay = Get_Raycast(*RemovedInitialCost.Key);
    AddInfo(FString::Printf(
        TEXT("[COST-REMOVAL-BAKED] partitions=%d->%d removed=%s waypoints=%d maxLateral=%.3f"),
        InitialPartitionCount, Get_PlateCount(*RemovedInitialCost.Key), *Describe_Raycast(InitialBakedRemovedRay),
        InitiallyBakedRemovalWaypoints.Num(), Get_MaxLateralDeviation(InitiallyBakedRemovalWaypoints)));
    TestTrue(TEXT("initial-baked cost removal ray clears with baseline status"),
        InitialBakedRemovedRay._Status == BaseRay._Status);
    TestTrue(TEXT("initial-baked cost removal ray restores baseline cost"),
        FMath::IsNearlyEqual(InitialBakedRemovedRay._AccumulatedCost, BaseRay._AccumulatedCost, 0.01f));
    TestTrue(TEXT("initial-baked cost removal fresh route is straight within product tolerance"),
        Get_MaxLateralDeviation(InitiallyBakedRemovalWaypoints) <= kStraightToleranceUu);


    return true;
}
