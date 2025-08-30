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

        Print("Simple AudioCue Gym Started - Background music and spatial audio should be playing", 5.0f);
    }

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        // Don't start audio immediately - wait for ECS setup
        Print("Simple AudioCue Gym - Waiting for ECS setup...", 3.0f);
    }

    void StartBackgroundMusic()
    {
        auto CueReplicatorSubsystem = Subsystem::GetWorldSubsystem(UCk_CueExecutor_Subsystem_Base_UE);
        if (!ck::IsValid(CueReplicatorSubsystem))
        {
            Print("❌ Background Music - No CueReplicator subsystem found", 3.0f);
            return;
        }

        CueReplicatorSubsystem.Request_ExecuteCue_Local(ck::SelfEntity(this),
            utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Simple.BackgroundMusic"),
            FInstancedStruct());

        Print("🎵 Background Music AudioCue Executed via Subsystem", 3.0f);
    }

    void StartSpatialAudio()
    {
        auto CueReplicatorSubsystem = Subsystem::GetWorldSubsystem(UCk_CueExecutor_Subsystem_Base_UE);
        if (!ck::IsValid(CueReplicatorSubsystem))
        {
            Print("❌ Spatial Audio - No CueReplicator subsystem found", 3.0f);
            return;
        }

        CueReplicatorSubsystem.Request_ExecuteCue_Local(ck::SelfEntity(this),
            utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Simple.SpatialAudio"),
            FInstancedStruct());

        Print("🔊 Spatial Audio AudioCue Executed via Subsystem", 3.0f);
    }

    UFUNCTION(Exec, DisplayName="Simple AudioGym - Restart Background Music")
    void RestartBackgroundMusic()
    {
        StartBackgroundMusic();
    }

    UFUNCTION(Exec, DisplayName="Simple AudioGym - Trigger Spatial Audio")
    void TriggerSpatialAudio()
    {
        StartSpatialAudio();
    }
}