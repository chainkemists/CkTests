// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_FootholdLandsOnPillarTop : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 12.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Fixture;
    private FCk_Handle_ProceduralGait _Gait;
    private TArray<FCk_Handle_ProceduralLeg> _Legs;
    private FVector _Origin = FVector(120000.0, 295000.0, 600.0);
    // Two 150 cm pillars leave a gap from Y 75 to 125, where the side rig's +Y rest foot falls.
    private FVector _PillarHalfExtents = FVector(25.0, 25.0, 75.0);
    private float _NearPillarY = 50.0;
    private float _FarPillarY = 150.0;
    private float _PillarTopZ = 150.0;
    // The body rides the rest drop above the pillar tops.
    private float _BodyHeight = 215.0;
    // Well inside the 42 cm between the held pillar top and the ideal target over the gap, so the hold can only keep
    // serving because the ideal target is unusable, not because the two agree.
    private float _TightKeepRadius = 10.0;
    private float _WatchSeconds = 1.0;
    private float _StillTolerance = 0.5;
    private FCk_Handle_ProceduralLeg _PlusLeg;
    private FCk_Handle_Transform _Body;
    // Turned half round, the +Y leg's ideal target lies over the bare floor 100 cm to the other side while its hold on the
    // near pillar top stays within reach of its hip and in sight of it, 158 cm from the ideal: farther than the leg's
    // force-step reach (0.92 x 140 cm), so the hold may no longer serve.
    private float _TurnYawDegrees = 180.0;
    private ECk_ProceduralLeg_Foothold _SourceAfterTurn = ECk_ProceduralLeg_Foothold::Held;
    private int32 _TightKeepRadiusCompletions = 0;
    private float _WatchStartTime = -1.0;
    private FVector _WatchStartPosition;
    private int32 _WatchedFrames = 0;
    private int32 _Violations = 0;
    private FString _FirstViolation;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        if (_Fixture.Create(InHandle, _Origin, ECkProceduralAnimationGym_Course::Flat, false, 1) == false)
        {
            FinishFailure("The isolated pillar fixture could not be created");
            return;
        }
        // Do not call fixture.Update: only its Jolt floor and the pillars are needed, and no crawler may spawn.
        auto Color = FLinearColor(0.18, 0.25, 0.31, 1.0);
        _Fixture.AddSurface(FVector(0.0, _NearPillarY, _PillarHalfExtents.Z), FRotator::ZeroRotator, _PillarHalfExtents, Color);
        _Fixture.AddSurface(FVector(0.0, _FarPillarY, _PillarHalfExtents.Z), FRotator::ZeroRotator, _PillarHalfExtents, Color);
        Add_Step_WaitUntil("the floor and the pillars are queryable", n"Check_SurfacesReady");
        Add_Step("compose a gait-only side walker above the gap", n"Step_ComposeGait");
        Add_Step_WaitUntil("the gait publishes its initial planted feet", n"Check_GaitReady");
        Add_Step("verify the +Y foot stands on a pillar top", n"Step_CheckFeet");
        Add_Step("shrink the keep radius below the hold's distance from the ideal", n"Step_ApplyTightKeepRadius");
        Add_Step_WaitUntil("the tight keep-radius preset completes", n"Check_TightKeepRadiusApplied");
        Add_Step_WaitUntil("the +Y foot is watched for a second with the body still", n"Check_HoldServes", 600);
        Add_Step("verify the hold served on every frame", n"Step_VerifyHoldServed");
        Add_Step("turn the body half round, leaving the hold far from the +Y leg's ideal target", n"Step_TurnBody");
        Add_Step_WaitUntil("the +Y leg lets go of the hold that trails its ideal target", n"Check_HoldReleased", 120);
        Add_Step("verify the trailing hold was released", n"Step_VerifyHoldReleased");
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
        auto Owner = _Fixture.SceneRoot;
        auto Root = utils_entity_lifetime::Request_CreateEntity(Owner);
        Root.Request_OverrideToSelf();
        _Fixture.Entities.Add(Root);
        auto Body = utils_transform::Add(Root, FTransform(_Origin + FVector(0.0, 0.0, _BodyHeight)), ECk_Replication::DoesNotReplicate);
        _Body = Body;

        auto Walker = utils_procedural_animation::Add_Walker(Body, ck::ProceduralTest_SideRig, ck::ProceduralGym_Gait,
            TArray<FCk_ProceduralWalker_LegChain>());
        _Gait = Walker.Get_Gait();
        _Legs = Walker.Get_Legs();
        Assert_True(ck::IsValid(_Gait) && _Legs.Num() == 2, "A gait-only side walker is admitted");

        auto UnderRestFoot = utils_jolt_query::Get_RayCast(_Origin + FVector(0.0, 100.0, 400.0), _Origin + FVector(0.0, 100.0, -10.0),
            FCk_Jolt_QueryFilter());
        Assert_True(UnderRestFoot.Get_HasHit() && Math::Abs(UnderRestFoot.Get_Position().Z - _Origin.Z) < 1.0,
            "Precondition: the ground straight under the +Y rest foot is the floor in the gap");
    }

    UFUNCTION()
    private void Check_GaitReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(ck::IsValid(_Gait) && utils_procedural_gait::Get_Status(_Gait) == ECk_ProceduralAnimation_Status::Ready);
    }

    // A held foothold only ever comes from the search, and the gait reports it as held from its first update on.
    bool Get_IsSearchOrHeld(ECk_ProceduralLeg_Foothold InSource) const
    {
        return InSource == ECk_ProceduralLeg_Foothold::Ring || InSource == ECk_ProceduralLeg_Foothold::Inward
            || InSource == ECk_ProceduralLeg_Foothold::Outward || InSource == ECk_ProceduralLeg_Foothold::Held;
    }

    UFUNCTION()
    private void Step_CheckFeet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Body = _Origin + FVector(0.0, 0.0, _BodyHeight);
        auto CheckedPlusLeg = false;
        for (auto Leg : _Legs)
        {
            auto Hip = Body + utils_procedural_leg::Get_Placement(Leg).Get_HipLocal();
            if (Hip.Y < Body.Y)
            {
                continue;
            }
            CheckedPlusLeg = true;
            _PlusLeg = Leg;
            auto Foot = utils_procedural_leg::Get_Foot(Leg);
            auto Local = Foot.Get_Position() - _Origin;
            auto SourceValue = int32(Foot.Get_Foothold());
            Assert_True(Foot.Get_Phase() == ECk_ProceduralLeg_FootPhase::Planted && Foot.Get_Contact() == ECk_ProceduralLeg_FootContact::Trusted,
                "The +Y foot is planted on trusted ground");
            Assert_Equals_Float(Local.Z, _PillarTopZ, 1.0,
                f"The +Y foot stands on a pillar top, not in the gap (at {Local.X :.1}, {Local.Y :.1}, {Local.Z :.1})");
            Assert_True(Get_IsSearchOrHeld(Foot.Get_Foothold()), f"The +Y foot's target came from the foothold search (got {SourceValue})");
        }
        Assert_True(CheckedPlusLeg, "The side rig has a +Y leg");
    }

    UFUNCTION()
    private void Step_ApplyTightKeepRadius(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        UCk_ProceduralGait_Data Preset = ck::ProceduralGym_Gait;
        auto Foothold = Preset.Get_Foothold();
        Foothold.Set_KeepRadius(_TightKeepRadius);
        auto Gait = _Gait;
        utils_procedural_gait::Request_ApplyPreset(Gait,
            FCk_Request_ProceduralGait_ApplyPreset(Preset.Get_Timing(), Preset.Get_Step(), Preset.Get_Probe(), Foothold),
            FCk_Delegate_Request_OnCompleted(this, n"OnTightKeepRadiusApplied"));
    }

    UFUNCTION()
    private void OnTightKeepRadiusApplied(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    {
        _TightKeepRadiusCompletions++;
    }

    UFUNCTION()
    private void Check_TightKeepRadiusApplied(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_TightKeepRadiusCompletions > 0);
    }

    // The ideal target over the gap stays unusable, so the hold on the pillar top must serve on every solve and the foot
    // must not move, however far the hold lies from the ideal.
    UFUNCTION()
    private void Check_HoldServes(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Now = float(System::GetGameTimeInSeconds());
        auto Foot = utils_procedural_leg::Get_Foot(_PlusLeg);
        if (_WatchStartTime < 0.0)
        {
            _WatchStartTime = Now;
            _WatchStartPosition = Foot.Get_Position();
        }
        _WatchedFrames++;

        auto Moved = (Foot.Get_Position() - _WatchStartPosition).Size();
        auto Serves = Foot.Get_Foothold() == ECk_ProceduralLeg_Foothold::Held
            && Foot.Get_Phase() == ECk_ProceduralLeg_FootPhase::Planted
            && Moved <= _StillTolerance;
        if (Serves == false)
        {
            _Violations++;
            if (_FirstViolation.IsEmpty())
            {
                auto SourceValue = int32(Foot.Get_Foothold());
                auto Elapsed = Now - _WatchStartTime;
                _FirstViolation = f"at {Elapsed :.2} s: source {SourceValue}, moved {Moved :.2} cm";
            }
        }

        auto Result = OutResult;
        Result.Set(Now - _WatchStartTime >= _WatchSeconds);
    }

    UFUNCTION()
    private void Step_VerifyHoldServed(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_WatchedFrames > 0, "Precondition: the watch sampled the +Y foot");
        Assert_True(_Violations == 0,
            f"The hold serves and the +Y foot stays put ({_Violations} violations in {_WatchedFrames} frames; first: {_FirstViolation})");
    }

    UFUNCTION()
    private void Step_TurnBody(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Body = _Body;
        utils_transform::Request_SetTransform(Body,
            FTransform(FRotator(0.0, _TurnYawDegrees, 0.0), _Origin + FVector(0.0, 0.0, _BodyHeight)));
    }

    UFUNCTION()
    private void Check_HoldReleased(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _SourceAfterTurn = utils_procedural_leg::Get_Foot(_PlusLeg).Get_Foothold();
        auto Result = OutResult;
        Result.Set(_SourceAfterTurn != ECk_ProceduralLeg_Foothold::Held);
    }

    UFUNCTION()
    private void Step_VerifyHoldReleased(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto SourceValue = int32(_SourceAfterTurn);
        Assert_True(_SourceAfterTurn != ECk_ProceduralLeg_Foothold::Held,
            f"A hold farther than the force-step reach from an unusable ideal target is released (source {SourceValue})");
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
