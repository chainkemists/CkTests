// Language=angelscript

//============================================================================
// CK TRANSFORM INTERPOLATION - AUTOMATION TEST: LOCATION LERPS TOWARD GOAL
//============================================================================
//
// Smoke test for the TransformInterpolation feature: setting a location-
// offset goal should cause the underlying Transform to progress toward
// (start + offset) over time, then converge.
//
// Setup:
//   - Add Transform at origin.
//   - Add TransformInterpolation with Linear strategy and a short smooth time.
//   - Set a location-offset goal of (300, 0, 0).
//   - Sample location after 1 tick (must be > 0 but < goal - actively lerping).
//   - Sample location after a wait long enough to converge.
//
// Pass: intermediate sample shows progress (X > 0); final sample lands within
//   tolerance of the goal location.
// Fail: never moves, jumps to goal in one tick, or overshoots out of tolerance.
//============================================================================

class UCk_AutoTest_TransformInterpolation_LocationLerps : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private const FVector StartLocation = FVector::ZeroVector;
    private const FVector GoalOffset = FVector(300.0f, 0.0f, 0.0f);
    private const float32 IntermediateMinX = 10.0f;
    private const float32 IntermediateMaxX = 290.0f;
    private const float32 ConvergenceToleranceCm = 5.0f;
    private const float32 IntermediateSampleSeconds = 0.05f;
    private const float32 FinalSampleSeconds = 1.5f;

    private FCk_Handle_Transform _Transform;
    private FCk_Handle_TransformInterpolation _Interp;
    private float32 _Elapsed = 0.0f;
    private bool _IntermediateSampled = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto StartXf = FTransform::Identity;
        StartXf.SetLocation(StartLocation);
        _Transform = utils_transform::Add(LocalHandle, StartXf, ECk_Replication::DoesNotReplicate);

        auto Settings = FCk_Transform_Interpolation_Settings();
        Settings.Set_Strategy(ECk_Interpolation_Strategy::Linear);
        Settings.Set_SmoothLocationTime(FCk_Time(0.25f));

        _Interp = utils_transform_interpolation::Add(LocalHandle, Settings);

        utils_transform_interpolation::Request_SetInterpolationGoal_LocationOffset(_Interp, GoalOffset);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _Elapsed += float32(InDeltaT.Get_Seconds());

        if (!_IntermediateSampled && _Elapsed >= IntermediateSampleSeconds)
        {
            _IntermediateSampled = true;
            auto MidLoc = utils_transform::Get_EntityCurrentLocation(_Transform);
            Assert_True(MidLoc.X >= IntermediateMinX && MidLoc.X <= IntermediateMaxX,
                f"Intermediate sample: X should be progressing between {IntermediateMinX} and {IntermediateMaxX}; got X={MidLoc.X}");
            return;
        }

        if (_Elapsed >= FinalSampleSeconds)
        {
            auto FinalLoc = utils_transform::Get_EntityCurrentLocation(_Transform);
            auto Expected = StartLocation + GoalOffset;
            Assert_True(FinalLoc.Equals(Expected, ConvergenceToleranceCm),
                f"Final sample: location should converge to start+offset; expected {Expected}, got {FinalLoc}");
            FinishSuccess();
        }
    }
}
