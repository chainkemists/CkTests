class ACk_AudioGym_Simple_PlayerController : ACk_PlayerController_UE
{
    UPROPERTY(DefaultComponent)
    UCk_EntityBridge_ActorComponent_UE EntityBridge;
    default EntityBridge._Replication = ECk_Replication::DoesNotReplicate;
    default EntityBridge._ConstructionScript = UCk_Entity_ConstructionScript_WithTransform_PDA;

    UFUNCTION(BlueprintOverride)
    void ConstructionScript()
    {
        EntityBridge._OnReplicationComplete_MC.AddUFunction(this, n"OnReplicationComplete");
    }

    UFUNCTION()
    void OnReplicationComplete(FCk_Handle InEntity)
    {
        // Entity is now ready - start audio after ECS setup
        StartBackgroundMusic();
        StartSpatialAudio();
    }

    void StartBackgroundMusic()
    {
        utils_cue_executor::Request_ExecuteCue_Local(ck::SelfEntity(this),
            utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Simple.BackgroundMusic"),
            FAudioCueTransform(FTransform(FVector(90.000000,900.000000,0.000000))));
    }

    void StartSpatialAudio()
    {
        utils_cue_executor::Request_ExecuteCue_Local(ck::SelfEntity(this),
            utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Simple.SpatialAudio"),
            FAudioCueTransform(FTransform(FVector(90.000000, 700.000000,100.000000))));
    }

    UFUNCTION(Exec, DisplayName="Simple AudioGym - Restart Background Music")
    void Ck_Gyms_RestartBackgroundMusic()
    {
        StartBackgroundMusic();
    }

    UFUNCTION(Exec, DisplayName="Simple AudioGym - Trigger Spatial Audio")
    void Ck_Gyms_TriggerSpatialAudio()
    {
        StartSpatialAudio();
    }
}