// Content fingerprint.
//
// Two properties are being pinned, and they pull in opposite directions:
//
//   1. EVERY enumerated bake input perturbs the fingerprint. An input that does not is a latent
//      staleness bug — the field would keep a result computed under inputs that have since changed.
//   2. Geometry SUBMISSION ORDER does not. Otherwise an unrelated change to collection order would
//      force a full rebake of a world that did not change.
//
// The frozen input enumeration lives in CkGroundNav_Fingerprint.h. A new bake input means a new case
// here in the same change.

#include "CkGroundNav/Bake/CkGroundNav_Fingerprint.h"
#include "CkGroundNav/Bake/CkGroundNav_MarkupTypes.h"

#include "CkShapes/Box/CkShapeBox_Fragment_Data.h"
#include "CkShapes/Sphere/CkShapeSphere_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

#include "NativeGameplayTags.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_CkTests_GroundNav_Fingerprint_AreaA, "CkTests.GroundNav.Fingerprint.AreaA");
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_CkTests_GroundNav_Fingerprint_AreaB, "CkTests.GroundNav.Fingerprint.AreaB");

namespace ck_test_groundnav_fingerprint
{
    using ck::groundnav::Get_ContentFingerprint;

    auto Make_Region() -> FBox
    {
        return FBox{FVector{0.0, 0.0, 0.0}, FVector{1000.0, 1000.0, 400.0}};
    }

    auto Make_Geometry() -> FCk_GroundNav_GeometryBatch
    {
        auto Batch = FCk_GroundNav_GeometryBatch{};

        Batch.Add_Box(FBox{FVector{0.0, 0.0, 0.0}, FVector{500.0, 500.0, 10.0}});
        Batch.Add_Box(FBox{FVector{600.0, 0.0, 0.0}, FVector{900.0, 400.0, 10.0}});

        return Batch;
    }

    auto Get_Baseline() -> ck::groundnav::FCk_GroundNav_ContentFingerprint
    {
        return Get_ContentFingerprint(Make_Geometry(), Make_Region(),
            FCk_GroundNav_BakeConfig{}, FCk_GroundNav_AgentProfile{});
    }

    // Two volumes over the fixture's ground, one of each kind, so a perturbation of either half of the
    // markup contract is visible.
    auto Make_Markup(
        int32                    InId,
        ECk_GroundNav_MarkupKind InKind) -> FCk_GroundNav_MarkupRecord
    {
        auto Record = FCk_GroundNav_MarkupRecord{
            InId,
            FCk_AnyShape{FCk_ShapeBox_Dimensions{FVector{50.0, 50.0, 50.0}}},
            FTransform{FVector{100.0 * static_cast<double>(InId), 100.0, 10.0}},
            InKind};

        Record.Set_AreaTag(TAG_CkTests_GroundNav_Fingerprint_AreaA);
        Record.Set_CostMultiplier(2.0f);

        return Record;
    }

    auto Make_Markups() -> TArray<FCk_GroundNav_MarkupRecord>
    {
        return TArray<FCk_GroundNav_MarkupRecord>{
            Make_Markup(1, ECk_GroundNav_MarkupKind::Walkability),
            Make_Markup(2, ECk_GroundNav_MarkupKind::Cost)};
    }

    auto Get_Print(
        TConstArrayView<FCk_GroundNav_MarkupRecord> InMarkups)
        -> ck::groundnav::FCk_GroundNav_ContentFingerprint
    {
        return Get_ContentFingerprint(Make_Geometry(), Make_Region(),
            FCk_GroundNav_BakeConfig{}, FCk_GroundNav_AgentProfile{}, InMarkups);
    }

    auto Get_MarkupBaseline() -> ck::groundnav::FCk_GroundNav_ContentFingerprint
    {
        return Get_Print(Make_Markups());
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Fingerprint_IsStableAndOrderIndependent,
    "CkTests.UnitTests.CkGroundNav.Bake.Fingerprint_IsStableAndOrderIndependent",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Fingerprint_IsStableAndOrderIndependent::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_fingerprint;

    TestTrue(TEXT("the same inputs fingerprint identically across calls"),
        Get_Baseline() == Get_Baseline());

    // Same two boxes, submitted in the opposite order.
    auto Reordered = FCk_GroundNav_GeometryBatch{};
    Reordered.Add_Box(FBox{FVector{600.0, 0.0, 0.0}, FVector{900.0, 400.0, 10.0}});
    Reordered.Add_Box(FBox{FVector{0.0, 0.0, 0.0}, FVector{500.0, 500.0, 10.0}});

    const auto ReorderedPrint = Get_ContentFingerprint(Reordered, Make_Region(),
        FCk_GroundNav_BakeConfig{}, FCk_GroundNav_AgentProfile{});

    TestTrue(TEXT("submission ORDER does not change the fingerprint"),
        ReorderedPrint == Get_Baseline());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Fingerprint_EveryEnumeratedInputPerturbsIt,
    "CkTests.UnitTests.CkGroundNav.Bake.Fingerprint_EveryEnumeratedInputPerturbsIt",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Fingerprint_EveryEnumeratedInputPerturbsIt::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_fingerprint;

    const auto Baseline = Get_Baseline();

    const auto CheckDiffers = [&](
        const TCHAR*                                          InWhat,
        const ck::groundnav::FCk_GroundNav_ContentFingerprint& InPerturbed) -> void
    {
        TestFalse(FString::Printf(TEXT("perturbing %s changes the fingerprint"), InWhat),
            InPerturbed == Baseline);
    };

    // ---- 1. Geometry ---------------------------------------------------------------------------------
    {
        // One vertex moved by a single unit.
        auto Batch = Make_Geometry();
        Batch._Vertices[0].X += 1.0;

        CheckDiffers(TEXT("a single vertex"),
            Get_ContentFingerprint(Batch, Make_Region(), FCk_GroundNav_BakeConfig{}, FCk_GroundNav_AgentProfile{}));
    }
    {
        // A duplicated triangle. This is the case a XOR-based combiner would silently lose: two
        // identical triangles would cancel, and a doubled surface would fingerprint as no surface.
        auto Batch = Make_Geometry();
        auto A = FVector::ZeroVector;
        auto B = FVector::ZeroVector;
        auto C = FVector::ZeroVector;
        Batch.Get_Triangle(0, A, B, C);
        Batch.Add_Triangle(A, B, C);

        CheckDiffers(TEXT("a duplicated triangle"),
            Get_ContentFingerprint(Batch, Make_Region(), FCk_GroundNav_BakeConfig{}, FCk_GroundNav_AgentProfile{}));
    }
    {
        // Reversed winding is a different world: the surface now faces the other way.
        auto Batch = FCk_GroundNav_GeometryBatch{};
        Batch.Add_Triangle(FVector{0, 0, 0}, FVector{100, 0, 0}, FVector{0, 100, 0});

        auto Reversed = FCk_GroundNav_GeometryBatch{};
        Reversed.Add_Triangle(FVector{0, 0, 0}, FVector{0, 100, 0}, FVector{100, 0, 0});

        const auto Forward = Get_ContentFingerprint(Batch, Make_Region(),
            FCk_GroundNav_BakeConfig{}, FCk_GroundNav_AgentProfile{});
        const auto Backward = Get_ContentFingerprint(Reversed, Make_Region(),
            FCk_GroundNav_BakeConfig{}, FCk_GroundNav_AgentProfile{});

        TestFalse(TEXT("reversing a triangle's winding changes the fingerprint"),
            Forward == Backward);

        // ...but merely rotating which corner is listed first does NOT.
        auto Rotated = FCk_GroundNav_GeometryBatch{};
        Rotated.Add_Triangle(FVector{100, 0, 0}, FVector{0, 100, 0}, FVector{0, 0, 0});

        const auto RotatedPrint = Get_ContentFingerprint(Rotated, Make_Region(),
            FCk_GroundNav_BakeConfig{}, FCk_GroundNav_AgentProfile{});

        TestTrue(TEXT("rotating which corner is listed first does NOT change the fingerprint"),
            RotatedPrint == Forward);
    }

    // ---- 2. Region -----------------------------------------------------------------------------------
    {
        auto Region = Make_Region();
        Region.Max.Z += 1.0;

        CheckDiffers(TEXT("the region"),
            Get_ContentFingerprint(Make_Geometry(), Region, FCk_GroundNav_BakeConfig{}, FCk_GroundNav_AgentProfile{}));
    }

    // ---- 3. Bake config ------------------------------------------------------------------------------
    {
        auto Config = FCk_GroundNav_BakeConfig{};
        Config = FCk_GroundNav_BakeConfig{12.5f, Config.Get_CellHeightUu()};

        CheckDiffers(TEXT("cell size"),
            Get_ContentFingerprint(Make_Geometry(), Make_Region(), Config, FCk_GroundNav_AgentProfile{}));
    }
    {
        auto Config = FCk_GroundNav_BakeConfig{};
        Config = FCk_GroundNav_BakeConfig{Config.Get_CellSizeUu(), 5.0f};

        CheckDiffers(TEXT("cell height"),
            Get_ContentFingerprint(Make_Geometry(), Make_Region(), Config, FCk_GroundNav_AgentProfile{}));
    }

    // ---- 4. Agent profile ----------------------------------------------------------------------------
    {
        auto Profile = FCk_GroundNav_AgentProfile{};
        Profile.Set_MaxSlopeDegrees(40.0f);

        CheckDiffers(TEXT("max slope"),
            Get_ContentFingerprint(Make_Geometry(), Make_Region(), FCk_GroundNav_BakeConfig{}, Profile));
    }
    {
        auto Profile = FCk_GroundNav_AgentProfile{};
        Profile.Set_MaxSlopeChangeDegrees(20.0f);

        CheckDiffers(TEXT("max slope change"),
            Get_ContentFingerprint(Make_Geometry(), Make_Region(), FCk_GroundNav_BakeConfig{}, Profile));
    }
    {
        auto Profile = FCk_GroundNav_AgentProfile{};
        Profile.Set_StepHeightUu(35.0f);

        CheckDiffers(TEXT("step height"),
            Get_ContentFingerprint(Make_Geometry(), Make_Region(), FCk_GroundNav_BakeConfig{}, Profile));
    }
    {
        auto Profile = FCk_GroundNav_AgentProfile{};
        Profile.Set_LedgeSensitivity(0.5f);

        CheckDiffers(TEXT("ledge sensitivity"),
            Get_ContentFingerprint(Make_Geometry(), Make_Region(), FCk_GroundNav_BakeConfig{}, Profile));
    }
    {
        auto Profile = FCk_GroundNav_AgentProfile{};
        Profile.Set_RoughPerchToleranceUu(3.0f);

        CheckDiffers(TEXT("rough-perch tolerance"),
            Get_ContentFingerprint(Make_Geometry(), Make_Region(), FCk_GroundNav_BakeConfig{}, Profile));
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Fingerprint_EveryMarkupFieldPerturbsIt,
    "CkTests.UnitTests.CkGroundNav.Bake.Fingerprint_EveryMarkupFieldPerturbsIt",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Fingerprint_EveryMarkupFieldPerturbsIt::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_fingerprint;

    const auto Baseline = Get_MarkupBaseline();

    TestFalse(TEXT("submitting markup at all changes the fingerprint"), Baseline == Get_Baseline());

    const auto CheckDiffers = [&](
        const TCHAR*                              InWhat,
        const TArray<FCk_GroundNav_MarkupRecord>& InPerturbed) -> void
    {
        TestFalse(FString::Printf(TEXT("perturbing a markup's %s changes the fingerprint"), InWhat),
            Get_Print(InPerturbed) == Baseline);
    };

    {
        auto Markups = Make_Markups();
        Markups[0] = FCk_GroundNav_MarkupRecord{
            7,
            Markups[0].Get_Shape(),
            Markups[0].Get_WorldTransform(),
            Markups[0].Get_Kind()};
        Markups[0].Set_AreaTag(TAG_CkTests_GroundNav_Fingerprint_AreaA);
        Markups[0].Set_CostMultiplier(2.0f);

        CheckDiffers(TEXT("id"), Markups);
    }
    {
        // Same dimensions where the two types share one, so only the TYPE differs.
        auto Markups = Make_Markups();
        Markups[0] = FCk_GroundNav_MarkupRecord{
            Markups[0].Get_Id(),
            FCk_AnyShape{FCk_ShapeSphere_Dimensions{50.0f}},
            Markups[0].Get_WorldTransform(),
            Markups[0].Get_Kind()};
        Markups[0].Set_AreaTag(TAG_CkTests_GroundNav_Fingerprint_AreaA);
        Markups[0].Set_CostMultiplier(2.0f);

        CheckDiffers(TEXT("shape type"), Markups);
    }
    {
        auto Markups = Make_Markups();
        Markups[0] = FCk_GroundNav_MarkupRecord{
            Markups[0].Get_Id(),
            FCk_AnyShape{FCk_ShapeBox_Dimensions{FVector{50.0, 50.0, 51.0}}},
            Markups[0].Get_WorldTransform(),
            Markups[0].Get_Kind()};
        Markups[0].Set_AreaTag(TAG_CkTests_GroundNav_Fingerprint_AreaA);
        Markups[0].Set_CostMultiplier(2.0f);

        CheckDiffers(TEXT("shape dimensions"), Markups);
    }
    {
        auto Markups = Make_Markups();
        Markups[0] = FCk_GroundNav_MarkupRecord{
            Markups[0].Get_Id(),
            Markups[0].Get_Shape(),
            FTransform{FVector{101.0, 100.0, 10.0}},
            Markups[0].Get_Kind()};
        Markups[0].Set_AreaTag(TAG_CkTests_GroundNav_Fingerprint_AreaA);
        Markups[0].Set_CostMultiplier(2.0f);

        CheckDiffers(TEXT("world transform"), Markups);
    }
    {
        auto Markups = Make_Markups();
        Markups[0].Set_AreaTag(TAG_CkTests_GroundNav_Fingerprint_AreaB);

        CheckDiffers(TEXT("area tag"), Markups);
    }
    {
        auto Markups = Make_Markups();
        Markups[0] = FCk_GroundNav_MarkupRecord{
            Markups[0].Get_Id(),
            Markups[0].Get_Shape(),
            Markups[0].Get_WorldTransform(),
            ECk_GroundNav_MarkupKind::Cost};
        Markups[0].Set_AreaTag(TAG_CkTests_GroundNav_Fingerprint_AreaA);
        Markups[0].Set_CostMultiplier(2.0f);

        CheckDiffers(TEXT("kind"), Markups);
    }
    {
        auto Markups = Make_Markups();
        Markups[1].Set_CostMultiplier(3.0f);

        CheckDiffers(TEXT("cost multiplier"), Markups);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Fingerprint_MarkupOrderAndDisabledRecordsDoNotCount,
    "CkTests.UnitTests.CkGroundNav.Bake.Fingerprint_MarkupOrderAndDisabledRecordsDoNotCount",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Fingerprint_MarkupOrderAndDisabledRecordsDoNotCount::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_fingerprint;

    const auto Baseline = Get_MarkupBaseline();

    {
        // The same two volumes, submitted the other way round. Canonical id order is what makes this
        // hold, and holding it is what stops an unrelated change to collection order forcing a rebake.
        auto Reordered = Make_Markups();
        Reordered.Swap(0, 1);

        TestTrue(TEXT("record ORDER does not change the fingerprint"),
            Get_Print(Reordered) == Baseline);
    }

    {
        // A disabled record decides nothing about the field, so its presence must not force a rebuild.
        auto WithDisabled = Make_Markups();
        WithDisabled.Emplace(Make_Markup(3, ECk_GroundNav_MarkupKind::Cost));
        WithDisabled.Last().Set_Enable(ECk_EnableDisable::Disable);

        TestTrue(TEXT("a disabled record does not change the fingerprint"),
            Get_Print(WithDisabled) == Baseline);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
