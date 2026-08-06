// Language=angelscript

//============================================================================
// CK HOMING — AUTOMATION TEST: ADD ATTACHES FEATURE
//============================================================================
//
// Verifies utils_homing::Add on a projectile-equipped entity:
//   1. Has is false before Add and true after.
//   2. Homing starts dormant — no target, not active.
//   3. The typed handle round-trips through the getters.
//============================================================================

class UCk_AutoTest_Homing_Add_AttachesFeature : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto Projectile = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        utils_transform::Add(Projectile, FTransform(), ECk_Replication::DoesNotReplicate);

        Assert_True(!utils_homing::Has(Projectile),
            "Entity should not have the Homing feature before Add");

        auto ProjectileParams = FCk_Projectile_Spec(
            FCk_Velocity_Spec(ECk_LocalWorld::World, FVector(600.0, 0.0, 0.0)),
            FCk_Acceleration_Spec(ECk_LocalWorld::World, FVector::ZeroVector),
            FCk_AutoReorient_Spec(ECk_AutoReorient_Policy::NoAutoReorient));
        utils_projectile::Add(Projectile, ProjectileParams, ECk_Replication::DoesNotReplicate);

        auto HomingParams = FCk_Homing_Spec(FCk_Homing_GuidanceSettings(2000.0));
        auto Homing = utils_homing::Add(Projectile, HomingParams);

        Assert_True(utils_homing::Has(Projectile),
            "Entity should have the Homing feature after Add");
        Assert_True(!utils_homing::Get_IsActive(Homing),
            "Homing should be dormant until a target is set");
        Assert_True(utils_homing::Get_TargetMode(Homing) == ECk_Homing_TargetMode::None,
            "Target mode should be None until a target is set");
        Assert_True(!utils_handle::Get_IsValid(utils_homing::Get_TargetEntity(Homing)),
            "Target entity should be invalid until a target is set");

        FinishSuccess();
    }
}
