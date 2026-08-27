// Language=angelscript

//============================================================================
// CK LOADINGSCREEN - AUTOMATION TEST: HOLDER SEMANTICS
//============================================================================
//
// Verifies the CkLoadingScreen holder bookkeeping headlessly. Presentation is
// suppressed in -unattended/null-RHI runs by design, but the holder state
// machine still runs - this test asserts exactly that contract:
//
//   1. The subsystem exists in PIE.
//   2. Creating a UCk_LoadingProcess_Task_UE flips Get_NeedsLoadingScreen()
//      to true with the task's reason surfaced in Get_DebugReason().
//   3. Request_SetReason updates the surfaced reason.
//   4. A generous watchdog timeout does not mis-trip while legitimately held.
//   5. Request_Unregister releases the hold - Get_NeedsLoadingScreen()
//      returns to its pre-test value and the reason no longer mentions us.
//   6. Presentation never engages headless (Get_IsLoadingScreenShowing()
//      stays false throughout).
//
// Everything is synchronous (no deferred ECS requests), so the whole test
// runs inside DoBeginPlay.
//============================================================================

class UCk_AutoTest_LoadingScreen_HolderSemantics : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto Subsystem = Subsystem::GetGameInstanceSubsystem(UCk_LoadingScreen_Subsystem_UE);
        if (ck::Is_NOT_Valid(Subsystem))
        {
            FinishFailure("UCk_LoadingScreen_Subsystem_UE not found on the PIE game instance");
            return;
        }

        // Capture the environment's baseline before we register anything.
        const bool InitialNeeds = Subsystem.Get_NeedsLoadingScreen();

        Assert_True(!Subsystem.Get_IsLoadingScreenShowing(),
            "presentation must be suppressed headless (screen not showing at start)");

        const FString HolderReason = "CkAutoTest_LoadingScreen holder ALPHA";
        // WorldContextObject param is auto-filled (stripped from the AS signature by the fork).
        auto Task = UCk_LoadingProcess_Task_UE::Create(HolderReason, FCk_Time());
        if (ck::Is_NOT_Valid(Task))
        {
            FinishFailure("UCk_LoadingProcess_Task_UE::Create returned null on a client game instance");
            return;
        }

        Assert_True(Subsystem.Get_NeedsLoadingScreen(),
            "a registered holder task must flip Get_NeedsLoadingScreen to true");
        FString ReasonAfterCreate = Subsystem.Get_DebugReason();
        Assert_True(ReasonAfterCreate.Contains(HolderReason),
            f"Get_DebugReason must surface the holder's reason (got: {ReasonAfterCreate})");

        const FString UpdatedReason = "CkAutoTest_LoadingScreen holder BETA";
        Task.Request_SetReason(UpdatedReason);
        Subsystem.Get_NeedsLoadingScreen();  // re-evaluates so Get_DebugReason reflects the new reason
        FString ReasonAfterUpdate = Subsystem.Get_DebugReason();
        Assert_True(ReasonAfterUpdate.Contains(UpdatedReason),
            f"Get_DebugReason must surface the updated reason (got: {ReasonAfterUpdate})");

        // A generous watchdog timeout must not mis-trip while the hold is legitimately active.
        auto TimedTask = UCk_LoadingProcess_Task_UE::Create("CkAutoTest_LoadingScreen holder TIMED", FCk_Time(60.0f));
        Assert_True(Subsystem.Get_NeedsLoadingScreen(),
            "a timeout-armed holder must hold like a normal one before its deadline");
        Assert_True(!TimedTask.Get_HasTimedOut(),
            "a 60s watchdog must not have tripped within the same frame");
        TimedTask.Request_Unregister();

        Task.Request_Unregister();

        const bool NeedsAfterRelease = Subsystem.Get_NeedsLoadingScreen();
        FString ReasonAfterRelease = Subsystem.Get_DebugReason();
        Assert_True(NeedsAfterRelease == InitialNeeds,
            f"releasing the holder must restore the baseline need state (initial={InitialNeeds}, after={NeedsAfterRelease})");
        Assert_True(!ReasonAfterRelease.Contains("CkAutoTest_LoadingScreen holder"),
            f"released holder's reason must no longer be surfaced (got: {ReasonAfterRelease})");

        Assert_True(!Subsystem.Get_IsLoadingScreenShowing(),
            "presentation must be suppressed headless (screen not showing at end)");

        FinishSuccess();
    }
}
