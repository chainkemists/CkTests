// Language=angelscript

//============================================================================
// CkGoapEmpire_Gym — single-station 5-action plan
//
// Plan resolves to 5 steps. Player commands:
//   Goap.Empire.ToggleFood / Gold / Wood / Barracks / Feudal
//     — flip each resource WS bit individually.
//   Goap.Empire.Reset
//     — clear everything to false.
//============================================================================

USTRUCT()
struct FCk_GoapGym_Empire_Station_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;
}

class UCk_EntityScript_GoapGym_Empire_Station : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    private FCk_Handle_Goap_Planner _Planner;
    private FCk_Handle_Goap_WorldState _WS;
    private TArray<TSubclassOf<UCk_GoapAction_EntityScript>> _KnownClasses;
    private TArray<FString> _KnownLabels;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

        _WS = utils_goap_world_state::Create(InHandle,
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.Empire"),
            FCk_Fragment_Goap_WorldState_ParamsData());
        Reset_WS();

        // U11.1: Planner goal on PlannerParams.
        auto Goal = TArray<FCk_GoapWS_Condition_Authored>();
        Goal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.Empire.FeudalResearched"),
            true));

        auto ActionSetParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.ActionSet.Empire"));
        ActionSetParams.Set_Goal(Goal);
        ActionSetParams.Set_WorldStateSource(_WS);
        ActionSetParams.Set_ReplanPolicy(ECk_Goap_ReplanPolicy::OnWorldStateDirty);
        _Planner = utils_goap_planner::Add(InHandle, ActionSetParams);

        utils_goap_planner::AddAction(_Planner,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_Empire_GatherFood));
        utils_goap_planner::AddAction(_Planner,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_Empire_GatherGold));
        utils_goap_planner::AddAction(_Planner,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_Empire_GatherWood));
        utils_goap_planner::AddAction(_Planner,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_Empire_BuildBarracks));
        utils_goap_planner::AddAction(_Planner,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_Empire_ResearchFeudal));
        // Always-valid-plan tenet fallback — see CkGoap/CLAUDE.md § "Design tenets".
        utils_goap_planner::AddAction(_Planner,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_Empire_WaitForOrders));

        _KnownClasses.Add(UCk_GoapGym_Empire_GatherFood);     _KnownLabels.Add("GatherFood");
        _KnownClasses.Add(UCk_GoapGym_Empire_GatherGold);     _KnownLabels.Add("GatherGold");
        _KnownClasses.Add(UCk_GoapGym_Empire_GatherWood);     _KnownLabels.Add("GatherWood");
        _KnownClasses.Add(UCk_GoapGym_Empire_BuildBarracks);  _KnownLabels.Add("BuildBarracks");
        _KnownClasses.Add(UCk_GoapGym_Empire_ResearchFeudal); _KnownLabels.Add("ResearchFeudal");
        _KnownClasses.Add(UCk_GoapGym_Empire_WaitForOrders);  _KnownLabels.Add("WaitForOrders");

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnDisplayTick"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    private void Reset_WS()
    {
        if (ck::Is_NOT_Valid(_WS)) { return; }
        Set(n"Gym.Goap.WS.Empire.HasFood", false);
        Set(n"Gym.Goap.WS.Empire.HasGold", false);
        Set(n"Gym.Goap.WS.Empire.HasWood", false);
        Set(n"Gym.Goap.WS.Empire.BarracksBuilt", false);
        Set(n"Gym.Goap.WS.Empire.FeudalResearched", false);
    }

    private void Set(FName InKey, bool InValue)
    {
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
        if (ck::Is_NOT_Valid(_Planner)) { return; }

        auto F = Get(n"Gym.Goap.WS.Empire.HasFood");
        auto G = Get(n"Gym.Goap.WS.Empire.HasGold");
        auto W = Get(n"Gym.Goap.WS.Empire.HasWood");
        auto B = Get(n"Gym.Goap.WS.Empire.BarracksBuilt");
        auto Fr = Get(n"Gym.Goap.WS.Empire.FeudalResearched");

        auto Status = utils_goap_planner::Get_PlanStatus(_Planner);
        auto Plan = utils_goap_planner::Get_PlanClasses(_Planner);
        auto Cost = utils_goap_planner::Get_PlanCost(_Planner);

        auto Body = "Resources / Progress\n"
            + f"  HasFood            {CkGoapGym_Common::Render_Bool(F)}\n"
            + f"  HasGold            {CkGoapGym_Common::Render_Bool(G)}\n"
            + f"  HasWood            {CkGoapGym_Common::Render_Bool(W)}\n"
            + f"  BarracksBuilt      {CkGoapGym_Common::Render_Bool(B)}\n"
            + f"  FeudalResearched   {CkGoapGym_Common::Render_Bool(Fr)}\n\n"
            + "Operators (cost)\n"
            + "  GatherFood       3   pre (none)\n"
            + "  GatherGold       4   pre (none)\n"
            + "  GatherWood       2   pre (none)\n"
            + "  BuildBarracks    5   pre Food, Gold, Wood\n"
            + "  ResearchFeudal   6   pre Barracks, Food\n\n"
            + "Planner\n"
            + f"  Status        {CkGoapGym_Common::Format_PlanStatus(Status)}\n"
            + f"  Plan length   {Plan.Num()}\n"
            + f"  Plan          {CkGoapGym_Common::Format_Plan(Plan, _KnownClasses, _KnownLabels)}\n"
            + f"  Plan cost     {Cost}\n\n"
            + "Console\n"
            + "  Goap.Empire.ToggleFood / Gold / Wood / Barracks / Feudal\n"
            + "  Goap.Empire.Reset";

        CkGym_Common::Update_StationDisplay(ck::ToEntity(this),
            "EMPIRE / FEUDAL RESEARCH", Body,
            "5-step plan from raw gathering to research.\nFlip any WS bit and watch the plan re-resolve.");
    }
}
