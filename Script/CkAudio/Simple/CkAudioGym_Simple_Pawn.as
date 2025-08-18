UCLASS()
class ACk_AudioGym_Simple_Pawn : ADefaultPawn
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
        // Minimal pawn setup - just needs entity bridge for framework integration
    }
}