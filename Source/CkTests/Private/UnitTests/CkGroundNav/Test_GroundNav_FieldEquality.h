#pragma once

#include "CkGroundNav/Field/CkGroundNav_Field.h"

#include <CoreMinimal.h>

// --------------------------------------------------------------------------------------------------------------------
//
// Field/tile equality for the GroundNav bake tests, shared by every fixture that pins byte-identical
// output. Written out member by member rather than memcmp'd or relying on a struct's own operator==:
// these structures carry doubles beside int32s, so they have padding a byte compare would read, and
// padding is not a value anything set.
//
// `inline` throughout: CkTests is a unity build, so a plain free function defined in a header included
// by more than one translation unit of the same blob would violate ODR.

namespace ck_test_groundnav_field_equality
{
    enum class EPolicyComparison
    {
        // Everything, the cost labelling included.
        Include,

        // Everything a cost-only derive is forbidden to touch. What is left out is exactly what such a
        // derive is allowed to change, so a derive that moved anything else fails this.
        Ignore
    };

    // Excluded by default: epochs are the one thing a rebuild and a derive are SUPPOSED to move, so a
    // byte-identity pin compares everything else; Include is for pins that assert the stamps themselves.
    enum class EEpochComparison
    {
        Exclude,

        // For pins that want the stricter, byte-identical-including-epochs form.
        Include
    };

    // ---- Generic array equality ------------------------------------------------------------------------

    template <typename T, typename T_Predicate>
    inline auto Get_ArraysEqual(
        const TArray<T>& InLhs,
        const TArray<T>& InRhs,
        T_Predicate      InPredicate) -> bool
    {
        if (InLhs.Num() != InRhs.Num())
        { return false; }

        for (auto Index = 0; Index < InLhs.Num(); ++Index)
        {
            if (NOT InPredicate(InLhs[Index], InRhs[Index]))
            { return false; }
        }

        return true;
    }

    template <typename T>
    inline auto Get_ValueArraysEqual(
        const TArray<T>& InLhs,
        const TArray<T>& InRhs) -> bool
    {
        return Get_ArraysEqual(InLhs, InRhs, [](const T& InA, const T& InB) -> bool { return InA == InB; });
    }

    inline auto Get_NestedIndexArraysEqual(
        const TArray<TArray<int32>>& InLhs,
        const TArray<TArray<int32>>& InRhs) -> bool
    {
        return Get_ArraysEqual(InLhs, InRhs,
            [](const TArray<int32>& InA, const TArray<int32>& InB) -> bool
            {
                return Get_ValueArraysEqual(InA, InB);
            });
    }

    // ---- Generic array diagnostics -----------------------------------------------------------------------
    //
    // The diff-returning twins of the equality helpers above: empty string means equal, otherwise a
    // fragment naming where the mismatch starts, meant to be appended onto the caller's own member name.

    template <typename T, typename T_ElementDiff>
    inline auto Get_FirstArrayDifference(
        const TArray<T>& InLhs,
        const TArray<T>& InRhs,
        T_ElementDiff    InElementDiff) -> FString
    {
        if (InLhs.Num() != InRhs.Num())
        { return FString::Printf(TEXT(" count %d vs %d"), InLhs.Num(), InRhs.Num()); }

        for (auto Index = 0; Index < InLhs.Num(); ++Index)
        {
            const auto ElementDiff = InElementDiff(InLhs[Index], InRhs[Index]);

            if (NOT ElementDiff.IsEmpty())
            { return FString::Printf(TEXT("[%d]%s"), Index, *ElementDiff); }
        }

        return {};
    }

    template <typename T>
    inline auto Get_FirstValueArrayDifference(
        const TArray<T>& InLhs,
        const TArray<T>& InRhs) -> FString
    {
        return Get_FirstArrayDifference(InLhs, InRhs,
            [](const T& InElementLhs, const T& InElementRhs) -> FString
            {
                return InElementLhs == InElementRhs ? FString{} : FString{TEXT(" differs")};
            });
    }

    inline auto Get_FirstNestedIndexArrayDifference(
        const TArray<TArray<int32>>& InLhs,
        const TArray<TArray<int32>>& InRhs) -> FString
    {
        return Get_FirstArrayDifference(InLhs, InRhs,
            [](const TArray<int32>& InElementLhs, const TArray<int32>& InElementRhs) -> FString
            {
                return Get_FirstValueArrayDifference(InElementLhs, InElementRhs);
            });
    }

    // ---- Per-element diagnostics and the equality checks built on them ------------------------------------

    inline auto Get_FirstPlateDifference(
        const ck::groundnav::FCk_GroundNav_Plate& InLhs,
        const ck::groundnav::FCk_GroundNav_Plate& InRhs,
        EPolicyComparison                         InPolicy) -> FString
    {
        if (InLhs._LayerIndex != InRhs._LayerIndex)
        { return TEXT("._LayerIndex differs"); }

        if (InLhs._MinX != InRhs._MinX)
        { return TEXT("._MinX differs"); }

        if (InLhs._MinY != InRhs._MinY)
        { return TEXT("._MinY differs"); }

        if (InLhs._MaxX != InRhs._MaxX)
        { return TEXT("._MaxX differs"); }

        if (InLhs._MaxY != InRhs._MaxY)
        { return TEXT("._MaxY differs"); }

        if (InLhs._MaxPlaneResidualUu != InRhs._MaxPlaneResidualUu)
        { return TEXT("._MaxPlaneResidualUu differs"); }

        if (InLhs._HeightRangeUu != InRhs._HeightRangeUu)
        { return TEXT("._HeightRangeUu differs"); }

        if (InLhs._MinClearanceUu != InRhs._MinClearanceUu)
        { return TEXT("._MinClearanceUu differs"); }

        if (InPolicy == EPolicyComparison::Ignore)
        { return {}; }

        if (InLhs._AreaPolicyIndex != InRhs._AreaPolicyIndex)
        { return TEXT("._AreaPolicyIndex differs"); }

        if (InLhs._CostMultiplier != InRhs._CostMultiplier)
        { return TEXT("._CostMultiplier differs"); }

        return {};
    }

    inline auto Get_PlatesEqual(
        const ck::groundnav::FCk_GroundNav_Plate& InLhs,
        const ck::groundnav::FCk_GroundNav_Plate& InRhs,
        EPolicyComparison                         InPolicy) -> bool
    {
        return Get_FirstPlateDifference(InLhs, InRhs, InPolicy).IsEmpty();
    }

    inline auto Get_FirstPortalDifference(
        const ck::groundnav::FCk_GroundNav_Portal& InLhs,
        const ck::groundnav::FCk_GroundNav_Portal& InRhs) -> FString
    {
        if (InLhs._PlateA != InRhs._PlateA)
        { return TEXT("._PlateA differs"); }

        if (InLhs._PlateB != InRhs._PlateB)
        { return TEXT("._PlateB differs"); }

        if (InLhs._Direction != InRhs._Direction)
        { return TEXT("._Direction differs"); }

        if (InLhs._FromMin != InRhs._FromMin)
        { return TEXT("._FromMin differs"); }

        if (InLhs._FromMax != InRhs._FromMax)
        { return TEXT("._FromMax differs"); }

        if (InLhs._MinEndZUu != InRhs._MinEndZUu)
        { return TEXT("._MinEndZUu differs"); }

        if (InLhs._MaxEndZUu != InRhs._MaxEndZUu)
        { return TEXT("._MaxEndZUu differs"); }

        if (InLhs._TraversalClearanceUu != InRhs._TraversalClearanceUu)
        { return TEXT("._TraversalClearanceUu differs"); }

        return {};
    }

    inline auto Get_PortalsEqual(
        const ck::groundnav::FCk_GroundNav_Portal& InLhs,
        const ck::groundnav::FCk_GroundNav_Portal& InRhs) -> bool
    {
        return Get_FirstPortalDifference(InLhs, InRhs).IsEmpty();
    }

    inline auto Get_FirstSegmentDifference(
        const ck::groundnav::FCk_GroundNav_BoundarySegment& InLhs,
        const ck::groundnav::FCk_GroundNav_BoundarySegment& InRhs) -> FString
    {
        if (InLhs._PlateIndex != InRhs._PlateIndex)
        { return TEXT("._PlateIndex differs"); }

        if (InLhs._LayerIndex != InRhs._LayerIndex)
        { return TEXT("._LayerIndex differs"); }

        if (InLhs._Side != InRhs._Side)
        { return TEXT("._Side differs"); }

        if (InLhs._FromCell != InRhs._FromCell)
        { return TEXT("._FromCell differs"); }

        if (InLhs._ToCell != InRhs._ToCell)
        { return TEXT("._ToCell differs"); }

        if (InLhs._Start != InRhs._Start)
        { return TEXT("._Start differs"); }

        if (InLhs._End != InRhs._End)
        { return TEXT("._End differs"); }

        if (InLhs._InwardNormalXY != InRhs._InwardNormalXY)
        { return TEXT("._InwardNormalXY differs"); }

        return {};
    }

    inline auto Get_SegmentsEqual(
        const ck::groundnav::FCk_GroundNav_BoundarySegment& InLhs,
        const ck::groundnav::FCk_GroundNav_BoundarySegment& InRhs) -> bool
    {
        return Get_FirstSegmentDifference(InLhs, InRhs).IsEmpty();
    }

    inline auto Get_FirstStubDifference(
        const ck::groundnav::FCk_GroundNav_SeamStub& InLhs,
        const ck::groundnav::FCk_GroundNav_SeamStub& InRhs) -> FString
    {
        if (InLhs._Direction != InRhs._Direction)
        { return TEXT("._Direction differs"); }

        if (InLhs._AlongIndex != InRhs._AlongIndex)
        { return TEXT("._AlongIndex differs"); }

        if (InLhs._PlateIndex != InRhs._PlateIndex)
        { return TEXT("._PlateIndex differs"); }

        if (InLhs._NearSurfaceZUu != InRhs._NearSurfaceZUu)
        { return TEXT("._NearSurfaceZUu differs"); }

        if (InLhs._FarSurfaceZUu != InRhs._FarSurfaceZUu)
        { return TEXT("._FarSurfaceZUu differs"); }

        if (InLhs._ClearanceUu != InRhs._ClearanceUu)
        { return TEXT("._ClearanceUu differs"); }

        return {};
    }

    inline auto Get_StubsEqual(
        const ck::groundnav::FCk_GroundNav_SeamStub& InLhs,
        const ck::groundnav::FCk_GroundNav_SeamStub& InRhs) -> bool
    {
        return Get_FirstStubDifference(InLhs, InRhs).IsEmpty();
    }

    inline auto Get_FirstSeamPortalDifference(
        const ck::groundnav::FCk_GroundNav_SeamPortal& InLhs,
        const ck::groundnav::FCk_GroundNav_SeamPortal& InRhs) -> FString
    {
        if (InLhs._TileIndexA != InRhs._TileIndexA)
        { return TEXT("._TileIndexA differs"); }

        if (InLhs._TileIndexB != InRhs._TileIndexB)
        { return TEXT("._TileIndexB differs"); }

        if (InLhs._PlateA != InRhs._PlateA)
        { return TEXT("._PlateA differs"); }

        if (InLhs._PlateB != InRhs._PlateB)
        { return TEXT("._PlateB differs"); }

        if (InLhs._Direction != InRhs._Direction)
        { return TEXT("._Direction differs"); }

        if (InLhs._AlongMin != InRhs._AlongMin)
        { return TEXT("._AlongMin differs"); }

        if (InLhs._AlongMax != InRhs._AlongMax)
        { return TEXT("._AlongMax differs"); }

        if (InLhs._MinEndZUu != InRhs._MinEndZUu)
        { return TEXT("._MinEndZUu differs"); }

        if (InLhs._MaxEndZUu != InRhs._MaxEndZUu)
        { return TEXT("._MaxEndZUu differs"); }

        if (InLhs._TraversalClearanceUu != InRhs._TraversalClearanceUu)
        { return TEXT("._TraversalClearanceUu differs"); }

        return {};
    }

    inline auto Get_SeamPortalsEqual(
        const ck::groundnav::FCk_GroundNav_SeamPortal& InLhs,
        const ck::groundnav::FCk_GroundNav_SeamPortal& InRhs) -> bool
    {
        return Get_FirstSeamPortalDifference(InLhs, InRhs).IsEmpty();
    }

    inline auto Get_FirstSurfaceRefDifference(
        const ck::groundnav::FCk_GroundNav_SurfaceRef& InLhs,
        const ck::groundnav::FCk_GroundNav_SurfaceRef& InRhs) -> FString
    {
        if (InLhs._TileIndex != InRhs._TileIndex)
        { return TEXT("._TileIndex differs"); }

        if (InLhs._LayerIndex != InRhs._LayerIndex)
        { return TEXT("._LayerIndex differs"); }

        if (InLhs._CellX != InRhs._CellX)
        { return TEXT("._CellX differs"); }

        if (InLhs._CellY != InRhs._CellY)
        { return TEXT("._CellY differs"); }

        if (InLhs._PlateIndex != InRhs._PlateIndex)
        { return TEXT("._PlateIndex differs"); }

        return {};
    }

    inline auto Get_FirstResolvedLinkDifference(
        const ck::groundnav::FCk_GroundNav_ResolvedLink& InLhs,
        const ck::groundnav::FCk_GroundNav_ResolvedLink& InRhs) -> FString
    {
        if (InLhs._Id != InRhs._Id)
        { return TEXT("._Id differs"); }

        if (InLhs._Start != InRhs._Start)
        { return TEXT("._Start differs"); }

        if (InLhs._End != InRhs._End)
        { return TEXT("._End differs"); }

        const auto StartSurfaceDiff = Get_FirstSurfaceRefDifference(InLhs._StartSurface, InRhs._StartSurface);

        if (NOT StartSurfaceDiff.IsEmpty())
        { return FString::Printf(TEXT("._StartSurface%s"), *StartSurfaceDiff); }

        const auto EndSurfaceDiff = Get_FirstSurfaceRefDifference(InLhs._EndSurface, InRhs._EndSurface);

        if (NOT EndSurfaceDiff.IsEmpty())
        { return FString::Printf(TEXT("._EndSurface%s"), *EndSurfaceDiff); }

        if (InLhs._StartFlatPlate != InRhs._StartFlatPlate)
        { return TEXT("._StartFlatPlate differs"); }

        if (InLhs._EndFlatPlate != InRhs._EndFlatPlate)
        { return TEXT("._EndFlatPlate differs"); }

        if (InLhs._StartStatus != InRhs._StartStatus)
        { return TEXT("._StartStatus differs"); }

        if (InLhs._EndStatus != InRhs._EndStatus)
        { return TEXT("._EndStatus differs"); }

        if (InLhs._Direction != InRhs._Direction)
        { return TEXT("._Direction differs"); }

        if (InLhs._CostMultiplierForward != InRhs._CostMultiplierForward)
        { return TEXT("._CostMultiplierForward differs"); }

        if (InLhs._CostMultiplierBackward != InRhs._CostMultiplierBackward)
        { return TEXT("._CostMultiplierBackward differs"); }

        if (InLhs._ClearanceUu != InRhs._ClearanceUu)
        { return TEXT("._ClearanceUu differs"); }

        if (InLhs._AreaTag != InRhs._AreaTag)
        { return TEXT("._AreaTag differs"); }

        if (InLhs._UserTypeTag != InRhs._UserTypeTag)
        { return TEXT("._UserTypeTag differs"); }

        if (InLhs._Enable != InRhs._Enable)
        { return TEXT("._Enable differs"); }

        return {};
    }

    inline auto Get_ResolvedLinksEqual(
        const ck::groundnav::FCk_GroundNav_ResolvedLink& InLhs,
        const ck::groundnav::FCk_GroundNav_ResolvedLink& InRhs) -> bool
    {
        return Get_FirstResolvedLinkDifference(InLhs, InRhs).IsEmpty();
    }

    inline auto Get_FirstOpenBodyDifference(
        const ck::groundnav::FCk_GroundNav_OpenBody& InLhs,
        const ck::groundnav::FCk_GroundNav_OpenBody& InRhs) -> FString
    {
        if (InLhs._Body != InRhs._Body)
        { return TEXT("._Body differs"); }

        if (NOT InLhs._Description.Equals(InRhs._Description, ESearchCase::CaseSensitive))
        { return TEXT("._Description differs"); }

        if (InLhs._Bounds.Min != InRhs._Bounds.Min)
        { return TEXT("._Bounds.Min differs"); }

        if (InLhs._Bounds.Max != InRhs._Bounds.Max)
        { return TEXT("._Bounds.Max differs"); }

        if (InLhs._Bounds.IsValid != InRhs._Bounds.IsValid)
        { return TEXT("._Bounds.IsValid differs"); }

        if (InLhs._TriangleCount != InRhs._TriangleCount)
        { return TEXT("._TriangleCount differs"); }

        if (InLhs._OpenEdgeCount != InRhs._OpenEdgeCount)
        { return TEXT("._OpenEdgeCount differs"); }

        const auto EdgePointsDiff = Get_FirstValueArrayDifference(InLhs._OpenEdgePoints, InRhs._OpenEdgePoints);

        if (NOT EdgePointsDiff.IsEmpty())
        { return FString::Printf(TEXT("._OpenEdgePoints%s"), *EdgePointsDiff); }

        return {};
    }

    inline auto Get_OpenBodiesEqual(
        const ck::groundnav::FCk_GroundNav_OpenBody& InLhs,
        const ck::groundnav::FCk_GroundNav_OpenBody& InRhs) -> bool
    {
        return Get_FirstOpenBodyDifference(InLhs, InRhs).IsEmpty();
    }

    // ---- Tile equality ------------------------------------------------------------------------------------

    inline auto Get_FirstTileDifference(
        int32                                      InTileIndex,
        const ck::groundnav::FCk_GroundNav_Tile&  InLhs,
        const ck::groundnav::FCk_GroundNav_Tile&  InRhs,
        EPolicyComparison                         InPolicy,
        EEpochComparison                          InEpochMode) -> FString
    {
        const auto MakeMessage = [InTileIndex](const TCHAR* InMember) -> FString
        {
            return FString::Printf(TEXT("Tile %d: %s"), InTileIndex, InMember);
        };

        if (InLhs._Coord != InRhs._Coord)
        { return MakeMessage(TEXT("_Coord differs")); }

        if (InLhs._Status != InRhs._Status)
        { return MakeMessage(TEXT("_Status differs")); }

        if (InLhs._Origin != InRhs._Origin)
        { return MakeMessage(TEXT("_Origin differs")); }

        if (InLhs._CellSizeUu != InRhs._CellSizeUu)
        { return MakeMessage(TEXT("_CellSizeUu differs")); }

        if (InLhs._MaxClearanceUu != InRhs._MaxClearanceUu)
        { return MakeMessage(TEXT("_MaxClearanceUu differs")); }

        if (InLhs._SizeX != InRhs._SizeX)
        { return MakeMessage(TEXT("_SizeX differs")); }

        if (InLhs._SizeY != InRhs._SizeY)
        { return MakeMessage(TEXT("_SizeY differs")); }

        if (InLhs._LayerCount != InRhs._LayerCount)
        { return MakeMessage(TEXT("_LayerCount differs")); }

        if (InEpochMode == EEpochComparison::Include && NOT (InLhs._Epoch == InRhs._Epoch))
        { return MakeMessage(TEXT("_Epoch differs")); }

        if (InLhs._BakeStats._SourceTriangleCount != InRhs._BakeStats._SourceTriangleCount)
        { return MakeMessage(TEXT("_BakeStats._SourceTriangleCount differs")); }

        if (InLhs._BakeStats._RasterizedSpanCount != InRhs._BakeStats._RasterizedSpanCount)
        { return MakeMessage(TEXT("_BakeStats._RasterizedSpanCount differs")); }

        if (InLhs._BakeStats._RejectedCellCount != InRhs._BakeStats._RejectedCellCount)
        { return MakeMessage(TEXT("_BakeStats._RejectedCellCount differs")); }

        const auto SurfaceZDiff = Get_FirstValueArrayDifference(InLhs._SurfaceZ, InRhs._SurfaceZ);

        if (NOT SurfaceZDiff.IsEmpty())
        { return MakeMessage(*FString::Printf(TEXT("_SurfaceZ%s"), *SurfaceZDiff)); }

        if (InLhs._Clearance._SizeX != InRhs._Clearance._SizeX)
        { return MakeMessage(TEXT("_Clearance._SizeX differs")); }

        if (InLhs._Clearance._SizeY != InRhs._Clearance._SizeY)
        { return MakeMessage(TEXT("_Clearance._SizeY differs")); }

        if (InLhs._Clearance._LayerCount != InRhs._Clearance._LayerCount)
        { return MakeMessage(TEXT("_Clearance._LayerCount differs")); }

        if (InLhs._Clearance._CellSizeUu != InRhs._Clearance._CellSizeUu)
        { return MakeMessage(TEXT("_Clearance._CellSizeUu differs")); }

        const auto ClearanceCellsDiff = Get_FirstValueArrayDifference(InLhs._Clearance._Cells, InRhs._Clearance._Cells);

        if (NOT ClearanceCellsDiff.IsEmpty())
        { return MakeMessage(*FString::Printf(TEXT("_Clearance._Cells%s"), *ClearanceCellsDiff)); }

        if (InLhs._Plates._SizeX != InRhs._Plates._SizeX)
        { return MakeMessage(TEXT("_Plates._SizeX differs")); }

        if (InLhs._Plates._SizeY != InRhs._Plates._SizeY)
        { return MakeMessage(TEXT("_Plates._SizeY differs")); }

        if (InLhs._Plates._LayerCount != InRhs._Plates._LayerCount)
        { return MakeMessage(TEXT("_Plates._LayerCount differs")); }

        const auto PlatesDiff = Get_FirstArrayDifference(InLhs._Plates._Plates, InRhs._Plates._Plates,
            [InPolicy](const ck::groundnav::FCk_GroundNav_Plate& InElementLhs,
                       const ck::groundnav::FCk_GroundNav_Plate& InElementRhs) -> FString
            {
                return Get_FirstPlateDifference(InElementLhs, InElementRhs, InPolicy);
            });

        if (NOT PlatesDiff.IsEmpty())
        { return MakeMessage(*FString::Printf(TEXT("_Plates._Plates%s"), *PlatesDiff)); }

        const auto CellToPlateDiff = Get_FirstValueArrayDifference(InLhs._Plates._CellToPlate, InRhs._Plates._CellToPlate);

        if (NOT CellToPlateDiff.IsEmpty())
        { return MakeMessage(*FString::Printf(TEXT("_Plates._CellToPlate%s"), *CellToPlateDiff)); }

        if (InPolicy == EPolicyComparison::Include)
        {
            const auto AreaPoliciesDiff = Get_FirstValueArrayDifference(InLhs._Plates._AreaPolicies, InRhs._Plates._AreaPolicies);

            if (NOT AreaPoliciesDiff.IsEmpty())
            { return MakeMessage(*FString::Printf(TEXT("_Plates._AreaPolicies%s"), *AreaPoliciesDiff)); }
        }

        const auto PortalsDiff = Get_FirstArrayDifference(
            InLhs._Portals._Portals, InRhs._Portals._Portals, &Get_FirstPortalDifference);

        if (NOT PortalsDiff.IsEmpty())
        { return MakeMessage(*FString::Printf(TEXT("_Portals._Portals%s"), *PortalsDiff)); }

        const auto PlateToPortalsDiff = Get_FirstNestedIndexArrayDifference(
            InLhs._Portals._PlateToPortals, InRhs._Portals._PlateToPortals);

        if (NOT PlateToPortalsDiff.IsEmpty())
        { return MakeMessage(*FString::Printf(TEXT("_Portals._PlateToPortals%s"), *PlateToPortalsDiff)); }

        if (InLhs._Boundary._BucketsX != InRhs._Boundary._BucketsX)
        { return MakeMessage(TEXT("_Boundary._BucketsX differs")); }

        if (InLhs._Boundary._BucketsY != InRhs._Boundary._BucketsY)
        { return MakeMessage(TEXT("_Boundary._BucketsY differs")); }

        const auto SegmentsDiff = Get_FirstArrayDifference(
            InLhs._Boundary._Segments, InRhs._Boundary._Segments, &Get_FirstSegmentDifference);

        if (NOT SegmentsDiff.IsEmpty())
        { return MakeMessage(*FString::Printf(TEXT("_Boundary._Segments%s"), *SegmentsDiff)); }

        const auto EdgeCandidatesDiff = Get_FirstArrayDifference(
            InLhs._Boundary._EdgeCandidates, InRhs._Boundary._EdgeCandidates, &Get_FirstSegmentDifference);

        if (NOT EdgeCandidatesDiff.IsEmpty())
        { return MakeMessage(*FString::Printf(TEXT("_Boundary._EdgeCandidates%s"), *EdgeCandidatesDiff)); }

        const auto BucketsDiff = Get_FirstNestedIndexArrayDifference(InLhs._Boundary._Buckets, InRhs._Boundary._Buckets);

        if (NOT BucketsDiff.IsEmpty())
        { return MakeMessage(*FString::Printf(TEXT("_Boundary._Buckets%s"), *BucketsDiff)); }

        const auto SeamStubsDiff = Get_FirstArrayDifference(InLhs._SeamStubs, InRhs._SeamStubs, &Get_FirstStubDifference);

        if (NOT SeamStubsDiff.IsEmpty())
        { return MakeMessage(*FString::Printf(TEXT("_SeamStubs%s"), *SeamStubsDiff)); }

        return {};
    }

    inline auto Get_TilesEqual(
        const ck::groundnav::FCk_GroundNav_Tile& InLhs,
        const ck::groundnav::FCk_GroundNav_Tile& InRhs,
        EPolicyComparison                        InPolicy) -> bool
    {
        return Get_FirstTileDifference(0, InLhs, InRhs, InPolicy, EEpochComparison::Exclude).IsEmpty();
    }

    // ---- Params equality ------------------------------------------------------------------------------------
    //
    // The AUTHORED half of a field, which a round trip has to carry as faithfully as the bake product:
    // a field whose tiles match and whose params do not is a field that would bake differently next
    // time. Read through the getters because these are reflected types whose members are private, and
    // every tag is compared AS A TAG rather than through a hash - an FName's hash is an index into a
    // per-process table, so two hashes agreeing says nothing across a write and a read.

    inline auto Get_FirstShapeDifference(
        const FCk_AnyShape& InLhs,
        const FCk_AnyShape& InRhs) -> FString
    {
        if (InLhs.Get_ShapeType() != InRhs.Get_ShapeType())
        { return TEXT("._ShapeType differs"); }

        // Only the dimensions the type SELECTS. The other three are the shape's unused slots, and
        // nothing that reads the shape through its type can see them.
        switch (InLhs.Get_ShapeType())
        {
            case ECk_Shape_Type::Box:
            {
                if (InLhs.Get_Box().Get_HalfExtents() != InRhs.Get_Box().Get_HalfExtents())
                { return TEXT("._Box._HalfExtents differs"); }

                if (InLhs.Get_Box().Get_ConvexRadius() != InRhs.Get_Box().Get_ConvexRadius())
                { return TEXT("._Box._ConvexRadius differs"); }

                break;
            }
            case ECk_Shape_Type::Capsule:
            {
                if (InLhs.Get_Capsule().Get_HalfHeight() != InRhs.Get_Capsule().Get_HalfHeight())
                { return TEXT("._Capsule._HalfHeight differs"); }

                if (InLhs.Get_Capsule().Get_Radius() != InRhs.Get_Capsule().Get_Radius())
                { return TEXT("._Capsule._Radius differs"); }

                break;
            }
            case ECk_Shape_Type::Cylinder:
            {
                if (InLhs.Get_Cylinder().Get_HalfHeight() != InRhs.Get_Cylinder().Get_HalfHeight())
                { return TEXT("._Cylinder._HalfHeight differs"); }

                if (InLhs.Get_Cylinder().Get_Radius() != InRhs.Get_Cylinder().Get_Radius())
                { return TEXT("._Cylinder._Radius differs"); }

                if (InLhs.Get_Cylinder().Get_ConvexRadius() != InRhs.Get_Cylinder().Get_ConvexRadius())
                { return TEXT("._Cylinder._ConvexRadius differs"); }

                break;
            }
            case ECk_Shape_Type::Sphere:
            {
                if (InLhs.Get_Sphere().Get_Radius() != InRhs.Get_Sphere().Get_Radius())
                { return TEXT("._Sphere._Radius differs"); }

                break;
            }
            case ECk_Shape_Type::None:
            default:
            {
                break;
            }
        }

        return {};
    }

    inline auto Get_FirstTransformDifference(
        const FTransform& InLhs,
        const FTransform& InRhs) -> FString
    {
        constexpr auto ExactTolerance = 0.0;

        if (NOT InLhs.GetRotation().Equals(InRhs.GetRotation(), ExactTolerance))
        { return TEXT(".Rotation differs"); }

        if (InLhs.GetTranslation() != InRhs.GetTranslation())
        { return TEXT(".Translation differs"); }

        if (InLhs.GetScale3D() != InRhs.GetScale3D())
        { return TEXT(".Scale3D differs"); }

        return {};
    }

    inline auto Get_FirstBakeConfigDifference(
        const FCk_GroundNav_BakeConfig& InLhs,
        const FCk_GroundNav_BakeConfig& InRhs) -> FString
    {
        if (InLhs.Get_CellSizeUu() != InRhs.Get_CellSizeUu())
        { return TEXT("._CellSizeUu differs"); }

        if (InLhs.Get_CellHeightUu() != InRhs.Get_CellHeightUu())
        { return TEXT("._CellHeightUu differs"); }

        if (InLhs.Get_TileSizeUu() != InRhs.Get_TileSizeUu())
        { return TEXT("._TileSizeUu differs"); }

        if (InLhs.Get_MaxColumnsPerTile() != InRhs.Get_MaxColumnsPerTile())
        { return TEXT("._MaxColumnsPerTile differs"); }

        return {};
    }

    inline auto Get_FirstAgentProfileDifference(
        const FCk_GroundNav_AgentProfile& InLhs,
        const FCk_GroundNav_AgentProfile& InRhs) -> FString
    {
        const auto ExtentsDiff = Get_FirstShapeDifference(InLhs.Get_StandingExtents(), InRhs.Get_StandingExtents());

        if (NOT ExtentsDiff.IsEmpty())
        { return FString::Printf(TEXT("._StandingExtents%s"), *ExtentsDiff); }

        if (InLhs.Get_MaxSlopeDegrees() != InRhs.Get_MaxSlopeDegrees())
        { return TEXT("._MaxSlopeDegrees differs"); }

        if (InLhs.Get_MaxSlopeChangeDegrees() != InRhs.Get_MaxSlopeChangeDegrees())
        { return TEXT("._MaxSlopeChangeDegrees differs"); }

        if (InLhs.Get_StepHeightUu() != InRhs.Get_StepHeightUu())
        { return TEXT("._StepHeightUu differs"); }

        if (InLhs.Get_LedgeSensitivity() != InRhs.Get_LedgeSensitivity())
        { return TEXT("._LedgeSensitivity differs"); }

        if (InLhs.Get_RoughPerchToleranceUu() != InRhs.Get_RoughPerchToleranceUu())
        { return TEXT("._RoughPerchToleranceUu differs"); }

        return {};
    }

    inline auto Get_FirstMergeTunablesDifference(
        const FCk_GroundNav_MergeTunables& InLhs,
        const FCk_GroundNav_MergeTunables& InRhs) -> FString
    {
        if (InLhs.Get_PlaneFitToleranceUu() != InRhs.Get_PlaneFitToleranceUu())
        { return TEXT("._PlaneFitToleranceUu differs"); }

        if (InLhs.Get_NormalConeDegrees() != InRhs.Get_NormalConeDegrees())
        { return TEXT("._NormalConeDegrees differs"); }

        return {};
    }

    inline auto Get_FirstMarkupRecordDifference(
        const FCk_GroundNav_MarkupRecord& InLhs,
        const FCk_GroundNav_MarkupRecord& InRhs) -> FString
    {
        if (InLhs.Get_Id() != InRhs.Get_Id())
        { return TEXT("._Id differs"); }

        const auto ShapeDiff = Get_FirstShapeDifference(InLhs.Get_Shape(), InRhs.Get_Shape());

        if (NOT ShapeDiff.IsEmpty())
        { return FString::Printf(TEXT("._Shape%s"), *ShapeDiff); }

        const auto TransformDiff = Get_FirstTransformDifference(InLhs.Get_WorldTransform(), InRhs.Get_WorldTransform());

        if (NOT TransformDiff.IsEmpty())
        { return FString::Printf(TEXT("._WorldTransform%s"), *TransformDiff); }

        if (InLhs.Get_AreaTag() != InRhs.Get_AreaTag())
        { return TEXT("._AreaTag differs"); }

        if (InLhs.Get_Enable() != InRhs.Get_Enable())
        { return TEXT("._Enable differs"); }

        if (InLhs.Get_Kind() != InRhs.Get_Kind())
        { return TEXT("._Kind differs"); }

        if (InLhs.Get_CostMultiplier() != InRhs.Get_CostMultiplier())
        { return TEXT("._CostMultiplier differs"); }

        if (InLhs.Get_RequestedAtEpoch() != InRhs.Get_RequestedAtEpoch())
        { return TEXT("._RequestedAtEpoch differs"); }

        return {};
    }

    inline auto Get_FirstLinkRecordDifference(
        const FCk_GroundNav_LinkRecord& InLhs,
        const FCk_GroundNav_LinkRecord& InRhs) -> FString
    {
        if (InLhs.Get_Id() != InRhs.Get_Id())
        { return TEXT("._Id differs"); }

        if (InLhs.Get_Start() != InRhs.Get_Start())
        { return TEXT("._Start differs"); }

        if (InLhs.Get_End() != InRhs.Get_End())
        { return TEXT("._End differs"); }

        if (InLhs.Get_Direction() != InRhs.Get_Direction())
        { return TEXT("._Direction differs"); }

        if (InLhs.Get_CostMultiplierForward() != InRhs.Get_CostMultiplierForward())
        { return TEXT("._CostMultiplierForward differs"); }

        if (InLhs.Get_CostMultiplierBackward() != InRhs.Get_CostMultiplierBackward())
        { return TEXT("._CostMultiplierBackward differs"); }

        if (InLhs.Get_ClearanceUu() != InRhs.Get_ClearanceUu())
        { return TEXT("._ClearanceUu differs"); }

        if (InLhs.Get_AreaTag() != InRhs.Get_AreaTag())
        { return TEXT("._AreaTag differs"); }

        if (InLhs.Get_UserTypeTag() != InRhs.Get_UserTypeTag())
        { return TEXT("._UserTypeTag differs"); }

        if (InLhs.Get_Enable() != InRhs.Get_Enable())
        { return TEXT("._Enable differs"); }

        if (InLhs.Get_ProjectionMode() != InRhs.Get_ProjectionMode())
        { return TEXT("._ProjectionMode differs"); }

        if (InLhs.Get_ProjectionHorizontalExtentUu() != InRhs.Get_ProjectionHorizontalExtentUu())
        { return TEXT("._ProjectionHorizontalExtentUu differs"); }

        if (InLhs.Get_ProjectionVerticalExtentUu() != InRhs.Get_ProjectionVerticalExtentUu())
        { return TEXT("._ProjectionVerticalExtentUu differs"); }

        if (InLhs.Get_RequestedAtEpoch() != InRhs.Get_RequestedAtEpoch())
        { return TEXT("._RequestedAtEpoch differs"); }

        return {};
    }

    inline auto Get_FirstParamsDifference(
        const ck::groundnav::FCk_GroundNav_FieldParams& InLhs,
        const ck::groundnav::FCk_GroundNav_FieldParams& InRhs) -> FString
    {
        if (InLhs._OriginXY != InRhs._OriginXY)
        { return TEXT("_Params._OriginXY differs"); }

        if (InLhs._Divisions != InRhs._Divisions)
        { return TEXT("_Params._Divisions differs"); }

        if (InLhs._MinZUu != InRhs._MinZUu)
        { return TEXT("_Params._MinZUu differs"); }

        if (InLhs._MaxZUu != InRhs._MaxZUu)
        { return TEXT("_Params._MaxZUu differs"); }

        if (InLhs._MaxClearanceUu != InRhs._MaxClearanceUu)
        { return TEXT("_Params._MaxClearanceUu differs"); }

        const auto ConfigDiff = Get_FirstBakeConfigDifference(InLhs._Config, InRhs._Config);

        if (NOT ConfigDiff.IsEmpty())
        { return FString::Printf(TEXT("_Params._Config%s"), *ConfigDiff); }

        const auto ProfileDiff = Get_FirstAgentProfileDifference(InLhs._Profile, InRhs._Profile);

        if (NOT ProfileDiff.IsEmpty())
        { return FString::Printf(TEXT("_Params._Profile%s"), *ProfileDiff); }

        const auto TunablesDiff = Get_FirstMergeTunablesDifference(InLhs._MergeTunables, InRhs._MergeTunables);

        if (NOT TunablesDiff.IsEmpty())
        { return FString::Printf(TEXT("_Params._MergeTunables%s"), *TunablesDiff); }

        const auto MarkupDiff = Get_FirstArrayDifference(
            InLhs._MarkupRecords, InRhs._MarkupRecords, &Get_FirstMarkupRecordDifference);

        if (NOT MarkupDiff.IsEmpty())
        { return FString::Printf(TEXT("_Params._MarkupRecords%s"), *MarkupDiff); }

        const auto LinksDiff = Get_FirstArrayDifference(InLhs._Links, InRhs._Links, &Get_FirstLinkRecordDifference);

        if (NOT LinksDiff.IsEmpty())
        { return FString::Printf(TEXT("_Params._Links%s"), *LinksDiff); }

        return {};
    }

    inline auto Get_ParamsEqual(
        const ck::groundnav::FCk_GroundNav_FieldParams& InLhs,
        const ck::groundnav::FCk_GroundNav_FieldParams& InRhs) -> bool
    {
        return Get_FirstParamsDifference(InLhs, InRhs).IsEmpty();
    }

    // ---- Field equality -------------------------------------------------------------------------------------

    inline auto Get_FirstFieldDifference(
        const ck::groundnav::FCk_GroundNav_Field& InLhs,
        const ck::groundnav::FCk_GroundNav_Field& InRhs,
        EPolicyComparison                         InPolicy = EPolicyComparison::Include,
        EEpochComparison                          InEpochMode = EEpochComparison::Exclude) -> FString
    {
        if (InLhs._Tiles.Num() != InRhs._Tiles.Num())
        { return FString::Printf(TEXT("_Tiles count %d vs %d"), InLhs._Tiles.Num(), InRhs._Tiles.Num()); }

        for (auto TileIndex = 0; TileIndex < InLhs._Tiles.Num(); ++TileIndex)
        {
            const auto TileDiff = Get_FirstTileDifference(
                TileIndex, InLhs._Tiles[TileIndex], InRhs._Tiles[TileIndex], InPolicy, InEpochMode);

            if (NOT TileDiff.IsEmpty())
            { return TileDiff; }
        }

        if (InEpochMode == EEpochComparison::Include && NOT (InLhs._Epoch == InRhs._Epoch))
        { return TEXT("_Epoch differs"); }

        if (InLhs._UnmatchedSeamStubCount != InRhs._UnmatchedSeamStubCount)
        { return TEXT("_UnmatchedSeamStubCount differs"); }

        if (InLhs._UnresolvedLinkCount != InRhs._UnresolvedLinkCount)
        { return TEXT("_UnresolvedLinkCount differs"); }

        const auto SeamPortalsDiff = Get_FirstArrayDifference(
            InLhs._SeamPortals, InRhs._SeamPortals, &Get_FirstSeamPortalDifference);

        if (NOT SeamPortalsDiff.IsEmpty())
        { return FString::Printf(TEXT("_SeamPortals%s"), *SeamPortalsDiff); }

        const auto ResolvedLinksDiff = Get_FirstArrayDifference(
            InLhs._ResolvedLinks, InRhs._ResolvedLinks, &Get_FirstResolvedLinkDifference);

        if (NOT ResolvedLinksDiff.IsEmpty())
        { return FString::Printf(TEXT("_ResolvedLinks%s"), *ResolvedLinksDiff); }

        const auto TileEdgeBoundaryDiff = Get_FirstArrayDifference(InLhs._TileEdgeBoundary, InRhs._TileEdgeBoundary,
            [](const TArray<ck::groundnav::FCk_GroundNav_BoundarySegment>& InElementLhs,
               const TArray<ck::groundnav::FCk_GroundNav_BoundarySegment>& InElementRhs) -> FString
            {
                return Get_FirstArrayDifference(InElementLhs, InElementRhs, &Get_FirstSegmentDifference);
            });

        if (NOT TileEdgeBoundaryDiff.IsEmpty())
        { return FString::Printf(TEXT("_TileEdgeBoundary%s"), *TileEdgeBoundaryDiff); }

        const auto TilePlateOffsetsDiff = Get_FirstValueArrayDifference(InLhs._TilePlateOffsets, InRhs._TilePlateOffsets);

        if (NOT TilePlateOffsetsDiff.IsEmpty())
        { return FString::Printf(TEXT("_TilePlateOffsets%s"), *TilePlateOffsetsDiff); }

        const auto ReachabilityLabelsDiff = Get_FirstValueArrayDifference(
            InLhs._ReachabilityLabels, InRhs._ReachabilityLabels);

        if (NOT ReachabilityLabelsDiff.IsEmpty())
        { return FString::Printf(TEXT("_ReachabilityLabels%s"), *ReachabilityLabelsDiff); }

        const auto ComponentIsOpenDiff = Get_FirstValueArrayDifference(InLhs._ComponentIsOpen, InRhs._ComponentIsOpen);

        if (NOT ComponentIsOpenDiff.IsEmpty())
        { return FString::Printf(TEXT("_ComponentIsOpen%s"), *ComponentIsOpenDiff); }

        const auto OpenBodiesDiff = Get_FirstArrayDifference(
            InLhs._OpenBodies, InRhs._OpenBodies, &Get_FirstOpenBodyDifference);

        if (NOT OpenBodiesDiff.IsEmpty())
        { return FString::Printf(TEXT("_OpenBodies%s"), *OpenBodiesDiff); }

        return {};
    }

    inline auto Get_FieldsEqual(
        const ck::groundnav::FCk_GroundNav_Field& InLhs,
        const ck::groundnav::FCk_GroundNav_Field& InRhs,
        EPolicyComparison                         InPolicy) -> bool
    {
        return Get_FirstFieldDifference(InLhs, InRhs, InPolicy, EEpochComparison::Exclude).IsEmpty();
    }

    // The stricter form for pins that want epochs included too — see the exclusion rationale above.
    inline auto Get_FieldsEqualIncludingEpochs(
        const ck::groundnav::FCk_GroundNav_Field& InLhs,
        const ck::groundnav::FCk_GroundNav_Field& InRhs,
        EPolicyComparison                         InPolicy) -> bool
    {
        return Get_FirstFieldDifference(InLhs, InRhs, InPolicy, EEpochComparison::Include).IsEmpty();
    }
}

// --------------------------------------------------------------------------------------------------------------------
