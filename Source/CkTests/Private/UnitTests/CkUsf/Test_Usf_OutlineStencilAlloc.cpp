// Headless unit test for the CkUsf outline stencil allocator (UCkUsf_OutlineSubsystem).
// Pure allocation/refcount logic — no rendering — so it runs under nullrhi too. Deliberately stays UNDER
// the stencil range capacity: allocating past capacity emits a ck::usf::Warning, which the AutoTest harness
// escalates to a test failure (that exhaustion path is exercised by review, not here).

#if WITH_EDITOR

#include "Misc/AutomationTest.h"

#include "Editor.h"
#include "Engine/World.h"

#include "CkUsf/Outline/CkUsf_OutlineSubsystem.h"
#include "CkUsf/Outline/CkUsf_OutlinePreset.h"

// --------------------------------------------------------------------------------------------------------------------

namespace
{
    constexpr auto kOutlineTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ProductFilter;

    auto Get_TestWorld() -> UWorld*
    {
        if (GEditor != nullptr)
        {
            if (auto* W = GEditor->GetEditorWorldContext().World())
            { return W; }
        }
        return GWorld;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Usf_OutlineStencilAlloc,
    "CkTests.UnitTests.CkUsf.OutlineStencilAlloc",
    kOutlineTestFlags)

bool FCkTest_Usf_OutlineStencilAlloc::RunTest(const FString& Parameters)
{
    auto* World = Get_TestWorld();
    if (TestNotNull(TEXT("editor world available"), World) == false)
    { return false; }

    auto* Subsystem = World->GetSubsystem<UCkUsf_OutlineSubsystem>();
    if (TestNotNull(TEXT("outline subsystem available"), Subsystem) == false)
    { return false; }

    const auto Min = Subsystem->Get_StencilMin();
    const auto Max = Subsystem->Get_StencilMax();
    TestTrue(TEXT("stencil range is non-empty"), Max >= Min);

    // ---- Distinct presets get distinct, in-range stencil values ----
    constexpr int32 Count = 5;
    TArray<UCkUsf_OutlinePreset*> Presets;
    TArray<uint8> Values;
    for (auto Index = 0; Index < Count; ++Index)
    {
        auto* Preset = NewObject<UCkUsf_OutlinePreset>(GetTransientPackage());
        Presets.Add(Preset);

        const auto Value = Subsystem->Get_OrAllocate_StencilFor(Preset);
        TestTrue(FString::Printf(TEXT("preset %d stencil in [%d,%d]"), Index, Min, Max), Value >= Min && Value <= Max);
        TestFalse(FString::Printf(TEXT("preset %d stencil is distinct"), Index), Values.Contains(Value));
        Values.Add(Value);
    }

    // ---- Re-allocating the same preset returns the same value (and increments its refcount) ----
    const auto Again = Subsystem->Get_OrAllocate_StencilFor(Presets[0]);
    TestEqual(TEXT("re-alloc of same preset returns same value"), Again, Values[0]);

    // ---- Refcount: release the extra ref (still active), then the original (freed) ----
    Subsystem->Release_StencilFor(Presets[0]); // 2 -> 1
    Subsystem->Release_StencilFor(Presets[0]); // 1 -> 0 (freed)

    // After a free, the preset can be allocated again to a valid value.
    const auto Reborn = Subsystem->Get_OrAllocate_StencilFor(Presets[0]);
    TestTrue(TEXT("re-alloc after free is in range"), Reborn >= Min && Reborn <= Max);

    // ---- Cleanup: release everything this test allocated so subsystem state is clean for other tests ----
    Subsystem->Release_StencilFor(Presets[0]);
    for (auto Index = 1; Index < Count; ++Index)
    { Subsystem->Release_StencilFor(Presets[Index]); }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif // WITH_EDITOR
