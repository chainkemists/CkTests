// Language=angelscript

//============================================================================
// CkGoapGym — Cross River station entity
//
// Branching plan with cost sensitivity.
//
// Initial WS: BridgeIsOpen=true, HasCoin=true, Crossed=false.
// Plan: [UseBridge] (cost 2 — lowest).
//
// Player commands:
//   Goap.River.ToggleBridge — Bridge becomes blocked → plan flips to UseFerry.
//   Goap.River.SpendCoin    — coin gone too → plan flips to SwimAcross.
//   Goap.River.Reset        — restore both, plan returns to UseBridge.
//============================================================================

USTRUCT()
struct FCk_GoapGym_CrossRiver_Station_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;
}

class UCk_EntityScript_GoapGym_CrossRiver_Station : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    private FCk_Handle_Goap_Planner _Planner;
    private FCk_Handle_Goap_Action _RootAction;
    private FCk_Handle_Goap_WorldState _WS;
    private TArray<TSubclassOf<UCk_GoapAction_EntityScript>> _KnownClasses;
    private TArray<FString> _KnownLabels;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

        _WS = utils_goap_world_state::Create(InHandle,
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.CrossRiver"),
            FCk_Fragment_Goap_WorldState_ParamsData());
        Set(n"Gym.Goap.WS.CrossRiver.BridgeIsOpen", true);
        Set(n"Gym.Goap.WS.CrossRiver.HasCoin", true);
        Set(n"Gym.Goap.WS.CrossRiver.Crossed", false);

        // U11.1: Planner goal on PlannerParams.
        auto Goal = TArray<FCk_GoapWS_Condition_Authored>();
        Goal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.CrossRiver.Crossed"),
            true));

        auto ActionSetParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.ActionSet.CrossRiver"));
        ActionSetParams.Set_Goal(Goal);
        ActionSetParams.Set_WorldStateSource(_WS);
        ActionSetParams.Set_ReplanPolicy(ECk_Goap_ReplanPolicy::OnWorldStateDirty);
        _Planner = utils_goap_planner::Add(InHandle, ActionSetParams);

        auto RootParams = FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_CrossRiver_Root);

        _RootAction = utils_goap_planner::AddAction(_Planner, RootParams);

        utils_goap_planner::AddAction(_Planner,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_CrossRiver_UseBridge));
        utils_goap_planner::AddAction(_Planner,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_CrossRiver_UseFerry));
        utils_goap_planner::AddAction(_Planner,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_CrossRiver_SwimAcross));

        _KnownClasses.Add(UCk_GoapGym_CrossRiver_UseBridge);  _KnownLabels.Add("UseBridge");
        _KnownClasses.Add(UCk_GoapGym_CrossRiver_UseFerry);   _KnownLabels.Add("UseFerry");
        _KnownClasses.Add(UCk_GoapGym_CrossRiver_SwimAcross); _KnownLabels.Add("SwimAcross");

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnDisplayTick"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    private void Set(FName InKey, bool InValue)
    {
        if (ck::Is_NOT_Valid(_WS)) { return; }
        utils_goap_world_state::Set_Value(_WS,
            utils_gameplay_tag::ResolveGameplayTag(InKey), InValue);
    }

    private bool Get(FName InKey)
    {
        return utils_goap_world_state::Get_Value(_WS,
            utils_gameplay_tag::ResolveGameplayTag(InKey));
    }

    UFUNCTION()
    private void OnDisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (ck::Is_NOT_Valid(_RootAction)) { return; }

        auto BridgeOpen = Get(n"Gym.Goap.WS.CrossRiver.BridgeIsOpen");
        auto HasCoin = Get(n"Gym.Goap.WS.CrossRiver.HasCoin");
        auto Crossed = Get(n"Gym.Goap.WS.CrossRiver.Crossed");

        auto Status = utils_goap_planner::Get_PlanStatus(_Planner);
        auto Plan = utils_goap_planner::Get_PlanClasses(_Planner);
        auto Cost = utils_goap_planner::Get_PlanCost(_Planner);

        auto Body = "World State\n"
            + f"  BridgeIsOpen   {CkGoapGym_Common::Render_Bool(BridgeOpen)}\n"
            + f"  HasCoin        {CkGoapGym_Common::Render_Bool(HasCoin)}\n"
            + f"  Crossed        {CkGoapGym_Common::Render_Bool(Crossed)}\n\n"
            + "Operators (cost)\n"
            + "  UseBridge   2   pre BridgeIsOpen\n"
            + "  UseFerry    4   pre HasCoin\n"
            + "  SwimAcross  8   pre (none)\n\n"
            + "Planner\n"
            + f"  Status         {CkGoapGym_Common::Format_PlanStatus(Status)}\n"
            + f"  Plan           {CkGoapGym_Common::Format_Plan(Plan, _KnownClasses, _KnownLabels)}\n"
            + f"  Plan cost      {Cost}\n\n"
            + "Console\n"
            + "  Goap.River.ToggleBridge  Block / open the bridge\n"
            + "  Goap.River.SpendCoin     Lose the coin (one-way)\n"
            + "  Goap.River.Reset         Restore initial WS";

        CkGym_Common::Update_StationDisplay(ck::ToEntity(this),
            "STATION 3 / CROSS RIVER", Body,
            "Branching: 3 operators, same effect, different costs.\nLowest-cost branch wins; replans on WS flips.");
    }
}
