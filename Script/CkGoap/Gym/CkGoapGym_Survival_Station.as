// Language=angelscript

//============================================================================
// CkGoapGym — Survival Decision station entity
//
// Single entity with TWO ActionSets on one Goap root:
//   ActionSet "Hunger"   goal {Hungry=false}
//     ├── EatFood   pre {HasFood}  eff {Hungry=false}  cost 1
//     └── Forage    pre {}         eff {HasFood=true}  cost 4
//   ActionSet "Defense"  goal {SafeFromThreat=true}
//     ├── FightEnemy pre {ThreatActive, HasWeapon}  eff {SafeFromThreat=true}  cost 1
//     └── RunAway    pre {ThreatActive}             eff {SafeFromThreat=true}  cost 3
//
// Both ActionSets share the same WS entity but plan independently. Toggling
// HasFood / HasWeapon / ThreatActive on the same WS triggers replans on the
// matching ActionSet's root only — the unique-to-unified-model isolation.
//
// Player commands:
//   Goap.Survival.ToggleHungry         — flip Hungry (Hunger ActionSet goal).
//   Goap.Survival.ToggleHasFood        — flip HasFood.
//   Goap.Survival.ToggleThreat         — flip ThreatActive.
//   Goap.Survival.ToggleHasWeapon      — flip HasWeapon.
//   Goap.Survival.Reset                — Hungry=true, HasFood=false,
//                                        ThreatActive=true, HasWeapon=true.
//============================================================================

USTRUCT()
struct FCk_GoapGym_Survival_Station_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;
}

class UCk_EntityScript_GoapGym_Survival_Station : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    private FCk_Handle_Goap_Planner _ActionSet_Hunger;
    private FCk_Handle_Goap_Planner _ActionSet_Defense;
    private FCk_Handle_Goap_Action _Root_Hunger;
    private FCk_Handle_Goap_Action _Root_Defense;
    private FCk_Handle_Goap_WorldState _WS;

    private TArray<TSubclassOf<UCk_GoapAction_EntityScript>> _KnownClasses_Hunger;
    private TArray<FString> _KnownLabels_Hunger;
    private TArray<TSubclassOf<UCk_GoapAction_EntityScript>> _KnownClasses_Defense;
    private TArray<FString> _KnownLabels_Defense;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

        _WS = utils_goap_world_state::Create(InHandle,
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.Survival"),
            FCk_Fragment_Goap_WorldState_ParamsData());
        Reset_WS();

        // -------- Hunger ActionSet --------
        auto HungerParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.ActionSet.Survival.Hunger"));
        _ActionSet_Hunger = utils_goap_planner::Add(InHandle, HungerParams);

        auto HungerGoal = TArray<FCk_GoapWS_Condition_Authored>();
        HungerGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.Survival.Hungry"),
            false));
        auto HungerRootParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_GoapGym_Survival_HungerRoot);
        HungerRootParams.Set_InitialGoal_RootOnly(HungerGoal);
        HungerRootParams.Set_ReplanPolicy(ECk_Goap_ReplanPolicy::OnWorldStateDirty);
        _Root_Hunger = utils_goap_planner::SetRootAction(_ActionSet_Hunger, HungerRootParams, _WS);

        utils_goap_action::AddAction_ToAction(_Root_Hunger,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_Survival_EatFood));
        utils_goap_action::AddAction_ToAction(_Root_Hunger,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_Survival_Forage));

        _KnownClasses_Hunger.Add(UCk_GoapGym_Survival_EatFood); _KnownLabels_Hunger.Add("EatFood");
        _KnownClasses_Hunger.Add(UCk_GoapGym_Survival_Forage);  _KnownLabels_Hunger.Add("Forage");

        // -------- Defense ActionSet --------
        auto DefenseParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.ActionSet.Survival.Defense"));
        _ActionSet_Defense = utils_goap_planner::Add(InHandle, DefenseParams);

        auto DefenseGoal = TArray<FCk_GoapWS_Condition_Authored>();
        DefenseGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.Survival.SafeFromThreat"),
            true));
        auto DefenseRootParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_GoapGym_Survival_DefenseRoot);
        DefenseRootParams.Set_InitialGoal_RootOnly(DefenseGoal);
        DefenseRootParams.Set_ReplanPolicy(ECk_Goap_ReplanPolicy::OnWorldStateDirty);
        _Root_Defense = utils_goap_planner::SetRootAction(_ActionSet_Defense, DefenseRootParams, _WS);

        utils_goap_action::AddAction_ToAction(_Root_Defense,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_Survival_FightEnemy));
        utils_goap_action::AddAction_ToAction(_Root_Defense,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_Survival_RunAway));

        _KnownClasses_Defense.Add(UCk_GoapGym_Survival_FightEnemy); _KnownLabels_Defense.Add("FightEnemy");
        _KnownClasses_Defense.Add(UCk_GoapGym_Survival_RunAway);    _KnownLabels_Defense.Add("RunAway");

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnDisplayTick"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    private void Reset_WS()
    {
        if (ck::Is_NOT_Valid(_WS)) { return; }
        Set(n"Gym.Goap.WS.Survival.Hungry", true);
        Set(n"Gym.Goap.WS.Survival.HasFood", false);
        Set(n"Gym.Goap.WS.Survival.ThreatActive", true);
        Set(n"Gym.Goap.WS.Survival.HasWeapon", true);
        Set(n"Gym.Goap.WS.Survival.SafeFromThreat", false);
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
        if (ck::Is_NOT_Valid(_Root_Hunger) || ck::Is_NOT_Valid(_Root_Defense)) { return; }

        auto Hungry = Get(n"Gym.Goap.WS.Survival.Hungry");
        auto HasFood = Get(n"Gym.Goap.WS.Survival.HasFood");
        auto Threat = Get(n"Gym.Goap.WS.Survival.ThreatActive");
        auto HasWeapon = Get(n"Gym.Goap.WS.Survival.HasWeapon");
        auto Safe = Get(n"Gym.Goap.WS.Survival.SafeFromThreat");

        auto HStatus = utils_goap_action::Get_PlanStatus(_Root_Hunger);
        auto HPlan = utils_goap_action::Get_Plan(_Root_Hunger);
        auto DStatus = utils_goap_action::Get_PlanStatus(_Root_Defense);
        auto DPlan = utils_goap_action::Get_Plan(_Root_Defense);

        auto Body = "World State (shared by both ActionSets)\n"
            + f"  Hungry          {CkGoapGym_Common::Render_Bool(Hungry)}\n"
            + f"  HasFood         {CkGoapGym_Common::Render_Bool(HasFood)}\n"
            + f"  ThreatActive    {CkGoapGym_Common::Render_Bool(Threat)}\n"
            + f"  HasWeapon       {CkGoapGym_Common::Render_Bool(HasWeapon)}\n"
            + f"  SafeFromThreat  {CkGoapGym_Common::Render_Bool(Safe)}\n\n"
            + "Hunger ActionSet (goal Hungry=false)\n"
            + f"  Status   {CkGoapGym_Common::Format_PlanStatus(HStatus)}\n"
            + f"  Plan     {CkGoapGym_Common::Format_Plan(HPlan, _KnownClasses_Hunger, _KnownLabels_Hunger)}\n\n"
            + "Defense ActionSet (goal SafeFromThreat=true)\n"
            + f"  Status   {CkGoapGym_Common::Format_PlanStatus(DStatus)}\n"
            + f"  Plan     {CkGoapGym_Common::Format_Plan(DPlan, _KnownClasses_Defense, _KnownLabels_Defense)}\n\n"
            + "Buttons\n"
            + "  Goap.Survival.ToggleHungry / HasFood\n"
            + "  Goap.Survival.ToggleThreat / HasWeapon\n"
            + "  Goap.Survival.Reset";

        CkGym_Common::Update_StationDisplay(ck::ToEntity(this),
            "STATION 5 / SURVIVAL DECISION", Body,
            "Two ActionSets on one entity. Independent planning + replan.");
    }
}
