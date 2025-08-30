UCLASS()
class ACk_Gym_Base_Pawn : ADefaultPawn
{
    UPROPERTY(DefaultComponent)
    UCk_EntityBridge_ActorComponent_UE EntityBridge;
    default EntityBridge._Replication = ECk_Replication::Replicates;
    default EntityBridge._ConstructionScript = UCk_Entity_ConstructionScript_WithTransform_PDA;

    UFUNCTION(BlueprintOverride)
    void ConstructionScript()
    {
        EntityBridge._OnReplicationComplete_MC.AddUFunction(this, n"OnReplicationComplete");
    }

    UFUNCTION()
    void OnReplicationComplete(FCk_Handle InEntity)
    {
        // Standard pawn setup - can be extended by derived classes
        ck::Trace("Gym pawn entity setup complete");
        Request_OnPawnReady();
    }

    // Override this in derived gym classes if custom pawn behavior is needed
    void Request_OnPawnReady()
    {
        // Base implementation does nothing - gyms typically handle logic in PlayerController
    }
}