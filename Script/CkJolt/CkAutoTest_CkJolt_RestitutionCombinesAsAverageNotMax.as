// Language=angelscript

//============================================================================
// CK JOLT — AUTOMATION TEST: A CONTACT PAIR'S RESTITUTION COMBINES BY AVERAGE
//============================================================================
//
// Jolt's stock combine function is max(r1, r2); Chaos uses the project's
// RestitutionCombineMode, which defaults to Average. Symmetric pairs agree
// either way, so the divergence only shows up when two surfaces disagree — and
// there it is total.
//
// This pins the SHIPPED DEFAULT of the Jolt project setting
// (Jolt Physics|Simulation -> RestitutionCombineMode, installed in
// UCk_Jolt_Subsystem::Initialize). A project that deliberately sets any other
// mode is expected to see this go red — that is the setting doing its job, not
// a regression.
//
//   1. Static floor, restitution 0.0.
//   2. Dynamic sphere, restitution 1.0, zero damping, dropped 400uu.
//   3. Measure the rebound apex above the impact low point.
//
// Impact speed is sqrt(2 * 981 * 400) ~= 886 cm/s, well clear of the 100 cm/s
// mMinVelocityForRestitution floor. Rebound height is (e * v)^2 / 2g:
//      average -> e = 0.5 -> ~100uu       max -> e = 1.0 -> ~400uu
// The 200uu ceiling sits a clean 2x from each, so neither a solver tweak nor a
// re-introduced max() can land in the gap.
//
// Placed at an isolated Y so it never touches other autotests' physics bodies.
//============================================================================

class UCk_AutoTest_CkJolt_RestitutionCombinesAsAverageNotMax : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_Transform _BallTransform;

    private FVector _FloorCenter = FVector(0.0, 96000.0, 0.0);
    private float _BallRadius = 50.0;
    private float _DropHeight = 400.0;
    private float _StartZ = 475.0;    // floorTop 25 + radius 50 + drop 400

    // Perfectly elastic would rebound the full 400uu; averaged restitution reaches ~100uu.
    private float _MaxAllowedRebound = 200.0;
    // A rebound this small means restitution was lost entirely, which is its own regression.
    private float _MinExpectedRebound = 20.0;

    private float _Elapsed = 0.0;
    private float _MinZ = 100000.0;
    private float _ApexZ = 0.0;
    private bool  _Rebounding = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        // ---- Static floor, fully inelastic -----------------------------------------------------
        auto FloorEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        FloorEntity.Request_OverrideToSelf();
        utils_transform::Add(FloorEntity, FTransform(FRotator::ZeroRotator, _FloorCenter),
            ECk_Replication::DoesNotReplicate);

        auto FloorShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        FloorShape.Set_HalfExtents(FVector(500.0, 500.0, 25.0));
        auto FloorParams = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        FloorParams.Set_ShapeDimensions(FloorShape);
        FloorParams.Set_MotionType(ECk_MotionType::Static);
        FloorParams.Set_SurfaceSource(ECk_JoltBody_SurfaceSource::Explicit);
        FloorParams.Set_Friction(0.5);
        FloorParams.Set_Restitution(0.0);
        utils_jolt_body::Add(FloorEntity, FloorParams);

        // ---- Dynamic sphere, perfectly elastic on its own side ---------------------------------
        auto BallStart = _FloorCenter + FVector(0.0, 0.0, _StartZ);
        auto BallEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        BallEntity.Request_OverrideToSelf();
        _BallTransform = utils_transform::Add(BallEntity,
            FTransform(FRotator::ZeroRotator, BallStart), ECk_Replication::DoesNotReplicate);

        auto BallShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Sphere);
        BallShape.Set_Radius(_BallRadius);
        auto BallParams = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        BallParams.Set_ShapeDimensions(BallShape);
        BallParams.Set_MotionType(ECk_MotionType::Dynamic);
        BallParams.Set_SurfaceSource(ECk_JoltBody_SurfaceSource::Explicit);
        BallParams.Set_Friction(0.5);
        BallParams.Set_Restitution(1.0);
        // Damping would bleed energy the rebound arithmetic above does not account for.
        BallParams.Set_LinearDamping(0.0);
        BallParams.Set_AngularDamping(0.0);
        utils_jolt_body::Add(BallEntity, BallParams);

        utils_timer::Create_Tick(_SelfHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _Elapsed += float(InDeltaT.Get_Seconds());
        if (_Elapsed > 15.0)
        {
            FinishFailure(f"Ball never completed a bounce after {_Elapsed}s (rebounding={_Rebounding}, low Z={_MinZ}, apex Z={_ApexZ})");
            return;
        }

        const auto CurrentZ = utils_transform::Get_EntityCurrentLocation(_BallTransform).Z - _FloorCenter.Z;

        if (_Rebounding == false)
        {
            if (CurrentZ < _MinZ)
            {
                _MinZ = CurrentZ;
                return;
            }

            // Only a rise that follows a real fall counts — a body still waiting on its Jolt
            // body-add sits at its spawn Z and must not be mistaken for an impact.
            if (_MinZ > _StartZ - 100.0 || CurrentZ <= _MinZ + 1.0)
            { return; }

            _Rebounding = true;
            _ApexZ = CurrentZ;
            return;
        }

        if (CurrentZ > _ApexZ)
        {
            _ApexZ = CurrentZ;
            return;
        }

        // Falling again: the apex is behind us and the rebound is measurable.
        if (CurrentZ < _ApexZ - 1.0)
        {
            const auto Rebound = _ApexZ - _MinZ;

            Assert_True(Rebound <= _MaxAllowedRebound,
                f"Restitution 1.0 vs 0.0 must combine to ~0.5 (Chaos average), not 1.0 (Jolt max). Dropped {_DropHeight}uu and rebounded {Rebound}uu (ceiling {_MaxAllowedRebound}uu, low Z={_MinZ}, apex Z={_ApexZ})");
            Assert_True(Rebound >= _MinExpectedRebound,
                f"The ball barely bounced ({Rebound}uu) - restitution looks lost, not averaged (low Z={_MinZ}, apex Z={_ApexZ})");

            FinishSuccess();
            return;
        }
    }
}
