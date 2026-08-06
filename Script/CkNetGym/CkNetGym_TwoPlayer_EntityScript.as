// Language=angelscript

//============================================================================
// TWO-PLAYER NET GYM — ENTITY SCRIPT
//============================================================================
// Replicated (runs Construct on BOTH server and client via the entity-script
// replication path). Adds:
//   - Health: server-authoritative replicated CkAttribute.
//   - StateMachine: owning-client-authoritative, WithHistory, AutoStart Disabled
//     (the owning client issues Request_Start once it controls the pawn).
// Handles the Damage / AdvanceState messages the cadence director drives, and
// self-draws live state both as floating world-space text above the pawn and as
// an on-screen line.
//============================================================================

class UCk_NetGym_TwoPlayer_EntityScript : UCk_EntityScript_WithActor_UE
{
    default _Replication = ECk_Replication::Replicates;

    private FCk_Handle_FloatAttribute _Health;
    private FCk_Handle_StateMachine _StateMachine;

    // Owning-client SMs must NOT auto-start (the server is non-authority for a remote
    // client's pawn and would ensure on the dropped Start request). Instead the OWNING
    // client issues Request_Start once it is locally controlling the pawn. One-shot.
    private bool _StartRequested = false;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        utils_entity_tag::Add(InHandle, CkNetGym::PlayerPawnTag);

        // --- Server-authoritative Health attribute (both worlds Add it; server mutates) ---
        auto HealthParams = FCk_Fragment_FloatAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(CkNetGym::HealthTagName),
            CkNetGym::StartingHealth);
        HealthParams.Set_MinMax(ECk_MinMax::MinMax);
        HealthParams.Set_MinValue(CkNetGym::MinHealth);
        HealthParams.Set_MaxValue(CkNetGym::MaxHealth);
        _Health = utils_float_attribute::Add(InHandle, HealthParams, ECk_Replication::Replicates);

        // --- Owning-client-authoritative State Machine ---
        auto SmParams = FCk_Fragment_StateMachine_ParamsData(UCk_NetGym_State_Idle);
        SmParams.Set_Replication(ECk_Replication::Replicates);
        SmParams.Set_AuthorityModel(ECk_Sm_AuthorityModel::OwningClientAuthoritative);
        SmParams.Set_ReplicationModel(ECk_Sm_ReplicationModel::WithHistory);
        SmParams.Set_AutoStart(ECk_SmAutoStart::Disabled);
        _StateMachine = UCk_Utils_StateMachine_UE::Add(InHandle, SmParams);

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_NetGym_Damage,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnDamage"));
        utils_messaging::BindTo_OnBroadcast(InHandle, FCk_Message_NetGym_AdvanceState,
            FCk_Delegate_Messaging_OnBroadcast(this, n"OnAdvanceState"));

        auto DisplayTimerParams = FCk_Timer_Spec(FCk_Time(0.0f));
        DisplayTimerParams.Set_StartingState(ECk_Timer_State::Running).Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto DisplayTimer = utils_timer::Add(InHandle, DisplayTimerParams);
        DisplayTimer.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"DisplayTick"));
    }

    // Server-auth: this is only ever broadcast on the SERVER (from the pawn's Server RPC),
    // so Request_Override runs on the authoritative world and the value replicates.
    UFUNCTION()
    private void OnDamage(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        if (ck::Is_NOT_Valid(_Health))
        { return; }

        auto Typed = InPayload.Get(FCk_Message_NetGym_Damage);
        auto Current = utils_float_attribute::Get_FinalValue(_Health, ECk_MinMaxCurrent::Current);

        // Loop the showcase: once depleted, refill to full so HP visibly cycles 100 -> 0 -> 100.
        if (Current - Typed.Amount <= CkNetGym::MinHealth)
        { utils_float_attribute::Request_Override(_Health, float32(CkNetGym::MaxHealth), ECk_MinMaxCurrent::Current); }
        else
        { utils_float_attribute::Request_Override(_Health, float32(Current - Typed.Amount), ECk_MinMaxCurrent::Current); }
    }

    // Owning-client: broadcast LOCALLY on the owning client. Request_Transition commits locally
    // (owning-client authority) and relays to the server, which replicates to the other client.
    UFUNCTION()
    private void OnAdvanceState(FCk_Handle InHandle, FGameplayTag InMessageName, FInstancedStruct InPayload)
    {
        if (ck::Is_NOT_Valid(_StateMachine))
        { return; }

        auto Current = _StateMachine.Get_CurrentStateClass();
        auto Next = Get_NextStateClass(Current);
        _StateMachine.Request_Transition(Next);
    }

    private TSubclassOf<UCk_SmState_EntityScript> Get_NextStateClass(TSubclassOf<UCk_SmState_EntityScript> InCurrent)
    {
        if (InCurrent == UCk_NetGym_State_Idle)   { return UCk_NetGym_State_Active; }
        if (InCurrent == UCk_NetGym_State_Active) { return UCk_NetGym_State_Recovering; }
        return UCk_NetGym_State_Idle;
    }

    UFUNCTION()
    private void DisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto SelfEntity = ck::ToEntity(this);

        auto Role = CkGym_Common::Get_NetworkRoleTitle(SelfEntity);
        auto HP = ck::IsValid(_Health)
            ? utils_float_attribute::Get_FinalValue(_Health, ECk_MinMaxCurrent::Current)
            : -1.0f;
        auto StateName = ck::IsValid(_StateMachine)
            ? Get_StateDisplayName(_StateMachine.Get_CurrentStateClass())
            : "?";

        // Is THIS pawn the one locally controlled on this world? Drives slot + colour.
        auto LocalResult = utils_net::Get_IsEntityLocallyControlled_ByPlayer(SelfEntity);
        // Get_IsEntityLocallyControlled_ByPlayer returns the LocallyControlled result enum.
        auto IsLocal = LocalResult == ECk_Utils_Net_IsLocallyControlled_Result::IsLocallyControlled;

        // Owning client kicks off the SM once it is locally controlling the pawn (possession
        // established). One-shot. Non-owning worlds receive the started SM via replication.
        if (IsLocal && !_StartRequested && ck::IsValid(_StateMachine))
        {
            _StateMachine.Request_Start();
            _StartRequested = true;
        }

        auto Tint = IsLocal ? FLinearColor(0.2f, 1.0f, 0.2f) : FLinearColor(1.0f, 0.9f, 0.2f);
        auto Tag = IsLocal ? "P-LOCAL" : "P-REMOTE";
        auto Label = f"[{Tag}] HP={HP} SM={StateName}";

        // --- Floating world-space text above the pawn ---
        auto TH = SelfEntity.As_Transform();
        if (ck::IsValid(TH))
        {
            auto Loc = utils_transform::Get_EntityCurrentTransform(TH).GetLocation();
            UCk_Utils_DebugDraw_UE::DrawDebugString(Loc + FVector(0.0, 0.0, 120.0), Label, Tint, 0.0f);
        }

        // --- On-screen text: two fixed slots (local = top, remote = below) ---
        auto ScreenY = IsLocal ? 60.0f : 90.0f;
        UCk_Utils_DebugDraw_Screen_UE::DrawDebugText_OnScreen(
            FVector2D(40.0, ScreenY), f"({Role}) {Label}", Tint, 1.2f);
    }

    private FString Get_StateDisplayName(TSubclassOf<UCk_SmState_EntityScript> InState)
    {
        if (InState == UCk_NetGym_State_Idle)       { return "Idle"; }
        if (InState == UCk_NetGym_State_Active)     { return "Active"; }
        if (InState == UCk_NetGym_State_Recovering) { return "Recovering"; }
        return "<none>";
    }
}
