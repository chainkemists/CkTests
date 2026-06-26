// Language=angelscript

//============================================================================
// CK TIMER — AUTOMATION TEST: AddOrReplace replaces existing same-name timer
//============================================================================
//
// Pins the AddOrReplace contract (CkTimer_Utils.cpp:84): when a timer
// with the same TimerName already exists on the owner, AddOrReplace
// must:
//   1. Return the SAME entity (not create a new one).
//   2. Replace the timer's params + chrono in place.
//   3. Leave the owner with exactly ONE timer of that name.
//
// Verifies the no-duplicate contract by counting total timers on the
// owner via ForEach_Timer before and after AddOrReplace. Goal-value
// replacement is verified by re-reading the chrono after the call.
//
// Closes the AddOrReplace audit gap.
//============================================================================

class UCk_AutoTest_Timer_AddOrReplace_ReplacesExisting : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 2.0f;

    private int32 _CountBefore = 0;
    private int32 _CountAfter = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto FirstParams = FCk_Fragment_Timer_ParamsData(FCk_Time(10.0f));
        FirstParams.Set_TimerName(utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Timer.AddOrReplace_Slot"));
        FirstParams.Set_StartingState(ECk_Timer_State::Paused);
        FirstParams.Set_Behavior(ECk_Timer_Behavior::PauseOnDone);

        auto FirstTimer = utils_timer::Add(LocalHandle, FirstParams);
        Assert_True(ck::IsValid(FirstTimer),
            "Precondition: initial Add should return a valid handle");

        // Count timers BEFORE the AddOrReplace.
        utils_timer::ForEach_Timer(LocalHandle, FInstancedStruct(),
            FCk_Lambda_InHandle(this, n"OnVisitBefore"));
        Assert_Equals_Int(_CountBefore, 1,
            "Precondition: owner should have exactly 1 timer after the initial Add");

        // AddOrReplace with same name, different goal (5s instead of 10s).
        auto ReplaceParams = FCk_Fragment_Timer_ParamsData(FCk_Time(5.0f));
        ReplaceParams.Set_TimerName(utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Timer.AddOrReplace_Slot"));
        ReplaceParams.Set_StartingState(ECk_Timer_State::Paused);
        ReplaceParams.Set_Behavior(ECk_Timer_Behavior::PauseOnDone);

        auto ReplacedTimer = utils_timer::AddOrReplace(LocalHandle, ReplaceParams);
        Assert_True(ck::IsValid(ReplacedTimer),
            "AddOrReplace should return a valid handle");

        // Count timers AFTER. Should STILL be 1 (in-place replace, no new entity).
        utils_timer::ForEach_Timer(LocalHandle, FInstancedStruct(),
            FCk_Lambda_InHandle(this, n"OnVisitAfter"));
        Assert_Equals_Int(_CountAfter, 1,
            "After AddOrReplace on existing same-name timer, owner should still have exactly 1 timer (no duplicate added)");

        // Verify the chrono goal reflects the NEW duration (5s, not 10s).
        auto ReplacedChrono = utils_timer::Get_CurrentTimerValue(ReplacedTimer);
        FCk_Time ReplacedGoal;
        FCk_Time ReplacedElapsed;
        FCk_Time ReplacedRemaining;
        ReplacedChrono.Break_Chrono(ReplacedGoal, ReplacedElapsed, ReplacedRemaining);
        Assert_True(ReplacedGoal.Get_Milliseconds() == 5000,
            f"After AddOrReplace with goal=5s, chrono goal should be 5000ms (got {ReplacedGoal.Get_Milliseconds()}ms)");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnVisitBefore(FCk_Handle InHandle, FInstancedStruct InOptionalPayload)
    {
        _CountBefore += 1;
    }

    UFUNCTION()
    private void OnVisitAfter(FCk_Handle InHandle, FInstancedStruct InOptionalPayload)
    {
        _CountAfter += 1;
    }
}
