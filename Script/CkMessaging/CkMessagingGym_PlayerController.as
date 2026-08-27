// Language=angelscript

//============================================================================
// MESSAGING GYM - PLAYER CONTROLLER
//============================================================================

class ACk_MessagingGym_PlayerController : ACk_Gym_Base_PlayerController
{
    int32 SequenceCounter = 0;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        // Station 1: Basic Broadcast & Listen
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Messaging.BasicBroadcast");
            Station.Title = FText::FromString("BASIC BROADCAST & LISTEN");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Demonstrates basic message broadcast and listener binding."));
            Description.Add(FText::FromString("Tests payload extraction with sender and sequence data."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Station 2: Multi-Listener Fan-Out
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Messaging.MultiListener");
            Station.Title = FText::FromString("MULTI-LISTENER FAN-OUT");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Three delegates bound to the same message type on one entity."));
            Description.Add(FText::FromString("A single broadcast fires all three listeners simultaneously."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Station 3: One-Shot Listener
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Messaging.OneShot");
            Station.Title = FText::FromString("ONE-SHOT LISTENER");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Listener auto-unbinds after first fire using PostFireBehavior::Unbind."));
            Description.Add(FText::FromString("Subsequent broadcasts are ignored until reset re-arms the listener."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Station 4: Dynamic Bind / Unbind
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Messaging.DynamicBind");
            Station.Title = FText::FromString("DYNAMIC BIND / UNBIND");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Runtime bind and unbind of message listeners via console commands."));
            Description.Add(FText::FromString("Tests UnbindFrom_OnBroadcast and re-binding at runtime."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Station 5: Multiple Message Types
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Messaging.MultiType");
            Station.Title = FText::FromString("MULTIPLE MESSAGE TYPES");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Single entity listening to three different message types."));
            Description.Add(FText::FromString("Ping, Pong, and Alert messages tracked independently."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        return Stations;
    }

    void Request_StartGym() override
    {
        Request_StartBasicStation();
        Request_StartMultiListenerStation();
        Request_StartOneShotStation();
        Request_StartDynamicBindStation();
        Request_StartMultiTypeStation();
        ck::Trace("[OK] Messaging Gym - All stations started");
    }

    //------------------------------------------------------------------------
    // STATION STARTUP FUNCTIONS
    //------------------------------------------------------------------------

    void Request_StartBasicStation()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.Messaging.BasicBroadcast", ECk_GymStation_Anchor::PanelCenter);
        auto SpawnParams = FMessagingGymSpawnParams(StationTransform);

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Messaging.BasicBroadcast"),
            UCk_EntityScript_MessagingGym_Basic,
            FInstancedStruct::Make(SpawnParams)
        );

        if (ck::IsValid(SpawnRequest))
        {
            ck::Trace("[OK] Basic Broadcast & Listen station started");
        }
        else
        {
            ck::Error("[FAIL] Failed to spawn Basic Broadcast entity");
        }
    }

    void Request_StartMultiListenerStation()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.Messaging.MultiListener", ECk_GymStation_Anchor::PanelCenter);
        auto SpawnParams = FMessagingGymSpawnParams(StationTransform);

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Messaging.MultiListener"),
            UCk_EntityScript_MessagingGym_MultiListener,
            FInstancedStruct::Make(SpawnParams)
        );

        if (ck::IsValid(SpawnRequest))
        {
            ck::Trace("[OK] Multi-Listener Fan-Out station started");
        }
        else
        {
            ck::Error("[FAIL] Failed to spawn Multi-Listener entity");
        }
    }

    void Request_StartOneShotStation()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.Messaging.OneShot", ECk_GymStation_Anchor::PanelCenter);
        auto SpawnParams = FMessagingGymSpawnParams(StationTransform);

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Messaging.OneShot"),
            UCk_EntityScript_MessagingGym_OneShot,
            FInstancedStruct::Make(SpawnParams)
        );

        if (ck::IsValid(SpawnRequest))
        {
            ck::Trace("[OK] One-Shot Listener station started");
        }
        else
        {
            ck::Error("[FAIL] Failed to spawn One-Shot entity");
        }
    }

    void Request_StartDynamicBindStation()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.Messaging.DynamicBind", ECk_GymStation_Anchor::PanelCenter);
        auto SpawnParams = FMessagingGymSpawnParams(StationTransform);

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Messaging.DynamicBind"),
            UCk_EntityScript_MessagingGym_DynamicBind,
            FInstancedStruct::Make(SpawnParams)
        );

        if (ck::IsValid(SpawnRequest))
        {
            ck::Trace("[OK] Dynamic Bind / Unbind station started");
        }
        else
        {
            ck::Error("[FAIL] Failed to spawn Dynamic Bind entity");
        }
    }

    void Request_StartMultiTypeStation()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.Messaging.MultiType", ECk_GymStation_Anchor::PanelCenter);
        auto SpawnParams = FMessagingGymSpawnParams(StationTransform);

        auto SpawnRequest = utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Messaging.MultiType"),
            UCk_EntityScript_MessagingGym_MultiType,
            FInstancedStruct::Make(SpawnParams)
        );

        if (ck::IsValid(SpawnRequest))
        {
            ck::Trace("[OK] Multiple Message Types station started");
        }
        else
        {
            ck::Error("[FAIL] Failed to spawn Multi-Type entity");
        }
    }

    //------------------------------------------------------------------------
    // STATION 1: BASIC BROADCAST COMMANDS
    //------------------------------------------------------------------------

    //--------------------------------------------------------------------------------------------------------------------------
    // CONTROL PANEL (Script/Common/CkGym_ControlPanel.as)
    //
    // A message gym shows nothing until a message is SENT, so every station here is dead on arrival until
    // someone types a console command. The sends are Actions rather than Toggles: broadcasting has no
    // readback, so there is no state to report and a two-state row would be inventing one.
    //--------------------------------------------------------------------------------------------------------------------------

    FString Get_ControlPanelTitle() override
    {
        return "MESSAGING";
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();

        Rows.Add(CkGym_Control::Header("SEND"));
        Rows.Add(CkGym_Control::Numbered(0, "Ping", false));
        Rows.Add(CkGym_Control::Numbered(1, "Fan-out ping", false));
        Rows.Add(CkGym_Control::Numbered(2, "One-shot", false));
        Rows.Add(CkGym_Control::Numbered(3, "Ping to dynamic", false));
        Rows.Add(CkGym_Control::Numbered(4, "Pong", false));
        Rows.Add(CkGym_Control::Numbered(5, "Alert, priority 5", false));
        Rows.Add(CkGym_Control::Numbered(6, "All types at once", false));

        Rows.Add(CkGym_Control::Header("BINDINGS"));
        Rows.Add(CkGym_Control::Action(EKeys::B, "B", "Flip the dynamic bind"));
        Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Reset every station"));

        Rows.Add(CkGym_Control::Status("Alert at another priority: console only"));

        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        // Rows 0 and 8 are headers, which hold no key and never arrive here.
        if (InRowIndex == 1) { Ck_GymMessaging_SendPing(); }
        else if (InRowIndex == 2) { Ck_GymMessaging_FanOutPing(); }
        else if (InRowIndex == 3) { Ck_GymMessaging_FireOneShot(); }
        else if (InRowIndex == 4) { Ck_GymMessaging_SendPingToDynamic(); }
        else if (InRowIndex == 5) { Ck_GymMessaging_SendPong(); }
        else if (InRowIndex == 6) { Ck_GymMessaging_SendAlert(5); }
        else if (InRowIndex == 7) { Ck_GymMessaging_SendAllTypes(); }
        else if (InRowIndex == 9) { Ck_GymMessaging_ToggleBind(); }
        else if (InRowIndex == 10) { Ck_GymMessaging_ResetAll(); }
    }

    UFUNCTION(Exec, DisplayName="Messaging Gym - Send Ping")
    void Ck_GymMessaging_SendPing()
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_MessagingGym_Basic");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_MessagingGym_Ping("Console", SequenceCounter));
        }
        SequenceCounter++;
    }

    //------------------------------------------------------------------------
    // STATION 2: MULTI-LISTENER COMMANDS
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Messaging Gym - Fan-Out Ping")
    void Ck_GymMessaging_FanOutPing()
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_MessagingGym_MultiListener");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_MessagingGym_Ping("FanOut", SequenceCounter));
        }
        SequenceCounter++;
    }

    //------------------------------------------------------------------------
    // STATION 3: ONE-SHOT COMMANDS
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Messaging Gym - Fire One-Shot")
    void Ck_GymMessaging_FireOneShot()
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_MessagingGym_OneShot");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_MessagingGym_Ping("OneShot", SequenceCounter));
        }
        SequenceCounter++;
    }

    //------------------------------------------------------------------------
    // STATION 4: DYNAMIC BIND COMMANDS
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Messaging Gym - Toggle Bind")
    void Ck_GymMessaging_ToggleBind()
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_MessagingGym_DynamicBind");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_MessagingGym_ToggleBind());
        }
    }

    UFUNCTION(Exec, DisplayName="Messaging Gym - Send Ping to Dynamic")
    void Ck_GymMessaging_SendPingToDynamic()
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_MessagingGym_DynamicBind");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_MessagingGym_Ping("Dynamic", SequenceCounter));
        }
        SequenceCounter++;
    }

    //------------------------------------------------------------------------
    // STATION 5: MULTI-TYPE COMMANDS
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Messaging Gym - Send Pong")
    void Ck_GymMessaging_SendPong()
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_MessagingGym_MultiType");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_MessagingGym_Pong("Console", SequenceCounter));
        }
        SequenceCounter++;
    }

    UFUNCTION(Exec, DisplayName="Messaging Gym - Send Alert")
    void Ck_GymMessaging_SendAlert(int32 InPriority)
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_MessagingGym_MultiType");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_MessagingGym_Alert("Warning!", InPriority));
        }
    }

    UFUNCTION(Exec, DisplayName="Messaging Gym - Send All Types")
    void Ck_GymMessaging_SendAllTypes()
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_MessagingGym_MultiType");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_MessagingGym_Ping("AllTypes", SequenceCounter));
            utils_messaging::Broadcast(Entity, FCk_Message_MessagingGym_Pong("AllTypes", SequenceCounter));
            utils_messaging::Broadcast(Entity, FCk_Message_MessagingGym_Alert("Batch Alert", 5));
        }
        SequenceCounter++;
    }

    //------------------------------------------------------------------------
    // GLOBAL COMMANDS
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Messaging Gym - Reset All Stations")
    void Ck_GymMessaging_ResetAll()
    {
        auto AllTags = TArray<FName>();
        AllTags.Add(n"TAG_MessagingGym_Basic");
        AllTags.Add(n"TAG_MessagingGym_MultiListener");
        AllTags.Add(n"TAG_MessagingGym_OneShot");
        AllTags.Add(n"TAG_MessagingGym_DynamicBind");
        AllTags.Add(n"TAG_MessagingGym_MultiType");

        for (auto Tag : AllTags)
        {
            auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), Tag);
            for (auto Entity : Entities)
            {
                utils_messaging::Broadcast(Entity, FCk_Message_MessagingGym_Reset());
            }
        }

        SequenceCounter = 0;
        ck::Trace("[OK] All Messaging Gym stations reset");
    }
}
