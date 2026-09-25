#include "CoreMinimal.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkProceduralAnimation/Debug/CkProceduralAnimation_Debug.h"
#include "CkProceduralAnimationDebugger/Data/CkProceduralAnimationDebugger_History.h"

#include "Misc/AutomationTest.h"

#include <limits>

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_procedural_animation_debugger_history
{
    // The debugger is editor tooling; its history is exercised in the editor context.
    constexpr auto TestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;
    constexpr auto NaN = std::numeric_limits<double>::quiet_NaN();
    constexpr auto Infinity = std::numeric_limits<double>::infinity();
    constexpr auto MinCapacity = 1;
    constexpr auto MaxCapacity = 4096;

    auto
        MakeSample(
            uint64 InSequence)
        -> FCk_ProceduralAnimation_DebugSnapshot
    {
        auto Sample = FCk_ProceduralAnimation_DebugSnapshot{};
        Sample.Set_Available(true).Set_HasAcceptedSample(true).Set_GaitReady(true)
            .Set_Sequence(InSequence).Set_FrameNumber(InSequence)
            .Set_Time(FCk_Time{static_cast<double>(InSequence) * 0.1})
            .Set_EntityId(TEXT("HistoryFixture"))
            .Set_BodyTransform(FTransform{FVector{static_cast<double>(InSequence), 0.0, 0.0}});
        return Sample;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralAnimationDebugger_HistoryBoundedOrderedCopies,
    "Ck.ProceduralAnimation.Debugger.History.BoundedOrderedCopies",
    ck_test_procedural_animation_debugger_history::TestFlags)

auto
    FCkProceduralAnimationDebugger_HistoryBoundedOrderedCopies::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_animation_debugger_history;
    auto History = FCkProceduralAnimationDebugger_History{3};
    for (auto Sequence = uint64{1}; Sequence <= 4; ++Sequence)
    {
        auto Sample = MakeSample(Sequence);
        TestTrue(TEXT("An accepted advancing sample is recorded"), History.Push(Sample));
        Sample.Set_Sequence(999).Set_BodyTransform(FTransform{FVector{999.0, 0.0, 0.0}});
    }
    TestEqual(TEXT("History retains the configured bounded count"), History.Get_Count(), 3);
    TestEqual(TEXT("History reports its effective capacity"), History.Get_Capacity(), 3);
    for (auto Index = 0; Index < 3; ++Index)
    {
        const auto* Sample = History.Get_Sample(Index);
        if (NOT TestNotNull(TEXT("Chronological sample is available"), Sample))
        {
            continue;
        }
        TestEqual(TEXT("Oldest is evicted while retained samples remain ordered"),
            Sample->Get_Sequence(), static_cast<uint64>(Index + 2));
        TestEqual(TEXT("Caller mutation does not alter captured pose"),
            Sample->Get_BodyTransform().GetLocation().X, static_cast<double>(Index + 2));
    }
    TestNull(TEXT("Negative sample index is rejected"), History.Get_Sample(-1));
    TestNull(TEXT("Past-end sample index is rejected"), History.Get_Sample(3));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralAnimationDebugger_HistoryHoldScrubLiveReset,
    "Ck.ProceduralAnimation.Debugger.History.HoldScrubLiveReset",
    ck_test_procedural_animation_debugger_history::TestFlags)

auto
    FCkProceduralAnimationDebugger_HistoryHoldScrubLiveReset::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_animation_debugger_history;
    auto History = FCkProceduralAnimationDebugger_History{3};
    History.Push(MakeSample(1));
    History.Hold();
    for (auto Sequence = uint64{2}; Sequence <= 5; ++Sequence)
    {
        History.Push(MakeSample(Sequence));
    }
    TestFalse(TEXT("Hold leaves capture running but presentation frozen"), History.Get_IsLive());
    if (TestNotNull(TEXT("Held value survives eviction"), History.Get_Displayed()))
    {
        TestEqual(TEXT("Held value is independently pinned"), History.Get_Displayed()->Get_Sequence(), uint64{1});
    }
    TestEqual(TEXT("Capture advanced while presentation was held"), History.Get_Count(), 3);
    TestTrue(TEXT("Scrub accepts an existing chronological sample"), History.Scrub(0));
    if (TestNotNull(TEXT("Scrubbed sample is displayed"), History.Get_Displayed()))
    {
        TestEqual(TEXT("Scrub selects oldest retained sample"), History.Get_Displayed()->Get_Sequence(), uint64{3});
    }
    TestFalse(TEXT("Negative scrub index is rejected"), History.Scrub(-1));
    TestFalse(TEXT("Past-end scrub index is rejected"), History.Scrub(3));
    if (TestNotNull(TEXT("Rejected scrub retains selection"), History.Get_Displayed()))
    {
        TestEqual(TEXT("Rejected scrub cannot replace the pinned value"), History.Get_Displayed()->Get_Sequence(), uint64{3});
    }
    History.GoLive();
    TestTrue(TEXT("Go live restores presentation tracking"), History.Get_IsLive());
    if (TestNotNull(TEXT("Newest live sample is displayed"), History.Get_Displayed()))
    {
        TestEqual(TEXT("Go live jumps to newest captured value"), History.Get_Displayed()->Get_Sequence(), uint64{5});
    }
    History.Reset();
    TestEqual(TEXT("Reset removes captured history"), History.Get_Count(), 0);
    TestTrue(TEXT("Reset starts a fresh live session"), History.Get_IsLive());
    TestNull(TEXT("Reset releases the pinned sample"), History.Get_Displayed());
    TestFalse(TEXT("Empty history cannot be scrubbed"), History.Scrub(0));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralAnimationDebugger_HistoryRejectsStaleAndMixedSamples,
    "Ck.ProceduralAnimation.Debugger.History.RejectsStaleAndMixedSamples",
    ck_test_procedural_animation_debugger_history::TestFlags)

auto
    FCkProceduralAnimationDebugger_HistoryRejectsStaleAndMixedSamples::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_animation_debugger_history;
    auto History = FCkProceduralAnimationDebugger_History{3};
    TestFalse(TEXT("Default unavailable sample cannot become history"),
        History.Push(FCk_ProceduralAnimation_DebugSnapshot{}));
    auto Unsampled = MakeSample(1);
    Unsampled.Set_HasAcceptedSample(false);
    TestFalse(TEXT("Admitted but unsolved state cannot become a pose sample"), History.Push(Unsampled));
    TestTrue(TEXT("First accepted pose starts history"), History.Push(MakeSample(2)));
    TestFalse(TEXT("Repeated getter of the same accepted solve is deduplicated"), History.Push(MakeSample(2)));
    TestFalse(TEXT("Older solve cannot reorder history"), History.Push(MakeSample(1)));
    auto Mixed = MakeSample(3);
    Mixed.Set_EntityId(TEXT("OtherEntity"));
    TestFalse(TEXT("Another entity cannot mix into selected history"), History.Push(Mixed));
    auto BackwardsTime = MakeSample(3);
    BackwardsTime.Set_Time(FCk_Time{0.05});
    TestFalse(TEXT("Advancing sequence with backwards time is rejected"), History.Push(BackwardsTime));
    TestEqual(TEXT("Every rejected append leaves the captured count untouched"), History.Get_Count(), 1);
    if (TestNotNull(TEXT("Rejected appends retain the original sample"), History.Get_Displayed()))
    {
        TestEqual(TEXT("Rejected appends preserve the accepted sequence"), History.Get_Displayed()->Get_Sequence(), uint64{2});
    }
    TestTrue(TEXT("A valid later sample still appends after rejection"), History.Push(MakeSample(3)));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralAnimationDebugger_HistoryRejectsNonFiniteTime,
    "Ck.ProceduralAnimation.Debugger.History.RejectsNonFiniteTime",
    ck_test_procedural_animation_debugger_history::TestFlags)

auto
    FCkProceduralAnimationDebugger_HistoryRejectsNonFiniteTime::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_animation_debugger_history;
    auto History = FCkProceduralAnimationDebugger_History{3};
    TestTrue(TEXT("A finite accepted sample starts history"), History.Push(MakeSample(1)));

    auto NaNTime = MakeSample(2);
    NaNTime.Set_Time(FCk_Time{NaN});
    TestFalse(TEXT("A sample with a NaN time is rejected"), History.Push(NaNTime));

    auto InfiniteTime = MakeSample(3);
    InfiniteTime.Set_Time(FCk_Time{Infinity});
    TestFalse(TEXT("A sample with an infinite time is rejected"), History.Push(InfiniteTime));

    TestEqual(TEXT("Rejected non-finite samples leave the captured count untouched"), History.Get_Count(), 1);
    if (TestNotNull(TEXT("The finite sample is still displayed"), History.Get_Displayed()))
    {
        TestEqual(TEXT("The finite sample keeps its sequence"), History.Get_Displayed()->Get_Sequence(), uint64{1});
    }
    TestTrue(TEXT("A finite later sample still appends"), History.Push(MakeSample(4)));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralAnimationDebugger_HistoryClampsCapacity,
    "Ck.ProceduralAnimation.Debugger.History.ClampsCapacity",
    ck_test_procedural_animation_debugger_history::TestFlags)

auto
    FCkProceduralAnimationDebugger_HistoryClampsCapacity::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_animation_debugger_history;
    TestEqual(TEXT("A zero capacity clamps to one sample"),
        FCkProceduralAnimationDebugger_History{0}.Get_Capacity(), MinCapacity);
    TestEqual(TEXT("A negative capacity clamps to one sample"),
        FCkProceduralAnimationDebugger_History{-5}.Get_Capacity(), MinCapacity);
    TestEqual(TEXT("An oversized capacity clamps to the ring maximum"),
        FCkProceduralAnimationDebugger_History{MaxCapacity + 1000}.Get_Capacity(), MaxCapacity);

    auto Single = FCkProceduralAnimationDebugger_History{0};
    TestTrue(TEXT("A clamped single-sample ring records"), Single.Push(MakeSample(1)));
    TestTrue(TEXT("A clamped single-sample ring evicts in place"), Single.Push(MakeSample(2)));
    TestEqual(TEXT("A clamped single-sample ring holds one sample"), Single.Get_Count(), 1);
    if (TestNotNull(TEXT("The newest sample is retained"), Single.Get_Sample(0)))
    {
        TestEqual(TEXT("The single slot holds the newest sequence"), Single.Get_Sample(0)->Get_Sequence(), uint64{2});
    }
    return true;
}

#endif

// --------------------------------------------------------------------------------------------------------------------
