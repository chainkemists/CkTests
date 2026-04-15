//============================================================================
// REPLICATION GYM — REPLICATED ACTOR ENTITY SCRIPT (Scenario A)
//============================================================================
// Mirror of UBB_Store_EntityScript. Replicates, and in DoConstructWithActor
// adds a replicated Integer Attribute — this is the call path that currently
// triggers:
//   Ensure: No container fragment entry found for type
//           [Ck_RepData_IntegerAttributes] on Entity ...
//============================================================================

class UCk_ReplicationGym_ReplicatedActor_EntityScript : UCk_EntityScript_WithActor_UE
{
    default _Replication = ECk_Replication::Replicates;

    // Hardcoded to keep the spawn params a plain FCk_EntityScript_WithActor_SpawnParams.
    const int32 StartingValue = 100;

    // Cache so DisplayTick can read it without repeated TryGet lookups.
    FCk_Handle_IntegerAttribute ValueAttribute;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        utils_entity_tag::Add(InHandle, n"TAG_ReplicationGym_ReplicatedActor");

        // *** THIS IS THE REPRO LINE ***
        // Adding a replicated Integer Attribute on an entity whose replication
        // driver has no container entry for FCk_RepData_IntegerAttributes yet.
        auto Params = FCk_Fragment_IntegerAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"IntegerAttribute.ReplicationGym.ActorValue"),
            StartingValue);
        Params.Set_MinMax(ECk_MinMax::Min);
        Params.Set_MinValue(0);
        ValueAttribute = utils_integer_attribute::Add(InHandle, Params, ECk_Replication::Replicates);

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_ReplicationGym_SetAttribute,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnSetAttribute"));

        // Display timer — every frame, update the station demo display.
        auto DisplayTimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

        ck::Warning("[ReplicationGym] ReplicatedActor entity construction done — "
                  + "if 'No container fragment entry found' appears above this line, bug reproduced");
    }

    UFUNCTION()
    private void OnSetAttribute(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        auto Typed = InPayload.Get(FCk_Message_ReplicationGym_SetAttribute);
        if (ck::IsValid(ValueAttribute))
        {
            utils_integer_attribute::Request_Override(ValueAttribute, Typed.Value);
        }
    }

    UFUNCTION()
    private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto SelfEntity = ck::ToEntity(this);
        auto NetworkRole = CkGym_Common::Get_NetworkRoleTitle(SelfEntity);

        auto AttrTag = utils_gameplay_tag::ResolveGameplayTag(n"IntegerAttribute.ReplicationGym.ActorValue");
        auto AttrHandle = utils_integer_attribute::TryGet(SelfEntity, AttrTag);
        auto AttrPresent = AttrHandle.IsValid();
        auto AttrValue = AttrPresent ? AttrHandle.Get_FinalValue(ECk_MinMaxCurrent::Current) : 0;
        auto PresenceStr = AttrPresent ? "YES" : "NO";

        auto Title = "REPLICATION — REPLICATED ACTOR (" + NetworkRole + ")";

        FString Body;
        Body = Body + "Scenario A: replicated actor -> WithActor entity script\n";
        Body = Body + "  Actor Replicates:  true\n";
        Body = Body + "  EntityScript Rep:  Replicates\n";
        Body = Body + f"  Attribute present: {PresenceStr}\n";
        Body = Body + f"  Attribute value:   {AttrValue}\n\n";
        Body = Body + "PASS = no 'No container fragment entry found' in Output Log\n";
        Body = Body + "       + Attribute present YES on both server and client.\n\n";
        Body = Body + "Manual:\n";
        Body = Body + "  Ck_GymReplication_SetActorValue [n]\n";
        Body = Body + "  Ck_GymReplication_RespawnActor\n";
        Body = Body + "  Ck_GymReplication_DumpRep\n";

        // The station demo display actor is spawned separately by the PC.
        // Look it up by the station tag and write the display fragment onto
        // its entity handle.
        auto StationActor = utils_actor::Get_FirstActorWithNameContaining(
            "Gym.Replication.ReplicatedActor", ECk_ActorSearchMethod::SearchByTag);
        if (!ck::IsValid(StationActor))
        { return; }

        auto StationHandle = utils_owning_actor::TryGet_ActorEntityHandle(StationActor);
        if (!ck::IsValid(StationHandle))
        { return; }

        auto& Fragment = StationHandle.AddOrGet_Fragment(FCkGym_Station_TitleAndDescription);
        Fragment.Title = FText::FromString(Title);
        Fragment.Description = FText::FromString(Body);
    }
}
