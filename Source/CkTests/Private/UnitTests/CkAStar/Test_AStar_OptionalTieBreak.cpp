#include "CkAStar/Algorithm/CkAStar_GraphConcept.h"
#include "CkAStar/Algorithm/CkAStar_Search.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_astar_optional_tiebreak
{
    // The goal lane and every dead-end lane have exactly F = 10. The optional score prefers the
    // goal lane's lower remaining distance; the legacy graph deliberately has no TieBreak method.
    struct FEqualFLaneGraphBase
    {
        static constexpr int32 Start = 0;
        static constexpr int32 FirstDeadEnd = 1;
        static constexpr int32 DeadEndCount = 16;
        static constexpr int32 GoalLane = FirstDeadEnd + DeadEndCount;
        static constexpr int32 Goal = GoalLane + 1;

        auto Neighbors(int32 InNode) const -> TArray<int32>
        {
            if (InNode == Start)
            {
                auto Result = TArray<int32>{};
                Result.Reserve(DeadEndCount + 1);
                for (auto Node = FirstDeadEnd; Node < FirstDeadEnd + DeadEndCount; ++Node)
                {
                    Result.Add(Node);
                }
                Result.Add(GoalLane);
                return Result;
            }

            return InNode == GoalLane ? TArray<int32>{Goal} : TArray<int32>{};
        }

        auto Cost(int32 InFrom, int32 InTo) const -> float
        {
            if (InFrom == Start && InTo == GoalLane)
            {
                return 5.0f;
            }

            if (InFrom == GoalLane && InTo == Goal)
            {
                return 5.0f;
            }

            return 1.0f;
        }

        auto Heuristic(int32 InNode, int32 InGoal) const -> float
        {
            check(InGoal == Goal);
            if (InNode == Goal)
            {
                return 0.0f;
            }

            return InNode == GoalLane ? 5.0f : (InNode == Start ? 10.0f : 9.0f);
        }

        auto IsGoal(int32 InNode) const -> bool
        {
            return InNode == Goal;
        }
    };

    struct FLegacyEqualFLaneGraph : FEqualFLaneGraphBase
    {
    };

    struct FGoalDirectedEqualFLaneGraph : FEqualFLaneGraphBase
    {
        auto TieBreak(int32 InNode, int32 InGoal) const -> float
        {
            return Heuristic(InNode, InGoal);
        }
    };

    struct FCheaperPrimaryGraph
    {
        static constexpr int32 Start = 0;
        static constexpr int32 CheaperGoal = 1;
        static constexpr int32 TieFavoredExpensive = 2;

        auto Neighbors(int32 InNode) const -> TArray<int32>
        {
            return InNode == Start ? TArray<int32>{CheaperGoal, TieFavoredExpensive} : TArray<int32>{};
        }

        auto Cost(int32 InFrom, int32 InTo) const -> float
        {
            check(InFrom == Start);
            return InTo == CheaperGoal ? 1.0f : 2.0f;
        }

        auto Heuristic(int32 InNode, int32 InGoal) const -> float
        {
            check(InGoal == CheaperGoal);
            return 0.0f;
        }

        auto IsGoal(int32 InNode) const -> bool
        {
            return InNode == CheaperGoal;
        }

        auto TieBreak(int32 InNode, int32 InGoal) const -> float
        {
            check(InGoal == CheaperGoal);
            return InNode == TieFavoredExpensive ? 0.0f : 100.0f;
        }
    };

    static_assert(ck::astar::AStarGraph<FLegacyEqualFLaneGraph, int32>);
    static_assert(NOT ck::astar::AStarGraphWithTieBreak<FLegacyEqualFLaneGraph, int32>);
    static_assert(ck::astar::AStarGraphWithTieBreak<FGoalDirectedEqualFLaneGraph, int32>);

    template <typename T_Graph>
    auto Solve(T_Graph InGraph, int32 InStart, int32 InGoal) -> ck::astar::TSearchState<int32, T_Graph>
    {
        auto Search = ck::astar::TSearchState<int32, T_Graph>{MoveTemp(InGraph), InStart, InGoal};
        while (Search.ContinueSearch({}) == ck::astar::ESearchStatus::InProgress)
        {
        }
        return Search;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_AStar_OptionalTieBreak,
    "CkTests.UnitTests.CkAStar.OptionalTieBreak",
    kCkUnitTestFlags)

bool FCkTest_AStar_OptionalTieBreak::RunTest(const FString& Parameters)
{
    using namespace ck_test_astar_optional_tiebreak;

    const auto Legacy = Solve(FLegacyEqualFLaneGraph{}, FEqualFLaneGraphBase::Start, FEqualFLaneGraphBase::Goal);
    TestEqual(TEXT("a graph without TieBreak still completes"), Legacy.GetStatus(), ck::astar::ESearchStatus::Complete);
    TestEqual(TEXT("the legacy graph retains its optimal cost"), Legacy.GetResultCost(), 10.0f);

    const auto GoalDirected = Solve(
        FGoalDirectedEqualFLaneGraph{}, FEqualFLaneGraphBase::Start, FEqualFLaneGraphBase::Goal);
    TestEqual(TEXT("the opt-in equal-F lane graph completes"),
        GoalDirected.GetStatus(), ck::astar::ESearchStatus::Complete);
    TestEqual(TEXT("the opt-in graph retains the same optimal cost"), GoalDirected.GetResultCost(), 10.0f);
    TestTrue(TEXT("the optional secondary score reduces equal-F lane work"),
        GoalDirected.GetTotalIterations() < Legacy.GetTotalIterations());

    const auto WarmPrefix = TArray<int32>{FEqualFLaneGraphBase::Start, FEqualFLaneGraphBase::GoalLane};
    auto Warm = ck::astar::TSearchState<int32, FGoalDirectedEqualFLaneGraph>{
        FGoalDirectedEqualFLaneGraph{}, FEqualFLaneGraphBase::Start, FEqualFLaneGraphBase::Goal,
        WarmPrefix, WarmPrefix.Num()};
    if (NOT TestEqual(TEXT("the warm-start constructor opens one prefix endpoint"), Warm.GetOpenSetSize(), 1))
    {
        return false;
    }
    TestEqual(TEXT("the warm-start entry receives the graph tie score"),
        Warm.GetOpenSet()[0].TieBreakScore, 5.0f);
    while (Warm.ContinueSearch({}) == ck::astar::ESearchStatus::InProgress)
    {
    }
    TestEqual(TEXT("the warm-start search completes"), Warm.GetStatus(), ck::astar::ESearchStatus::Complete);
    TestEqual(TEXT("the warm-start search retains the optimal cost"), Warm.GetResultCost(), 10.0f);

    const auto CheaperPrimary = Solve(
        FCheaperPrimaryGraph{}, FCheaperPrimaryGraph::Start, FCheaperPrimaryGraph::CheaperGoal);
    TestEqual(TEXT("the cheaper primary-F graph completes"),
        CheaperPrimary.GetStatus(), ck::astar::ESearchStatus::Complete);
    TestEqual(TEXT("a lower FScore wins before the secondary score"), CheaperPrimary.GetResultCost(), 1.0f);
    TestTrue(TEXT("the lower-F path is selected despite its worse tie score"),
        CheaperPrimary.GetResultPath() == TArray<int32>{FCheaperPrimaryGraph::Start, FCheaperPrimaryGraph::CheaperGoal});

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
