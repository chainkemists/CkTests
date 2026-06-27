// Registry-level round-trip for the CkTimer countdown progress. Proves FFragment_Timer_Current's FCk_Chrono —
// specifically its UPROPERTY(Transient) _CurrentValue (the elapsed/countdown progress) — survives capture -> wipe ->
// restore. _CurrentValue is Transient (correctly dropped by replication + the reflected save path), so the only way
// a mid-countdown timer RESUMES after a load is the explicit FCk_Chrono::SerializeSnapshot this test guards. If that
// serialize regresses, the restored chrono's elapsed reads 0 and the equality fails.

#include "CkSnapshot/Snapshot/CkSnapshot_Capture.h"
#include "CkSnapshot/Snapshot/CkSnapshot_Restore.h"
#include "CkSnapshot/SaveGame/CkSnapshot_Header.h"
#include "CkSnapshot/Snapshot/CkSnapshot_LoadReport.h"

#include "CkTimer/CkTimer_Fragment.h"

#include "CkCore/Chrono/CkChrono.h"
#include "CkCore/Time/CkTime.h"

#include "CkEcs/World/CkEcsWorld.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"

#include "CkCore/Macros/CkMacros.h"

#include "Serialization/BufferArchive.h"
#include "Serialization/MemoryReader.h"

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_TimerChrono_RoundTrip_Test,
    "Ck.Snapshot.Timer.ChronoRoundTrip",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_TimerChrono_RoundTrip_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    constexpr auto GoalSeconds    = 10.0;
    constexpr auto ElapsedSeconds = 3.5; // a distinctive mid-countdown value (NOT 0, NOT the goal)
    constexpr auto Tolerance      = 0.001;

    // ---- Arrange: a chrono ticked to a distinctive mid-countdown, added as a Timer_Current fragment ------------
    auto EcsWorld = ck::FEcsWorld{};

    auto* RawRegistry = ck::registry_table::TryResolve(EcsWorld.Get_Registry().Get_RegistryHandle());
    if (NOT TestNotNull(TEXT("Resolved raw entt registry from FEcsWorld"), RawRegistry))
    { return false; }

    auto TimerEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(EcsWorld.Get_Registry());
    if (NOT TestTrue(TEXT("Timer entity is valid"), ck::IsValid(TimerEntity)))
    { return false; }

    auto Chrono = FCk_Chrono{FCk_Time{GoalSeconds}};
    Chrono.Tick(FCk_Time{ElapsedSeconds}); // advance elapsed to 3.5s
    TimerEntity.Add<ck::FFragment_Timer_Current>(Chrono);

    if (NOT TestTrue(TEXT("Pre-capture: live chrono elapsed == 3.5s"),
            FMath::IsNearlyEqual(TimerEntity.Get<ck::FFragment_Timer_Current>().Get_Chrono().Get_TimeElapsed().Get_Seconds(),
                ElapsedSeconds, Tolerance)))
    { return false; }

    // ---- Act (capture) ----------------------------------------------------------------------------------------
    auto Buffer = FBufferArchive{};
    auto Header = FCk_Snapshot_Header{};

    if (NOT TestEqual(TEXT("Capture result is Success"),
            static_cast<uint8>(ck::snapshot::Run_Capture_Registry(*RawRegistry, Buffer, Header)),
            static_cast<uint8>(ECk_SnapshotResult::Success)))
    { return false; }

    // ---- Act (restore: wipe-then-rebuild) ---------------------------------------------------------------------
    auto Reader = FMemoryReader{Buffer, /*bIsPersistent=*/true};
    const auto Report = ck::snapshot::Run_Restore_Registry(*RawRegistry, Reader, Header);

    TestEqual(TEXT("Restore result is Success"),
        static_cast<uint8>(Report.Get_Result()), static_cast<uint8>(ECk_SnapshotResult::Success));
    // A non-zero skip here means FFragment_Timer_Current's marker/registration didn't take.
    TestEqual(TEXT("No fragment types were skipped"), Report.Get_SkippedFragmentTypes().Num(), 0);

    // ---- Assert: the chrono's goal AND mid-countdown progress survived ------------------------------------------
    // The pre-restore handle is stale (registry was wiped); re-find the restored entity by view.
    auto FoundCount = 0;
    for (const auto Entity : RawRegistry->view<ck::FFragment_Timer_Current>())
    {
        ++FoundCount;
        const auto& RestoredChrono = RawRegistry->get<ck::FFragment_Timer_Current>(Entity).Get_Chrono();

        // THE load-bearing assertion: _CurrentValue (Transient) survived past the snapshot Transient trap.
        TestTrue(TEXT("Restored chrono elapsed == 3.5s (Transient _CurrentValue resumed, not reset to 0)"),
            FMath::IsNearlyEqual(RestoredChrono.Get_TimeElapsed().Get_Seconds(), ElapsedSeconds, Tolerance));
        TestTrue(TEXT("Restored chrono goal == 10s (remaining == 6.5s)"),
            FMath::IsNearlyEqual(RestoredChrono.Get_TimeRemaining().Get_Seconds(), GoalSeconds - ElapsedSeconds, Tolerance));
    }

    TestEqual(TEXT("Exactly one entity carries the Timer_Current fragment after restore"), FoundCount, 1);

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
