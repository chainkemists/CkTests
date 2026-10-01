// Language=angelscript

//============================================================================
// CK PSO - AUTOMATION TEST: LOADING SCREEN HOLD
//============================================================================
//
// Drives the PSO drain gate headlessly through ck.Pso.Debug.SimulatedRemaining.
// Under WITH_EDITOR the engine disables PSO precaching outright, so the gate is
// inert in every editor/PIE run unless a simulated count is set - this cvar is
// the only way to exercise it here.
//
//   1. A simulated pending count plus Request_BeginDrainWindow holds
//      Get_NeedsLoadingScreen() with a "PSO precache" reason.
//   2. The hold persists while the count does not move.
//   3. Dropping the count to zero does not release on the spot; the hold drops
//      only once the quiet period has run.
//
// Both cvars go through Set_CVarForTest, which restores them on the success AND
// failure paths, so the gate is inert again for every later test in the lane.
//============================================================================

class UCk_AutoTest_Pso_HoldReleasesAfterQuietPeriod : UCk_AutoTest_Base
{
    private UCk_Pso_Subsystem_UE _Pso;
    private UCk_LoadingScreen_Subsystem_UE _LoadingScreen;

    private int32 _SimulatedPending = 500;
    private bool _InitialNeeds = false;
    private float _DrainedToZeroAtSeconds = 0.0;

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

        const float ReleaseBoundSeconds = float(UCk_Utils_Pso_Settings_UE::Get_DrainQuietPeriod().Get_Seconds()) + 2.0;

        Add_Step(          "arm a simulated drain window",                  n"Step_Arm");
        Add_Step_WaitFrames("the simulated pending count does not move",    10);
        Add_Step(          "the hold persists while nothing drains",       n"Step_AssertStillHolding");
        Add_Step(          "drain the simulated count to zero",             n"Step_DrainToZero");
        Add_Step_WaitUntil("the PSO gate releases after the quiet period",  n"Check_Released", 0, ReleaseBoundSeconds);
        Add_Step(          "the release restored the baseline need state",  n"Step_AssertReleased");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arm(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _InitialNeeds = _LoadingScreen.Get_NeedsLoadingScreen();

        Set_CVarForTest(n"ck.Pso.WaitForPrecache", "1");
        Set_CVarForTest(n"ck.Pso.Debug.SimulatedRemaining", f"{_SimulatedPending}");

        _Pso.Request_BeginDrainWindow();

        Assert_True(_Pso.Get_IsDraining(),
            "Request_BeginDrainWindow with a simulated pending count must open a holding window");
        Assert_True(_LoadingScreen.Get_NeedsLoadingScreen(),
            "a holding PSO drain window must flip Get_NeedsLoadingScreen to true");

        FString Reason = _LoadingScreen.Get_DebugReason();
        Assert_True(Reason.Contains("PSO precache"),
            f"Get_DebugReason must name the PSO gate (got: {Reason})");

        auto Progress = _Pso.Get_DrainProgress();
        Assert_True(Progress.Get_State() == ECk_Pso_DrainState::Draining,
            "a window armed with pending work starts Draining");
        Assert_Equals_Int(Progress.Get_NumRemaining(), _SimulatedPending,
            "the armed window is seeded with the pending count immediately");
        Assert_Equals_Int(Progress.Get_NumPeak(), _SimulatedPending,
            "the seeded count is the window's peak");
    }

    UFUNCTION()
    private void Step_AssertStillHolding(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_Pso.Get_IsDraining(),
            "the window must keep holding while the pending count does not decrease");
        Assert_True(_LoadingScreen.Get_NeedsLoadingScreen(),
            "the loading screen must stay needed while the PSO window holds");

        auto Progress = _Pso.Get_DrainProgress();
        Assert_True(Progress.Get_State() == ECk_Pso_DrainState::Draining,
            "a count that has not moved keeps the window Draining");
        Assert_Equals_Float(Progress.Get_ProgressRatio(), 0.0, 0.0001,
            "no drained work means no progress");
    }

    UFUNCTION()
    private void Step_DrainToZero(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Set_CVarForTest(n"ck.Pso.Debug.SimulatedRemaining", "0");
        _DrainedToZeroAtSeconds = float(System::GetGameTimeInSeconds());

        Assert_True(_Pso.Get_IsDraining(),
            "the window must not release in the same frame the count reaches zero");
        Assert_True(_LoadingScreen.Get_NeedsLoadingScreen(),
            "the loading screen must stay needed until the quiet period has run");
    }

    UFUNCTION()
    private void Check_Released(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Pso.Get_IsDraining() == false);
    }

    UFUNCTION()
    private void Step_AssertReleased(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Progress = _Pso.Get_DrainProgress();
        Assert_True(Progress.Get_State() == ECk_Pso_DrainState::Complete,
            "a drained window completes rather than timing out");
        Assert_Equals_Float(Progress.Get_ProgressRatio(), 1.0, 0.0001,
            "a completed window reports full progress");

        const float QuietPeriodSeconds = float(UCk_Utils_Pso_Settings_UE::Get_DrainQuietPeriod().Get_Seconds());
        const float HeldForSeconds = float(System::GetGameTimeInSeconds()) - _DrainedToZeroAtSeconds;
        Assert_True(HeldForSeconds >= QuietPeriodSeconds - 0.001,
            f"the hold must outlast the quiet period ({QuietPeriodSeconds}s) after the count reached zero (released after {HeldForSeconds}s)");

        const bool NeedsAfterRelease = _LoadingScreen.Get_NeedsLoadingScreen();
        Assert_True(NeedsAfterRelease == _InitialNeeds,
            f"a completed PSO window must restore the baseline need state (initial={_InitialNeeds}, after={NeedsAfterRelease})");

        FString Reason = _LoadingScreen.Get_DebugReason();
        Assert_True(Reason.Contains("PSO precache") == false,
            f"a released PSO window must no longer be surfaced as the reason (got: {Reason})");
    }
}
