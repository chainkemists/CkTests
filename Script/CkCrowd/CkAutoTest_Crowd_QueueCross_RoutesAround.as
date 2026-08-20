// Language=angelscript
//============================================================================
// CK CROWD — AUTOMATION TEST: A CLOSE GOAL PAST A STANDING LINE ROUTES AROUND
//
// Two-phase planning (_PlanAroundStandingCrowds) against the field symptom:
// "the NPC's goal is VERY close on the other side of a queue; instead of
// pathing around, it tries to go through, jitters, and never arrives." A short
// crossing beats any detour under the 64x toll, so single-phase planning
// legitimately picks 'through'; the strict phase treats the painted line as a
// wall and always detours.
//
// Shape: 6 parked agents form a line; one crosser's goal sits only 200cm past
// it, mid-line. Contract: the crosser ARRIVES, never nears contact with any
// line member, and no member is displaced.
//============================================================================

class UCk_AutoTest_Crowd_QueueCross_RoutesAround : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 30.0f;

    private const int32 LineCount = 6;
    private const float LineSpacingUu = 95.0;
    private const float CrosserApproachX = 500.0;
    private const float CrosserOvershootX = 200.0;
    private const float MaxMemberDriftUu = 15.0;
    private const float MinCrosserClearanceUu = 55.0;

    private TArray<FCk_Handle_CrowdAgent> _LineMembers;
    private TArray<FVector> _MemberSpawnLocs;
    private FCk_Handle_CrowdAgent _Crosser;
    private float _FloorZ = 0.0;
    private bool _MeshFound = false;
    private bool _LineSpawned = false;
    private bool _CrosserDispatched = false;
    private bool _CrosserReached = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, FVector(-CrosserApproachX, 0.0, 100.0), FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

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

        if (_MeshFound == false)
        {
            FVector OriginOnMesh;
            if (utils_nav::Try_ProjectOntoNavmesh(SelfHandle, FVector::ZeroVector, 100.0f, OriginOnMesh, 300.0f) == false)
            { return; }

            _MeshFound = true;
            _FloorZ = float(OriginOnMesh.Z);
            return;
        }

        if (_LineSpawned == false)
        {
            const auto SpanY = float(LineCount - 1) * LineSpacingUu;
            for (int32 i = 0; i < LineCount; ++i)
            {
                const auto SlotY = (float(i) * LineSpacingUu) - (SpanY * 0.5);
                const auto Loc = FVector(0.0, SlotY, _FloorZ + 100.0);
                _LineMembers.Add(Spawn_Agent(SelfHandle, Loc));
                _MemberSpawnLocs.Add(Loc);
            }
            _LineSpawned = true;
            return;
        }

        if (_CrosserDispatched == false)
        {
            for (auto Member : _LineMembers)
            {
                if (utils_crowd_agent::Get_IsStationaryMarkupConfirmed(Member) == false)
                { return; }
            }

            // Mid-line Y, between two members — the straight route crosses the band, never an end.
            const auto CrossY = LineSpacingUu * 0.5;
            const auto SpawnLoc = FVector(-CrosserApproachX, CrossY, _FloorZ + 100.0);
            const auto GoalLoc  = FVector(CrosserOvershootX, CrossY, _FloorZ + 100.0);
            _Crosser = Spawn_Agent(SelfHandle, SpawnLoc);

            utils_crowd_agent::BindTo_OnGoalReached(_Crosser,
                FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnCrosserReached"),
                ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
                ECk_Signal_PostFireBehavior::DoNothing);
            utils_crowd_agent::BindTo_OnGoalFailed(_Crosser,
                FCk_Delegate_CrowdAgent_OnGoalFailed(this, n"OnCrosserFailed"),
                ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
                ECk_Signal_PostFireBehavior::DoNothing);

            utils_crowd_agent_diag::Track(_Crosser, SpawnLoc, GoalLoc);
            utils_crowd_agent::Request_MoveTo(_Crosser, FCk_Request_CrowdAgent_MoveTo(GoalLoc));
            _CrosserDispatched = true;
            return;
        }

        if (_CrosserReached == false)
        { return; }

        for (int32 i = 0; i < _LineMembers.Num(); ++i)
        {
            const auto MemberLoc = utils_transform::Get_EntityCurrentLocation(
                utils_transform::DoCastChecked(FCk_Handle(_LineMembers[i])));
            auto DriftDelta = MemberLoc - _MemberSpawnLocs[i];
            DriftDelta.Z = 0.0;
            const auto Drift = float(DriftDelta.Size());
            Assert_True(Drift <= MaxMemberDriftUu,
                f"SHOVED: line member {i} drifted {Drift}uu (ceiling {MaxMemberDriftUu}). Crossing the queue must not disturb it.");
        }

        const auto Recorder = utils_crowd_agent_diag::Get_RecorderData(_Crosser);
        Assert_True(Recorder.Get_MinSepAcrossCycle() >= MinCrosserClearanceUu,
            f"PRESSED: the crosser came within {Recorder.Get_MinSepAcrossCycle()}uu of the line (need {MinCrosserClearanceUu}+). The route went through the queue, not around its end.");

        FinishSuccess();
    }

    private FCk_Handle_CrowdAgent Spawn_Agent(FCk_Handle& InOwner, FVector InLoc)
    {
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);
        auto AgentEntity = utils_entity_lifetime::Request_CreateEntity(InOwner);
        auto AgentTransform = utils_transform::Add(AgentEntity,
            FTransform(FRotator::ZeroRotator, InLoc, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        auto Agent = utils_crowd_agent::Add(AgentTransform, Params);

        utils_velocity::Add(AgentEntity, FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(AgentEntity, FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(AgentEntity);

        return Agent;
    }

    UFUNCTION()
    private void OnCrosserReached(FCk_Handle_CrowdAgent InAgent)
    {
        if (IsFinished()) { return; }
        _CrosserReached = true;
    }

    UFUNCTION()
    private void OnCrosserFailed(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalFailedInfo InInfo)
    {
        if (IsFinished()) { return; }
        FinishFailure(f"the crosser FAILED although a route around the line's end exists (reason={InInfo.Get_Reason()}, crowdFree={InInfo.Get_NoCrowdFreeRouteExisted()})");
    }
}

class ACk_AutoTest_Crowd_QueueCross_RoutesAround_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_QueueCross_RoutesAround;
    default _TimeoutSeconds = 30.0f;
}
