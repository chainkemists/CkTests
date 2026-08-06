//============================================================================
// REPLICATION GYM — PAWN EXTRA ENTITY SCRIPT (Scenario B)
//============================================================================
// A second UCk_EntityScript_WithActor_UE attached to the replicated pawn,
// with ck::TransientEntity() as the lifetime owner. Mirrors the shape that
// caused ensures on BB_PlayerCharacter after re-ordering attribute setup.
//============================================================================

class UCk_ReplicationGym_PawnExtra_EntityScript : UCk_EntityScript_WithActor_UE
{
    default _Replication = ECk_Replication::Replicates;

    const int32 StartingValue = 50;

    FCk_Handle_IntegerAttribute ValueAttribute;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        utils_entity_tag::Add(InHandle, n"TAG_ReplicationGym_PawnExtra");

        // *** REPRO LINE — Scenario B ***
        auto Params = FCk_Fragment_IntegerAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"IntegerAttribute.ReplicationGym.PawnValue"),
            StartingValue);
        Params.Set_MinMax(ECk_MinMax::Min);
        Params.Set_MinValue(0);
        ValueAttribute = utils_integer_attribute::Add(InHandle, Params, ECk_Replication::Replicates);

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_ReplicationGym_SetAttribute,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnSetAttribute"));

        auto DisplayTimerParams = FCk_Timer_Spec(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));

        ck::Warning("[ReplicationGym] PawnExtra entity construction done — "
                  + "if 'No container fragment entry found' appears above this line, bug reproduced");
    }

    UFUNCTION()
    private void OnSetAttribute(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        auto Typed = InPayload.Get(FCk_Message_ReplicationGym_SetAttribute);
        if (ck::IsValid(ValueAttribute))
        {
            utils_integer_attribute::Request_Override(ValueAttribute, Typed.Value, ECk_MinMaxCurrent::Current);
        }
    }

    UFUNCTION()
    private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto SelfEntity = ck::ToEntity(this);
        auto NetworkRole = CkGym_Common::Get_NetworkRoleTitle(SelfEntity);

        auto AttrTag = utils_gameplay_tag::ResolveGameplayTag(n"IntegerAttribute.ReplicationGym.PawnValue");
        auto AttrHandle = utils_integer_attribute::TryGet(SelfEntity, AttrTag);
        auto AttrPresent = AttrHandle.IsValid();
        auto AttrValue = AttrPresent ? AttrHandle.Get_FinalValue(ECk_MinMaxCurrent::Current) : 0;
        auto PresenceStr = AttrPresent ? "YES" : "NO";

        auto Title = "REPLICATION — PAWN TRANSIENT-ENTITY CHILD (" + NetworkRole + ")";

        FString Body;
        Body = Body + "Scenario B: replicated pawn + second WithActor script\n";
        Body = Body + "             (lifetime owner = TransientEntity)\n";
        Body = Body + "  Pawn Replicates:   true\n";
        Body = Body + "  EntityScript Rep:  Replicates\n";
        Body = Body + f"  Attribute present: {PresenceStr}\n";
        Body = Body + f"  Attribute value:   {AttrValue}\n\n";
        Body = Body + "PASS = no 'No container fragment entry found' in Output Log\n";
        Body = Body + "       + Attribute present YES on both server and client.\n\n";
        Body = Body + "Manual:\n";
        Body = Body + "  Ck_GymReplication_SetPawnValue [n]\n";
        Body = Body + "  Ck_GymReplication_DumpRep\n";

        auto StationActor = utils_actor::Get_FirstActorWithNameContaining(
            "Gym.Replication.PawnTransient", ECk_ActorSearchMethod::SearchByTag);
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
