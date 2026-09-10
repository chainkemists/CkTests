#include "CkAutoTestMapPopulator.h"

#include "CkAutoTestRunner.h"

#include "CkCore/Macros/CkMacros.h"

#include <AssetRegistry/AssetData.h>
#include <Engine/StaticMeshActor.h>
#include <Misc/AutomationTest.h>

// --------------------------------------------------------------------------------------------------------------------

namespace ck_autotest_populator_wipefloor_tests
{
    // Uniquely named rather than reusing CkTests' kCkUnitTestFlags: that constant lives in
    // the CkTests module's Private tree and is not reachable from CkTestsEditor. Its own
    // header explains why a test needing different flags declares its own.
    inline constexpr auto kFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ProductFilter;

    // Minimal FAssetData carrying the one tag the wrapper rule reads.
    static auto Make_ExternalActorAsset(
        const FString& InActorMetaDataClass) -> FAssetData
    {
        auto Tags = FAssetDataTagMap{};
        if (NOT InActorMetaDataClass.IsEmpty())
        { Tags.Add(TEXT("ActorMetaDataClass"), InActorMetaDataClass); }

        return FAssetData{
            FName{TEXT("/Game/Map/__ExternalActors__/AutoTests/0/AB/CDEF")},
            FName{TEXT("/Game/Map/__ExternalActors__/AutoTests/0/AB")},
            FName{TEXT("CDEF")},
            FTopLevelAssetPath{TEXT("/Script/Angelscript"), TEXT("Ck_AutoTest_Foo_Actor")},
            MoveTemp(Tags)};
    }
}

// --------------------------------------------------------------------------------------------------------------------

// The floor itself. Each row is a state the populator can genuinely be in; the two that
// must NOT refuse are as load-bearing as the one that must, because a floor that refuses
// a legitimate sync breaks the feature it is protecting.
IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_AutoTestPopulator_WipeFloor_RefusesOnlyWhenDiscoveryIsEmpty,
    "Ck.AutoTest.Populator.WipeFloor.RefusesOnlyWhenDiscoveryIsEmpty",
    ck_autotest_populator_wipefloor_tests::kFlags)

bool FCkTest_AutoTestPopulator_WipeFloor_RefusesOnlyWhenDiscoveryIsEmpty::RunTest(const FString& Parameters)
{
    const auto WouldWipe = &UCkAutoTestMapPopulator::Get_WouldWipeUnrecognizedWrappers;

    // THE case being floored: discovery collapsed (renamed plugin folder, a ClassScanRoot
    // that stopped matching the class's absolute source path, AngelScript never compiled)
    // while the map is full of wrappers.
    TestTrue(TEXT("Empty discovery against a populated map REFUSES"),
        WouldWipe(0, 533));

    // One wrapper is enough. There is no quorum below which destroying the corpus is fine.
    TestTrue(TEXT("Empty discovery against a single wrapper REFUSES"),
        WouldWipe(0, 1));

    // A map that legitimately holds nothing yet. Refusing here would mean a config could
    // never populate its map for the first time.
    TestFalse(TEXT("Empty discovery against an empty map does NOT refuse"),
        WouldWipe(0, 0));

    // The steady state: everything discovered, everything present.
    TestFalse(TEXT("Matched discovery does NOT refuse"),
        WouldWipe(533, 533));

    // A fresh map with tests to spawn. Nothing is destroyed on this path.
    TestFalse(TEXT("Discovery with an unpopulated map does NOT refuse"),
        WouldWipe(533, 0));

    // Deliberately NOT refused, and this is the row that keeps the predicate honest: a
    // non-empty wanted set that intersects nothing placed is a genuinely stale map (copied
    // from another project, or a config repointed at a new target), and syncing it is the
    // correct thing to do. A ratio-based floor would refuse this and be wrong.
    TestFalse(TEXT("One discovered class against a stale map does NOT refuse"),
        WouldWipe(1, 533));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// The floor counts wrappers through this rule, so a regression here does not fail loudly --
// it makes Count_WrapperPackagesOnDisk return 0 and the floor silently stops floring.
IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_AutoTestPopulator_WipeFloor_RecognisesWrapperPackages,
    "Ck.AutoTest.Populator.WipeFloor.RecognisesWrapperPackages",
    ck_autotest_populator_wipefloor_tests::kFlags)

bool FCkTest_AutoTestPopulator_WipeFloor_RecognisesWrapperPackages::RunTest(const FString& Parameters)
{
    using namespace ck_autotest_populator_wipefloor_tests;

    const auto Kind = &UCkAutoTestMapPopulator::Get_WrapperPackageKind;

    TestTrue(TEXT("A package whose ActorMetaDataClass is ACk_AutoTestRunner is a wrapper"),
        Kind(Make_ExternalActorAsset(ACk_AutoTestRunner::StaticClass()->GetPathName()))
            == ECk_AutoTestWrapperPackageKind::Wrapper);

    TestTrue(TEXT("A package with an unrelated native class is not a wrapper"),
        Kind(Make_ExternalActorAsset(AStaticMeshActor::StaticClass()->GetPathName()))
            == ECk_AutoTestWrapperPackageKind::NotAWrapper);

    // The distinction the three-valued result exists for: "no tag" and "tag naming a class
    // this build does not have" are different answers, and the pre-check acts on them
    // differently -- the first forces a full pass, the second is skipped as none of the
    // populator's business.
    TestTrue(TEXT("A package with no ActorMetaDataClass tag reads as UnreadableMetadata"),
        Kind(Make_ExternalActorAsset(FString{}))
            == ECk_AutoTestWrapperPackageKind::UnreadableMetadata);

    TestTrue(TEXT("A package whose recorded class no longer resolves is not a wrapper"),
        Kind(Make_ExternalActorAsset(TEXT("/Script/NoSuchModule.ANoSuchClass")))
            == ECk_AutoTestWrapperPackageKind::NotAWrapper);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// The DECISION, not just the predicate. This is the half review found unpinned: the rule
// was single-sourced from the start but its handling was not, and the drift it produced was
// a real defect -- an authorised UNFORCED pass fell past the floor into the pre-check with
// an empty wanted set and reported "Already in sync -- 0 wrapper(s) verified".
IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_AutoTestPopulator_WipeFloor_DecisionAndWording,
    "Ck.AutoTest.Populator.WipeFloor.DecisionAndWording",
    ck_autotest_populator_wipefloor_tests::kFlags)

bool FCkTest_AutoTestPopulator_WipeFloor_DecisionAndWording::RunTest(const FString& Parameters)
{
    const auto Evaluate = [](int32 InWanted, int32 InAssociated, int32 InResident, bool bInAuthorised)
    {
        return UCkAutoTestMapPopulator::Evaluate_WipeFloor(
            TEXT("TestConfig"), TEXT("/Game/Map/AutoTests"), InWanted, InAssociated, InResident, bInAuthorised);
    };

    // Unauthorised: refuse, and carry a reason the caller can record.
    {
        const auto Verdict = Evaluate(0, 531, 531, /*bInAuthorised=*/false);
        TestTrue(TEXT("Unauthorised empty discovery REFUSES"),
            Verdict.Decision == ECk_AutoTestWipeFloorDecision::Refuse);
        TestTrue(TEXT("A refusal carries a reason"), NOT Verdict.Reason.IsEmpty());
        TestTrue(TEXT("A refusal carries an explanation"), NOT Verdict.Explanation.IsEmpty());
    }

    // Authorised: proceed, but as its OWN outcome so the authorisation gets announced.
    // A plain Proceed here would let a CVar left in an .ini wipe a map silently.
    {
        const auto Verdict = Evaluate(0, 531, 531, /*bInAuthorised=*/true);
        TestTrue(TEXT("Authorised empty discovery is ProceedAuthorised, not plain Proceed"),
            Verdict.Decision == ECk_AutoTestWipeFloorDecision::ProceedAuthorised);
        TestTrue(TEXT("An authorised wipe still says so"), NOT Verdict.Explanation.IsEmpty());
    }

    // Authorisation is not reachable on an unforced pass. This pins the fix for the defect
    // above at the level that matters: the CVar alone must never be enough.
    //
    // Asserted through Get_IsWipeAuthorised with the CVar state passed IN. Asserting on
    // Get_WipeAuthorisation instead would be vacuous -- the CVar defaults to 0, so the
    // conjunction is false whether or not the forced clause exists, and the test would stay
    // green with the fix reverted.
    {
        TestFalse(TEXT("CVar set but pass NOT forced is NOT authorised"),
            UCkAutoTestMapPopulator::Get_IsWipeAuthorised(/*bInCVarSet=*/true, /*bInIsForcedPass=*/false));
        TestFalse(TEXT("Forced but CVar NOT set is NOT authorised"),
            UCkAutoTestMapPopulator::Get_IsWipeAuthorised(/*bInCVarSet=*/false, /*bInIsForcedPass=*/true));
        TestTrue(TEXT("CVar set AND forced IS authorised"),
            UCkAutoTestMapPopulator::Get_IsWipeAuthorised(/*bInCVarSet=*/true, /*bInIsForcedPass=*/true));
    }

    // Healthy project: no verdict, no wording, nothing to announce.
    {
        const auto Verdict = Evaluate(531, 531, 531, /*bInAuthorised=*/false);
        TestTrue(TEXT("A healthy pass proceeds"),
            Verdict.Decision == ECk_AutoTestWipeFloorDecision::Proceed);
        TestTrue(TEXT("A proceeding pass has nothing to say"), Verdict.Explanation.IsEmpty());
    }

    // TRUTHFULNESS. The refusal states a consequence, and that consequence is only real
    // when the wrapper classes are resident: with none resident there are no actors for the
    // orphan sweep and no loaded objects for the stranded pass, so a sync would have
    // deleted nothing today. Review caught the message asserting the deletion in both
    // states. A refusal that overstates its own stakes is no more trustworthy than one that
    // hides them.
    {
        const auto Resident = Evaluate(0, 531, 531, /*bInAuthorised=*/false);
        TestTrue(TEXT("With classes resident, the refusal says files would have been deleted"),
            Resident.Explanation.Contains(TEXT("source-control-deleted")));

        const auto Absent = Evaluate(0, 531, 0, /*bInAuthorised=*/false);
        TestFalse(TEXT("With NO classes resident, the refusal does NOT claim files would have been deleted"),
            Absent.Explanation.Contains(TEXT("source-control-deleted")));
    }

    // THE TOAST/LOG SPLIT. A Slate notification silently clips a long message MID-TOKEN --
    // observed live: an ~800-character refusal rendered as
    // "...set Ck.AutoTest.Populator.AllowUnrecogn AND run..." with the console variable
    // truncated. The log line was complete, so the loss is in the toast, not the format.
    //
    // Half a CVar name is worse than none: it looks copyable and is not. So the headline
    // must stay short, must NOT carry the recipe, and must say where the recipe is; the
    // explanation must carry it in full.
    {
        const auto Verdict = Evaluate(0, 533, 0, /*bInAuthorised=*/false);

        // 180 rather than a generous bound: the observed clip happened on ~800 chars in a
        // narrow column, and a limit that only rules out the disaster leaves room to drift
        // back toward it. The current headline is ~150.
        TestTrue(TEXT("The toast headline is short enough to render without clipping"),
            Verdict.Headline.Len() < 180);
        TestTrue(TEXT("The full explanation is the long one"),
            Verdict.Explanation.Len() > Verdict.Headline.Len());

        TestFalse(TEXT("The headline does NOT carry the CVar name (it would be clipped)"),
            Verdict.Headline.Contains(TEXT("AllowUnrecognizedWipe")));
        TestTrue(TEXT("The explanation DOES carry the full CVar name and value"),
            Verdict.Explanation.Contains(TEXT("Ck.AutoTest.Populator.AllowUnrecognizedWipe=1")));

        TestTrue(TEXT("The headline says nothing was changed"),
            Verdict.Headline.Contains(TEXT("Nothing was changed")));
        TestTrue(TEXT("The headline points at the channel that has the rest"),
            Verdict.Headline.Contains(TEXT("Output Log")));
    }

    // And it must not send the reader to a cause that cannot produce this state. A failed
    // AngelScript compile blocks engine init or exits, and a failed hot reload never
    // broadcasts PostCompile -- so the populator is not called at all. The first version of
    // this message told the reader to go check exactly that.
    {
        const auto Verdict = Evaluate(0, 531, 531, /*bInAuthorised=*/false);
        TestFalse(TEXT("The refusal does not blame AngelScript compilation"),
            Verdict.Explanation.Contains(TEXT("AngelScript compiled")));
        TestTrue(TEXT("The refusal names the cause that CAN produce this state"),
            Verdict.Explanation.Contains(TEXT("ClassScanRoot")));
    }

    return true;
}
