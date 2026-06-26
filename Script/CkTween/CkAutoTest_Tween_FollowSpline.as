// Language=angelscript

//============================================================================
// CK TWEEN — AUTOMATION TEST: FOLLOW SPLINE
//============================================================================
//
// Verifies the CkSpline feature and the CkTween spline-follow tween together:
//   1. Build an FCk_Fragment_Spline_ParamsData from 3 known points via
//      utils_spline::Make_Params_FromPoints, then Create a spline entity.
//   2. Assert the pure (no-tick) query surface: length is positive, location
//      at distance 0 is the first point, location at full distance is the last.
//   3. Create a follower transform entity and a follow-spline tween (Linear
//      easing, OrientToSpline); verify the follower arrives at the spline end
//      when the tween completes.
//
// Out of scope (CkSpline / CkTween have their own coverage):
//   - Per-frame interpolation accuracy and orientation correctness
//   - PositionOnly vs OrientToSpline rotation behaviour
//   - Closed-loop splines
//============================================================================

class UCk_AutoTest_Tween_FollowSpline : UCk_AutoTest_Base
{
    private FCk_Handle_Spline _Spline;
    private FCk_Handle_Transform _Follower;
    private FVector _SplineEnd;
    private float32 _SplineLength = 0.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        // ---- Build a curved 3-point path -------------------------------------
        _SplineEnd = FVector(400.0, 400.0, 0.0);

        TArray<FVector> Points;
        Points.Add(FVector(0.0, 0.0, 0.0));
        Points.Add(FVector(400.0, 0.0, 0.0));
        Points.Add(_SplineEnd);

        auto Params = utils_spline::Make_Params_FromPoints(Points, false);

        // The spline feature lives on a transform entity; create one at the
        // origin so its local curves line up 1:1 with world space.
        auto SplineOwner = utils_transform::Create(
            LocalHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        _Spline = utils_spline::Create(SplineOwner, Params);

        Assert_True(ck::IsValid(_Spline), "Spline handle is valid after Create");

        // ---- Pure query assertions (deterministic, no ticking) ---------------
        _SplineLength = utils_spline::Get_Length(_Spline);
        Assert_True(_SplineLength > 1.0f,
            f"Spline length is positive (got {_SplineLength})");

        const auto StartOffset = (utils_spline::Get_LocationAtDistance(_Spline, 0.0f) - FVector(0.0, 0.0, 0.0)).Size();
        Assert_True(StartOffset < 1.0f,
            f"Location at distance 0 is the first point (off by {StartOffset})");

        const auto EndOffset = (utils_spline::Get_LocationAtDistance(_Spline, _SplineLength) - _SplineEnd).Size();
        Assert_True(EndOffset < 1.0f,
            f"Location at full distance is the last point (off by {EndOffset})");

        // ---- Drive a follower along the spline -------------------------------
        _Follower = utils_transform::Create(
            LocalHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto Tween = UCk_Utils_Tween_UE::Create_TweenEntityTransform_FollowSpline(
            _Follower, _Spline, 0.25f,
            ECk_Tween_SplineOrientation::OrientToSpline,
            ECk_TweenEasing::Linear,
            ECk_TweenLoopType::None, 0, 0.0f,
            ECk_TweenCompletionBehavior::DoNothing);

        Assert_True(ck::IsValid(Tween), "Follow-spline tween handle is valid");

        Tween.BindTo_OnComplete(FCk_Delegate_Tween_OnComplete(this, n"OnTweenComplete"));
    }

    UFUNCTION()
    private void OnTweenComplete(
        FCk_Handle_Tween InTween,
        FCk_Tween_Payload_OnComplete InPayload)
    {
        if (IsFinished()) { return; }

        // The completion snap enqueues a deferred transform request — wait a
        // frame for it to apply before reading the follower's location.
        WaitOneFrame(n"OnFollowerSettled");
    }

    UFUNCTION()
    private void OnFollowerSettled(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        const auto ArrivalOffset = (utils_transform::Get_EntityCurrentLocation(_Follower) - _SplineEnd).Size();
        Assert_True(ArrivalOffset < 5.0f,
            f"Follower reached the spline end on completion (off by {ArrivalOffset})");

        FinishSuccess();
    }
}
