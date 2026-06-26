class ACk_Gym_Base_PlayerController : ACk_PlayerController_UE
{
    default Replicates = false;

    // Z offset applied to every station's default grid placement. Override
    // in subclasses whose world floor isn't at Z=0 — the GymStation's alcove
    // floor sits at Z=FloorThickness/2 above the station origin, so without
    // adjustment that floor protrudes above any world floor whose top is at
    // Z=0. Negative values pull the alcove down. See ACk_NavigationGym_PlayerController.
    UPROPERTY()
    float DefaultStationGridZ = 0.0f;

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto SpawnParams = FCk_EntityScript_WithActor_SpawnParams();
        SpawnParams._OwningActor = this;
        auto PendingEntity = utils_entity_script::Request_SpawnEntity(
            ck::TransientEntity(), UCk_EntityScript_WithActor_UE, SpawnParams);
        utils_pending_entity_script::Promise_OnConstructed(
            PendingEntity, FCk_Delegate_EntityScript_Constructed(this, n"OnEntityConstructed"));
    }

    private int32 _PendingStationCount = 0;

    // The PC's own ECS entity (the WithActor entity spawned in BeginPlay). Hosts
    // the deferred-wait timer used by WaitOneFrame.
    private FCk_Handle _SelfEntity;

    UFUNCTION()
    void OnEntityConstructed(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        _SelfEntity = FCk_Handle(InEntityScriptHandle);
        Request_EnsureStationsExist();
    }

    UFUNCTION()
    void OnStationEntityConstructed(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        _PendingStationCount--;
        if (_PendingStationCount <= 0)
        {
            // Stations tag themselves via utils_entity_tag::Add inside DoConstruct,
            // which is DEFERRED by one processor pass (see CkEntityTag CLAUDE.md
            // "Timing"). Request_StartGym / Get_StationHandle query that tag store,
            // so starting in this same construction pass finds zero stations. Wait
            // one frame for the deferred Adds to settle before starting the gym.
            WaitOneFrame(n"OnStationsSettled");
        }
    }

    UFUNCTION()
    private void OnStationsSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        Request_StartGym();
    }

    // Mirrors CkAutoTest_Base::WaitOneFrame — schedules a one-frame timer on the
    // PC's own entity and invokes InCallbackName (FCk_Delegate_Timer signature)
    // once it fires. Use to observe state mutated through a deferred pathway
    // (e.g. deferred CkEntityTag Adds) on a subsequent frame.
    private void WaitOneFrame(FName InCallbackName)
    {
        auto Params = FCk_Fragment_Timer_ParamsData(FCk_Time(0.05));
        Params.Set_StartingState(ECk_Timer_State::Running)
              .Set_Behavior(ECk_Timer_Behavior::StopOnDone);
        auto Timer = utils_timer::Add(_SelfEntity, Params);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, InCallbackName));
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
            // No stations to spawn — proceed straight to gym startup.
            Request_StartGym();
            return;
        }

        // Apply default grid layout if transforms not explicitly set.
        Request_ApplyDefaultGridLayout(RequiredStations);

        _PendingStationCount = 0;

        for (auto StationParams : RequiredStations)
        {
            if (Request_StationExists(StationParams.Tags))
            { continue; }

            _PendingStationCount++;
            auto Pending = CkGym_Common::Request_SpawnNewStation(StationParams);
            utils_pending_entity_script::Promise_OnConstructed(
                Pending, FCk_Delegate_EntityScript_Constructed(this, n"OnStationEntityConstructed"));
        }

        if (_PendingStationCount == 0)
        {
            // All stations already existed — nothing to await.
            Request_StartGym();
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
                DefaultTransform.SetLocation(FVector(XPos, YPos, DefaultStationGridZ));
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

        // Check if any station entity with any of these tags exists.
        for (auto Tag : InTags)
        {
            auto Entities = utils_entity_tag::ForEach_Entity(ck::TransientEntity(), Tag);
            if (Entities.Num() > 0)
            {
                return true;
            }
        }

        return false;
    }

    // Override this in derived gym classes to implement gym-specific startup logic
    void Request_StartGym()
    {
        // Base class: show the gym selector HUD menu
        auto MenuHUD = Cast<ACkGym_MenuHUD>(GetHUD());
        if (ck::IsValid(MenuHUD))
        {
            MenuHUD.Request_ShowMenu();
        }
    }

    // Look up the station entity tagged with InStationTag. Stations are
    // pure ECS entities now (UCk_EntityScript_GymStation) — no underlying
    // AActor — so all station lookups go through utils_entity_tag.
    FCk_Handle Get_StationHandle(FString InStationTag)
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::TransientEntity(), FName(InStationTag));
        if (Entities.Num() == 0)
        {
            ck::Warning("Cannot get station handle - station entity not found: " + InStationTag);
            return FCk_Handle();
        }
        return Entities[0];
    }

    FTransform Get_StationTransform(FString InStationTag)
    {
        auto Handle = Get_StationHandle(InStationTag);
        if (!ck::IsValid(Handle))
        {
            return FTransform::Identity;
        }

        auto TH = Handle.As_Transform();
        if (!ck::IsValid(TH))
        {
            ck::Warning("Station [" + InStationTag + "] entity has no Transform fragment");
            return FTransform::Identity;
        }

        return utils_transform::Get_EntityCurrentTransform(TH);
    }

    void Set_StationTitleAndDescription(FString InStationTag, FCkGym_Station_TitleAndDescription InTextAndDescription)
    {
        auto Handle = Get_StationHandle(InStationTag);
        if (!ck::IsValid(Handle))
        {
            ck::Warning("Cannot set station text - station entity not found: " + InStationTag);
            return;
        }
        auto& Fragment = Handle.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
        Fragment = InTextAndDescription;
    }

    // Cross-gym anchor lookup. Reads the FCkGym_Station_Anchors snapshot
    // fragment that the GymStation EntityScript populates in DoConstruct.
    // Returns FVector::ZeroVector if the station entity isn't found.
    //
    // Picking the right anchor:
    //   - PanelCenter      → DEFAULT for most gyms. Inside the alcove at
    //                        mid-height; debug visuals don't intersect geometry.
    //   - FootprintCenter  → For nav / physics / spatial / AStar gyms whose
    //                        test elements need to sit on the floor / navmesh.
    //   - AgentSpawn*      → Perimeter pickup points (respects AgentSpawnOffset).
    //   - PanelTopFront    → Banner / label attach point.
    FVector Get_StationAnchorLocation(FString InStationTag, ECk_GymStation_Anchor InAnchor)
    {
        auto Handle = Get_StationHandle(InStationTag);
        if (!ck::IsValid(Handle))
        {
            return FVector::ZeroVector;
        }
        auto Anchors = Handle.Get_Fragment(FCkGym_Station_Anchors);
        if (InAnchor == ECk_GymStation_Anchor::FootprintCenter) { return Anchors.FootprintCenter; }
        if (InAnchor == ECk_GymStation_Anchor::AgentSpawnFront) { return Anchors.AgentSpawnFront; }
        if (InAnchor == ECk_GymStation_Anchor::AgentSpawnBack)  { return Anchors.AgentSpawnBack; }
        if (InAnchor == ECk_GymStation_Anchor::AgentSpawnLeft)  { return Anchors.AgentSpawnLeft; }
        if (InAnchor == ECk_GymStation_Anchor::AgentSpawnRight) { return Anchors.AgentSpawnRight; }
        if (InAnchor == ECk_GymStation_Anchor::PanelTopFront)   { return Anchors.PanelTopFront; }
        return Anchors.PanelCenter;
    }

    // Convenience for callers that want a full FTransform at the named anchor
    // (anchor location + station's existing rotation). Replaces the common
    // pattern of Get_StationTransform(tag) when migrating gyms to use a
    // specific anchor — the inventory entity / cube / etc. still gets the
    // station's facing direction, just placed at the chosen anchor.
    FTransform Get_StationAnchorTransform(FString InStationTag, ECk_GymStation_Anchor InAnchor)
    {
        auto StationT = Get_StationTransform(InStationTag);
        auto Location = Get_StationAnchorLocation(InStationTag, InAnchor);
        return FTransform(StationT.Rotator(), Location, FVector(1.0, 1.0, 1.0));
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
