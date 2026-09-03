// Language=angelscript

//============================================================================
// CK CROWD - AUTOMATION TEST: ONE PROVIDER, ONE RESULT, PER MOVE EPISODE
//============================================================================
//
// The episode invariant the GroundNav branch inherits and must not break: a
// MoveTo advances the navigation request revision, abandons whatever the
// previous provider was still holding, parks the SHARED nav slot at Pending
// carrying the NEW revision, and dispatches exactly ONE provider request. A
// result that names an older revision is stale by construction and must never
// reach InstallExternalPath.
//
// Two providers share one result slot, so the failure this exists to catch is
// specific and silent: a superseded episode's plan landing on the slot AFTER
// the supersede, overwriting a live route with a route to a goal nobody asked
// for any more. Nothing observable breaks at the moment it happens - the agent
// simply walks somewhere else.
//
// Shape: MoveTo A, then MoveTo B one frame later, on a wide open GroundNav
// field where both goals are trivially reachable. The revision is read off the
// shared slot on each side of the supersede (Get_PathResult().
// Get_RequestRevision(), the Stall_UnreachableGoalFailsBounded idiom) and every
// OnPathReady is recorded with the revision it carried and the time it arrived.
//
// WHAT IS AND IS NOT PINNED DOWN. Episode A's search can legitimately finish
// before MoveTo B is drained - a small field plans in a frame or two - and a
// route installed while it was still the live episode is not a defect. So the
// assertion is not "A never produced a result"; it is the invariant that
// actually holds: after the supersede is OBSERVED on the slot, no OnPathReady
// carrying anything other than episode B's revision may arrive, and exactly one
// carrying B's revision may.
//
// ECk_CrowdAgent_PathProvider is not bound to AngelScript - there is no
// Get_ActiveProvider on utils_crowd_agent - so "one provider" is asserted
// through the signals and the revision on the shared slot, not by reading the
// recorded provider back. Selection itself is covered by the walk test, which
// cannot pass on Recast at this Y band at all.
//
// Isolated Y band: 124000 - clear of every other autotest's bodies.
//============================================================================

class UCk_AutoTest_Crowd_GroundNav_OneProviderPerEpisode : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 40.0f;

    //------------------------------------------------------------------------
    // Fixture geometry
    //------------------------------------------------------------------------

    private const float BandY = 124000.0;

    private const float SlabHalfX = 1100.0;
    private const float SlabHalfY = 600.0;
    private const float SlabHalfZ = 50.0;

    private const float VolumeHalfX = 900.0;
    private const float VolumeHalfY = 400.0;
    private const float VolumeFloorZ = -200.0;
    private const float VolumeCeilingZ = 500.0;

    private const float SurfaceZ = 0.0;
    private const float AgentCentreOffsetZ = 100.0;

    private const float SpawnX = -600.0;

    private const float AgentRadius = 42.0;
    private const float AgentHeight = 192.0;

    //------------------------------------------------------------------------
    // Budgets
    //------------------------------------------------------------------------

    private const float SampleIntervalSec = 0.1;

    // The supersede must be visible on the slot within a handful of frames; if it
    // is not, MoveTo B was never drained and nothing below means anything.
    private const float SupersedeDeadlineSec = 5.0;
    // Episode B's plan on an 1800x800 field is a sub-second search; 8s is the
    // watchdog's own PathPending timeout minus room, so a miss here is a real miss.
    private const float ResultDeadlineSec = 8.0;
    // One quiet stretch after B's result, so a stale A result arriving late is
    // caught rather than raced past.
    private const float SettleAfterResultSec = 1.0;
    private const float HardDeadlineSec = 34.0;

    //------------------------------------------------------------------------
    // State
    //------------------------------------------------------------------------

    private FCk_Handle _SelfHandle;
    private FCk_Handle _FloorEntity;
    private FCk_Handle _VolumeEntity;
    private FCk_Handle _AgentEntity;

    private FCk_Handle_JoltBody _FloorBody;
    private FCk_Handle_GroundNavVolume _Volume;
    private FCk_Handle_CrowdAgent _Agent;

    private ECk_NavSurface_Provider _ProviderBefore = ECk_NavSurface_Provider::Recast;
    private ECk_NavSurface_Provider _ProviderWhilePlanning = ECk_NavSurface_Provider::Recast;
    private bool _ProviderSwapped = false;

    private int32 _BuildCompletions = 0;
    private ECk_Request_OperationResult _LastBuildResult = ECk_Request_OperationResult::Failed;

    private bool _BuildRequested = false;
    private bool _FirstMoveToIssued = false;

    private bool _SecondMoveToIssued = false;
    private float _SecondMoveToAtSec = -1.0;
    private int32 _RevisionA = 0;
    private int32 _EpisodeA = 0;

    private bool _SupersedeObserved = false;
    private float _SupersedeAtSec = -1.0;
    private int32 _RevisionB = 0;
    private int32 _EpisodeB = 0;

    private TArray<int32> _ReadyRevisions;
    private TArray<float> _ReadyAtSec;
    private int32 _PathFailedCount = 0;

    private float _ElapsedSec = 0.0;

    //------------------------------------------------------------------------
    // Lifecycle
    //------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        _SelfHandle = InHandle;
        _ProviderBefore = utils_nav_surface::Get_Provider();

        utils_transform::Add(_SelfHandle,
            FTransform(FRotator::ZeroRotator, FVector(0.0, BandY, 0.0), FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        Build_Fixture();

        auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(SampleIntervalSec));
        TimerParams.Set_StartingState(ECk_Timer_State::Running)
                   .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto Timer = utils_timer::Add(_SelfHandle, TimerParams);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnPoll"));
    }

    UFUNCTION(BlueprintOverride)
    void DoEndPlay(FCk_Handle InHandle)
    {
        Teardown();
    }

    //------------------------------------------------------------------------
    // Fixture
    //------------------------------------------------------------------------

    private void Build_Fixture()
    {
        _FloorEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _FloorEntity.Request_OverrideToSelf();

        utils_transform::Add(_FloorEntity,
            FTransform(FRotator::ZeroRotator, FVector(0.0, BandY, SurfaceZ - SlabHalfZ)),
            ECk_Replication::DoesNotReplicate);

        auto SlabShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        SlabShape.Set_HalfExtents(FVector(SlabHalfX, SlabHalfY, SlabHalfZ));

        auto SlabParams = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        SlabParams.Set_ShapeDimensions(SlabShape);
        SlabParams.Set_MotionType(ECk_MotionType::Static);

        _FloorBody = utils_jolt_body::Add(_FloorEntity, SlabParams);

        Assert_True(ck::IsValid(_FloorBody), "the slab's Jolt body must be valid");

        _VolumeEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _VolumeEntity.Request_OverrideToSelf();

        auto Config = FCk_GroundNav_BakeConfig(25.0f, 10.0f);
        Config.Set_TileSizeUu(500.0f);

        auto Profile = FCk_GroundNav_AgentProfile(
            utils_shapes::Make_Capsule(FCk_ShapeCapsule_Dimensions(96.0f, 42.0f)));
        Profile.Set_LedgeSensitivity(0.0f);

        const auto Bounds = FBox(
            FVector(-VolumeHalfX, BandY - VolumeHalfY, VolumeFloorZ),
            FVector( VolumeHalfX, BandY + VolumeHalfY, VolumeCeilingZ));

        auto VolumeParams = FCk_Fragment_GroundNavVolume_ParamsData(Bounds, Config, Profile);
        VolumeParams.Set_AutoBuildOnSetup(ECk_EnableDisable::Disable);

        _Volume = utils_ground_nav_volume::Add(_VolumeEntity, VolumeParams);

        Assert_True(ck::IsValid(_Volume), "Add() must return a valid volume handle");
    }

    private FVector Get_GoalA() const
    {
        return FVector(600.0, BandY, SurfaceZ + AgentCentreOffsetZ);
    }

    private FVector Get_GoalB() const
    {
        // A genuinely different goal, well clear of A and still deep inside the field.
        return FVector(0.0, BandY + 250.0, SurfaceZ + AgentCentreOffsetZ);
    }

    private void Spawn_Agent()
    {
        const auto Spawn = FVector(SpawnX, BandY, SurfaceZ + AgentCentreOffsetZ);

        auto Params = FCk_Fragment_CrowdAgent_ParamsData(float32(AgentRadius), float32(AgentHeight));

        _AgentEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _AgentEntity.Set_DebugName(n"GroundNav_OneProviderPerEpisode_Walker");

        const auto Rot = (Get_GoalA() - Spawn).Rotation();
        auto AgentTransform = utils_transform::Add(_AgentEntity,
            FTransform(Rot, Spawn, FVector::OneVector), ECk_Replication::DoesNotReplicate);

        _Agent = utils_crowd_agent::Add(AgentTransform, Params);

        utils_velocity::Add(_AgentEntity,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(_AgentEntity,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(_AgentEntity);

        utils_nav::BindTo_OnPathReady(_AgentEntity,
            FCk_Delegate_Nav_OnPathReady(this, n"OnPathReady"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_nav::BindTo_OnPathFailed(_AgentEntity,
            FCk_Delegate_Nav_OnPathFailed(this, n"OnPathFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
    }

    //------------------------------------------------------------------------
    // Poll
    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnPoll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _ElapsedSec += SampleIntervalSec;

        if (_ElapsedSec >= HardDeadlineSec)
        {
            Fail(f"HARD DEADLINE at {_ElapsedSec}s (builds={_BuildCompletions}, firstMoveTo={_FirstMoveToIssued}, secondMoveTo={_SecondMoveToIssued}, supersede={_SupersedeObserved}, readySignals={_ReadyRevisions.Num()})");
            return;
        }

        if (_BuildRequested == false)
        {
            if (utils_jolt_body::Get_IsBodyAdded(_FloorBody) == false) { return; }

            _BuildRequested = true;
            utils_ground_nav_volume::Request_Build(_Volume, FCk_Request_GroundNavVolume_Build(),
                FCk_Delegate_Request_OnCompleted(this, n"OnBuildCompleted"));
            return;
        }

        if (_FirstMoveToIssued == false)
        {
            if (_BuildCompletions < 1) { return; }
            if (utils_ground_nav_volume::Get_IsBuilt(_Volume) == false) { return; }

            Assert_True(_LastBuildResult == ECk_Request_OperationResult::Succeeded,
                f"a bake that finished must complete with Succeeded (got {_LastBuildResult})");

            utils_nav_surface::Request_SetProvider(ECk_NavSurface_Provider::GroundNav);
            _ProviderSwapped = true;
            _ProviderWhilePlanning = utils_nav_surface::Get_Provider();

            Assert_True(_ProviderWhilePlanning == ECk_NavSurface_Provider::GroundNav,
                f"the world must report the provider it was told to plan on (got {_ProviderWhilePlanning})");

            Spawn_Agent();

            utils_crowd_agent::Request_MoveTo(_Agent, FCk_Request_CrowdAgent_MoveTo(Get_GoalA()));
            _FirstMoveToIssued = true;

            // A short separation, so episode A is genuinely DISPATCHED before it is superseded - a
            // same-tick second MoveTo is drained in the same processor pass and would prove nothing
            // about an in-flight provider query being abandoned. WaitOneFrame is 0.05s of wall
            // clock rather than a frame count (CkTests/CLAUDE.md), which is the shortest wait the
            // harness offers and is deliberately kept rather than converted to a named condition:
            // the condition here IS "one dispatch has happened", and there is no predicate for it
            // that would not already be true on arrival.
            WaitOneFrame(n"OnIssueSecondMoveTo");
            return;
        }

        if (ck::Is_NOT_Valid(_Agent))
        {
            Fail("the walker went invalid mid-run");
            return;
        }

        if (_SecondMoveToIssued == false) { return; }

        if (_SupersedeObserved == false)
        {
            const auto RevisionNow = utils_nav::Get_PathResult(_Agent).Get_RequestRevision();
            if (RevisionNow == _RevisionA)
            {
                if (_ElapsedSec >= _SecondMoveToAtSec + SupersedeDeadlineSec)
                {
                    Fail(f"{SupersedeDeadlineSec}s after a second MoveTo the shared nav slot still carries episode A's revision {_RevisionA}. A MoveTo that does not advance the revision cannot supersede the in-flight provider query, and every later assertion here would be vacuous.");
                }
                return;
            }

            _SupersedeObserved = true;
            _SupersedeAtSec = _ElapsedSec;
            _RevisionB = RevisionNow;
            _EpisodeB = utils_crowd_agent::Get_ActiveMoveEpisode(_Agent);

            Assert_Equals_Int(_EpisodeB, _EpisodeA + 1,
                "a second MoveTo starts exactly one fresh movement episode - two episodes for one request would mean the fork dispatched twice");
            return;
        }

        if (Get_ReadyCountForRevision(_RevisionB) < 1)
        {
            if (_ElapsedSec >= _SupersedeAtSec + ResultDeadlineSec)
            {
                const auto Status = utils_nav::Get_PathStatus(_Agent);
                Fail(f"{ResultDeadlineSec}s after the supersede, episode B (revision {_RevisionB}) has produced no OnPathReady (navStatus={Status}, readySignals={_ReadyRevisions.Num()}, failSignals={_PathFailedCount}). Abandoning the previous provider must not leave the new episode with nobody dispatched to answer it.");
            }
            return;
        }

        // A quiet stretch after B's result: a stale A result that installs late is exactly the
        // silent overwrite this test exists for, and it would otherwise be raced past.
        if (_ElapsedSec < _SupersedeAtSec + ResultDeadlineSec &&
            _ElapsedSec < Get_LastReadyAtSec() + SettleAfterResultSec)
        { return; }

        DoAssert_Episodes();
    }

    UFUNCTION()
    private void OnIssueSecondMoveTo(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _RevisionA = utils_nav::Get_PathResult(_Agent).Get_RequestRevision();
        _EpisodeA = utils_crowd_agent::Get_ActiveMoveEpisode(_Agent);

        utils_crowd_agent::Request_MoveTo(_Agent, FCk_Request_CrowdAgent_MoveTo(Get_GoalB()));
        _SecondMoveToIssued = true;
        _SecondMoveToAtSec = _ElapsedSec;
    }

    //------------------------------------------------------------------------
    // Assertions
    //------------------------------------------------------------------------

    private void DoAssert_Episodes()
    {
        auto ReadyForB = 0;
        auto StaleAfterSupersede = 0;
        auto StaleRevisionSeen = 0;

        for (int32 Index = 0; Index < _ReadyRevisions.Num(); Index++)
        {
            if (_ReadyRevisions[Index] == _RevisionB)
            {
                ReadyForB += 1;
                continue;
            }

            if (_ReadyAtSec[Index] >= _SupersedeAtSec)
            {
                StaleAfterSupersede += 1;
                StaleRevisionSeen = _ReadyRevisions[Index];
            }
        }

        Assert_Equals_Int(StaleAfterSupersede, 0,
            f"a plan carrying revision {StaleRevisionSeen} installed AFTER the slot had already advanced to {_RevisionB}. A superseded episode's result must be dropped, not written over the live route - nothing observable breaks at the moment it happens, the agent simply walks to a goal nobody asked for any more.");

        Assert_Equals_Int(ReadyForB, 1,
            f"exactly one provider answered episode B - {ReadyForB} routes were installed against revision {_RevisionB}, and a second install means two providers were dispatched for one episode");

        Assert_Equals_Int(_PathFailedCount, 0,
            f"neither episode failed on a wide open baked field (got {_PathFailedCount} OnPathFailed signals)");

        Assert_Equals_Int(utils_crowd_agent::Get_ActiveMoveEpisode(_Agent), _EpisodeB,
            "no third movement episode was started behind the caller's back");

        Teardown();
        FinishSuccess();
    }

    private int32 Get_ReadyCountForRevision(int32 InRevision) const
    {
        auto Count = 0;
        for (int32 Index = 0; Index < _ReadyRevisions.Num(); Index++)
        {
            if (_ReadyRevisions[Index] == InRevision) { Count += 1; }
        }
        return Count;
    }

    private float Get_LastReadyAtSec() const
    {
        auto Last = -1.0;
        for (int32 Index = 0; Index < _ReadyAtSec.Num(); Index++)
        {
            if (_ReadyAtSec[Index] > Last) { Last = _ReadyAtSec[Index]; }
        }
        return Last;
    }

    //------------------------------------------------------------------------
    // Signals
    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnBuildCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _BuildCompletions += 1;
        _LastBuildResult = InResult;
    }

    UFUNCTION()
    private void OnPathReady(FCk_Handle InHandle, FCk_Nav_PathResult InResult)
    {
        if (IsFinished()) { return; }

        _ReadyRevisions.Add(InResult.Get_RequestRevision());
        _ReadyAtSec.Add(_ElapsedSec);
    }

    UFUNCTION()
    private void OnPathFailed(FCk_Handle InHandle)
    {
        if (IsFinished()) { return; }

        _PathFailedCount += 1;
    }

    //------------------------------------------------------------------------
    // Teardown
    //------------------------------------------------------------------------

    private void Fail(const FString& InMessage)
    {
        Teardown();
        FinishFailure(InMessage);
    }

    private void Teardown()
    {
        if (_ProviderSwapped)
        {
            _ProviderSwapped = false;
            utils_nav_surface::Request_SetProvider(_ProviderBefore);
        }

        if (ck::IsValid(_AgentEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_AgentEntity);
            _AgentEntity = FCk_Handle();
        }
        if (ck::IsValid(_VolumeEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_VolumeEntity);
            _VolumeEntity = FCk_Handle();
        }
        if (ck::IsValid(_FloorEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_FloorEntity);
            _FloorEntity = FCk_Handle();
        }
    }
}
