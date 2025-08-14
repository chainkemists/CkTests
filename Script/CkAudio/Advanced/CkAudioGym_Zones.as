// Base zone class for music areas
UCLASS()
class ACk_AudioGym_BaseZone : AActor
{
    UPROPERTY(DefaultComponent)
    USceneComponent Root;

    UPROPERTY(DefaultComponent)
    UCk_EntityBridge_ActorComponent_UE EntityBridge;
    default EntityBridge._Replication = ECk_Replication::DoesNotReplicate;
    default EntityBridge._ConstructionScript = UCk_Entity_ConstructionScript_WithTransform_PDA;

    UPROPERTY()
    FCk_Handle_Probe ZoneProbe;

    UPROPERTY(EditAnywhere)
    FString ZoneName = "Base Zone";

    UPROPERTY(EditAnywhere)
    FGameplayTag MusicTag;

    UPROPERTY(EditAnywhere)
    FLinearColor ZoneColor = FLinearColor::White;

    UPROPERTY(EditAnywhere)
    FVector ZoneSize = FVector(800, 800, 200);

    UFUNCTION(BlueprintOverride)
    void ConstructionScript()
    {
        EntityBridge._OnPreConstruct.AddUFunction(this, n"EcsConstructionScript");
        EntityBridge._OnReplicationComplete_MC.AddUFunction(this, n"OnReplicationComplete");
    }

    UFUNCTION()
    private void EcsConstructionScript(FCk_Handle InEntity)
    {
        utils_transform::Add(InEntity, GetActorTransform(), ECk_Replication::Replicates);
    }

    UFUNCTION()
    void OnReplicationComplete(FCk_Handle InEntity)
    {
        CreateZoneProbe();
    }

    void CreateZoneProbe()
    {
        // First add a box shape
        auto SelfEntity = ck::SelfEntity(this);

        auto TransformHandle = SelfEntity.To_FCk_Handle_Transform();

        Print(f"SelfEntity: {TransformHandle.ToString()}");

        auto BoxShape = utils_shapes::Make_Box(FCk_ShapeBox_Dimensions(ZoneSize));
        utils_shapes::Add(SelfEntity, BoxShape);

        // Add player tag for filtering
        utils_entity_tag::Add_UsingGameplayTag(SelfEntity,
            utils_gameplay_tag::ResolveGameplayTag(n"Pawn.Player"));

        // Create probe
        auto ProbeParams = FCk_Fragment_Probe_ParamsData();
        ProbeParams._ProbeName = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Probe.Zone");
        ProbeParams._ResponsePolicy = ECk_ProbeResponse_Policy::Notify;
        ProbeParams._Filter.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"Player.Probe"));

        auto DebugInfo = FCk_Probe_DebugInfo();

        ZoneProbe = utils_probe::Add(TransformHandle, ProbeParams, DebugInfo);

        utils_probe::BindTo_OnBeginOverlap(ZoneProbe, ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing, FCk_Delegate_Probe_OnBeginOverlap(this, n"OnPlayerEntered"));
        utils_probe::BindTo_OnEndOverlap(ZoneProbe, ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing, FCk_Delegate_Probe_OnEndOverlap(this, n"OnPlayerExited"));
    }

    UFUNCTION()
    void OnPlayerEntered(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnBeginOverlap InOverlapInfo)
    {
        auto PlayerController = Cast<ACk_AudioGym_PlayerController>(GetWorld().Get_FirstPlayerController());
        if (ck::IsValid(PlayerController))
        {
            PlayerController.OnEnteredZone(ZoneName, MusicTag);
        }
    }

    UFUNCTION()
    void OnPlayerExited(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnEndOverlap InOverlapInfo)
    {
        auto PlayerController = Cast<ACk_AudioGym_PlayerController>(GetWorld().Get_FirstPlayerController());
        if (ck::IsValid(PlayerController))
        {
            PlayerController.OnExitedZone(ZoneName);
        }
    }

    UFUNCTION(BlueprintOverride)
    void Tick(float DeltaTime)
    {
        DrawZoneVisuals();
    }

    void DrawZoneVisuals()
    {
        auto Location = GetActorLocation();

        // Draw zone boundary
        utils_debug_draw::DrawDebugBox(Location, ZoneSize, ZoneColor,
            GetActorRotation(), 0.0f, 3.0f);

        // Draw zone label
        utils_debug_draw::DrawDebugString(Location + FVector(0, 0, ZoneSize.Z + 50),
            ZoneName, nullptr, ZoneColor, 0.0f);

        // Draw corner markers
        DrawCornerMarkers(Location, ZoneSize, ZoneColor);
    }

    void DrawCornerMarkers(FVector Center, FVector Size, FLinearColor Color)
    {
        auto HalfSize = Size * 0.5f;
        TArray<FVector> Corners;

        Corners.Add(Center + FVector(HalfSize.X, HalfSize.Y, -HalfSize.Z));
        Corners.Add(Center + FVector(-HalfSize.X, HalfSize.Y, -HalfSize.Z));
        Corners.Add(Center + FVector(-HalfSize.X, -HalfSize.Y, -HalfSize.Z));
        Corners.Add(Center + FVector(HalfSize.X, -HalfSize.Y, -HalfSize.Z));

        for (auto& Corner : Corners)
        {
            utils_debug_draw::DrawDebugSphere(Corner, 20.0f, 8, Color, 0.0f, 2.0f);
        }
    }
};

// Ambient music zone (default background music)
UCLASS()
class ACk_AudioGym_AmbientZone : ACk_AudioGym_BaseZone
{
    default ZoneName = "AMBIENT ZONE";
    default MusicTag = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Music.Ambient");
    default ZoneColor = FLinearColor(0.0f, 0.0f, 1.0f);
    default ZoneSize = FVector(1200, 1200, 200);
};

// Combat music zone (high priority)
UCLASS()
class ACk_AudioGym_CombatZone : ACk_AudioGym_BaseZone
{
    default ZoneName = "COMBAT ZONE";
    default MusicTag = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Music.Combat");
    default ZoneColor = FLinearColor(1.0f, 0.0f, 0.0f);
    default ZoneSize = FVector(600, 600, 200);
};

// Activity music zone (medium priority)
UCLASS()
class ACk_AudioGym_ActivityZone : ACk_AudioGym_BaseZone
{
    default ZoneName = "ACTIVITY ZONE";
    default MusicTag = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Music.Activity");
    default ZoneColor = FLinearColor(1.0f, 1.0f, 0.0f);
    default ZoneSize = FVector(600, 600, 200);
};

// Quiet zone (stops music)
UCLASS()
class ACk_AudioGym_QuietZone : ACk_AudioGym_BaseZone
{
    default ZoneName = "QUIET ZONE";
    default MusicTag = FGameplayTag(); // Invalid tag = stop music
    default ZoneColor = FLinearColor(0.0f, 1.0f, 0.0f);
    default ZoneSize = FVector(400, 400, 200);

    void OnPlayerEntered(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnBeginOverlap InOverlapInfo) override
    {
        auto PlayerController = Cast<ACk_AudioGym_PlayerController>(GetWorld().Get_FirstPlayerController());
        if (ck::IsValid(PlayerController))
        {
            PlayerController.OnEnteredZone(ZoneName, MusicTag);
            // Stop all music in quiet zone
            PlayerController.StopAllMusic();
        }
    }
};