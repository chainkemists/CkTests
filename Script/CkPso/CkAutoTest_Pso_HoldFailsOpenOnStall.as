// Language=angelscript

//============================================================================
// CK PSO - AUTOMATION TEST: LOADING SCREEN HOLD FAILS OPEN
//============================================================================
//
// A pending count that never drains must not hold the loading screen forever:
// the window times out on whichever enabled budget is shorter (_DrainStallTimeout
// or _DrainMaxWait; MaxWait wins a tie) and releases the hold.
//
// ck.Pso.Debug.StallTimeoutOverride shortens the stall budget to half a second:
// every Warning any system logs while an AutoTest runs fails it, so a test that
// sat through the project's 10s budget would fail on unrelated editor noise.
// The effective budgets are then read back to know which reason to expect. The
// timeout Warning is this test's expected observation; the hand-authored
// wrapper below declares it.
//============================================================================

class UCk_AutoTest_Pso_HoldFailsOpenOnStall : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private UCk_Pso_Subsystem_UE _Pso;
    private UCk_LoadingScreen_Subsystem_UE _LoadingScreen;

    private int32 _SimulatedPending = 500;
    private bool _InitialNeeds = false;
    private ECk_Pso_DrainTimeoutReason _ExpectedReason = ECk_Pso_DrainTimeoutReason::None;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Pso = Cast<UCk_Pso_Subsystem_UE>(Subsystem::GetGameInstanceSubsystem(UCk_Pso_Subsystem_UE));
        if (ck::Is_NOT_Valid(_Pso))
        {
            FinishFailure("UCk_Pso_Subsystem_UE not found on the PIE game instance");
            return;
        }

        _LoadingScreen = Cast<UCk_LoadingScreen_Subsystem_UE>(Subsystem::GetGameInstanceSubsystem(UCk_LoadingScreen_Subsystem_UE));
        if (ck::Is_NOT_Valid(_LoadingScreen))
        {
            FinishFailure("UCk_LoadingScreen_Subsystem_UE not found on the PIE game instance");
            return;
        }

        Set_CVarForTest(n"ck.Pso.Debug.StallTimeoutOverride", "0.5");

        const float StallSeconds = float(UCk_Utils_Pso_Settings_UE::Get_DrainStallTimeout().Get_Seconds());
        const float MaxWaitSeconds = float(UCk_Utils_Pso_Settings_UE::Get_DrainMaxWait().Get_Seconds());
        const bool StallIsEnabled = StallSeconds > 0.0;
        const bool MaxWaitIsEnabled = MaxWaitSeconds > 0.0;

        if (StallIsEnabled == false && MaxWaitIsEnabled == false)
        {
            FinishFailure("both _DrainStallTimeout and _DrainMaxWait are disabled - a count that never drains would hold the loading screen forever");
            return;
        }

        float ExpectedSeconds = MaxWaitSeconds;
        _ExpectedReason = ECk_Pso_DrainTimeoutReason::MaxWait;
        if (StallIsEnabled && (MaxWaitIsEnabled == false || StallSeconds < MaxWaitSeconds))
        {
            ExpectedSeconds = StallSeconds;
            _ExpectedReason = ECk_Pso_DrainTimeoutReason::Stalled;
        }

        // The tracker charges at most 0.1s per tick, so a slow frame stretches the wall-clock wait past the budget.
        const float TimeoutBoundSeconds = ExpectedSeconds + 3.0;
        if (TimeoutBoundSeconds > _TimeoutSeconds * 0.9f)
        {
            FinishFailure(f"the configured fail-open budget ({ExpectedSeconds}s) does not fit this test's deadline - raise _TimeoutSeconds on the entity script AND the wrapper");
            return;
        }

        Add_Step(          "arm a simulated drain window that never drains", n"Step_Arm");
        Add_Step_WaitUntil("the window fails open on its budget",             n"Check_TimedOut", 0, TimeoutBoundSeconds);
        Add_Step(          "the fail-open released the loading screen",       n"Step_AssertFailOpen");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arm(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _InitialNeeds = _LoadingScreen.Get_NeedsLoadingScreen();

        Set_CVarForTest(n"ck.Pso.WaitForPrecache", "1");
        Set_CVarForTest(n"ck.Pso.Debug.SimulatedRemaining", f"{_SimulatedPending}");

        _Pso.Request_BeginDrainWindow();

        Assert_True(_LoadingScreen.Get_NeedsLoadingScreen(),
            "a holding PSO drain window must flip Get_NeedsLoadingScreen to true before it times out");

        FString Reason = _LoadingScreen.Get_DebugReason();
        Assert_True(Reason.Contains("PSO precache"),
            f"Get_DebugReason must name the PSO gate while it holds (got: {Reason})");
    }

    UFUNCTION()
    private void Check_TimedOut(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Pso.Get_DrainProgress().Get_State() == ECk_Pso_DrainState::TimedOut);
    }

    UFUNCTION()
    private void Step_AssertFailOpen(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Progress = _Pso.Get_DrainProgress();
        Assert_True(Progress.Get_TimeoutReason() == _ExpectedReason,
            "the window must time out on the shorter enabled budget");
        Assert_Equals_Int(Progress.Get_NumRemaining(), _SimulatedPending,
            "a fail-open release leaves the pending work where it was");

        Assert_True(_Pso.Get_IsDraining() == false,
            "a timed-out window no longer holds");
        const bool NeedsAfterTimeout = _LoadingScreen.Get_NeedsLoadingScreen();
        Assert_True(NeedsAfterTimeout == _InitialNeeds,
            f"a timed-out PSO window must restore the baseline need state - fail-open (initial={_InitialNeeds}, after={NeedsAfterTimeout})");

        FString Reason = _LoadingScreen.Get_DebugReason();
        Assert_True(Reason.Contains("PSO precache") == false,
            f"a timed-out PSO window must no longer be surfaced as the reason (got: {Reason})");
    }
}

// Hand-authored so the expected timeout Warning can be declared. The generator skips any wrapper living outside
// Script/Generated/, which also means it no longer propagates _TimeoutSeconds - this wrapper must match the entity
// script's value itself.
class ACk_AutoTest_Pso_HoldFailsOpenOnStall_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Pso_HoldFailsOpenOnStall;
    default _TimeoutSeconds = 10.0f;

    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        Out.Add("PSO drain window timed out");
        return Out;
    }
}
