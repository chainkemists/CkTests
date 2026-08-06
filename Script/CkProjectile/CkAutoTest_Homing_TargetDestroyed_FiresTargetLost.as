// Language=angelscript

//============================================================================
// CK HOMING — AUTOMATION TEST: TARGET DESTROYED FIRES TARGET LOST
//============================================================================
//
// A projectile is homing on a target entity that gets destroyed mid-flight.
// The Homing processor must broadcast OnTargetLost and deactivate itself
// instead of silently chasing a dead handle.
//============================================================================

class UCk_AutoTest_Homing_TargetDestroyed_FiresTargetLost : UCk_AutoTest_Base
{
    private FCk_Handle _Target;
    private FCk_Handle_Homing _Homing;
    private bool _TargetDestroyed = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto Projectile = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        utils_transform::Add(Projectile, FTransform(), ECk_Replication::DoesNotReplicate);

        auto ProjectileParams = FCk_Projectile_Spec(
            FCk_Velocity_Spec(ECk_LocalWorld::World, FVector(600.0, 0.0, 0.0)),
            FCk_Acceleration_Spec(ECk_LocalWorld::World, FVector::ZeroVector),
            FCk_AutoReorient_Spec(ECk_AutoReorient_Policy::NoAutoReorient));
        utils_projectile::Add(Projectile, ProjectileParams, ECk_Replication::DoesNotReplicate);

        _Homing = utils_homing::Add(Projectile,
            FCk_Homing_Spec(FCk_Homing_GuidanceSettings(2000.0)));

        _Target = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        utils_transform::Add(_Target,
            FTransform(FRotator::ZeroRotator, FVector(3000.0, 0.0, 0.0), FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        utils_homing::BindTo_OnTargetLost(_Homing, FCk_Delegate_Homing_OnTargetLost(this, n"OnTargetLost"));

        utils_homing::Request_SetTargetEntity(_Homing, FCk_Request_Homing_SetTargetEntity(_Target));

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        if (_TargetDestroyed) { return; }

        // Wait until homing is established, then rip the target away
        if (utils_homing::Get_IsActive(_Homing))
        {
            _TargetDestroyed = true;
            utils_entity_lifetime::Request_DestroyEntity(_Target);
        }
    }

    UFUNCTION()
    private void OnTargetLost(FCk_Handle_Homing InHandle, FCk_Homing_Payload_OnTargetLost InPayload)
    {
        if (IsFinished()) { return; }

        Assert_True(_TargetDestroyed,
            "OnTargetLost should only fire after the target entity was destroyed");
        Assert_True(!utils_homing::Get_IsActive(_Homing),
            "Homing should deactivate when its target is lost");
        Assert_True(utils_homing::Get_TargetMode(_Homing) == ECk_Homing_TargetMode::None,
            "Target mode should reset to None when the target is lost");

        FinishSuccess();
    }
}
