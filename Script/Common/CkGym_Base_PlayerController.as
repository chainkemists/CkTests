class ACk_Gym_Base_PlayerController : ACk_PlayerController_UE
{
    UPROPERTY(DefaultComponent)
    UCk_EntityBridge_ActorComponent_UE EntityBridge;
    default EntityBridge._Replication = ECk_Replication::Replicates;
    default EntityBridge._ConstructionScript = UCk_Entity_ConstructionScript_WithTransform_PDA;

    default Replicates = true;

    UFUNCTION(BlueprintOverride)
    void ConstructionScript()
    {
        EntityBridge._OnReplicationComplete_MC.AddUFunction(this, n"OnReplicationComplete");
    }

    UFUNCTION()
    void OnReplicationComplete(FCk_Handle InEntity)
    {
        Request_StartGym();
    }

    // Override this in derived gym classes to implement gym-specific startup logic
    void Request_StartGym()
    {
        ck::Trace("Base gym started - override Request_StartGym() in derived class");
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
        auto& Fragment = utils_dynamic_fragment::AddOrGet_Fragment(Handle, FCkGym_Station_TitleAndDescription);
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
}