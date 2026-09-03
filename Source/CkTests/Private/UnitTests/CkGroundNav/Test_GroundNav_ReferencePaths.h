#pragma once

// An exact Euclidean shortest path over the ground storey, built from the field's own boundary runs
// and solved with Dijkstra over a visibility graph.
//
// Held here rather than inside one test because two suites need the same independent answer: the flood
// fill's distances are checked against it, and so are the walked distances the path-distance point
// generator draws points by. It shares no code and no idea with either — one walks portals and
// string-pulls, the other draws every corner-to-corner line the geometry admits — so a propagation bug
// in either shows up as a disagreement instead of as two matching wrong numbers, and a second copy of
// the construction would be a second thing to keep honest.
//
// Every function is inline and lives in a named namespace, for the reason the query fixtures give: the
// including .cpp files land in the same unity blob, where a non-inline definition or an anonymous
// namespace would collide.

#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Projection.h"

#include "Test_GroundNav_QueryFixtures.h"

#include <CoreMinimal.h>

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_groundnav_referencepaths
{
    using ck::groundnav::FCk_GroundNav_BoundarySegment;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_IsNavigableQuery;
    using ck::groundnav::Get_IsNavigable;

    using ck_test_groundnav_queryfixtures::kGroundZ;
    using ck_test_groundnav_queryfixtures::kStepHeight;

    // The deck sits 260 uu up, so anything at or under this height is the ground storey and nothing
    // else is. The reference construction is stated on that storey alone.
    inline constexpr auto kGroundStoreyMaxZ = 50.0;

    inline constexpr auto kEpsilon = 1.0e-3;

    // Corners shared by two runs arrive twice, at bit-identical coordinates; this welds them without
    // ever merging two corners the lattice actually keeps apart (the nearest are a cell size apart).
    inline constexpr auto kNodeWeldUu = 1.0e-3;

    // ----------------------------------------------------------------------------------------------------------------

    inline auto Get_XY(
        const FVector& InLocation) -> FVector2D
    {
        return FVector2D{InLocation.X, InLocation.Y};
    }

    // ----------------------------------------------------------------------------------------------------------------

    struct FGroundRun
    {
        FVector2D _Start = FVector2D::ZeroVector;
        FVector2D _End = FVector2D::ZeroVector;
    };

    struct FVisibilityGraph
    {
        // Every wall, drop and rim of the source's own component on the ground storey.
        TArray<FGroundRun> _Runs;

        // The source, then every run endpoint. A target is appended per query.
        TArray<FVector2D> _Nodes;

        TArray<TArray<int32>> _Adjacency;
    };

    /** Perpendicular distance from a point to the infinite line through a segment, signed by which side. */
    inline auto Get_SignedDistanceToLine(
        const FVector2D& InFrom,
        const FVector2D& InTo,
        const FVector2D& InPoint) -> double
    {
        const auto Along = InTo - InFrom;
        const auto Length = Along.Size();

        if (Length <= kNodeWeldUu)
        { return FVector2D::Distance(InFrom, InPoint); }

        return ((Along.X * (InPoint.Y - InFrom.Y)) - (Along.Y * (InPoint.X - InFrom.X))) / Length;
    }

    inline auto Get_Side(
        double InSignedDistance) -> int32
    {
        if (InSignedDistance > kEpsilon)
        { return 1; }

        if (InSignedDistance < -kEpsilon)
        { return -1; }

        return 0;
    }

    /**
     * Whether two segments cross each other's interiors.
     *
     * Touching at an endpoint and lying collinear both count as NOT crossing: a shortest path is allowed
     * to bend on a corner and to run flush along a wall face, and a test that called either a collision
     * would reject the very edges the reference needs.
     */
    inline auto Get_SegmentsProperlyIntersect(
        const FVector2D& InLeftFrom,
        const FVector2D& InLeftTo,
        const FVector2D& InRightFrom,
        const FVector2D& InRightTo) -> bool
    {
        const auto LeftFromSide = Get_Side(Get_SignedDistanceToLine(InRightFrom, InRightTo, InLeftFrom));
        const auto LeftToSide = Get_Side(Get_SignedDistanceToLine(InRightFrom, InRightTo, InLeftTo));
        const auto RightFromSide = Get_Side(Get_SignedDistanceToLine(InLeftFrom, InLeftTo, InRightFrom));
        const auto RightToSide = Get_Side(Get_SignedDistanceToLine(InLeftFrom, InLeftTo, InRightTo));

        return (LeftFromSide * LeftToSide) < 0 && (RightFromSide * RightToSide) < 0;
    }

    inline auto Do_CollectGroundRuns(
        const FCk_GroundNav_Field& InField,
        int32                      InLabel,
        TArray<FGroundRun>&        OutRuns) -> void
    {
        const auto Do_Consider = [&](int32 InTileIndex, const FCk_GroundNav_BoundarySegment& InSegment) -> void
        {
            if (InSegment._Start.Z > kGroundStoreyMaxZ)
            { return; }

            if (InField.Get_ReachabilityLabel(InTileIndex, InSegment._PlateIndex) != InLabel)
            { return; }

            auto Run = FGroundRun{};

            Run._Start = Get_XY(InSegment._Start);
            Run._End = Get_XY(InSegment._End);

            OutRuns.Emplace(Run);
        };

        for (auto TileIndex = 0; TileIndex < InField._Tiles.Num(); ++TileIndex)
        {
            if (NOT InField._Tiles[TileIndex].Get_IsBuilt())
            { continue; }

            for (const auto& Segment : InField._Tiles[TileIndex]._Boundary._Segments)
            { Do_Consider(TileIndex, Segment); }

            for (const auto& Segment : InField.Get_TileEdgeBoundary(TileIndex))
            { Do_Consider(TileIndex, Segment); }
        }
    }

    inline auto Do_AddNode(
        TArray<FVector2D>& InOutNodes,
        const FVector2D&   InPoint) -> void
    {
        for (const auto& Node : InOutNodes)
        {
            if (FVector2D::Distance(Node, InPoint) <= kNodeWeldUu)
            { return; }
        }

        InOutNodes.Emplace(InPoint);
    }

    /**
     * Whether the open segment between two nodes is a path the ground actually offers.
     *
     * Two independent refusals, and both are needed. The crossing test rejects an edge that cuts through
     * a wall or over the rim of a hole; the midpoint check rejects an edge that threads BETWEEN two runs
     * without touching either — the strip of ground under a wall's own footprint is exactly that shape,
     * bounded by the wall's two faces and crossed by neither.
     */
    inline auto Get_EdgeIsAdmitted(
        const FCk_GroundNav_Field& InField,
        const TArray<FGroundRun>&  InRuns,
        const FVector2D&           InFrom,
        const FVector2D&           InTo) -> bool
    {
        if (FVector2D::Distance(InFrom, InTo) <= kNodeWeldUu)
        { return false; }

        for (const auto& Run : InRuns)
        {
            if (Get_SegmentsProperlyIntersect(InFrom, InTo, Run._Start, Run._End))
            { return false; }
        }

        const auto Midpoint = (InFrom + InTo) * 0.5;

        auto Query = FCk_GroundNav_IsNavigableQuery{};

        Query._Location = FVector{Midpoint.X, Midpoint.Y, kGroundZ};
        Query._VerticalToleranceUu = kStepHeight;

        const auto Result = Get_IsNavigable(InField, Query);

        return Result.Get_IsSuccess() && static_cast<double>(Result._SurfaceZUu) <= kGroundStoreyMaxZ;
    }

    inline auto Make_VisibilityGraph(
        const FCk_GroundNav_Field& InField,
        int32                      InLabel,
        const FVector2D&           InSource) -> FVisibilityGraph
    {
        auto Graph = FVisibilityGraph{};

        Do_CollectGroundRuns(InField, InLabel, Graph._Runs);

        Graph._Nodes.Emplace(InSource);

        for (const auto& Run : Graph._Runs)
        {
            Do_AddNode(Graph._Nodes, Run._Start);
            Do_AddNode(Graph._Nodes, Run._End);
        }

        Graph._Adjacency.SetNum(Graph._Nodes.Num());

        for (auto Left = 0; Left < Graph._Nodes.Num(); ++Left)
        {
            for (auto Right = Left + 1; Right < Graph._Nodes.Num(); ++Right)
            {
                if (NOT Get_EdgeIsAdmitted(InField, Graph._Runs, Graph._Nodes[Left], Graph._Nodes[Right]))
                { continue; }

                Graph._Adjacency[Left].Emplace(Right);
                Graph._Adjacency[Right].Emplace(Left);
            }
        }

        return Graph;
    }

    /** Dijkstra from the graph's source (node zero) to a target appended for this query alone. */
    inline auto Get_ReferenceDistance(
        const FCk_GroundNav_Field& InField,
        const FVisibilityGraph&    InGraph,
        const FVector2D&           InTarget) -> TOptional<double>
    {
        const auto StaticCount = InGraph._Nodes.Num();
        const auto TargetIndex = StaticCount;
        const auto NodeCount = StaticCount + 1;

        auto TargetEdges = TArray<int32>{};

        for (auto Index = 0; Index < StaticCount; ++Index)
        {
            if (Get_EdgeIsAdmitted(InField, InGraph._Runs, InGraph._Nodes[Index], InTarget))
            { TargetEdges.Emplace(Index); }
        }

        auto Distances = TArray<double>{};
        Distances.Init(TNumericLimits<double>::Max(), NodeCount);

        auto Settled = TArray<bool>{};
        Settled.Init(false, NodeCount);

        Distances[0] = 0.0;

        const auto Get_Position = [&](int32 InIndex) -> FVector2D
        {
            return InIndex == TargetIndex ? InTarget : InGraph._Nodes[InIndex];
        };

        for (auto Step = 0; Step < NodeCount; ++Step)
        {
            int32 Best = INDEX_NONE;
            auto BestDistance = TNumericLimits<double>::Max();

            for (auto Index = 0; Index < NodeCount; ++Index)
            {
                if (Settled[Index])
                { continue; }

                if (Distances[Index] < BestDistance)
                {
                    BestDistance = Distances[Index];
                    Best = Index;
                }
            }

            if (Best == INDEX_NONE)
            { break; }

            Settled[Best] = true;

            const auto Do_Relax = [&](int32 InNeighbour) -> void
            {
                const auto Candidate =
                    BestDistance + FVector2D::Distance(Get_Position(Best), Get_Position(InNeighbour));

                if (Candidate < Distances[InNeighbour])
                { Distances[InNeighbour] = Candidate; }
            };

            if (Best == TargetIndex)
            {
                for (const auto Neighbour : TargetEdges)
                { Do_Relax(Neighbour); }

                continue;
            }

            for (const auto Neighbour : InGraph._Adjacency[Best])
            { Do_Relax(Neighbour); }

            if (TargetEdges.Contains(Best))
            { Do_Relax(TargetIndex); }
        }

        if (Distances[TargetIndex] >= TNumericLimits<double>::Max())
        { return {}; }

        return Distances[TargetIndex];
    }
}

// --------------------------------------------------------------------------------------------------------------------
