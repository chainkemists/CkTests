#include "CkTween/CkTween_Utils.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_TweenUtils_GetEasedProgress_MatchesTable,
    "Ck.Tween.Utils.GetEasedProgress.MatchesTable",
    kCkUnitTestFlags)

bool
    FCk_TweenUtils_GetEasedProgress_MatchesTable::
    RunTest(
        const FString& Parameters)
{
    constexpr auto Tolerance = 1.0e-4f;

    TestEqual(
        TEXT("Linear is the identity at the midpoint"),
        UCk_Utils_Tween_UE::Get_EasedProgress(ECk_TweenEasing::Linear, FCk_FloatRange_0to1{0.5}),
        0.5f,
        Tolerance);

    TestEqual(
        TEXT("InOutSine starts at 0"),
        UCk_Utils_Tween_UE::Get_EasedProgress(ECk_TweenEasing::InOutSine, FCk_FloatRange_0to1{0.0}),
        0.0f,
        Tolerance);

    TestEqual(
        TEXT("InOutSine ends at 1"),
        UCk_Utils_Tween_UE::Get_EasedProgress(ECk_TweenEasing::InOutSine, FCk_FloatRange_0to1{1.0}),
        1.0f,
        Tolerance);

    TestEqual(
        TEXT("InOutSine is symmetric about the midpoint"),
        UCk_Utils_Tween_UE::Get_EasedProgress(ECk_TweenEasing::InOutSine, FCk_FloatRange_0to1{0.5}),
        0.5f,
        Tolerance);

    // The range type clamps the input, so an overshooting progress reads as the end of the curve.
    TestEqual(
        TEXT("Progress above 1 is clamped to the curve's end"),
        UCk_Utils_Tween_UE::Get_EasedProgress(ECk_TweenEasing::InQuad, FCk_FloatRange_0to1{1.5}),
        UCk_Utils_Tween_UE::Get_EasedProgress(ECk_TweenEasing::InQuad, FCk_FloatRange_0to1{1.0}),
        Tolerance);

    // The OUTPUT is not clamped: an overshooting easing keeps its authored shape.
    TestTrue(
        TEXT("OutBack overshoots past 1 mid-curve"),
        UCk_Utils_Tween_UE::Get_EasedProgress(ECk_TweenEasing::OutBack, FCk_FloatRange_0to1{0.5}) > 1.0f);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
