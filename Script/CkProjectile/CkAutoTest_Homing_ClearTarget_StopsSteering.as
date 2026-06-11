// Language=angelscript

//============================================================================
// CK HOMING — AUTOMATION TEST: CLEAR TARGET STOPS STEERING
//============================================================================
//
// A projectile steers toward a lateral homing point (proving guidance bends
// its path), then the target is cleared. From that moment the projectile must
// fly dead straight: homing restores the base acceleration (zero here) and
// stops touching the velocity. Verified by checking that the movement
// direction stays constant across several frames after the clear.
//============================================================================

class UCk_AutoTest_Homing_ClearTarget_StopsSteering : UCk_AutoTest_Base
{
    private FCk_Handle_Transform _ProjectileTransform;
    private FCk_Handle_Homing _Homing;

    private bool _TargetCleared = false;
    private int32 _SettleTicksAfterClear = 0;
    private bool _HasReferenceDirection = false;
    private FVector _ReferenceDirection;
    private FVector _PreviousLocation;
    private int32 _StraightTicks = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto Projectile = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        _ProjectileTransform = utils_transform::Add(Projectile, FTransform(), ECk_Replication::DoesNotReplicate);

        auto ProjectileParams = FCk_Fragment_Projectile_ParamsData(
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector(600.0, 0.0, 0.0)),
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            FCk_Fragment_AutoReorient_ParamsData(ECk_AutoReorient_Policy::NoAutoReorient));
        utils_projectile::Add(Projectile, ProjectileParams, ECk_Replication::DoesNotReplicate);

        _Homing = utils_homing::Add(Projectile,
            FCk_Fragment_Homing_ParamsData(FCk_Homing_GuidanceSettings(3000.0)));

        utils_homing::Request_SetTargetLocation(_Homing,
            FCk_Request_Homing_SetTargetLocation(FVector(1000.0, 1000.0, 0.0)));

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Location = utils_transform::Get_EntityCurrentLocation(_ProjectileTransform);

        // Phase 1 — wait until guidance has visibly bent the path, then clear the target
        if (!_TargetCleared)
        {
            if (Location.Y > 50.0)
            {
                utils_homing::Request_ClearTarget(_Homing);
                _TargetCleared = true;
                _PreviousLocation = Location;
            }

            return;
        }

        // Phase 2 — let the clear request and the base-acceleration restore settle
        if (_SettleTicksAfterClear < 2)
        {
            _SettleTicksAfterClear++;
            _PreviousLocation = Location;
            return;
        }

        // Phase 3 — direction must not change anymore
        auto Delta = Location - _PreviousLocation;
        _PreviousLocation = Location;

        if (Delta.Size() < 1.0)
        { return; }

        auto Direction = Delta.GetSafeNormal();

        if (!_HasReferenceDirection)
        {
            _ReferenceDirection = Direction;
            _HasReferenceDirection = true;
            return;
        }

        Assert_True(_ReferenceDirection.DotProduct(Direction) > 0.999,
            "Movement direction should stay constant after ClearTarget");

        _StraightTicks++;

        if (_StraightTicks >= 8)
        {
            Assert_True(!utils_homing::Get_IsActive(_Homing),
                "Homing should not be active after ClearTarget");
            Assert_True(utils_homing::Get_TargetMode(_Homing) == ECk_Homing_TargetMode::None,
                "Target mode should be None after ClearTarget");

            FinishSuccess();
        }
    }
}
