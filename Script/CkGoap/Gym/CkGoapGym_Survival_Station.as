// Language=angelscript

//============================================================================
// CkGoapGym — Survival Decision station entity
//
// One owner entity hosting TWO independent child Planners (via Create):
//   Planner "Hunger"   goal {Hungry=false}
//     ├── EatFood        pre {HasFood}  eff {Hungry=false}  cost 1
//     ├── Forage         pre {}         eff {HasFood=true}  cost 4
//     └── HuddleInPlace  pre {}         eff {Hungry=false}  cost 999  (fallback)
//   Planner "Defense"  goal {SafeFromThreat=true}
//     ├── FightEnemy   pre {ThreatActive, HasWeapon}  eff {SafeFromThreat=true}  cost 1
//     ├── RunAway      pre {ThreatActive}             eff {SafeFromThreat=true}  cost 3
//     └── RemainAlert  pre {}                          eff {SafeFromThreat=true}  cost 999  (fallback)
//
// Always-valid-plan tenet (CkGoap/CLAUDE.md § "Design tenets"):
//   HuddleInPlace and RemainAlert are the unconditional fallbacks for the
//   two Planners. They only win when no real Action chain is viable (e.g.
//   HasFood=false on Hunger; ThreatActive=false on Defense).
//
// Both Planners share the same WS entity but plan independently. Toggling
// HasFood / HasWeapon / ThreatActive on the same WS triggers replans on the
// matching Planner's root only — the unique-to-unified-model isolation.
//
// Player commands:
//   Goap.Survival.ToggleHungry         — flip Hungry (Hunger Planner goal).
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

    private FCk_Handle_Goap_Planner _Planner_Hunger;
    private FCk_Handle_Goap_Planner _Planner_Defense;
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
            FCk_Goap_WorldState_Spec());
        Reset_WS();

        // -------- Hunger Planner -------- (U11.1: goal on PlannerParams)
        auto HungerGoal = TArray<FCk_GoapWS_Condition_Authored>();
        HungerGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.Survival.Hungry"),
            false));

        auto HungerParams = FCk_Goap_Planner_Spec(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.ActionSet.Survival.Hunger"));
        HungerParams.Set_Goal(HungerGoal);
        HungerParams.Set_WorldStateSource(_WS);
        HungerParams.Set_ReplanPolicy(ECk_Goap_ReplanPolicy::OnWorldStateDirty);
        // Two independent Planners on one owner → Create (named child Planners).
        // Add stamps the Planner role onto InHandle directly and would reject the
        // second (Defense) Planner — one Planner role per entity.
        _Planner_Hunger = utils_goap_planner::Create(InHandle,
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.ActionSet.Survival.Hunger"),
            HungerParams);

        utils_goap_planner::AddAction(_Planner_Hunger,
            FCk_Goap_Action_Spec(UCk_GoapGym_Survival_EatFood));
        utils_goap_planner::AddAction(_Planner_Hunger,
            FCk_Goap_Action_Spec(UCk_GoapGym_Survival_Forage));
        // Always-valid-plan tenet fallback — see CkGoap/CLAUDE.md § "Design tenets".
        utils_goap_planner::AddAction(_Planner_Hunger,
            FCk_Goap_Action_Spec(UCk_GoapGym_Survival_HuddleInPlace));

        _KnownClasses_Hunger.Add(UCk_GoapGym_Survival_EatFood);       _KnownLabels_Hunger.Add("EatFood");
        _KnownClasses_Hunger.Add(UCk_GoapGym_Survival_Forage);        _KnownLabels_Hunger.Add("Forage");
        _KnownClasses_Hunger.Add(UCk_GoapGym_Survival_HuddleInPlace); _KnownLabels_Hunger.Add("HuddleInPlace");

        // -------- Defense Planner -------- (U11.1: goal on PlannerParams)
        auto DefenseGoal = TArray<FCk_GoapWS_Condition_Authored>();
        DefenseGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.Survival.SafeFromThreat"),
            true));

        auto DefenseParams = FCk_Goap_Planner_Spec(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.ActionSet.Survival.Defense"));
        DefenseParams.Set_Goal(DefenseGoal);
        DefenseParams.Set_WorldStateSource(_WS);
        DefenseParams.Set_ReplanPolicy(ECk_Goap_ReplanPolicy::OnWorldStateDirty);
        _Planner_Defense = utils_goap_planner::Create(InHandle,
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.ActionSet.Survival.Defense"),
            DefenseParams);

        utils_goap_planner::AddAction(_Planner_Defense,
            FCk_Goap_Action_Spec(UCk_GoapGym_Survival_FightEnemy));
        utils_goap_planner::AddAction(_Planner_Defense,
            FCk_Goap_Action_Spec(UCk_GoapGym_Survival_RunAway));
        // Always-valid-plan tenet fallback — see CkGoap/CLAUDE.md § "Design tenets".
        utils_goap_planner::AddAction(_Planner_Defense,
            FCk_Goap_Action_Spec(UCk_GoapGym_Survival_RemainAlert));

        _KnownClasses_Defense.Add(UCk_GoapGym_Survival_FightEnemy);  _KnownLabels_Defense.Add("FightEnemy");
        _KnownClasses_Defense.Add(UCk_GoapGym_Survival_RunAway);     _KnownLabels_Defense.Add("RunAway");
        _KnownClasses_Defense.Add(UCk_GoapGym_Survival_RemainAlert); _KnownLabels_Defense.Add("RemainAlert");

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
        if (ck::Is_NOT_Valid(_Planner_Hunger) || ck::Is_NOT_Valid(_Planner_Defense)) { return; }

        auto Hungry = Get(n"Gym.Goap.WS.Survival.Hungry");
        auto HasFood = Get(n"Gym.Goap.WS.Survival.HasFood");
        auto Threat = Get(n"Gym.Goap.WS.Survival.ThreatActive");
        auto HasWeapon = Get(n"Gym.Goap.WS.Survival.HasWeapon");
        auto Safe = Get(n"Gym.Goap.WS.Survival.SafeFromThreat");

        auto HStatus = utils_goap_planner::Get_PlanStatus(_Planner_Hunger);
        auto HPlan = utils_goap_planner::Get_PlanClasses(_Planner_Hunger);
        auto DStatus = utils_goap_planner::Get_PlanStatus(_Planner_Defense);
        auto DPlan = utils_goap_planner::Get_PlanClasses(_Planner_Defense);

        auto Body = "World State (shared by both Planners)\n"
            + f"  Hungry          {CkGoapGym_Common::Render_Bool(Hungry)}\n"
            + f"  HasFood         {CkGoapGym_Common::Render_Bool(HasFood)}\n"
            + f"  ThreatActive    {CkGoapGym_Common::Render_Bool(Threat)}\n"
            + f"  HasWeapon       {CkGoapGym_Common::Render_Bool(HasWeapon)}\n"
            + f"  SafeFromThreat  {CkGoapGym_Common::Render_Bool(Safe)}\n\n"
            + "Hunger Planner (goal Hungry=false)\n"
            + f"  Status   {CkGoapGym_Common::Format_PlanStatus(HStatus)}\n"
            + f"  Plan     {CkGoapGym_Common::Format_Plan(HPlan, _KnownClasses_Hunger, _KnownLabels_Hunger)}\n\n"
            + "Defense Planner (goal SafeFromThreat=true)\n"
            + f"  Status   {CkGoapGym_Common::Format_PlanStatus(DStatus)}\n"
            + f"  Plan     {CkGoapGym_Common::Format_Plan(DPlan, _KnownClasses_Defense, _KnownLabels_Defense)}\n\n"
            + "Console\n"
            + "  Goap.Survival.ToggleHungry / HasFood\n"
            + "  Goap.Survival.ToggleThreat / HasWeapon\n"
            + "  Goap.Survival.Reset";

        CkGym_Common::Update_StationDisplay(ck::ToEntity(this),
            "STATION 5 / SURVIVAL DECISION", Body,
            "Two Planners on one entity. Independent planning + replan.");
    }
}
