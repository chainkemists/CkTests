// Microbenchmark — handle copy/destroy throughput. Not a correctness check;
// recorded on commit so the migration's perf claim ("no atomics on the
// copy/destroy hot path") has a citable number. Pre-migration TSharedPtr
// copy+destroy was ~30-60 ns/iter (atomic-bound); post-migration trivial
// 12-byte memcpy + memcpy should be ~1-3 ns/iter.
//
// Anti-LICM design — the original "single Source, copy in a loop" pattern
// let the compiler prove the source was loop-invariant and hoist the read
// of Source.Get_Entity().Get_ID() out of the loop, producing a sub-1ns/iter
// number that wasn't measuring the copy at all. The fix: an array of N_DISTINCT
// genuinely-different handles, indexed per-iteration. The optimizer can't
// prove the array load is invariant, so the indexed read + 12-byte copy +
// destroy actually run each iteration.
//
// N_DISTINCT is chosen to comfortably exceed L1d while staying small enough
// that we can hold the whole array (each FCk_Handle is ~40-48 bytes including
// TWeakObjectPtr fields) without flooding L2.

#include "Misc/AutomationTest.h"
#include "HAL/PlatformTime.h"
#include "Containers/Array.h"
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

    // Build a pool of distinct handles so the per-iteration source actually
    // varies — defeats LICM on Get_Entity().Get_ID().
    constexpr int32 N_DISTINCT = 1024;                    // power of two — bitwise-AND wrap
    static_assert((N_DISTINCT & (N_DISTINCT - 1)) == 0, "N_DISTINCT must be a power of two");

    auto Handles = TArray<FCk_Handle>{};
    Handles.Reserve(N_DISTINCT);
    for (int32 i = 0; i < N_DISTINCT; ++i)
    {
        Handles.Emplace(FCk_Entity{OwnedReg->create()}, Slot);
    }

    constexpr int32 N = 10'000'000;

    // Accumulator forces the read after copy to be observable. Volatile sink
    // at the end of the loop body keeps the whole chain from being elided.
    // The XOR with `i` ensures the per-iteration read is genuinely a function
    // of the iteration index and can't be folded to a constant.
    int64 Sink = 0;

    const double Start = FPlatformTime::Seconds();
    for (int32 i = 0; i < N; ++i)
    {
        auto Copy = Handles[i & (N_DISTINCT - 1)];        // indexed load — not loop-invariant
        Sink ^= static_cast<int64>(Copy.Get_Entity().Get_ID()) ^ static_cast<int64>(i);
    }                                                      // dtor each iter (TWeakObjectPtr no-ops + POD memcpy)
    const double Elapsed = FPlatformTime::Seconds() - Start;
    volatile int64 GlobalSink = 0;
    GlobalSink = Sink;
    (void)GlobalSink;

    AddInfo(FString::Printf(TEXT("Handle copy+destroy: %d iterations in %.3fs (%.2f ns/iter, pool=%d distinct)"),
        N, Elapsed, (Elapsed / N) * 1.0e9, N_DISTINCT));

    Free(Slot);
    delete OwnedReg;
    return true;
}

#endif
