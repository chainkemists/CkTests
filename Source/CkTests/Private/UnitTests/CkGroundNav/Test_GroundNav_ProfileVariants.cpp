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
// Pure value logic over the stub backend: no world, no registry, no physics.

#include "CkGroundNav/Backend/CkGroundNav_GeometryBackend_Stub.h"
#include "CkGroundNav/Bake/CkGroundNav_Fingerprint.h"
#include "CkGroundNav/Field/CkGroundNav_FieldBuild.h"

#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "Test_GroundNav_FieldEquality.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

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
