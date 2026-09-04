// One bake, N agent profiles.
//
// The claim under test is that a profile variant costs a second BAKE and not a second geometry
// collection: the tile is still the resumable unit, its halo geometry is collected once, and every
// profile is baked out of that one batch before the resume point moves. The probe counter cannot see
// that — a probe is a cell or span read inside a tile's bake, so N profiles spend N times as many of
// them whichever way the geometry arrived — which is why _GeometryFetches exists and is what these
// cases assert on.
//
// The other half is that the variants are genuinely different worlds to walk in. Step height is the
// cleanest lever: the ledge filter demotes a span whose neighbour drops further than one step, so a
// riser between the two profiles' step heights is ground one of them can stand on and the other
// cannot, out of the same triangles.
//
// The bake cases below are pure value logic over the stub backend: no world, no registry, no physics.
// The cases from DuplicateOrEmptyVariantTagIsRefused onwards are about the VOLUME and the world-field
// registry instead - which profile a query resolves to - and take a registry, and for the registry
// half a UWorld, because that is what the registry is keyed on.
//
// The last two are about what a variant does to the consumers of a publish: which field a route already
// planned is measured against when only that route's profile moved, and what the surface revision does
// when a variant is dropped.

#include "CkCore/Time/CkTime.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Request/CkRequest_Completion.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"
#include "CkEcs/World/CkEcsWorld.h"

#include "CkGroundNav/Backend/CkGroundNav_GeometryBackend_Stub.h"
#include "CkGroundNav/Bake/CkGroundNav_Fingerprint.h"
#include "CkGroundNav/Facade/CkGroundNav_WorldFieldRegistry.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Field/CkGroundNav_FieldBuild.h"
#include "CkGroundNav/Path/CkGroundNavPath_Invalidate_Processor.h"
#include "CkGroundNav/Path/CkGroundNavPath_Processor.h"
#include "CkGroundNav/Path/CkGroundNavPath_Utils.h"
#include "CkGroundNav/Volume/CkGroundNavVolume_Processor.h"
#include "CkGroundNav/Volume/CkGroundNavVolume_Utils.h"

#include "CkNavigation/NavSurface/CkNavSurface_Fragment.h"
#include "CkNavigation/NavSurface/CkNavSurface_ProviderTable.h"
#include "CkNavigation/NavSurface/CkNavSurface_Utils.h"

#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "Test_GroundNav_FieldEquality.h"

#include "../CkTest_CompletionListener.h"
#include "../CkUnitTest_Common.h"

#include <Engine/World.h>
#include <NativeGameplayTags.h>
#include <UObject/StrongObjectPtr.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

// The tag one authored variant is named by. Registered natively here rather than in an ini, so the
// AngelScript pin over the same feature can resolve it by name without the corpus carrying a data
// asset for one test's sake.
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_CkTests_GroundNav_Profile_Crawler, "CkTests.GroundNav.Profile.Crawler");

// A tag no volume in this file ever authors a variant for. Its whole job is to be asked about.
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_CkTests_GroundNav_Profile_Swimmer, "CkTests.GroundNav.Profile.Swimmer");

namespace ck_test_groundnav_profilevariants
{
    using ck::groundnav::DoBake_Field;
    using ck::groundnav::FCk_GroundNav_Epoch;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldBuildState;
    using ck::groundnav::FCk_GroundNav_FieldParams;
    using ck::groundnav::FCk_GroundNav_GeometryBackend_Stub;
    using ck::groundnav::Get_CompletedField;
    using ck::groundnav::Get_CompletedFields;
    using ck::groundnav::Get_ContentFingerprint;
    using ck::groundnav::Request_AdvanceBuild;
    using ck::groundnav::Request_BeginBuild;
    using ck::groundnav::Request_BeginBuild_MultiProfile;

    constexpr auto kCellSize = 25.0f;
    constexpr auto kCellHeight = 10.0f;
    constexpr auto kTileSize = 400.0f;
    constexpr auto kMaxClearance = 100.0f;

    constexpr auto kMinZ = -50.0f;
    constexpr auto kMaxZ = 300.0f;

    constexpr auto kDivisions = 2;

    // The riser sits strictly between the two step heights, so it is the one thing the two profiles
    // disagree about and the disagreement is not a matter of a cell height either way.
    constexpr auto kLowStepHeightUu = 40.0f;
    constexpr auto kStepRiseZ = 60.0;
    constexpr auto kHighStepHeightUu = 80.0f;

    auto Make_Profile(
        float InStepHeightUu) -> FCk_GroundNav_AgentProfile
    {
        auto Profile = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{70.0f, 20.0f}}};

        Profile.Set_StepHeightUu(InStepHeightUu);

        // Left at the conservative default rather than switched off as the other bake fixtures do:
        // the ledge filter is where step height decides the walkable SET, so a fixture that disabled
        // it would bake two identical fields and pin nothing.
        return Profile;
    }

    auto Make_Params(
        const FCk_GroundNav_AgentProfile& InProfile) -> FCk_GroundNav_FieldParams
    {
        auto Config = FCk_GroundNav_BakeConfig{kCellSize, kCellHeight};
        Config.Set_TileSizeUu(kTileSize);

        auto Params = FCk_GroundNav_FieldParams{};

        Params._OriginXY = FVector2D::ZeroVector;
        Params._Divisions = FIntPoint{kDivisions, kDivisions};
        Params._MinZUu = kMinZ;
        Params._MaxZUu = kMaxZ;
        Params._Config = Config;
        Params._Profile = InProfile;
        Params._MaxClearanceUu = kMaxClearance;

        return Params;
    }

    auto Make_LowStepParams() -> FCk_GroundNav_FieldParams
    {
        return Make_Params(Make_Profile(kLowStepHeightUu));
    }

    auto Make_HighStepParams() -> FCk_GroundNav_FieldParams
    {
        return Make_Params(Make_Profile(kHighStepHeightUu));
    }

    auto Make_BothParams() -> TArray<FCk_GroundNav_FieldParams>
    {
        return TArray<FCk_GroundNav_FieldParams>{Make_LowStepParams(), Make_HighStepParams()};
    }

    /**
     * Floor reaching well past the field in every direction so no tile's halo is answering about the
     * edge of the fixture, with one raised slab interior to the first tile.
     *
     * The slab's underside lies flush on the floor, which is what makes the ground beneath it covered
     * rather than open — the closed-collision contract the whole bake reads under.
     */
    auto Make_StepScene() -> TArray<FBox>
    {
        auto Boxes = TArray<FBox>{
            FBox{FVector{-300.0, -300.0, -10.0}, FVector{1100.0, 1100.0, 0.0}}};

        Boxes.Emplace(FBox{FVector{100.0, 100.0, 0.0}, FVector{300.0, 300.0, kStepRiseZ}});

        return Boxes;
    }

    auto Make_StepGeometryBatch() -> FCk_GroundNav_GeometryBatch
    {
        auto Batch = FCk_GroundNav_GeometryBatch{};

        for (const auto& Box : Make_StepScene())
        { Batch.Add_Box(Box); }

        return Batch;
    }

    auto Get_WalkableCellCount(
        const FCk_GroundNav_Field& InField) -> int32
    {
        auto Count = 0;

        for (const auto& Tile : InField._Tiles)
        { Count += Tile.Get_WalkableCellCount(); }

        return Count;
    }

    auto Get_Fingerprint(
        const FCk_GroundNav_FieldParams& InParams) -> ck::groundnav::FCk_GroundNav_ContentFingerprint
    {
        return Get_ContentFingerprint(Make_StepGeometryBatch(), InParams.Get_Bounds(),
            InParams._Config, InParams._Profile, InParams._MarkupRecords, InParams._Links);
    }

    /**
     * Run a whole build at the given budget over N profiles, reporting how many slices it took.
     *
     * Takes the array by reference rather than as a view, because every call site assembles its params
     * inline and a view parameter would be one built over a temporary at each of them.
     */
    auto Build_Sliced(
        const TArray<FCk_GroundNav_FieldParams>& InParams,
        const TArray<FBox>&                      InBoxes,
        int32                                    InProbeBudget,
        FCk_GroundNav_FieldBuildState&           OutState,
        int32&                                   OutSliceCount) -> bool
    {
        const auto Backend = FCk_GroundNav_GeometryBackend_Stub{InBoxes};

        if (NOT Request_BeginBuild_MultiProfile(InParams, FCk_GroundNav_Epoch{1}, OutState).Get_IsCompleted())
        { return false; }

        OutSliceCount = 0;

        // Bounded so a build that failed to advance ends the test rather than the process.
        constexpr auto MaxSlices = 256;

        while (OutSliceCount < MaxSlices)
        {
            const auto Result = Request_AdvanceBuild(Backend, InProbeBudget, OutState);
            ++OutSliceCount;

            if (Result.Get_Status() == ECk_GroundNav_BakeStatus::BudgetExhausted)
            { continue; }

            return Result.Get_IsCompleted();
        }

        return false;
    }

    /** One slice at a budget nothing can exhaust, which is the whole build in one call. */
    auto Build_InOneSlice(
        const TArray<FCk_GroundNav_FieldParams>& InParams,
        const TArray<FBox>&                      InBoxes,
        FCk_GroundNav_FieldBuildState&           OutState) -> bool
    {
        auto SliceCount = 0;

        return Build_Sliced(InParams, InBoxes, TNumericLimits<int32>::Max(), OutState, SliceCount);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_ProfileVariants_TwoProfilesBakeFromOneGeometryFetchPerTile,
    "CkTests.UnitTests.CkGroundNav.ProfileVariants.TwoProfilesBakeFromOneGeometryFetchPerTile",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_ProfileVariants_TwoProfilesBakeFromOneGeometryFetchPerTile::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_profilevariants;

    auto SingleState = FCk_GroundNav_FieldBuildState{};

    if (NOT TestTrue(TEXT("the single-profile build completes"),
        Build_InOneSlice(TArray<FCk_GroundNav_FieldParams>{Make_LowStepParams()},
            Make_StepScene(), SingleState)))
    { return false; }

    auto BothState = FCk_GroundNav_FieldBuildState{};

    if (NOT TestTrue(TEXT("and so does the two-profile build"),
        Build_InOneSlice(Make_BothParams(), Make_StepScene(), BothState)))
    { return false; }

    const auto ExpectedTileCount = kDivisions * kDivisions;

    TestEqual(TEXT("the two-profile build holds a field per profile"),
        BothState.Get_ProfileCount(), 2);

    TestEqual(TEXT("collecting geometry exactly once per tile"),
        BothState._GeometryFetches, ExpectedTileCount);

    // The whole claim: adding a profile adds bakes, not collections. A second fetch per profile would
    // show up here and nowhere else.
    TestEqual(TEXT("which is the same count a single-profile build spends"),
        BothState._GeometryFetches, SingleState._GeometryFetches);

    // Probes, by contrast, DO sum: each profile's tile bake spends its own cell and span reads, which
    // is why the probe counter cannot witness the one-collection-per-tile claim.
    TestTrue(TEXT("while probes sum across the profiles"),
        BothState._ProbesSpent > SingleState._ProbesSpent);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_ProfileVariants_TwoProfilesProduceDifferingWalkableSets,
    "CkTests.UnitTests.CkGroundNav.ProfileVariants.TwoProfilesProduceDifferingWalkableSets",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_ProfileVariants_TwoProfilesProduceDifferingWalkableSets::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_profilevariants;

    auto State = FCk_GroundNav_FieldBuildState{};

    if (NOT TestTrue(TEXT("the two-profile build completes"),
        Build_InOneSlice(Make_BothParams(), Make_StepScene(), State)))
    { return false; }

    const auto Fields = Get_CompletedFields(State);

    if (NOT TestEqual(TEXT("yielding a field per profile"), Fields.Num(), 2))
    { return false; }

    const auto LowStepCells = Get_WalkableCellCount(Fields[0]);
    const auto HighStepCells = Get_WalkableCellCount(Fields[1]);

    if (NOT TestTrue(TEXT("both profiles found ground to stand on"),
        LowStepCells > 0 && HighStepCells > 0))
    { return false; }

    // The riser is taller than one profile's step and shorter than the other's, so the slab's rim
    // drops away for the first and is supported ground for the second.
    TestTrue(FString::Printf(
        TEXT("the shorter step reaches less ground than the taller one (%d vs %d)"),
        LowStepCells, HighStepCells), LowStepCells < HighStepCells);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_ProfileVariants_SlicedMultiProfileBakeMatchesOneShot,
    "CkTests.UnitTests.CkGroundNav.ProfileVariants.SlicedMultiProfileBakeMatchesOneShot",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_ProfileVariants_SlicedMultiProfileBakeMatchesOneShot::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_profilevariants;
    using namespace ck_test_groundnav_field_equality;

    const auto BothParams = Make_BothParams();

    auto OneShots = TArray<FCk_GroundNav_Field>{};
    OneShots.SetNum(BothParams.Num());

    for (auto ProfileIndex = 0; ProfileIndex < BothParams.Num(); ++ProfileIndex)
    {
        const auto Backend = FCk_GroundNav_GeometryBackend_Stub{Make_StepScene()};

        if (NOT TestTrue(FString::Printf(TEXT("the one-shot bake of profile %d completes"), ProfileIndex),
            DoBake_Field(Backend, BothParams[ProfileIndex], FCk_GroundNav_Epoch{1},
                OneShots[ProfileIndex]).Get_IsCompleted()))
        { return false; }
    }

    auto State = FCk_GroundNav_FieldBuildState{};
    auto SliceCount = 0;

    // A budget of one probe forces the smallest slice the builder allows, which is one tile — for
    // every profile at once, because the resume point is shared.
    if (NOT TestTrue(TEXT("the sliced two-profile build completes"),
        Build_Sliced(BothParams, Make_StepScene(), 1, State, SliceCount)))
    { return false; }

    if (NOT TestTrue(FString::Printf(TEXT("in more than one slice (took %d)"), SliceCount),
        SliceCount > 1))
    { return false; }

    const auto Sliced = Get_CompletedFields(State);

    if (NOT TestEqual(TEXT("and yields a field per profile"), Sliced.Num(), BothParams.Num()))
    { return false; }

    // Byte for byte, per profile, not approximately: sharing one geometry collection and one resume
    // point across N profiles must not change a single number any one of them would have baked alone.
    for (auto ProfileIndex = 0; ProfileIndex < BothParams.Num(); ++ProfileIndex)
    {
        const auto Difference = Get_FirstFieldDifference(
            OneShots[ProfileIndex], Sliced[ProfileIndex],
            EPolicyComparison::Include, EEpochComparison::Include);

        TestTrue(FString::Printf(TEXT("profile %d is identical to its one-shot bake (%s)"),
            ProfileIndex, *Difference), Difference.IsEmpty());
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_ProfileVariants_MismatchedParamsOtherThanProfileAreRefused,
    "CkTests.UnitTests.CkGroundNav.ProfileVariants.MismatchedParamsOtherThanProfileAreRefused",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_ProfileVariants_MismatchedParamsOtherThanProfileAreRefused::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_profilevariants;

    auto Mismatched = Make_BothParams();

    // The lattice is what the shared geometry collection is placed against, so two variants that
    // disagree about where the field starts cannot be answered by one fetch — and each would look
    // entirely reasonable on its own.
    Mismatched[1]._OriginXY = FVector2D{500.0, 0.0};

    AddExpectedError(
        TEXT("must differ only in their agent profile"),
        EAutomationExpectedErrorFlags::Contains,
        0);

    auto State = FCk_GroundNav_FieldBuildState{};

    const auto BeginResult = Request_BeginBuild_MultiProfile(
        Mismatched, FCk_GroundNav_Epoch{1}, State);

    TestEqual(TEXT("a params list that disagrees outside the profile is refused at admission"),
        BeginResult.Get_Status(), ECk_GroundNav_BakeStatus::InvalidInput);

    // All-or-nothing: the profile that WOULD have baked must not be left half-begun either.
    TestEqual(TEXT("with no field begun for any profile"), State.Get_ProfileCount(), 0);
    TestTrue(TEXT("and nothing reachable"), Get_CompletedField(State) == nullptr);

    const auto Backend = FCk_GroundNav_GeometryBackend_Stub{Make_StepScene()};
    const auto SliceResult = Request_AdvanceBuild(Backend, 1, State);

    TestEqual(TEXT("driving the refused build refuses on the same grounds"),
        SliceResult.Get_Status(), ECk_GroundNav_BakeStatus::InvalidInput);

    TestEqual(TEXT("without collecting any geometry"), State._GeometryFetches, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_ProfileVariants_SingleProfileBuildMatchesTheOneShotBake,
    "CkTests.UnitTests.CkGroundNav.ProfileVariants.SingleProfileBuildMatchesTheOneShotBake",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_ProfileVariants_SingleProfileBuildMatchesTheOneShotBake::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_profilevariants;
    using namespace ck_test_groundnav_field_equality;

    auto SingleEntryState = FCk_GroundNav_FieldBuildState{};

    {
        const auto Backend = FCk_GroundNav_GeometryBackend_Stub{Make_StepScene()};

        if (NOT TestTrue(TEXT("the single-params entry point begins a build"),
            Request_BeginBuild(Make_LowStepParams(), FCk_GroundNav_Epoch{1},
                SingleEntryState).Get_IsCompleted()))
        { return false; }

        if (NOT TestTrue(TEXT("and drives it to completion"),
            Request_AdvanceBuild(Backend, TNumericLimits<int32>::Max(),
                SingleEntryState).Get_IsCompleted()))
        { return false; }
    }

    TestEqual(TEXT("holding exactly one field"), SingleEntryState.Get_ProfileCount(), 1);

    auto OneElementState = FCk_GroundNav_FieldBuildState{};

    if (NOT TestTrue(TEXT("a one-element multi-profile build completes"),
        Build_InOneSlice(TArray<FCk_GroundNav_FieldParams>{Make_LowStepParams()},
            Make_StepScene(), OneElementState)))
    { return false; }

    const auto* FromSingleEntry = Get_CompletedField(SingleEntryState);
    const auto* FromOneElement = Get_CompletedField(OneElementState);

    if (NOT TestTrue(TEXT("both yield a field"),
        FromSingleEntry != nullptr && FromOneElement != nullptr))
    { return false; }

    const auto Difference = Get_FirstFieldDifference(
        *FromSingleEntry, *FromOneElement, EPolicyComparison::Include, EEpochComparison::Include);

    TestTrue(FString::Printf(TEXT("and the two are identical (%s)"), *Difference),
        Difference.IsEmpty());

    // Against the one-shot bake as well: a single-profile build routed through the N-profile machinery
    // must land on the same field DoBake_Field produces in one pass.
    auto OneShot = FCk_GroundNav_Field{};

    {
        const auto Backend = FCk_GroundNav_GeometryBackend_Stub{Make_StepScene()};

        if (NOT TestTrue(TEXT("the one-shot bake completes"),
            DoBake_Field(Backend, Make_LowStepParams(), FCk_GroundNav_Epoch{1}, OneShot).Get_IsCompleted()))
        { return false; }
    }

    const auto OneShotDifference = Get_FirstFieldDifference(
        OneShot, *FromSingleEntry, EPolicyComparison::Include, EEpochComparison::Include);

    TestTrue(FString::Printf(TEXT("as is the one-shot bake of the same scene (%s)"), *OneShotDifference),
        OneShotDifference.IsEmpty());

    TestEqual(TEXT("having spent the same probes"),
        OneElementState._ProbesSpent, SingleEntryState._ProbesSpent);

    TestEqual(TEXT("and collected geometry the same number of times"),
        OneElementState._GeometryFetches, SingleEntryState._GeometryFetches);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_ProfileVariants_EachProfileFieldFingerprintsItsOwnProfile,
    "CkTests.UnitTests.CkGroundNav.ProfileVariants.EachProfileFieldFingerprintsItsOwnProfile",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_ProfileVariants_EachProfileFieldFingerprintsItsOwnProfile::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_profilevariants;

    auto State = FCk_GroundNav_FieldBuildState{};

    if (NOT TestTrue(TEXT("the two-profile build completes"),
        Build_InOneSlice(Make_BothParams(), Make_StepScene(), State)))
    { return false; }

    if (NOT TestEqual(TEXT("holding a params entry per profile"), State._Params.Num(), 2))
    { return false; }

    const auto LowPrint = Get_Fingerprint(State._Params[0]);
    const auto HighPrint = Get_Fingerprint(State._Params[1]);

    // Item 4 of the frozen enumeration hashes the profile's own values, so two variants over one world
    // are two bake identities already — a profile INDEX would only ever say which of N fields is which,
    // and there is no seventh item to add for it.
    TestFalse(TEXT("the two profiles fingerprint differently over the same world"),
        LowPrint == HighPrint);

    // And each entry is still the profile it was submitted as, in submission order: the shared build
    // must not have handed one profile's params to the other's field.
    TestTrue(TEXT("the first entry prints as a lone low-step bake would"),
        LowPrint == Get_Fingerprint(Make_LowStepParams()));

    TestTrue(TEXT("and the second as a lone high-step bake would"),
        HighPrint == Get_Fingerprint(Make_HighStepParams()));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// --------------------------------------------------------------------------------------------------------------------
// THE VOLUME AND THE REGISTRY: which profile a query is answered from.
//
// Above, a build produces N fields. Here they are the volume's, keyed by the tag a caller names them
// with, and the claim is that the tag SELECTS - it never merely hints. A tag the containing volume
// authored no variant for is answered by no field at all, because handing back the untagged default
// would walk an agent up a step its own profile says it cannot climb, which is the whole failure a
// variant exists to prevent.
//
// The volume BAKING one field per profile end to end is not reachable here: the geometry backend needs
// a physics world, which a headless test has none of, so a published field is staged by baking through
// the stub and publishing it. The end-to-end claim - an authored variant becomes a second published
// field a neutral query resolves against - is the AngelScript pin
// CkAutoTest_GroundNav_ProfileVariant_QuerySelectsTheProfilesField.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_groundnav_profilevariants_volume
{
    namespace world_fields = ck::groundnav::world_fields;

    using ck::groundnav::DoBake_Field;
    using ck::groundnav::FCk_GroundNav_Epoch;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldPtr;
    using ck::groundnav::FCk_GroundNav_GeometryBackend_Stub;

    constexpr auto kSixtyHertz = 1.0f / 60.0f;
    constexpr auto InformEngineOfWorld = false;

    // The volume's bounds are the field fixture's lattice stated as a box: origin (0,0), 2 x 2 tiles of
    // 400uu, the same Z span. A volume and a field that disagreed about the ground they cover would
    // make every location assertion below a statement about the fixture instead of the feature.
    auto Make_VolumeParams(
        const FCk_GroundNav_AgentProfile& InProfile) -> FCk_Fragment_GroundNavVolume_ParamsData
    {
        using namespace ck_test_groundnav_profilevariants;

        auto Config = FCk_GroundNav_BakeConfig{kCellSize, kCellHeight};
        Config.Set_TileSizeUu(kTileSize);

        const auto Bounds = FBox{
            FVector{0.0, 0.0, kMinZ},
            FVector{kDivisions * kTileSize, kDivisions * kTileSize, kMaxZ}};

        return FCk_Fragment_GroundNavVolume_ParamsData{Bounds, Config, InProfile};
    }

    auto Make_Variant(
        const FGameplayTag& InProfileTag,
        float               InStepHeightUu) -> FCk_GroundNav_ProfileVariant
    {
        using namespace ck_test_groundnav_profilevariants;

        return FCk_GroundNav_ProfileVariant{InProfileTag, Make_Profile(InStepHeightUu)};
    }

    auto Bake_Field(
        const FCk_GroundNav_AgentProfile& InProfile) -> FCk_GroundNav_FieldPtr
    {
        using namespace ck_test_groundnav_profilevariants;

        const auto Backend = FCk_GroundNav_GeometryBackend_Stub{Make_StepScene()};

        auto Field = MakeShared<FCk_GroundNav_Field>();

        if (NOT DoBake_Field(Backend, Make_Params(InProfile), FCk_GroundNav_Epoch{1}, *Field).Get_IsCompleted())
        { return {}; }

        return FCk_GroundNav_FieldPtr{Field};
    }

    /**
     * The centre of the slab's CORNER cell, which is where the two profiles disagree.
     *
     * The slab spans 100..300uu on both axes over a 25uu lattice whose origin is the field's, so it
     * covers cells 4..11 exactly and cell (4,4) is its corner. The ledge filter demotes a span whose
     * neighbouring column holds nothing within one step below it: this cell's -X and -Y neighbours are
     * bare floor 60uu down, which is inside an 80uu step and outside a 40uu one. The slab's INTERIOR
     * cells are surrounded by slab and stay walkable for both profiles, which is why the assertion has
     * to stand on a rim cell rather than anywhere on top.
     */
    auto Make_SlabCornerCellCentre() -> FVector
    {
        using namespace ck_test_groundnav_profilevariants;

        return FVector{112.5, 112.5, kStepRiseZ};
    }

    /**
     * Tight enough that the projection can reach nothing but the cell the probe stands in.
     *
     * Horizontal: the nearest point of any neighbouring cell is 12.5uu away, so 10uu excludes every one
     * of them - including the interior cells that stay walkable for both profiles. Vertical: the floor
     * is 60uu below, so 20uu excludes it. Without both, a demoted cell would be answered by whatever
     * walkable ground lies beside it and the two profiles would agree.
     */
    auto Make_TightSearchHalfExtents() -> FVector
    {
        return FVector{10.0, 10.0, 20.0};
    }

    auto TryGet_GroundNavTable() -> const FCk_NavSurface_ProviderTable*
    {
        return ck::nav_surface::TryGet_ProviderTable(ECk_NavSurface_Provider::GroundNav);
    }

    struct FWorldFixture
    {
        UWorld* _World = nullptr;
        FCk_Handle _VolumeEntity;
    };

    auto Make_Fixture(
        const TCHAR* InWorldName) -> FWorldFixture
    {
        auto Fixture = FWorldFixture{};

        Fixture._World = UWorld::CreateWorld(EWorldType::Game, InformEngineOfWorld, FName{InWorldName});

        if (Fixture._World == nullptr)
        { return Fixture; }

        auto WorldEntity = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(Fixture._World);

        if (ck::Is_NOT_Valid(WorldEntity))
        { return Fixture; }

        Fixture._VolumeEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(WorldEntity);

        return Fixture;
    }

    auto Get_IsReady(
        const FWorldFixture& InFixture) -> bool
    {
        return InFixture._World != nullptr && ck::IsValid(InFixture._VolumeEntity);
    }

    auto Destroy_Fixture(
        FWorldFixture& InFixture) -> void
    {
        if (InFixture._World != nullptr)
        { InFixture._World->DestroyWorld(InformEngineOfWorld); }

        InFixture._World = nullptr;
    }

    auto Make_Listener() -> TStrongObjectPtr<UCk_Test_CompletionListener_UE>
    {
        return TStrongObjectPtr<UCk_Test_CompletionListener_UE>{
            NewObject<UCk_Test_CompletionListener_UE>(GetTransientPackage())};
    }

    auto Make_Delegate(
        UCk_Test_CompletionListener_UE* InListener) -> FCk_Delegate_Request_OnCompleted
    {
        auto Delegate = FCk_Delegate_Request_OnCompleted{};
        Delegate.BindDynamic(InListener, &UCk_Test_CompletionListener_UE::OnRequestCompleted);

        return Delegate;
    }

    // The build drain, invoked directly: a headless registry has no scheduler, so the view's TExclude
    // filters are the header's claim rather than this file's.
    auto DoDrain_BuildRequests(
        ck::FEcsWorld&              InWorld,
        FCk_Handle_GroundNavVolume& InVolume) -> void
    {
        ck::FProcessor_GroundNavVolume_HandleRequests{InWorld.Get_Registry()}.ForEachEntity(
            FCk_Time{kSixtyHertz},
            InVolume,
            InVolume.Get<ck::FFragment_GroundNavVolume_Params>(),
            InVolume.Get<ck::FFragment_GroundNavVolume_BuildState>(),
            InVolume.Get<ck::FFragment_GroundNavVolume_RepairState>(),
            InVolume.Get<ck::FFragment_GroundNavVolume_Requests>());
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_ProfileVariants_DuplicateOrEmptyVariantTagIsRefused,
    "CkTests.UnitTests.CkGroundNav.ProfileVariants.DuplicateOrEmptyVariantTagIsRefused",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_ProfileVariants_DuplicateOrEmptyVariantTagIsRefused::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_profilevariants;
    using namespace ck_test_groundnav_profilevariants_volume;

    auto World = ck::FEcsWorld{};

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());

    // The tag is the ONLY way a variant is reached, so an empty one names nothing and a repeated one
    // names two profiles at once. Both are the same defect - a selector that cannot select - and both
    // are refused where the volume's params are judged.
    auto UntaggedParams = Make_VolumeParams(Make_Profile(kHighStepHeightUu));
    UntaggedParams.Set_ProfileVariants(TArray<FCk_GroundNav_ProfileVariant>{
        Make_Variant(FGameplayTag{}, kLowStepHeightUu)});

    auto DuplicateParams = Make_VolumeParams(Make_Profile(kHighStepHeightUu));
    DuplicateParams.Set_ProfileVariants(TArray<FCk_GroundNav_ProfileVariant>{
        Make_Variant(TAG_CkTests_GroundNav_Profile_Crawler.GetTag(), kLowStepHeightUu),
        Make_Variant(TAG_CkTests_GroundNav_Profile_Crawler.GetTag(), kHighStepHeightUu)});

    auto UsableParams = Make_VolumeParams(Make_Profile(kHighStepHeightUu));
    UsableParams.Set_ProfileVariants(TArray<FCk_GroundNav_ProfileVariant>{
        Make_Variant(TAG_CkTests_GroundNav_Profile_Crawler.GetTag(), kLowStepHeightUu)});

    auto Untagged = UCk_Utils_GroundNavVolume_UE::Add(Owner, UntaggedParams);
    auto Duplicate = UCk_Utils_GroundNavVolume_UE::Add(Owner, DuplicateParams);
    auto Usable = UCk_Utils_GroundNavVolume_UE::Add(Owner, UsableParams);

    if (NOT TestTrue(TEXT("all three volumes compose"),
        ck::IsValid(Untagged) && ck::IsValid(Duplicate) && ck::IsValid(Usable)))
    { return false; }

    TestEqual(TEXT("the authored tags read back off the params, variant-only and in authored order"),
        UCk_Utils_GroundNavVolume_UE::Get_ProfileVariantTags(Usable).Num(), 1);

    TestTrue(TEXT("and it is the tag that was authored"),
        UCk_Utils_GroundNavVolume_UE::Get_ProfileVariantTags(Usable).Contains(
            TAG_CkTests_GroundNav_Profile_Crawler.GetTag()));

    AddExpectedError(
        TEXT("its params are not bakeable"),
        EAutomationExpectedErrorFlags::Contains,
        0);

    const auto UntaggedListener = Make_Listener();
    const auto DuplicateListener = Make_Listener();
    const auto UsableListener = Make_Listener();

    UCk_Utils_GroundNavVolume_UE::Request_Build(Untagged,
        FCk_Request_GroundNavVolume_Build{}, Make_Delegate(UntaggedListener.Get()));
    UCk_Utils_GroundNavVolume_UE::Request_Build(Duplicate,
        FCk_Request_GroundNavVolume_Build{}, Make_Delegate(DuplicateListener.Get()));
    UCk_Utils_GroundNavVolume_UE::Request_Build(Usable,
        FCk_Request_GroundNavVolume_Build{}, Make_Delegate(UsableListener.Get()));

    DoDrain_BuildRequests(World, Untagged);
    DoDrain_BuildRequests(World, Duplicate);
    DoDrain_BuildRequests(World, Usable);

    TestEqual(TEXT("the empty-tagged volume's build request completes"),
        UntaggedListener->_TimesRequestCompleted, 1);
    TestTrue(TEXT("as Failed"),
        UntaggedListener->_LastRequestResult == ECk_Request_OperationResult::Failed);
    TestFalse(TEXT("and it is not armed to build"),
        Untagged.Has<ck::FTag_GroundNavVolume_NeedsBuild>());

    TestEqual(TEXT("the duplicate-tagged volume's build request completes"),
        DuplicateListener->_TimesRequestCompleted, 1);
    TestTrue(TEXT("as Failed"),
        DuplicateListener->_LastRequestResult == ECk_Request_OperationResult::Failed);
    TestFalse(TEXT("and it is not armed to build either"),
        Duplicate.Has<ck::FTag_GroundNavVolume_NeedsBuild>());

    // The POSITIVE the two refusals rest on: params identical but for the tags are admitted, so what
    // was refused above is the tag and not the variant.
    TestEqual(TEXT("the usable volume's build request does not complete at the drain - it is armed"),
        UsableListener->_TimesRequestCompleted, 0);
    TestTrue(TEXT("and it IS armed to build"),
        Usable.Has<ck::FTag_GroundNavVolume_NeedsBuild>());

    // Authored data survives a refusal: the params are what a caller fixes and re-requests against.
    TestEqual(TEXT("the refused volume still holds the variants it authored"),
        UCk_Utils_GroundNavVolume_UE::Get_ProfileVariantTags(Duplicate).Num(), 2);

    // Built is what a PUBLISH stamps, so an armed volume is built for no profile - not for the tag it
    // authored and not for the untagged default either.
    TestFalse(TEXT("an armed volume is not yet built for its variant"),
        UCk_Utils_GroundNavVolume_UE::Get_IsBuilt_ForProfile(
            Usable, TAG_CkTests_GroundNav_Profile_Crawler.GetTag()));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_ProfileVariants_RegistrySelectsTheVariantByTag,
    "CkTests.UnitTests.CkGroundNav.ProfileVariants.RegistrySelectsTheVariantByTag",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_ProfileVariants_RegistrySelectsTheVariantByTag::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_profilevariants;
    using namespace ck_test_groundnav_profilevariants_volume;

    auto Fixture = Make_Fixture(TEXT("CkGroundNavProfileVariantsSelect"));

    if (NOT TestTrue(TEXT("the world composes an entity to publish under"), Get_IsReady(Fixture)))
    {
        Destroy_Fixture(Fixture);
        return false;
    }

    const auto DefaultField = Bake_Field(Make_Profile(kHighStepHeightUu));
    const auto VariantField = Bake_Field(Make_Profile(kLowStepHeightUu));

    if (NOT TestTrue(TEXT("both the default and the variant bake"),
        DefaultField.IsValid() && VariantField.IsValid()))
    {
        Destroy_Fixture(Fixture);
        return false;
    }

    auto VariantFields = TMap<FGameplayTag, FCk_GroundNav_FieldPtr>{};
    VariantFields.Emplace(TAG_CkTests_GroundNav_Profile_Crawler.GetTag(), VariantField);

    world_fields::Publish(Fixture._World, Fixture._VolumeEntity, DefaultField, VariantFields);

    const auto Probe = Make_SlabCornerCellCentre();

    TestTrue(TEXT("the two-argument read still answers the untagged default"),
        world_fields::TryGet_Field(Fixture._World, Probe) == DefaultField);

    TestTrue(TEXT("and so does an empty tag - the default is what no tag means"),
        world_fields::TryGet_Field(Fixture._World, Probe, FGameplayTag{}) == DefaultField);

    TestTrue(TEXT("the variant's tag answers the variant's field"),
        world_fields::TryGet_Field(
            Fixture._World, Probe, TAG_CkTests_GroundNav_Profile_Crawler.GetTag()) == VariantField);

    // The POSITIVE the selection rests on: two pointers that were the same field would satisfy every
    // assertion above without anything having been selected.
    TestFalse(TEXT("and the two are different fields"), DefaultField == VariantField);

    // A publish REPLACES the whole variant map rather than merging into it, so a volume that stops
    // baking a variant leaves nothing behind under its tag.
    world_fields::Publish(
        Fixture._World, Fixture._VolumeEntity, DefaultField,
        TMap<FGameplayTag, FCk_GroundNav_FieldPtr>{});

    TestFalse(TEXT("a dropped variant is gone from the entry"),
        world_fields::TryGet_Field(
            Fixture._World, Probe, TAG_CkTests_GroundNav_Profile_Crawler.GetTag()).IsValid());

    TestTrue(TEXT("while the default it was published beside is untouched"),
        world_fields::TryGet_Field(Fixture._World, Probe) == DefaultField);

    world_fields::Unpublish(Fixture._World, Fixture._VolumeEntity);
    Destroy_Fixture(Fixture);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_ProfileVariants_UnknownProfileTagAnswersNoField,
    "CkTests.UnitTests.CkGroundNav.ProfileVariants.UnknownProfileTagAnswersNoField",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_ProfileVariants_UnknownProfileTagAnswersNoField::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_profilevariants;
    using namespace ck_test_groundnav_profilevariants_volume;

    auto Fixture = Make_Fixture(TEXT("CkGroundNavProfileVariantsUnknown"));

    if (NOT TestTrue(TEXT("the world composes an entity to publish under"), Get_IsReady(Fixture)))
    {
        Destroy_Fixture(Fixture);
        return false;
    }

    const auto DefaultField = Bake_Field(Make_Profile(kHighStepHeightUu));
    const auto VariantField = Bake_Field(Make_Profile(kLowStepHeightUu));

    if (NOT TestTrue(TEXT("both the default and the variant bake"),
        DefaultField.IsValid() && VariantField.IsValid()))
    {
        Destroy_Fixture(Fixture);
        return false;
    }

    auto VariantFields = TMap<FGameplayTag, FCk_GroundNav_FieldPtr>{};
    VariantFields.Emplace(TAG_CkTests_GroundNav_Profile_Crawler.GetTag(), VariantField);

    world_fields::Publish(Fixture._World, Fixture._VolumeEntity, DefaultField, VariantFields);

    const auto Probe = Make_SlabCornerCellCentre();

    // NO FALLBACK, and this is the whole point of the read. The volume covers this location and has a
    // field for it, so the tempting answer is the default's - which is ground the named profile was
    // never judged against.
    TestFalse(TEXT("a tag this volume authored no variant for answers no field"),
        world_fields::TryGet_Field(
            Fixture._World, Probe, TAG_CkTests_GroundNav_Profile_Swimmer.GetTag()).IsValid());

    TestTrue(TEXT("even though the very same location has a default field to fall back to"),
        world_fields::TryGet_Field(Fixture._World, Probe).IsValid());

    TestTrue(TEXT("and a tag it DID author one for is still answered"),
        world_fields::TryGet_Field(
            Fixture._World, Probe, TAG_CkTests_GroundNav_Profile_Crawler.GetTag()) == VariantField);

    world_fields::Unpublish(Fixture._World, Fixture._VolumeEntity);

    TestFalse(TEXT("an unpublished entry takes its variants with it"),
        world_fields::TryGet_Field(
            Fixture._World, Probe, TAG_CkTests_GroundNav_Profile_Crawler.GetTag()).IsValid());

    Destroy_Fixture(Fixture);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_ProfileVariants_NeutralQueryCarriesTheProfileTag,
    "CkTests.UnitTests.CkGroundNav.ProfileVariants.NeutralQueryCarriesTheProfileTag",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_ProfileVariants_NeutralQueryCarriesTheProfileTag::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_profilevariants;
    using namespace ck_test_groundnav_profilevariants_volume;

    const auto* Table = TryGet_GroundNavTable();

    if (NOT TestTrue(TEXT("the GroundNav provider registered a table to answer through"),
        Table != nullptr && static_cast<bool>(Table->_ProjectPoint)))
    { return false; }

    auto Fixture = Make_Fixture(TEXT("CkGroundNavProfileVariantsNeutral"));

    if (NOT TestTrue(TEXT("the world composes an entity to publish under"), Get_IsReady(Fixture)))
    {
        Destroy_Fixture(Fixture);
        return false;
    }

    const auto DefaultField = Bake_Field(Make_Profile(kHighStepHeightUu));
    const auto VariantField = Bake_Field(Make_Profile(kLowStepHeightUu));

    if (NOT TestTrue(TEXT("both the default and the variant bake"),
        DefaultField.IsValid() && VariantField.IsValid()))
    {
        Destroy_Fixture(Fixture);
        return false;
    }

    auto VariantFields = TMap<FGameplayTag, FCk_GroundNav_FieldPtr>{};
    VariantFields.Emplace(TAG_CkTests_GroundNav_Profile_Crawler.GetTag(), VariantField);

    world_fields::Publish(Fixture._World, Fixture._VolumeEntity, DefaultField, VariantFields);

    auto Query = FCk_NavSurface_ProjectionQuery{Make_SlabCornerCellCentre()};
    Query.Set_SearchHalfExtents(Make_TightSearchHalfExtents());

    const auto Untagged = Table->_ProjectPoint(Fixture._World, Query);

    auto CrawlerQuery = Query;
    CrawlerQuery.Set_ProfileTag(TAG_CkTests_GroundNav_Profile_Crawler.GetTag());

    const auto Crawler = Table->_ProjectPoint(Fixture._World, CrawlerQuery);

    auto SwimmerQuery = Query;
    SwimmerQuery.Set_ProfileTag(TAG_CkTests_GroundNav_Profile_Swimmer.GetTag());

    const auto Swimmer = Table->_ProjectPoint(Fixture._World, SwimmerQuery);

    world_fields::Unpublish(Fixture._World, Fixture._VolumeEntity);
    Destroy_Fixture(Fixture);

    // The 80uu profile steps up the 60uu riser, so the slab's corner cell is ground it may stand on.
    TestEqual(TEXT("the untagged query stands on the slab's corner"),
        Untagged.Get_Status(), ECk_NavSurface_QueryStatus::Success);

    TestTrue(FString::Printf(TEXT("on the slab's own top face rather than the floor below (%f)"),
        Untagged.Get_Location().Z),
        FMath::IsNearlyEqual(Untagged.Get_Location().Z, static_cast<double>(kStepRiseZ), 1.0));

    // The 40uu profile cannot, so the same cell is a ledge for it. Same world, same probe, same
    // extents - the tag is the only thing that differs, which is what makes this a test of the seam
    // rather than of the fixture.
    TestEqual(TEXT("the variant's tag is answered from the variant's field, where the same cell is "
                   "not walkable"),
        Crawler.Get_Status(), ECk_NavSurface_QueryStatus::NoSurface);

    // NoProvider rather than NoSurface: there is no surface to have an opinion at all, which is a
    // different answer from ground that was looked at and refused.
    TestEqual(TEXT("a tag with no field behind it answers NoProvider"),
        Swimmer.Get_Status(), ECk_NavSurface_QueryStatus::NoProvider);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
// A ROUTE PLANNED OVER A VARIANT, and what a change that reached only that variant does to it.
//
// An invalidator decides with the epoch of the field a plan was made on, so the field it resolves has
// to be the one the corridor was planned over. A variant-planned corridor measured against the untagged
// default is measured against ground that never moved with it, and every route over a variant would
// then survive a change to the very field it walks.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_groundnav_profilevariants_path
{
    namespace volume_fixture = ck_test_groundnav_profilevariants_volume;
    namespace world_fields = ck::groundnav::world_fields;

    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldPtr;

    // Far past what this scene needs, so a run that stops on it is a search that never terminated.
    constexpr auto kMaxTicks = 4096;

    // The capsule the fixture profiles are built around, said again here because the path params carry
    // the radius separately and a plan made for a different body would walk a different corridor.
    constexpr auto kAgentRadiusUu = 20.0f;

    // The corner-offset pass off, for the reason Test_GroundNav_PathInvalidation turns it off: the
    // corridor box is the subject, and that pass moves waypoints for reasons of its own.
    constexpr auto kNoCornerOffset = 0.0f;

    // Bare floor on either side of the slab. The route is a run of open ground both profiles agree
    // about, because what is under test is which FIELD the corridor is measured against and not which
    // cells the search found.
    const auto kRouteStart = FVector{50.0, 700.0, 0.0};
    const auto kRouteGoal = FVector{700.0, 50.0, 0.0};

    // Two agents rather than one asked twice: the positive and the negative have to be taken off the
    // same publish, or a gate that simply never fires would satisfy one of them on its own.
    constexpr auto kVariantAgent = 0;
    constexpr auto kDefaultAgent = 1;

    // Well inside the corridor, so the bounds half of the decision is a fact about the boxes rather
    // than about a face landing exactly on one.
    constexpr auto kWellClearUu = 100.0;

    struct FPathFixture
    {
        UWorld*    _World = nullptr;
        FCk_Handle _WorldEntity;
        FCk_Handle _VolumeEntity;

        FCk_GroundNav_FieldPtr _DefaultField;
        FCk_GroundNav_FieldPtr _VariantField;

        TArray<FCk_Handle_GroundNavPath> _Paths;
    };

    auto Make_VariantMap(
        const FCk_GroundNav_FieldPtr& InVariantField) -> TMap<FGameplayTag, FCk_GroundNav_FieldPtr>
    {
        auto VariantFields = TMap<FGameplayTag, FCk_GroundNav_FieldPtr>{};
        VariantFields.Emplace(TAG_CkTests_GroundNav_Profile_Crawler.GetTag(), InVariantField);

        return VariantFields;
    }

    auto Make_PathParams() -> FCk_Fragment_GroundNavPath_ParamsData
    {
        using namespace ck_test_groundnav_profilevariants;

        auto Params = FCk_Fragment_GroundNavPath_ParamsData{kAgentRadiusUu};

        Params.Set_VerticalToleranceUu(kHighStepHeightUu);
        Params.Set_CornerOffsetK(kNoCornerOffset);

        return Params;
    }

    auto Do_Teardown(
        FPathFixture& InOutFixture) -> void
    {
        if (InOutFixture._World == nullptr)
        { return; }

        world_fields::Unpublish(InOutFixture._World, InOutFixture._VolumeEntity);

        InOutFixture._World->DestroyWorld(volume_fixture::InformEngineOfWorld);
        InOutFixture._World = nullptr;
    }

    /**
     * One volume's entry in a real world - a default field and a variant field under the crawler's tag -
     * and two agents to plan over them.
     *
     * The three NavSurface fragments are seeded by hand for the reason Test_GroundNav_PathInvalidation
     * seeds them: the watch's own DoTick composes them, and a headless world has no scheduler to run it.
     */
    auto Do_Setup(
        FPathFixture& InOutFixture,
        const TCHAR*  InWorldName) -> bool
    {
        using namespace ck_test_groundnav_profilevariants;

        InOutFixture._World = UWorld::CreateWorld(
            EWorldType::Game, volume_fixture::InformEngineOfWorld, FName{InWorldName});

        if (InOutFixture._World == nullptr)
        { return false; }

        InOutFixture._WorldEntity =
            UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InOutFixture._World);

        if (ck::Is_NOT_Valid(InOutFixture._WorldEntity))
        { return false; }

        InOutFixture._WorldEntity.AddOrGet<ck::FFragment_NavSurface_Provider>();
        InOutFixture._WorldEntity.AddOrGet<ck::FFragment_NavSurface_RevisionWatch>();
        InOutFixture._WorldEntity.AddOrGet<ck::FFragment_NavSurface_PendingRebuilds>();

        InOutFixture._VolumeEntity =
            UCk_Utils_EntityLifetime_UE::Request_CreateEntity(InOutFixture._WorldEntity);

        if (ck::Is_NOT_Valid(InOutFixture._VolumeEntity))
        { return false; }

        InOutFixture._DefaultField = volume_fixture::Bake_Field(Make_Profile(kHighStepHeightUu));

        if (NOT InOutFixture._DefaultField.IsValid())
        { return false; }

        // The variant is a COPY of the default rather than a second bake. What this case turns on is
        // one field's epoch moving while the other's stands still, and two fields that also disagreed
        // about their cells would put the corridor's own plates in the way of that.
        InOutFixture._VariantField = MakeShared<FCk_GroundNav_Field>(*InOutFixture._DefaultField);

        world_fields::Publish(
            InOutFixture._World, InOutFixture._VolumeEntity, InOutFixture._DefaultField,
            Make_VariantMap(InOutFixture._VariantField));

        UCk_Utils_NavSurface_UE::Request_SetProvider(
            InOutFixture._World, ECk_NavSurface_Provider::GroundNav);

        if (UCk_Utils_NavSurface_UE::Get_Provider(InOutFixture._World) !=
            ECk_NavSurface_Provider::GroundNav)
        { return false; }

        for (auto Index = 0; Index < 2; ++Index)
        {
            auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(InOutFixture._WorldEntity);

            auto Path = UCk_Utils_GroundNavPath_UE::Add(Owner, Make_PathParams());

            if (ck::Is_NOT_Valid(Path))
            { return false; }

            InOutFixture._Paths.Emplace(Path);
        }

        return true;
    }

    /** One cold plan for one agent under one profile tag, sliced until its slot carries an episode. */
    auto Do_PlanAgent(
        FPathFixture&       InOutFixture,
        int32               InAgentIndex,
        const FGameplayTag& InProfileTag) -> bool
    {
        auto& Path = InOutFixture._Paths[InAgentIndex];

        auto Request = FCk_Request_GroundNavPath_FindPath{kRouteStart, kRouteGoal};

        Request.Set_RequestRevision(1);
        Request.Set_PlanMode(ECk_GroundNav_PlanMode::Cold);
        Request.Set_ProfileTag(InProfileTag);

        UCk_Utils_GroundNavPath_UE::Request_FindPath(Path, Request, {});

        ck::FProcessor_GroundNavPath_HandleRequests{InOutFixture._WorldEntity.Get_RegistryView()}
            .ForEachEntity(
                FCk_Time{volume_fixture::kSixtyHertz},
                Path,
                Path.Get<ck::FFragment_GroundNavPath_Params>(),
                Path.Get<ck::FFragment_GroundNavPath_Current>(),
                Path.Get<ck::FFragment_GroundNavPath_Result>(),
                Path.Get<ck::FFragment_GroundNavPath_Requests>());

        auto Slice = ck::FProcessor_GroundNavPath_Slice{InOutFixture._WorldEntity.Get_RegistryView()};

        auto Ticks = 0;

        while (NOT Path.Get<ck::FFragment_GroundNavPath_Result>().Get_HasFreshResult() &&
               Ticks < kMaxTicks)
        {
            Slice.DoTick(FCk_Time{volume_fixture::kSixtyHertz});
            ++Ticks;
        }

        return UCk_Utils_GroundNavPath_UE::Get_LastCorridorBounds(Path).IsValid != 0;
    }

    /**
     * Republishes the variant under the next epoch and the default under the pointer it already had.
     *
     * The bake is not re-run: the epoch is the subject, and re-baking would make the corridor's own
     * plates a second variable. The default's epoch does not move, which is the whole shape of a change
     * that reached one profile's ground and no other.
     */
    auto Do_PublishVariantOnlyChange(
        FPathFixture& InOutFixture) -> void
    {
        auto Moved = MakeShared<FCk_GroundNav_Field>(*InOutFixture._VariantField);

        Moved->_Epoch = InOutFixture._VariantField->_Epoch.Get_Next();

        InOutFixture._VariantField = Moved;

        world_fields::Publish(
            InOutFixture._World, InOutFixture._VolumeEntity, InOutFixture._DefaultField,
            Make_VariantMap(InOutFixture._VariantField));
    }

    auto Do_NotifyRebuilt(
        FPathFixture& InOutFixture,
        const FBox&   InBounds) -> void
    {
        ck::nav_surface::Request_NotifySurfaceRebuilt(InOutFixture._World, InBounds);
    }

    auto Do_RunInvalidator(
        FPathFixture& InOutFixture) -> void
    {
        ck::FProcessor_GroundNavPath_InvalidateOnRebuilt{InOutFixture._WorldEntity.Get_RegistryView()}
            .DoTick(FCk_Time{volume_fixture::kSixtyHertz});
    }

    auto Get_StoredCorridor(
        const FPathFixture& InFixture,
        int32               InAgentIndex) -> FBox
    {
        return UCk_Utils_GroundNavPath_UE::Get_LastCorridorBounds(InFixture._Paths[InAgentIndex]);
    }

    auto Get_StoredProfileTag(
        const FPathFixture& InFixture,
        int32               InAgentIndex) -> FGameplayTag
    {
        return InFixture._Paths[InAgentIndex].Get<ck::FFragment_GroundNavPath_Current>()
            .Get_ProfileTag();
    }

    auto Get_IsFlagged(
        const FPathFixture& InFixture,
        int32               InAgentIndex) -> bool
    {
        return InFixture._Paths[InAgentIndex].Has<ck::FTag_GroundNavPath_RepathRequired>();
    }

    /** A box well inside the corridor, so the overlap is a fact about the boxes and not about a face. */
    auto Make_OverlappingBox(
        const FBox& InCorridor) -> FBox
    {
        return FBox{InCorridor.GetCenter() - FVector{kWellClearUu},
                    InCorridor.GetCenter() + FVector{kWellClearUu}};
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_ProfileVariants_VariantPlannedPathIsInvalidatedByAVariantOnlyChange,
    "CkTests.UnitTests.CkGroundNav.ProfileVariants.VariantPlannedPathIsInvalidatedByAVariantOnlyChange",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_ProfileVariants_VariantPlannedPathIsInvalidatedByAVariantOnlyChange::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_profilevariants;
    using namespace ck_test_groundnav_profilevariants_path;

    auto Fixture = FPathFixture{};

    if (NOT TestTrue(TEXT("the world publishes a default and a variant and takes two agents"),
        Do_Setup(Fixture, TEXT("CkGroundNavProfileVariantsInvalidation"))))
    {
        Do_Teardown(Fixture);
        return false;
    }

    if (NOT TestTrue(TEXT("the crawler-tagged agent plans a route with a corridor to measure against"),
        Do_PlanAgent(Fixture, kVariantAgent, TAG_CkTests_GroundNav_Profile_Crawler.GetTag())))
    {
        Do_Teardown(Fixture);
        return false;
    }

    if (NOT TestTrue(TEXT("and so does the untagged one"),
        Do_PlanAgent(Fixture, kDefaultAgent, FGameplayTag{})))
    {
        Do_Teardown(Fixture);
        return false;
    }

    // The corridor carries the profile it was planned for, which is what lets the invalidator resolve
    // the field the plan was made on rather than whichever field the volume answers by default.
    TestTrue(TEXT("the crawler's corridor is stamped with the crawler's tag"),
        Get_StoredProfileTag(Fixture, kVariantAgent) ==
            TAG_CkTests_GroundNav_Profile_Crawler.GetTag());

    TestFalse(TEXT("and the untagged agent's corridor carries no tag at all"),
        Get_StoredProfileTag(Fixture, kDefaultAgent).IsValid());

    const auto VariantCorridor = Get_StoredCorridor(Fixture, kVariantAgent);
    const auto DefaultCorridor = Get_StoredCorridor(Fixture, kDefaultAgent);

    Do_PublishVariantOnlyChange(Fixture);

    // ONE box, reaching both corridors. A box that missed the untagged agent would make the negative
    // below a statement about geometry instead of about the epoch gate.
    Do_NotifyRebuilt(Fixture, Make_OverlappingBox(VariantCorridor));

    if (NOT TestTrue(TEXT("the published box reaches the untagged agent's corridor as well"),
        Make_OverlappingBox(VariantCorridor).Intersect(DefaultCorridor)))
    {
        Do_Teardown(Fixture);
        return false;
    }

    Do_RunInvalidator(Fixture);

    // The variant's field moved past the epoch this plan was dated against, and the entry's publish
    // note is stamped from the DEFAULT's epoch - so the note cannot account for the change either, and
    // the decision falls to the box, which reaches this corridor.
    TestTrue(TEXT("the variant-planned route is flagged for repath by a change to the variant's field"),
        Get_IsFlagged(Fixture, kVariantAgent));

    // Not flagged, and flagged by nothing: the untagged agent's field is the default, whose epoch did
    // not move, so it never reaches the box at all - the epoch gate answers first and answers current.
    TestFalse(TEXT("while the route planned over the untouched default is left alone by the epoch gate"),
        Get_IsFlagged(Fixture, kDefaultAgent));

    Do_Teardown(Fixture);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_ProfileVariants_VariantRevisionNeverFalls,
    "CkTests.UnitTests.CkGroundNav.ProfileVariants.VariantRevisionNeverFalls",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_ProfileVariants_VariantRevisionNeverFalls::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_profilevariants;
    using namespace ck_test_groundnav_profilevariants_volume;

    const auto* Table = TryGet_GroundNavTable();

    if (NOT TestTrue(TEXT("the GroundNav provider registered a table to answer through"),
        Table != nullptr && static_cast<bool>(Table->_SurfaceRevision)))
    { return false; }

    auto Fixture = Make_Fixture(TEXT("CkGroundNavProfileVariantsRevision"));

    if (NOT TestTrue(TEXT("the world composes an entity to publish under"), Get_IsReady(Fixture)))
    {
        Destroy_Fixture(Fixture);
        return false;
    }

    const auto DefaultField = Bake_Field(Make_Profile(kHighStepHeightUu));
    const auto VariantField = Bake_Field(Make_Profile(kLowStepHeightUu));

    if (NOT TestTrue(TEXT("both the default and the variant bake"),
        DefaultField.IsValid() && VariantField.IsValid()))
    {
        Destroy_Fixture(Fixture);
        return false;
    }

    auto VariantFields = TMap<FGameplayTag, FCk_GroundNav_FieldPtr>{};
    VariantFields.Emplace(TAG_CkTests_GroundNav_Profile_Crawler.GetTag(), VariantField);

    world_fields::Publish(Fixture._World, Fixture._VolumeEntity, DefaultField, VariantFields);

    const auto RevisionWithTheVariant = Table->_SurfaceRevision(Fixture._World);

    if (NOT TestTrue(TEXT("the variant's own ground is counted while it is published"),
        world_fields::Get_VariantRevision(Fixture._World) > 0))
    {
        world_fields::Unpublish(Fixture._World, Fixture._VolumeEntity);
        Destroy_Fixture(Fixture);
        return false;
    }

    // The same volume and the same default, with the variant simply gone - what a volume that stopped
    // authoring one republishes.
    world_fields::Publish(
        Fixture._World, Fixture._VolumeEntity, DefaultField,
        TMap<FGameplayTag, FCk_GroundNav_FieldPtr>{});

    const auto RevisionAfterTheDrop = Table->_SurfaceRevision(Fixture._World);

    // The LIVE count has to lose it: the map that held it is gone.
    TestTrue(TEXT("the dropped variant stops being counted as live ground"),
        world_fields::Get_VariantRevision(Fixture._World) == 0);

    // Which is the whole claim - the sum is retired rather than lost, so a number a watcher has already
    // seen can never come round a second time and read as no change.
    TestTrue(FString::Printf(
        TEXT("and the surface revision does not fall across the drop (%lld then %lld)"),
        RevisionWithTheVariant, RevisionAfterTheDrop),
        RevisionAfterTheDrop >= RevisionWithTheVariant);

    world_fields::Unpublish(Fixture._World, Fixture._VolumeEntity);
    Destroy_Fixture(Fixture);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
