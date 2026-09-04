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

#include "CkCore/Algorithms/CkAlgorithms.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/World/CkEcsWorld.h"

#include "CkGroundNav/Bake/CkGroundNav_Fingerprint.h"
#include "CkGroundNav/Bake/CkGroundNav_LinkTypes.h"
#include "CkGroundNav/Bake/CkGroundNav_MarkupTypes.h"
#include "CkGroundNav/Volume/CkGroundNavVolume_Utils.h"

#include "CkShapes/Box/CkShapeBox_Fragment_Data.h"
#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"
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
    using ck::groundnav::Get_InputFingerprint;

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

    // Two links over the fixture's ground, so a perturbation of any field of either is visible.
    auto Make_Link(
        int32 InId) -> FCk_GroundNav_LinkRecord
    {
        auto Record = FCk_GroundNav_LinkRecord{
            InId,
            FVector{100.0 * static_cast<double>(InId), 100.0, 10.0},
            FVector{100.0 * static_cast<double>(InId), 300.0, 10.0}};

        Record.Set_AreaTag(TAG_CkTests_GroundNav_Fingerprint_AreaA);
        Record.Set_UserTypeTag(TAG_CkTests_GroundNav_Fingerprint_AreaA);
        Record.Set_CostMultiplierForward(2.0f);
        Record.Set_CostMultiplierBackward(3.0f);
        Record.Set_ClearanceUu(60.0f);

        return Record;
    }

    auto Make_Links() -> TArray<FCk_GroundNav_LinkRecord>
    {
        return TArray<FCk_GroundNav_LinkRecord>{Make_Link(1), Make_Link(2)};
    }

    auto Get_LinkPrint(
        TConstArrayView<FCk_GroundNav_LinkRecord> InLinks)
        -> ck::groundnav::FCk_GroundNav_ContentFingerprint
    {
        return Get_ContentFingerprint(Make_Geometry(), Make_Region(),
            FCk_GroundNav_BakeConfig{}, FCk_GroundNav_AgentProfile{}, {}, InLinks);
    }

    auto Get_LinkBaseline() -> ck::groundnav::FCk_GroundNav_ContentFingerprint
    {
        return Get_LinkPrint(Make_Links());
    }

    // The authored variant list in the shape the fingerprint takes it: a tag NAME beside its profile.
    // A name rather than the tag itself because a tag is an index this process alone agrees on, and
    // because the bake layer holds no volume concepts to take the authored type through.
    auto Make_Variant(
        const FName& InTagName,
        float        InStepHeightUu) -> TPair<FName, FCk_GroundNav_AgentProfile>
    {
        auto Profile = FCk_GroundNav_AgentProfile{};
        Profile.Set_StepHeightUu(InStepHeightUu);

        return TPair<FName, FCk_GroundNav_AgentProfile>{InTagName, Profile};
    }

    auto Make_Variants() -> TArray<TPair<FName, FCk_GroundNav_AgentProfile>>
    {
        return TArray<TPair<FName, FCk_GroundNav_AgentProfile>>{
            Make_Variant(TEXT("CkTests.GroundNav.Fingerprint.Crawler"), 30.0f),
            Make_Variant(TEXT("CkTests.GroundNav.Fingerprint.Strider"), 60.0f)};
    }

    auto Get_VariantPrint(
        TConstArrayView<TPair<FName, FCk_GroundNav_AgentProfile>> InVariants)
        -> ck::groundnav::FCk_GroundNav_ContentFingerprint
    {
        return Get_ContentFingerprint(Make_Geometry(), Make_Region(),
            FCk_GroundNav_BakeConfig{}, FCk_GroundNav_AgentProfile{}, {}, {},
            FCk_GroundNav_MergeTunables{}, 0.0f, InVariants);
    }

    auto Get_AuthoredInputPrint(
        float                                                     InMaxClearanceUu,
        TConstArrayView<TPair<FName, FCk_GroundNav_AgentProfile>> InVariants)
        -> ck::groundnav::FCk_GroundNav_ContentFingerprint
    {
        return Get_InputFingerprint(Make_Region(), FCk_GroundNav_BakeConfig{},
            FCk_GroundNav_AgentProfile{}, Make_Markups(), Make_Links(),
            FCk_GroundNav_MergeTunables{}, InMaxClearanceUu, InVariants);
    }

    auto Get_ContentPrintOverWorld(
        uint64                                                    InGeometryHash,
        float                                                     InMaxClearanceUu,
        TConstArrayView<TPair<FName, FCk_GroundNav_AgentProfile>> InVariants)
        -> ck::groundnav::FCk_GroundNav_ContentFingerprint
    {
        return Get_ContentFingerprint(InGeometryHash, Make_Region(), FCk_GroundNav_BakeConfig{},
            FCk_GroundNav_AgentProfile{}, Make_Markups(), Make_Links(),
            FCk_GroundNav_MergeTunables{}, InMaxClearanceUu, InVariants);
    }

    // A volume for the two reads below and nothing else. It never bakes - the geometry backend needs a
    // physics world, which a headless registry has none of - so what is pinned here is the shape of the
    // answers before any build has published, which is exactly the state a caller polls in.
    auto Make_VolumeParams() -> FCk_Fragment_GroundNavVolume_ParamsData
    {
        auto Config = FCk_GroundNav_BakeConfig{25.0f, 10.0f};
        Config.Set_TileSizeUu(400.0f);

        const auto Profile = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{70.0f, 20.0f}}};

        const auto Bounds = FBox{FVector{0.0, 0.0, -50.0}, FVector{800.0, 800.0, 300.0}};

        return FCk_Fragment_GroundNavVolume_ParamsData{Bounds, Config, Profile};
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

    // The batch-taking form is the hash-taking one with item 1 reduced by Get_GeometryHash, and a
    // caller that reduces its own geometry has to land on the identical print - otherwise a tiled
    // build, which never holds a whole region's triangles, could not be compared against one that did.
    TestTrue(TEXT("reducing the geometry first fingerprints identically to handing over the batch"),
        Get_ContentFingerprint(ck::groundnav::Get_GeometryHash(Make_Geometry()), Make_Region(),
            FCk_GroundNav_BakeConfig{}, FCk_GroundNav_AgentProfile{}) == Get_Baseline());

    // And the reduction carries the order independence with it, rather than the caller above having
    // happened to reduce two batches that were already equal.
    TestTrue(TEXT("and the reduction is itself order-independent"),
        ck::groundnav::Get_GeometryHash(Reordered) ==
        ck::groundnav::Get_GeometryHash(Make_Geometry()));

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

    // ---- 7. Merge tunables ---------------------------------------------------------------------------
    // The struct is read-only past construction, so each case is a fresh one differing from the
    // defaults in exactly one member.
    {
        CheckDiffers(TEXT("the plane-fit tolerance"),
            Get_ContentFingerprint(Make_Geometry(), Make_Region(), FCk_GroundNav_BakeConfig{},
                FCk_GroundNav_AgentProfile{}, {}, {}, FCk_GroundNav_MergeTunables{25.0f, 10.0f}));
    }
    {
        CheckDiffers(TEXT("the normal cone"),
            Get_ContentFingerprint(Make_Geometry(), Make_Region(), FCk_GroundNav_BakeConfig{},
                FCk_GroundNav_AgentProfile{}, {}, {}, FCk_GroundNav_MergeTunables{10.0f, 25.0f}));
    }

    // ---- 8. Clearance cap ----------------------------------------------------------------------------
    {
        CheckDiffers(TEXT("the clearance cap"),
            Get_ContentFingerprint(Make_Geometry(), Make_Region(), FCk_GroundNav_BakeConfig{},
                FCk_GroundNav_AgentProfile{}, {}, {}, FCk_GroundNav_MergeTunables{}, 200.0f));
    }

    // The other half of a perturbation case, and the one that catches a hash that folds in something
    // besides its arguments: the two trailing inputs spelled out AT THEIR DEFAULTS must fingerprint
    // exactly as omitting them does, or a caller could not compare two prints at all.
    TestTrue(TEXT("the trailing inputs spelled out at their defaults fingerprint as omitting them"),
        Get_ContentFingerprint(Make_Geometry(), Make_Region(), FCk_GroundNav_BakeConfig{},
            FCk_GroundNav_AgentProfile{}, {}, {}, FCk_GroundNav_MergeTunables{10.0f, 10.0f}, 0.0f) ==
        Get_Baseline());

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

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Fingerprint_EveryLinkFieldPerturbsIt,
    "CkTests.UnitTests.CkGroundNav.Bake.Fingerprint_EveryLinkFieldPerturbsIt",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Fingerprint_EveryLinkFieldPerturbsIt::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_fingerprint;

    const auto Baseline = Get_LinkBaseline();

    TestFalse(TEXT("submitting links at all changes the fingerprint"), Baseline == Get_Baseline());

    const auto CheckDiffers = [&](
        const TCHAR*                            InWhat,
        const TArray<FCk_GroundNav_LinkRecord>& InPerturbed) -> void
    {
        TestFalse(FString::Printf(TEXT("perturbing a link's %s changes the fingerprint"), InWhat),
            Get_LinkPrint(InPerturbed) == Baseline);
    };

    // The identity and the endpoints are read-only on the record, so a perturbation of any of the three
    // is a fresh record carrying every other authored value forward unchanged.
    const auto Rebuild = [](
        const FCk_GroundNav_LinkRecord& InFrom,
        int32                           InId,
        const FVector&                  InStart,
        const FVector&                  InEnd) -> FCk_GroundNav_LinkRecord
    {
        auto Record = FCk_GroundNav_LinkRecord{InId, InStart, InEnd};

        Record.Set_Direction(InFrom.Get_Direction());
        Record.Set_CostMultiplierForward(InFrom.Get_CostMultiplierForward());
        Record.Set_CostMultiplierBackward(InFrom.Get_CostMultiplierBackward());
        Record.Set_ClearanceUu(InFrom.Get_ClearanceUu());
        Record.Set_AreaTag(InFrom.Get_AreaTag());
        Record.Set_UserTypeTag(InFrom.Get_UserTypeTag());
        Record.Set_ProjectionMode(InFrom.Get_ProjectionMode());
        Record.Set_ProjectionHorizontalExtentUu(InFrom.Get_ProjectionHorizontalExtentUu());
        Record.Set_ProjectionVerticalExtentUu(InFrom.Get_ProjectionVerticalExtentUu());

        return Record;
    };

    {
        auto Links = Make_Links();
        Links[0] = Rebuild(Links[0], 7, Links[0].Get_Start(), Links[0].Get_End());

        CheckDiffers(TEXT("id"), Links);
    }
    {
        auto Links = Make_Links();
        Links[0] = Rebuild(Links[0], Links[0].Get_Id(),
            Links[0].Get_Start() + FVector{1.0, 0.0, 0.0}, Links[0].Get_End());

        CheckDiffers(TEXT("start point"), Links);
    }
    {
        auto Links = Make_Links();
        Links[0] = Rebuild(Links[0], Links[0].Get_Id(),
            Links[0].Get_Start(), Links[0].Get_End() + FVector{0.0, 1.0, 0.0});

        CheckDiffers(TEXT("end point"), Links);
    }
    {
        // The two ends SWAPPED: the same pair of points, and a different link, because the direction
        // and the two multipliers are stated relative to which end is the start.
        auto Links = Make_Links();
        Links[0] = Rebuild(Links[0], Links[0].Get_Id(), Links[0].Get_End(), Links[0].Get_Start());

        CheckDiffers(TEXT("endpoint order"), Links);
    }
    {
        auto Links = Make_Links();
        Links[0].Set_Direction(ECk_GroundNav_LinkDirection::Forward);

        CheckDiffers(TEXT("direction"), Links);
    }
    {
        auto Links = Make_Links();
        Links[0].Set_CostMultiplierForward(5.0f);

        CheckDiffers(TEXT("forward cost multiplier"), Links);
    }
    {
        auto Links = Make_Links();
        Links[0].Set_CostMultiplierBackward(5.0f);

        CheckDiffers(TEXT("backward cost multiplier"), Links);
    }
    {
        auto Links = Make_Links();
        Links[0].Set_ClearanceUu(30.0f);

        CheckDiffers(TEXT("clearance"), Links);
    }
    {
        auto Links = Make_Links();
        Links[0].Set_AreaTag(TAG_CkTests_GroundNav_Fingerprint_AreaB);

        CheckDiffers(TEXT("area tag"), Links);
    }
    {
        auto Links = Make_Links();
        Links[0].Set_UserTypeTag(TAG_CkTests_GroundNav_Fingerprint_AreaB);

        CheckDiffers(TEXT("user type tag"), Links);
    }
    {
        auto Links = Make_Links();
        Links[0].Set_ProjectionMode(ECk_NavSurface_ProjectionMode::Down);

        CheckDiffers(TEXT("projection mode"), Links);
    }
    {
        auto Links = Make_Links();
        Links[0].Set_ProjectionHorizontalExtentUu(75.0f);

        CheckDiffers(TEXT("projection horizontal extent"), Links);
    }
    {
        auto Links = Make_Links();
        Links[0].Set_ProjectionVerticalExtentUu(150.0f);

        CheckDiffers(TEXT("projection vertical extent"), Links);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Fingerprint_DisabledLinksDoNotCount,
    "CkTests.UnitTests.CkGroundNav.Bake.Fingerprint_DisabledLinksDoNotCount",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Fingerprint_DisabledLinksDoNotCount::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_fingerprint;

    {
        // A disabled link decides nothing about the field, so a list holding only disabled links must
        // fingerprint exactly as no links at all - otherwise switching one off would force a rebake.
        auto AllDisabled = Make_Links();

        for (auto& Link : AllDisabled)
        { Link.Set_Enable(ECk_EnableDisable::Disable); }

        TestTrue(TEXT("links that are all disabled fingerprint as no links at all"),
            Get_LinkPrint(AllDisabled) == Get_Baseline());
    }

    {
        auto WithDisabled = Make_Links();
        WithDisabled.Emplace(Make_Link(3));
        WithDisabled.Last().Set_Enable(ECk_EnableDisable::Disable);

        TestTrue(TEXT("a disabled link does not change the fingerprint"),
            Get_LinkPrint(WithDisabled) == Get_LinkBaseline());
    }

    return true;
}


// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Fingerprint_ProfileVariantsPerturbIt,
    "CkTests.UnitTests.CkGroundNav.Bake.Fingerprint_ProfileVariantsPerturbIt",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Fingerprint_ProfileVariantsPerturbIt::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_fingerprint;

    const auto Baseline = Get_VariantPrint(Make_Variants());

    TestTrue(TEXT("the same variant list fingerprints identically"),
        Get_VariantPrint(Make_Variants()) == Baseline);

    TestFalse(TEXT("a volume authoring no variant at all fingerprints differently"),
        Get_VariantPrint({}) == Baseline);

    {
        auto Added = Make_Variants();
        Added.Emplace(Make_Variant(TEXT("CkTests.GroundNav.Fingerprint.Wader"), 90.0f));

        TestFalse(TEXT("adding a variant changes the fingerprint"), Get_VariantPrint(Added) == Baseline);
    }

    {
        auto Edited = Make_Variants();
        Edited[0].Value.Set_StepHeightUu(45.0f);

        TestFalse(TEXT("editing a variant's profile changes the fingerprint"),
            Get_VariantPrint(Edited) == Baseline);
    }

    {
        auto Renamed = Make_Variants();
        Renamed[0].Key = TEXT("CkTests.GroundNav.Fingerprint.Renamed");

        TestFalse(TEXT("renaming a variant's tag changes the fingerprint"),
            Get_VariantPrint(Renamed) == Baseline);
    }

    {
        // Authored ORDER is part of the item: a volume bakes its variants in the order it lists them,
        // so the same pairs listed the other way round are a different set of publishes.
        auto Swapped = Make_Variants();
        Swap(Swapped[0], Swapped[1]);

        TestFalse(TEXT("swapping two variants' order changes the fingerprint"),
            Get_VariantPrint(Swapped) == Baseline);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Fingerprint_InputPrintIsTheContentPrintWithoutTheGeometry,
    "CkTests.UnitTests.CkGroundNav.Bake.Fingerprint_InputPrintIsTheContentPrintWithoutTheGeometry",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Fingerprint_InputPrintIsTheContentPrintWithoutTheGeometry::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_fingerprint;

    constexpr auto ClearanceCapUu = 200.0f;
    constexpr auto MovedClearanceCapUu = 240.0f;

    // Two callers over one set of authored inputs and two different worlds.
    constexpr auto FirstWorld = uint64{0x0000000000001111};
    constexpr auto SecondWorld = uint64{0x0000000000002222};

    const auto Variants = Make_Variants();

    const auto FirstContent = Get_ContentPrintOverWorld(FirstWorld, ClearanceCapUu, Variants);
    const auto SecondContent = Get_ContentPrintOverWorld(SecondWorld, ClearanceCapUu, Variants);

    TestFalse(TEXT("two worlds under the same authored inputs are two content fingerprints"),
        FirstContent == SecondContent);

    const auto InputPrint = Get_AuthoredInputPrint(ClearanceCapUu, Variants);

    TestTrue(TEXT("but one input fingerprint, which is the same enumeration with item 1 left out"),
        InputPrint == Get_AuthoredInputPrint(ClearanceCapUu, Variants));

    // And it is not merely constant: every authored item still reaches it, which is what makes the two
    // questions - has the world moved, have the inputs moved - separately answerable.
    TestFalse(TEXT("moving an authored input moves the input fingerprint"),
        Get_AuthoredInputPrint(MovedClearanceCapUu, Variants) == InputPrint);

    TestFalse(TEXT("and so does moving the variant list"),
        Get_AuthoredInputPrint(ClearanceCapUu, {}) == InputPrint);

    TestFalse(TEXT("an authored input that moved also moves the content fingerprint"),
        Get_ContentPrintOverWorld(FirstWorld, MovedClearanceCapUu, Variants) == FirstContent);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Fingerprint_PublishedIdentityMovesWhenARecordIsAdded,
    "CkTests.UnitTests.CkGroundNav.Bake.Fingerprint_PublishedIdentityMovesWhenARecordIsAdded",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Fingerprint_PublishedIdentityMovesWhenARecordIsAdded::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_fingerprint;

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_VolumeParams());

    if (NOT TestTrue(TEXT("the volume composes"), ck::IsValid(Volume)))
    { return false; }

    // The authored half of the identity every publish stamps, assembled from the volume's own params
    // the way the publishers assemble it. A published field cannot be staged headless - the geometry
    // backend needs a physics world, and the built-field fragment is writable only by the processors
    // that publish - so what is pinned is the input half, which is the half that moves when a record
    // does.
    const auto& Params = Volume.Get<ck::FFragment_GroundNavVolume_Params>();

    const auto Get_Identity =
        [&Params](TConstArrayView<FCk_GroundNav_MarkupRecord> InRecords)
        -> ck::groundnav::FCk_GroundNav_ContentFingerprint
        {
            const auto Variants = ck::algo::Transform<TArray<TPair<FName, FCk_GroundNav_AgentProfile>>>(
                Params.Get_ProfileVariants(),
                [](const FCk_GroundNav_ProfileVariant& InVariant) -> TPair<FName, FCk_GroundNav_AgentProfile>
                {
                    return TPair<FName, FCk_GroundNav_AgentProfile>{
                        InVariant.Get_ProfileTag().GetTagName(), InVariant.Get_Profile()};
                });

            return Get_InputFingerprint(Params.Get_VolumeBounds(), Params.Get_Config(),
                Params.Get_Profile(), InRecords, {}, Params.Get_MergeTunables(),
                Params.Get_MaxClearanceUu(), Variants);
        };

    const auto Unpainted = Get_Identity({});

    TestTrue(TEXT("recomputing the identity over the same records answers the same value"),
        Get_Identity({}) == Unpainted);

    const auto Painted = Get_Identity(Make_Markups());

    TestFalse(TEXT("adding records moves it"), Painted == Unpainted);

    TestTrue(TEXT("and it recomputes to the same value while those records stand"),
        Get_Identity(Make_Markups()) == Painted);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Fingerprint_AnUnbuiltVolumeHasNoBakeIdentity,
    "CkTests.UnitTests.CkGroundNav.Bake.Fingerprint_AnUnbuiltVolumeHasNoBakeIdentity",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Fingerprint_AnUnbuiltVolumeHasNoBakeIdentity::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_fingerprint;

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, Make_VolumeParams());

    if (NOT TestTrue(TEXT("the volume composes"), ck::IsValid(Volume)))
    { return false; }

    // A volume that has published nothing has no bake for an identity to be OF. Zero rather than the
    // print of its own params, which would name a bake that never ran.
    TestEqual(TEXT("an unbuilt volume reports no bake fingerprint"),
        UCk_Utils_GroundNavVolume_UE::Get_BuildFingerprint(Volume), static_cast<int64>(0));

    TestFalse(TEXT("and is not build-current, because there is no build for its inputs to be current with"),
        UCk_Utils_GroundNavVolume_UE::Get_IsBuildCurrent(Volume));

    // A caller that cannot name a volume is asking about no ground, so both reads answer it the way
    // they answer an unbuilt one rather than ensuring.
    TestEqual(TEXT("an invalid volume handle reports no bake fingerprint"),
        UCk_Utils_GroundNavVolume_UE::Get_BuildFingerprint(FCk_Handle_GroundNavVolume{}),
        static_cast<int64>(0));

    TestFalse(TEXT("and is not build-current"),
        UCk_Utils_GroundNavVolume_UE::Get_IsBuildCurrent(FCk_Handle_GroundNavVolume{}));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
