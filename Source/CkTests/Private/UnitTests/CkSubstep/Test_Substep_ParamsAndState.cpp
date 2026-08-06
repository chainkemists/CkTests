// Unit tests for CkSubstep's pure-data surface: ParamsData defaults +
// constructor round-trip, plus the ECk_Substep_State formatter.

#include "Misc/AutomationTest.h"

#include "CkCore/Format/CkFormat.h"
#include "CkSubstep/CkSubstep_Fragment_Data.h"

// --------------------------------------------------------------------------------------------------------------------

namespace
{
    constexpr auto kSubstepUnitTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::ProductFilter;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Substep_ParamsData_Defaults,
    "CkTests.UnitTests.CkSubstep.ParamsData.Defaults",
    kSubstepUnitTestFlags)

bool FCkTest_Substep_ParamsData_Defaults::RunTest(const FString& Parameters)
{
    const auto Params = FCk_Substep_Spec{};
    TestEqual(TEXT("Default _TickRate is 0.01s"),
        Params.Get_TickRate().Get_Seconds(), 0.01);
    TestEqual(TEXT("Default _StartingState is Paused"),
        Params.Get_StartingState(), ECk_Substep_State::Paused);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Substep_ParamsData_CtorRoundtrip,
    "CkTests.UnitTests.CkSubstep.ParamsData.CtorRoundtrip",
    kSubstepUnitTestFlags)

bool FCkTest_Substep_ParamsData_CtorRoundtrip::RunTest(const FString& Parameters)
{
    auto Params = FCk_Substep_Spec{FCk_Time{0.05}};
    Params.Set_StartingState(ECk_Substep_State::Running);
    TestEqual(TEXT("Constructor preserves _TickRate"),
        Params.Get_TickRate().Get_Seconds(), 0.05);
    TestEqual(TEXT("Set_StartingState updates field"),
        Params.Get_StartingState(), ECk_Substep_State::Running);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Substep_State_Formatter,
    "CkTests.UnitTests.CkSubstep.State.Formatter",
    kSubstepUnitTestFlags)

bool FCkTest_Substep_State_Formatter::RunTest(const FString& Parameters)
{
    const auto Paused  = ck::Format_UE(TEXT("{}"), ECk_Substep_State::Paused);
    const auto Running = ck::Format_UE(TEXT("{}"), ECk_Substep_State::Running);
    TestFalse(TEXT("Paused non-empty"),  Paused.IsEmpty());
    TestFalse(TEXT("Running non-empty"), Running.IsEmpty());
    TestNotEqual(TEXT("Paused vs Running distinct"), Paused, Running);
    return true;
}
