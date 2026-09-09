// A direct strict-cell search experiment. It intentionally bypasses world, ECS and request queues:
// the reported counters describe one planner query, not runtime service pressure.

#include "CkAutoTest_Utils.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Query/CkGroundNav_Query_DynamicObstacles.h"
#include "CkGroundNav/Search/CkGroundNav_CellPathSearch.h"
#include "CkGroundNav/Search/CkGroundNav_PathSearch.h"

#include "../CkUnitTest_Common.h"
#include "Test_GroundNav_QueryFixtures.h"

#include <HAL/IConsoleManager.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_strictsearchwork
{
    using ck::groundnav::ECk_GroundNav_CellRouteEdgeKind;
    using ck::groundnav::ECk_GroundNav_DynamicUnionEdge;
    using ck::groundnav::ECk_GroundNav_PathRouteKind;
    using ck::groundnav::FCk_GroundNav_CellSearchTiming;
    using ck::groundnav::FCk_GroundNav_DynamicObstacleDisc;
    using ck::groundnav::FCk_GroundNav_DynamicObstacleObb;
    using ck::groundnav::FCk_GroundNav_DynamicObstacleSnapshot;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_PathQuery;
    using ck::groundnav::FCk_GroundNav_PathResult;
    using ck::groundnav::FCk_GroundNav_PathSearch;
    using ck::groundnav::FCk_GroundNav_PathSliceParams;
    using ck::groundnav::Get_DynamicUnionEdge;
    using ck::groundnav::Try_MakeDynamicObstacleSnapshot;

    using ck_test_groundnav_queryfixtures::Bake;
    using ck_test_groundnav_queryfixtures::kGroundZ;
    using ck_test_groundnav_queryfixtures::Make_QueryParams;

    const auto kTimingCVar = FName{TEXT("ck.GroundNav.Debug.CellSearchTiming")};
    const auto kStart = FVector{100.0, 100.0, kGroundZ};
    const auto kGoal = FVector{1500.0, 1500.0, kGroundZ};
    constexpr auto kDiscCount = 9;

    class FScopedCVar
    {
    public:
        explicit FScopedCVar(FName InName, const FString& InValue)
            : _Name(InName)
            , _CVar(IConsoleManager::Get().FindConsoleVariable(*InName.ToString()))
        {
            UCk_Utils_AutoTest_UE::Request_PushCVarOverride(_Name, InValue);
        }

        ~FScopedCVar()
        {
            UCk_Utils_AutoTest_UE::Request_PopCVarOverride(_Name);
        }

        auto HasEffectiveValue(int32 InExpected) const -> bool
        {
            return _CVar != nullptr && _CVar->GetInt() == InExpected;
        }

    private:
        FName _Name;
        IConsoleVariable* _CVar = nullptr;
    };

    struct FRun
    {
        ECk_GroundNav_PathStatus _Status = ECk_GroundNav_PathStatus::InProgress;
        FCk_GroundNav_PathResult _Result;
        FCk_GroundNav_CellSearchTiming _Timing;
    };

    auto MakeDisc(const FVector& InCentre) -> FCk_GroundNav_DynamicObstacleDisc
    {
        auto Disc = FCk_GroundNav_DynamicObstacleDisc{};
        Disc._Centre = InCentre;
        Disc._RadiusUu = 55.0f;
        Disc._VerticalHalfExtentUu = 30.0f;
        return Disc;
    }

    auto MakeSnapshot(TConstArrayView<FCk_GroundNav_DynamicObstacleDisc> InDiscs)
        -> TOptional<FCk_GroundNav_DynamicObstacleSnapshot>
    {
        return Try_MakeDynamicObstacleSnapshot(InDiscs, TConstArrayView<FCk_GroundNav_DynamicObstacleObb>{});
    }

    auto RunToTerminal(
        const ck::groundnav::FCk_GroundNav_FieldPtr& InField,
        const FCk_GroundNav_PathQuery& InQuery) -> FRun
    {
        auto Search = FCk_GroundNav_PathSearch{};
        auto Result = FRun{};
        Result._Status = Search.Request_Begin(InField, InQuery);

        auto Slice = FCk_GroundNav_PathSliceParams{};
        Slice._MaxIterations = 0;

        for (auto Iteration = 0; Iteration < 20'000 && NOT Search.Get_IsTerminal(); ++Iteration)
        { Result._Status = Search.ContinueSearch(Slice); }

        if (NOT Search.Get_IsTerminal())
        {
            Result._Status = ECk_GroundNav_PathStatus::InProgress;
            Result._Timing = Search.Get_CellSearchTiming();
            return Result;
        }

        Result._Status = Search.Get_Status();
        Result._Result = Search.Get_Result();
        Result._Timing = Search.Get_CellSearchTiming();
        return Result;
    }

    auto Get_IsFiniteStrictRoute(const FRun& InRun) -> bool
    {
        if (InRun._Result._RouteKind != ECk_GroundNav_PathRouteKind::StrictCell ||
            InRun._Result._CellRoute.IsEmpty())
        { return false; }

        for (const auto& Edge : InRun._Result._CellRoute)
        {
            if (Edge._FromPoint.ContainsNaN() || Edge._ToPoint.ContainsNaN())
            { return false; }

            if (Edge._Kind != ECk_GroundNav_CellRouteEdgeKind::Link)
            {
                const auto Union = Get_DynamicUnionEdge(
                    InRun._Result._DynamicObstacles, Edge._FromPoint, Edge._ToPoint);
                if (NOT Union.IsSet() || *Union != ECk_GroundNav_DynamicUnionEdge::Clear)
                { return false; }
            }
        }

        return true;
    }

    auto AddRunInfo(FAutomationTestBase& InTest, const TCHAR* InName, const FRun& InRun) -> void
    {
        const auto& Timing = InRun._Timing;
        InTest.AddInfo(FString::Printf(
            TEXT("[STRICT-SEARCH-WORK] %s status=%d kind=%d expansions=%d edges=%d steps=%d rays=%d dynamic=%d "
                 "edgeUs=%lld stepUs=%lld rayUs=%lld dynamicUs=%lld"),
            InName, static_cast<int32>(InRun._Status), static_cast<int32>(InRun._Result._RouteKind),
            InRun._Result._ExpansionCount, Timing._EdgeBuildCount, Timing._StepAcrossCount,
            Timing._StaticRayCount, Timing._DynamicAdmissionCount,
            static_cast<long long>(Timing._EdgeBuildTime.Get_Seconds() * 1'000'000.0),
            static_cast<long long>(Timing._StepAcrossTime.Get_Seconds() * 1'000'000.0),
            static_cast<long long>(Timing._StaticRayTime.Get_Seconds() * 1'000'000.0),
            static_cast<long long>(Timing._DynamicAdmissionTime.Get_Seconds() * 1'000'000.0)));
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_StrictSearchWork_IsolatesPlannerWork,
    "CkTests.UnitTests.CkGroundNav.Path.StrictSearchWork.IsolatesPlannerWork",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_StrictSearchWork_IsolatesPlannerWork::RunTest(const FString& InParameters)
{
    using namespace ck_test_groundnav_strictsearchwork;

    // 2x2 tiles / 64x64 cells: long enough for the strict graph's cardinal expansion pattern, while
    // remaining a small deterministic native bake. The floor exceeds every tile halo.
    auto Field = MakeShared<FCk_GroundNav_Field>();
    const auto FlatFloor = TArray<FBox>{
        FBox{FVector{-400.0, -400.0, -10.0}, FVector{2000.0, 2000.0, kGroundZ}}};
    if (NOT TestTrue(TEXT("the flat experiment field bakes"), Bake(FlatFloor, Make_QueryParams(), *Field)))
    { return false; }

    auto LegacyQuery = FCk_GroundNav_PathQuery{};
    LegacyQuery._Start = kStart;
    LegacyQuery._Goal = kGoal;

    auto FarDiscs = TArray<FCk_GroundNav_DynamicObstacleDisc>{};
    auto ChainDiscs = TArray<FCk_GroundNav_DynamicObstacleDisc>{};
    FarDiscs.Reserve(kDiscCount);
    ChainDiscs.Reserve(kDiscCount);
    for (auto Index = 0; Index < kDiscCount; ++Index)
    {
        const auto Along = 450.0f + static_cast<float>(Index) * 75.0f;
        FarDiscs.Add(MakeDisc(FVector{Along, Along, 10'000.0}));
        ChainDiscs.Add(MakeDisc(FVector{Along, Along, kGroundZ}));
    }

    const auto FarSnapshot = MakeSnapshot(FarDiscs);
    const auto ChainSnapshot = MakeSnapshot(ChainDiscs);
    const auto HasFarSnapshot = TestTrue(TEXT("the far dynamic snapshot is valid"), FarSnapshot.IsSet());
    const auto HasChainSnapshot = TestTrue(TEXT("the blocking dynamic snapshot is valid"), ChainSnapshot.IsSet());
    if (NOT HasFarSnapshot || NOT HasChainSnapshot) { return false; }

    auto IrrelevantStrictQuery = LegacyQuery;
    IrrelevantStrictQuery._DynamicObstacles = FarSnapshot.GetValue();
    auto BlockingStrictQuery = LegacyQuery;
    BlockingStrictQuery._DynamicObstacles = ChainSnapshot.GetValue();

    const auto FarChord = Get_DynamicUnionEdge(IrrelevantStrictQuery._DynamicObstacles, kStart, kGoal);
    const auto BlockingChord = Get_DynamicUnionEdge(BlockingStrictQuery._DynamicObstacles, kStart, kGoal);
    const auto HasFarChord = TestTrue(TEXT("the high-Z snapshot evaluates the experiment chord"), FarChord.IsSet());
    const auto HasBlockingChord = TestTrue(TEXT("the grounded chain evaluates the experiment chord"), BlockingChord.IsSet());
    if (NOT HasFarChord || NOT HasBlockingChord) { return false; }
    TestEqual(TEXT("the high-Z snapshot leaves the direct chord clear"), *FarChord,
        ECk_GroundNav_DynamicUnionEdge::Clear);
    TestEqual(TEXT("the grounded chain makes the direct chord non-monotonic"), *BlockingChord,
        ECk_GroundNav_DynamicUnionEdge::NonMonotonic);

    const auto ScopedTiming = FScopedCVar{kTimingCVar, TEXT("1")};
    if (NOT TestTrue(TEXT("strict-cell timing is enabled for this scoped experiment"),
        ScopedTiming.HasEffectiveValue(1)))
    { return false; }

    const auto Legacy = RunToTerminal(Field, LegacyQuery);
    const auto IrrelevantStrict = RunToTerminal(Field, IrrelevantStrictQuery);
    const auto BlockingStrict = RunToTerminal(Field, BlockingStrictQuery);

    AddRunInfo(*this, TEXT("legacy-empty"), Legacy);
    AddRunInfo(*this, TEXT("strict-far-high-z"), IrrelevantStrict);
    AddRunInfo(*this, TEXT("strict-nine-disc-chain"), BlockingStrict);

    TestEqual(TEXT("the legacy empty query resolves"), Legacy._Status, ECk_GroundNav_PathStatus::Ready);
    TestEqual(TEXT("the irrelevant populated snapshot selects strict-cell routing"),
        IrrelevantStrict._Result._RouteKind, ECk_GroundNav_PathRouteKind::StrictCell);
    TestEqual(TEXT("the blocking populated snapshot selects strict-cell routing"),
        BlockingStrict._Result._RouteKind, ECk_GroundNav_PathRouteKind::StrictCell);
    TestEqual(TEXT("the irrelevant strict query resolves"), IrrelevantStrict._Status, ECk_GroundNav_PathStatus::Ready);
    TestEqual(TEXT("the blocking strict query finds a two-sided detour"), BlockingStrict._Status, ECk_GroundNav_PathStatus::Ready);
    TestTrue(TEXT("the irrelevant strict query records enabled timing"), IrrelevantStrict._Timing._IsEnabled);
    TestEqual(TEXT("the irrelevant strict query captures all discs"),
        IrrelevantStrict._Timing._SnapshotDiscCount, kDiscCount);
    TestTrue(TEXT("the blocking strict query records enabled timing"), BlockingStrict._Timing._IsEnabled);
    TestEqual(TEXT("the blocking strict query captures all discs"),
        BlockingStrict._Timing._SnapshotDiscCount, kDiscCount);
    TestTrue(TEXT("the irrelevant strict route is finite and dynamically clear"), Get_IsFiniteStrictRoute(IrrelevantStrict));
    TestTrue(TEXT("the blocking strict route is finite and dynamically clear"), Get_IsFiniteStrictRoute(BlockingStrict));
    TestTrue(TEXT("the static chain forces more than one strict route leg"),
        BlockingStrict._Result._CellRoute.Num() > 2);

    // This is a diagnostic experiment, not a machine-sensitive performance gate. The three records
    // distinguish legacy planning, intrinsic strict-cell work, and detour branching in its log only.
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
