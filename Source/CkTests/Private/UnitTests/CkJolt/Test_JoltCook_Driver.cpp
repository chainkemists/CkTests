#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkCore/Time/CkTime.h"
#include "CkCore/Validation/CkIsValid.h"

#include "CkJoltEditor/Cook/CkJoltCook_Types.h"
#include "CkJoltEditor/Cook/CkJoltCook_WorldCooker.h"

#include <Editor.h>
#include <Engine/World.h>
#include <Math/NumericLimits.h>

// --------------------------------------------------------------------------------------------------------------------
// The incremental cook's stepper contract, which the editor subsystem's ticker depends on. A phase
// that failed to advance would spin the ticker forever AND hang the synchronous commandlet path,
// and a progress count that overran its total would drive the notification past 100%.
//
// DryRun on purpose: it reaches a terminal phase without writing a single asset, so the test cannot
// deposit cooked content into the workspace.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_jolt_cook_driver
{
    constexpr auto kTestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;

    // Far above any real phase count; only a non-advancing phase can reach it.
    constexpr auto kStepCeiling = 100000;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltCook_Driver,
    "Ck.Jolt.Cook.Driver",
    ck_test_jolt_cook_driver::kTestFlags)

bool FCkTest_JoltCook_Driver::RunTest(const FString& Parameters)
{
    using namespace ck::jolt::cook;
    using namespace ck_test_jolt_cook_driver;

    if (ck::Is_NOT_Valid(GEditor))
    { return true; }

    auto* World = GEditor->GetEditorWorldContext().World();

    if (ck::Is_NOT_Valid(World))
    { return true; }

    // ---- A zero budget must still advance ------------------------------------------------------------
    {
        auto Driver = FCk_Jolt_IncrementalCookDriver{*World, ECk_Jolt_CookMode::DryRun};

        constexpr auto ZeroBudget = FCk_Time{0.0};
        auto Result = ECk_Jolt_CookStepResult::InProgress;
        auto NumSteps = 0;

        while (Result == ECk_Jolt_CookStepResult::InProgress && NumSteps < kStepCeiling)
        {
            Result = Driver.Step(ZeroBudget);
            ++NumSteps;
        }

        TestTrue(TEXT("zero budget: reaches a terminal phase rather than spinning"),
            Result != ECk_Jolt_CookStepResult::InProgress);

        TestTrue(TEXT("zero budget: terminates well inside the ceiling"), NumSteps < kStepCeiling);

        TestTrue(TEXT("progress never overruns its total"),
            Driver.Get_CompletedUnits() <= Driver.Get_TotalUnits());

        TestTrue(TEXT("progress is never negative"), Driver.Get_CompletedUnits() >= 0);
    }

    // ---- An unbounded budget reaches the same terminal state ------------------------------------------
    {
        auto Driver = FCk_Jolt_IncrementalCookDriver{*World, ECk_Jolt_CookMode::DryRun};

        constexpr auto WholeBudget = FCk_Time{TNumericLimits<double>::Max()};
        auto Result = ECk_Jolt_CookStepResult::InProgress;
        auto NumSteps = 0;

        while (Result == ECk_Jolt_CookStepResult::InProgress && NumSteps < kStepCeiling)
        {
            Result = Driver.Step(WholeBudget);
            ++NumSteps;
        }

        TestTrue(TEXT("whole budget: reaches a terminal phase"),
            Result != ECk_Jolt_CookStepResult::InProgress);

        // Terminal phases are idempotent — the subsystem may tick once more before it tears the
        // driver down, and that must not resurrect the run.
        const auto Repeated = Driver.Step(WholeBudget);
        TestTrue(TEXT("stepping a finished driver keeps its terminal result"), Repeated == Result);
    }

    // ---- DryRun writes nothing, so the outcome is reportable either way -------------------------------
    {
        auto Driver = FCk_Jolt_IncrementalCookDriver{*World, ECk_Jolt_CookMode::DryRun};

        constexpr auto WholeBudget = FCk_Time{TNumericLimits<double>::Max()};
        auto Result = ECk_Jolt_CookStepResult::InProgress;
        auto NumSteps = 0;

        while (Result == ECk_Jolt_CookStepResult::InProgress && NumSteps < kStepCeiling)
        {
            Result = Driver.Step(WholeBudget);
            ++NumSteps;
        }

        const auto Stats = Driver.Get_Stats();

        // A cook that declined reports WHY; one that ran reports Incremental. Either is a valid
        // terminal state — what must never happen is a decline that claims it cooked.
        const auto DeclinedWithReason = Result == ECk_Jolt_CookStepResult::FullCookRequired
            && Stats._Outcome != ECk_Jolt_IncrementalOutcome::Incremental;

        const auto RanIncrementally = Result == ECk_Jolt_CookStepResult::Done
            && Stats._Outcome == ECk_Jolt_IncrementalOutcome::Incremental;

        TestTrue(TEXT("the reported outcome agrees with the terminal result"),
            DeclinedWithReason || RanIncrementally || Result == ECk_Jolt_CookStepResult::Failed);

        TestEqual(TEXT("a dry run never reports a written cell"), Stats._NumCellsWritten, 0);
    }

    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
