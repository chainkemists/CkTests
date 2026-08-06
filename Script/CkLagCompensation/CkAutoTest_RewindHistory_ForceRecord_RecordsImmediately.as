// Language=angelscript

//============================================================================
// CK REWIND HISTORY — AUTOMATION TEST: FORCE RECORD RECORDS IMMEDIATELY
//============================================================================
//
// The record interval is set far beyond the test's lifetime, so only two
// things can ever put frames in the buffer:
//   1. The guaranteed first-frame record (buffer must never start empty).
//   2. An explicit Request_ForceRecordFrame.
// The test verifies both, and that no interval-driven recording sneaks in
// between the marks.
//============================================================================

class UCk_AutoTest_RewindHistory_ForceRecord_RecordsImmediately : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_RewindHistory _History;
    private int32 _CountBeforeForce = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        auto Target = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        utils_transform::Add(Target, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto HitShapes = TArray<FCk_LagComp_HitShape>();
        HitShapes.Add(FCk_LagComp_HitShape(
            utils_gameplay_tag::ResolveGameplayTag(n"CkTests.LagComp.Body"),
            UCk_Utils_Shapes_UE::Make_Sphere(FCk_ShapeSphere_Dimensions(50.0))));

        // Interval far longer than the test — interval-driven recording is impossible
        auto Params = FCk_RewindHistory_Spec(HitShapes);
        Params.Set_RecordInterval(FCk_Time(60.0));
        Params.Set_RetentionPeriod(FCk_Time(120.0));

        _History = UCk_Utils_RewindHistory_UE::Add(Target, Params);

        if (ck::Is_NOT_Valid(_History))
        {
            FinishFailure("UCk_Utils_RewindHistory_UE::Add should return a valid handle");
            return;
        }

        ScheduleMark(0.3, n"OnMark1");
    }

    private void ScheduleMark(float InDelaySeconds, FName InCallbackName)
    {
        auto Params = FCk_Timer_Spec(FCk_Time(InDelaySeconds));
        Params.Set_StartingState(ECk_Timer_State::Running)
              .Set_Behavior(ECk_Timer_Behavior::StopOnDone);
        auto Timer = utils_timer::Add(_SelfHandle, Params);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, InCallbackName));
    }

    UFUNCTION()
    private void OnMark1(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _CountBeforeForce = _History.Get_RecordedFrameCount();

        Assert_Equals_Int(_CountBeforeForce, 1,
            "Only the guaranteed first frame should have recorded under a 60s interval");

        _History.Request_ForceRecordFrame();

        ScheduleMark(0.2, n"OnMark2");
    }

    UFUNCTION()
    private void OnMark2(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_History.Get_RecordedFrameCount(), _CountBeforeForce + 1,
            "ForceRecordFrame should have recorded exactly one extra frame despite the interval");

        FinishSuccess();
    }
}
