// T-C6-1a — the hold-to-(scope, tick time) table, asserted as a table.
//
// What a world-actor tick is allowed to do during a load is one mapping from one enum, and ck::Get_TickPlanForHold
// is that mapping written as a pure function precisely so it can be asserted without a world. Every row matters
// for a different reason, and getting any of them wrong is silent:
//
//   None        Full / real   — normal play; a hold left set here would freeze a live game.
//   Teardown    Full / ZERO   — kernel scope WEDGES a teardown (the destruction pipeline, the entity-lifecycle
//                               groups and all 136 feature EndPlay processors are outside the kernel), so this
//                               row is the difference between a load that completes and one that hangs.
//   Rebuilding  Kernel / real — the only row that keeps real time, because the kernel's own watchdogs are the
//                               things that must still make progress while nothing else does.
//   Escalated   Full / ZERO   — full scope so multi-stage constructions can finish, zero time so time-paced world
//                               policy cannot act on a census taken mid-rebuild.
//   Draining    Full / ZERO   — payload applies and the deferred requests they issue.
//   Converging  Full / ZERO   — physics and overlaps converge before the player is handed the world.
//
// RED before C6: ECk_EcsWorld_LoadHold, ck::FCk_TickPlan and Get_TickPlanForHold do not exist — the pre-range
// world actor read a bool pair inline, so the mapping had no name and no observation point at all.
// Surface in Session Frontend: Ck.Snapshot.LoadHold.TickPlanForHold

#include "CkCore/Format/CkFormat.h" // ck::Format_UE — the enum spells itself in the failure message
#include "CkCore/Macros/CkMacros.h"

#include "CkEcs/Scheduler/CkProcessorScheduler.h" // ECk_SchedulerTickScope
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_test_loadhold_tickplan
{
    constexpr auto kFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::ProductFilter;

    // A frame delta no row may invent and no row may round away from: the real-time rows must hand this through
    // unchanged, and the frozen rows must not leak any part of it.
    constexpr auto DeltaSeconds = 1.0f / 60.0f;

    struct FExpectedRow
    {
        ECk_EcsWorld_LoadHold Hold;
        ck::ECk_SchedulerTickScope Scope;
        bool ExpectsRealTime;
        const TCHAR* Why;
    };
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_LoadHold_TickPlanForHold,
    "Ck.Snapshot.LoadHold.TickPlanForHold",
    ck_test_loadhold_tickplan::kFlags)

bool FCk_Snapshot_LoadHold_TickPlanForHold::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_loadhold_tickplan;

    const auto ExpectedTable = TArray<FExpectedRow>
    {
        {ECk_EcsWorld_LoadHold::None, ck::ECk_SchedulerTickScope::Full, true,
            TEXT("normal play")},
        {ECk_EcsWorld_LoadHold::Teardown, ck::ECk_SchedulerTickScope::Full, false,
            TEXT("kernel scope wedges the destruction cascade this phase waits on")},
        {ECk_EcsWorld_LoadHold::Rebuilding, ck::ECk_SchedulerTickScope::LoadKernel, true,
            TEXT("the kernel's own watchdogs have to keep making progress")},
        {ECk_EcsWorld_LoadHold::Escalated, ck::ECk_SchedulerTickScope::Full, false,
            TEXT("full scope to finish staged constructions, zero time so world policy cannot act on them")},
        {ECk_EcsWorld_LoadHold::Draining, ck::ECk_SchedulerTickScope::Full, false,
            TEXT("payload applies and the deferred requests they issue")},
        {ECk_EcsWorld_LoadHold::Converging, ck::ECk_SchedulerTickScope::Full, false,
            TEXT("physics and overlaps converge before the world is handed back")},
    };

    // The table is the contract, so a NEW hold value must fail here rather than quietly inherit a default.
    auto AllGood = TestEqual(
        TEXT("the expected table covers every ECk_EcsWorld_LoadHold value"),
        ExpectedTable.Num(), static_cast<int32>(ECk_EcsWorld_LoadHold::Converging) + 1);

    for (const auto& Row : ExpectedTable)
    {
        const auto Plan = ck::Get_TickPlanForHold(Row.Hold, DeltaSeconds);

        AllGood &= TestTrue(
            FString::Printf(TEXT("[%s] ticks at the %s scope — %s"),
                *ck::Format_UE(TEXT("{}"), Row.Hold),
                Row.Scope == ck::ECk_SchedulerTickScope::Full ? TEXT("FULL") : TEXT("LoadKernel"),
                Row.Why),
            Plan._Scope == Row.Scope);

        if (Row.ExpectsRealTime)
        {
            AllGood &= TestEqual(
                FString::Printf(TEXT("[%s] hands the frame's REAL delta through unchanged"),
                    *ck::Format_UE(TEXT("{}"), Row.Hold)),
                Plan._TickTime.Get_Seconds(), static_cast<double>(DeltaSeconds), 1.0e-6);
        }
        else
        {
            AllGood &= TestEqual(
                FString::Printf(TEXT("[%s] hands out ZERO time — %s"),
                    *ck::Format_UE(TEXT("{}"), Row.Hold), Row.Why),
                Plan._TickTime.Get_Seconds(), 0.0, 1.0e-9);
        }
    }

    // The zeroing is a property of the HOLD, not of the frame: a long frame must not leak time into a frozen
    // phase, and a zero-length frame must not make a real-time phase look frozen.
    AllGood &= TestEqual(
        TEXT("a long frame still yields zero time under Converging"),
        ck::Get_TickPlanForHold(ECk_EcsWorld_LoadHold::Converging, 10.0f)._TickTime.Get_Seconds(), 0.0, 1.0e-9);

    AllGood &= TestEqual(
        TEXT("a long frame passes through unchanged under None"),
        ck::Get_TickPlanForHold(ECk_EcsWorld_LoadHold::None, 10.0f)._TickTime.Get_Seconds(), 10.0, 1.0e-6);

    return AllGood;
}

#endif // WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
