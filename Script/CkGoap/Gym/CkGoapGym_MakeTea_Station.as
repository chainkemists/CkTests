// Language=angelscript

//============================================================================
// CkGoapGym — Make Tea station entity
//
// Four-step linear dependency chain. Plan resolves to:
//   [BoilWater, SteepLeaves, PourCup, Serve]
//
// Initial WS has all ingredients (HasKettle/HasWater/HasTeaLeaves/HasCup).
// Drop any ingredient via the per-key toggle exec to see the plan collapse
// to PlanFailed.
//
// Player commands:
//   Goap.Tea.ToggleKettle / ToggleWater / ToggleLeaves / ToggleCup
//     — flip each ingredient WS bit.
//   Goap.Tea.Reset
//     — restore all ingredients (true) and clear partial-progress bits.
//============================================================================

USTRUCT()
struct FCk_GoapGym_MakeTea_Station_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;
}

class UCk_EntityScript_GoapGym_MakeTea_Station : UCk_GenericEntityScript_UE
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
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.Tea"),
            FCk_Fragment_Goap_WorldState_ParamsData());
        Reset_WS_To_AllIngredients();

        // U11.1: Planner goal on PlannerParams.
        auto Goal = TArray<FCk_GoapWS_Condition_Authored>();
        Goal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.Tea.TeaServed"),
            true));

        auto ActionSetParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.ActionSet.Tea"));
        ActionSetParams.Set_Goal(Goal);
        ActionSetParams.Set_WorldStateSource(_WS);
        ActionSetParams.Set_ReplanPolicy(ECk_Goap_ReplanPolicy::OnWorldStateDirty);
        _Planner = utils_goap_planner::Add(InHandle, ActionSetParams);

        utils_goap_planner::AddAction(_Planner,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_MakeTea_BoilWater));
        utils_goap_planner::AddAction(_Planner,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_MakeTea_SteepLeaves));
        utils_goap_planner::AddAction(_Planner,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_MakeTea_PourCup));
        utils_goap_planner::AddAction(_Planner,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_MakeTea_Serve));

        _KnownClasses.Add(UCk_GoapGym_MakeTea_BoilWater);   _KnownLabels.Add("BoilWater");
        _KnownClasses.Add(UCk_GoapGym_MakeTea_SteepLeaves); _KnownLabels.Add("SteepLeaves");
        _KnownClasses.Add(UCk_GoapGym_MakeTea_PourCup);     _KnownLabels.Add("PourCup");
        _KnownClasses.Add(UCk_GoapGym_MakeTea_Serve);       _KnownLabels.Add("Serve");

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnDisplayTick"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    private void Reset_WS_To_AllIngredients()
    {
        if (ck::Is_NOT_Valid(_WS)) { return; }
        Set(n"Gym.Goap.WS.Tea.HasKettle", true);
        Set(n"Gym.Goap.WS.Tea.HasWater", true);
        Set(n"Gym.Goap.WS.Tea.HasTeaLeaves", true);
        Set(n"Gym.Goap.WS.Tea.HasCup", true);
        Set(n"Gym.Goap.WS.Tea.WaterBoiled", false);
        Set(n"Gym.Goap.WS.Tea.TeaSteeped", false);
        Set(n"Gym.Goap.WS.Tea.TeaPoured", false);
        Set(n"Gym.Goap.WS.Tea.TeaServed", false);
    }

    private void Set(FName InKey, bool InValue)
    {
        utils_goap_world_state::Set_Value(_WS,
            utils_gameplay_tag::ResolveGameplayTag(InKey), InValue);
    }

    UFUNCTION()
    private void OnDisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (ck::Is_NOT_Valid(_Planner)) { return; }

        auto HasKettle  = Get(n"Gym.Goap.WS.Tea.HasKettle");
        auto HasWater   = Get(n"Gym.Goap.WS.Tea.HasWater");
        auto HasLeaves  = Get(n"Gym.Goap.WS.Tea.HasTeaLeaves");
        auto HasCup     = Get(n"Gym.Goap.WS.Tea.HasCup");
        auto WaterBoiled = Get(n"Gym.Goap.WS.Tea.WaterBoiled");
        auto TeaSteeped = Get(n"Gym.Goap.WS.Tea.TeaSteeped");
        auto TeaPoured  = Get(n"Gym.Goap.WS.Tea.TeaPoured");
        auto TeaServed  = Get(n"Gym.Goap.WS.Tea.TeaServed");

        auto Status = utils_goap_planner::Get_PlanStatus(_Planner);
        auto Plan = utils_goap_planner::Get_PlanClasses(_Planner);

        auto Body = "Ingredients\n"
            + f"  HasKettle      {CkGoapGym_Common::Render_Bool(HasKettle)}\n"
            + f"  HasWater       {CkGoapGym_Common::Render_Bool(HasWater)}\n"
            + f"  HasTeaLeaves   {CkGoapGym_Common::Render_Bool(HasLeaves)}\n"
            + f"  HasCup         {CkGoapGym_Common::Render_Bool(HasCup)}\n\n"
            + "Progress\n"
            + f"  WaterBoiled    {CkGoapGym_Common::Render_Bool(WaterBoiled)}\n"
            + f"  TeaSteeped     {CkGoapGym_Common::Render_Bool(TeaSteeped)}\n"
            + f"  TeaPoured      {CkGoapGym_Common::Render_Bool(TeaPoured)}\n"
            + f"  TeaServed      {CkGoapGym_Common::Render_Bool(TeaServed)}\n\n"
            + "Planner\n"
            + f"  Status         {CkGoapGym_Common::Format_PlanStatus(Status)}\n"
            + f"  Plan           {CkGoapGym_Common::Format_Plan(Plan, _KnownClasses, _KnownLabels)}\n\n"
            + "Console\n"
            + "  Goap.Tea.ToggleKettle / Water / Leaves / Cup\n"
            + "  Goap.Tea.Reset";

        CkGym_Common::Update_StationDisplay(ck::ToEntity(this),
            "STATION 2 / MAKE TEA", Body,
            "4-step dependency chain. Drop an ingredient to see PlanFailed.");
    }

    private bool Get(FName InKey)
    {
        return utils_goap_world_state::Get_Value(_WS,
            utils_gameplay_tag::ResolveGameplayTag(InKey));
    }
}
