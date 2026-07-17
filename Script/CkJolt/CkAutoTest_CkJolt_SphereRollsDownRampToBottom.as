// Language=angelscript

//============================================================================
// CK JOLT — AUTOMATION TEST: SPHERE ROLLS DOWN A RAMP AND SETTLES AT THE BOTTOM
//============================================================================
//
// Gravity + friction on an inclined Static surface: a Dynamic sphere placed on the
// high end of a tilted ramp must roll down-slope, off the lower edge, and settle
// past it (a back wall on the floor catches it for a deterministic rest).
//
//   1. Static floor + a Static ramp box pitched 20 deg (high end at +X, low end -X)
//      + a Static back wall near the low end.
//   2. Dynamic sphere placed above the ramp's high (+X) end.
//   3. Assert the sphere's X progresses down-slope and settles past the ramp's lower
//      edge (against the back wall), well below where it started.
//
// Placed at an isolated Y so it never touches other autotests' physics bodies.
//============================================================================

class UCk_AutoTest_CkJolt_SphereRollsDownRampToBottom : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 25.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_Transform _SphereTransform;

    private float _ParkY = 57000.0;
    private float _SphereStartX = 250.0;
    // Ramp half-extent X = 300 pitched 20 deg -> horizontal reach 300*cos(20) ~= 282; lower edge at -282.
    private float _RampLowerEdgeX = -280.0;

    private int _FramesWaited = 0;
    private int _StableFrames = 0;
    private FVector _LastPos = FVector::ZeroVector;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        // ---- Static floor ---------------------------------------------------------------------
        DoAddStaticBox(FVector(0.0, _ParkY, 0.0), FRotator::ZeroRotator, FVector(700.0, 200.0, 25.0));

        // ---- Static ramp: pitched 20 deg about Y (high end +X, low end -X) --------------------
        DoAddStaticBox(FVector(0.0, _ParkY, 150.0), FRotator(20.0, 0.0, 0.0), FVector(300.0, 150.0, 15.0));

        // ---- Static back wall near the low end to catch the rolling sphere --------------------
        DoAddStaticBox(FVector(-640.0, _ParkY, 100.0), FRotator::ZeroRotator, FVector(10.0, 200.0, 100.0));

        // ---- Dynamic sphere on the ramp's high (+X) end ---------------------------------------
        auto SphereStart = FVector(_SphereStartX, _ParkY, 330.0);
        auto SphereEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        SphereEntity.Request_OverrideToSelf();
        _SphereTransform = utils_transform::Add(SphereEntity, FTransform(FRotator::ZeroRotator, SphereStart),
            ECk_Replication::DoesNotReplicate);

        auto SphereShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Sphere);
        SphereShape.Set_Radius(30.0);
        auto SphereParams = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        SphereParams.Set_ShapeDimensions(SphereShape);
        SphereParams.Set_MotionType(ECk_MotionType::Dynamic);
        SphereParams.Set_SurfaceSource(ECk_JoltBody_SurfaceSource::Explicit);
        SphereParams.Set_Friction(0.4);
        SphereParams.Set_Restitution(0.0);
        utils_jolt_body::Add(SphereEntity, SphereParams);

        _LastPos = SphereStart;
        utils_timer::Create_Tick(_SelfHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    private void DoAddStaticBox(FVector InCenter, FRotator InRotation, FVector InHalfExtents)
    {
        auto Entity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        Entity.Request_OverrideToSelf();
        utils_transform::Add(Entity, FTransform(InRotation, InCenter), ECk_Replication::DoesNotReplicate);

        auto Shape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        Shape.Set_HalfExtents(InHalfExtents);
        auto Params = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        Params.Set_ShapeDimensions(Shape);
        Params.Set_MotionType(ECk_MotionType::Static);
        utils_jolt_body::Add(Entity, Params);
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _FramesWaited++;
        auto CurrentPos = utils_transform::Get_EntityCurrentLocation(_SphereTransform);

        if (CurrentPos.Distance(_LastPos) < 0.5)
        { _StableFrames++; }
        else
        { _StableFrames = 0; }
        _LastPos = CurrentPos;

        // Settled: stable for 15 consecutive frames (resting against the back wall).
        if (_StableFrames >= 15)
        {
            Assert_True(CurrentPos.X < _SphereStartX - 300.0,
                f"Sphere should progress well down-slope from its start (start X={_SphereStartX}, final X={CurrentPos.X})");
            Assert_True(CurrentPos.X < _RampLowerEdgeX,
                f"Sphere should settle PAST the ramp's lower edge (lowerEdge X={_RampLowerEdgeX}, final X={CurrentPos.X})");
            FinishSuccess();
            return;
        }

        if (_FramesWaited > 1200)
        { FinishFailure(f"Sphere never settled after {_FramesWaited} frames (X={CurrentPos.X}, Z={CurrentPos.Z})"); }
    }
}
