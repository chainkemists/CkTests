// Language=angelscript

//============================================================================
// CK JOLT - AUTOMATION TEST: CHARACTER REPORTS GROUND-STATE TRANSITIONS
//============================================================================
//
// OnGroundStateChanged must fire on the real ground-state edges:
//
//   1. Character spawned in the air above a Static floor -> it falls and the
//      InAir -> OnGround landing edge raises a ground-state signal carrying OnGround.
//   2. Request_Jump (consumed once the character is supported) -> a transition AWAY
//      from OnGround (airborne), then the fall raises another OnGround landing edge.
//
// Ground state is a mirror updated by the game-thread apply pass, so this drives the
// sequence off the SIGNAL edges (not same-frame polling); a tick only confirms the
// character was genuinely airborne before the first landing and guards the budget.
//
// Placed at an isolated Y so it never touches other autotests' physics bodies.
//============================================================================

class UCk_AutoTest_CkJolt_JoltCharacter_ReportsGroundStateTransitions : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_JoltCharacter _Char;

    private float _ParkY = 66000.0;
    private float _JumpVelocity = 500.0;

    // 0 = airborne, waiting for first landing; 1 = jumped, waiting to leave OnGround;
    // 2 = airborne after jump, waiting to land again.
    private int _Phase = 0;
    private bool _ConfirmedAirborne = false;
    private float _Elapsed = 0.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        // ---- Static floor ---------------------------------------------------------------------
        auto FloorEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        FloorEntity.Request_OverrideToSelf();
        utils_transform::Add(FloorEntity, FTransform(FRotator::ZeroRotator, FVector(0.0, _ParkY, 0.0)),
            ECk_Replication::DoesNotReplicate);

        auto FloorShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        FloorShape.Set_HalfExtents(FVector(500.0, 500.0, 25.0));
        auto FloorParams = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        FloorParams.Set_ShapeDimensions(FloorShape);
        FloorParams.Set_MotionType(ECk_MotionType::Static);
        utils_jolt_body::Add(FloorEntity, FloorParams);

        // ---- Character spawned ~300uu above its rest height (clearly airborne) -----------------
        auto CharStart = FVector(0.0, _ParkY, 425.0);   // rest centre would be 125; +300 in the air
        auto CharEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        CharEntity.Request_OverrideToSelf();
        utils_transform::Add(CharEntity, FTransform(FRotator::ZeroRotator, CharStart),
            ECk_Replication::DoesNotReplicate);

        auto CharParams = FCk_Fragment_JoltCharacter_ParamsData(40.0, 60.0);
        _Char = utils_jolt_character::Add(CharEntity, CharParams);

        utils_jolt_character::BindTo_OnJoltCharacterGroundStateChanged(_Char,
            FCk_Delegate_JoltCharacter_OnGroundStateChanged(this, n"OnGroundChanged"));

        utils_timer::Create_Tick(_SelfHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnGroundChanged(FCk_Handle_JoltCharacter InHandle, ECk_JoltCharacter_GroundState InState)
    {
        if (IsFinished()) { return; }

        if (_Phase == 0)
        {
            // First landing after spawning airborne: the OnGround edge IS the InAir->OnGround transition.
            if (InState == ECk_JoltCharacter_GroundState::OnGround && _ConfirmedAirborne)
            {
                _Phase = 1;
                utils_jolt_character::Request_Jump(_Char, FCk_Request_JoltCharacter_Jump(_JumpVelocity));
            }
            return;
        }

        if (_Phase == 1)
        {
            // The jump must move the character off the ground.
            if (InState != ECk_JoltCharacter_GroundState::OnGround)
            { _Phase = 2; }
            return;
        }

        // Phase 2 - the jump arc must land the character back OnGround.
        if (InState == ECk_JoltCharacter_GroundState::OnGround)
        { FinishSuccess(); }
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _Elapsed += float(InDeltaT.Get_Seconds());

        if (_Phase == 0)
        {
            auto GroundState = utils_jolt_character::Get_GroundState(_Char);
            if (GroundState == ECk_JoltCharacter_GroundState::InAir ||
                GroundState == ECk_JoltCharacter_GroundState::NotSupported)
            { _ConfirmedAirborne = true; }

            if (_Elapsed > 10.0)
            { FinishFailure(f"Character never landed from its airborne spawn (airborneConfirmed={_ConfirmedAirborne})"); }

            return;
        }

        if (_Elapsed > 20.0)
        { FinishFailure(f"Jump ground-state cycle did not complete (phase={_Phase})"); }
    }
}
