//============================================================================
// REPLICATION GYM - PLAYER CONTROLLER
//============================================================================

class ACk_ReplicationGym_PlayerController : ACk_Gym_Base_PlayerController
{
    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        // Scenario A - replicated actor that spawns a WithActor entity script.
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Replication.ReplicatedActor");
            Station.Title = FText::FromString("REPLICATION — REPLICATED ACTOR");
            Station.AutoSize = true;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Scenario A: a replicated AActor (mirror of ABB_Store) spawns a"));
            Description.Add(FText::FromString("UCk_EntityScript_WithActor_UE subclass with _Replication=Replicates"));
            Description.Add(FText::FromString("using ck::TransientEntity() as lifetime. The entity script adds a"));
            Description.Add(FText::FromString("replicated Integer Attribute in DoConstructWithActor."));
            Description.Add(FText::FromString("BUG: ensure 'No container fragment entry found for type"));
            Description.Add(FText::FromString("      [Ck_RepData_IntegerAttributes]' fires on the Listen Server."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        // Scenario B - replicated pawn + second WithActor entity script.
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Replication.PawnTransient");
            Station.Title = FText::FromString("REPLICATION — PAWN TRANSIENT-ENTITY CHILD");
            Station.AutoSize = true;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Scenario B: the replicated pawn attaches a SECOND WithActor entity"));
            Description.Add(FText::FromString("script with ck::TransientEntity() as lifetime, and that script adds"));
            Description.Add(FText::FromString("a replicated Integer Attribute in DoConstructWithActor."));
            Description.Add(FText::FromString("Mirrors the BB_PlayerCharacter regression after re-ordering."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        return Stations;
    }

    void Request_StartGym() override
    {
        Request_StartReplicatedActorStation();
        // Scenario B is driven by the Pawn itself (see ACk_ReplicationGym_Pawn::Request_OnPawnReady).
        ck::Trace("[ReplicationGym] Gym started - watch Output Log for 'No container fragment entry found'");
    }

    //------------------------------------------------------------------------
    // Scenario A startup
    //------------------------------------------------------------------------

    private ACk_ReplicationGym_ReplicatedActor _SpawnedReplicatedActor;

    void Request_StartReplicatedActorStation()
    {
        if (!HasAuthority())
        { return; }

        auto StationTransform = Get_StationAnchorTransform("Gym.Replication.ReplicatedActor", ECk_GymStation_Anchor::PanelCenter);

        // Destroy any previous one (used by the respawn exec command).
        if (ck::IsValid(_SpawnedReplicatedActor))
        {
            _SpawnedReplicatedActor.DestroyActor();
            _SpawnedReplicatedActor = nullptr;
        }

        _SpawnedReplicatedActor = Cast<ACk_ReplicationGym_ReplicatedActor>(SpawnActor(
            ACk_ReplicationGym_ReplicatedActor,
            StationTransform.GetLocation(),
            StationTransform.Rotator()));
    }

    //------------------------------------------------------------------------
    // Console commands
    //------------------------------------------------------------------------

    //--------------------------------------------------------------------------------------------------------------------------
    // CONTROL PANEL (Script/Common/CkGym_ControlPanel.as)
    //
    // Both value setters are preset RINGS rather than single-value actions: each attribute is Min-clamped
    // at 0 with no maximum (see the two entity scripts), so a ring that steps through the placard value,
    // zero, a NEGATIVE value and a large one exercises the clamp the replicated attribute has to survive
    // - and the clamped result is what has to arrive on the other side.
    //--------------------------------------------------------------------------------------------------------------------------

    // -1 means nothing has been sent yet, so the row shows the ring instead of a value.
    private int32 _ActorPresetIndex = -1;
    private int32 _PawnPresetIndex = -1;

    FString Get_ControlPanelTitle() override
    {
        return "REPLICATION";
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();

        Rows.Add(CkGym_Control::Cycle(EKeys::One, "1", "Actor value", DoGet_ActorPresetLabel()));
        Rows.Add(CkGym_Control::Cycle(EKeys::Two, "2", "Pawn value",  DoGet_PawnPresetLabel()));
        Rows.Add(CkGym_Control::Action(EKeys::G, "G", "Respawn replicated actor"));
        Rows.Add(CkGym_Control::Action(EKeys::J, "J", "Dump replication state"));

        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (InRowIndex == 0)
        {
            auto Values = Get_ActorPresetValues();
            _ActorPresetIndex = (_ActorPresetIndex + 1) % Values.Num();
            Request_BroadcastToActor(Values[_ActorPresetIndex]);
        }
        else if (InRowIndex == 1)
        {
            auto Values = Get_PawnPresetValues();
            _PawnPresetIndex = (_PawnPresetIndex + 1) % Values.Num();
            Request_BroadcastToPawn(Values[_PawnPresetIndex]);
        }
        else if (InRowIndex == 2) { Ck_GymReplication_RespawnActor(); }
        else if (InRowIndex == 3) { Ck_GymReplication_DumpRep(); }
    }

    // The negative entry is the point of the ring: it has to arrive clamped to the Min of 0.
    private TArray<int32> Get_ActorPresetValues() const
    {
        auto Values = TArray<int32>();
        Values.Add(100);
        Values.Add(0);
        Values.Add(-50);
        Values.Add(9999);
        return Values;
    }

    private TArray<int32> Get_PawnPresetValues() const
    {
        auto Values = TArray<int32>();
        Values.Add(50);
        Values.Add(0);
        Values.Add(-25);
        Values.Add(500);
        return Values;
    }

    private FString DoGet_ActorPresetLabel() const
    {
        if (_ActorPresetIndex < 0)
        { return "(100 / 0 / -50 / 9999)"; }

        auto Values = Get_ActorPresetValues();
        auto Current = Values[_ActorPresetIndex];
        return f"sent {Current}";
    }

    private FString DoGet_PawnPresetLabel() const
    {
        if (_PawnPresetIndex < 0)
        { return "(50 / 0 / -25 / 500)"; }

        auto Values = Get_PawnPresetValues();
        auto Current = Values[_PawnPresetIndex];
        return f"sent {Current}";
    }

    private void Request_BroadcastToActor(int32 InValue)
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_ReplicationGym_ReplicatedActor"))
        {
            utils_messaging::Broadcast(E, FCk_Message_ReplicationGym_SetAttribute(InValue));
        }
    }

    private void Request_BroadcastToPawn(int32 InValue)
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_ReplicationGym_PawnExtra"))
        {
            utils_messaging::Broadcast(E, FCk_Message_ReplicationGym_SetAttribute(InValue));
        }
    }

    UFUNCTION(Exec, DisplayName="Replication Gym - Respawn Replicated Actor")
    void Ck_GymReplication_RespawnActor()
    {
        Request_StartReplicatedActorStation();
    }

    UFUNCTION(Exec, DisplayName="Replication Gym - Dump Replication State")
    void Ck_GymReplication_DumpRep()
    {
        auto Self = ck::ToEntity(this);

        auto ActorTag = utils_gameplay_tag::ResolveGameplayTag(n"IntegerAttribute.ReplicationGym.ActorValue");
        auto PawnTag  = utils_gameplay_tag::ResolveGameplayTag(n"IntegerAttribute.ReplicationGym.PawnValue");

        ck::Trace("=== ReplicationGym - DumpRep ===");
        for (auto E : utils_entity_tag::ForEach_Entity(Self, n"TAG_ReplicationGym_ReplicatedActor"))
        {
            auto A = utils_integer_attribute::TryGet(E, ActorTag);
            ck::Trace(f"  ReplicatedActor: present={A.IsValid()} value={(A.IsValid() ? A.Get_FinalValue(ECk_MinMaxCurrent::Current) : 0)}");
        }
        for (auto E : utils_entity_tag::ForEach_Entity(Self, n"TAG_ReplicationGym_PawnExtra"))
        {
            auto A = utils_integer_attribute::TryGet(E, PawnTag);
            ck::Trace(f"  PawnExtra:       present={A.IsValid()} value={(A.IsValid() ? A.Get_FinalValue(ECk_MinMaxCurrent::Current) : 0)}");
        }
        ck::Trace("================================");
    }
}
