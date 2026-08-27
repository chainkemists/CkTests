// Language=angelscript

//============================================================================
// CK HOMING - AUTOMATION TEST: ENABLE/DISABLE TOGGLES STEERING
//============================================================================
//
// Homing is added with StartingState=Disable. Setting a target while disabled
// must NOT activate steering. Request_EnableDisable(Enable) activates it
// (the target was retained), and a subsequent Disable deactivates it again
// after which the projectile flies dead straight.
//============================================================================

class UCk_AutoTest_Homing_EnableDisable_TogglesSteering : UCk_AutoTest_Base
{
    private FCk_Handle _SelfHandle;
    private FCk_Handle_Transform _ProjectileTransform;
    private FCk_Handle_Homing _Homing;

    private int32 _Phase = 0;
    private int32 _PhaseTicks = 0;
    private bool _HasReferenceDirection = false;
    private FVector _ReferenceDirection;
    private FVector _PreviousLocation;
    private int32 _StraightTicks = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        auto Projectile = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _ProjectileTransform = utils_transform::Add(Projectile, FTransform(), ECk_Replication::DoesNotReplicate);

        auto ProjectileParams = FCk_Fragment_Projectile_ParamsData(
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector(600.0, 0.0, 0.0)),
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            FCk_Fragment_AutoReorient_ParamsData(ECk_AutoReorient_Policy::NoAutoReorient));
        utils_projectile::Add(Projectile, ProjectileParams, ECk_Replication::DoesNotReplicate);

        auto HomingParams = FCk_Fragment_Homing_ParamsData(FCk_Homing_GuidanceSettings(3000.0));
        HomingParams.Set_StartingState(ECk_EnableDisable::Disable);

        _Homing = utils_homing::Add(Projectile, HomingParams);

        utils_homing::Request_SetTargetEntity(_Homing, FCk_Request_Homing_SetTargetEntity(
            CreateTarget(FVector(2000.0, 1500.0, 0.0))));

        utils_timer::Create_Tick(_SelfHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    private FCk_Handle CreateTarget(FVector InLocation)
    {
        auto Target = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        utils_transform::Add(Target,
            FTransform(FRotator::ZeroRotator, InLocation, FVector::OneVector), ECk_Replication::DoesNotReplicate);
        return Target;
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _PhaseTicks++;

        if (_Phase == 0)
        {
            // Setting a target while disabled must not activate homing
            if (_PhaseTicks < 5) { return; }

            Assert_True(!utils_homing::Get_IsActive(_Homing),
                "Homing must stay inactive when a target is set while disabled");
            Assert_True(utils_homing::Get_TargetMode(_Homing) == ECk_Homing_TargetMode::Entity,
                "The target set while disabled should be retained");

            utils_homing::Request_EnableDisable(_Homing,
                FCk_Request_Homing_EnableDisable(ECk_EnableDisable::Enable));

            _Phase = 1;
            _PhaseTicks = 0;
            return;
        }

        if (_Phase == 1)
        {
            // Enable with a retained target must activate steering
            if (!utils_homing::Get_IsActive(_Homing))
            {
                Assert_True(_PhaseTicks < 60, "Homing should activate within a few frames of Enable");
                return;
            }

            utils_homing::Request_EnableDisable(_Homing,
                FCk_Request_Homing_EnableDisable(ECk_EnableDisable::Disable));

            _Phase = 2;
            _PhaseTicks = 0;
            return;
        }

        // Phase 2 - settle the disable, then the flight direction must never change again
        if (_PhaseTicks <= 2)
        {
            _PreviousLocation = utils_transform::Get_EntityCurrentLocation(_ProjectileTransform);
            return;
        }

        Assert_True(!utils_homing::Get_IsActive(_Homing),
            "Homing must be inactive after Disable");

        auto Location = utils_transform::Get_EntityCurrentLocation(_ProjectileTransform);
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
            "Movement direction should stay constant while homing is disabled");

        _StraightTicks++;

        if (_StraightTicks >= 8)
        {
            FinishSuccess();
        }
    }
}
