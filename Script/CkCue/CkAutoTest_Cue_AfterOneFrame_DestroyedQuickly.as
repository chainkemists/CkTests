// Language=angelscript

//============================================================================
// CK CUE - AUTOMATION TEST: AFTER-ONE-FRAME LIFETIME DESTROYS QUICKLY
//============================================================================
//
// Pins the AfterOneFrame lifetime contract: a cue fired with
// ECk_Cue_LifetimeBehavior::AfterOneFrame is constructed (entity tag
// observable for at least one tick) and then destroyed shortly after.
// After a 0.5s settle window, the cue entity must be gone.
//
// Uses the shared UCk_AutoTestCue_AfterOneFrame subclass (see
// CkAutoTest_Cue_Common.as).
//============================================================================

class UCk_AutoTest_Cue_AfterOneFrame_DestroyedQuickly : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Params = FCk_AutoTestCue_SpawnParams(FTransform::Identity);
        utils_cue_generic::Request_ExecuteCue(
            LocalHandle,
            GameplayTags::ResolveGameplayTag(n"AutoTest.Cue.AfterOneFrame"),
            FInstancedStruct::Make(Params),
            ECk_Cue_ReliabilityPolicy::Unreliable,
            ECk_Cue_MulticastPolicy::LocalOnly);

        // Settle past the cue spawn + one-frame destroy.
        auto SettleParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.5f));
        SettleParams.Set_StartingState(ECk_Timer_State::Running)
                    .Set_Behavior(ECk_Timer_Behavior::StopOnDone);
        auto SettleTimer = utils_timer::Add(LocalHandle, SettleParams);
        SettleTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnSettled"));
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto LiveCues = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AutoTestCue_AfterOneFrame");
        Assert_Equals_Int(LiveCues.Num(), 0,
            "AfterOneFrame cue should be destroyed within 0.5s of firing - no live entities should remain");

        FinishSuccess();
    }
}
