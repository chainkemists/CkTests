#include "CkGroundNav/Volume/CkGroundNavVolume_EntityScript.h"
#include "CkGroundNav/Volume/CkGroundNavVolume_Utils.h"

#include "CkJolt/Settings/CkJolt_ProjectSettings.h"

#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

#include <limits>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_volumeauthoring
{
    auto Make_Config() -> FCk_GroundNav_BakeConfig
    {
        auto Config = FCk_GroundNav_BakeConfig{25.0f, 10.0f};
        Config.Set_TileSizeUu(400.0f);
        return Config;
    }

    auto Make_Profile() -> FCk_GroundNav_AgentProfile
    {
        return FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{70.0f, 20.0f}}};
    }

    auto Make_Params(
        const FBox& InBounds,
        const FCk_GroundNav_BakeConfig& InConfig = Make_Config())
        -> FCk_Fragment_GroundNavVolume_ParamsData
    {
        return FCk_Fragment_GroundNavVolume_ParamsData{InBounds, InConfig, Make_Profile()};
    }

    auto Get_IsRejected(const FCk_Fragment_GroundNavVolume_ParamsData& InParams) -> bool
    {
        const auto FieldParams = ck::groundnav::Get_VolumeFieldParams(InParams, {}, {});
        return FieldParams._Divisions == FIntPoint::ZeroValue && NOT FieldParams.Get_IsValid();
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_VolumeAuthoring_PlacementMovesOnlyBounds,
    "CkTests.UnitTests.CkGroundNav.VolumeAuthoring.PlacementMovesOnlyBounds",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_VolumeAuthoring_PlacementMovesOnlyBounds::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_volumeauthoring;

    const auto Params = Make_Params(FBox{FVector{-100.0, -200.0, -50.0}, FVector{300.0, 400.0, 250.0}});
    const auto Placement = FTransform{FRotator{15.0f, 45.0f, 30.0f}, FVector{1000.0, -500.0, 75.0}, FVector{2.0f}};
    const auto Placed = ck::groundnav::Get_PlacedVolumeParams(Params, Placement);

    TestEqual(TEXT("translation moves the minimum bound"), Placed.Get_VolumeBounds().Min,
        FVector{900.0, -700.0, 25.0});
    TestEqual(TEXT("translation moves the maximum bound"), Placed.Get_VolumeBounds().Max,
        FVector{1300.0, -100.0, 325.0});
    TestEqual(TEXT("rotation and scale leave the authored box dimensions unchanged"),
        Placed.Get_VolumeBounds().GetSize(), Params.Get_VolumeBounds().GetSize());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_VolumeAuthoring_FieldParamsRejectMalformedBoundsAndSpan,
    "CkTests.UnitTests.CkGroundNav.VolumeAuthoring.FieldParamsRejectMalformedBoundsAndSpan",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_VolumeAuthoring_FieldParamsRejectMalformedBoundsAndSpan::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_volumeauthoring;

    const auto ValidBounds = FBox{FVector{100.0, 200.0, -50.0}, FVector{901.0, 1000.0, 250.0}};
    const auto Valid = ck::groundnav::Get_VolumeFieldParams(Make_Params(ValidBounds), {}, {});
    TestEqual(TEXT("valid X extent rounds up to three 400uu tiles"), Valid._Divisions.X, 3);
    TestEqual(TEXT("valid Y extent rounds up to two 400uu tiles"), Valid._Divisions.Y, 2);
    TestEqual(TEXT("valid bounds retain their XY origin"), Valid._OriginXY, FVector2D{100.0, 200.0});

    auto InvalidBounds = Make_Params(FBox{ForceInit});
    TestTrue(TEXT("an uninitialized box produces no field"), Get_IsRejected(InvalidBounds));

    auto NaNBounds = Make_Params(ValidBounds);
    auto NaNBox = ValidBounds;
    NaNBox.Min.X = std::numeric_limits<double>::quiet_NaN();
    NaNBox.IsValid = 1;
    NaNBounds.Set_VolumeBounds(NaNBox);
    TestTrue(TEXT("NaN bounds produce no field"), Get_IsRejected(NaNBounds));

    auto InfiniteBounds = Make_Params(ValidBounds);
    auto InfiniteBox = ValidBounds;
    InfiniteBox.Max.Y = std::numeric_limits<double>::infinity();
    InfiniteBox.IsValid = 1;
    InfiniteBounds.Set_VolumeBounds(InfiniteBox);
    TestTrue(TEXT("infinite bounds produce no field"), Get_IsRejected(InfiniteBounds));

    auto InvertedBounds = Make_Params(ValidBounds);
    auto InvertedBox = ValidBounds;
    InvertedBox.Min.X = 500.0;
    InvertedBox.Max.X = 100.0;
    InvertedBox.IsValid = 1;
    InvertedBounds.Set_VolumeBounds(InvertedBox);
    TestTrue(TEXT("inverted bounds produce no field"), Get_IsRejected(InvertedBounds));

    auto ZeroBounds = Make_Params(ValidBounds);
    auto ZeroBox = ValidBounds;
    ZeroBox.Max.Y = ZeroBox.Min.Y;
    ZeroBox.IsValid = 1;
    ZeroBounds.Set_VolumeBounds(ZeroBox);
    TestTrue(TEXT("zero-size bounds produce no field"), Get_IsRejected(ZeroBounds));

    auto HugeBounds = Make_Params(ValidBounds);
    auto HugeBox = ValidBounds;
    HugeBox.Max.X = 1.0e20;
    HugeBox.IsValid = 1;
    HugeBounds.Set_VolumeBounds(HugeBox);
    TestTrue(TEXT("bounds needing more than int32 tiles produce no field"), Get_IsRejected(HugeBounds));

    auto HugeConfig = Make_Config();
    HugeConfig.Set_TileSizeUu(TNumericLimits<float>::Max());
    const auto HugeSpan = Make_Params(ValidBounds, HugeConfig);
    TestTrue(TEXT("a tile span whose cell count overflows int32 produces no field"), Get_IsRejected(HugeSpan));

    auto InfiniteConfig = Make_Config();
    InfiniteConfig.Set_TileSizeUu(std::numeric_limits<float>::infinity());
    const auto InfiniteSpan = Make_Params(ValidBounds, InfiniteConfig);
    TestTrue(TEXT("an infinite tile span produces no field"), Get_IsRejected(InfiniteSpan));

    const auto TooManyTiles = Make_Params(
        FBox{FVector::ZeroVector, FVector{20000000.0, 20000000.0, 250.0}});
    TestTrue(TEXT("a finite extent whose rounded tile count overflows int32 produces no field"),
        Get_IsRejected(TooManyTiles));

    auto FloatOverflowZ = Make_Params(ValidBounds);
    auto FloatOverflowZBox = ValidBounds;
    FloatOverflowZBox.Max.Z = static_cast<double>(TNumericLimits<float>::Max()) * 2.0;
    FloatOverflowZBox.IsValid = 1;
    FloatOverflowZ.Set_VolumeBounds(FloatOverflowZBox);
    TestTrue(TEXT("a finite Z range not representable by field floats produces no field"),
        Get_IsRejected(FloatOverflowZ));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#if WITH_EDITOR
IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_VolumeAuthoring_JoltOverrideRestoresNestedScopes,
    "CkTests.UnitTests.CkGroundNav.VolumeAuthoring.JoltOverrideRestoresNestedScopes",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_VolumeAuthoring_JoltOverrideRestoresNestedScopes::RunTest(const FString& Parameters)
{
    auto* Settings = GetMutableDefault<UCk_Jolt_ProjectSettings_UE>();
    if (NOT TestNotNull(TEXT("the Jolt settings CDO resolves"), Settings))
    { return false; }

    const auto Original = Settings->Get_EditorStaticWorldMode();
    {
        FCk_Jolt_ScopedEditorStaticWorldModeOverride Outer{ECk_Jolt_EditorStaticWorldMode::Disabled};
        TestTrue(TEXT("the outer override applies"), Outer.Get_IsApplied());
        TestEqual(TEXT("the outer override selects Disabled"), Settings->Get_EditorStaticWorldMode(),
            ECk_Jolt_EditorStaticWorldMode::Disabled);

        {
            FCk_Jolt_ScopedEditorStaticWorldModeOverride Inner{ECk_Jolt_EditorStaticWorldMode::LiveExtract};
            TestTrue(TEXT("the inner override applies"), Inner.Get_IsApplied());
            TestEqual(TEXT("the inner override selects LiveExtract"), Settings->Get_EditorStaticWorldMode(),
                ECk_Jolt_EditorStaticWorldMode::LiveExtract);
        }

        TestEqual(TEXT("the inner scope restores the outer setting"), Settings->Get_EditorStaticWorldMode(),
            ECk_Jolt_EditorStaticWorldMode::Disabled);
    }
    TestEqual(TEXT("the outer scope restores the original setting"), Settings->Get_EditorStaticWorldMode(), Original);

    AddExpectedError(TEXT("Jolt editor static-world overrides require the game thread and a valid mode."),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);
    FCk_Jolt_ScopedEditorStaticWorldModeOverride Invalid{
        static_cast<ECk_Jolt_EditorStaticWorldMode>(255)};
    TestFalse(TEXT("an invalid mode does not apply"), Invalid.Get_IsApplied());
    TestEqual(TEXT("an invalid mode does not mutate the setting"), Settings->Get_EditorStaticWorldMode(), Original);

    return true;
}
#endif
