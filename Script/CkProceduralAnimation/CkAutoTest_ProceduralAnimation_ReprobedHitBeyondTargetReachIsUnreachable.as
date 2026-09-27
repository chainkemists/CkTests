// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_ReprobedHitBeyondTargetReachIsUnreachable : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Fixture;
    private FVector _Origin = FVector(120000.0, 330000.0, 600.0);
    // Two gait-only side walkers, one per scene along X. Each +Y leg (hip 30 cm out, rest foot 100 cm out and 65 cm down,
    // a 140 cm chain: target reach 112 cm) has its rest foot over a 150 cm drop, 20 cm above the top of a slab whose edge
    // lies past it. The ideal probe leans in toward the body at its top and out at its bottom, so it passes the rest foot
    // and clips the slab's top 7 cm farther out, 114.7 cm from the hip; that hit is clamped toward the hip (keeping its
    // height) to 102.9 cm out and probed again, straight down.
    private float _BodyHeight = 235.0;
    private float _SlabTopZ = 150.0;
    private float _SlabDepthY = 100.0;
    private float _SceneHalfLength = 50.0;
    // Past the clamped point: the second probe falls past the slab's edge to the floor 150 cm down, far out of reach.
    private float _EdgeBeyondReachY = 105.0;
    // Under the clamped point: the second probe meets the top right there, at the target reach.
    private float _EdgeWithinReachY = 100.0;
    private float _BeyondSceneX = -200.0;
    private float _WithinSceneX = 200.0;
    private FCk_Handle_ProceduralGait _BeyondGait;
    private FCk_Handle_ProceduralGait _WithinGait;
    private FCk_Handle_ProceduralLeg _BeyondLeg;
    private FCk_Handle_ProceduralLeg _WithinLeg;
    private float _WatchSeconds = 0.3;
    private float _WatchStartTime = -1.0;
    private int32 _WatchedFrames = 0;
    private int32 _BeyondViolations = 0;
    private int32 _WithinViolations = 0;
    private FString _FirstBeyondViolation;
    private FString _FirstWithinViolation;

    void DoAdd_Scene(float InSceneX, float InEdgeY)
    {
        auto Color = FLinearColor(0.18, 0.25, 0.31, 1.0);
        auto SlabHalf = FVector(_SceneHalfLength, _SlabDepthY * 0.5, _SlabTopZ * 0.5);
        _Fixture.AddSurface(FVector(InSceneX, InEdgeY + SlabHalf.Y, SlabHalf.Z), FRotator::ZeroRotator, SlabHalf, Color);
        // The -Y leg stands on a platform at its rest foot's height.
        auto PlatformTopZ = _BodyHeight - ck_procedural_gym_assets::RestDrop;
        auto PlatformHalf = FVector(_SceneHalfLength, 50.0, PlatformTopZ * 0.5);
        _Fixture.AddSurface(FVector(InSceneX, -ck_procedural_gym_assets::SideRestOffset, PlatformHalf.Z), FRotator::ZeroRotator,
            PlatformHalf, Color);
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        if (_Fixture.Create(InHandle, _Origin, ECkProceduralAnimationGym_Course::Flat, false, 1) == false)
        {
            FinishFailure("The slab fixture could not be created");
            return;
        }
        // Do not call fixture.Update: only its Jolt floor and the slabs are needed, and no crawler may spawn.
        DoAdd_Scene(_BeyondSceneX, _EdgeBeyondReachY);
        DoAdd_Scene(_WithinSceneX, _EdgeWithinReachY);
        Add_Step_WaitUntil("the floor and the slabs are queryable", n"Check_SurfacesReady");
        Add_Step("compose a gait-only side walker in each scene", n"Step_ComposeGaits");
        Add_Step_WaitUntil("both gaits are ready", n"Check_GaitsReady");
        Add_Step("start watching the +Y legs' ideal verdicts", n"Step_StartWatch");
        Add_Step_WaitUntil("the +Y legs are watched", n"Check_Watched", 0, 3.0f);
        Add_Step("verify the reprobed hit beyond the target reach is Unreachable and the one within it Usable", n"Step_Verify");
        Add_Step("retire the fixture and the gaits", n"Step_Destroy");
        Add_Step_WaitUntil("entities and collision are gone", n"Check_Destroyed");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_SurfacesReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Fixture.Get_AreSurfacesReady());
    }

    FCk_ProceduralWalker DoCompose_Walker(float InSceneX)
    {
        auto Root = utils_entity_lifetime::Request_CreateEntity(_Fixture.SceneRoot);
        Root.Request_OverrideToSelf();
        _Fixture.Entities.Add(Root);
        auto Body = utils_transform::Add(Root, FTransform(_Origin + FVector(InSceneX, 0.0, _BodyHeight)),
            ECk_Replication::DoesNotReplicate);
        return utils_procedural_animation::Add_Walker(Body, ck::ProceduralTest_SideRig, ck::ProceduralGym_Gait,
            TArray<FCk_ProceduralWalker_LegChain>());
    }

    FCk_Handle_ProceduralLeg Get_PlusLeg(FCk_ProceduralWalker InWalker)
    {
        for (auto Leg : InWalker.Get_Legs())
        {
            if (utils_procedural_leg::Get_Placement(Leg).Get_HipLocal().Y > 0.0)
            {
                return Leg;
            }
        }
        return FCk_Handle_ProceduralLeg();
    }

    UFUNCTION()
    private void Step_ComposeGaits(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Beyond = DoCompose_Walker(_BeyondSceneX);
        auto Within = DoCompose_Walker(_WithinSceneX);
        _BeyondGait = Beyond.Get_Gait();
        _WithinGait = Within.Get_Gait();
        _BeyondLeg = Get_PlusLeg(Beyond);
        _WithinLeg = Get_PlusLeg(Within);
        Assert_True(ck::IsValid(_BeyondGait) && ck::IsValid(_WithinGait) && ck::IsValid(_BeyondLeg) && ck::IsValid(_WithinLeg),
            "Both gait-only side walkers are admitted with a +Y leg");
    }

    UFUNCTION()
    private void Check_GaitsReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(utils_procedural_gait::Get_Status(_BeyondGait) == ECk_ProceduralAnimation_Status::Ready
            && utils_procedural_gait::Get_Status(_WithinGait) == ECk_ProceduralAnimation_Status::Ready);
    }

    UFUNCTION()
    private void Step_StartWatch(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _WatchStartTime = float(System::GetGameTimeInSeconds());
    }

    UFUNCTION()
    private void Check_Watched(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _WatchedFrames++;
        auto BeyondVerdict = utils_procedural_leg::Get_IdealVerdict(_BeyondLeg);
        auto BeyondSource = utils_procedural_leg::Get_Foot(_BeyondLeg).Get_Foothold();
        if (BeyondVerdict != ECk_ProceduralLeg_FootholdVerdict::Unreachable || BeyondSource == ECk_ProceduralLeg_Foothold::Ideal)
        {
            _BeyondViolations++;
            if (_FirstBeyondViolation.IsEmpty())
            {
                auto VerdictValue = int32(BeyondVerdict);
                auto SourceValue = int32(BeyondSource);
                _FirstBeyondViolation = f"frame {_WatchedFrames}: verdict {VerdictValue}, source {SourceValue}";
            }
        }
        auto WithinVerdict = utils_procedural_leg::Get_IdealVerdict(_WithinLeg);
        auto WithinSource = utils_procedural_leg::Get_Foot(_WithinLeg).Get_Foothold();
        if (WithinVerdict != ECk_ProceduralLeg_FootholdVerdict::Usable || WithinSource != ECk_ProceduralLeg_Foothold::Ideal)
        {
            _WithinViolations++;
            if (_FirstWithinViolation.IsEmpty())
            {
                auto VerdictValue = int32(WithinVerdict);
                auto SourceValue = int32(WithinSource);
                _FirstWithinViolation = f"frame {_WatchedFrames}: verdict {VerdictValue}, source {SourceValue}";
            }
        }

        auto Result = OutResult;
        Result.Set(float(System::GetGameTimeInSeconds()) - _WatchStartTime >= _WatchSeconds);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_WatchedFrames > 0, "Precondition: the +Y legs were watched");
        Assert_True(_BeyondViolations == 0,
            f"A reprobed hit beyond the target reach reads Unreachable and is never the target ({_BeyondViolations} of {_WatchedFrames} frames otherwise; first: {_FirstBeyondViolation})");
        Assert_True(_WithinViolations == 0,
            f"Control: a reprobed hit at the target reach reads Usable and is the target ({_WithinViolations} of {_WatchedFrames} frames otherwise; first: {_FirstWithinViolation})");
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
