// Language=angelscript

//============================================================================
// CK JOLT — AUTOMATION TEST: CHARACTER PUSH POLICY GOVERNS BOX DISPLACEMENT
//============================================================================
//
// A JoltCharacter's PushPolicy decides whether it can shove dynamic bodies. Two
// independent pairs (unique Y offsets) run side by side:
//
//   A (PushAndBePushed): character walks into a light Dynamic box -> the box is
//      displaced (> 20uu along the walk direction).
//   B (Neither): character walks into an identical box -> the box stays put (< 5uu)
//      and the character is obstructed (its X stalls at the box, no walk-through).
//
// Both boxes are made light (explicit 1kg) so a push, when allowed, clearly moves
// them. One class = one file (the wrapper generator requires it), two pairs inside.
//
// Phases are TIME-based (accumulated tick delta), never frame-counted: the automation
// PIE runs uncapped (~170fps observed), so "180 frames" is ~1s of walking, not the 3s
// a 60fps assumption gives — the characters never reached their boxes and every
// assertion passed or failed vacuously.
//
// Placed at isolated Ys so neither pair touches other autotests' physics bodies.
//============================================================================

class UCk_AutoTest_CkJolt_JoltCharacter_PushPolicyGovernsBoxDisplacement : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 25.0f;

    private FCk_Handle _SelfHandle;

    // Pair A — PushAndBePushed
    private FCk_Handle_JoltCharacter _CharA;
    private FCk_Handle_Transform _BoxATransform;
    private float _BoxAStartX = 0.0;

    // Pair B — Neither
    private FCk_Handle_JoltCharacter _CharB;
    private FCk_Handle_Transform _CharBTransform;
    private FCk_Handle_Transform _BoxBTransform;
    private float _BoxBStartX = 0.0;

    // Scratch for handing the just-created character transform back to the caller (AS value handles).
    private FCk_Handle_Transform _LastCharTransform;

    private float _MoveSpeed = 150.0;
    private float _BoxNearFaceX = 50.0;   // box centre 100, half-extent 50

    private int _Phase = 0;   // 0 = settle, 1 = push window
    private float _Elapsed = 0.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        // ---- Pair A (PushAndBePushed) at Y = 69000 --------------------------------------------
        // Characters start 130uu from the box face (front of capsule -80 -> face 50) so the 3s walk
        // window has ample margin even if the fixed-step pump lags real time on a loaded machine.
        DoAddStaticFloor(69000.0);
        _BoxATransform = DoAddLightBox(FVector(100.0, 69000.0, 75.0));
        _CharA = DoAddCharacter(FVector(-120.0, 69000.0, 125.0),
            ECk_JoltCharacter_PushPolicy::PushAndBePushed);

        // ---- Pair B (Neither) at Y = 72000 ----------------------------------------------------
        DoAddStaticFloor(72000.0);
        _BoxBTransform = DoAddLightBox(FVector(100.0, 72000.0, 75.0));
        _CharB = DoAddCharacter(FVector(-120.0, 72000.0, 125.0),
            ECk_JoltCharacter_PushPolicy::Neither);
        _CharBTransform = _LastCharTransform;   // stashed by DoAddCharacter (AS value handles)

        utils_timer::Create_Tick(_SelfHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    private void DoAddStaticFloor(float InY)
    {
        auto FloorEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        FloorEntity.Request_OverrideToSelf();
        utils_transform::Add(FloorEntity, FTransform(FRotator::ZeroRotator, FVector(0.0, InY, 0.0)),
            ECk_Replication::DoesNotReplicate);

        auto FloorShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        FloorShape.Set_HalfExtents(FVector(500.0, 500.0, 25.0));
        auto FloorParams = FCk_JoltBody_Spec(ECk_JoltBody_ShapeSource::ExplicitShape);
        FloorParams.Set_ShapeDimensions(FloorShape);
        FloorParams.Set_MotionType(ECk_MotionType::Static);
        utils_jolt_body::Add(FloorEntity, FloorParams);
    }

    private FCk_Handle_Transform DoAddLightBox(FVector InCenter)
    {
        auto BoxEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        BoxEntity.Request_OverrideToSelf();
        auto BoxTransform = utils_transform::Add(BoxEntity, FTransform(FRotator::ZeroRotator, InCenter),
            ECk_Replication::DoesNotReplicate);

        auto BoxShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        BoxShape.Set_HalfExtents(FVector(50.0, 50.0, 50.0));
        auto BoxParams = FCk_JoltBody_Spec(ECk_JoltBody_ShapeSource::ExplicitShape);
        BoxParams.Set_ShapeDimensions(BoxShape);
        BoxParams.Set_MotionType(ECk_MotionType::Dynamic);
        BoxParams.Set_MassSource(ECk_JoltBody_MassSource::Explicit);
        BoxParams.Set_MassKg(1.0);
        BoxParams.Set_SurfaceSource(ECk_JoltBody_SurfaceSource::Explicit);
        BoxParams.Set_Friction(0.2);
        BoxParams.Set_Restitution(0.0);
        utils_jolt_body::Add(BoxEntity, BoxParams);

        return BoxTransform;
    }

    private FCk_Handle_JoltCharacter DoAddCharacter(FVector InCenter, ECk_JoltCharacter_PushPolicy InPolicy)
    {
        auto CharEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        CharEntity.Request_OverrideToSelf();
        _LastCharTransform = utils_transform::Add(CharEntity, FTransform(FRotator::ZeroRotator, InCenter),
            ECk_Replication::DoesNotReplicate);

        auto CharParams = FCk_JoltCharacter_Spec(40.0, 60.0);
        CharParams.Set_PushPolicy(InPolicy);
        CharParams.Set_MaxStrengthNewtons(200.0);
        return utils_jolt_character::Add(CharEntity, CharParams);
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _Elapsed += float(InDeltaT.Get_Seconds());

        // ---- Phase 0: let both pairs finish setup and settle, then start walking --------------
        if (_Phase == 0)
        {
            if (_Elapsed >= 0.5)
            {
                _BoxAStartX = utils_transform::Get_EntityCurrentLocation(_BoxATransform).X;
                _BoxBStartX = utils_transform::Get_EntityCurrentLocation(_BoxBTransform).X;

                utils_jolt_character::Request_Move(_CharA,
                    FCk_Request_JoltCharacter_Move(FVector(_MoveSpeed, 0.0, 0.0)));
                utils_jolt_character::Request_Move(_CharB,
                    FCk_Request_JoltCharacter_Move(FVector(_MoveSpeed, 0.0, 0.0)));

                _Phase = 1;
                _Elapsed = 0.0;
            }
            return;
        }

        // ---- Phase 1: walk into the boxes for 3s, then compare displacement -------------------
        if (_Elapsed < 3.0)
        { return; }

        auto BoxADisplacement = utils_transform::Get_EntityCurrentLocation(_BoxATransform).X - _BoxAStartX;
        auto BoxBDisplacement = utils_transform::Get_EntityCurrentLocation(_BoxBTransform).X - _BoxBStartX;
        auto CharBX = utils_transform::Get_EntityCurrentLocation(_CharBTransform).X;

        // A: the box was pushed clearly forward.
        Assert_True(BoxADisplacement > 20.0,
            f"PushAndBePushed character should displace the box > 20uu (moved {BoxADisplacement}uu)");

        // B: the box did NOT move, and the character was obstructed by it (never walked through).
        Assert_True(Math::Abs(BoxBDisplacement) < 5.0,
            f"Neither-policy character must NOT displace the box (moved {BoxBDisplacement}uu)");
        Assert_True(CharBX < _BoxNearFaceX,
            f"Neither-policy character should stall at the box, not pass through (char X={CharBX}, box near face={_BoxNearFaceX})");

        FinishSuccess();
    }
}
