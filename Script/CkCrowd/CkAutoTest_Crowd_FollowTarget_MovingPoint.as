// Language=angelscript

//============================================================================
// CK CROWD - AUTOMATION TEST: FOLLOW TARGET (moving point)
//============================================================================
//
// Pins the FCk_Request_CrowdAgent_FollowTarget contract: the goal is a LIVE
// transform handle, not a position snapshot.
//
//   1. CHASE. An agent follows a target point that GLIDES away along a path
//      (a manual tween, driven by the sample timer). The agent must converge
//      on the target's FINAL position - a snapshot MoveTo would park at the
//      START position, which ends up several hundred cm away.
//   2. RE-ENGAGE. Once the agent has arrived and gone Idle, the target jumps
//      to a fresh spot. The follow must WAKE the idle agent and converge
//      again - arrival is not terminal while the follow stands.
//
// REQUIREMENT: navmesh from (-500, -500) to (500, 500) on the AutoTests map
// (same fixture as the Pathfinding tests). All coordinates stay within it.
//============================================================================

class UCk_AutoTest_Crowd_FollowTarget_MovingPoint : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 30.0f;

    private FCk_Handle_CrowdAgent   _Agent;
    private FCk_Handle_Transform    _TargetPoint;

    private float _ElapsedSec = 0.0;
    private bool  _PhaseChaseDone   = false;
    private bool  _TargetJumped     = false;

    private const FVector AgentSpawn   = FVector(-400.0, 0.0, 0.0);
    private const FVector TargetStart  = FVector(300.0, 0.0, 0.0);
    private const FVector TargetEnd    = FVector(300.0, 400.0, 0.0);   // glide destination (phase 1)
    private const FVector TargetJumpTo = FVector(-200.0, 400.0, 0.0);  // re-engage spot (phase 2)

    private const float SampleIntervalSec = 0.05;

    // Phase 1: the target glides Start->End over GlideSeconds (~80cm/s - slower
    // than the agent, so the chase can converge).
    private const float GlideStartSec = 1.0;
    private const float GlideSeconds  = 5.0;

    private const float ChaseDeadlineSec  = 14.0;
    private const float ResumeDeadlineSec = 26.0;

    // Converged = within the follow's arrival radius + coast/separation slack.
    private const float ArrivalRadiusCm = 60.0;
    private const float ConvergeSlackCm = 90.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        // This entity IS the chasing agent - spawned facing its target.
        LocalHandle.Set_DebugName(n"FollowTarget_Chaser");
        auto AgentTransform = utils_transform::Add(LocalHandle,
            FTransform((TargetStart - AgentSpawn).Rotation(), AgentSpawn, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        // The moving TARGET POINT - a bare transform entity the sample timer glides.
        auto TargetEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        _TargetPoint = utils_transform::Add(TargetEntity,
            FTransform(FRotator::ZeroRotator, TargetStart, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);
        _Agent = utils_crowd_agent::Add(AgentTransform, Params);
        utils_velocity::Add(LocalHandle,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(LocalHandle,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(LocalHandle);

        // ONE follow request for the whole test - everything after this is the
        // follow keeping itself alive.
        auto Follow = FCk_Request_CrowdAgent_FollowTarget(_TargetPoint);
        Follow.Set_ArrivalRadiusOverrideMode(ECk_Override::Override);
        Follow.Set_ArrivalRadiusOverrideValue(ArrivalRadiusCm);
        utils_crowd_agent::Request_FollowTarget(_Agent, Follow);

        auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(SampleIntervalSec));
        TimerParams.Set_StartingState(ECk_Timer_State::Running)
                   .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto Timer = utils_timer::Add(LocalHandle, TimerParams);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnSample"));
    }

    UFUNCTION()
    private void OnSample(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _ElapsedSec += SampleIntervalSec;

        if (ck::Is_NOT_Valid(_Agent) || ck::Is_NOT_Valid(_TargetPoint))
        {
            FinishFailure("agent or target went invalid mid-run");
            return;
        }

        // ---- Drive the target: glide Start -> End (the manual tween). ----
        if (_ElapsedSec >= GlideStartSec && _ElapsedSec < GlideStartSec + GlideSeconds)
        {
            const auto Alpha = Math::Clamp((_ElapsedSec - GlideStartSec) / GlideSeconds, 0.0f, 1.0f);
            const auto GlideLoc = Math::Lerp(TargetStart, TargetEnd, Alpha);
            utils_transform::Request_SetLocation(_TargetPoint, FCk_Request_Transform_SetLocation(GlideLoc));
        }

        const auto AgentLoc  = utils_transform::Get_EntityCurrentLocation(
            utils_transform::DoCastChecked(FCk_Handle(_Agent)));
        const auto TargetLoc = utils_transform::Get_EntityCurrentLocation(_TargetPoint);

        // ---- Phase 1: converge on the GLIDED position. ----
        if (_PhaseChaseDone == false)
        {
            const auto Converged = _ElapsedSec > GlideStartSec + GlideSeconds
                && float((AgentLoc - TargetLoc).Size()) <= ArrivalRadiusCm + ConvergeSlackCm;
            if (Converged)
            {
                // The clincher: the glided end is ~400cm from the start snapshot. An
                // agent parked at the snapshot cannot be near the target now.
                Assert_True(float((AgentLoc - TargetStart).Size()) > ArrivalRadiusCm + ConvergeSlackCm,
                    "agent converged AT the original snapshot - the target glided away, so the follow never re-pathed");

                _PhaseChaseDone = true;
                return;
            }
            if (_ElapsedSec >= ChaseDeadlineSec)
            {
                FinishFailure(f"CHASE: agent never converged on the moving target - still {float((AgentLoc - TargetLoc).Size())}cm away at t={_ElapsedSec} (a snapshot MoveTo parks at the target's START and never follows)");
                return;
            }
            return;
        }

        // ---- Phase 2: jump the target; the idle-arrived agent must re-engage. ----
        if (_TargetJumped == false)
        {
            _TargetJumped = true;
            utils_transform::Request_SetLocation(_TargetPoint, FCk_Request_Transform_SetLocation(TargetJumpTo));
            ck::crowd::Log(f"[FOLLOW] target jumped to {TargetJumpTo} at t={_ElapsedSec} - the arrived agent must wake and re-converge");
            return;
        }

        if (float((AgentLoc - TargetJumpTo).Size()) <= ArrivalRadiusCm + ConvergeSlackCm)
        {
            FinishSuccess();
            return;
        }

        if (_ElapsedSec >= ResumeDeadlineSec)
        {
            FinishFailure(f"RE-ENGAGE: the target jumped away after the agent arrived, but the agent never followed - still {float((AgentLoc - TargetJumpTo).Size())}cm away at t={_ElapsedSec}. Arrival must not be terminal while the follow stands.");
            return;
        }
    }
}

class ACk_AutoTest_Crowd_FollowTarget_MovingPoint_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_FollowTarget_MovingPoint;
    default _TimeoutSeconds = 30.0f;
}
