#pragma once

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

// Shared base for tests that force a collect to observe what a fragment-held asset reference does
// afterwards.
//
// Proving "was this collected?" inside a single RunTest call requires a full-purge GC, but that also
// collects whatever stale PIE world the shared automation process is still holding, and tearing down
// that world's tickable subsystems fires engine ensures. The framework attributes any logged error to
// whichever test triggered the collect, so without this a GC test flakes against unrelated map
// teardown — passing alone, failing in combination.
//
// Suppression is limited to CAPTURED LOG output: SuppressLogErrors is consulted only by the
// automation output device, never by AddError, so TestTrue/TestNull failures still fail the test.
class FCkTest_GcWeakRefBase : public FAutomationTestBase
{
public:
    FCkTest_GcWeakRefBase(
        const FString& InName,
        const bool     InIsComplexTask)
        : FAutomationTestBase(InName, InIsComplexTask)
    {
    }

    virtual bool SuppressLogErrors() override { return true; }
};

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_gc_weak_ref
{
    constexpr auto kTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::EngineFilter;
}

#endif // WITH_DEV_AUTOMATION_TESTS
