// Unit tests for CkWatermark's ColorBands lookup — the densest pure-data
// surface in the module. Pins both directions (higher-is-better and
// lower-is-better), boundary inequality preference, and the StatQuality
// enum formatter. Uses default thresholds: HigherIsBetter VeryGood=60 /
// Good=45 / Okay=30 / Bad=20; LowerIsBetter VeryGood=30 / Good=60 /
// Okay=100 / Bad=150.

#include "Misc/AutomationTest.h"

#include "CkCore/Format/CkFormat.h"
#include "CkWatermark/CkWatermark_Types.h"

// --------------------------------------------------------------------------------------------------------------------

namespace
{
    constexpr auto kWatermarkUnitTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::ProductFilter;
}

// --------------------------------------------------------------------------------------------------------------------
// HigherIsBetter
// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Watermark_ColorBands_HigherIsBetter_AtVeryGood,
    "CkTests.UnitTests.CkWatermark.ColorBands_HigherIsBetter.AtVeryGoodThreshold_ReturnsVeryGoodColor",
    kWatermarkUnitTestFlags)

bool FCkTest_Watermark_ColorBands_HigherIsBetter_AtVeryGood::RunTest(const FString& Parameters)
{
    const auto Bands = FCk_Watermark_ColorBands_HigherIsBetter{};
    TestEqual(TEXT("60.0 (>= VeryGood_Threshold=60) maps to VeryGood_Color"),
        Bands.GetColorForValue(60.0f), Bands.VeryGood_Color);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Watermark_ColorBands_HigherIsBetter_BetweenGoodAndOkay,
    "CkTests.UnitTests.CkWatermark.ColorBands_HigherIsBetter.BetweenGoodAndOkay_ReturnsGoodColor",
    kWatermarkUnitTestFlags)

bool FCkTest_Watermark_ColorBands_HigherIsBetter_BetweenGoodAndOkay::RunTest(const FString& Parameters)
{
    const auto Bands = FCk_Watermark_ColorBands_HigherIsBetter{};
    // 50.0 is below VeryGood(60) but at-or-above Good(45) → Good band.
    TestEqual(TEXT("50.0 (between Good=45 and VeryGood=60) maps to Good_Color"),
        Bands.GetColorForValue(50.0f), Bands.Good_Color);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Watermark_ColorBands_HigherIsBetter_BelowBad,
    "CkTests.UnitTests.CkWatermark.ColorBands_HigherIsBetter.BelowBadThreshold_ReturnsVeryBadColor",
    kWatermarkUnitTestFlags)

bool FCkTest_Watermark_ColorBands_HigherIsBetter_BelowBad::RunTest(const FString& Parameters)
{
    const auto Bands = FCk_Watermark_ColorBands_HigherIsBetter{};
    // 10.0 is below Bad(20) → VeryBad band.
    TestEqual(TEXT("10.0 (below Bad=20) maps to VeryBad_Color"),
        Bands.GetColorForValue(10.0f), Bands.VeryBad_Color);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Watermark_ColorBands_HigherIsBetter_AtBoundaryPrefersHigherBand,
    "CkTests.UnitTests.CkWatermark.ColorBands_HigherIsBetter.AtBoundary_PrefersHigherBand",
    kWatermarkUnitTestFlags)

bool FCkTest_Watermark_ColorBands_HigherIsBetter_AtBoundaryPrefersHigherBand::RunTest(const FString& Parameters)
{
    const auto Bands = FCk_Watermark_ColorBands_HigherIsBetter{};
    // The lookup uses `>=` — at exactly Good_Threshold(45) the value picks Good
    // (the higher band), not Okay below it.
    TestEqual(TEXT("At Good_Threshold (45) the value picks Good_Color (the higher band)"),
        Bands.GetColorForValue(45.0f), Bands.Good_Color);
    TestEqual(TEXT("At Okay_Threshold (30) the value picks Okay_Color (the higher band)"),
        Bands.GetColorForValue(30.0f), Bands.Okay_Color);
    TestEqual(TEXT("At Bad_Threshold (20) the value picks Bad_Color (the higher band)"),
        Bands.GetColorForValue(20.0f), Bands.Bad_Color);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Watermark_ColorBands_HigherIsBetter_NegativeReturnsVeryBad,
    "CkTests.UnitTests.CkWatermark.ColorBands_HigherIsBetter.NegativeValue_ReturnsVeryBadColor",
    kWatermarkUnitTestFlags)

bool FCkTest_Watermark_ColorBands_HigherIsBetter_NegativeReturnsVeryBad::RunTest(const FString& Parameters)
{
    const auto Bands = FCk_Watermark_ColorBands_HigherIsBetter{};
    // Defensive: negative values are below every threshold → VeryBad.
    TestEqual(TEXT("Negative value falls through every threshold to VeryBad_Color"),
        Bands.GetColorForValue(-1.0f), Bands.VeryBad_Color);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
// LowerIsBetter
// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Watermark_ColorBands_LowerIsBetter_AtVeryGood,
    "CkTests.UnitTests.CkWatermark.ColorBands_LowerIsBetter.AtVeryGoodThreshold_ReturnsVeryGoodColor",
    kWatermarkUnitTestFlags)

bool FCkTest_Watermark_ColorBands_LowerIsBetter_AtVeryGood::RunTest(const FString& Parameters)
{
    const auto Bands = FCk_Watermark_ColorBands_LowerIsBetter{};
    // 30.0 (<= VeryGood_Threshold=30) → VeryGood_Color. low-is-good for ping.
    TestEqual(TEXT("30.0 (<= VeryGood_Threshold=30) maps to VeryGood_Color"),
        Bands.GetColorForValue(30.0f), Bands.VeryGood_Color);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Watermark_ColorBands_LowerIsBetter_AboveBad,
    "CkTests.UnitTests.CkWatermark.ColorBands_LowerIsBetter.AboveBadThreshold_ReturnsVeryBadColor",
    kWatermarkUnitTestFlags)

bool FCkTest_Watermark_ColorBands_LowerIsBetter_AboveBad::RunTest(const FString& Parameters)
{
    const auto Bands = FCk_Watermark_ColorBands_LowerIsBetter{};
    // 999.0 is above Bad(150) → VeryBad band.
    TestEqual(TEXT("999.0 (above Bad=150) maps to VeryBad_Color"),
        Bands.GetColorForValue(999.0f), Bands.VeryBad_Color);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Watermark_ColorBands_LowerIsBetter_AtBoundaryPrefersLowerBand,
    "CkTests.UnitTests.CkWatermark.ColorBands_LowerIsBetter.AtBoundary_PrefersLowerBand",
    kWatermarkUnitTestFlags)

bool FCkTest_Watermark_ColorBands_LowerIsBetter_AtBoundaryPrefersLowerBand::RunTest(const FString& Parameters)
{
    const auto Bands = FCk_Watermark_ColorBands_LowerIsBetter{};
    // The lookup uses `<=` — at exactly Good_Threshold(60) the value picks Good
    // (the lower-numbered band, semantically "better"), not Okay above it.
    TestEqual(TEXT("At Good_Threshold (60) the value picks Good_Color (the lower/better band)"),
        Bands.GetColorForValue(60.0f), Bands.Good_Color);
    TestEqual(TEXT("At Okay_Threshold (100) the value picks Okay_Color (the lower/better band)"),
        Bands.GetColorForValue(100.0f), Bands.Okay_Color);
    TestEqual(TEXT("At Bad_Threshold (150) the value picks Bad_Color (the lower/better band)"),
        Bands.GetColorForValue(150.0f), Bands.Bad_Color);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
// StatQuality enum formatter
// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Watermark_StatQuality_Formatter,
    "CkTests.UnitTests.CkWatermark.StatQuality.Formatter",
    kWatermarkUnitTestFlags)

bool FCkTest_Watermark_StatQuality_Formatter::RunTest(const FString& Parameters)
{
    const auto VeryGood = ck::Format_UE(TEXT("{}"), ECk_Watermark_StatQuality::VeryGood);
    const auto Good     = ck::Format_UE(TEXT("{}"), ECk_Watermark_StatQuality::Good);
    const auto Okay     = ck::Format_UE(TEXT("{}"), ECk_Watermark_StatQuality::Okay);
    const auto Bad      = ck::Format_UE(TEXT("{}"), ECk_Watermark_StatQuality::Bad);
    const auto VeryBad  = ck::Format_UE(TEXT("{}"), ECk_Watermark_StatQuality::VeryBad);

    TestFalse(TEXT("VeryGood formats to non-empty"), VeryGood.IsEmpty());
    TestFalse(TEXT("Good formats to non-empty"),     Good.IsEmpty());
    TestFalse(TEXT("Okay formats to non-empty"),     Okay.IsEmpty());
    TestFalse(TEXT("Bad formats to non-empty"),      Bad.IsEmpty());
    TestFalse(TEXT("VeryBad formats to non-empty"),  VeryBad.IsEmpty());

    TestNotEqual(TEXT("VeryGood vs Good distinct"),  VeryGood, Good);
    TestNotEqual(TEXT("Good vs Okay distinct"),      Good,     Okay);
    TestNotEqual(TEXT("Okay vs Bad distinct"),       Okay,     Bad);
    TestNotEqual(TEXT("Bad vs VeryBad distinct"),    Bad,      VeryBad);

    return true;
}
