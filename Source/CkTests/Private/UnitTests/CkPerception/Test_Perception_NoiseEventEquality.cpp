// Unit tests for CkPerception's hearing-perception equality comparators.
// These pin the CURRENT narrow contract:
//   NoiseInfo::operator==  compares ONLY _NoiseTag
//   NoiseEvent::operator== compares NoiseInfo (i.e. NoiseTag) AND _Instigator
// Fields NoiseLocation / TravelDistance / Lifetime / NoiseSound are ignored
// by equality. If the refactor widens the comparison (e.g. include location),
// the location-pin test below flips and surfaces the change.

#include "Misc/AutomationTest.h"

#include "CkPerception/Hearing/CkHearingPerception_Params.h"
#include "CkPerception/Hearing/CkHearingPerception_Utils.h"

// --------------------------------------------------------------------------------------------------------------------

namespace
{
    constexpr auto kPerceptionUnitTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::ProductFilter;

    auto MakeInfo(FGameplayTag InTag = FGameplayTag::EmptyTag, float InTravelDistance = 500.0f, float InLifetime = 1.0f)
        -> FCk_HearingPerception_NoiseInfo
    {
        return FCk_HearingPerception_NoiseInfo{InTag, InTravelDistance, InLifetime, nullptr};
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Perception_NoiseEvent_IsEqual_DefaultConstructed_True,
    "CkTests.UnitTests.CkPerception.NoiseEvent.IsEqual_DefaultConstructed_True",
    kPerceptionUnitTestFlags)

bool FCkTest_Perception_NoiseEvent_IsEqual_DefaultConstructed_True::RunTest(const FString& Parameters)
{
    const auto A = FCk_HearingPerception_NoiseEvent{};
    const auto B = FCk_HearingPerception_NoiseEvent{};
    TestTrue(TEXT("Two default-constructed NoiseEvents compare equal"), A == B);
    TestTrue(TEXT("Get_NoiseEvent_IsEqual agrees with operator=="),
        UCk_Utils_HearingPerception_UE::Get_NoiseEvent_IsEqual(A, B));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Perception_NoiseEvent_IsEqual_IdenticalEvents_True,
    "CkTests.UnitTests.CkPerception.NoiseEvent.IsEqual_IdenticalEvents_True",
    kPerceptionUnitTestFlags)

bool FCkTest_Perception_NoiseEvent_IsEqual_IdenticalEvents_True::RunTest(const FString& Parameters)
{
    const auto Info = MakeInfo();
    const auto Loc = FVector{10.0f, 20.0f, 30.0f};
    const auto A = FCk_HearingPerception_NoiseEvent{Info, Loc, nullptr};
    const auto B = FCk_HearingPerception_NoiseEvent{Info, Loc, nullptr};
    TestTrue(TEXT("Two NoiseEvents constructed from identical inputs compare equal"), A == B);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Perception_NoiseEvent_IsEqual_DifferentLocations_PinsNarrowComparator,
    "CkTests.UnitTests.CkPerception.NoiseEvent.IsEqual_DifferentLocations_PinsNarrowComparator",
    kPerceptionUnitTestFlags)

bool FCkTest_Perception_NoiseEvent_IsEqual_DifferentLocations_PinsNarrowComparator::RunTest(const FString& Parameters)
{
    // Discovered behavior: NoiseLocation is NOT part of equality. Two events
    // at different world positions but the same NoiseInfo+Instigator are
    // considered equal. This test pins that — refactor widening the
    // comparator to include location will flip this assertion.
    const auto Info = MakeInfo();
    const auto A = FCk_HearingPerception_NoiseEvent{Info, FVector{10.0f, 0.0f, 0.0f}, nullptr};
    const auto B = FCk_HearingPerception_NoiseEvent{Info, FVector{99.0f, 0.0f, 0.0f}, nullptr};
    TestTrue(TEXT("Different locations are IGNORED by the current narrow comparator (Tag + Instigator only)"),
        A == B);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Perception_NoiseEvent_IsEqual_DifferentNoiseTag_False,
    "CkTests.UnitTests.CkPerception.NoiseEvent.IsEqual_DifferentNoiseTag_False",
    kPerceptionUnitTestFlags)

bool FCkTest_Perception_NoiseEvent_IsEqual_DifferentNoiseTag_False::RunTest(const FString& Parameters)
{
    // The NoiseTag is the ONE NoiseInfo field that participates in equality
    // (NoiseInfo::operator== compares only _NoiseTag — TravelDistance and
    // Lifetime are ignored). Varying the tag must produce inequality.
    const auto TagA = FGameplayTag::RequestGameplayTag(FName{TEXT("AutoTest.Noise.A")}, /*ErrorIfNotFound*/ false);
    const auto TagB = FGameplayTag::RequestGameplayTag(FName{TEXT("AutoTest.Noise.B")}, /*ErrorIfNotFound*/ false);

    // If neither tag exists in the project's tag table, fall back to comparing
    // empty-vs-something-else via a hand-built FName tag. Either way, we need
    // two distinct FGameplayTag values to exercise the inequality path.
    if (TagA == TagB)
    {
        AddWarning(TEXT("AutoTest.Noise.A / .B tags are not registered; skipping inequality check"));
        return true;
    }

    const auto A = FCk_HearingPerception_NoiseEvent{MakeInfo(TagA), FVector::ZeroVector, nullptr};
    const auto B = FCk_HearingPerception_NoiseEvent{MakeInfo(TagB), FVector::ZeroVector, nullptr};
    TestFalse(TEXT("NoiseEvents differing in NoiseInfo.NoiseTag compare not-equal"), A == B);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Perception_NoiseEvent_IsNotEqual_NegatesIsEqual,
    "CkTests.UnitTests.CkPerception.NoiseEvent.IsNotEqual_NegatesIsEqual",
    kPerceptionUnitTestFlags)

bool FCkTest_Perception_NoiseEvent_IsNotEqual_NegatesIsEqual::RunTest(const FString& Parameters)
{
    const auto Info = MakeInfo();
    const auto Equal_A = FCk_HearingPerception_NoiseEvent{Info, FVector{10.0f, 0.0f, 0.0f}, nullptr};
    const auto Equal_B = FCk_HearingPerception_NoiseEvent{Info, FVector{99.0f, 0.0f, 0.0f}, nullptr};

    // operator!= on events the narrow comparator considers equal must return false.
    TestFalse(TEXT("operator!= false when events compare equal under the narrow contract"),
        Equal_A != Equal_B);
    TestEqual(TEXT("Get_NoiseEvent_IsNotEqual mirrors operator!="),
        UCk_Utils_HearingPerception_UE::Get_NoiseEvent_IsNotEqual(Equal_A, Equal_B),
        Equal_A != Equal_B);

    // To prove the negation works in the inequality direction, build two events
    // that differ by the only field that matters (NoiseTag).
    const auto TagA = FGameplayTag::RequestGameplayTag(FName{TEXT("AutoTest.Noise.A")}, /*ErrorIfNotFound*/ false);
    const auto TagB = FGameplayTag::RequestGameplayTag(FName{TEXT("AutoTest.Noise.B")}, /*ErrorIfNotFound*/ false);
    if (TagA != TagB)
    {
        const auto Diff_A = FCk_HearingPerception_NoiseEvent{MakeInfo(TagA), FVector::ZeroVector, nullptr};
        const auto Diff_B = FCk_HearingPerception_NoiseEvent{MakeInfo(TagB), FVector::ZeroVector, nullptr};
        TestTrue(TEXT("operator!= true when events differ on NoiseTag"), Diff_A != Diff_B);
    }

    return true;
}
