// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_FaceFootWeighsNothing : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Fixture;
    private FCk_Handle_ProceduralGait _Gait;
    private TArray<FCk_Handle_ProceduralLeg> _Legs;
    private FVector _Origin = FVector(120000.0, 327500.0, 600.0);
    // The walker stands on a table 200 cm above the floor; the eight-leg rig's rest feet stand 65 cm below its body, on the
    // table, 100 cm out from its centre. Along the face leg's radial (U; V across it) the table stops 40 cm out, and a slot
    // 100 cm wide runs out from there between two side tables that carry the neighbouring legs. At setup the face leg stands
    // on a step level with the table, 80 to 160 cm out.
    private float _TableTop = 200.0;
    private float _BodyHeight = 265.0;
    private int32 _FaceLeg = 0;
    // Once the gait stands, a wall rising 300 cm above the table is set down over that step, its inner face 20 cm inside the
    // rest foot. The ideal probe leans in toward the body at its top and out at its bottom, so it crosses that face about
    // 57 cm above the table: the leg's target becomes the face, a trusted Ideal target the hip sees, and the plant the wall
    // now hides from the hip steps onto it. Nothing else lies in reach to compete with the face: the slot drops 200 cm and
    // the wall's top lies out of reach. A setup plant would not do: the gait seeds its plants level.
    private float _FaceRadius = 80.0;
    private float _TableEdge = 40.0;
    private float _SlotHalfWidth = 50.0;
    private float _WallDepth = 80.0;
    private float _WallRise = 300.0;
    private float _TableHalfSpan = 160.0;
    private float _SideTableEnd = 170.0;
    private float _MinFaceFootHeight = 10.0;
    private float _MaxFaceNormalZ = 0.1;
    private float _FloorFootTolerance = 1.0;
    private float _Tolerance = 0.5;
    private float _WatchSeconds = 0.5;
    private float _WatchStartTime = -1.0;
    private int32 _WatchedFrames = 0;
    private float _WorstDeviation = 0.0;
    private int32 _FittedFrames = 0;

    FVector Get_FaceRadial() const
    {
        return ck_procedural_gym_assets::Get_RadialDirection(_FaceLeg, 8);
    }

    // A box spanning InMinU to InMaxU along the face leg's radial and InMinV to InMaxV across it, from the floor up to InTopZ.
    void DoAdd_Box(float InMinU, float InMaxU, float InMinV, float InMaxV, float InTopZ)
    {
        auto Radial = Get_FaceRadial();
        auto Across = FVector(-Radial.Y, Radial.X, 0.0);
        auto Centre = Radial * ((InMinU + InMaxU) * 0.5) + Across * ((InMinV + InMaxV) * 0.5) + FVector(0.0, 0.0, InTopZ * 0.5);
        auto HalfExtents = FVector((InMaxU - InMinU) * 0.5, (InMaxV - InMinV) * 0.5, InTopZ * 0.5);
        auto Yaw = Math::RadiansToDegrees(Math::Atan2(Radial.Y, Radial.X));
        _Fixture.AddSurface(Centre, FRotator(0.0, Yaw, 0.0), HalfExtents, FLinearColor(0.18, 0.25, 0.31, 1.0));
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        if (_Fixture.Create(InHandle, _Origin, ECkProceduralAnimationGym_Course::Flat, false, 1) == false)
        {
            FinishFailure("The flat floor fixture could not be created");
            return;
        }
        // Do not call fixture.Update: only its Jolt floor and the tables are needed, and no crawler may spawn.
        DoAdd_Box(-_TableHalfSpan, _TableEdge, -_TableHalfSpan, _TableHalfSpan, _TableTop);
        DoAdd_Box(_TableEdge, _SideTableEnd, _SlotHalfWidth, _TableHalfSpan, _TableTop);
        DoAdd_Box(_TableEdge, _SideTableEnd, -_TableHalfSpan, -_SlotHalfWidth, _TableTop);
        DoAdd_Box(_FaceRadius, _FaceRadius + _WallDepth, -_SlotHalfWidth, _SlotHalfWidth, _TableTop);
        Add_Step_WaitUntil("the floor and the tables are queryable", n"Check_SurfacesReady");
        Add_Step("compose a gait-only eight-leg walker on the table", n"Step_ComposeGait");
        Add_Step_WaitUntil("the gait is ready", n"Check_GaitReady");
        Add_Step("set the wall down over the face leg's foot", n"Step_AddWall");
        Add_Step_WaitUntil("the face leg steps onto the wall's face", n"Check_OnTheFace", 0, 4.0f);
        Add_Step("verify one foot stands on the wall's face and the rest on the table", n"Step_CheckFeet");
        Add_Step_WaitUntil("the feet plane is watched for half a second", n"Check_Watched", 0, 3.0f);
        Add_Step("verify the plane stayed on the table", n"Step_Verify");
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
        auto Body = utils_transform::Add(Root, FTransform(_Origin + FVector(0.0, 0.0, _BodyHeight)), ECk_Replication::DoesNotReplicate);

        auto Walker = utils_procedural_animation::Add_Walker(Body, ck::ProceduralGym_Rig8, ck::ProceduralGym_Gait,
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
    private void Step_AddWall(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoAdd_Box(_FaceRadius, _FaceRadius + _WallDepth, -_SlotHalfWidth, _SlotHalfWidth, _TableTop + _WallRise);
    }

    UFUNCTION()
    private void Check_OnTheFace(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Foot = utils_procedural_leg::Get_Foot(_Legs[_FaceLeg]);
        auto NormalZ = Foot.Get_Normal().Z;
        auto Result = OutResult;
        Result.Set(_Fixture.Get_AreSurfacesReady() && Foot.Get_Phase() == ECk_ProceduralLeg_FootPhase::Planted
            && Math::Abs(NormalZ) <= _MaxFaceNormalZ);
    }

    UFUNCTION()
    private void Step_CheckFeet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        for (auto Index = 0; Index < _Legs.Num(); Index++)
        {
            auto Foot = utils_procedural_leg::Get_Foot(_Legs[Index]);
            auto Local = Foot.Get_Position() - _Origin - FVector(0.0, 0.0, _TableTop);
            auto Planted = Foot.Get_Phase() == ECk_ProceduralLeg_FootPhase::Planted
                && Foot.Get_Contact() == ECk_ProceduralLeg_FootContact::Trusted;
            if (Index == _FaceLeg)
            {
                auto NormalZ = Foot.Get_Normal().Z;
                Assert_True(Planted && Local.Z >= _MinFaceFootHeight && Math::Abs(NormalZ) <= _MaxFaceNormalZ,
                    f"Precondition: leg {Index} stands trusted on the wall's face (at {Local.X :.1}, {Local.Y :.1}, {Local.Z :.1} over the table, normal z {NormalZ :.2})");
            }
            else
            {
                Assert_True(Planted && Math::Abs(Local.Z) <= _FloorFootTolerance,
                    f"Precondition: leg {Index} stands trusted on the table (at height {Local.Z :.1} over it)");
            }
        }
        _WatchStartTime = float(System::GetGameTimeInSeconds());
    }

    UFUNCTION()
    private void Check_Watched(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Plane = utils_procedural_gait::Get_FeetPlane(_Gait);
        _WatchedFrames++;
        if (Plane.Get_State() == ECk_ProceduralGait_FeetPlane::Fitted)
        {
            _FittedFrames++;
        }
        _WorstDeviation = Math::Max(_WorstDeviation, Math::Abs(Plane.Get_Point().Z - _Origin.Z - _TableTop));

        auto Result = OutResult;
        Result.Set(float(System::GetGameTimeInSeconds()) - _WatchStartTime >= _WatchSeconds);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        ck::Trace(f"[FACE-FOOT] plane fitted on {_FittedFrames} of {_WatchedFrames} frames; worst plane height above the table at the body {_WorstDeviation :.3} cm");
        Assert_True(_WatchedFrames > 0 && _FittedFrames == _WatchedFrames,
            f"The feet plane is fitted on every watched frame ({_FittedFrames} of {_WatchedFrames})");
        Assert_True(_WorstDeviation <= _Tolerance,
            f"A foot on a vertical face weighs nothing: the plane's height at the body is the table's within {_Tolerance :.1} cm (worst {_WorstDeviation :.3} cm)");
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
