// Language=angelscript

//============================================================================
// CK CUE — AUTOMATION TEST: TIMED LIFETIME DESTROYS AFTER DURATION
//============================================================================
//
// Pins the Timed lifetime contract: a cue with
// ECk_Cue_LifetimeBehavior::Timed and _LifetimeDuration=0.2s is alive
// shortly after firing (~0.1s in) and destroyed after a comfortable
// margin past the duration (~0.5s wait total).
//
// Two phase observation:
//   - At t=0.1s: cue is alive (entity tag count == 1).
//   - At t=0.5s: cue is destroyed (entity tag count == 0).
//============================================================================

class UCk_AutoTest_Cue_Timed_DestroyedAfterDuration : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private bool _MidFlightCueObserved = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto Params = FCk_AutoTestCue_SpawnParams(FTransform::Identity);
        utils_cue_generic::Request_ExecuteCue(
            LocalHandle,
            GameplayTags::ResolveGameplayTag(n"AutoTest.Cue.Timed"),
            FInstancedStruct::Make(Params),
            ECk_Cue_ReliabilityPolicy::Unreliable,
            ECk_Cue_MulticastPolicy::LocalOnly);

        // Mid-flight check at 0.1s — well before the 0.2s lifetime expires.
        System::SetTimer(this, n"OnMidFlight", 0.1f, false);
        // Final check at 0.5s — well past the 0.2s lifetime expiry.
        System::SetTimer(this, n"OnAfterExpiry", 0.5f, false);
    }

    UFUNCTION()
    private void OnMidFlight()
    {
        if (IsFinished()) { return; }

        auto LiveCues = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AutoTestCue_Timed");
        _MidFlightCueObserved = LiveCues.Num() == 1;
    }

    UFUNCTION()
    private void OnAfterExpiry()
    {
        if (IsFinished()) { return; }

        Assert_True(_MidFlightCueObserved,
            "Timed cue should still be alive at 0.1s (well before the 0.2s _LifetimeDuration expires) — without this the test cannot prove the duration mattered");

        auto LiveCues = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_AutoTestCue_Timed");
        Assert_Equals_Int(LiveCues.Num(), 0,
            "Timed cue should be destroyed by 0.5s (past the 0.2s _LifetimeDuration with margin) — no live entities should remain");

        FinishSuccess();
    }
}
