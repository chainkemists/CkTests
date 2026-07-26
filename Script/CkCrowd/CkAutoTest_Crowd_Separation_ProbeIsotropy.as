// Language=angelscript
//============================================================================
// CK CROWD — AUTOMATION TEST: SEPARATION PROBE ISOTROPY
//
// REGRESSION TEST for the Jolt Y-axis probe-cylinder defect (2026-07-13).
//
// Jolt's CylinderShape is Y-AXIS ALIGNED by convention ("one top at
// (0,-HalfHeight,0), the other at (0,+HalfHeight,0)" — Jolt CylinderShape.h),
// while CkSpatialQuery runs Jolt in Unreal's Z-up frame with an axis-passthrough
// Conv(). Nobody applied the Y->Z correction, so every crowd agent's
// neighbor-detection probe lay ON ITS SIDE. Neighbor detection was ANISOTROPIC
// in the ground plane: an agent could see a neighbor along world X that it was
// blind to along world Y.
//
// Not one of the 771 automated tests noticed. The three behavioral
// Crowd_Separation_* tests passed with the broken sideways probe AND with the
// fixed upright one — they assert on emergent walking behavior, which is far too
// slack to feel a distorted query volume. It took a human squinting at a debug
// draw in PIE. THIS test closes that hole by asserting on the probe's GEOMETRY.
//
//----------------------------------------------------------------------------
// THE GEOMETRY — derived from source, not assumed
//
// An agent's probe is its ONLY shape (CkCrowdAgent_Processor.cpp:74-87): a
// cylinder of Radius = _Radius + _SeparationLookahead and HalfHeight = _Height/2,
// SceneNode-parented at agent + (0,0,HalfHeight). Its Probe filter AND name are
// both TAG_Crowd_Agent, so probes overlap EACH OTHER — the neighbor cache maps
// each overlap back through the other PROBE CHILD to its agent
// (CkCrowdAgent_Neighbors_Processor.cpp:76-83).
//
// Detection reach is therefore the sum of TWO probes, not probe-vs-point:
//
//   ProbeRadius     = _Radius(42) + _SeparationLookahead(200) = 242
//   ProbeHalfHeight = _Height(192) / 2                        = 96
//
//   FIXED  (Z-aligned): two agents at equal Z overlap iff planar distance
//                       <= 2 * ProbeRadius     = 484   (in EVERY bearing)
//   BROKEN (Y-aligned): overlap additionally requires |dY|
//                       <= 2 * ProbeHalfHeight = 192   (a slab, not a disc)
//
// So a neighbor placed at GapCm from its subject is seen in every bearing by the
// fixed probe, but the broken probe goes BLIND to it once |dY| exceeds 192.
// GapCm = 330 sits 138cm clear of that cutoff and 154cm inside the fixed reach —
// deliberately not a knife-edge at either end.
//
// The subject is one of a RING of bearings. Under the broken probe the six
// bearings within 35.6deg of +/-Y (i.e. |330*sin(theta)| > 192) go undetected and
// report zero force; the 0deg / 180deg pair stays visible and doubles as the
// "the probe pipeline is alive at all" control — if THOSE fail, nothing is being
// detected anywhere and the isotropy claim was never testable.
//
//----------------------------------------------------------------------------
// WHY DETECTION, NOT FORCE MAGNITUDE, IS THE ASSERTION
//
// Two traps make a force-magnitude comparison the wrong instrument:
//
//  1. The separation processor adds a deterministic per-agent JITTER of fixed
//     magnitude 0.05 to break head-on stalemates, BEFORE scaling by
//     (_SeparationWeight * _MaxSpeed) = 120 (CkCrowdAgent_Separation_Processor
//     .cpp:96-106). That is +/-6cm/s of entity-hash-keyed noise per subject, so
//     two geometrically identical pairs legitimately disagree on |F| by up to
//     12cm/s. Asserting |F_a| == |F_b| to a tight tolerance FAILS ON CORRECT CODE.
//  2. Even without the jitter, once a neighbor IS detected its force depends only
//     on distance and _SeparationRadius — both identical across bearings by
//     construction. Comparing magnitudes re-measures our own spawn geometry and
//     says nothing whatsoever about the probe's shape.
//
// Detection is a BOOLEAN per bearing, and that boolean is exactly the isotropy
// claim. We read it through the separation force projected onto the away-axis:
// with _SeparationRadius(600) > GapCm(330), any detected neighbor yields a force,
// and an undetected one yields exactly zero (the processor early-outs on an empty
// cache). Expected projection is
//     (1 - 330/600)^2 * 0.5 * 240 = 24.3 cm/s,
// worst-cased by the jitter to >= 18.3 — far above MinDetectableForce, and
// infinitely above the 0.0 the broken probe produces.
//
// NOTE the agents are deliberately IDLE (no MoveTo). NeighborSync and Separation
// exclude only FTag_CrowdAgent_Asleep (which nothing ever stamps), while Steering
// REQUIRES FTag_CrowdAgent_Walking (CkCrowdAgent_Steering_Processor.h:34). So the
// probe -> neighbor-cache -> separation-force chain runs on a standing agent that
// never moves: the geometry under test holds still, with zero interference from
// path-follow or steering dynamics.
//============================================================================

class UCk_AutoTest_Crowd_Separation_ProbeIsotropy : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 15.0f;

    private TArray<FCk_Handle_CrowdAgent> _Subjects;
    private TArray<FVector> _AwayDirs;      // unit vector pointing from the neighbor back to its subject
    private TArray<float> _BearingsDeg;

    private float _ElapsedSec = 0.0;

    // See header. 192 < GapCm < 484, and GapCm < SeparationRadius.
    private const float GapCm               = 330.0;
    private const float SeparationRadius    = 600.0;
    private const float SeparationLookahead = 200.0;  // -> ProbeRadius = 42 + 200 = 242
    private const float PairIsolationCm     = 1500.0; // 1500 - 2*330 = 840 > 484: pairs cannot see each other
    private const float SpawnZ              = 100.0;

    private const int32 BearingCount        = 8;      // full ring, every 45deg

    private const float SettleSec           = 1.0;    // NeighborSync lags probe overlap by a frame
    private const float SampleIntervalSec   = 0.05;

    // Expected away-axis projection is 24.3cm/s, worst-cased to 18.3 by the jitter.
    // The broken probe produces exactly 0.0 in a blind bearing.
    private const float MinDetectableForce  = 5.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, FVector::ZeroVector, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        // One isolated subject+neighbor pair per bearing, strung out along world X so no agent
        // of one pair falls inside any probe of another.
        for (int32 Bearing = 0; Bearing < BearingCount; ++Bearing)
        {
            const auto AngleDeg = 360.0f * float(Bearing) / float(BearingCount);
            const auto AngleRad = AngleDeg * Math::PI / 180.0f;
            const auto Dir = FVector(Math::Cos(AngleRad), Math::Sin(AngleRad), 0.0);

            const auto SubjectLoc = FVector(float(Bearing) * PairIsolationCm, 0.0, SpawnZ);

            _Subjects.Add(SpawnIdleAgent(LocalHandle, SubjectLoc));
            SpawnIdleAgent(LocalHandle, SubjectLoc + Dir * GapCm);

            _AwayDirs.Add(Dir * -1.0);
            _BearingsDeg.Add(AngleDeg);
        }

        auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(SampleIntervalSec));
        TimerParams.Set_StartingState(ECk_Timer_State::Running)
                   .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto Timer = utils_timer::Add(LocalHandle, TimerParams);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnSettled"));
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _ElapsedSec += SampleIntervalSec;
        if (_ElapsedSec < SettleSec) { return; }

        for (int32 Bearing = 0; Bearing < BearingCount; ++Bearing)
        {
            auto Subject = _Subjects[Bearing];
            if (ck::Is_NOT_Valid(Subject))
            {
                FinishFailure("a subject agent went invalid before the probe settled");
                return;
            }

            const auto Force = utils_crowd_agent::Get_SeparationForce(Subject);
            const auto AwayDir = _AwayDirs[Bearing];
            const auto AwayForce = float(Force.DotProduct(AwayDir));
            const auto AngleDeg = _BearingsDeg[Bearing];

            // THE REGRESSION ASSERTION. Zero here means the probe never detected a neighbor
            // sitting GapCm away on this bearing — i.e. the query volume is not rotationally
            // symmetric about Z. Under the Y-aligned cylinder this fires for every bearing whose
            // |dY| exceeds 2*ProbeHalfHeight (192cm): 45/90/135/225/270/315 degrees all go blind.
            Assert_True(AwayForce >= MinDetectableForce,
                f"bearing {AngleDeg} deg: away-axis separation force is {AwayForce} (need >= {MinDetectableForce}). A neighbor {GapCm}cm away on this bearing went UNDETECTED, while the SAME neighbor at the SAME distance is seen on other bearings. The probe volume is ANISOTROPIC in the ground plane: this is the Jolt Y-axis cylinder defect (Jolt's CylinderShape is Y-aligned; CkSpatialQuery must rotate it Y->Z). If the 0 and 180 degree bearings ALSO failed, nothing is being detected at all and the probe pipeline itself is broken.");
        }

        FinishSuccess();
    }

    // Idle on purpose — NO MoveTo, and no euler-integrator start. Steering requires
    // FTag_CrowdAgent_Walking, so an idle agent never gets a desired velocity and never moves;
    // Separation has no such requirement, so it still publishes a force. Velocity/Acceleration are
    // composed anyway because the VelocityBridge processor runs on every non-asleep agent and
    // overrides velocity through the Velocity feature's public API.
    private FCk_Handle_CrowdAgent SpawnIdleAgent(FCk_Handle& InOwner, FVector InSpawn)
    {
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);
        Params.Set_SeparationRadius(SeparationRadius);
        Params.Set_SeparationLookahead(SeparationLookahead);

        // ONE ENTITY PER AGENT. utils_crowd_agent::Add composes onto the handle it is given and
        // enforces one agent per entity; utils_transform::Add is idempotent. Passing the shared
        // owner (as this did before) therefore collapsed every agent in the ring into a SINGLE
        // agent at the owner's transform: the first call won, the rest were no-ops, and a lone
        // agent has no neighbours — every bearing read exactly 0.0 force.
        auto AgentEntity = utils_entity_lifetime::Request_CreateEntity(InOwner);
        auto AgentTransform = utils_transform::Add(AgentEntity,
            FTransform(FRotator::ZeroRotator, InSpawn, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        auto Agent = utils_crowd_agent::Add(AgentTransform, Params);
        utils_velocity::Add(AgentEntity,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(AgentEntity,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);

        return Agent;
    }
}

class ACk_AutoTest_Crowd_Separation_ProbeIsotropy_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_Separation_ProbeIsotropy;
    default _TimeoutSeconds = 15.0f;
}
