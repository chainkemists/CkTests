// Language=angelscript

//============================================================================
// CK CUE — AUTOMATION TEST: PERSISTENT LIFETIME STAYS ALIVE
//============================================================================
//
// Pins the Persistent lifetime contract: a cue fired with
// ECk_Cue_LifetimeBehavior::Persistent stays alive indefinitely (until
// explicitly destroyed). After a 0.5s settle, the cue entity is still
// observable via its marker tag.
//
// Companion to Cue_AfterOneFrame_DestroyedQuickly — these two tests
// together pin the two lifetime endpoints (immediate destroy vs. no
// auto-destroy). Timed is covered separately.
//============================================================================

class UCk_AutoTest_Cue_Persistent_StaysAlive : UCk_AutoTest_Base
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
            GameplayTags::ResolveGameplayTag(n"AutoTest.Cue.Persistent"),
            FInstancedStruct::Make(Params),
            ECk_Cue_ReliabilityPolicy::Unreliable,
            ECk_Cue_MulticastPolicy::LocalOnly);

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

        auto LiveCues = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AutoTestCue_Persistent");
        Assert_Equals_Int(LiveCues.Num(), 1,
            "Persistent cue should still be alive 0.5s after firing — exactly one tagged entity should remain");

        FinishSuccess();
    }
}
