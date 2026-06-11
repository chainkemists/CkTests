// Language=angelscript

//============================================================================
// CK HOMING — AUTOMATION TEST: MISSED TARGET FIRES SIGNAL
//============================================================================
//
// A projectile with NO steering budget (MaxAcceleration = 0) flies straight
// past a homing point sitting 200 units off its path. The moment it stops
// closing and starts receding inside the miss-notify threshold,
// OnTargetMissed must fire — with the closest-approach distance in the
// payload.
//============================================================================

class UCk_AutoTest_Homing_MissedTarget_FiresSignal : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto Projectile = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        utils_transform::Add(Projectile, FTransform(), ECk_Replication::DoesNotReplicate);

        auto ProjectileParams = FCk_Fragment_Projectile_ParamsData(
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector(600.0, 0.0, 0.0)),
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            FCk_Fragment_AutoReorient_ParamsData(ECk_AutoReorient_Policy::NoAutoReorient));
        utils_projectile::Add(Projectile, ProjectileParams, ECk_Replication::DoesNotReplicate);

        auto HomingParams = FCk_Fragment_Homing_ParamsData(FCk_Homing_GuidanceSettings(0.0));
        HomingParams.Set_MissNotifyDistanceThreshold(500.0);

        auto Homing = utils_homing::Add(Projectile, HomingParams);

        utils_homing::BindTo_OnTargetMissed(Homing, FCk_Delegate_Homing_OnTargetMissed(this, n"OnTargetMissed"));

        utils_homing::Request_SetTargetLocation(Homing,
            FCk_Request_Homing_SetTargetLocation(FVector(300.0, 200.0, 0.0)));
    }

    UFUNCTION()
    private void OnTargetMissed(FCk_Handle_Homing InHandle, FCk_Homing_Payload_OnTargetMissed InPayload)
    {
        if (IsFinished()) { return; }

        Assert_True(InPayload.Get_MissDistance() > 0.0,
            "Miss distance should be positive at the closest-approach flip");
        Assert_True(InPayload.Get_MissDistance() < 500.0,
            "Miss must only be reported inside the miss-notify threshold");

        FinishSuccess();
    }
}
