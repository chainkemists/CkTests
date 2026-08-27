// Language=angelscript

//============================================================================
// CK JOLT - AUTOMATION TEST: IMPULSE CHANGES VELOCITY (BODY LEAVES + RETURNS)
//============================================================================
//
// Request_AddImpulse must impart an instantaneous velocity change: a settled
// dynamic box shot straight up leaves the floor, then gravity brings it back to
// rest at the same spot.
//
//   1. Static floor + a Dynamic box settled on it (rest Z ~= floorTop + halfExtent).
//   2. Once stable, record the rest Z and fire Request_AddImpulse straight up.
//   3. Assert the box rises clearly above rest (left the floor) ...
//   4. ... and returns to rest (gravity), settling back near the recorded Z.
//
// The default-density (1000 kg/m^3) 100uu box has a Jolt-computed mass of
// ~1000 * (8*50*50*50) = 1e9; impulse = mass * dv, so ~4e11 targets a ~400uu/s
// launch (a clean, quick hop). We assert on the observed rise/return, not the
// exact velocity, so the test is robust to the precise mass.
//
// Placed at an isolated Y so it never touches other autotests' physics bodies.
//============================================================================

class UCk_AutoTest_CkJolt_ImpulseChangesVelocity : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 25.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_JoltBody _Body;
    private FCk_Handle_Transform _BoxTransform;

    private FVector _FloorCenter = FVector(0.0, 45000.0, 0.0);
    private float _BoxHalfExtent = 50.0;

    // ~4e11 -> ~400uu/s upward launch on the ~1e9 shape-mass (see header).
    private float _UpImpulseZ = 400000000000.0;
    private float _RiseThreshold = 20.0;   // must clear this above rest to count as "left the floor"

    private int _Phase = 0;   // 0 = settling, 1 = launched (watch rise + return)
    private float _Elapsed = 0.0;
    private float _StableTime = 0.0;
    private float _LastZ = 0.0;
    private float _RestZ = 0.0;
    private float _PeakZ = 0.0;
    private bool _LeftFloor = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        // ---- Static floor ---------------------------------------------------------------------
        auto FloorEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        FloorEntity.Request_OverrideToSelf();
        utils_transform::Add(FloorEntity, FTransform(FRotator::ZeroRotator, _FloorCenter),
            ECk_Replication::DoesNotReplicate);

        auto FloorShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        FloorShape.Set_HalfExtents(FVector(500.0, 500.0, 25.0));
        auto FloorParams = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        FloorParams.Set_ShapeDimensions(FloorShape);
        FloorParams.Set_MotionType(ECk_MotionType::Static);
        utils_jolt_body::Add(FloorEntity, FloorParams);

        // ---- Dynamic box dropped a short distance so it settles quickly ------------------------
        auto BoxStart = _FloorCenter + FVector(0.0, 0.0, 150.0);
        auto BoxEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        BoxEntity.Request_OverrideToSelf();
        _BoxTransform = utils_transform::Add(BoxEntity, FTransform(FRotator::ZeroRotator, BoxStart),
            ECk_Replication::DoesNotReplicate);

        auto BoxShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        BoxShape.Set_HalfExtents(FVector(_BoxHalfExtent, _BoxHalfExtent, _BoxHalfExtent));
        auto BoxParams = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        BoxParams.Set_ShapeDimensions(BoxShape);
        BoxParams.Set_MotionType(ECk_MotionType::Dynamic);
        _Body = utils_jolt_body::Add(BoxEntity, BoxParams);

        _LastZ = BoxStart.Z;
        utils_timer::Create_Tick(_SelfHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _Elapsed += float(InDeltaT.Get_Seconds());
        auto CurrentZ = utils_transform::Get_EntityCurrentLocation(_BoxTransform).Z;

        if (_Phase == 0)
        {
            if (Math::Abs(CurrentZ - _LastZ) < 0.1)
            { _StableTime += float(InDeltaT.Get_Seconds()); }
            else
            { _StableTime = 0.0; }
            _LastZ = CurrentZ;

            if (_StableTime >= 0.25)
            {
                _RestZ = CurrentZ;
                _PeakZ = CurrentZ;
                utils_jolt_body::Request_AddImpulse(_Body,
                    FCk_Request_JoltBody_AddImpulse(FVector(0.0, 0.0, _UpImpulseZ)));
                _Phase = 1;
                _Elapsed = 0.0;
            }

            if (_Elapsed > 15.0)
            { FinishFailure(f"Box never settled before impulse (last Z={CurrentZ})"); }

            return;
        }

        // Phase 1 - the box must rise clearly above rest, then return to rest.
        if (CurrentZ > _PeakZ)
        { _PeakZ = CurrentZ; }

        if (CurrentZ > _RestZ + _RiseThreshold)
        { _LeftFloor = true; }

        if (_LeftFloor && Math::Abs(CurrentZ - _RestZ) <= 8.0)
        {
            Assert_True(_PeakZ > _RestZ + _RiseThreshold,
                f"Impulse should launch the box clear of rest (peak Z={_PeakZ}, rest Z={_RestZ})");
            Assert_True(Math::Abs(CurrentZ - _RestZ) <= 8.0,
                f"Box should return to rest after the hop (Z={CurrentZ}, rest Z={_RestZ})");
            FinishSuccess();
            return;
        }

        if (_Elapsed > 20.0)
        {
            FinishFailure(f"Box did not complete the impulse hop+return (peak Z={_PeakZ}, rest Z={_RestZ}, current Z={CurrentZ})");
        }
    }
}
