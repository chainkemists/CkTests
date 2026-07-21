// Language=angelscript
//============================================================================
// CK CROWD — AUTOMATION TEST: SEPARATION CONVERGENCE
//
// 5 agents around a 600cm circle, all targeting the SAME point — an
// unsatisfiable goal (five 42cm agents in contact form a ring of radius
// ~71cm, so NOBODY can stand within the 30cm arrival radius). They therefore
// press inward forever. Two phases, two DISTINCT invariants:
//
// Phase 1 (t=6s) — LIVENESS under crowding (the freeze-bug regression guard):
// all agents within 200cm of the target, still pressing, and no pair piled
// up: PairSep >= 61cm. That floor is DERIVED, not tuned. PushApart resolves
// >= 0.7 x penetration per pair per frame (each agent displaces 0.5*0.7*P
// along the pair axis in iteration 1 alone — CkCrowdAgent_PushApart_Processor
// .cpp), while the integrator can re-close a pair by at most 2*MaxSpeed*dt.
// Worst case at 30fps: 2*240*(1/30) / 0.7 ~= 23cm of equilibrium overlap
// -> floor = 84 - 23 = 61cm.
//
// ZERO INTERPENETRATION WHILE AGENTS ACTIVELY DRIVE INWARD IS NOT AN
// INVARIANT of this resolver family (0.7 factor, 4 iterations, deliberately
// under-relaxed; stock UE ships dtCrowd's equivalent DISABLED and leans on
// physics capsules). The residual is an EQUILIBRIUM, not a transient: it
// scales with press-speed x frame-time, so no fixed floor mid-press is
// derivable and no resolver tuning makes one robust. Asserting 84cm here
// demands a guarantee the algorithm never made — and it only ever held
// because Steering used to DAMP path-follow as neighbours pressed, i.e.
// agents gave up when crowded. That "giving up" WAS the freeze bug.
//
// Phase 2 (t=7s, after Request_Stop at t=6s) — NON-PENETRATION AT REST: the
// safety invariant players actually see (idle NPCs must not clip through
// each other). With the inward drive gone, PushApart converges geometrically
// (>= 70% of remaining pair overlap per frame, and it runs on idle agents
// too — no Walking requirement), so a ~1.5cm residual is gone within a
// handful of frames; 1s of settling is orders of magnitude more than needed.
// All 10 pairs must then satisfy PairSep >= _Radius * 2 (= 84cm) — the
// Gate_03_Separation_Addendum.md §8 "final positions" criterion, asserted
// where the resolver actually guarantees it.
//
// If a SETTLED pair ever reads below 84cm, that is a real resolver defect.
// Do not add slack to make it pass.
//============================================================================

class UCk_AutoTest_Crowd_Separation_Convergence : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private TArray<FCk_Handle_CrowdAgent> _Agents;
    private const float TimeoutSec = 6.0;
    private const float SettleSec = 7.0;                // TimeoutSec + 1s of drive-free settling
    private const float ArrivalWindow = 200.0;
    private const float MinPairwiseSep = 84.0;          // _Radius * 2 — zero overlap, asserted AT REST
    private const float MinPairwiseSepPressing = 61.0;  // 84 - 23cm derived press equilibrium (see banner)

    // PushApart's fixed point IS the contact distance, approached from BELOW and never overshot: it
    // only pushes while Dist < CombinedRadius, and its resolve factor is 0.7 (< 1), so a settled pair
    // converges to exactly 84.0 asymptotically. A strict `>= 84.0` on a float is therefore an
    // unsatisfiable comparison against that asymptote — a settled pair reads 83.999827, i.e. 1.7
    // MICRONS short. This tolerance admits the asymptote and nothing else: it is a thousandth of the
    // 23cm press-equilibrium bound and one part in 84,000 of a body. Any real interpenetration — a
    // disabled or regressed PushApart, agents genuinely clipping — is orders of magnitude larger and
    // still fails hard. This is NOT slack to make a red test green; it is the difference between
    // "touching" and "overlapping".
    private const float ContactToleranceCm = 0.1;
    private const FVector Centre = FVector(0.0, 0.0, 100.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, FVector::ZeroVector, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        // Kick the navmesh: AutoTests_CkTests_Level has the fixture but the bake is lazy.
        // Each spawned agent issues a MoveTo → FindPath; the deferred-request queue holds
        // those until the rebuild completes (~10ms in practice).
        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        const auto Radius = 600.0;
        const auto Count = 5;
        const auto Step = (2.0 * Math::PI) / float(Count);
        for (int32 i = 0; i < Count; ++i)
        {
            const auto Angle = Step * float(i);
            const auto Spawn = Centre + FVector(Radius * Math::Cos(Angle), Radius * Math::Sin(Angle), 0.0);
            _Agents.Add(SpawnAgent(LocalHandle, Spawn, Centre));
        }

        // Phase 1 fires at TimeoutSec (liveness + pile-up asserts, then Stop all agents);
        // Phase 2 fires at SettleSec (at-rest non-penetration assert + FinishSuccess).
        auto ConvergeParams = FCk_Fragment_Timer_ParamsData(FCk_Time(TimeoutSec));
        ConvergeParams.Set_StartingState(ECk_Timer_State::Running)
                      .Set_Behavior(ECk_Timer_Behavior::StopOnDone);
        auto ConvergeTimer = utils_timer::Add(LocalHandle, ConvergeParams);
        ConvergeTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnConvergeTimeout"));

        auto SettleParams = FCk_Fragment_Timer_ParamsData(FCk_Time(SettleSec));
        SettleParams.Set_StartingState(ECk_Timer_State::Running)
                    .Set_Behavior(ECk_Timer_Behavior::StopOnDone);
        auto SettleTimer = utils_timer::Add(LocalHandle, SettleParams);
        SettleTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnSettleTimeout"));
    }

    UFUNCTION()
    private void OnConvergeTimeout(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Finals = DoGatherAgentPositions();
        if (IsFinished()) { return; }

        for (auto Loc : Finals)
        {
            const auto DistToCentre = float((Loc - Centre).Size());
            Assert_True(DistToCentre <= ArrivalWindow,
                f"agent failed to reach within {ArrivalWindow}cm of centre — final {DistToCentre}cm");
        }
        DoAssertPairwiseSeparation(Finals, MinPairwiseSepPressing, "while pressing");

        // Cut the inward drive: Walking -> Idle, desired velocity zeroed. The VelocityBridge has no
        // Walking requirement, so it ships that zero and the agents actually halt. PushApart — which
        // also runs on idle agents — now owns the cluster and de-penetrates it geometrically.
        for (auto Agent : _Agents)
        {
            utils_crowd_agent::Request_Stop(Agent);
        }
    }

    UFUNCTION()
    private void OnSettleTimeout(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Finals = DoGatherAgentPositions();
        if (IsFinished()) { return; }

        for (auto Loc : Finals)
        {
            const auto DistToCentre = float((Loc - Centre).Size());
            Assert_True(DistToCentre <= ArrivalWindow,
                f"agent drifted outside {ArrivalWindow}cm of centre after Stop — final {DistToCentre}cm");
        }
        DoAssertPairwiseSeparation(Finals, MinPairwiseSep, "at rest");

        FinishSuccess();
    }

    private TArray<FVector> DoGatherAgentPositions()
    {
        TArray<FVector> Positions;
        for (auto Agent : _Agents)
        {
            if (ck::Is_NOT_Valid(Agent))
            {
                FinishFailure("an agent went invalid before timeout — possible early destroy / replication issue");
                return Positions;
            }
            Positions.Add(utils_transform::Get_EntityCurrentLocation(utils_transform::DoCastChecked(FCk_Handle(Agent))));
        }
        return Positions;
    }

    private void DoAssertPairwiseSeparation(const TArray<FVector>&in InFinals, float InFloor, const FString&in InPhase)
    {
        for (int32 i = 0; i < InFinals.Num(); ++i)
        {
            for (int32 j = i + 1; j < InFinals.Num(); ++j)
            {
                const auto PairSep = float((InFinals[i] - InFinals[j]).Size());
                Assert_True(PairSep >= InFloor - ContactToleranceCm,
                    f"agents {i} and {j} ended within {InFloor}cm ({InPhase}) — pile-up at goal ({PairSep}cm)");
            }
        }
    }

    private FCk_Handle_CrowdAgent SpawnAgent(FCk_Handle& InOwner, FVector InSpawn, FVector InTarget)
    {
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);
        FCk_Handle Generic = InOwner;
        const auto Rot = (InTarget - InSpawn).Rotation();
        auto AgentTransform = utils_transform::Add(Generic, FTransform(Rot, InSpawn, FVector::OneVector), ECk_Replication::DoesNotReplicate);
        auto Agent = utils_crowd_agent::Add(AgentTransform, Params);
        utils_velocity::Add(Generic, FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(Generic, FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(Generic);
        utils_crowd_agent::Request_MoveTo(Agent, FCk_Request_CrowdAgent_MoveTo(InTarget));
        return Agent;
    }
}

class ACk_AutoTest_Crowd_Separation_Convergence_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_Separation_Convergence;
    default _TimeoutSeconds = 10.0f;
}
