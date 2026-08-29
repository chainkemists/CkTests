// Language=angelscript

//============================================================================
// MESSAGING GYM - PLAYER CONTROLLER
//============================================================================

class ACk_MessagingGym_PlayerController : ACk_Gym_Base_PlayerController
{
    int32 SequenceCounter = 0;

    // Ring position for the alert row. -1 means nothing has been sent yet, so the row advertises the
    // ring instead of claiming a priority that was never broadcast.
    private int32 _AlertPresetIndex = -1;

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
            Description.Add(FText::FromString("Runtime bind and unbind of message listeners via the [B] panel row."));
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

    //--------------------------------------------------------------------------------------------------------------------------
    // CONTROL PANEL (Script/Common/CkGym_ControlPanel.as)
    //
    // A message gym shows nothing until a message is SENT, so every station here is dead on arrival until
    // a row fires. The sends are Actions rather than Toggles: broadcasting has no readback, so there is
    // no state to report and a two-state row would be inventing one.
    //
    // The alert row is the one exception - it carries a priority, so each press walks a 1/5/9 ring and
    // sends at the value it lands on. Its value column reports the priority LAST SENT, which is the only
    // thing about it that can be known.
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
        Rows.Add(DoMake_AlertRow());
        Rows.Add(CkGym_Control::Numbered(6, "All types at once", false));

        Rows.Add(CkGym_Control::Header("BINDINGS"));
        Rows.Add(CkGym_Control::Action(EKeys::B, "B", "Flip the dynamic bind"));
        Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Reset every station"));

        return Rows;
    }

    private FCkGym_ControlRow DoMake_AlertRow() const
    {
        auto Row = CkGym_Control::Numbered(5, "Alert", false);
        Row.Value = _AlertPresetIndex < 0 ? "(1 / 5 / 9)" : f"priority {DoGet_AlertPriority(_AlertPresetIndex)}";
        return Row;
    }

    private int32 DoGet_AlertPriority(int32 InIndex) const
    {
        return InIndex == 0 ? 1 : InIndex == 1 ? 5 : 9;
    }

    // Each press walks the ring and sends at the value it lands on - the shape the attribute gym's
    // preset rings already use. 5 is the priority the multi-type station's placard talks about; 1 and 9
    // bracket it so the station's priority formatting is exercised at both ends.
    private void DoCycleAlertPriority()
    {
        _AlertPresetIndex = (_AlertPresetIndex + 1) % 3;

        auto Priority = DoGet_AlertPriority(_AlertPresetIndex);
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_MessagingGym_MultiType");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_MessagingGym_Alert("Warning!", Priority));
        }
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        // Rows 0 and 8 are headers, which hold no key and never arrive here.
        if (InRowIndex == 1) { DoBroadcastPing(n"TAG_MessagingGym_Basic", "Console"); }
        else if (InRowIndex == 2) { DoBroadcastPing(n"TAG_MessagingGym_MultiListener", "FanOut"); }
        else if (InRowIndex == 3) { DoBroadcastPing(n"TAG_MessagingGym_OneShot", "OneShot"); }
        else if (InRowIndex == 4) { DoBroadcastPing(n"TAG_MessagingGym_DynamicBind", "Dynamic"); }
        else if (InRowIndex == 5) { DoBroadcastPong(); }
        else if (InRowIndex == 6) { DoCycleAlertPriority(); }
        else if (InRowIndex == 7) { DoBroadcastAllTypes(); }
        else if (InRowIndex == 9) { DoToggleBind(); }
        else if (InRowIndex == 10) { DoResetAll(); }
    }

    private void DoBroadcastPing(FName InTag, FString InSender)
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InTag);
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_MessagingGym_Ping(InSender, SequenceCounter));
        }
        SequenceCounter++;
    }

    private void DoBroadcastPong()
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_MessagingGym_MultiType");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_MessagingGym_Pong("Console", SequenceCounter));
        }
        SequenceCounter++;
    }

    private void DoBroadcastAllTypes()
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

    private void DoToggleBind()
    {
        auto Entities = utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_MessagingGym_DynamicBind");
        for (auto Entity : Entities)
        {
            utils_messaging::Broadcast(Entity, FCk_Message_MessagingGym_ToggleBind());
        }
    }

    private void DoResetAll()
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
