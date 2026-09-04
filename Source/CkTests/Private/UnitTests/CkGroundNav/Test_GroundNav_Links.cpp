// What an authored nav link resolves to against the field that carries it, and what that resolution is
// then allowed to claim.
//
// A link is two world points and nothing else. Everything else about it - which tile, which cell,
// which plate, and therefore which reachability component - is DERIVED at every publish, so the tests
// here are about a derivation and not about a stored value: the same records over the same ground must
// give the same entries every time, an end over ground that is missing must be told apart from an end
// over ground that is merely unbaked, and neither may cost the field anything else.
//
// The comparisons are exact. A link that resolved is compared field by field through the shared
// comparator rather than by the one member a case happens to be about, and "the field is otherwise
// identical" is asserted by diffing two whole bakes with the link entries themselves lifted out -
// which is the only form of that claim that could catch a resolution quietly moving a plate.

#include "CkGroundNav/Bake/CkGroundNav_LinkTypes.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Field/CkGroundNav_FieldLinks.h"

#include "Test_GroundNav_FieldEquality.h"
#include "Test_GroundNav_QueryFixtures.h"

#include "../CkUnitTest_Common.h"

#include "NativeGameplayTags.h"

#include <CoreMinimal.h>

#include <type_traits>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_CkTests_GroundNav_Link_Ladder, "CkTests.GroundNav.Link.Ladder");
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_CkTests_GroundNav_Link_Drop, "CkTests.GroundNav.Link.Drop");

namespace ck_test_groundnav_links
{
    using ck::groundnav::DoLabel_Reachability;
    using ck::groundnav::DoResolve_Links;
    using ck::groundnav::FCk_GroundNav_Epoch;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldParams;
    using ck::groundnav::FCk_GroundNav_FieldPtr;
    using ck::groundnav::FCk_GroundNav_SurfaceRef;
    using ck::groundnav::Get_FieldWithLinks;

    using ck_test_groundnav_field_equality::EEpochComparison;
    using ck_test_groundnav_field_equality::EPolicyComparison;
    using ck_test_groundnav_field_equality::Get_FieldsEqualIncludingEpochs;
    using ck_test_groundnav_field_equality::Get_FirstFieldDifference;

    using ck_test_groundnav_queryfixtures::Bake;
    using ck_test_groundnav_queryfixtures::Do_MakeTileUnbuiltAt;
    using ck_test_groundnav_queryfixtures::Get_TileCentre;
    using ck_test_groundnav_queryfixtures::kFlatProbeX;
    using ck_test_groundnav_queryfixtures::kFlatProbeY;
    using ck_test_groundnav_queryfixtures::kGroundZ;
    using ck_test_groundnav_queryfixtures::kHoleMax;
    using ck_test_groundnav_queryfixtures::kHoleMin;
    using ck_test_groundnav_queryfixtures::Make_FlatParams;
    using ck_test_groundnav_queryfixtures::Make_FlatScene;
    using ck_test_groundnav_queryfixtures::Make_QueryParams;
    using ck_test_groundnav_queryfixtures::Make_QueryScene;

    // --------------------------------------------------------------------------------------------------

    // The link value types carry no raw pointer, no TObjectPtr and no TWeakObjectPtr: an
    //   rg -n "TObjectPtr|TWeakObjectPtr|\w+\s*\*\s*_" over
    //   CkGroundNav/Bake/CkGroundNav_LinkTypes.h and CkGroundNav/Field/CkGroundNav_FieldTypes.h
    // matches nothing, which is what lets a resolved entry be copied out of the field it was derived
    // on and outlive it.
    //
    // Pinned here on the addressing leaf, which is integers alone. FCk_GroundNav_ResolvedLink itself
    // carries two FGameplayTags, and whether THAT type is trivially copyable is the engine's decision
    // rather than this module's, so asserting on the whole entry would pin somebody else's contract.
    // The case below pins what the assert cannot: an entry copied out of a field that is then
    // destroyed still reads everything it resolved to.
    static_assert(std::is_trivially_copyable_v<FCk_GroundNav_SurfaceRef>,
        "A resolved link's endpoint address must stay copyable as bytes - anything with a lifetime in it is a lifetime the copy could outlive");

    // --------------------------------------------------------------------------------------------------

    constexpr auto kBakeCount = 20;

    // The two-island scene: two floors with a gap wider than any halo between them, so no portal and no
    // seam joins them and a link is the only thing that can. Same shape as the one
    // Test_GroundNav_Query_Reachability.cpp's Make_TwoIslandScene uses to make a label comparison mean Unreachable,
    // repeated here because that copy is a file-local helper of that file's own namespace.
    constexpr auto kIslandGapMinX = 600.0;
    constexpr auto kIslandGapMaxX = 1000.0;

    // One point per island, clear of both the gap and every tile boundary.
    const auto kIslandAPoint = FVector{200.0, 400.0, kGroundZ};
    const auto kIslandBPoint = FVector{1500.0, 400.0, kGroundZ};

    // Over the square of missing floor, far enough inside it that a default projection box reaches no
    // ground at all in any direction.
    const auto kHolePoint = FVector{(kHoleMin + kHoleMax) * 0.5, (kHoleMin + kHoleMax) * 0.5, kGroundZ};

    // On the floor of tile 0 of the query scene, interior to its cell.
    const auto kGroundPoint = FVector{kFlatProbeX, kFlatProbeY, kGroundZ};

    // On the floor of tile 3 of the query scene - the tile a case can take away.
    const auto kFarTilePoint = FVector{1400.0, 1400.0, kGroundZ};

    // The two tiles the points above stand on, in a 2x2 field of 800 uu tiles from the world origin.
    constexpr auto kGroundTileIndex = 0;
    constexpr auto kFarTileIndex = 3;

    // Two points on the flat scene's single tile, for the cases whose answer must not depend on
    // anything else in the world.
    const auto kFlatLinkStartA = FVector{200.0, 200.0, kGroundZ};
    const auto kFlatLinkEndA = FVector{600.0, 200.0, kGroundZ};
    const auto kFlatLinkStartB = FVector{200.0, 600.0, kGroundZ};
    const auto kFlatLinkEndB = FVector{600.0, 600.0, kGroundZ};

    // --------------------------------------------------------------------------------------------------

    auto Make_TwoIslandScene() -> TArray<FBox>
    {
        return TArray<FBox>{
            FBox{FVector{-400.0, -400.0, -10.0}, FVector{kIslandGapMinX, 2000.0, kGroundZ}},
            FBox{FVector{kIslandGapMaxX, -400.0, -10.0}, FVector{2000.0, 2000.0, kGroundZ}}};
    }

    /** A link carrying an authored value in every field a resolution copies, so a round trip can lose any of them. */
    auto Make_Link(
        int32          InId,
        const FVector& InStart,
        const FVector& InEnd) -> FCk_GroundNav_LinkRecord
    {
        auto Record = FCk_GroundNav_LinkRecord{InId, InStart, InEnd};

        Record.Set_Direction(ECk_GroundNav_LinkDirection::Bidirectional);
        Record.Set_CostMultiplierForward(2.0f);
        Record.Set_CostMultiplierBackward(3.0f);
        Record.Set_ClearanceUu(60.0f);
        Record.Set_AreaTag(TAG_CkTests_GroundNav_Link_Ladder);
        Record.Set_UserTypeTag(TAG_CkTests_GroundNav_Link_Drop);

        return Record;
    }

    auto Bake_WithLinks(
        const TArray<FBox>&                     InBoxes,
        const FCk_GroundNav_FieldParams&        InBaseParams,
        const TArray<FCk_GroundNav_LinkRecord>& InLinks,
        FCk_GroundNav_Field&                    OutField) -> bool
    {
        auto Params = InBaseParams;
        Params._Links = InLinks;

        return Bake(InBoxes, Params, OutField);
    }

    /**
     * Everything the field comparator compares EXCEPT the link entries and their count.
     *
     * That pair is exactly what an extra record is allowed to move, so lifting it out is what turns
     * "otherwise identical" into an assertion: a resolution that also moved a plate, a portal, a label
     * or a boundary run fails this, and a resolution that moved only its own entry passes.
     */
    auto Get_FirstDifferenceIgnoringLinks(
        const FCk_GroundNav_Field& InLhs,
        const FCk_GroundNav_Field& InRhs) -> FString
    {
        auto Lhs = FCk_GroundNav_Field{InLhs};
        auto Rhs = FCk_GroundNav_Field{InRhs};

        Lhs._ResolvedLinks.Reset();
        Lhs._UnresolvedLinkCount = 0;

        Rhs._ResolvedLinks.Reset();
        Rhs._UnresolvedLinkCount = 0;

        return Get_FirstFieldDifference(Lhs, Rhs, EPolicyComparison::Include, EEpochComparison::Exclude);
    }

    /** The component label of a flat plate, or INDEX_NONE where the field has no such plate. */
    auto Get_LabelOfFlatPlate(
        const FCk_GroundNav_Field& InField,
        int32                      InFlatPlate) -> int32
    {
        if (NOT InField._ReachabilityLabels.IsValidIndex(InFlatPlate))
        { return INDEX_NONE; }

        return InField._ReachabilityLabels[InFlatPlate];
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Links_RecordRoundTripsThroughTheField,
    "CkTests.UnitTests.CkGroundNav.Links.RecordRoundTripsThroughTheField",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Links_RecordRoundTripsThroughTheField::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_links;

    const auto Links = TArray<FCk_GroundNav_LinkRecord>{
        Make_Link(1, kFlatLinkStartA, kFlatLinkEndA),
        Make_Link(2, kFlatLinkStartB, kFlatLinkEndB)};

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the flat scene bakes with two links"),
        Bake_WithLinks(Make_FlatScene(), Make_FlatParams(), Links, Field)))
    { return false; }

    if (NOT TestTrue(TEXT("and carries one resolved entry per authored record"),
        Field.Get_ResolvedLinkCount() == Links.Num()))
    { return false; }

    TestEqual(TEXT("with nothing left unresolved"), Field.Get_UnresolvedLinkCount(), 0);

    for (auto Index = 0; Index < Links.Num(); ++Index)
    {
        const auto& Record = Links[Index];
        const auto& Entry = Field._ResolvedLinks[Index];

        // Entries are in the params' own order, so an index into the array means the same link across
        // two publishes of the same records.
        TestEqual(FString::Printf(TEXT("entry %d keeps the authored id"), Index),
            Entry._Id, Record.Get_Id());

        TestTrue(FString::Printf(TEXT("entry %d keeps the authored start"), Index),
            Entry._Start == Record.Get_Start());
        TestTrue(FString::Printf(TEXT("entry %d keeps the authored end"), Index),
            Entry._End == Record.Get_End());
        TestTrue(FString::Printf(TEXT("entry %d keeps the authored direction"), Index),
            Entry._Direction == Record.Get_Direction());
        TestTrue(FString::Printf(TEXT("entry %d keeps the forward multiplier"), Index),
            Entry._CostMultiplierForward == Record.Get_CostMultiplierForward());
        TestTrue(FString::Printf(TEXT("entry %d keeps the backward multiplier"), Index),
            Entry._CostMultiplierBackward == Record.Get_CostMultiplierBackward());
        TestTrue(FString::Printf(TEXT("entry %d keeps the authored clearance"), Index),
            Entry._ClearanceUu == Record.Get_ClearanceUu());
        TestTrue(FString::Printf(TEXT("entry %d keeps the area tag"), Index),
            Entry._AreaTag == Record.Get_AreaTag());
        TestTrue(FString::Printf(TEXT("entry %d keeps the user type tag"), Index),
            Entry._UserTypeTag == Record.Get_UserTypeTag());
        TestTrue(FString::Printf(TEXT("entry %d keeps the enabled state"), Index),
            Entry._Enable == Record.Get_Enable());

        TestTrue(FString::Printf(TEXT("entry %d resolved both ends"), Index), Entry.Get_IsResolved());
        TestTrue(FString::Printf(TEXT("entry %d is traversable"), Index), Entry.Get_IsTraversable());

        TestTrue(FString::Printf(TEXT("entry %d names a start plate"), Index),
            Entry._StartFlatPlate != INDEX_NONE);
        TestTrue(FString::Printf(TEXT("entry %d names an end plate"), Index),
            Entry._EndFlatPlate != INDEX_NONE);

        TestTrue(FString::Printf(TEXT("entry %d names a start surface"), Index),
            Entry._StartSurface.Get_IsValid());
        TestTrue(FString::Printf(TEXT("entry %d names an end surface"), Index),
            Entry._EndSurface.Get_IsValid());
    }

    TestTrue(TEXT("a field with links compares equal to itself"),
        Get_FieldsEqualIncludingEpochs(Field, Field, EPolicyComparison::Include));

    const auto Copy = FCk_GroundNav_Field{Field};

    TestTrue(TEXT("and to a value copy of itself, epochs included"),
        Get_FieldsEqualIncludingEpochs(Field, Copy, EPolicyComparison::Include));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Links_EndpointOverAHoleIsUnresolvedAndCounted,
    "CkTests.UnitTests.CkGroundNav.Links.EndpointOverAHoleIsUnresolvedAndCounted",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Links_EndpointOverAHoleIsUnresolvedAndCounted::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_links;

    const auto OverTheHole = TArray<FCk_GroundNav_LinkRecord>{
        Make_Link(1, kGroundPoint, kHolePoint)};

    auto WithLink = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes with a link that reaches over the hole"),
        Bake_WithLinks(Make_QueryScene(), Make_QueryParams(), OverTheHole, WithLink)))
    { return false; }

    auto WithoutLink = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("and bakes again with no link at all"),
        Bake_WithLinks(Make_QueryScene(), Make_QueryParams(), {}, WithoutLink)))
    { return false; }

    if (NOT TestTrue(TEXT("the link is held rather than dropped"), WithLink.Get_ResolvedLinkCount() == 1))
    { return false; }

    const auto& Entry = WithLink._ResolvedLinks[0];

    TestEqual(TEXT("exactly one link reads unresolved"), WithLink.Get_UnresolvedLinkCount(), 1);

    TestTrue(TEXT("the end over the hole found no surface"),
        Entry._EndStatus == ECk_NavSurface_QueryStatus::NoSurface);

    // NoSurface, not Unbuilt: every tile the box reached is built, so this is ground that will not
    // arrive later and the two answers are never conflated.
    TestTrue(TEXT("and the end over ground resolved"),
        Entry._StartStatus == ECk_NavSurface_QueryStatus::Success);

    TestTrue(TEXT("the unresolved end names no plate"), Entry._EndFlatPlate == INDEX_NONE);
    TestTrue(TEXT("and no surface"), NOT Entry._EndSurface.Get_IsValid());

    TestTrue(TEXT("the resolved end still names one"), Entry._StartFlatPlate != INDEX_NONE);

    TestFalse(TEXT("the link is not resolved"), Entry.Get_IsResolved());
    TestFalse(TEXT("and not traversable"), Entry.Get_IsTraversable());

    TestEqual(TEXT("the bake without the link holds none"), WithoutLink.Get_ResolvedLinkCount(), 0);
    TestEqual(TEXT("and counts none unresolved"), WithoutLink.Get_UnresolvedLinkCount(), 0);

    const auto Difference = Get_FirstDifferenceIgnoringLinks(WithLink, WithoutLink);

    if (NOT Difference.IsEmpty())
    {
        AddError(FString::Printf(
            TEXT("a link with an unresolved end changed the field somewhere else, at %s"), *Difference));
        return false;
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Links_EndpointOverAnUnbuiltTileIsHeldNotDropped,
    "CkTests.UnitTests.CkGroundNav.Links.EndpointOverAnUnbuiltTileIsHeldNotDropped",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Links_EndpointOverAnUnbuiltTileIsHeldNotDropped::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_links;

    const auto AcrossTheField = TArray<FCk_GroundNav_LinkRecord>{
        Make_Link(1, kGroundPoint, kFarTilePoint)};

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes with a link that spans two tiles"),
        Bake_WithLinks(Make_QueryScene(), Make_QueryParams(), AcrossTheField, Field)))
    { return false; }

    if (NOT TestTrue(TEXT("both ends resolve while every tile is built"),
        Field.Get_ResolvedLinkCount() == 1 && Field._ResolvedLinks[0].Get_IsResolved()))
    { return false; }

    if (NOT TestTrue(TEXT("the tile under the far end can be taken away"),
        Do_MakeTileUnbuiltAt(Field, Get_TileCentre(Field, kFarTileIndex)) == kFarTileIndex))
    { return false; }

    // Every pass that depends on the tile is re-run here in the order the composers run them in: the
    // seams, then the resolution, then the labels.
    DoResolve_Links(Field);
    DoLabel_Reachability(Field);

    const auto& Entry = Field._ResolvedLinks[0];

    TestEqual(TEXT("the link is still held"), Field.Get_ResolvedLinkCount(), 1);
    TestEqual(TEXT("and counted unresolved"), Field.Get_UnresolvedLinkCount(), 1);

    // Unbuilt, never NoSurface: the answer may be in the tile nobody has baked, and the next publish
    // over it resolves the end without the author touching the record.
    TestTrue(TEXT("the end over the unbuilt tile reads Unbuilt"),
        Entry._EndStatus == ECk_NavSurface_QueryStatus::Unbuilt);

    TestTrue(TEXT("the end over built ground still resolved"),
        Entry._StartStatus == ECk_NavSurface_QueryStatus::Success);

    TestTrue(TEXT("the held end names no plate"), Entry._EndFlatPlate == INDEX_NONE);

    TestFalse(TEXT("the link is not resolved"), Entry.Get_IsResolved());
    TestFalse(TEXT("and not traversable"), Entry.Get_IsTraversable());

    // The record itself is untouched: what the field could not answer is not the author's mistake.
    TestEqual(TEXT("the authored record is still on the field's params"),
        Field._Params._Links.Num(), 1);
    TestTrue(TEXT("with its endpoints as authored"),
        Field._Params._Links[0].Get_End() == kFarTilePoint);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Links_LinkJoinsTwoComponentsIntoOneLabel,
    "CkTests.UnitTests.CkGroundNav.Links.LinkJoinsTwoComponentsIntoOneLabel",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Links_LinkJoinsTwoComponentsIntoOneLabel::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_links;

    auto Joining = Make_Link(1, kIslandAPoint, kIslandBPoint);

    auto Joined = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the two-island scene bakes with a link across the gap"),
        Bake_WithLinks(Make_TwoIslandScene(), Make_QueryParams(),
            TArray<FCk_GroundNav_LinkRecord>{Joining}, Joined)))
    { return false; }

    if (NOT TestTrue(TEXT("the link resolves on both islands"),
        Joined.Get_ResolvedLinkCount() == 1 && Joined._ResolvedLinks[0].Get_IsResolved()))
    { return false; }

    const auto StartPlate = Joined._ResolvedLinks[0]._StartFlatPlate;
    const auto EndPlate = Joined._ResolvedLinks[0]._EndFlatPlate;

    if (NOT TestTrue(TEXT("and lands on two different plates"), StartPlate != EndPlate))
    { return false; }

    auto Unjoined = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the same scene bakes with no link"),
        Bake_WithLinks(Make_TwoIslandScene(), Make_QueryParams(), {}, Unjoined)))
    { return false; }

    // A link changes no plate, so the two bakes number their plates identically and one bake's flat
    // plate indices read the other's labels. Asserted rather than assumed - it is what every label
    // comparison below rests on.
    if (NOT TestTrue(TEXT("both bakes number their plates the same way"),
        Joined._TilePlateOffsets == Unjoined._TilePlateOffsets &&
        Joined._ReachabilityLabels.Num() == Unjoined._ReachabilityLabels.Num()))
    { return false; }

    TestTrue(TEXT("with the link, the two islands share one label"),
        Get_LabelOfFlatPlate(Joined, StartPlate) == Get_LabelOfFlatPlate(Joined, EndPlate) &&
        Get_LabelOfFlatPlate(Joined, StartPlate) != INDEX_NONE);

    TestTrue(TEXT("without it they do not"),
        Get_LabelOfFlatPlate(Unjoined, StartPlate) != Get_LabelOfFlatPlate(Unjoined, EndPlate));

    auto Disabled = Joining;
    Disabled.Set_Enable(ECk_EnableDisable::Disable);

    auto WithDisabled = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the scene bakes with the link switched off"),
        Bake_WithLinks(Make_TwoIslandScene(), Make_QueryParams(),
            TArray<FCk_GroundNav_LinkRecord>{Disabled}, WithDisabled)))
    { return false; }

    // A disabled link is still RESOLVED - the ground under it is what it is - and still joins nothing.
    TestTrue(TEXT("a disabled link still resolves both ends"),
        WithDisabled._ResolvedLinks[0].Get_IsResolved());
    TestFalse(TEXT("but is not traversable"), WithDisabled._ResolvedLinks[0].Get_IsTraversable());
    TestEqual(TEXT("and is not counted unresolved"), WithDisabled.Get_UnresolvedLinkCount(), 0);

    TestTrue(TEXT("so the two islands keep their separate labels"),
        Get_LabelOfFlatPlate(WithDisabled, StartPlate) != Get_LabelOfFlatPlate(WithDisabled, EndPlate));

    auto Forward = Joining;
    Forward.Set_Direction(ECk_GroundNav_LinkDirection::Forward);

    auto WithForward = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the scene bakes with a one-directional link"),
        Bake_WithLinks(Make_TwoIslandScene(), Make_QueryParams(),
            TArray<FCk_GroundNav_LinkRecord>{Forward}, WithForward)))
    { return false; }

    // A label only ever promises that a DIFFERENT label is provably unreachable, and a one-way route
    // leaves that proof unavailable in both directions - so direction does not enter the union.
    TestTrue(TEXT("a forward-only link joins the labels just as a bidirectional one does"),
        Get_LabelOfFlatPlate(WithForward, StartPlate) == Get_LabelOfFlatPlate(WithForward, EndPlate));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Links_BakeIsDeterministicWithLinks,
    "CkTests.UnitTests.CkGroundNav.Links.BakeIsDeterministicWithLinks",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Links_BakeIsDeterministicWithLinks::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_links;

    // One link that resolves on both ends, one that cannot: a resolution that depended on iteration
    // order or on a hash would show up in either, and the unresolved one also pins the counter.
    const auto Links = TArray<FCk_GroundNav_LinkRecord>{
        Make_Link(1, kGroundPoint, kFarTilePoint),
        Make_Link(2, kGroundPoint, kHolePoint)};

    auto First = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes with links"),
        Bake_WithLinks(Make_QueryScene(), Make_QueryParams(), Links, First)))
    { return false; }

    if (NOT TestTrue(TEXT("and the fixture produces links worth comparing"),
        First.Get_ResolvedLinkCount() == 2 && First.Get_UnresolvedLinkCount() == 1))
    { return false; }

    for (auto BakeIndex = 1; BakeIndex < kBakeCount; ++BakeIndex)
    {
        auto Other = FCk_GroundNav_Field{};

        if (NOT TestTrue(FString::Printf(TEXT("bake %d of the same scene completes"), BakeIndex),
            Bake_WithLinks(Make_QueryScene(), Make_QueryParams(), Links, Other)))
        { return false; }

        const auto Difference = Get_FirstFieldDifference(
            First, Other, EPolicyComparison::Include, EEpochComparison::Include);

        if (Difference.IsEmpty())
        { continue; }

        AddError(FString::Printf(
            TEXT("bake %d of the same scene and the same links differs from the first at %s"),
            BakeIndex, *Difference));

        return false;
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Links_NoPointerInTheLinkValueTypes,
    "CkTests.UnitTests.CkGroundNav.Links.NoPointerInTheLinkValueTypes",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Links_NoPointerInTheLinkValueTypes::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_links;

    const auto Record = Make_Link(7, kFlatLinkStartA, kFlatLinkEndA);

    auto Field = MakeUnique<FCk_GroundNav_Field>();

    if (NOT TestTrue(TEXT("the flat scene bakes with a link"),
        Bake_WithLinks(Make_FlatScene(), Make_FlatParams(),
            TArray<FCk_GroundNav_LinkRecord>{Record}, *Field)))
    { return false; }

    if (NOT TestTrue(TEXT("and resolves it"),
        Field->Get_ResolvedLinkCount() == 1 && Field->_ResolvedLinks[0].Get_IsResolved()))
    { return false; }

    // A value copy taken out of the field, which is then destroyed under it. Everything the entry
    // answers afterwards is something it owns rather than something it points at.
    const auto Entry = Field->_ResolvedLinks[0];

    Field.Reset();

    TestEqual(TEXT("the copy keeps its id with the field gone"), Entry._Id, Record.Get_Id());
    TestTrue(TEXT("and its endpoints"),
        Entry._Start == Record.Get_Start() && Entry._End == Record.Get_End());
    TestTrue(TEXT("and its tags"),
        Entry._AreaTag == Record.Get_AreaTag() && Entry._UserTypeTag == Record.Get_UserTypeTag());
    TestTrue(TEXT("and its plates"),
        Entry._StartFlatPlate != INDEX_NONE && Entry._EndFlatPlate != INDEX_NONE);
    TestTrue(TEXT("and still says it resolved"), Entry.Get_IsResolved());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Links_DeriveMovesOnlyTheEndpointTilesOfAChangedLink,
    "CkTests.UnitTests.CkGroundNav.Links.DeriveMovesOnlyTheEndpointTilesOfAChangedLink",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Links_DeriveMovesOnlyTheEndpointTilesOfAChangedLink::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_links;

    const auto SourceEpoch = FCk_GroundNav_Epoch{1};

    auto Source = MakeShared<FCk_GroundNav_Field>();

    // The shared fixture bakes at epoch 1, which is what SourceEpoch names.
    if (NOT TestTrue(TEXT("the query scene bakes and publishes with no links"),
        Bake_WithLinks(Make_QueryScene(), Make_QueryParams(), {}, *Source)))
    { return false; }

    const auto Published = FCk_GroundNav_FieldPtr{Source};

    if (NOT TestTrue(TEXT("the published field has its four tiles"), Published->_Tiles.Num() == 4))
    { return false; }

    const auto Links = TArray<FCk_GroundNav_LinkRecord>{
        Make_Link(1, kGroundPoint, kFarTilePoint)};

    const auto AddedEpoch = SourceEpoch.Get_Next();
    const auto Added = Get_FieldWithLinks(*Published, Links, AddedEpoch);

    if (NOT TestTrue(TEXT("the derive completes and yields a field"),
        Added.Value.Get_IsCompleted() && Added.Key.IsValid()))
    { return false; }

    TestEqual(TEXT("a link derive spends no probes"), Added.Value.Get_ProbesSpent(), 0);

    TestTrue(TEXT("the published field a reader is holding is untouched"),
        Published->Get_ResolvedLinkCount() == 0);

    if (NOT TestTrue(TEXT("the added link resolves on both ends"),
        Added.Key->Get_ResolvedLinkCount() == 1 && Added.Key->_ResolvedLinks[0].Get_IsResolved()))
    { return false; }

    for (auto TileIndex = 0; TileIndex < Added.Key->_Tiles.Num(); ++TileIndex)
    {
        const auto HoldsAnEnd = TileIndex == kGroundTileIndex || TileIndex == kFarTileIndex;
        const auto Expected = HoldsAnEnd ? AddedEpoch : SourceEpoch;

        TestTrue(FString::Printf(
            TEXT("tile %d %s the added link's ends and carries epoch %lld"),
            TileIndex, HoldsAnEnd ? TEXT("holds one of") : TEXT("holds neither of"),
            Added.Key->_Tiles[TileIndex]._Epoch._Value),
            Added.Key->_Tiles[TileIndex]._Epoch == Expected);
    }

    TestTrue(TEXT("and the field follows the tiles that moved"), Added.Key->_Epoch == AddedEpoch);

    // The same list again. Every record resolves to what it already resolved to, so there is nothing
    // for a reader to notice and nothing that may be stamped.
    const auto UnchangedEpoch = AddedEpoch.Get_Next();
    const auto Unchanged = Get_FieldWithLinks(*Added.Key, Links, UnchangedEpoch);

    if (NOT TestTrue(TEXT("the second derive completes and yields a field"),
        Unchanged.Value.Get_IsCompleted() && Unchanged.Key.IsValid()))
    { return false; }

    TestTrue(TEXT("a derive that changed no link moves no field epoch"),
        Unchanged.Key->_Epoch == AddedEpoch);

    for (auto TileIndex = 0; TileIndex < Unchanged.Key->_Tiles.Num(); ++TileIndex)
    {
        TestTrue(FString::Printf(TEXT("and leaves tile %d's epoch where it was"), TileIndex),
            Unchanged.Key->_Tiles[TileIndex]._Epoch == Added.Key->_Tiles[TileIndex]._Epoch);
    }

    auto Disabled = Links;
    Disabled[0].Set_Enable(ECk_EnableDisable::Disable);

    const auto DisabledEpoch = UnchangedEpoch.Get_Next();
    const auto Switched = Get_FieldWithLinks(*Unchanged.Key, Disabled, DisabledEpoch);

    if (NOT TestTrue(TEXT("the derive after the switch-off completes and yields a field"),
        Switched.Value.Get_IsCompleted() && Switched.Key.IsValid()))
    { return false; }

    TestFalse(TEXT("the link is no longer traversable"),
        Switched.Key->_ResolvedLinks[0].Get_IsTraversable());

    for (auto TileIndex = 0; TileIndex < Switched.Key->_Tiles.Num(); ++TileIndex)
    {
        const auto HoldsAnEnd = TileIndex == kGroundTileIndex || TileIndex == kFarTileIndex;
        const auto Expected = HoldsAnEnd ? DisabledEpoch : Unchanged.Key->_Tiles[TileIndex]._Epoch;

        TestTrue(FString::Printf(
            TEXT("switching the link off moves tile %d to epoch %lld"),
            TileIndex, Switched.Key->_Tiles[TileIndex]._Epoch._Value),
            Switched.Key->_Tiles[TileIndex]._Epoch == Expected);
    }

    TestTrue(TEXT("with the field following it"), Switched.Key->_Epoch == DisabledEpoch);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
