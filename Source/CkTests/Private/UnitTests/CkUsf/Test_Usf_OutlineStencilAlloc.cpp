// Headless unit test for the CkUsf outline stencil allocator (UCkUsf_OutlineSubsystem).
// Pure allocation/refcount logic — no rendering — so it runs under nullrhi too. Deliberately stays UNDER
// the stencil range capacity: allocating past capacity emits a ck::usf::Warning, which the AutoTest harness
// escalates to a test failure (that exhaustion path is exercised by review, not here).

#if WITH_EDITOR

#include "Misc/AutomationTest.h"

#include "Editor.h"
#include "Engine/World.h"
#include "UObject/StrongObjectPtr.h"

#include <limits>

#include "CkUsf/Outline/CkUsf_OutlineSubsystem.h"
#include "CkUsf/Outline/CkUsf_OutlinePreset.h"

// --------------------------------------------------------------------------------------------------------------------

namespace
{
    constexpr auto kOutlineTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ProductFilter;

    auto Get_OutlineTestWorld() -> UWorld*
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
    auto* World = Get_OutlineTestWorld();
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

    AddExpectedErrorPlain(TEXT("thickness scale"), EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);
    AddExpectedErrorPlain(TEXT("overflows authored width"), EAutomationExpectedErrorFlags::Contains,
        /*Occurrences=*/-1);
    for (const auto InvalidScale : {-1.0f, std::numeric_limits<float>::quiet_NaN(),
                                    std::numeric_limits<float>::infinity()})
    {
        Presets[0]->_ThicknessScale = InvalidScale;
        TestEqual(TEXT("invalid scale cannot increment an existing slot's refcount"),
            Subsystem->Get_OrAllocate_StencilFor(Presets[0]), static_cast<uint8>(0));
    }
    Presets[0]->_ThicknessScale = std::numeric_limits<float>::max();
    TestEqual(TEXT("overflow scale cannot increment an existing slot's refcount"),
        Subsystem->Get_OrAllocate_StencilFor(Presets[0]), static_cast<uint8>(0));
    Presets[0]->_ThicknessScale = 1.0f;
    Subsystem->Release_StencilFor(Presets[0]);

    auto InvalidPreset = TStrongObjectPtr<UCkUsf_OutlinePreset>{NewObject<UCkUsf_OutlinePreset>(GetTransientPackage())};
    for (const auto InvalidScale : {-1.0f, std::numeric_limits<float>::quiet_NaN(),
                                    std::numeric_limits<float>::infinity()})
    {
        InvalidPreset->_ThicknessScale = InvalidScale;
        TestEqual(TEXT("invalid scale cannot allocate a fresh slot"),
            Subsystem->Get_OrAllocate_StencilFor(InvalidPreset.Get()), static_cast<uint8>(0));
    }
    InvalidPreset->_ThicknessScale = std::numeric_limits<float>::max();
    TestEqual(TEXT("finite scale whose product overflows cannot allocate a fresh slot"),
        Subsystem->Get_OrAllocate_StencilFor(InvalidPreset.Get()), static_cast<uint8>(0));
    InvalidPreset->_ThicknessScale = 1.0f;
    const auto ReclaimedValue = Subsystem->Get_OrAllocate_StencilFor(InvalidPreset.Get());
    TestEqual(TEXT("rejected allocations preserved the released slot and refcount"), ReclaimedValue, Values[0]);
    Subsystem->Release_StencilFor(InvalidPreset.Get());

    // ---- Re-allocating the same preset returns the same value (and increments its refcount) ----
    const auto First = Subsystem->Get_OrAllocate_StencilFor(Presets[0]);
    TestEqual(TEXT("released preset reclaims its original slot"), First, Values[0]);
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
