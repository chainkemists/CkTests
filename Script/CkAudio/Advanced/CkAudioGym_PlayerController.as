class ACk_AudioGym_PlayerController : ACk_PlayerController_UE
{
    UPROPERTY()
    FString CurrentMusicTrack = "None";
    UPROPERTY()
    FString CurrentZone = "None";
    UPROPERTY()
    ACk_AudioGym_DebugDisplay DebugDisplay;

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        CreateAudioCues();
        SpawnGymElements();
    }

    void CreateAudioCues()
    {
        // AudioCues are now Angelscript classes that the subsystem auto-discovers
        // No manual setup needed - just execute by name when needed
    }

    UFUNCTION()
    void OnMusicTrackStarted(FCk_Handle_AudioCue InAudioCue, FGameplayTag InTrackName)
    {
        Print(f"🎵 Track Started: {InTrackName.ToString()}", 3.0f);
        CurrentMusicTrack = InTrackName.ToString();

        if (ck::IsValid(DebugDisplay))
        {
            DebugDisplay.UpdateMusic(CurrentMusicTrack);
        }
    }

    void SpawnGymElements()
    {
        // Create 4 separate booths in corners of a square
        // Each booth is 800x800, with 1000 units between centers

        // Booth 1: Ambient Zone (Top-Left)
        SpawnActor(ACk_AudioGym_AmbientZone, FVector(-1000, -1000, 0));
        SpawnActor(ACk_AudioGym_StingerPickup, FVector(-1000, -800, 50));
        SpawnActor(ACk_AudioGym_StingerPickup, FVector(-800, -1000, 50));
        SpawnBoothLabel("AMBIENT MUSIC\nLow Priority (10)\nCrossfade Transitions\n\nCollect stingers to test UI sounds",
            FVector(-1000, -1000, 200), FLinearColor(0.0f, 0.0f, 1.0f));

        // Booth 2: Combat Zone (Top-Right)
        SpawnActor(ACk_AudioGym_CombatZone, FVector(1000, -1000, 0));
        SpawnActor(ACk_AudioGym_StingerPickup, FVector(1000, -800, 50));
        SpawnActor(ACk_AudioGym_StingerPickup, FVector(800, -1000, 50));
        SpawnBoothLabel("COMBAT MUSIC\nHigh Priority (100)\nOverrides other music\n\nFast transitions",
            FVector(1000, -1000, 200), FLinearColor(1.0f, 0.0f, 0.0f));

        // Booth 3: Activity Zone (Bottom-Left)
        SpawnActor(ACk_AudioGym_ActivityZone, FVector(-1000, 1000, 0));
        SpawnActor(ACk_AudioGym_StingerPickup, FVector(-1000, 800, 50));
        SpawnActor(ACk_AudioGym_StingerPickup, FVector(-800, 1000, 50));
        SpawnBoothLabel("ACTIVITY MUSIC\nMedium Priority (90)\nSmooth crossfades\n\nBalanced volume",
            FVector(-1000, 1000, 200), FLinearColor(1.0f, 1.0f, 0.0f));

        // Booth 4: Quiet Zone (Bottom-Right)
        SpawnActor(ACk_AudioGym_QuietZone, FVector(1000, 1000, 0));
        SpawnActor(ACk_AudioGym_StingerPickup, FVector(1000, 800, 50));
        SpawnActor(ACk_AudioGym_StingerPickup, FVector(800, 1000, 50));
        SpawnBoothLabel("QUIET ZONE\nStops all music\nSilence for testing\n\nEnter to mute audio",
            FVector(1000, 1000, 200), FLinearColor(0.0f, 1.0f, 0.0f));

        // Center area: Controls and spatial audio
        SpawnActor(ACk_AudioGym_ControlPanel, FVector(0, 0, 0));
        SpawnActor(ACk_AudioGym_MovingAudioSource, FVector(0, -300, 100));
        SpawnBoothLabel("CONTROL PANEL\nWalk into to cycle options\nManual audio testing",
            FVector(0, 0, 100), FLinearColor(1.0f, 0.0f, 1.0f));
        SpawnBoothLabel("3D SPATIAL AUDIO\nOrbiting sound source\nTest 3D positioning",
            FVector(0, -300, 200), FLinearColor(1.0f, 0.65f, 0.0f));

        // Pathway stingers between booths
        SpawnActor(ACk_AudioGym_StingerPickup, FVector(0, -1000, 50));  // Top center
        SpawnActor(ACk_AudioGym_StingerPickup, FVector(0, 1000, 50));   // Bottom center
        SpawnActor(ACk_AudioGym_StingerPickup, FVector(-1000, 0, 50));  // Left center
        SpawnActor(ACk_AudioGym_StingerPickup, FVector(1000, 0, 50));   // Right center

        // Spawn debug display
        DebugDisplay = Cast<ACk_AudioGym_DebugDisplay>(SpawnActor(ACk_AudioGym_DebugDisplay, FVector(0, 0, 500)));
    }

    void SpawnBoothLabel(const FString& Text, FVector Location, FLinearColor Color)
    {
        auto TextActor = Cast<ATextRenderActor>(SpawnActor(ATextRenderActor, Location));
        if (ck::IsValid(TextActor))
        {
            auto TextComponent = TextActor.TextRender;
            if (ck::IsValid(TextComponent))
            {
                TextComponent.Text = ck::Text(Text);
                TextComponent.TextRenderColor = Color.ToFColor(true);
                TextComponent.HorizontalAlignment = EHorizTextAligment::EHTA_Center;
                TextComponent.VerticalAlignment = EVerticalTextAligment::EVRTA_TextCenter;
                TextComponent.SetWorldSize(48.0f);
            }
        }
    }

    UFUNCTION()
    void OnEnteredZone(const FString& ZoneName, FGameplayTag MusicTag)
    {
        CurrentZone = ZoneName;
        ck::Trace(f"Zone: {ZoneName}", n"AudioGym_Zone", 0.0f, FLinearColor(1.0f, 1.0f, 0.0f));

        if (ck::IsValid(DebugDisplay))
        {
            DebugDisplay.UpdateZone(ZoneName);
        }

        // Determine which cue to play based on the music tag
        auto ContextEntity = ck::SelfEntity(this);

        if (MusicTag == utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Music.Ambient"))
        {
            utils_cue::Request_Execute_Local(ContextEntity,
                utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Music.Ambient"),
                FInstancedStruct());
            ck::Trace("Music: Ambient", n"AudioGym_Music", 0.0f, FLinearColor(0.0f, 1.0f, 1.0f));
        }
        else if (MusicTag == utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Music.Combat"))
        {
            utils_cue::Request_Execute_Local(ContextEntity,
                utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Music.Combat"),
                FInstancedStruct());
            ck::Trace("Music: Combat", n"AudioGym_Music", 0.0f, FLinearColor(1.0f, 0.0f, 0.0f));
        }
        else if (MusicTag == utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Music.Activity"))
        {
            utils_cue::Request_Execute_Local(ContextEntity,
                utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Music.Activity"),
                FInstancedStruct());
            ck::Trace("Music: Activity", n"AudioGym_Music", 0.0f, FLinearColor(1.0f, 1.0f, 0.0f));
        }
    }

    void OnExitedZone(const FString& ZoneName)
    {
        if (CurrentZone == ZoneName)
        {
            CurrentZone = "None";
            ck::Trace("Zone: None", n"AudioGym_Zone", 0.0f, FLinearColor(0.5f, 0.5f, 0.5f));

            if (ck::IsValid(DebugDisplay))
            {
                DebugDisplay.UpdateZone("None");
            }

            StopAllMusic();
        }
    }

    UFUNCTION()
    void OnStingerTriggered(FGameplayTag StingerTag)
    {
        auto ContextEntity = ck::SelfEntity(this);
        utils_cue::Request_Execute_Local(ContextEntity,
            utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Stingers.UI"),
            FInstancedStruct());

        ck::Trace(f"Stinger: {StingerTag.ToString()}", n"AudioGym_Stinger", 3.0f, FLinearColor(1.0f, 0.5f, 0.0f));

        if (ck::IsValid(DebugDisplay))
        {
            DebugDisplay.UpdateStinger(StingerTag.ToString());
        }
    }

    void StartAmbientMusic()
    {
        auto ContextEntity = ck::SelfEntity(this);
        utils_cue::Request_Execute_Local(ContextEntity,
            utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Music.Ambient"),
            FInstancedStruct());

        CurrentMusicTrack = "Ambient";
        if (ck::IsValid(DebugDisplay))
        {
            DebugDisplay.UpdateMusic("Ambient");
        }
    }

    UFUNCTION(Exec, DisplayName="AudioGym - Start Combat Music")
    void StartCombatMusic()
    {
        auto ContextEntity = ck::SelfEntity(this);
        utils_cue::Request_Execute_Local(ContextEntity,
            utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Music.Combat"),
            FInstancedStruct());

        CurrentMusicTrack = "Combat";
        if (ck::IsValid(DebugDisplay))
        {
            DebugDisplay.UpdateMusic("Combat");
        }
    }

    void StopAllMusic()
    {
        // Note: With the Cue system, stopping all music would need to be handled
        // by the individual AudioCue implementations or through a separate mechanism
        // For now, we could execute a "stop all" cue or handle this differently

        CurrentMusicTrack = "None";
        ck::Trace("Music: None", n"AudioGym_Music", 0.0f, FLinearColor(0.5f, 0.5f, 0.5f));

        if (ck::IsValid(DebugDisplay))
        {
            DebugDisplay.UpdateMusic("None");
        }
    }

    UFUNCTION(Exec, DisplayName="AudioGym - Play Test Stinger")
    void PlayTestStinger()
    {
        OnStingerTriggered(utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Stingers.UI.Interface"));
    }
};