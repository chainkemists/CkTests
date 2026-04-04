class ACk_Gym_Base_PlayerController : ACk_PlayerController_UE
{
    UPROPERTY(DefaultComponent)
    UCk_EntityBridge_ActorComponent_UE EntityBridge;
    default EntityBridge._Replication = ECk_Replication::DoesNotReplicate;
    default EntityBridge._ConstructionScript = UCk_Entity_ConstructionScript_WithTransform_PDA;

    default Replicates = false;

    UFUNCTION(BlueprintOverride)
    void ConstructionScript()
    {
        EntityBridge._OnReplicationComplete_MC.AddUFunction(this, n"OnReplicationComplete");
    }

    UFUNCTION()
    void OnReplicationComplete(FCk_Handle InEntity)
    {
        Request_EnsureStationsExist();
        Request_StartGym();
    }

    // Override in derived classes to define required stations
    // Stations will be spawned in a default grid layout unless transforms are explicitly set
    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations()
    {
        return TArray<FCkGym_Station_SpawnParams_Payload>();
    }

    void Request_EnsureStationsExist()
    {
        auto RequiredStations = Get_RequiredStations();
        if (RequiredStations.Num() == 0)
        {
            return;
        }

        // Apply default grid layout if transforms not explicitly set
        Request_ApplyDefaultGridLayout(RequiredStations);

        // Spawn stations that don't already exist
        for (auto StationParams : RequiredStations)
        {
            if (Request_StationExists(StationParams.Tags))
            {
                continue;
            }

            CkGym_Common::Request_SpawnNewStation(StationParams);
        }
    }

    void Request_ApplyDefaultGridLayout(TArray<FCkGym_Station_SpawnParams_Payload>& InOutStations)
    {
        auto StationSpacing = 800.0f;
        auto RowSpacing = 800.0f;
        auto MaxStationsPerRow = 7;
        auto Rotation180 = FRotator(0.0f, 180.0f, 0.0f);
        auto BaseXOffset = 500.0f;

        for (int32 i = 0; i < InOutStations.Num(); i++)
        {
            // Only apply default layout if transform is identity (not explicitly set)
            if (InOutStations[i].Transform.Equals(FTransform::Identity))
            {
                auto RowIndex = Math::IntegerDivisionTrunc(i, MaxStationsPerRow);
                auto ColIndex = i % MaxStationsPerRow;
                auto StationsInRow = Math::Min(MaxStationsPerRow, InOutStations.Num() - (RowIndex * MaxStationsPerRow));
                auto RowStartOffset = -(StationsInRow - 1) * StationSpacing * 0.5f;

                auto DefaultTransform = FTransform::Identity;
                auto XPos = BaseXOffset + (RowIndex * RowSpacing);
                auto YPos = RowStartOffset + (ColIndex * StationSpacing);
                DefaultTransform.SetLocation(FVector(XPos, YPos, 0.0f));
                DefaultTransform.SetRotation(Rotation180.Quaternion());
                InOutStations[i].Transform = DefaultTransform;
            }
        }
    }

    bool Request_StationExists(TArray<FName> InTags)
    {
        if (InTags.Num() == 0)
        {
            return false;
        }

        // Check if any station with any of these tags exists
        for (auto Tag : InTags)
        {
            auto StationActor = utils_actor::Get_FirstActorWithNameContaining(Tag.ToString(), ECk_ActorSearchMethod::SearchByTag);
            if (ck::IsValid(StationActor))
            {
                return true;
            }
        }

        return false;
    }

    //--------------------------------------------------------------------------------------------------------------------------
    // Gym Menu — Look-at Selection
    //--------------------------------------------------------------------------------------------------------------------------

    bool bMenuActive = false;
    int32 HighlightedGymIndex = -1;
    TArray<FVector> GymLabelPositions;
    float GymLabelVerticalSpacing = 35.0f;
    float GymLabelSelectThreshold = 40.0f;

    // Override this in derived gym classes to implement gym-specific startup logic
    void Request_StartGym()
    {
        // Base class: spawn a menu station and compute label positions for look-at selection
        auto Registry = CkGym_Cycler::Get_GymRegistry();
        auto Description = TArray<FText>();

        for (int32 i = 0; i < Registry.Num(); i++)
        {
            Description.Add(FText::FromString(f"[{i}] {Registry[i].DisplayName}"));
        }

        Description.Add(FText::FromString(""));
        Description.Add(FText::FromString("Look at a gym and press E to select"));

        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Title = FText::FromString("Gym Cycler");
        Station.Description = Description;
        Station.Tags.Add(n"Gym.Cycler.Menu");
        Station.Width = 8.0f;
        Station.Height = 8.0f;

        auto MenuTransform = FTransform::Identity;
        MenuTransform.SetLocation(FVector(500.0f, 0.0f, 0.0f));
        MenuTransform.SetRotation(FRotator(0.0f, 180.0f, 0.0f).Quaternion());
        Station.Transform = MenuTransform;

        CkGym_Common::Request_SpawnNewStation(Station);

        // Compute world positions for each gym label on the station face
        // Station faces the player (rotated 180), so labels are on the -X side
        auto StationLoc = MenuTransform.GetLocation();
        auto LabelBasePos = StationLoc + FVector(-50.0f, 0.0f, 350.0f);

        GymLabelPositions.Empty();
        for (int32 i = 0; i < Registry.Num(); i++)
        {
            auto LabelPos = LabelBasePos - FVector(0.0f, 0.0f, float(i) * GymLabelVerticalSpacing);
            GymLabelPositions.Add(LabelPos);
        }

        bMenuActive = true;
        HighlightedGymIndex = -1;
    }

    UFUNCTION(BlueprintOverride)
    void Tick(float DeltaSeconds)
    {
        if (bMenuActive == false)
        {
            return;
        }

        auto Registry = CkGym_Cycler::Get_GymRegistry();
        if (GymLabelPositions.Num() == 0)
        {
            return;
        }

        // Get camera ray
        FVector CameraLoc;
        FRotator CameraRot;
        GetPlayerViewPoint(CameraLoc, CameraRot);
        auto ForwardDir = CameraRot.GetForwardVector();

        // Find which label the camera ray is closest to
        auto BestIndex = -1;
        auto BestDistance = GymLabelSelectThreshold;

        for (int32 i = 0; i < GymLabelPositions.Num(); i++)
        {
            auto ToLabel = GymLabelPositions[i] - CameraLoc;
            auto Projection = ToLabel.DotProduct(ForwardDir);
            if (Projection < 0.0f)
            {
                continue;
            }

            auto ClosestPoint = CameraLoc + ForwardDir * Projection;
            auto Distance = (GymLabelPositions[i] - ClosestPoint).Size();
            if (Distance < BestDistance)
            {
                BestDistance = Distance;
                BestIndex = i;
            }
        }

        HighlightedGymIndex = BestIndex;

        // Draw labels with highlight
        for (int32 i = 0; i < GymLabelPositions.Num(); i++)
        {
            auto IsHighlighted = (i == HighlightedGymIndex);
            auto Color = IsHighlighted ? FLinearColor(1.0f, 0.9f, 0.0f, 1.0f) : FLinearColor(0.7f, 0.7f, 0.7f, 1.0f);
            auto Prefix = IsHighlighted ? ">> " : "   ";
            auto LabelText = f"{Prefix}[{i}] {Registry[i].DisplayName}";

            utils_debug_draw::DrawDebugString(GymLabelPositions[i], LabelText, Color, 0.0f);
        }

        // Check for confirm input
        if (HighlightedGymIndex >= 0 && WasInputKeyJustPressed(EKeys::E))
        {
            bMenuActive = false;
            Ck_Gym_GoTo(HighlightedGymIndex);
        }
    }

    // Utility function for derived classes to find station by tag
    AActor Get_StationByTag(FString InStationTag)
    {
        auto StationActor = utils_actor::Get_FirstActorWithNameContaining(InStationTag, ECk_ActorSearchMethod::SearchByTag);
        if (!ck::IsValid(StationActor))
        {
            ck::Error("❌ Station not found with tag: " + InStationTag);
            return nullptr;
        }

        return StationActor;
    }

    FCk_Handle Get_StationHandle(FString InStationTag)
    {
        auto StationActor = Get_StationByTag(InStationTag);
        if (!ck::IsValid(StationActor))
        {
            ck::Warning("❌ Cannot get transform - station not found: " + InStationTag);
            return FCk_Handle();
        }

        return utils_owning_actor::Get_ActorEntityHandle(StationActor);
    }

    void Set_StationTitleAndDescription(FString InStationTag, FCkGym_Station_TitleAndDescription InTextAndDescription)
    {
        auto StationActor = Get_StationByTag(InStationTag);
        if (!ck::IsValid(StationActor))
        {
            ck::Warning("❌ Cannot get transform - station not found: " + InStationTag);
            return;
        }

        auto Handle = utils_owning_actor::Get_ActorEntityHandle(StationActor);
        auto& Fragment = Handle.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
        Fragment = InTextAndDescription;
    }

    // Utility function for derived classes to get station transform
    FTransform Get_StationTransform(FString InStationTag)
    {
        auto StationActor = Get_StationByTag(InStationTag);
        if (!ck::IsValid(StationActor))
        {
            ck::Warning("❌ Cannot get transform - station not found: " + InStationTag);
            return FTransform::Identity;
        }

        return StationActor.GetActorTransform();
    }

    UFUNCTION(Exec, DisplayName="Gym - Restart")
    void Ck_Gym_Restart()
    {
        Request_StartGym();
    }

    //--------------------------------------------------------------------------------------------------------------------------
    // Gym Cycling
    //--------------------------------------------------------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Gym - Next")
    void Ck_Gym_Next()
    {
        CkGym_Cycler::Request_NextGym();
    }

    UFUNCTION(Exec, DisplayName="Gym - Previous")
    void Ck_Gym_Prev()
    {
        CkGym_Cycler::Request_PrevGym();
    }

    UFUNCTION(Exec, DisplayName="Gym - Go To Index")
    void Ck_Gym_GoTo(int32 InIndex)
    {
        CkGym_Cycler::Request_TravelToGym(InIndex);
    }

    UFUNCTION(Exec, DisplayName="Gym - List All")
    void Ck_Gym_List()
    {
        CkGym_Cycler::Print_GymList();
    }

}
