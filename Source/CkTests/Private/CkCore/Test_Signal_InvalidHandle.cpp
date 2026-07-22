#include "CkEcs/Signal/CkSignal_Utils.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h"

#include "../CkSnapshot/Test_Snapshot_DynamicFragment_Fixtures.h"

#include "Misc/AutomationTest.h"
#include <StructUtils/InstancedStruct.h>

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_test_signal_invalid_handle
{
    struct FSignal : ck::TFragment_Signal<int32>
    {
    };

    class FSignalUtils : public ck::TUtils_Signal<FSignal>
    {
    };

    struct FRetainedSignal : ck::TFragment_Signal<FInstancedStruct>
    {
    };

    class FRetainedSignalUtils : public ck::TUtils_Signal<FRetainedSignal>
    {
    };

    struct FListener
    {
        auto OnSignal(int32) -> void
        { ++InvocationCount; }

        int32 InvocationCount = 0;
    };

    struct FRetainedListener
    {
        auto OnSignal(FInstancedStruct) -> void
        { ++InvocationCount; }

        int32 InvocationCount = 0;
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Signal_InvalidHandleFailsClosed,
    "Ck.CkCore.Signal.InvalidHandleFailsClosed",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkTest_Signal_InvalidHandleFailsClosed::RunTest(const FString&)
{
    using namespace ck_test_signal_invalid_handle;

    // Whitelist every matching line: one CK ensure can surface through multiple log paths.
    AddExpectedError(TEXT("rejected invalid/tombstone handle"), EAutomationExpectedErrorFlags::Contains, -1);

    auto DefaultListener = FListener{};
    const auto DefaultHandle = FCk_Handle{};
    const auto DefaultConnection = FSignalUtils::Bind<&FListener::OnSignal,
        ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
        ECk_Signal_PostFireBehavior::DoNothing>(DefaultListener, DefaultHandle);

    FSignalUtils::Broadcast(DefaultHandle, ck::MakePayload(42));

    TestFalse(TEXT("default-handle bind returns no live connection"), static_cast<bool>(DefaultConnection));
    TestEqual(TEXT("default-handle bind cannot fire through a later invalid broadcast"), DefaultListener.InvocationCount, 0);
    TestFalse(TEXT("default handle never acquires signal state"), FSignalUtils::Has(DefaultHandle));

    auto BackingRegistry = ck::registry_table::EnttRegistryType{};
    const auto RegistryHandle = ck::registry_table::Allocate(&BackingRegistry);
    const auto Entity = BackingRegistry.create();
    const auto TombstoneHandle = FCk_Handle{FCk_Entity{Entity}, RegistryHandle};
    BackingRegistry.destroy(Entity);

    auto TombstoneListener = FListener{};
    const auto TombstoneConnection = FSignalUtils::Bind<&FListener::OnSignal,
        ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
        ECk_Signal_PostFireBehavior::DoNothing>(TombstoneListener, TombstoneHandle);

    FSignalUtils::Broadcast(TombstoneHandle, ck::MakePayload(84));

    TestFalse(TEXT("tombstone-handle bind returns no live connection"), static_cast<bool>(TombstoneConnection));
    TestEqual(TEXT("tombstone-handle bind cannot fire through a later invalid broadcast"), TombstoneListener.InvocationCount, 0);
    TestFalse(TEXT("tombstone handle never acquires signal state"), FSignalUtils::Has(TombstoneHandle));

    ck::registry_table::Free(RegistryHandle);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Signal_UnsafeRetainedPayloadFailsClosed,
    "Ck.CkCore.Signal.UnsafeRetainedPayloadFailsClosed",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkTest_Signal_UnsafeRetainedPayloadFailsClosed::RunTest(const FString&)
{
    using namespace ck_test_signal_invalid_handle;

    auto BackingRegistry = ck::registry_table::EnttRegistryType{};
    const auto RegistryHandle = ck::registry_table::Allocate(&BackingRegistry);
    const auto Entity = BackingRegistry.create();
    const auto SignalHandle = FCk_Handle{FCk_Entity{Entity}, RegistryHandle};

    auto MissingSignalListener = FListener{};
    // Occurrences=0 suppresses every matching line while still requiring at least one match.
    AddExpectedError(TEXT("Unbind rejected a handle without signal state"),
        EAutomationExpectedErrorFlags::Contains, 0);
    FSignalUtils::Unbind<&FListener::OnSignal>(MissingSignalListener, SignalHandle);
    TestFalse(TEXT("missing-signal Unbind does not create or mutate fallback signal state"),
        FSignalUtils::Has(SignalHandle));

    auto Listener = FRetainedListener{};
    const auto Connection = FRetainedSignalUtils::Bind<&FRetainedListener::OnSignal,
        ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
        ECk_Signal_PostFireBehavior::DoNothing>(Listener, SignalHandle);

    AddExpectedError(TEXT("rejected unsafe InstancedStruct payload"), EAutomationExpectedErrorFlags::Contains, -1);
    FRetainedSignalUtils::Broadcast(
        SignalHandle,
        ck::MakePayload(FInstancedStruct::Make(FCk_Test_HydrationPayloadWithObject{})));

    TestTrue(TEXT("valid-handle bind returns a live connection"), static_cast<bool>(Connection));
    TestEqual(TEXT("unsafe retained payload invokes no callbacks"), Listener.InvocationCount, 0);
    TestFalse(TEXT("unsafe retained payload is not stored as in flight"),
        FRetainedSignalUtils::HasFiredAtLeastOnce(SignalHandle));

    FRetainedSignalUtils::Broadcast(
        SignalHandle,
        ck::MakePayload(FInstancedStruct::Make(FCk_Test_DynFrag_PureData{})));

    TestEqual(TEXT("safe retained payload still invokes callbacks"), Listener.InvocationCount, 1);
    TestTrue(TEXT("safe retained payload is stored as in flight"),
        FRetainedSignalUtils::HasFiredAtLeastOnce(SignalHandle));

    BackingRegistry.destroy(Entity);
    ck::registry_table::Free(RegistryHandle);

    return true;
}

#endif
