UCLASS()
class ACk_Gym_Base_Pawn : ADefaultPawn
{
    default Replicates = true;

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        if (HasAuthority())
        {
            auto SpawnParams = FCk_EntityScript_WithActor_SpawnParams();
            SpawnParams._OwningActor = this;
            auto PendingEntity = utils_entity_script::Request_SpawnEntity(
                ck::TransientEntity(), UCk_EntityScript_WithActor_UE, SpawnParams);
            utils_pending_entity_script::Promise_OnConstructed(
                PendingEntity, FCk_Delegate_EntityScript_Constructed(this, n"OnEntityConstructed"));
        }
    }

    UFUNCTION()
    void OnEntityConstructed(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        ck::Trace("Gym pawn entity setup complete");
        Request_OnPawnReady();
    }

    // Override this in derived gym classes if custom pawn behavior is needed
    void Request_OnPawnReady()
    {
        // Base implementation does nothing - gyms typically handle logic in PlayerController
    }
}
