// Language=angelscript

//============================================================================
// CK HOMING — AUTOMATION TEST: RETARGET SWITCHES PURSUIT
//============================================================================
//
// The projectile first closes on target A. Mid-flight, a second
// Request_SetTargetEntity switches it to target B on the opposite flank —
// the guidance state must reset cleanly (no stale miss latch or velocity
// history) and the distance to B must then shrink to half of what it was at
// the moment of the switch.
//============================================================================

class UCk_AutoTest_Homing_Retarget_SwitchesPursuit : UCk_AutoTest_Base
{
    private FCk_Handle _SelfHandle;
    private FCk_Handle_Transform _ProjectileTransform;
    private FCk_Handle _TargetA;
    private FCk_Handle _TargetB;
    private FCk_Handle_Transform _TargetATransform;
    private FCk_Handle_Transform _TargetBTransform;
    private FCk_Handle_Homing _Homing;

    private bool _Retargeted = false;
    private float _DistanceToBAtSwitch = 0.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        auto Projectile = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _ProjectileTransform = utils_transform::Add(Projectile, FTransform(), ECk_Replication::DoesNotReplicate);

        auto ProjectileParams = FCk_Projectile_Spec(
            FCk_Velocity_Spec(ECk_LocalWorld::World, FVector(600.0, 0.0, 0.0)),
            FCk_Acceleration_Spec(ECk_LocalWorld::World, FVector::ZeroVector),
            FCk_AutoReorient_Spec(ECk_AutoReorient_Policy::NoAutoReorient));
        utils_projectile::Add(Projectile, ProjectileParams, ECk_Replication::DoesNotReplicate);

        _Homing = utils_homing::Add(Projectile,
            FCk_Homing_Spec(FCk_Homing_GuidanceSettings(3000.0)));

        _TargetA = CreateTarget(FVector(2000.0, 1500.0, 0.0), _TargetATransform);
        _TargetB = CreateTarget(FVector(2000.0, -1500.0, 0.0), _TargetBTransform);

        utils_homing::Request_SetTargetEntity(_Homing, FCk_Request_Homing_SetTargetEntity(_TargetA));

        utils_timer::Create_Tick(_SelfHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    private FCk_Handle CreateTarget(FVector InLocation, FCk_Handle_Transform&out OutTransform)
    {
        auto Target = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        OutTransform = utils_transform::Add(Target,
            FTransform(FRotator::ZeroRotator, InLocation, FVector::OneVector), ECk_Replication::DoesNotReplicate);
        return Target;
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto ProjectileLocation = utils_transform::Get_EntityCurrentLocation(_ProjectileTransform);

        if (!_Retargeted)
        {
            auto DistanceToA = ProjectileLocation.Distance(utils_transform::Get_EntityCurrentLocation(_TargetATransform));

            // Wait until the pursuit of A is clearly established, then switch to B
            if (DistanceToA < 1500.0)
            {
                _DistanceToBAtSwitch = ProjectileLocation.Distance(utils_transform::Get_EntityCurrentLocation(_TargetBTransform));

                utils_homing::Request_SetTargetEntity(_Homing, FCk_Request_Homing_SetTargetEntity(_TargetB));
                _Retargeted = true;
            }

            return;
        }

        if (ProjectileLocation.Distance(utils_transform::Get_EntityCurrentLocation(_TargetBTransform)) < _DistanceToBAtSwitch * 0.5)
        {
            Assert_True(utils_homing::Get_TargetEntity(_Homing) == _TargetB,
                "The pursued entity should be target B after the retarget");
            Assert_True(utils_homing::Get_IsActive(_Homing),
                "Homing should remain active across a retarget");

            FinishSuccess();
        }
    }
}
