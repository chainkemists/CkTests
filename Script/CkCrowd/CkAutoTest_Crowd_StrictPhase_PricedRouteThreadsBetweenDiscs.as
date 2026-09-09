// Language=angelscript
//============================================================================
// CK CROWD - AUTOMATION TEST: STRICT GROUNDNAV ROUTES THREAD A REAL CROWD GAP
//
// Two confirmed stationary pickets are 300uu apart. Their default 84uu markup
// extents leave 132uu between painted edges; the 42uu walker fits with 24uu of
// clearance per side. GroundNav must price the discs, then accept that geometric
// strict route instead of denying their whole plate.
//============================================================================

class UCk_AutoTest_Crowd_StrictPhase_PricedRouteThreadsBetweenDiscs : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 45.0f;
    default _AutoStageOriginField = false;

    private FCkAutoTest_GroundNavFixture _Field;

    private const float WalkerRadiusUu = 42.0;
    private const float PicketSeparationUu = 300.0;
    // These points all lie inside the [0, 500] tile of the origin fixture.
    private const float PicketX = 250.0;
    private const float PicketCentreY = 250.0;
    private const float StartX = 75.0;
    private const float GoalX = 425.0;

    private FCk_Handle_CrowdAgent _LowerPicket;
    private FCk_Handle_CrowdAgent _UpperPicket;
    private FCk_Handle_CrowdAgent _Walker;
    private float _FloorZ = 0.0;
    private bool _SurfaceReady = false;
    private bool _PicketsSpawned = false;
    private bool _WalkerDispatched = false;
    private bool _GoalFailed = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, FVector(StartX, PicketCentreY, 100.0), FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        if (utils_nav_surface::Get_Provider() == ECk_NavSurface_Provider::GroundNav &&
            _Field.Request_StageOriginField(InHandle) == false)
        {
            FinishFailure(_Field.Get_StagingError());
            return;
        }

        utils_nav_surface::Request_SurfaceRebuild_ForTesting();

        auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.5));
        TimerParams.Set_StartingState(ECk_Timer_State::Running)
                   .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto Timer = utils_timer::Add(LocalHandle, TimerParams);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnPoll"));
    }

    UFUNCTION()
    private void OnPoll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto SelfHandle = DoGet_ScriptEntity();

        if (_SurfaceReady == false)
        {
            const auto Projected = Do_ProjectOntoSurface(FVector::ZeroVector, FVector(100.0, 100.0, 300.0));
            if (Projected.Get_Status() != ECk_NavSurface_QueryStatus::Success)
            { return; }

            _SurfaceReady = true;
            _FloorZ = float(Projected.Get_Location().Z);
            return;
        }

        if (_PicketsSpawned == false)
        {
            const auto HalfSeparation = PicketSeparationUu * 0.5;
            _LowerPicket = Spawn_Agent(SelfHandle, FVector(PicketX, PicketCentreY - HalfSeparation, _FloorZ + 100.0));
            _UpperPicket = Spawn_Agent(SelfHandle, FVector(PicketX, PicketCentreY + HalfSeparation, _FloorZ + 100.0));
            _PicketsSpawned = true;
            return;
        }

        if (_WalkerDispatched == false)
        {
            if (utils_crowd_agent::Get_IsStationaryMarkupConfirmed(_LowerPicket) == false ||
                utils_crowd_agent::Get_IsStationaryMarkupConfirmed(_UpperPicket) == false)
            { return; }

            const auto SpawnLoc = FVector(StartX, PicketCentreY, _FloorZ + 100.0);
            const auto GoalLoc = FVector(GoalX, PicketCentreY, _FloorZ + 100.0);
            _Walker = Spawn_Agent(SelfHandle, SpawnLoc);
            utils_crowd_agent::BindTo_OnGoalReached(_Walker,
                FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnWalkerReached"),
                ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
                ECk_Signal_PostFireBehavior::DoNothing);
            utils_crowd_agent::BindTo_OnGoalFailed(_Walker,
                FCk_Delegate_CrowdAgent_OnGoalFailed(this, n"OnWalkerFailed"),
                ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
                ECk_Signal_PostFireBehavior::DoNothing);

            ck::crowd::Display(f"[STRICT-GAP] DISPATCH picketSeparation={PicketSeparationUu} rawGap=132 walkerRadius={WalkerRadiusUu}");
            utils_crowd_agent::Request_MoveTo(_Walker, FCk_Request_CrowdAgent_MoveTo(GoalLoc));
            _WalkerDispatched = true;
        }
    }

    private FCk_Handle_CrowdAgent Spawn_Agent(FCk_Handle& InOwner, FVector InLoc)
    {
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(WalkerRadiusUu, 192.0f);
        auto AgentEntity = utils_entity_lifetime::Request_CreateEntity(InOwner);
        auto AgentTransform = utils_transform::Add(AgentEntity,
            FTransform(FRotator::ZeroRotator, InLoc, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        auto Agent = utils_crowd_agent::Add(AgentTransform, Params);
        utils_velocity::Add(AgentEntity,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(AgentEntity,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(AgentEntity);
        return Agent;
    }

    private FCk_NavSurface_ProjectionResult Do_ProjectOntoSurface(FVector InPoint, FVector InSearchHalfExtents) const
    {
        auto Query = FCk_NavSurface_ProjectionQuery(InPoint);
        Query.Set_Mode(ECk_NavSurface_ProjectionMode::Closest);
        Query.Set_SearchHalfExtents(InSearchHalfExtents);
        return utils_nav_surface::Try_ProjectPoint(Query);
    }

    UFUNCTION()
    private void OnWalkerReached(FCk_Handle_CrowdAgent InAgent)
    {
        if (IsFinished()) { return; }
        Assert_True(_GoalFailed == false,
            "MESSAGE: the walker reached after a strict crowd failure was reported.");
        FinishSuccess();
    }

    UFUNCTION()
    private void OnWalkerFailed(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalFailedInfo InInfo)
    {
        if (IsFinished()) { return; }
        _GoalFailed = true;
        FinishFailure(f"the 132uu painted gap fits the 84uu walker diameter, but the strict phase failed (crowdFree={InInfo.Get_NoCrowdFreeRouteExisted()}, reason={InInfo.Get_Reason()})");
    }

    UFUNCTION(BlueprintOverride)
    void DoEndPlay(FCk_Handle InHandle)
    {
        _Field.Do_ReportCrossover("Crowd_StrictPhase_PricedRouteThreadsBetweenDiscs", IsFinished() ? "finished" : "unfinished");
        _Field.Request_ReleaseOriginField();
    }
}

class ACk_AutoTest_Crowd_StrictPhase_PricedRouteThreadsBetweenDiscs_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_StrictPhase_PricedRouteThreadsBetweenDiscs;
    default _TimeoutSeconds = 45.0f;
}
