#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "CkGroundNav/Bake/CkGroundNav_MarkupTypes.h"
#include "CkGroundNav/Field/CkGroundNav_FieldLinks.h"
#include "CkGroundNav/Field/CkGroundNav_FieldSerialize.h"
#include "CkGroundNav/Field/CkGroundNav_FieldTransform.h"

#include "CkShapes/Box/CkShapeBox_Fragment_Data.h"

#include "../CkUnitTest_Common.h"
#include "Test_GroundNav_FieldEquality.h"
#include "Test_GroundNav_QueryFixtures.h"

#include <NativeGameplayTags.h>

#include <limits>

// --------------------------------------------------------------------------------------------------------------------

UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_CkTests_GroundNav_FieldTransform_SourceArea,
                              "CkTests.GroundNav.FieldTransform.SourceArea");
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_CkTests_GroundNav_FieldTransform_DestinationArea,
                              "CkTests.GroundNav.FieldTransform.DestinationArea");
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_CkTests_GroundNav_FieldTransform_SourceUser,
                              "CkTests.GroundNav.FieldTransform.SourceUser");
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_CkTests_GroundNav_FieldTransform_DestinationUser,
                              "CkTests.GroundNav.FieldTransform.DestinationUser");

namespace ck_test_groundnav_fieldtransform
{
using ::FCk_GroundNav_LinkRecord;
using ::FCk_GroundNav_MarkupRecord;
using ck::groundnav::DoDerive_SeamPortals;
using ck::groundnav::DoLabel_Reachability;
using ck::groundnav::DoResolve_Links;
using ck::groundnav::ECk_GroundNav_FieldMergeStatus;
using ck::groundnav::FCk_GroundNav_Field;
using ck::groundnav::FCk_GroundNav_FieldInstanceTransform;
using ck::groundnav::FCk_GroundNav_FieldParams;
using ck::groundnav::FCk_GroundNav_Tile;
using ck::groundnav::FCk_GroundNav_TileCoord;
using ck::groundnav::FCk_GroundNav_TransformedFieldInstance;
using ck::groundnav::FCk_GroundNav_VolumeId;
using ck::groundnav::Get_TileCoord;
using ck::groundnav::Get_TileIndex;
using ck::groundnav::TryMerge_TransformedField;
using ck::groundnav::Write_Field;

using ck_test_groundnav_field_equality::EEpochComparison;
using ck_test_groundnav_field_equality::EPolicyComparison;
using ck_test_groundnav_field_equality::Get_FirstFieldDifference;
using ck_test_groundnav_field_equality::Get_FirstParamsDifference;
using ck_test_groundnav_field_equality::Get_FirstShapeDifference;
using ck_test_groundnav_queryfixtures::Bake;
using ck_test_groundnav_queryfixtures::kGroundZ;
using ck_test_groundnav_queryfixtures::kTileSize;
using ck_test_groundnav_queryfixtures::Make_Params;
using ck_test_groundnav_queryfixtures::Make_QueryParams;
using ck_test_groundnav_queryfixtures::Make_QueryScene;

constexpr auto kDestinationVolumeId = 731;
constexpr auto kMarkupOffset = 100;
constexpr auto kLinkOffset = 200;

auto Make_EmptyField(const FCk_GroundNav_FieldParams &InParams) -> FCk_GroundNav_Field
{
    auto Field = FCk_GroundNav_Field{};
    Field._Params = InParams;
    Field._Tiles.SetNum(InParams.Get_TileCount());

    for (auto TileIndex = 0; TileIndex < Field._Tiles.Num(); ++TileIndex)
    {
        Field._Tiles[TileIndex]._Coord = Get_TileCoord(InParams._Divisions, TileIndex);
    }

    return Field;
}

auto Make_SourceMarkup(const int32 InId = 1) -> FCk_GroundNav_MarkupRecord
{
    auto Markup =
        FCk_GroundNav_MarkupRecord{InId, FCk_AnyShape{FCk_ShapeBox_Dimensions{FVector{100.0, 50.0, 50.0}}},
                                   FTransform{FVector{300.0, 500.0, kGroundZ}}, ECk_GroundNav_MarkupKind::Cost};
    Markup.Set_AreaTag(TAG_CkTests_GroundNav_FieldTransform_SourceArea);
    Markup.Set_CostMultiplier(1.5f);
    return Markup;
}

auto Make_SourceLink() -> FCk_GroundNav_LinkRecord
{
    auto Link = FCk_GroundNav_LinkRecord{2, FVector{200.0, 200.0, kGroundZ}, FVector{600.0, 200.0, kGroundZ}};
    Link.Set_AreaTag(TAG_CkTests_GroundNav_FieldTransform_SourceArea);
    Link.Set_UserTypeTag(TAG_CkTests_GroundNav_FieldTransform_SourceUser);
    return Link;
}

auto Make_SourceParams() -> FCk_GroundNav_FieldParams
{
    auto Params = Make_QueryParams();
    Params._MarkupRecords = TArray<FCk_GroundNav_MarkupRecord>{Make_SourceMarkup()};
    Params._Links = TArray<FCk_GroundNav_LinkRecord>{Make_SourceLink()};
    return Params;
}

auto Make_HostParams() -> FCk_GroundNav_FieldParams
{
    return Make_Params(FIntPoint{4, 2});
}

auto Make_Descriptor() -> FCk_GroundNav_FieldInstanceTransform
{
    auto Descriptor = FCk_GroundNav_FieldInstanceTransform{};
    Descriptor._DestinationVolumeId = FCk_GroundNav_VolumeId{kDestinationVolumeId};
    Descriptor._DestinationTileAnchor = FCk_GroundNav_TileCoord{2, 0};
    Descriptor._YawDegrees = 90;
    Descriptor._MarkupIdOffset = kMarkupOffset;
    Descriptor._LinkIdOffset = kLinkOffset;
    Descriptor._TagRemap.Add(TAG_CkTests_GroundNav_FieldTransform_SourceArea,
                             TAG_CkTests_GroundNav_FieldTransform_DestinationArea);
    Descriptor._TagRemap.Add(TAG_CkTests_GroundNav_FieldTransform_SourceUser,
                             TAG_CkTests_GroundNav_FieldTransform_DestinationUser);
    return Descriptor;
}

// The descriptor's lower-left destination anchor is tile (2, 0). With a two-tile-wide source,
// its 90-degree placement rotates around the source origin, then offsets by (4 * tile span, 0).
auto Get_ReferencePlacement() -> FTransform
{
    return FTransform{FQuat{FVector::UpVector, FMath::DegreesToRadians(90.0)}, FVector{4.0 * kTileSize, 0.0, 0.0}};
}

auto Transform_Box(const FBox &InBox, const FTransform &InPlacement) -> FBox
{
    auto Result = FBox{ForceInit};

    for (auto X = 0; X < 2; ++X)
        for (auto Y = 0; Y < 2; ++Y)
            for (auto Z = 0; Z < 2; ++Z)
            {
                Result += InPlacement.TransformPosition(FVector{X == 0 ? InBox.Min.X : InBox.Max.X,
                                                                Y == 0 ? InBox.Min.Y : InBox.Max.Y,
                                                                Z == 0 ? InBox.Min.Z : InBox.Max.Z});
            }

    return Result;
}

auto Make_TransformedQueryScene() -> TArray<FBox>
{
    const auto Placement = Get_ReferencePlacement();
    auto Result = TArray<FBox>{};
    Result.Reserve(Make_QueryScene().Num());

    for (const auto &Box : Make_QueryScene())
    {
        Result.Emplace(Transform_Box(Box, Placement));
    }

    return Result;
}

auto Make_TransformedMarkup() -> FCk_GroundNav_MarkupRecord
{
    const auto Source = Make_SourceMarkup();
    auto Result = FCk_GroundNav_MarkupRecord{
        Source.Get_Id() + kMarkupOffset, Source.Get_Shape(),
        FTransform{Get_ReferencePlacement().GetRotation() * Source.Get_WorldTransform().GetRotation(),
                   Get_ReferencePlacement().TransformPosition(Source.Get_WorldTransform().GetLocation()),
                   Source.Get_WorldTransform().GetScale3D()},
        Source.Get_Kind()};
    Result.Set_AreaTag(TAG_CkTests_GroundNav_FieldTransform_DestinationArea);
    Result.Set_CostMultiplier(Source.Get_CostMultiplier());
    return Result;
}

constexpr auto kSemanticTolerance = 0.001f;

auto Get_AreEquivalent(const float InLhs, const float InRhs) -> bool
{
    return FMath::IsNearlyEqual(InLhs, InRhs, kSemanticTolerance);
}

auto Get_AreEquivalent(const FVector& InLhs, const FVector& InRhs) -> bool
{
    return InLhs.Equals(InRhs, kSemanticTolerance);
}

auto Get_AreEquivalent(const FQuat& InLhs, const FQuat& InRhs) -> bool
{
    return InLhs.IsNormalized() && InRhs.IsNormalized() &&
           FMath::Abs(InLhs | InRhs) >= 1.0f - kSemanticTolerance;
}

auto Get_AuthoredDifference(const FCk_GroundNav_Field& InLhs, const FCk_GroundNav_Field& InRhs) -> FString
{
    const auto& Lhs = InLhs._Params;
    const auto& Rhs = InRhs._Params;
    if (Lhs._MarkupRecords.Num() != Rhs._MarkupRecords.Num() || Lhs._Links.Num() != Rhs._Links.Num())
    {
        return TEXT("authored record count differs");
    }

    for (const auto& Markup : Lhs._MarkupRecords)
    {
        const auto* Expected = Rhs._MarkupRecords.FindByPredicate(
            [&Markup](const FCk_GroundNav_MarkupRecord& Candidate) { return Candidate.Get_Id() == Markup.Get_Id(); });
        if (Expected == nullptr || !Get_FirstShapeDifference(Markup.Get_Shape(), Expected->Get_Shape()).IsEmpty() ||
            Markup.Get_Kind() != Expected->Get_Kind() || Markup.Get_AreaTag() != Expected->Get_AreaTag() ||
            Markup.Get_Enable() != Expected->Get_Enable() || Markup.Get_RequestedAtEpoch() != Expected->Get_RequestedAtEpoch() ||
            !Get_AreEquivalent(Markup.Get_CostMultiplier(), Expected->Get_CostMultiplier()) ||
            !Get_AreEquivalent(Markup.Get_WorldTransform().GetLocation(), Expected->Get_WorldTransform().GetLocation()) ||
            !Get_AreEquivalent(Markup.Get_WorldTransform().GetRotation(), Expected->Get_WorldTransform().GetRotation()) ||
            !Get_AreEquivalent(Markup.Get_WorldTransform().GetScale3D(), Expected->Get_WorldTransform().GetScale3D()))
        {
            return FString::Printf(TEXT("markup %d differs semantically"), Markup.Get_Id());
        }
    }

    for (const auto& Link : Lhs._Links)
    {
        const auto* Expected = Rhs._Links.FindByPredicate(
            [&Link](const FCk_GroundNav_LinkRecord& Candidate) { return Candidate.Get_Id() == Link.Get_Id(); });
        if (Expected == nullptr || !Get_AreEquivalent(Link.Get_Start(), Expected->Get_Start()) ||
            !Get_AreEquivalent(Link.Get_End(), Expected->Get_End()) || Link.Get_AreaTag() != Expected->Get_AreaTag() ||
            Link.Get_UserTypeTag() != Expected->Get_UserTypeTag() || Link.Get_Direction() != Expected->Get_Direction() ||
            !Get_AreEquivalent(Link.Get_CostMultiplierForward(), Expected->Get_CostMultiplierForward()) ||
            !Get_AreEquivalent(Link.Get_CostMultiplierBackward(), Expected->Get_CostMultiplierBackward()) ||
            !Get_AreEquivalent(Link.Get_ClearanceUu(), Expected->Get_ClearanceUu()) || Link.Get_Enable() != Expected->Get_Enable())
        {
            return FString::Printf(TEXT("link %d differs semantically"), Link.Get_Id());
        }
    }

    return FString{};
}

auto Get_TileSemanticDifference(const FCk_GroundNav_Tile& InLhs, const FCk_GroundNav_Tile& InRhs) -> FString
{
    if (InLhs._Coord != InRhs._Coord || InLhs._Status != InRhs._Status || !Get_AreEquivalent(InLhs._Origin, InRhs._Origin) ||
        !Get_AreEquivalent(InLhs._CellSizeUu, InRhs._CellSizeUu) || InLhs._SizeX != InRhs._SizeX ||
        InLhs._SizeY != InRhs._SizeY || InLhs._LayerCount != InRhs._LayerCount)
    {
        return TEXT("tile lattice differs");
    }

    for (auto Layer = 0; Layer < InLhs._LayerCount; ++Layer)
        for (auto Y = 0; Y < InLhs._SizeY; ++Y)
            for (auto X = 0; X < InLhs._SizeX; ++X)
            {
                if (!Get_AreEquivalent(InLhs.Get_SurfaceZAt(X, Y, Layer), InRhs.Get_SurfaceZAt(X, Y, Layer)) ||
                    !Get_AreEquivalent(InLhs._Clearance.Get_ClearanceAt(X, Y, Layer), InRhs._Clearance.Get_ClearanceAt(X, Y, Layer)))
                {
                    return FString::Printf(TEXT("cell (%d,%d,%d) surface or clearance differs"), X, Y, Layer);
                }

                const auto LhsPlateIndex = InLhs._Plates.Get_PlateIndexAt(X, Y, Layer);
                const auto RhsPlateIndex = InRhs._Plates.Get_PlateIndexAt(X, Y, Layer);
                if ((LhsPlateIndex == INDEX_NONE) != (RhsPlateIndex == INDEX_NONE) ||
                    (LhsPlateIndex != INDEX_NONE && (!InLhs._Plates._Plates.IsValidIndex(LhsPlateIndex) ||
                                                     !InRhs._Plates._Plates.IsValidIndex(RhsPlateIndex))))
                {
                    return FString::Printf(TEXT("cell (%d,%d,%d) plate presence differs"), X, Y, Layer);
                }
            }

    return FString{};
}

auto Get_StubEndpoints(const ck::groundnav::FCk_GroundNav_Tile& InTile,
                       const ck::groundnav::FCk_GroundNav_SeamStub& InStub,
                       FVector& OutStart, FVector& OutEnd) -> void
{
    const auto Cell = InTile._CellSizeUu;
    if (InStub._Direction == 0 || InStub._Direction == 2)
    {
        const auto X = InStub._Direction == 0 ? InTile._SizeX : 0;
        OutStart = InTile._Origin + FVector{X * Cell, InStub._AlongIndex * Cell, InStub._NearSurfaceZUu};
        OutEnd = InTile._Origin + FVector{X * Cell, (InStub._AlongIndex + 1) * Cell, InStub._FarSurfaceZUu};
        return;
    }
    const auto Y = InStub._Direction == 1 ? InTile._SizeY : 0;
    OutStart = InTile._Origin + FVector{InStub._AlongIndex * Cell, Y * Cell, InStub._NearSurfaceZUu};
    OutEnd = InTile._Origin + FVector{(InStub._AlongIndex + 1) * Cell, Y * Cell, InStub._FarSurfaceZUu};
}

auto Get_TransformedDirection(const int32 InDirection, const FTransform* InPlacement) -> int32
{
    if (InPlacement == nullptr)
    {
        return InDirection;
    }
    const auto Offset = ck::groundnav::Get_DirectionOffset(InDirection);
    const auto Rotated = InPlacement->TransformVector(FVector{static_cast<float>(Offset.X), static_cast<float>(Offset.Y), 0.0f});
    if (FMath::Abs(Rotated.X) > FMath::Abs(Rotated.Y))
    {
        return Rotated.X >= 0.0 ? 0 : 2;
    }
    return Rotated.Y >= 0.0 ? 1 : 3;
}

auto Canonicalize_Endpoints(FVector& InOutStart, FVector& InOutEnd) -> void
{
    const auto EndComesFirst = InOutEnd.X < InOutStart.X ||
        (InOutEnd.X == InOutStart.X && InOutEnd.Y < InOutStart.Y) ||
        (InOutEnd.X == InOutStart.X && InOutEnd.Y == InOutStart.Y && InOutEnd.Z < InOutStart.Z);
    if (EndComesFirst)
    {
        Swap(InOutStart, InOutEnd);
    }
}

auto Normalize_SignedZero(FVector& InOutValue) -> void
{
    InOutValue.X = FMath::GridSnap(InOutValue.X, 0.001);
    InOutValue.Y = FMath::GridSnap(InOutValue.Y, 0.001);
    InOutValue.Z = FMath::GridSnap(InOutValue.Z, 0.001);
    if (FMath::IsNearlyZero(InOutValue.X, 0.0005)) InOutValue.X = 0.0;
    if (FMath::IsNearlyZero(InOutValue.Y, 0.0005)) InOutValue.Y = 0.0;
    if (FMath::IsNearlyZero(InOutValue.Z, 0.0005)) InOutValue.Z = 0.0;
}

auto Get_CanonicalTopology(const FCk_GroundNav_Field& InField, const FTransform* InPlacement = nullptr) -> TArray<FString>
{
    auto Result = TArray<FString>{};
    const auto TransformPoint = [InPlacement](const FVector& InPoint) { return InPlacement == nullptr ? InPoint : InPlacement->TransformPosition(InPoint); };
    const auto AddBoundary = [&Result](const ck::groundnav::FCk_GroundNav_BoundarySegment& InBoundary)
    {
        auto Start = InBoundary._Start;
        auto End = InBoundary._End;
        auto Normal = InBoundary._InwardNormalXY;
        Normalize_SignedZero(Start);
        Normalize_SignedZero(End);
        Normal.X = FMath::GridSnap(Normal.X, 0.001);
        Normal.Y = FMath::GridSnap(Normal.Y, 0.001);
        if (FMath::IsNearlyZero(Normal.X, 0.0005)) Normal.X = 0.0;
        if (FMath::IsNearlyZero(Normal.Y, 0.0005)) Normal.Y = 0.0;
        Canonicalize_Endpoints(Start, End);
        Result.Emplace(FString::Printf(TEXT("B %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %d"), Start.X,
                                       Start.Y, Start.Z, End.X, End.Y, End.Z,
                                       Normal.X, Normal.Y,
                                       InBoundary._LayerIndex));
    };
    for (const auto& Tile : InField._Tiles)
    {
        for (const auto& Portal : Tile._Portals._Portals)
        {
            auto Start = FVector{};
            auto End = FVector{};
            Portal.Get_Endpoints(Tile._Origin, Tile._CellSizeUu, Start, End);
            Start = TransformPoint(Start);
            End = TransformPoint(End);
            Normalize_SignedZero(Start);
            Normalize_SignedZero(End);
            Canonicalize_Endpoints(Start, End);
            Result.Emplace(FString::Printf(TEXT("P %.3f %.3f %.3f %.3f %.3f %.3f %.3f"), Start.X, Start.Y,
                                           Start.Z, End.X, End.Y, End.Z, Portal._TraversalClearanceUu));
        }
        for (const auto& Stub : Tile._SeamStubs)
        {
            auto Start = FVector{};
            auto End = FVector{};
            Get_StubEndpoints(Tile, Stub, Start, End);
            Start = TransformPoint(Start);
            End = TransformPoint(End);
            Normalize_SignedZero(Start);
            Normalize_SignedZero(End);
            Canonicalize_Endpoints(Start, End);
            Result.Emplace(FString::Printf(TEXT("S %.3f %.3f %.3f %.3f %.3f %.3f %d %.3f"), Start.X, Start.Y, Start.Z,
                                           End.X, End.Y, End.Z, Get_TransformedDirection(Stub._Direction, InPlacement),
                                           Stub._ClearanceUu));
        }
        for (const auto& Boundary : Tile._Boundary._Segments)
        {
            auto Transformed = Boundary;
            Transformed._Start = TransformPoint(Boundary._Start);
            Transformed._End = TransformPoint(Boundary._End);
            const auto Normal = InPlacement == nullptr ? FVector{Boundary._InwardNormalXY, 0.0f} :
                InPlacement->TransformVector(FVector{Boundary._InwardNormalXY, 0.0f});
            Transformed._InwardNormalXY = FVector2D{Normal.X, Normal.Y};
            AddBoundary(Transformed);
        }
    }
    for (const auto& Boundaries : InField._TileEdgeBoundary)
        for (const auto& Boundary : Boundaries)
        {
            auto Transformed = Boundary;
            Transformed._Start = TransformPoint(Boundary._Start);
            Transformed._End = TransformPoint(Boundary._End);
            const auto Normal = InPlacement == nullptr ? FVector{Boundary._InwardNormalXY, 0.0f} :
                InPlacement->TransformVector(FVector{Boundary._InwardNormalXY, 0.0f});
            Transformed._InwardNormalXY = FVector2D{Normal.X, Normal.Y};
            AddBoundary(Transformed);
        }
    for (const auto& Seam : InField._SeamPortals)
    {
        if (!InField._Tiles.IsValidIndex(Seam._TileIndexA))
        {
            return {TEXT("invalid seam tile")};
        }
        auto Start = FVector{};
        auto End = FVector{};
        Seam.Get_Endpoints(InField._Tiles[Seam._TileIndexA], Start, End);
        Start = TransformPoint(Start);
        End = TransformPoint(End);
        Normalize_SignedZero(Start);
        Normalize_SignedZero(End);
        Canonicalize_Endpoints(Start, End);
        Result.Emplace(FString::Printf(TEXT("M %.3f %.3f %.3f %.3f %.3f %.3f %.3f"), Start.X, Start.Y, Start.Z,
                                       End.X, End.Y, End.Z, Seam._TraversalClearanceUu));
    }
    Result.Sort();
    return Result;
}

auto Get_CanonicalReachability(const FCk_GroundNav_Field& InField) -> TArray<FString>
{
    auto Result = TArray<FString>{};
    auto Labels = TMap<int32, int32>{};
    for (auto TileIndex = 0; TileIndex < InField._Tiles.Num(); ++TileIndex)
    {
        const auto& Tile = InField._Tiles[TileIndex];
        for (auto Layer = 0; Layer < Tile._LayerCount; ++Layer)
            for (auto Y = 0; Y < Tile._SizeY; ++Y)
                for (auto X = 0; X < Tile._SizeX; ++X)
                {
                    const auto Plate = Tile._Plates.Get_PlateIndexAt(X, Y, Layer);
                    if (Plate == INDEX_NONE)
                    {
                        Result.Emplace(TEXT("none"));
                        continue;
                    }
                    const auto Label = InField.Get_ReachabilityLabel(TileIndex, Plate);
                    const auto Canonical = Labels.FindOrAdd(Label, Labels.Num());
                    Result.Emplace(FString::Printf(TEXT("%d:%d"), Canonical, InField.Get_IsComponentOpen(Label) ? 1 : 0));
                }
    }
    return Result;
}

auto Get_RemappedTag(const FGameplayTag InTag) -> FGameplayTag
{
    return InTag == TAG_CkTests_GroundNav_FieldTransform_SourceArea
               ? TAG_CkTests_GroundNav_FieldTransform_DestinationArea
               : InTag == TAG_CkTests_GroundNav_FieldTransform_SourceUser
                   ? TAG_CkTests_GroundNav_FieldTransform_DestinationUser
                   : InTag;
}

auto Get_RemappedPolicy(const FGameplayTagContainer& InPolicy) -> FGameplayTagContainer
{
    auto Tags = TArray<FGameplayTag>{};
    InPolicy.GetGameplayTagArray(Tags);
    auto Result = FGameplayTagContainer{};
    for (const auto& Tag : Tags)
    {
        Result.AddTag(Get_RemappedTag(Tag));
    }
    return Result;
}

auto Get_TransformedSourcePolicyDifference(const FCk_GroundNav_Field& InSource,
                                           const FCk_GroundNav_Field& InOutput,
                                           const FTransform& InPlacement) -> FString
{
    for (const auto& SourceTile : InSource._Tiles)
        for (auto Layer = 0; Layer < SourceTile._LayerCount; ++Layer)
            for (auto Y = 0; Y < SourceTile._SizeY; ++Y)
                for (auto X = 0; X < SourceTile._SizeX; ++X)
                {
                    const auto SourcePlateIndex = SourceTile._Plates.Get_PlateIndexAt(X, Y, Layer);
                    if (SourcePlateIndex == INDEX_NONE)
                    {
                        continue;
                    }
                    const auto World = InPlacement.TransformPosition(SourceTile.Get_CellCentre(X, Y, Layer));
                    const auto* OutputTile = InOutput.Get_TileAt(World);
                    if (OutputTile == nullptr)
                    {
                        return TEXT("transformed source cell has no output tile");
                    }
                    const auto OutputX = FMath::FloorToInt((World.X - OutputTile->_Origin.X) / OutputTile->_CellSizeUu);
                    const auto OutputY = FMath::FloorToInt((World.Y - OutputTile->_Origin.Y) / OutputTile->_CellSizeUu);
                    const auto OutputPlateIndex = OutputTile->_Plates.Get_PlateIndexAt(OutputX, OutputY, Layer);
                    if (!OutputTile->_Plates._Plates.IsValidIndex(OutputPlateIndex))
                    {
                        return TEXT("transformed source cell has no output plate");
                    }
                    const auto& SourcePlate = SourceTile._Plates._Plates[SourcePlateIndex];
                    const auto& OutputPlate = OutputTile->_Plates._Plates[OutputPlateIndex];
                    if (SourcePlate._LayerIndex != OutputPlate._LayerIndex ||
                        Get_RemappedPolicy(SourceTile._Plates.Get_AreaPolicy(SourcePlate._AreaPolicyIndex)) !=
                            OutputTile->_Plates.Get_AreaPolicy(OutputPlate._AreaPolicyIndex) ||
                        !Get_AreEquivalent(SourcePlate._CostMultiplier, OutputPlate._CostMultiplier) ||
                        !Get_AreEquivalent(SourcePlate._MinClearanceUu, OutputPlate._MinClearanceUu))
                    {
                        return FString::Printf(TEXT("transformed source policy differs at (%d,%d,%d)"), X, Y, Layer);
                    }
                }
    return FString{};
}

auto Get_CanonicalResolvedLinks(const FCk_GroundNav_Field& InField) -> TArray<FString>
{
    auto Result = TArray<FString>{};
    for (const auto& Link : InField._ResolvedLinks)
    {
        Result.Emplace(FString::Printf(TEXT("%d %.3f %.3f %.3f %.3f %.3f %.3f %d %d %d %.3f %.3f %.3f %s %s %d"),
                                       Link._Id, Link._Start.X, Link._Start.Y, Link._Start.Z, Link._End.X, Link._End.Y, Link._End.Z,
                                       static_cast<int32>(Link._StartStatus), static_cast<int32>(Link._EndStatus), static_cast<int32>(Link._Direction),
                                       Link._CostMultiplierForward, Link._CostMultiplierBackward, Link._ClearanceUu,
                                       *Link._AreaTag.ToString(), *Link._UserTypeTag.ToString(), static_cast<int32>(Link._Enable)));
    }
    Result.Sort();
    return Result;
}

auto Get_FirstCanonicalDifference(const TArray<FString>& InExpected, const TArray<FString>& InActual) -> FString
{
    if (InExpected.Num() != InActual.Num())
    {
        return FString::Printf(TEXT("count %d vs %d"), InExpected.Num(), InActual.Num());
    }
    for (auto Index = 0; Index < InExpected.Num(); ++Index)
    {
        if (InExpected[Index] != InActual[Index])
        {
            return FString::Printf(TEXT("index %d expected [%s] actual [%s]"), Index, *InExpected[Index],
                                   *InActual[Index]);
        }
    }
    return {};
}

auto Get_TransformedSourceResolvedLinks(const FCk_GroundNav_Field& InSource, const FTransform& InPlacement) -> TArray<FString>
{
    auto Result = TArray<FString>{};
    for (const auto& Link : InSource._ResolvedLinks)
    {
        const auto Start = InPlacement.TransformPosition(Link._Start);
        const auto End = InPlacement.TransformPosition(Link._End);
        Result.Emplace(FString::Printf(TEXT("%d %.3f %.3f %.3f %.3f %.3f %.3f %d %d %d %.3f %.3f %.3f %s %s %d"),
                                       Link._Id + kLinkOffset, Start.X, Start.Y, Start.Z, End.X, End.Y, End.Z,
                                       static_cast<int32>(Link._StartStatus), static_cast<int32>(Link._EndStatus), static_cast<int32>(Link._Direction),
                                       Link._CostMultiplierForward, Link._CostMultiplierBackward, Link._ClearanceUu,
                                       *Get_RemappedTag(Link._AreaTag).ToString(), *Get_RemappedTag(Link._UserTypeTag).ToString(),
                                       static_cast<int32>(Link._Enable)));
    }
    Result.Sort();
    return Result;
}

auto Get_FieldSemanticDifference(const FCk_GroundNav_Field& InLhs, const FCk_GroundNav_Field& InRhs) -> FString
{
    if (InLhs._Tiles.Num() != InRhs._Tiles.Num()) return TEXT("tile count differs");
    for (auto Index = 0; Index < InLhs._Tiles.Num(); ++Index)
    {
        const auto Difference = Get_TileSemanticDifference(InLhs._Tiles[Index], InRhs._Tiles[Index]);
        if (!Difference.IsEmpty()) return FString::Printf(TEXT("tile %d: %s"), Index, *Difference);
    }
    return FString{};
}

auto Make_TransformedLink() -> FCk_GroundNav_LinkRecord
{
    const auto Source = Make_SourceLink();
    auto Result = FCk_GroundNav_LinkRecord{Source.Get_Id() + kLinkOffset,
                                           Get_ReferencePlacement().TransformPosition(Source.Get_Start()),
                                           Get_ReferencePlacement().TransformPosition(Source.Get_End())};
    Result.Set_AreaTag(TAG_CkTests_GroundNav_FieldTransform_DestinationArea);
    Result.Set_UserTypeTag(TAG_CkTests_GroundNav_FieldTransform_DestinationUser);
    return Result;
}

auto Make_DirectParams() -> FCk_GroundNav_FieldParams
{
    auto Params = Make_HostParams();
    Params._MarkupRecords = TArray<FCk_GroundNav_MarkupRecord>{Make_TransformedMarkup()};
    Params._Links = TArray<FCk_GroundNav_LinkRecord>{Make_TransformedLink()};
    return Params;
}

auto Get_InstanceDifference(const FCk_GroundNav_TransformedFieldInstance &InLhs,
                            const FCk_GroundNav_TransformedFieldInstance &InRhs) -> FString
{
    if (NOT(InLhs._VolumeId == InRhs._VolumeId))
    {
        return TEXT("_VolumeId differs");
    }

    const auto ParamsDifference = Get_FirstParamsDifference(InLhs._Field._Params, InRhs._Field._Params);
    if (NOT ParamsDifference.IsEmpty())
    {
        return ParamsDifference;
    }

    return Get_FirstFieldDifference(InLhs._Field, InRhs._Field, EPolicyComparison::Include, EEpochComparison::Exclude);
}

auto Get_InstanceBytes(const FCk_GroundNav_TransformedFieldInstance &InInstance) -> TArray<uint8>
{
    auto Bytes = TArray<uint8>{};
    Write_Field(InInstance._Field, Bytes);
    return Bytes;
}

auto Make_PartialDirectField(const FCk_GroundNav_Field &InDirect) -> FCk_GroundNav_Field
{
    auto Result = Make_EmptyField(InDirect._Params);

    for (auto Y = 0; Y < InDirect._Params._Divisions.Y; ++Y)
        for (auto X = 2; X < InDirect._Params._Divisions.X; ++X)
        {
            const auto Coord = FCk_GroundNav_TileCoord{X, Y};
            const auto TileIndex = Get_TileIndex(InDirect._Params._Divisions, Coord);
            Result._Tiles[TileIndex] = InDirect._Tiles[TileIndex];
        }

    DoDerive_SeamPortals(Result);
    DoResolve_Links(Result);
    DoLabel_Reachability(Result);
    return Result;
}

auto Get_HasRemappedPlatePolicy(const FCk_GroundNav_Field &InField) -> bool
{
    auto FoundDestination = false;

    for (const auto &Tile : InField._Tiles)
        for (const auto &Policy : Tile._Plates._AreaPolicies)
        {
            if (Policy.HasTag(TAG_CkTests_GroundNav_FieldTransform_SourceArea))
            {
                return false;
            }

            FoundDestination |= Policy.HasTag(TAG_CkTests_GroundNav_FieldTransform_DestinationArea);
        }

    return FoundDestination;
}

auto Make_Sentinel() -> FCk_GroundNav_TransformedFieldInstance
{
    auto Sentinel = FCk_GroundNav_TransformedFieldInstance{};
    Sentinel._VolumeId = FCk_GroundNav_VolumeId{999};
    Sentinel._Field = Make_EmptyField(Make_HostParams());
    Sentinel._Field._Params._MinZUu = -12345.0f;
    return Sentinel;
}

auto Test_RefusalIsAtomic(FAutomationTestBase &InTest, const TCHAR *InName, ECk_GroundNav_FieldMergeStatus InActual,
                          ECk_GroundNav_FieldMergeStatus InExpected,
                          const FCk_GroundNav_TransformedFieldInstance &InBefore,
                          const FCk_GroundNav_TransformedFieldInstance &InAfter) -> void
{
    InTest.TestEqual(InName, InActual, InExpected);
    InTest.TestTrue(FString::Printf(TEXT("%s leaves the value sentinel unchanged"), InName),
                    Get_InstanceDifference(InBefore, InAfter).IsEmpty());
    InTest.TestTrue(FString::Printf(TEXT("%s leaves the serialized sentinel unchanged"), InName),
                    Get_InstanceBytes(InBefore) == Get_InstanceBytes(InAfter));
}
} // namespace ck_test_groundnav_fieldtransform

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_GroundNav_FieldTransform_QuarterTurnMatchesDirectBake,
                                 "CkTests.UnitTests.CkGroundNav.FieldTransform.QuarterTurnMatchesDirectBake",
                                 ck::tests::kCkUnitTestFlags)

bool FCkTest_GroundNav_FieldTransform_QuarterTurnMatchesDirectBake::RunTest(const FString &Parameters)
{
    using namespace ck_test_groundnav_fieldtransform;

    auto Source = FCk_GroundNav_Field{};
    auto Direct = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the asymmetric source scene bakes"), Bake(Make_QueryScene(), Make_SourceParams(), Source)) ||
        NOT TestTrue(TEXT("the equivalently transformed direct scene bakes"),
                     Bake(Make_TransformedQueryScene(), Make_DirectParams(), Direct)))
    {
        return false;
    }

    const auto Expected = Make_PartialDirectField(Direct);

    auto Output = Make_Sentinel();
    const auto Status =
        TryMerge_TransformedField(Make_EmptyField(Make_HostParams()), Source, Make_Descriptor(), Output);

    if (NOT TestEqual(TEXT("the aligned quarter-turn merge succeeds"), Status,
                      ECk_GroundNav_FieldMergeStatus::Completed))
    {
        return false;
    }

    TestEqual(TEXT("the transformed instance carries its explicit destination identity"), Output._VolumeId,
              FCk_GroundNav_VolumeId{kDestinationVolumeId});

    const auto AuthoredDifference = Get_AuthoredDifference(Output._Field, Expected);
    const auto ActualRotation = Output._Field._Params._MarkupRecords[0].Get_WorldTransform().GetRotation();
    const auto ExpectedRotation = Expected._Params._MarkupRecords[0].Get_WorldTransform().GetRotation();
    TestTrue(FString::Printf(TEXT("the merge transforms markup/link poses, rebases ids, and remaps authored tags [%s; "
                                  "actual rotation=%s; expected rotation=%s; abs dot=%.9f]"),
                             *AuthoredDifference, *ActualRotation.ToString(), *ExpectedRotation.ToString(),
                             FMath::Abs(ActualRotation | ExpectedRotation)),
             AuthoredDifference.IsEmpty());

    const auto DirectBakeDifference = Get_FieldSemanticDifference(Output._Field, Expected);
    const auto StrictDifference =
        Get_FirstFieldDifference(Output._Field, Expected, EPolicyComparison::Include, EEpochComparison::Exclude);
    TestTrue(FString::Printf(TEXT("the transformed merge matches direct per-cell surfaces, clearance, and plate presence "
                                  "[%s; strict diagnostic=%s]"), *DirectBakeDifference, *StrictDifference),
             DirectBakeDifference.IsEmpty());

    const auto Placement = Get_ReferencePlacement();
    const auto PolicyDifference = Get_TransformedSourcePolicyDifference(Source, Output._Field, Placement);
    TestTrue(FString::Printf(TEXT("the transformed source preserves remapped plate policies, costs, and clearance [%s]"),
                             *PolicyDifference), PolicyDifference.IsEmpty());

    const auto SourceTopology = Get_CanonicalTopology(Source, &Placement);
    const auto OutputTopology = Get_CanonicalTopology(Output._Field);
    const auto TopologyDifference = Get_FirstCanonicalDifference(SourceTopology, OutputTopology);
    TestTrue(FString::Printf(TEXT("the transformed source preserves portal, seam, stub, and boundary world geometry "
                                  "and canonical directions [%s]"), *TopologyDifference),
             TopologyDifference.IsEmpty());

    TestTrue(TEXT("the transformed field matches direct-bake reachability and open-state meaning"),
             Get_CanonicalReachability(Expected) == Get_CanonicalReachability(Output._Field));

    const auto SourceResolvedDifference = Get_FirstCanonicalDifference(
        Get_TransformedSourceResolvedLinks(Source, Placement), Get_CanonicalResolvedLinks(Output._Field));
    const auto DirectResolvedDifference = Get_FirstCanonicalDifference(
        Get_CanonicalResolvedLinks(Expected), Get_CanonicalResolvedLinks(Output._Field));
    TestTrue(FString::Printf(TEXT("the transformed source preserves resolved link world meaning without flat plate ids "
                                  "[source=%s; direct=%s]"),
                             *SourceResolvedDifference, *DirectResolvedDifference),
             SourceResolvedDifference.IsEmpty());
    TestTrue(TEXT("the transformed field re-resolves both link endpoints onto valid destination surfaces"),
             Output._Field._ResolvedLinks.Num() == 1 &&
                 Output._Field._ResolvedLinks[0]._StartSurface.Get_IsValid() &&
                 Output._Field._ResolvedLinks[0]._EndSurface.Get_IsValid());

    TestTrue(
        TEXT("the transformed merge retains only the explicitly remapped authored tags"),
        Output._Field._Params._MarkupRecords.Num() == 1 &&
            Output._Field._Params._MarkupRecords[0].Get_AreaTag() ==
                TAG_CkTests_GroundNav_FieldTransform_DestinationArea &&
            Output._Field._Params._Links.Num() == 1 &&
            Output._Field._Params._Links[0].Get_AreaTag() == TAG_CkTests_GroundNav_FieldTransform_DestinationArea &&
            Output._Field._Params._Links[0].Get_UserTypeTag() == TAG_CkTests_GroundNav_FieldTransform_DestinationUser);
    TestTrue(TEXT("the transformed markup pose is the direct-bake pose"),
             Output._Field._Params._MarkupRecords.Num() == 1 &&
                 Get_AreEquivalent(Output._Field._Params._MarkupRecords[0].Get_WorldTransform().GetLocation(),
                                   Expected._Params._MarkupRecords[0].Get_WorldTransform().GetLocation()) &&
                 Get_AreEquivalent(Output._Field._Params._MarkupRecords[0].Get_WorldTransform().GetRotation(),
                                   Expected._Params._MarkupRecords[0].Get_WorldTransform().GetRotation()));
    TestTrue(TEXT("the transformed link endpoints are the direct-bake endpoints"),
             Output._Field._Params._Links.Num() == 1 &&
                 Output._Field._Params._Links[0].Get_Start().Equals(Expected._Params._Links[0].Get_Start()) &&
                 Output._Field._Params._Links[0].Get_End().Equals(Expected._Params._Links[0].Get_End()));
    TestTrue(TEXT("the copied plate policies contain the destination tag rather than the source tag"),
             Get_HasRemappedPlatePolicy(Output._Field));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_GroundNav_FieldTransform_RefusalsAreAtomic,
                                 "CkTests.UnitTests.CkGroundNav.FieldTransform.RefusalsAreAtomic",
                                 ck::tests::kCkUnitTestFlags)

bool FCkTest_GroundNav_FieldTransform_RefusalsAreAtomic::RunTest(const FString &Parameters)
{
    using namespace ck_test_groundnav_fieldtransform;

    auto Source = FCk_GroundNav_Field{};
    if (NOT TestTrue(TEXT("the source for refusal coverage bakes"),
                     Bake(Make_QueryScene(), Make_SourceParams(), Source)))
    {
        return false;
    }

    const auto EmptyHost = Make_EmptyField(Make_HostParams());
    const auto Descriptor = Make_Descriptor();

    auto InvalidRotation = Descriptor;
    InvalidRotation._YawDegrees = 45;
    auto Before = Make_Sentinel();
    auto Output = Before;
    AddExpectedError(TEXT("GroundNav field transform has invalid descriptor or field payload"),
                     EAutomationExpectedErrorFlags::Contains, 2);
    Test_RefusalIsAtomic(*this, TEXT("a 45-degree rotation is rejected without snapping"),
                         TryMerge_TransformedField(EmptyHost, Source, InvalidRotation, Output),
                         ECk_GroundNav_FieldMergeStatus::InvalidInput, Before, Output);

    auto MissingTagMap = Descriptor;
    MissingTagMap._TagRemap.Remove(TAG_CkTests_GroundNav_FieldTransform_SourceUser);
    Before = Make_Sentinel();
    Output = Before;
    Test_RefusalIsAtomic(*this, TEXT("an unmapped authored tag is rejected"),
                         TryMerge_TransformedField(EmptyHost, Source, MissingTagMap, Output),
                         ECk_GroundNav_FieldMergeStatus::MissingTagRemap, Before, Output);

    auto CollisionHost = EmptyHost;
    auto CollisionMarkup = Make_SourceMarkup(1 + kMarkupOffset);
    CollisionHost._Params._MarkupRecords.Emplace(MoveTemp(CollisionMarkup));
    Before = Make_Sentinel();
    Output = Before;
    Test_RefusalIsAtomic(*this, TEXT("a rebased authored-id collision is rejected"),
                         TryMerge_TransformedField(CollisionHost, Source, Descriptor, Output),
                         ECk_GroundNav_FieldMergeStatus::IdentityConflict, Before, Output);

    auto Overflow = Descriptor;
    Overflow._MarkupIdOffset = TNumericLimits<int32>::Max();
    Before = Make_Sentinel();
    Output = Before;
    Test_RefusalIsAtomic(*this, TEXT("an overflowing authored-id rebase is rejected"),
                         TryMerge_TransformedField(EmptyHost, Source, Overflow, Output),
                         ECk_GroundNav_FieldMergeStatus::IdentityConflict, Before, Output);

    auto IncompatibleSource = Source;
    IncompatibleSource._Params._MergeTunables = FCk_GroundNav_MergeTunables{11.0f, 10.0f};
    Before = Make_Sentinel();
    Output = Before;
    AddExpectedError(TEXT("GroundNav field transform needs matching lattice settings"),
                     EAutomationExpectedErrorFlags::Contains, 2);
    Test_RefusalIsAtomic(*this, TEXT("a source from another lattice is rejected"),
                         TryMerge_TransformedField(EmptyHost, IncompatibleSource, Descriptor, Output),
                         ECk_GroundNav_FieldMergeStatus::IncompatibleLattice, Before, Output);

    auto OutOfBounds = Descriptor;
    OutOfBounds._DestinationTileAnchor = FCk_GroundNav_TileCoord{3, 0};
    Before = Make_Sentinel();
    Output = Before;
    Test_RefusalIsAtomic(*this, TEXT("an anchor outside the declared host lattice is rejected"),
                         TryMerge_TransformedField(EmptyHost, Source, OutOfBounds, Output),
                         ECk_GroundNav_FieldMergeStatus::OutOfBounds, Before, Output);

    const auto UnbuiltSource = Make_EmptyField(Make_SourceParams());
    auto UnbuiltOutOfBounds = Descriptor;
    UnbuiltOutOfBounds._DestinationTileAnchor = FCk_GroundNav_TileCoord{4, 0};
    Before = Make_Sentinel();
    Output = Before;
    Test_RefusalIsAtomic(*this, TEXT("an unbuilt source still has a bounded declared footprint"),
                         TryMerge_TransformedField(EmptyHost, UnbuiltSource, UnbuiltOutOfBounds, Output),
                         ECk_GroundNav_FieldMergeStatus::OutOfBounds, Before, Output);

    auto NonFiniteHost = EmptyHost;
    NonFiniteHost._Params._OriginXY.X = std::numeric_limits<double>::quiet_NaN();
    Before = Make_Sentinel();
    Output = Before;
    AddExpectedError(TEXT("GroundNav field transform has invalid descriptor or field payload"),
                     EAutomationExpectedErrorFlags::Contains, 2);
    Test_RefusalIsAtomic(*this, TEXT("a non-finite host lattice is rejected"),
                         TryMerge_TransformedField(NonFiniteHost, Source, Descriptor, Output),
                         ECk_GroundNav_FieldMergeStatus::InvalidInput, Before, Output);

    auto InvalidHostIdentity = EmptyHost;
    InvalidHostIdentity._Params._MarkupRecords.Emplace(Make_SourceMarkup(0));
    Before = Make_Sentinel();
    Output = Before;
    AddExpectedError(TEXT("GroundNav field transform has invalid descriptor or field payload"),
                     EAutomationExpectedErrorFlags::Contains, 2);
    Test_RefusalIsAtomic(*this, TEXT("a non-positive host identity is rejected"),
                         TryMerge_TransformedField(InvalidHostIdentity, Source, Descriptor, Output),
                         ECk_GroundNav_FieldMergeStatus::InvalidInput, Before, Output);

    auto OverlapHost = EmptyHost;
    OverlapHost._Tiles[3] = Source._Tiles[0];
    OverlapHost._Tiles[3]._Coord = FCk_GroundNav_TileCoord{3, 0};
    OverlapHost._Tiles[3]._Origin = FVector{OverlapHost._Params._OriginXY.X +
                                               (3 * OverlapHost._Params.Get_TileSpanUu()),
                                           OverlapHost._Params._OriginXY.Y, OverlapHost._Params._MinZUu};
    Before = Make_Sentinel();
    Output = Before;
    Test_RefusalIsAtomic(*this, TEXT("a transformed tile that overlaps built host ground is rejected"),
                         TryMerge_TransformedField(OverlapHost, Source, Descriptor, Output),
                         ECk_GroundNav_FieldMergeStatus::TileOverlap, Before, Output);

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
