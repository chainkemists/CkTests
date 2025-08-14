// World-based debug display for audio system
UCLASS()
class ACk_AudioGym_DebugDisplay : AActor
{
    UPROPERTY(DefaultComponent)
    USceneComponent Root;

    UPROPERTY(DefaultComponent)
    UCk_EntityBridge_ActorComponent_UE EntityBridge;
    default EntityBridge._Replication = ECk_Replication::DoesNotReplicate;
    default EntityBridge._ConstructionScript = UCk_Entity_ConstructionScript_WithTransform_PDA;

    UPROPERTY()
    FString CurrentZone = "None";
    UPROPERTY()
    FString CurrentMusic = "None";
    UPROPERTY()
    FString LastStinger = "None";
    UPROPERTY()
    float LastStingerTime = 0.0f;
    UPROPERTY()
    TArray<FString> ActiveTracks;

    UFUNCTION(BlueprintOverride)
    void ConstructionScript()
    {
        EntityBridge._OnReplicationComplete_MC.AddUFunction(this, n"OnReplicationComplete");
    }

    UFUNCTION()
    void OnReplicationComplete(FCk_Handle InEntity)
    {
        utils_transform::Add(InEntity, GetActorTransform(), ECk_Replication::DoesNotReplicate);
    }

    UFUNCTION(BlueprintOverride)
    void Tick(float DeltaTime)
    {
        DrawWorldDebugPanel();
    }

    void UpdateZone(const FString& Zone)
    {
        CurrentZone = Zone;
    }

    void UpdateMusic(const FString& Music)
    {
        CurrentMusic = Music;
    }

    void UpdateStinger(const FString& Stinger)
    {
        LastStinger = Stinger;
        LastStingerTime = GetWorld().GetTimeSeconds();
    }

    void AddActiveTrack(const FString& Track)
    {
        ActiveTracks.Add(Track);
    }

    void RemoveActiveTrack(const FString& TrackName)
    {
        for (int32 i = ActiveTracks.Num() - 1; i >= 0; i--)
        {
            if (ActiveTracks[i].Contains(TrackName))
            {
                ActiveTracks.RemoveAt(i);
            }
        }
    }

    void DrawWorldDebugPanel()
    {
        auto Location = GetActorLocation();
        auto CurrentTime = GetWorld().GetTimeSeconds();

        // Main panel background
        utils_debug_draw::DrawDebugBox(Location, FVector(300, 200, 100),
            FLinearColor(0.1f, 0.1f, 0.1f, 0.8f), FRotator::ZeroRotator, 0.0f, 2.0f);

        // Title
        utils_debug_draw::DrawDebugString(Location + FVector(0, 0, 120),
            "AUDIO SYSTEM STATUS", nullptr, FLinearColor(1.0f, 1.0f, 0.0f), 0.0f);

        // Current zone with colored indicator
        auto ZoneColor = CurrentZone == "None" ? FLinearColor(0.5f, 0.5f, 0.5f) :
                        CurrentZone == "COMBAT ZONE" ? FLinearColor(1.0f, 0.0f, 0.0f) :
                        CurrentZone == "AMBIENT ZONE" ? FLinearColor(0.0f, 0.0f, 1.0f) :
                        CurrentZone == "ACTIVITY ZONE" ? FLinearColor(1.0f, 1.0f, 0.0f) :
                        CurrentZone == "QUIET ZONE" ? FLinearColor(0.0f, 1.0f, 0.0f) :
                        FLinearColor(1.0f, 1.0f, 1.0f);

        // Zone indicator sphere
        utils_debug_draw::DrawDebugSphere(Location + FVector(-100, 0, 80), 15.0f, 8,
            ZoneColor, 0.0f, 3.0f);

        utils_debug_draw::DrawDebugString(Location + FVector(-50, 0, 90),
            f"Zone: {CurrentZone}", nullptr, ZoneColor, 0.0f);

        // Music track with waveform visualization
        utils_debug_draw::DrawDebugString(Location + FVector(-50, 0, 70),
            f"Music: {CurrentMusic}", nullptr, FLinearColor(0.0f, 1.0f, 1.0f), 0.0f);

        // Music visualization bars
        if (CurrentMusic != "None")
        {
            for (int32 i = 0; i < 5; i++)
            {
                auto BarHeight = 10.0f + (Math::Sin(CurrentTime * 10.0f + i) * 5.0f);
                utils_debug_draw::DrawDebugLine(
                    Location + FVector(50 + (i * 10), 0, 50),
                    Location + FVector(50 + (i * 10), 0, 50 + BarHeight),
                    FLinearColor(0.0f, 1.0f, 1.0f), 0.0f, 2.0f);
            }
        }

        // Recent stinger display
        if (LastStingerTime > 0.0f && (CurrentTime - LastStingerTime) < 3.0f)
        {
            auto StingerAlpha = 1.0f - ((CurrentTime - LastStingerTime) / 3.0f);
            utils_debug_draw::DrawDebugString(Location + FVector(-50, 0, 50),
                f"Stinger: {LastStinger}", nullptr,
                FLinearColor(1.0f, 0.5f, 0.0f, StingerAlpha), 0.0f);

            // Stinger burst effect
            auto BurstRadius = (CurrentTime - LastStingerTime) * 20.0f;
            utils_debug_draw::DrawDebugCircle(Location + FVector(0, 0, 50), BurstRadius, 16,
                FLinearColor(1.0f, 0.5f, 0.0f, StingerAlpha * 0.5f), 0.0f, 1.0f);
        }

        // Active tracks counter
        utils_debug_draw::DrawDebugString(Location + FVector(-50, 0, 30),
            f"Active Tracks: {ActiveTracks.Num()}", nullptr, FLinearColor(1.0f, 1.0f, 1.0f), 0.0f);

        // Track list
        for (int32 i = 0; i < Math::Min(ActiveTracks.Num(), 3); i++)
        {
            utils_debug_draw::DrawDebugString(Location + FVector(-40, 0, 10 - (i * 15)),
                f"• {ActiveTracks[i]}", nullptr, FLinearColor(0.8f, 0.8f, 0.8f), 0.0f);
        }
    }
}