//============================================================================
// REPLICATION GYM - REPLICATED ACTOR (Scenario A driver)
//============================================================================
// Direct mirror of ABB_Store. Placed in the world by the PlayerController at
// the station transform. In BeginPlay it spawns a replicated entity script
// with ck::TransientEntity() as the lifetime owner, passing itself as the
// WithActor owner. This is the exact shape that currently ensures.
//============================================================================

class ACk_ReplicationGym_ReplicatedActor : AActor
{
    default bReplicateMovement = false;
    default bReplicates = true;
    default bReplicateUsingRegisteredSubObjectList = true;

    UPROPERTY(DefaultComponent, RootComponent)
    USceneComponent RootComponent;

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto SpawnParams = FCk_EntityScript_WithActor_SpawnParams();
        SpawnParams._OwningActor = this;
        auto PendingEntity = utils_entity_script::Request_SpawnEntity(
            ck::TransientEntity(),
            UCk_ReplicationGym_ReplicatedActor_EntityScript,
            SpawnParams);
        utils_pending_entity_script::Promise_OnConstructed(
            PendingEntity, FCk_Delegate_EntityScript_Constructed(this, n"OnEntityConstructed"));
    }

    UFUNCTION()
    private void OnEntityConstructed(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        auto InEntity = FCk_Handle(InEntityScriptHandle);
        InEntity.Set_DebugName(n"ReplicatedActor");
    }
}
