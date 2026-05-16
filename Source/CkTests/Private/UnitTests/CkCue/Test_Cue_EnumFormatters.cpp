// Unit tests for CkCue's three policy/lifetime enums. Pins each value's
// formatted display string as non-empty and unique among siblings — guards
// against accidental enum-renames during the refactor.

#include "Misc/AutomationTest.h"

#include "CkCore/Format/CkFormat.h"
#include "CkCue/CkCue_EntityScript.h"

// --------------------------------------------------------------------------------------------------------------------

namespace
{
    constexpr auto kCueUnitTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::ProductFilter;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Cue_LifetimeBehavior_Formatter,
    "CkTests.UnitTests.CkCue.LifetimeBehavior.Formatter",
    kCueUnitTestFlags)

bool FCkTest_Cue_LifetimeBehavior_Formatter::RunTest(const FString& Parameters)
{
    const ECk_Cue_LifetimeBehavior Values[] = {
        ECk_Cue_LifetimeBehavior::AfterOneFrame,
        ECk_Cue_LifetimeBehavior::Persistent,
        ECk_Cue_LifetimeBehavior::Timed,
        ECk_Cue_LifetimeBehavior::Custom,
    };
    TSet<FString> Seen;
    for (const auto V : Values)
    {
        const auto Str = ck::Format_UE(TEXT("{}"), V);
        TestFalse(*FString::Printf(TEXT("LifetimeBehavior %d formats non-empty"), static_cast<int32>(V)), Str.IsEmpty());
        TestFalse(*FString::Printf(TEXT("LifetimeBehavior %d unique"), static_cast<int32>(V)), Seen.Contains(Str));
        Seen.Add(Str);
    }
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Cue_ConcurrencyPolicy_Formatter,
    "CkTests.UnitTests.CkCue.ConcurrencyPolicy.Formatter",
    kCueUnitTestFlags)

bool FCkTest_Cue_ConcurrencyPolicy_Formatter::RunTest(const FString& Parameters)
{
    const auto Allow   = ck::Format_UE(TEXT("{}"), ECk_Cue_ConcurrencyPolicy::AllowMultiple);
    const auto Restart = ck::Format_UE(TEXT("{}"), ECk_Cue_ConcurrencyPolicy::RestartExisting);
    TestFalse(TEXT("AllowMultiple non-empty"),   Allow.IsEmpty());
    TestFalse(TEXT("RestartExisting non-empty"), Restart.IsEmpty());
    TestNotEqual(TEXT("AllowMultiple vs RestartExisting distinct"), Allow, Restart);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Cue_OwnerValidationPolicy_Formatter,
    "CkTests.UnitTests.CkCue.OwnerValidationPolicy.Formatter",
    kCueUnitTestFlags)

bool FCkTest_Cue_OwnerValidationPolicy_Formatter::RunTest(const FString& Parameters)
{
    const auto Skip = ck::Format_UE(TEXT("{}"), ECk_Cue_OwnerValidationPolicy::SkipIfInvalid);
    const auto Req  = ck::Format_UE(TEXT("{}"), ECk_Cue_OwnerValidationPolicy::RequireValid);
    TestFalse(TEXT("SkipIfInvalid non-empty"), Skip.IsEmpty());
    TestFalse(TEXT("RequireValid non-empty"),  Req.IsEmpty());
    TestNotEqual(TEXT("SkipIfInvalid vs RequireValid distinct"), Skip, Req);
    return true;
}
