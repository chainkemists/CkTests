// Language=angelscript

//============================================================================
// CK BALLISTIC MOTION — AUTOMATION TEST: FAST-FORWARD EQUIVALENCE
//============================================================================
//
// The core lag-compensation determinism guarantee: a projectile launched NOW
// with its trajectory anchored 0.5s in the PAST (OverrideTime) must land in
// exactly the same place as a projectile that has genuinely been flying for
// those 0.5s. No stepping, no error accumulation — both are the same closed
// form evaluated at the same world time.
//============================================================================

class UCk_AutoTest_BallisticMotion_FastForwardEquivalence : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_BallisticMotion _MotionA;
    private FCk_Handle_BallisticMotion _MotionB;
    private FCk_Handle_Transform _TransformA;
    private FCk_Handle_Transform _TransformB;

    private FVector _StartLocation = FVector(0.0, 0.0, 1000.0);
    private FVector _LaunchVelocity = FVector(1200.0, 0.0, 300.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        _MotionA = CreateProjectile(_TransformA);
        _MotionA.Request_Launch(FCk_Request_BallisticMotion_Launch(_LaunchVelocity));

        ScheduleMark(0.5, n"OnMark1");
    }

    private FCk_Handle_BallisticMotion CreateProjectile(FCk_Handle_Transform&out OutTransform)
    {
        auto Entity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        OutTransform = utils_transform::Add(
            Entity, FTransform(FRotator::ZeroRotator, _StartLocation), ECk_Replication::DoesNotReplicate);

        auto TrajectoryParams = FCk_Ballistic_TrajectoryParams(FVector(0.0, 0.0, -6000.0));
        auto Params = FCk_Fragment_BallisticMotion_ParamsData(TrajectoryParams);
        return UCk_Utils_BallisticMotion_UE::Add(Entity, Params);
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

        // Projectile A has flown for ~0.5s. Launch B NOW, anchored at A's exact launch time —
        // it must instantly catch up and shadow A perfectly from here on
        auto LaunchTimeOfA = _MotionA.Get_InitialConditions().Get_StartTime();

        _MotionB = CreateProjectile(_TransformB);

        auto LaunchRequest = FCk_Request_BallisticMotion_Launch(_LaunchVelocity);
        LaunchRequest.Set_LaunchTimePolicy(ECk_BallisticMotion_LaunchTime::OverrideTime);
        LaunchRequest.Set_OverrideStartTime(LaunchTimeOfA);
        _MotionB.Request_Launch(LaunchRequest);

        ScheduleMark(0.3, n"OnMark2");
    }

    UFUNCTION()
    private void OnMark2(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto LocationA = utils_transform::Get_EntityCurrentLocation(_TransformA);
        auto LocationB = utils_transform::Get_EntityCurrentLocation(_TransformB);

        Assert_True(LocationA.X > _StartLocation.X + 500.0,
            f"Projectile A should have travelled (got X={LocationA.X})");

        auto Deviation = (LocationA - LocationB).Size();
        Assert_True(Deviation < 1.0,
            f"Fast-forwarded projectile must coincide with the genuinely-flying one (deviation={Deviation}cm)");

        auto VelocityDeviation = (_MotionA.Get_CurrentVelocity() - _MotionB.Get_CurrentVelocity()).Size();
        Assert_True(VelocityDeviation < 1.0,
            f"Velocities must coincide too (deviation={VelocityDeviation}cm/s)");

        FinishSuccess();
    }
}
