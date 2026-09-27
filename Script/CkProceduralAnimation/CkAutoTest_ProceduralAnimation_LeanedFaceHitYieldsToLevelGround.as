// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_LeanedFaceHitYieldsToLevelGround : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Fixture;
    private FVector _Origin = FVector(120000.0, 337500.0, 600.0);
    // Two gait-only side walkers, one per scene along X. Each +Y leg (hip 30 cm out, rest foot 100 cm out and 65 cm down,
    // a 140 cm chain) has its rest foot 3 cm short of a pillar's face; the pillar rises out of reach. The ideal probe leans in
    // toward the body at its top and out at its bottom: it passes the rest foot and meets that face 8.6 cm below it. In the
    // first scene a slab 20 cm under the rest foot runs up to the face, so a straight ray under the ideal finds level ground
    // 110 cm from the hip; in the second the floor lies 170 cm down, out of reach. The feet are checked where they stand and
    // by their foothold source: the gait seeds its setup plants level, so a planted foot's published normal is up either way.
    private float _BodyHeight = 235.0;
    private float _FaceY = 103.0;
    private float _PillarDepthY = 100.0;
    private float _PillarTopZ = 500.0;
    private float _PillarHalfLength = 60.0;
    private float _SlabDrop = 20.0;
    private float _SlabNearY = 20.0;
    private float _FloorSceneX = -200.0;
    private float _GapSceneX = 200.0;
    private float _Tolerance = 1.0;
    // Where the leaned attempt meets the face: 3 cm past the rest foot at 0.35 cm out per cm down.
    private float _FaceHitDrop = 8.6;
    private FCk_Handle_ProceduralGait _FloorGait;
    private FCk_Handle_ProceduralGait _GapGait;
    private FCk_Handle_ProceduralLeg _FloorLeg;
    private FCk_Handle_ProceduralLeg _GapLeg;
    private float _WatchSeconds = 0.3;
    private float _WatchStartTime = -1.0;
    private int32 _WatchedFrames = 0;
    private int32 _FloorViolations = 0;
    private int32 _GapViolations = 0;
    private FString _FirstFloorViolation;
    private FString _FirstGapViolation;

    float Get_RestFootZ() const
    {
        return _BodyHeight - ck_procedural_gym_assets::RestDrop;
    }

    void DoAdd_Scene(float InSceneX, bool InSlab)
    {
        auto Color = FLinearColor(0.18, 0.25, 0.31, 1.0);
        auto PillarHalf = FVector(_PillarHalfLength, _PillarDepthY * 0.5, _PillarTopZ * 0.5);
        _Fixture.AddSurface(FVector(InSceneX, _FaceY + PillarHalf.Y, PillarHalf.Z), FRotator::ZeroRotator, PillarHalf, Color);
        if (InSlab)
        {
            auto SlabTopZ = Get_RestFootZ() - _SlabDrop;
            auto SlabHalf = FVector(_PillarHalfLength, (_FaceY - _SlabNearY) * 0.5, SlabTopZ * 0.5);
            _Fixture.AddSurface(FVector(InSceneX, _SlabNearY + SlabHalf.Y, SlabHalf.Z), FRotator::ZeroRotator, SlabHalf, Color);
        }
        // The -Y leg stands on a platform at its rest foot's height.
        auto PlatformHalf = FVector(_PillarHalfLength, 50.0, Get_RestFootZ() * 0.5);
        _Fixture.AddSurface(FVector(InSceneX, -ck_procedural_gym_assets::SideRestOffset, PlatformHalf.Z), FRotator::ZeroRotator,
            PlatformHalf, Color);
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        if (_Fixture.Create(InHandle, _Origin, ECkProceduralAnimationGym_Course::Flat, false, 1) == false)
        {
            FinishFailure("The pillar fixture could not be created");
            return;
        }
        // Do not call fixture.Update: only its Jolt floor and the blocks are needed, and no crawler may spawn.
        DoAdd_Scene(_FloorSceneX, true);
        DoAdd_Scene(_GapSceneX, false);
        Add_Step_WaitUntil("the floor and the blocks are queryable", n"Check_SurfacesReady");
        Add_Step("compose a gait-only side walker in each scene", n"Step_ComposeGaits");
        Add_Step_WaitUntil("both gaits are ready", n"Check_GaitsReady");
        Add_Step("start watching the +Y legs' feet", n"Step_StartWatch");
        Add_Step_WaitUntil("the +Y legs are watched", n"Check_Watched", 0, 3.0f);
        Add_Step("verify the leaned face hit yields to level ground under the ideal and stands over a gap", n"Step_Verify");
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
        auto Floor = DoCompose_Walker(_FloorSceneX);
        auto Gap = DoCompose_Walker(_GapSceneX);
        _FloorGait = Floor.Get_Gait();
        _GapGait = Gap.Get_Gait();
        _FloorLeg = Get_PlusLeg(Floor);
        _GapLeg = Get_PlusLeg(Gap);
        Assert_True(ck::IsValid(_FloorGait) && ck::IsValid(_GapGait) && ck::IsValid(_FloorLeg) && ck::IsValid(_GapLeg),
            "Both gait-only side walkers are admitted with a +Y leg");
    }

    UFUNCTION()
    private void Check_GaitsReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(utils_procedural_gait::Get_Status(_FloorGait) == ECk_ProceduralAnimation_Status::Ready
            && utils_procedural_gait::Get_Status(_GapGait) == ECk_ProceduralAnimation_Status::Ready);
    }

    UFUNCTION()
    private void Step_StartWatch(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _WatchStartTime = float(System::GetGameTimeInSeconds());
    }

    FString Get_FootText(FCk_ProceduralLeg_Foot InFoot, FVector InLocal) const
    {
        auto SourceValue = int32(InFoot.Get_Foothold());
        auto Normal = InFoot.Get_Normal();
        return f"frame {_WatchedFrames}: foot ({InLocal.X :.1}, {InLocal.Y :.1}, {InLocal.Z :.1}), normal ({Normal.X :.2}, {Normal.Y :.2}, {Normal.Z :.2}), source {SourceValue}";
    }

    UFUNCTION()
    private void Check_Watched(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _WatchedFrames++;
        auto FloorFoot = utils_procedural_leg::Get_Foot(_FloorLeg);
        auto FloorLocal = FloorFoot.Get_Position() - _Origin - FVector(_FloorSceneX, 0.0, 0.0);
        auto OnTheSlab = Math::Abs(FloorLocal.Z - (Get_RestFootZ() - _SlabDrop)) <= _Tolerance
            && Math::Abs(FloorLocal.Y - ck_procedural_gym_assets::SideRestOffset) <= _Tolerance;
        if (OnTheSlab == false || FloorFoot.Get_Foothold() != ECk_ProceduralLeg_Foothold::Ideal)
        {
            _FloorViolations++;
            if (_FirstFloorViolation.IsEmpty())
            {
                _FirstFloorViolation = Get_FootText(FloorFoot, FloorLocal);
            }
        }

        auto GapFoot = utils_procedural_leg::Get_Foot(_GapLeg);
        auto GapLocal = GapFoot.Get_Position() - _Origin - FVector(_GapSceneX, 0.0, 0.0);
        auto OnTheFace = Math::Abs(GapLocal.Y - _FaceY) <= _Tolerance
            && Math::Abs(GapLocal.Z - (Get_RestFootZ() - _FaceHitDrop)) <= _Tolerance;
        if (OnTheFace == false || GapFoot.Get_Foothold() != ECk_ProceduralLeg_Foothold::Ideal)
        {
            _GapViolations++;
            if (_FirstGapViolation.IsEmpty())
            {
                _FirstGapViolation = Get_FootText(GapFoot, GapLocal);
            }
        }

        auto Result = OutResult;
        Result.Set(float(System::GetGameTimeInSeconds()) - _WatchStartTime >= _WatchSeconds);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_WatchedFrames > 0, "Precondition: the +Y legs were watched");
        Assert_True(_FloorViolations == 0,
            f"A leaned face hit yields to the level ground a straight ray finds under the ideal: the foot stands on it, source Ideal ({_FloorViolations} of {_WatchedFrames} frames otherwise; first: {_FirstFloorViolation})");
        Assert_True(_GapViolations == 0,
            f"Control: over a gap the face stands as the ideal ({_GapViolations} of {_WatchedFrames} frames otherwise; first: {_FirstGapViolation})");
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
