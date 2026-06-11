// Language=angelscript

//============================================================================
// CK REWIND HISTORY — AUTOMATION TEST: REWIND FINDS PAST POSE
//============================================================================
//
// Verifies the record processor + rewind queries end-to-end:
//   1. Entity with a 'Body' sphere hit shape sits at A while history records.
//   2. Capture T_A (newest recorded time while at A), teleport entity to B.
//   3. After more recording at B:
//      - Interpolated snapshots at T_A still report pose A.
//      - A sweep through A at the PAST time window hits (the MWO rewind case).
//      - The same sweep at the PRESENT time misses (target has moved).
//      - A sweep through B at the present time hits.
//============================================================================

namespace ck_rewind_history_test
{
    asset Asset_RewindHistoryTest_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"CkTests.LagComp.Body");
    }
}

class UCk_AutoTest_RewindHistory_RewindFindsPastPose : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_RewindHistory _History;
    private FCk_Handle_Transform _Transform;

    private FVector _PoseA = FVector(0.0, 0.0, 0.0);
    private FVector _PoseB = FVector(0.0, 1000.0, 0.0);
    private float _TimeAtA = 0.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        auto Target = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _Transform = utils_transform::Add(
            Target, FTransform(FRotator::ZeroRotator, _PoseA), ECk_Replication::DoesNotReplicate);

        auto HitShapes = TArray<FCk_LagComp_HitShape>();
        HitShapes.Add(FCk_LagComp_HitShape(
            utils_gameplay_tag::ResolveGameplayTag(n"CkTests.LagComp.Body"),
            UCk_Utils_Shapes_UE::Make_Sphere(FCk_ShapeSphere_Dimensions(50.0))));

        auto Params = FCk_Fragment_RewindHistory_ParamsData(HitShapes);
        _History = UCk_Utils_RewindHistory_UE::Add(Target, Params);

        if (ck::Is_NOT_Valid(_History))
        {
            FinishFailure("UCk_Utils_RewindHistory_UE::Add should return a valid handle");
            return;
        }

        ScheduleMark(0.4, n"OnMark1");
    }

    private void ScheduleMark(float InDelaySeconds, FName InCallbackName)
    {
        auto Params = FCk_Fragment_Timer_ParamsData(FCk_Time(InDelaySeconds));
        Params.Set_StartingState(ECk_Timer_State::Running)
              .Set_Behavior(ECk_Timer_Behavior::StopOnDone);
        auto Timer = utils_timer::Add(_SelfHandle, Params);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, InCallbackName));
    }

    UFUNCTION()
    private void OnMark1(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(_History.Get_RecordedFrameCount() >= 2,
            f"History should have recorded several frames while at A (got {_History.Get_RecordedFrameCount()})");

        _TimeAtA = _History.Get_NewestFrameTime().Get_Seconds();

        utils_transform::Request_SetLocation(_Transform, FCk_Request_Transform_SetLocation(_PoseB));

        ScheduleMark(0.5, n"OnMark2");
    }

    UFUNCTION()
    private void OnMark2(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // ---- Interpolated past pose ----
        auto PastSnapshots = _History.Get_InterpolatedSnapshotsAtTime(FCk_Time(_TimeAtA));
        Assert_Equals_Int(PastSnapshots.Num(), 1, "One hit shape snapshot at the past time");

        if (PastSnapshots.Num() == 1)
        {
            auto PastLocation = PastSnapshots[0].Get_WorldTransform().Location;
            Assert_True((PastLocation - _PoseA).Size() < 5.0,
                f"Interpolated pose at T_A should be A (got {PastLocation})");
        }

        // ---- Rewind sweep through A at the PAST time: hit ----
        auto SegmentStart = FVector(-200.0, 0.0, 0.0);
        auto SegmentEnd = FVector(200.0, 0.0, 0.0);

        // Window strictly BEFORE the teleport: a slice that straddles the teleport frame would
        // interpolate the target mid-jump, and the relative-motion sweep would correctly miss
        FCk_LagComp_RewindHit PastHit;
        auto PastHitFound = _History.Sweep_AgainstHistory(
            SegmentStart, SegmentEnd,
            FCk_Time(_TimeAtA - 0.06), FCk_Time(_TimeAtA - 0.02), 5.0, PastHit);

        Assert_True(PastHitFound, "Sweep through A at the past time window should hit");
        if (PastHitFound)
        {
            Assert_True(PastHit.Get_HitShapeLabel() == utils_gameplay_tag::ResolveGameplayTag(n"CkTests.LagComp.Body"),
                "Rewind hit should carry the 'Body' hit shape label");
        }

        // ---- Same sweep at the PRESENT time: miss (target moved to B) ----
        auto NowTime = _History.Get_NewestFrameTime().Get_Seconds();

        FCk_LagComp_RewindHit PresentHit;
        auto PresentHitFound = _History.Sweep_AgainstHistory(
            SegmentStart, SegmentEnd,
            FCk_Time(NowTime - 0.02), FCk_Time(NowTime), 5.0, PresentHit);

        Assert_True(!PresentHitFound, "Sweep through A at the present time should miss — target is at B");

        // ---- Sweep through B at the present time: hit ----
        FCk_LagComp_RewindHit PresentHitAtB;
        auto PresentHitAtBFound = _History.Sweep_AgainstHistory(
            _PoseB + FVector(-200.0, 0.0, 0.0), _PoseB + FVector(200.0, 0.0, 0.0),
            FCk_Time(NowTime - 0.02), FCk_Time(NowTime), 5.0, PresentHitAtB);

        Assert_True(PresentHitAtBFound, "Sweep through B at the present time should hit");

        FinishSuccess();
    }
}
