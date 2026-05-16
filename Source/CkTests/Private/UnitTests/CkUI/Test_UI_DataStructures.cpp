// Unit tests for CkUI's pure-data result structs and the ScreenFade params
// defaults. Both result structs are exported via CKUI_API; ScreenFade_Params
// is non-exported but its CK_DEFINE_CONSTRUCTORS-generated members are
// inline, so it's still usable from this module.

#include "Misc/AutomationTest.h"

#include "CkCore/Format/CkFormat.h"
#include "CkUI/CkScreen_Utils.h"
#include "CkUI/ScreenFade/CkScreenFade_Utils.h"

// --------------------------------------------------------------------------------------------------------------------

namespace
{
    constexpr auto kUIUnitTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::ProductFilter;
}

// --------------------------------------------------------------------------------------------------------------------
// FCk_LinePlaneIntersectionResult
// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_UI_LinePlaneIntersectionResult_DefaultIsInvalidPC,
    "CkTests.UnitTests.CkUI.LinePlaneIntersectionResult.DefaultIsInvalidPC",
    kUIUnitTestFlags)

bool FCkTest_UI_LinePlaneIntersectionResult_DefaultIsInvalidPC::RunTest(const FString& Parameters)
{
    const auto Result = FCk_LinePlaneIntersectionResult{};
    TestEqual(TEXT("Default-constructed LinePlaneIntersectionResult reports InvalidPlayerController status"),
        Result.Get_Status(), ECk_LinePlaneIntersectionStatus::InvalidPlayerController);
    TestEqual(TEXT("Default IntersectionPoint is ZeroVector"),
        Result.Get_IntersectionPoint(), FVector::ZeroVector);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_UI_LinePlaneIntersectionResult_CtorRoundtrip,
    "CkTests.UnitTests.CkUI.LinePlaneIntersectionResult.CtorRoundtrip",
    kUIUnitTestFlags)

bool FCkTest_UI_LinePlaneIntersectionResult_CtorRoundtrip::RunTest(const FString& Parameters)
{
    const auto Point = FVector{1.0f, 2.0f, 3.0f};
    const auto Result = FCk_LinePlaneIntersectionResult{ECk_LinePlaneIntersectionStatus::Success, Point};
    TestEqual(TEXT("Constructor preserves Status"),            Result.Get_Status(), ECk_LinePlaneIntersectionStatus::Success);
    TestEqual(TEXT("Constructor preserves IntersectionPoint"), Result.Get_IntersectionPoint(), Point);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
// FCk_ScreenFade_Params
// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_UI_ScreenFadeParams_DefaultFadeTime,
    "CkTests.UnitTests.CkUI.ScreenFadeParams.DefaultFadeTime",
    kUIUnitTestFlags)

bool FCkTest_UI_ScreenFadeParams_DefaultFadeTime::RunTest(const FString& Parameters)
{
    const auto Params = FCk_ScreenFade_Params{};
    TestEqual(TEXT("Default _FadeTime is 1.0f"), Params.Get_FadeTime(), 1.0f);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_UI_ScreenFadeParams_ColorRoundtrip,
    "CkTests.UnitTests.CkUI.ScreenFadeParams.ColorRoundtrip",
    kUIUnitTestFlags)

bool FCkTest_UI_ScreenFadeParams_ColorRoundtrip::RunTest(const FString& Parameters)
{
    auto Params = FCk_ScreenFade_Params{};
    const auto From = FLinearColor{0.1f, 0.2f, 0.3f, 1.0f};
    const auto To = FLinearColor{0.9f, 0.8f, 0.7f, 1.0f};
    Params.Set_FromColor(From);
    Params.Set_ToColor(To);

    TestEqual(TEXT("FromColor round-trips through setter/getter"), Params.Get_FromColor(), From);
    TestEqual(TEXT("ToColor round-trips through setter/getter"),   Params.Get_ToColor(),   To);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
// FCk_ScreenEdgeLocationResult
// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_UI_ScreenEdgeLocationResult_DefaultIsZero,
    "CkTests.UnitTests.CkUI.ScreenEdgeLocationResult.DefaultIsZero",
    kUIUnitTestFlags)

bool FCkTest_UI_ScreenEdgeLocationResult_DefaultIsZero::RunTest(const FString& Parameters)
{
    const auto Result = FCk_ScreenEdgeLocationResult{};
    TestEqual(TEXT("Default ScreenPosition is ZeroVector"),       Result.Get_ScreenPosition(),       FVector2D::ZeroVector);
    TestEqual(TEXT("Default RotationAngleDegrees is 0.0f"),       Result.Get_RotationAngleDegrees(), 0.0f);
    TestEqual(TEXT("Default IsOnScreen is false"),                Result.Get_IsOnScreen(),           false);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
// ECk_LinePlaneIntersectionStatus formatter
// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_UI_LinePlaneIntersectionStatus_Formatter,
    "CkTests.UnitTests.CkUI.LinePlaneIntersectionStatus.Formatter",
    kUIUnitTestFlags)

bool FCkTest_UI_LinePlaneIntersectionStatus_Formatter::RunTest(const FString& Parameters)
{
    // The enum has no CK_DEFINE_CUSTOM_FORMATTER_ENUM in CkScreen_Utils.h, but
    // UE's reflection still gives a printable display value via StaticEnum<>.
    // This test verifies each value yields a non-empty unique display name.
    const auto* EnumType = StaticEnum<ECk_LinePlaneIntersectionStatus>();
    TestNotNull(TEXT("StaticEnum<ECk_LinePlaneIntersectionStatus>() returns a valid UEnum"), EnumType);
    if (EnumType == nullptr) { return false; }

    const auto Success = EnumType->GetDisplayNameTextByValue(static_cast<int64>(ECk_LinePlaneIntersectionStatus::Success)).ToString();
    const auto Invalid = EnumType->GetDisplayNameTextByValue(static_cast<int64>(ECk_LinePlaneIntersectionStatus::InvalidPlayerController)).ToString();
    const auto NoIntersect = EnumType->GetDisplayNameTextByValue(static_cast<int64>(ECk_LinePlaneIntersectionStatus::NoIntersectionFound)).ToString();

    TestFalse(TEXT("Success display name is non-empty"),               Success.IsEmpty());
    TestFalse(TEXT("InvalidPlayerController display name is non-empty"), Invalid.IsEmpty());
    TestFalse(TEXT("NoIntersectionFound display name is non-empty"),    NoIntersect.IsEmpty());
    TestNotEqual(TEXT("Success vs Invalid display names distinct"),    Success,    Invalid);
    TestNotEqual(TEXT("Success vs NoIntersection display names distinct"), Success, NoIntersect);
    TestNotEqual(TEXT("Invalid vs NoIntersection display names distinct"), Invalid, NoIntersect);
    return true;
}
