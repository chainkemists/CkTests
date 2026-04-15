//============================================================================
// REPLICATION GYM — PLAYER CONTROLLER
//============================================================================

class ACk_ReplicationGym_PlayerController : ACk_Gym_Base_PlayerController
{
    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        // Scenario A — replicated actor that spawns a WithActor entity script.
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Replication.ReplicatedActor");
            Station.Title = FText::FromString("REPLICATION — REPLICATED ACTOR");
            Station.Height = gym_auto::EstimateStationHeight(0, 3, 14);
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

        // Scenario B — replicated pawn + second WithActor entity script.
        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Replication.PawnTransient");
            Station.Title = FText::FromString("REPLICATION — PAWN TRANSIENT-ENTITY CHILD");
            Station.Height = gym_auto::EstimateStationHeight(0, 2, 14);
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Scenario B: the replicated pawn attaches a SECOND WithActor entity"));
            Description.Add(FText::FromString("script with ck::TransientEntity() as lifetime, and that script adds"));
            Description.Add(FText::FromString("a replicated Integer Attribute in DoConstructWithActor."));
            Description.Add(FText::FromString("Mirrors the BB_PlayerCharacter regression after re-ordering."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        gym_auto::NormalizeStationHeights(Stations);
        return Stations;
    }

    void Request_StartGym() override
    {
        Request_StartReplicatedActorStation();
        // Scenario B is driven by the Pawn itself (see ACk_ReplicationGym_Pawn::Request_OnPawnReady).
        ck::Trace("[ReplicationGym] Gym started — watch Output Log for 'No container fragment entry found'");
    }

    //------------------------------------------------------------------------
    // Scenario A startup
    //------------------------------------------------------------------------

    private ACk_ReplicationGym_ReplicatedActor _SpawnedReplicatedActor;

    void Request_StartReplicatedActorStation()
    {
        if (!HasAuthority())
        { return; }

        auto StationTransform = Get_StationTransform("Gym.Replication.ReplicatedActor");

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

    UFUNCTION(Exec, DisplayName="Replication Gym - Set Actor Value")
    void Ck_GymReplication_SetActorValue(int32 InValue = 100)
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_ReplicationGym_ReplicatedActor"))
        {
            utils_messaging::Broadcast(E, FCk_Message_ReplicationGym_SetAttribute(InValue));
        }
    }

    UFUNCTION(Exec, DisplayName="Replication Gym - Set Pawn Value")
    void Ck_GymReplication_SetPawnValue(int32 InValue = 50)
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

        ck::Trace("=== ReplicationGym — DumpRep ===");
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
