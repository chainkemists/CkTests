// Language=angelscript

//============================================================================
// CK PROJECTILE — AUTOMATION TEST: ADD ATTACHES VELOCITY + ACCELERATION
//============================================================================
//
// First-coverage seed for CkProjectile. Projectile Add is a compound
// operation: it Adds Velocity + Acceleration + AutoReorient on the
// owning entity, then kicks off the Euler integrator and reorient
// systems. Without a Projectile Has accessor, the seed verifies the
// observable side-effect: after Add, both Velocity and Acceleration
// Has report true on the entity.
//
// The hit-detection and OnRangeExpired paths need a configured
// physics world and OverlapBody scaffolding and are deferred.
//============================================================================

class UCk_AutoTest_Projectile_Add_AttachesVelocityAndAcceleration : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private ACkAutoTest_ActorEntity_Helper _Helper;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Helper = Cast<ACkAutoTest_ActorEntity_Helper>(SpawnActor(
            ACkAutoTest_ActorEntity_Helper, FVector::ZeroVector, FRotator::ZeroRotator));
        if (ck::Is_NOT_Valid(_Helper))
        {
            FinishFailure("Failed to spawn ActorEntity helper");
            return;
        }

        utils_pending_entity_script::Promise_OnConstructed(
            _Helper.PendingEntity,
            FCk_Delegate_EntityScript_Constructed(this, n"OnEntityReady"));
    }

    UFUNCTION()
    private void OnEntityReady(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        if (IsFinished()) { return; }

        auto OwnedEntity = FCk_Handle(InEntityScriptHandle);

        auto VelocityParams = FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector(50.0f, 0.0f, 0.0f));
        auto AccelerationParams = FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector(0.0f, 0.0f, -980.0f));
        auto AutoReorientParams = FCk_Fragment_AutoReorient_ParamsData(ECk_AutoReorient_Policy::NoAutoReorient);

        auto ProjectileParams = FCk_Fragment_Projectile_ParamsData(VelocityParams, AccelerationParams, AutoReorientParams);
        utils_projectile::Add(OwnedEntity, ProjectileParams, ECk_Replication::DoesNotReplicate);

        Assert_True(utils_velocity::Has(OwnedEntity),
            "After Projectile Add, the entity must have a Velocity feature");
        Assert_True(utils_acceleration::Has(OwnedEntity),
            "After Projectile Add, the entity must have an Acceleration feature");

        FinishSuccess();
    }
}
