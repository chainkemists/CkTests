// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_FaceIdealYieldsToATopInReach : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Fixture;
    private FVector _Origin = FVector(120000.0, 332500.0, 600.0);
    // Two gait-only side walkers, one per scene along X. Each +Y leg (hip 30 cm out, rest foot 100 cm out and 65 cm down,
    // a 140 cm chain) has its rest foot 3 cm short of a block's near face, level with the block's top in the first scene.
    // The ideal probe leans in toward the body at its top and out at its bottom: it passes the rest foot and meets that face
    // 8.6 cm below the top, a usable face 104 cm from the hip. In the first scene the top lies within half the leg's reach
    // of the ideal; in the second the block rises 200 cm higher, and no top is in reach.
    private float _BodyHeight = 235.0;
    private float _FaceY = 103.0;
    private float _BlockDepthY = 100.0;
    private float _TopRise = 200.0;
    private float _SceneHalfLength = 50.0;
    private float _TopSceneX = -200.0;
    private float _WallSceneX = 200.0;
    private float _Tolerance = 1.0;
    private FCk_Handle_ProceduralGait _TopGait;
    private FCk_Handle_ProceduralGait _WallGait;
    private FCk_Handle_ProceduralLeg _TopLeg;
    private FCk_Handle_ProceduralLeg _WallLeg;
    private float _WatchSeconds = 0.3;
    private float _WatchStartTime = -1.0;
    private int32 _WatchedFrames = 0;
    private int32 _TopViolations = 0;
    private int32 _WallViolations = 0;
    private FString _FirstTopViolation;
    private FString _FirstWallViolation;

    float Get_RestFootZ() const
    {
        return _BodyHeight - ck_procedural_gym_assets::RestDrop;
    }

    void DoAdd_Scene(float InSceneX, float InBlockTopZ)
    {
        auto Color = FLinearColor(0.18, 0.25, 0.31, 1.0);
        auto BlockHalf = FVector(_SceneHalfLength, _BlockDepthY * 0.5, InBlockTopZ * 0.5);
        _Fixture.AddSurface(FVector(InSceneX, _FaceY + BlockHalf.Y, BlockHalf.Z), FRotator::ZeroRotator, BlockHalf, Color);
        // The -Y leg stands on a platform at its rest foot's height.
        auto PlatformHalf = FVector(_SceneHalfLength, 50.0, Get_RestFootZ() * 0.5);
        _Fixture.AddSurface(FVector(InSceneX, -ck_procedural_gym_assets::SideRestOffset, PlatformHalf.Z), FRotator::ZeroRotator,
            PlatformHalf, Color);
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        if (_Fixture.Create(InHandle, _Origin, ECkProceduralAnimationGym_Course::Flat, false, 1) == false)
        {
            FinishFailure("The block fixture could not be created");
            return;
        }
        // Do not call fixture.Update: only its Jolt floor and the blocks are needed, and no crawler may spawn.
        DoAdd_Scene(_TopSceneX, Get_RestFootZ());
        DoAdd_Scene(_WallSceneX, Get_RestFootZ() + _TopRise);
        Add_Step_WaitUntil("the floor and the blocks are queryable", n"Check_SurfacesReady");
        Add_Step("compose a gait-only side walker in each scene", n"Step_ComposeGaits");
        Add_Step_WaitUntil("both gaits are ready", n"Check_GaitsReady");
        Add_Step("start watching the +Y legs' feet", n"Step_StartWatch");
        Add_Step_WaitUntil("the +Y legs are watched", n"Check_Watched", 0, 3.0f);
        Add_Step("verify the face ideal yields to the top in reach and holds where no top is", n"Step_Verify");
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
        auto Top = DoCompose_Walker(_TopSceneX);
        auto Wall = DoCompose_Walker(_WallSceneX);
        _TopGait = Top.Get_Gait();
        _WallGait = Wall.Get_Gait();
        _TopLeg = Get_PlusLeg(Top);
        _WallLeg = Get_PlusLeg(Wall);
        Assert_True(ck::IsValid(_TopGait) && ck::IsValid(_WallGait) && ck::IsValid(_TopLeg) && ck::IsValid(_WallLeg),
            "Both gait-only side walkers are admitted with a +Y leg");
    }

    UFUNCTION()
    private void Check_GaitsReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(utils_procedural_gait::Get_Status(_TopGait) == ECk_ProceduralAnimation_Status::Ready
            && utils_procedural_gait::Get_Status(_WallGait) == ECk_ProceduralAnimation_Status::Ready);
    }

    UFUNCTION()
    private void Step_StartWatch(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _WatchStartTime = float(System::GetGameTimeInSeconds());
    }

    FString Get_FootText(FVector InLocal, ECk_ProceduralLeg_Foothold InSource) const
    {
        auto SourceValue = int32(InSource);
        return f"frame {_WatchedFrames}: foot ({InLocal.X :.1}, {InLocal.Y :.1}, {InLocal.Z :.1}), source {SourceValue}";
    }

    UFUNCTION()
    private void Check_Watched(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _WatchedFrames++;
        auto TopFoot = utils_procedural_leg::Get_Foot(_TopLeg);
        auto TopLocal = TopFoot.Get_Position() - _Origin - FVector(_TopSceneX, 0.0, 0.0);
        auto OnTheTop = Math::Abs(TopLocal.Z - Get_RestFootZ()) <= _Tolerance && TopLocal.Y >= _FaceY + _Tolerance;
        if (OnTheTop == false || TopFoot.Get_Foothold() == ECk_ProceduralLeg_Foothold::Ideal)
        {
            _TopViolations++;
            if (_FirstTopViolation.IsEmpty())
            {
                _FirstTopViolation = Get_FootText(TopLocal, TopFoot.Get_Foothold());
            }
        }

        auto WallFoot = utils_procedural_leg::Get_Foot(_WallLeg);
        auto WallLocal = WallFoot.Get_Position() - _Origin - FVector(_WallSceneX, 0.0, 0.0);
        auto OnTheFace = Math::Abs(WallLocal.Y - _FaceY) <= _Tolerance && WallLocal.Z < Get_RestFootZ() + _TopRise;
        if (OnTheFace == false || WallFoot.Get_Foothold() != ECk_ProceduralLeg_Foothold::Ideal)
        {
            _WallViolations++;
            if (_FirstWallViolation.IsEmpty())
            {
                _FirstWallViolation = Get_FootText(WallLocal, WallFoot.Get_Foothold());
            }
        }

        auto Result = OutResult;
        Result.Set(float(System::GetGameTimeInSeconds()) - _WatchStartTime >= _WatchSeconds);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_WatchedFrames > 0, "Precondition: the +Y legs were watched");
        Assert_True(_TopViolations == 0,
            f"A face ideal yields to a top within half the reach: the foot stands on the top, not on the ideal ({_TopViolations} of {_WatchedFrames} frames otherwise; first: {_FirstTopViolation})");
        Assert_True(_WallViolations == 0,
            f"Control: with no top in reach the foot stands on the face ideal ({_WallViolations} of {_WatchedFrames} frames otherwise; first: {_FirstWallViolation})");
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
