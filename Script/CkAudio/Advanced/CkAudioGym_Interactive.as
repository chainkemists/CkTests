// Moving audio source for 3D spatial testing
UCLASS()
class ACk_AudioGym_MovingAudioSource : AActor
{
    UPROPERTY(DefaultComponent)
    USceneComponent Root;

    UPROPERTY(DefaultComponent)
    UCk_EntityBridge_ActorComponent_UE EntityBridge;
    default EntityBridge._Replication = ECk_Replication::DoesNotReplicate;
    default EntityBridge._ConstructionScript = UCk_Entity_ConstructionScript_WithTransform_PDA;

    UPROPERTY()
    float OrbitRadius = 500.0f;
    UPROPERTY()
    float OrbitSpeed = 30.0f; // degrees per second
    UPROPERTY()
    float CurrentAngle = 0.0f;

    UPROPERTY()
    FVector CenterPoint = FVector::ZeroVector;

    UFUNCTION(BlueprintOverride)
    void ConstructionScript()
    {
        EntityBridge._OnPreConstruct.AddUFunction(this, n"EcsConstructionScript");
        EntityBridge._OnReplicationComplete_MC.AddUFunction(this, n"OnReplicationComplete");
    }

    UFUNCTION()
    void EcsConstructionScript(FCk_Handle InEntity)
    {
        utils_transform::Add(InEntity, GetActorTransform(), ECk_Replication::DoesNotReplicate);
    }

    UFUNCTION()
    void OnReplicationComplete(FCk_Handle InEntity)
    {
        // Add entity tag for identification
        auto SelfEntity = ck::SelfEntity(this);
        utils_entity_tag::Add_UsingGameplayTag(SelfEntity,
            utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.MovingAudioSource"));

        SetupSpatialAudio();
        FVector PlayerLocation;
        FRotator PlayerRotation;
        GetWorld().Get_FirstPlayerController().GetPlayerViewPoint(PlayerLocation, PlayerRotation);
        CenterPoint = PlayerLocation;
    }

    void SetupSpatialAudio()
    {
        // The spatial thunder cue will be executed when needed
        // No need to create persistent entities - the Cue system handles this
    }

    UFUNCTION()
    void OnSpatialTrackFinished(FCk_Handle_AudioCue InAudioCue, FGameplayTag InTrackName)
    {
        // Restart the spatial thunder cue
        auto SelfEntity = ck::SelfEntity(this);
        utils_cue::Request_Execute_Local(SelfEntity,
            utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Spatial.Moving"),
            FInstancedStruct());
    }

    UFUNCTION(BlueprintOverride)
    void Tick(float DeltaTime)
    {
        UpdateOrbitMovement(DeltaTime);
        DrawVisuals();
    }

    void UpdateOrbitMovement(float DeltaTime)
    {
        CurrentAngle += OrbitSpeed * DeltaTime;
        if (CurrentAngle >= 360.0f)
            CurrentAngle -= 360.0f;

        auto RadianAngle = Math::DegreesToRadians(CurrentAngle);
        auto NewLocation = CenterPoint + FVector(
            Math::Cos(RadianAngle) * OrbitRadius,
            Math::Sin(RadianAngle) * OrbitRadius,
            100.0f
        );

        SetActorLocation(NewLocation);
    }

    void DrawVisuals()
    {
        auto Location = GetActorLocation();

        // Draw moving audio source
        utils_debug_draw::DrawDebugSphere(Location, 30.0f, 12,
            FLinearColor(1.0f, 0.65f, 0.0f), 0.0f, 3.0f);
        utils_debug_draw::DrawDebugString(Location + FVector(0, 0, 50),
            "3D AUDIO SOURCE", nullptr, FLinearColor(1.0f, 0.65f, 0.0f), 0.0f);

        // Draw orbit path
        utils_debug_draw::DrawDebugCircle(CenterPoint, OrbitRadius, 32,
            FLinearColor(1.0f, 0.5f, 0.0f, 0.3f), 0.0f, 1.0f);

        // Draw connection line to center
        utils_debug_draw::DrawDebugLine(Location, CenterPoint,
            FLinearColor(1.0f, 0.5f, 0.0f, 0.5f), 0.0f, 1.0f);
    }
};

// Stinger pickup items
UCLASS()
class ACk_AudioGym_StingerPickup : AActor
{
    UPROPERTY(DefaultComponent)
    USceneComponent Root;

    UPROPERTY(DefaultComponent)
    UCk_EntityBridge_ActorComponent_UE EntityBridge;
    default EntityBridge._Replication = ECk_Replication::DoesNotReplicate;
    default EntityBridge._ConstructionScript = UCk_Entity_ConstructionScript_WithTransform_PDA;

    UPROPERTY()
    FCk_Handle_Probe PickupProbe;

    UPROPERTY()
    FGameplayTag StingerTag;

    UPROPERTY()
    float BobHeight = 20.0f;
    UPROPERTY()
    float BobSpeed = 2.0f;
    UPROPERTY()
    float BobTime = 0.0f;

    UPROPERTY()
    FVector BaseLocation;

    UPROPERTY()
    bool IsCollected = false;
    UPROPERTY()
    float RespawnTime = 5.0f;
    UPROPERTY()
    float CollectedTime = 0.0f;

    UFUNCTION(BlueprintOverride)
    void ConstructionScript()
    {
        EntityBridge._OnPreConstruct.AddUFunction(this, n"EcsConstructionScript");
        EntityBridge._OnReplicationComplete_MC.AddUFunction(this, n"OnReplicationComplete");
        StingerTag = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Stingers.UI.Interface");
    }

    UFUNCTION()
    void EcsConstructionScript(FCk_Handle InEntity)
    {
        utils_transform::Add(InEntity, GetActorTransform(), ECk_Replication::DoesNotReplicate);
    }

    UFUNCTION()
    void OnReplicationComplete(FCk_Handle InEntity)
    {
        BaseLocation = GetActorLocation();
        CreatePickupProbe();
    }

    void CreatePickupProbe()
    {
        // Add sphere shape
        auto SelfEntity = ck::SelfEntity(this);
        auto TransformHandle = SelfEntity.To_FCk_Handle_Transform();
        auto SphereShape = utils_shapes::Make_Sphere(FCk_ShapeSphere_Dimensions(50.0f));
        utils_shapes::Add(SelfEntity, SphereShape);

        // Create probe
        auto ProbeParams = FCk_Fragment_Probe_ParamsData();
        ProbeParams._ProbeName = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Probe.Pickup");
        ProbeParams._MotionType = ECk_MotionType::Kinematic;
        ProbeParams._ResponsePolicy = ECk_ProbeResponse_Policy::Notify;
        ProbeParams._Filter.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"Player.Probe"));

        auto DebugInfo = FCk_Probe_DebugInfo();

        PickupProbe = utils_probe::Add(TransformHandle, ProbeParams, DebugInfo);

        utils_probe::BindTo_OnBeginOverlap(PickupProbe, ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing, FCk_Delegate_Probe_OnBeginOverlap(this, n"OnPlayerTouched"));
    }

    UFUNCTION()
    void OnPlayerTouched(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnBeginOverlap InOverlapInfo)
    {
        if (IsCollected == false)
        {
            CollectPickup();
        }
    }

    void CollectPickup()
    {
        IsCollected = true;
        CollectedTime = 0.0f;

        // Trigger stinger
        auto PlayerController = Cast<ACk_AudioGym_PlayerController>(GetWorld().Get_FirstPlayerController());
        if (ck::IsValid(PlayerController))
        {
            PlayerController.OnStingerTriggered(StingerTag);
        }

        // Disable probe
        utils_probe::Request_EnableDisable(PickupProbe,
            FCk_Request_Probe_EnableDisable(ECk_EnableDisable::Disable));
    }

    UFUNCTION(BlueprintOverride)
    void Tick(float DeltaTime)
    {
        if (IsCollected)
        {
            CollectedTime += DeltaTime;
            if (CollectedTime >= RespawnTime)
            {
                RespawnPickup();
            }
        }
        else
        {
            UpdateBobbing(DeltaTime);
        }

        DrawVisuals();
    }

    void UpdateBobbing(float DeltaTime)
    {
        BobTime += DeltaTime;
        auto BobOffset = Math::Sin(BobTime * BobSpeed) * BobHeight;
        SetActorLocation(BaseLocation + FVector(0, 0, BobOffset));
    }

    void RespawnPickup()
    {
        IsCollected = false;
        CollectedTime = 0.0f;
        BobTime = 0.0f;

        // Re-enable probe
        utils_probe::Request_EnableDisable(PickupProbe,
            FCk_Request_Probe_EnableDisable(ECk_EnableDisable::Enable));
    }

    void DrawVisuals()
    {
        auto Location = GetActorLocation();

        if (IsCollected)
        {
            // Draw respawn countdown
            auto TimeLeft = RespawnTime - CollectedTime;
            utils_debug_draw::DrawDebugString(Location,
                f"Respawn: {Math::CeilToInt(TimeLeft)}s", nullptr, FLinearColor(0.5f, 0.5f, 0.5f), 0.0f);
        }
        else
        {
            // Draw active pickup
            utils_debug_draw::DrawDebugSphere(Location, 25.0f, 8,
                FLinearColor(0.0f, 1.0f, 1.0f), 0.0f, 2.0f);
            utils_debug_draw::DrawDebugString(Location + FVector(0, 0, 40),
                "STINGER", nullptr, FLinearColor(0.0f, 1.0f, 1.0f), 0.0f);

            // Draw pulsing ring
            auto PulseScale = 1.0f + (Math::Sin(BobTime * 4.0f) * 0.3f);
            utils_debug_draw::DrawDebugCircle(Location, 50.0f * PulseScale, 16,
                FLinearColor(0.0f, 1.0f, 1.0f, 0.5f), 0.0f, 1.0f);
        }
    }
};

// Control panel for manual audio testing
UCLASS()
class ACk_AudioGym_ControlPanel : AActor
{
    UPROPERTY(DefaultComponent)
    USceneComponent Root;

    UPROPERTY(DefaultComponent)
    UCk_EntityBridge_ActorComponent_UE EntityBridge;
    default EntityBridge._Replication = ECk_Replication::DoesNotReplicate;
    default EntityBridge._ConstructionScript = UCk_Entity_ConstructionScript_WithTransform_PDA;

    UPROPERTY()
    FCk_Handle_Probe InteractionProbe;

    UPROPERTY()
    TArray<FString> ControlOptions;

    UPROPERTY()
    int32 CurrentSelection = 0;

    UFUNCTION(BlueprintOverride)
    void ConstructionScript()
    {
        EntityBridge._OnReplicationComplete_MC.AddUFunction(this, n"OnReplicationComplete");

        ControlOptions.Add("Start Ambient Music");
        ControlOptions.Add("Start Combat Music");
        ControlOptions.Add("Start Activity Music");
        ControlOptions.Add("Stop All Music");
        ControlOptions.Add("Play Test Stinger");
        ControlOptions.Add("Spatial Audio Test");
    }

    UFUNCTION()
    void OnReplicationComplete(FCk_Handle InEntity)
    {
        utils_transform::Add(InEntity, GetActorTransform(), ECk_Replication::DoesNotReplicate);
        CreateInteractionProbe();
    }

    void CreateInteractionProbe()
    {
        // Add box shape
        auto SelfEntity = ck::SelfEntity(this);
        auto TransformHandle = SelfEntity.To_FCk_Handle_Transform();
        auto BoxShape = utils_shapes::Make_Box(FCk_ShapeBox_Dimensions(FVector(200, 200, 100)));
        utils_shapes::Add(SelfEntity, BoxShape);

        // Create probe
        auto ProbeParams = FCk_Fragment_Probe_ParamsData();
        ProbeParams._ProbeName = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Probe.Control");
        ProbeParams._MotionType = ECk_MotionType::Kinematic;
        ProbeParams._ResponsePolicy = ECk_ProbeResponse_Policy::Notify;
        ProbeParams._Filter.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"Player.Probe"));

        auto DebugInfo = FCk_Probe_DebugInfo();

        InteractionProbe = utils_probe::Add(TransformHandle, ProbeParams, DebugInfo);

        utils_probe::BindTo_OnBeginOverlap(InteractionProbe, ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing, FCk_Delegate_Probe_OnBeginOverlap(this, n"OnPlayerNearby"));
    }

    UFUNCTION()
    void OnPlayerNearby(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnBeginOverlap InOverlapInfo)
    {
        ExecuteCurrentSelection();
    }

    void ExecuteCurrentSelection()
    {
        auto PlayerController = Cast<ACk_AudioGym_PlayerController>(GetWorld().Get_FirstPlayerController());
        if (ck::IsValid(PlayerController) == false)
            return;

        switch (CurrentSelection)
        {
            case 0: PlayerController.StartAmbientMusic(); break;
            case 1: PlayerController.StartCombatMusic(); break;
            case 2: break; // Activity music - could add if needed
            case 3: PlayerController.StopAllMusic(); break;
            case 4: PlayerController.PlayTestStinger(); break;
            case 5: TriggerSpatialAudioTest(); break;
        }

        // Cycle to next option
        CurrentSelection = (CurrentSelection + 1) % ControlOptions.Num();
    }

    void TriggerSpatialAudioTest()
    {
        // Find moving audio source using entity tags
        auto SelfEntity = ck::SelfEntity(this);
        auto MovingSources = utils_entity_tag::ForEach_Entity(SelfEntity,
            utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.MovingAudioSource").TagName);

        if (MovingSources.Num() > 0)
        {
            // Get the first moving source found
            auto MovingSource = Cast<ACk_AudioGym_MovingAudioSource>(
                MovingSources[0].Get_EntityOwningActor());
            if (ck::IsValid(MovingSource))
            {
                MovingSource.CurrentAngle = 0.0f;

                // Execute the spatial audio cue
                auto SelfEntity = ck::SelfEntity(MovingSource);
                utils_cue::Request_Execute_Local(SelfEntity,
                    utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Spatial.Moving"),
                    FInstancedStruct());
            }
        }
    }

    UFUNCTION(BlueprintOverride)
    void Tick(float DeltaTime)
    {
        DrawControlPanel();
    }

    void DrawControlPanel()
    {
        auto Location = GetActorLocation();

        // Draw control panel base
        utils_debug_draw::DrawDebugBox(Location, FVector(200, 200, 50),
            FLinearColor(1.0f, 0.0f, 1.0f), GetActorRotation(), 0.0f, 4.0f);

        // Draw title
        utils_debug_draw::DrawDebugString(Location + FVector(0, 0, 100),
            "AUDIO CONTROL PANEL", nullptr, FLinearColor(1.0f, 0.0f, 1.0f), 0.0f);

        // Draw current selection
        if (ControlOptions.IsValidIndex(CurrentSelection))
        {
            utils_debug_draw::DrawDebugString(Location + FVector(0, 0, 70),
                f"Next: {ControlOptions[CurrentSelection]}", nullptr, FLinearColor(1.0f, 1.0f, 1.0f), 0.0f);
        }

        // Draw interaction hint
        utils_debug_draw::DrawDebugString(Location + FVector(0, 0, 40),
            "Walk into to activate", nullptr, FLinearColor(0.5f, 0.5f, 0.5f), 0.0f);
    }
};