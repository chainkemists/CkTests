// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_FeetPlaneFitsGroundPointsOnly : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 12.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Fixture;
    private FCk_Handle_ProceduralGait _Gait;
    private TArray<FCk_Handle_ProceduralLeg> _Legs;
    private FCk_Handle_Transform _Body;
    private FVector _Origin = FVector(120000.0, 325000.0, 600.0);
    // The eight-leg rig's rest feet stand this far below its body, on the floor.
    private float _BodyHeight = 65.0;
    private float _DriveSpeed = 120.0;
    private float _DriveSeconds = 2.5;
    private float _Tolerance = 0.5;
    private int32 _MinSwingFrames = 30;
    private float _DriveStartTime = -1.0;
    private int32 _SwingFrames = 0;
    private int32 _PlaneFrames = 0;
    private float _WorstDeviation = 0.0;
    private FString _WorstAt;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        if (_Fixture.Create(InHandle, _Origin, ECkProceduralAnimationGym_Course::Flat, false, 1) == false)
        {
            FinishFailure("The flat floor fixture could not be created");
            return;
        }
        // Do not call fixture.Update: only its Jolt floor is needed, and no crawler may spawn.
        Add_Step_WaitUntil("the floor is queryable", n"Check_SurfacesReady");
        Add_Step("compose a gait-only eight-leg walker standing on the floor", n"Step_ComposeGait");
        Add_Step_WaitUntil("the gait is ready", n"Check_GaitReady");
        Add_Step("start driving the body along +X", n"Step_StartDrive");
        Add_Step_WaitUntil("the body is driven along the floor while the feet plane is sampled on every frame a leg swings",
            n"Check_Driven", 0, 6.0f);
        Add_Step("verify the plane stayed on the floor through every swing", n"Step_Verify");
        Add_Step("retire the fixture and the gait", n"Step_Destroy");
        Add_Step_WaitUntil("entities and collision are gone", n"Check_Destroyed");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_SurfacesReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Fixture.Get_AreSurfacesReady());
    }

    UFUNCTION()
    private void Step_ComposeGait(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Root = utils_entity_lifetime::Request_CreateEntity(_Fixture.SceneRoot);
        Root.Request_OverrideToSelf();
        _Fixture.Entities.Add(Root);
        _Body = utils_transform::Add(Root, FTransform(_Origin + FVector(0.0, 0.0, _BodyHeight)), ECk_Replication::DoesNotReplicate);

        auto Walker = utils_procedural_animation::Add_Walker(_Body, ck::ProceduralGym_Rig8, ck::ProceduralGym_Gait,
            TArray<FCk_ProceduralWalker_LegChain>());
        _Gait = Walker.Get_Gait();
        _Legs = Walker.Get_Legs();
        Assert_True(ck::IsValid(_Gait) && _Legs.Num() == 8, "A gait-only eight-leg walker is admitted");
    }

    UFUNCTION()
    private void Check_GaitReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(ck::IsValid(_Gait) && utils_procedural_gait::Get_Status(_Gait) == ECk_ProceduralAnimation_Status::Ready);
    }

    UFUNCTION()
    private void Step_StartDrive(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _DriveStartTime = float(System::GetGameTimeInSeconds());
    }

    UFUNCTION()
    private void Check_Driven(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Elapsed = float(System::GetGameTimeInSeconds()) - _DriveStartTime;
        auto Body = _Body;
        utils_transform::Request_SetTransform(Body, FTransform(_Origin + FVector(_DriveSpeed * Elapsed, 0.0, _BodyHeight)));

        auto AnySwinging = false;
        for (auto Leg : _Legs)
        {
            AnySwinging = AnySwinging || utils_procedural_leg::Get_Foot(Leg).Get_Phase() == ECk_ProceduralLeg_FootPhase::Swinging;
        }
        auto Plane = utils_procedural_gait::Get_FeetPlane(_Gait);
        if (AnySwinging && Plane.Get_State() != ECk_ProceduralGait_FeetPlane::None)
        {
            _SwingFrames++;
            auto PointHeight = Plane.Get_Point().Z - _Origin.Z;
            auto Deviation = Math::Abs(PointHeight);
            if (Deviation > _WorstDeviation)
            {
                _WorstDeviation = Deviation;
                _WorstAt = f"t {Elapsed :.2}, plane point {PointHeight :.2} cm above the floor";
            }
        }
        if (Plane.Get_State() != ECk_ProceduralGait_FeetPlane::None)
        {
            _PlaneFrames++;
        }

        auto Result = OutResult;
        Result.Set(Elapsed >= _DriveSeconds);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        ck::Trace(f"[GROUND-POINTS] {_SwingFrames} frames with a leg in flight and a plane, {_PlaneFrames} with a plane; worst deviation {_WorstDeviation :.3} cm ({_WorstAt})");
        Assert_True(_SwingFrames >= _MinSwingFrames,
            f"Precondition: the walker stepped with a feet plane published ({_SwingFrames} frames with a leg in flight)");
        Assert_True(_WorstDeviation <= _Tolerance,
            f"The feet plane stays on the floor while legs swing, within {_Tolerance :.1} cm (worst {_WorstDeviation :.3} cm: {_WorstAt})");
    }

    UFUNCTION()
    private void Step_Destroy(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Fixture.Request_Destroy();
    }

    UFUNCTION()
    private void Check_Destroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Fixture.Get_IsDestroyed());
    }
}
