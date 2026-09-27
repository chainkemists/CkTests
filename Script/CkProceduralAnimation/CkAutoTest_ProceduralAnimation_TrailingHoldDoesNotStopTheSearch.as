// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_TrailingHoldDoesNotStopTheSearch : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 15.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Fixture;
    private FVector _Origin = FVector(120000.0, 335000.0, 600.0);
    // Two gait-only side walkers, one per scene along X, on a preset whose search ring (25 cm) lies inside the keep radius
    // (45 cm, 1.5 step thresholds). Each +Y leg (hip 30 cm out, rest foot 100 cm out and 65 cm down, a 140 cm chain: target
    // reach 112 cm) has its rest foot over a 170 cm drop between narrow tops level with it; the ring reaches one top at
    // setup and the leg holds it.
    // - Behind: the held top lies 25 cm back. The body walks 27 cm forward: the hold ends behind the hip along the travel
    //   and 52 cm from the ideal, beyond the keep radius, and the ring's forward point falls on a top ahead 25 cm from the
    //   ideal.
    // - Ahead: the held top lies 25 cm forward. The body backs 32 cm (a search there finds nothing: the ring's points hang
    //   over gaps), then creeps 2 cm forward, so the gait's velocity window holds forward travel only; a top is set down
    //   between the ideal and the hold, and the body walks 5 cm forward: the hold stays ahead of the hip and 49-55 cm from
    //   the ideal, beyond the keep radius, while a search would find the new top 25 cm from the ideal, cheaper than the
    //   hold.
    // The bodies walk slowly, so the velocity lead stays short.
    private float _BodyHeight = 235.0;
    private float _TopHalfDepthY = 10.0;
    private float _BehindHoldMinX = -35.0;
    private float _BehindHoldMaxX = -15.0;
    private float _BehindAheadMinX = 35.0;
    private float _AheadHoldMinX = 15.0;
    private float _AheadHoldMaxX = 35.0;
    private float _MiddleMinX = -10.0;
    private float _MiddleMaxX = 8.0;
    private float _TopLength = 80.0;
    private float _BehindWalk = 27.0;
    private float _AheadBack = 32.0;
    private float _AheadCreep = 2.0;
    private float _AheadWalk = 5.0;
    private float _BackSeconds = 1.5;
    private float _CreepSeconds = 0.3;
    private float _WalkSeconds = 1.0;
    private float _PhaseStartTime = -1.0;
    private float _BehindSceneX = -300.0;
    private float _AheadSceneX = 300.0;
    private float _Tolerance = 1.0;
    private FCk_Handle_Transform _BehindBody;
    private FCk_Handle_Transform _AheadBody;
    private FCk_Handle_ProceduralGait _BehindGait;
    private FCk_Handle_ProceduralGait _AheadGait;
    private FCk_Handle_ProceduralLeg _BehindLeg;
    private FCk_Handle_ProceduralLeg _AheadLeg;
    private float _WatchSeconds = 1.0;
    private int32 _WatchedFrames = 0;
    private bool _BehindSearched = false;
    private bool _BehindOnTopAhead = false;
    private int32 _AheadViolations = 0;
    private FString _FirstAheadViolation;
    private FString _BehindLast;

    float Get_TopZ() const
    {
        return _BodyHeight - ck_procedural_gym_assets::RestDrop;
    }

    void DoAdd_Top(float InSceneX, float InMinX, float InMaxX)
    {
        auto Half = FVector((InMaxX - InMinX) * 0.5, _TopHalfDepthY, Get_TopZ() * 0.5);
        _Fixture.AddSurface(FVector(InSceneX + (InMinX + InMaxX) * 0.5, ck_procedural_gym_assets::SideRestOffset, Half.Z),
            FRotator::ZeroRotator, Half, FLinearColor(0.18, 0.25, 0.31, 1.0));
    }

    void DoAdd_Platform(float InSceneX)
    {
        // The -Y leg stands on a platform at its rest foot's height through every move.
        auto PlatformHalf = FVector(150.0, 50.0, Get_TopZ() * 0.5);
        _Fixture.AddSurface(FVector(InSceneX, -ck_procedural_gym_assets::SideRestOffset, PlatformHalf.Z), FRotator::ZeroRotator,
            PlatformHalf, FLinearColor(0.18, 0.25, 0.31, 1.0));
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        if (_Fixture.Create(InHandle, _Origin, ECkProceduralAnimationGym_Course::Flat, false, 1) == false)
        {
            FinishFailure("The tops fixture could not be created");
            return;
        }
        // Do not call fixture.Update: only its Jolt floor and the tops are needed, and no crawler may spawn.
        DoAdd_Top(_BehindSceneX, _BehindHoldMinX, _BehindHoldMaxX);
        DoAdd_Top(_BehindSceneX, _BehindAheadMinX, _BehindAheadMinX + _TopLength);
        DoAdd_Platform(_BehindSceneX);
        DoAdd_Top(_AheadSceneX, _AheadHoldMinX, _AheadHoldMaxX);
        DoAdd_Platform(_AheadSceneX);
        Add_Step_WaitUntil("the floor and the tops are queryable", n"Check_SurfacesReady");
        Add_Step("compose a gait-only side walker in each scene", n"Step_ComposeGaits");
        Add_Step_WaitUntil("both +Y legs hold their top", n"Check_Held", 0, 3.0f);
        Add_Step("start backing the second body away from its hold", n"Step_StartPhase");
        Add_Step_WaitUntil("the second body has backed 32 cm and crept 2 cm forward", n"Check_BackedAway", 0, 3.0f);
        Add_Step("set a top down between the second leg's ideal and its hold", n"Step_AddMiddleTop");
        Add_Step_WaitUntil("the new top is queryable", n"Check_SurfacesReady");
        Add_Step("start walking both bodies forward", n"Step_StartPhase");
        Add_Step_WaitUntil("the bodies walk and the +Y legs are watched for a second after", n"Check_Watched", 0, 4.0f);
        Add_Step("verify only the hold behind the hip gave way to a searched top", n"Step_Verify");
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

    FCk_Handle_Transform DoCompose_Body(float InSceneX)
    {
        auto Root = utils_entity_lifetime::Request_CreateEntity(_Fixture.SceneRoot);
        Root.Request_OverrideToSelf();
        _Fixture.Entities.Add(Root);
        return utils_transform::Add(Root, FTransform(_Origin + FVector(InSceneX, 0.0, _BodyHeight)), ECk_Replication::DoesNotReplicate);
    }

    FCk_ProceduralWalker DoCompose_Walker(FCk_Handle_Transform InBody)
    {
        return utils_procedural_animation::Add_Walker(InBody, ck::ProceduralTest_SideRig, ck::ProceduralTest_NarrowRingGait,
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
        _BehindBody = DoCompose_Body(_BehindSceneX);
        _AheadBody = DoCompose_Body(_AheadSceneX);
        auto Behind = DoCompose_Walker(_BehindBody);
        auto Ahead = DoCompose_Walker(_AheadBody);
        _BehindGait = Behind.Get_Gait();
        _AheadGait = Ahead.Get_Gait();
        _BehindLeg = Get_PlusLeg(Behind);
        _AheadLeg = Get_PlusLeg(Ahead);
        Assert_True(ck::IsValid(_BehindGait) && ck::IsValid(_AheadGait) && ck::IsValid(_BehindLeg) && ck::IsValid(_AheadLeg),
            "Both gait-only side walkers are admitted with a +Y leg");
    }

    bool Get_HoldsTop(FCk_Handle_ProceduralLeg InLeg, float InSceneX, float InMinX, float InMaxX) const
    {
        auto Foot = utils_procedural_leg::Get_Foot(InLeg);
        auto Local = Foot.Get_Position() - _Origin - FVector(InSceneX, 0.0, 0.0);
        return Foot.Get_Phase() == ECk_ProceduralLeg_FootPhase::Planted && Foot.Get_Foothold() == ECk_ProceduralLeg_Foothold::Held
            && Local.X >= InMinX && Local.X <= InMaxX && Math::Abs(Local.Z - Get_TopZ()) <= _Tolerance;
    }

    UFUNCTION()
    private void Check_Held(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(utils_procedural_gait::Get_Status(_BehindGait) == ECk_ProceduralAnimation_Status::Ready
            && utils_procedural_gait::Get_Status(_AheadGait) == ECk_ProceduralAnimation_Status::Ready
            && Get_HoldsTop(_BehindLeg, _BehindSceneX, _BehindHoldMinX, _BehindHoldMaxX)
            && Get_HoldsTop(_AheadLeg, _AheadSceneX, _AheadHoldMinX, _AheadHoldMaxX));
    }

    UFUNCTION()
    private void Step_StartPhase(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _PhaseStartTime = float(System::GetGameTimeInSeconds());
    }

    float Get_PhaseShare(float InSeconds) const
    {
        return Math::Clamp((float(System::GetGameTimeInSeconds()) - _PhaseStartTime) / InSeconds, 0.0, 1.0);
    }

    void DoPlace_Body(FCk_Handle_Transform InBody, float InSceneX, float InX)
    {
        utils_transform::Request_SetTransform(InBody, FTransform(_Origin + FVector(InSceneX + InX, 0.0, _BodyHeight)));
    }

    UFUNCTION()
    private void Check_BackedAway(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Elapsed = float(System::GetGameTimeInSeconds()) - _PhaseStartTime;
        auto BackShare = Math::Clamp(Elapsed / _BackSeconds, 0.0, 1.0);
        auto CreepShare = Math::Clamp((Elapsed - _BackSeconds) / _CreepSeconds, 0.0, 1.0);
        DoPlace_Body(_AheadBody, _AheadSceneX, -_AheadBack * BackShare + _AheadCreep * CreepShare);
        auto Result = OutResult;
        Result.Set(CreepShare >= 1.0);
    }

    UFUNCTION()
    private void Step_AddMiddleTop(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoAdd_Top(_AheadSceneX, _MiddleMinX, _MiddleMaxX);
    }

    bool Get_IsSearchSource(ECk_ProceduralLeg_Foothold InSource) const
    {
        return InSource == ECk_ProceduralLeg_Foothold::Ring || InSource == ECk_ProceduralLeg_Foothold::Inward
            || InSource == ECk_ProceduralLeg_Foothold::Outward || InSource == ECk_ProceduralLeg_Foothold::Front;
    }

    UFUNCTION()
    private void Check_Watched(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Share = Get_PhaseShare(_WalkSeconds);
        DoPlace_Body(_BehindBody, _BehindSceneX, _BehindWalk * Share);
        DoPlace_Body(_AheadBody, _AheadSceneX, -_AheadBack + _AheadCreep + _AheadWalk * Share);
        _WatchedFrames++;

        auto BehindFoot = utils_procedural_leg::Get_Foot(_BehindLeg);
        auto BehindLocal = BehindFoot.Get_Position() - _Origin - FVector(_BehindSceneX, 0.0, 0.0);
        _BehindSearched = _BehindSearched || Get_IsSearchSource(BehindFoot.Get_Foothold());
        _BehindOnTopAhead = BehindFoot.Get_Phase() == ECk_ProceduralLeg_FootPhase::Planted && BehindLocal.X >= _BehindAheadMinX
            && BehindLocal.X <= _BehindAheadMinX + _TopLength && Math::Abs(BehindLocal.Z - Get_TopZ()) <= _Tolerance;
        auto BehindSourceValue = int32(BehindFoot.Get_Foothold());
        _BehindLast = f"foot ({BehindLocal.X :.1}, {BehindLocal.Y :.1}, {BehindLocal.Z :.1}), source {BehindSourceValue}";

        if (Get_HoldsTop(_AheadLeg, _AheadSceneX, _AheadHoldMinX, _AheadHoldMaxX) == false)
        {
            _AheadViolations++;
            if (_FirstAheadViolation.IsEmpty())
            {
                auto AheadFoot = utils_procedural_leg::Get_Foot(_AheadLeg);
                auto AheadLocal = AheadFoot.Get_Position() - _Origin - FVector(_AheadSceneX, 0.0, 0.0);
                auto AheadSourceValue = int32(AheadFoot.Get_Foothold());
                _FirstAheadViolation = f"frame {_WatchedFrames}: foot ({AheadLocal.X :.1}, {AheadLocal.Y :.1}, {AheadLocal.Z :.1}), source {AheadSourceValue}";
            }
        }

        auto Result = OutResult;
        Result.Set(float(System::GetGameTimeInSeconds()) - _PhaseStartTime >= _WalkSeconds + _WatchSeconds);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_WatchedFrames > 0, "Precondition: the +Y legs were watched");
        Assert_True(_BehindSearched && _BehindOnTopAhead,
            f"A hold behind the hip and beyond the keep radius does not stop the search: the leg takes a searched foothold and plants on the top ahead (searched {_BehindSearched}; last {_BehindLast})");
        Assert_True(_AheadViolations == 0,
            f"Control: a hold ahead of the hip keeps serving beyond the keep radius although a search would find a cheaper top ({_AheadViolations} of {_WatchedFrames} frames otherwise; first: {_FirstAheadViolation})");
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
