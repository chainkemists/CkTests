// Language=angelscript

//============================================================================
// CK BALLISTIC MOTION — AUTOMATION TEST: ARC FOLLOWS CLOSED FORM
//============================================================================
//
// Verifies the BallisticMotion feature end-to-end against the deterministic
// closed-form trajectory (no probe — pure flight):
//   1. Entity + Transform at (0,0,500); launch with velocity (900,0,700).
//   2. OnTrajectoryChanged fires with the anchored initial conditions.
//   3. Two samples ~0.7s apart: time-of-flight recovered from each sampled
//      position must advance by the same wall-clock gap — proving the motion
//      runs on the closed form anchored to world time, not per-frame
//      integration.
//   4. The arc actually arcs: X advances, Z falls below the no-gravity line.
//
// World time is never read in script: both samples lag the transform write
// by the same sub-frame amount, so the recovered time DELTA is exact.
//============================================================================

class UCk_AutoTest_BallisticMotion_ArcFollowsClosedForm : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_BallisticMotion _Motion;
    private FCk_Handle_Transform _Transform;
    private FCk_Ballistic_InitialConditions _InitialConditions;
    private FCk_Ballistic_TrajectoryParams _TrajectoryParams;
    private bool _TrajectoryObserved = false;

    private FVector _StartLocation = FVector(0.0, 0.0, 500.0);
    private FVector _LaunchVelocity = FVector(900.0, 0.0, 700.0);

    private FVector _Mark1Location;
    private float _Mark1TimeOfFlight = 0.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        auto Projectile = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _Transform = utils_transform::Add(
            Projectile, FTransform(FRotator::ZeroRotator, _StartLocation), ECk_Replication::DoesNotReplicate);

        if (ck::Is_NOT_Valid(_Transform))
        {
            FinishFailure("Failed to add Transform to projectile entity");
            return;
        }

        _TrajectoryParams = FCk_Ballistic_TrajectoryParams(FVector(0.0, 0.0, -4000.0));

        auto Params = FCk_Fragment_BallisticMotion_ParamsData(_TrajectoryParams);
        _Motion = UCk_Utils_BallisticMotion_UE::Add(Projectile, Params);

        if (ck::Is_NOT_Valid(_Motion))
        {
            FinishFailure("UCk_Utils_BallisticMotion_UE::Add should return a valid handle");
            return;
        }

        _Motion.BindTo_OnTrajectoryChanged(
            FCk_Delegate_BallisticMotion_OnTrajectoryChanged(this, n"OnTrajectoryChanged"));

        _Motion.Request_Launch(FCk_Request_BallisticMotion_Launch(_LaunchVelocity));

        ScheduleMark(0.7, n"OnMark1");
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
    private void OnTrajectoryChanged(
        FCk_Handle_BallisticMotion InHandle,
        FCk_Ballistic_InitialConditions InNewInitialConditions,
        int32 InTrajectorySegmentIndex)
    {
        if (IsFinished()) { return; }

        _TrajectoryObserved = true;
        _InitialConditions = InNewInitialConditions;

        Assert_Equals_Int(InTrajectorySegmentIndex, 0, "Launch anchors trajectory segment 0");
    }

    private float Get_RecoveredTimeOfFlight(const FVector& InSampledLocation)
    {
        auto CurrentVelocity = _Motion.Get_CurrentVelocity();
        return UCk_Utils_Ballistic_UE::Get_TimeOfFlightTo(
            _InitialConditions, _TrajectoryParams, InSampledLocation, CurrentVelocity).Get_Seconds();
    }

    UFUNCTION()
    private void OnMark1(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (!_TrajectoryObserved)
        {
            FinishFailure("OnTrajectoryChanged should have fired before the first mark");
            return;
        }

        _Mark1Location = utils_transform::Get_EntityCurrentLocation(_Transform);
        _Mark1TimeOfFlight = Get_RecoveredTimeOfFlight(_Mark1Location);

        Assert_True(_Mark1Location.X > _StartLocation.X + 100.0,
            f"Projectile should have advanced in X by mark 1 (got X={_Mark1Location.X})");

        ScheduleMark(0.7, n"OnMark2");
    }

    UFUNCTION()
    private void OnMark2(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Mark2Location = utils_transform::Get_EntityCurrentLocation(_Transform);
        auto Mark2TimeOfFlight = Get_RecoveredTimeOfFlight(Mark2Location);

        Assert_True(_Motion.Get_IsInFlight(),
            "Projectile should still be in flight at mark 2");
        Assert_Equals_Int(_Motion.Get_TrajectorySegmentIndex(), 0,
            "No impacts — still on trajectory segment 0");

        Assert_True(Mark2Location.X > _Mark1Location.X + 100.0,
            f"Projectile should keep advancing in X (mark1={_Mark1Location.X}, mark2={Mark2Location.X})");

        // The recovered flight-time delta must match the 0.7s wall-clock gap between marks.
        // Both samples lag the transform write by the same sub-frame amount, so the delta is
        // immune to that lag — generous bounds only absorb timer/frame quantization
        auto RecoveredDelta = Mark2TimeOfFlight - _Mark1TimeOfFlight;
        Assert_True(Math::Abs(RecoveredDelta - 0.7) < 0.15,
            f"Recovered time-of-flight should advance by the wall-clock gap (expected ~0.7s, got {RecoveredDelta})");

        // Gravity must have bent the arc below the no-gravity straight line
        auto StraightLineZ = _StartLocation.Z + _LaunchVelocity.Z * Mark2TimeOfFlight;
        Assert_True(Mark2Location.Z < StraightLineZ - 100.0,
            f"Arc should fall below the no-gravity line (Z={Mark2Location.Z}, line={StraightLineZ})");

        // Round-trip: the sampled position must lie on the closed-form trajectory
        auto ExpectedLocation = UCk_Utils_Ballistic_UE::Get_PositionAtTime(
            _InitialConditions, _TrajectoryParams, FCk_Time(Mark2TimeOfFlight));
        auto Deviation = (ExpectedLocation - Mark2Location).Size();
        Assert_True(Deviation < 1.0,
            f"Sampled position should lie on the closed-form trajectory (deviation={Deviation}cm)");

        FinishSuccess();
    }
}
