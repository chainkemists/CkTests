// Unit tests for CkRecord enum formatters. Pins each value's formatted string
// to a non-empty, unique result so a refactor renaming an enum entry produces
// a visible test failure.

#include "Misc/AutomationTest.h"

#include "CkCore/Format/CkFormat.h"
#include "CkRecord/Record/CkRecord_Fragment_Data.h"

// --------------------------------------------------------------------------------------------------------------------

namespace
{
    constexpr auto kRecordFormatterTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::ProductFilter;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Record_EntryHandlingPolicy_FormatterRoundTrip,
    "CkTests.UnitTests.CkRecord.EntryHandlingPolicy.FormatterRoundTrip",
    kRecordFormatterTestFlags)

bool FCkTest_Record_EntryHandlingPolicy_FormatterRoundTrip::RunTest(const FString& Parameters)
{
    const auto DefaultStr = ck::Format_UE(TEXT("{}"), ECk_Record_EntryHandlingPolicy::Default);
    const auto DisallowStr = ck::Format_UE(TEXT("{}"), ECk_Record_EntryHandlingPolicy::DisallowDuplicateNames);

    TestFalse(TEXT("Default formats to non-empty"), DefaultStr.IsEmpty());
    TestFalse(TEXT("DisallowDuplicateNames formats to non-empty"), DisallowStr.IsEmpty());
    TestNotEqual(TEXT("Distinct enum values produce distinct formatted strings"), DefaultStr, DisallowStr);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Record_ForEachIterationResult_FormatterRoundTrip,
    "CkTests.UnitTests.CkRecord.ForEachIterationResult.FormatterRoundTrip",
    kRecordFormatterTestFlags)

bool FCkTest_Record_ForEachIterationResult_FormatterRoundTrip::RunTest(const FString& Parameters)
{
    const auto ContinueStr = ck::Format_UE(TEXT("{}"), ECk_Record_ForEachIterationResult::Continue);
    const auto BreakStr = ck::Format_UE(TEXT("{}"), ECk_Record_ForEachIterationResult::Break);

    TestFalse(TEXT("Continue formats to non-empty"), ContinueStr.IsEmpty());
    TestFalse(TEXT("Break formats to non-empty"), BreakStr.IsEmpty());
    TestNotEqual(TEXT("Continue and Break produce distinct formatted strings"), ContinueStr, BreakStr);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Record_LabelRequirementPolicy_FormatterRoundTrip,
    "CkTests.UnitTests.CkRecord.LabelRequirementPolicy.FormatterRoundTrip",
    kRecordFormatterTestFlags)

bool FCkTest_Record_LabelRequirementPolicy_FormatterRoundTrip::RunTest(const FString& Parameters)
{
    const auto RequiredStr = ck::Format_UE(TEXT("{}"), ECk_Record_LabelRequirementPolicy::Required);
    const auto OptionalStr = ck::Format_UE(TEXT("{}"), ECk_Record_LabelRequirementPolicy::Optional);

    TestFalse(TEXT("Required formats to non-empty"), RequiredStr.IsEmpty());
    TestFalse(TEXT("Optional formats to non-empty"), OptionalStr.IsEmpty());
    TestNotEqual(TEXT("Required and Optional produce distinct formatted strings"), RequiredStr, OptionalStr);

    return true;
}
