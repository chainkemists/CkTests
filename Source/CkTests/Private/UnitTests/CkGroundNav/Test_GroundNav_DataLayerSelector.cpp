#include "CkGroundNav/Bake/CkGroundNav_DataLayerSelector.h"
#include "CkGroundNav/Bake/CkGroundNav_Fingerprint.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_DataLayerSelector_CanonicalExactAnyAndAtomicValidation,
    "CkTests.UnitTests.CkGroundNav.Bake.DataLayerSelector_CanonicalExactAnyAndAtomicValidation",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_DataLayerSelector_CanonicalExactAnyAndAtomicValidation::RunTest(const FString& Parameters)
{
    using namespace ck::groundnav;

    auto Selector = FCk_GroundNav_DataLayerSelector{};
    const auto MadeSelector = TryMake_DataLayerSelector(
        TArray<FName>{TEXT("CkTests.GroundNav.Layer.B"), TEXT("CkTests.GroundNav.Layer.A"),
            TEXT("CkTests.GroundNav.Layer.B")}, Selector);

    TestTrue(TEXT("valid names produce a selector"), MadeSelector);
    TestTrue(TEXT("selector storage is canonical"), Selector.Get_IsCanonical());
    TestEqual(TEXT("duplicate names collapse"), Selector.Get_LayerNames().Num(), 2);
    TestEqual(TEXT("names are FName-lexically ordered"), Selector.Get_LayerNames()[0],
        FName{TEXT("CkTests.GroundNav.Layer.A")});
    TestTrue(TEXT("any exact matching body layer is included"), Selector.Get_MatchesAny(
        TArray<FName>{TEXT("CkTests.GroundNav.Layer.Missing"), TEXT("CkTests.GroundNav.Layer.B")}));
    TestFalse(TEXT("nonmatching body layers are excluded"), Selector.Get_MatchesAny(
        TArray<FName>{TEXT("CkTests.GroundNav.Layer.Missing")}));
    TestFalse(TEXT("unlayered bodies are excluded by a non-empty selector"), Selector.Get_MatchesAny({}));

    const auto OriginalNames = Selector.Get_LayerNames();
    const auto RejectedInvalid = TryMake_DataLayerSelector(
        TArray<FName>{TEXT("CkTests.GroundNav.Layer.C"), NAME_None}, Selector);

    TestFalse(TEXT("empty layer names are rejected"), RejectedInvalid);
    TestEqual(TEXT("invalid validation leaves the prior selector intact"), Selector.Get_LayerNames(), OriginalNames);

    auto AllSelector = FCk_GroundNav_DataLayerSelector{};
    TestTrue(TEXT("an empty selection means all layers"), TryMake_DataLayerSelector({}, AllSelector));
    TestTrue(TEXT("the empty selector matches unlayered bodies"), AllSelector.Get_MatchesAny({}));

    auto PermutedSelector = FCk_GroundNav_DataLayerSelector{};
    TestTrue(TEXT("a permutation canonicalizes"), TryMake_DataLayerSelector(
        TArray<FName>{TEXT("CkTests.GroundNav.Layer.A"), TEXT("CkTests.GroundNav.Layer.B")},
        PermutedSelector));
    auto DifferentSelector = FCk_GroundNav_DataLayerSelector{};
    TestTrue(TEXT("a distinct selector canonicalizes"), TryMake_DataLayerSelector(
        TArray<FName>{TEXT("CkTests.GroundNav.Layer.C")}, DifferentSelector));

    const auto Region = FBox{FVector::ZeroVector, FVector{100.0, 100.0, 100.0}};
    const auto BaselineFingerprint = Get_InputFingerprint(Region, FCk_GroundNav_BakeConfig{},
        FCk_GroundNav_AgentProfile{}, {}, {}, {}, 0.0f, {}, Selector);
    const auto PermutedFingerprint = Get_InputFingerprint(Region, FCk_GroundNav_BakeConfig{},
        FCk_GroundNav_AgentProfile{}, {}, {}, {}, 0.0f, {}, PermutedSelector);
    const auto DifferentFingerprint = Get_InputFingerprint(Region, FCk_GroundNav_BakeConfig{},
        FCk_GroundNav_AgentProfile{}, {}, {}, {}, 0.0f, {}, DifferentSelector);
    TestEqual(TEXT("selector authoring order does not perturb the fingerprint"),
        BaselineFingerprint, PermutedFingerprint);
    TestNotEqual(TEXT("a selector change perturbs the fingerprint"),
        BaselineFingerprint, DifferentFingerprint);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
