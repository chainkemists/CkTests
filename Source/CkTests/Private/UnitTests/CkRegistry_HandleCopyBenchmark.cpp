// Microbenchmark — handle copy/destroy throughput. Not a correctness check;
// recorded on commit so the migration's perf claim ("no atomics on the
// copy/destroy hot path") has a citable number. Pre-migration TSharedPtr
// copy+destroy was ~30-60 ns/iter (atomic-bound); post-migration trivial
// 12-byte memcpy + memcpy should be ~1-3 ns/iter.

#include "Misc/AutomationTest.h"
#include "HAL/PlatformTime.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h"

#if WITH_DEV_AUTOMATION_TESTS

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkRegistry_HandleCopyDestroyBenchmark,
    "Ck.Registry.Benchmark.HandleCopyDestroy",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkRegistry_HandleCopyDestroyBenchmark::RunTest(const FString& Parameters)
{
    using namespace ck::registry_table;

    auto* OwnedReg = new EnttRegistryType{};
    auto Slot = Allocate(OwnedReg);
    const auto Source = FCk_Handle{FCk_Entity{OwnedReg->create()}, Slot};

    constexpr int32 N = 10'000'000;

    // Accumulator forces the optimizer to actually realize each copy.
    // We then write the result into a volatile sink at the end so the
    // entire chain has observable side effects and can't be elided.
    int32 Sink = 0;

    const double Start = FPlatformTime::Seconds();
    for (int32 i = 0; i < N; ++i)
    {
        auto Copy = Source;                    // copy ctor (12-byte memcpy post-migration)
        Sink += static_cast<int32>(Copy.Get_Entity().Get_ID()); // observable read forces the copy to materialize
    }                                          // dtor on every iteration (memcpy of bytes — no-op)
    const double Elapsed = FPlatformTime::Seconds() - Start;
    volatile int32 GlobalSink = 0;
    GlobalSink = Sink;
    (void)GlobalSink;

    AddInfo(FString::Printf(TEXT("Handle copy+destroy: %d iterations in %.3fs (%.1f ns/iter)"),
        N, Elapsed, (Elapsed / N) * 1.0e9));

    Free(Slot);
    delete OwnedReg;
    return true;
}

#endif
