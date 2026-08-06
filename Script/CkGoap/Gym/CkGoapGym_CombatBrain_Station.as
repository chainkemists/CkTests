// Language=angelscript

//============================================================================
// CkGoapGym — Combat Brain station entity  (3-tier canonical demo)
//
// Builds the canonical multi-tier example from spec §2.2 — one tier deeper
// than the Patrol station — with two sibling composites promoted at tier 2
// so the user can watch sibling branch selection happen at depth.
//
// PR-B.1b Stage 5: the implicit-root model is gone — Engage and Win are
// direct children of the Alive Planner.
//
// Construction sequence:
//   1. utils_goap_planner::Add(InHandle, AlivePlannerParams)
//        → top-level Alive Planner (goal: EnemyDead=true)
//   2. utils_goap_planner::AddAction(_Alive, EngageActionParams)
//        → Engage as Tier-1 Action under Alive
//   3. utils_goap_planner::AddAction(_Alive, WinParams)
//        → Win as Tier-1 atomic finisher under Alive
//   4. utils_goap_planner::PromoteActionToPlanner(_Engage, EngagePlannerParams)
//        → Engage gains the Planner role (sub-goal EnemyAttacked=true)
//   5. utils_goap_planner::AddAction(_Engage_AsPlanner, LightAttacksParams)
//      utils_goap_planner::AddAction(_Engage_AsPlanner, HeavyAttacksParams)
//        → Tier-2 composites under Engage
//   6. Promote each composite to a Planner (sub-goal EnemyHit=true).
//   7. utils_goap_planner::AddAction for Tier-3 leaves under each.
//
// Entity hierarchy after construction:
//   Owner entity
//     Alive_Planner            [Planner only]            goal: EnemyDead
//       Engage                 [Action + Planner]        eff: EnemyAttacked
//                                                        sub-goal: EnemyAttacked
//         LightAttacks         [Action + Planner]        eff: EnemyAttacked
//                                                        sub-goal: EnemyHit
//           Light1/Light2/Light3 [Action only]           eff: EnemyHit
//         HeavyAttacks         [Action + Planner]        eff: EnemyAttacked
//                                                        sub-goal: EnemyHit
//           Heavy1/Heavy2      [Action only]             eff: EnemyHit
//         Engage_HoldFire      [Action only]             eff: EnemyAttacked   (cost 999, fallback)
//       Win                    [Action only]             eff: EnemyDead
//       Standby                [Action only]             eff: EnemyDead       (cost 999, fallback)
//
// Always-valid-plan tenet (CkGoap/CLAUDE.md § "Design tenets"):
//   Standby is the top Alive fallback; Engage_HoldFire is the Engage sub-Planner
//   fallback. LightAttacks and HeavyAttacks sub-Planners already comply via
//   their precondition-less Light1..3 / Heavy1..2 leaves.
//============================================================================

USTRUCT()
struct FCk_GoapGym_CombatBrain_Station_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;
}

class UCk_EntityScript_GoapGym_CombatBrain_Station : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    // ---- Top-level Planner ----
    private FCk_Handle_Goap_Planner _AlivePlanner;

    // ---- Tier-1 ----
    private FCk_Handle_Goap_Action  _Engage_AsAction;
    private FCk_Handle_Goap_Planner _Engage_AsPlanner;
    private FCk_Handle_Goap_Action  _Win;

    // ---- Tier-2 ----
    private FCk_Handle_Goap_Action  _LightAttacks_AsAction;
    private FCk_Handle_Goap_Planner _LightAttacks_AsPlanner;
    private FCk_Handle_Goap_Action  _HeavyAttacks_AsAction;
    private FCk_Handle_Goap_Planner _HeavyAttacks_AsPlanner;

    // ---- WS ----
    private FCk_Handle_Goap_WorldState _WS;

    // ---- Label maps per tier (for plan rendering) ----
    private TArray<TSubclassOf<UCk_GoapAction_EntityScript>> _KnownClasses_Alive;
    private TArray<FString> _KnownLabels_Alive;
    private TArray<TSubclassOf<UCk_GoapAction_EntityScript>> _KnownClasses_Engage;
    private TArray<FString> _KnownLabels_Engage;
    private TArray<TSubclassOf<UCk_GoapAction_EntityScript>> _KnownClasses_Light;
    private TArray<FString> _KnownLabels_Light;
    private TArray<TSubclassOf<UCk_GoapAction_EntityScript>> _KnownClasses_Heavy;
    private TArray<FString> _KnownLabels_Heavy;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

        // ------------------------------------------------------------------
        // WorldState — all keys start false.
        // ------------------------------------------------------------------
        _WS = utils_goap_world_state::Create(InHandle,
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.CombatBrain"),
            FCk_Goap_WorldState_Spec());
        Reset_WS();

        // ------------------------------------------------------------------
        // Top-level Alive Planner, goal: EnemyDead=true.
        // ------------------------------------------------------------------
        auto AliveGoal = TArray<FCk_GoapWS_Condition_Authored>();
        AliveGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.CombatBrain.EnemyDead"),
            true));

        auto AlivePlannerParams = FCk_Goap_Planner_Spec(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.ActionSet.CombatBrain"));
        AlivePlannerParams.Set_Goal(AliveGoal);
        AlivePlannerParams.Set_WorldStateSource(_WS);
        AlivePlannerParams.Set_ReplanPolicy(ECk_Goap_ReplanPolicy::OnWorldStateDirty);
        _AlivePlanner = utils_goap_planner::Add(InHandle, AlivePlannerParams);

        // ------------------------------------------------------------------
        // Tier 1 — Engage Action under Alive (promoted to Planner below).
        // ------------------------------------------------------------------
        auto EngageActionParams = FCk_Goap_Action_Spec(
            UCk_GoapGym_CombatBrain_Engage);
        _Engage_AsAction = utils_goap_planner::AddAction(_AlivePlanner, EngageActionParams);

        // Tier 1 — Win atomic finisher under Alive.
        auto WinParams = FCk_Goap_Action_Spec(UCk_GoapGym_CombatBrain_Win);
        _Win = utils_goap_planner::AddAction(_AlivePlanner, WinParams);

        // Always-valid-plan tenet fallback for top Alive — see CkGoap/CLAUDE.md
        // § "Design tenets".
        utils_goap_planner::AddAction(_AlivePlanner,
            FCk_Goap_Action_Spec(UCk_GoapGym_CombatBrain_Standby));

        // Promote Engage: sub-goal EnemyAttacked=true.
        auto EngageGoal = TArray<FCk_GoapWS_Condition_Authored>();
        EngageGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.CombatBrain.EnemyAttacked"),
            true));
        auto EngagePlannerParams = FCk_Goap_Planner_Spec(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.ActionSet.CombatBrain.Engage"));
        EngagePlannerParams.Set_Goal(EngageGoal);
        EngagePlannerParams.Set_ReplanPolicy(ECk_Goap_ReplanPolicy::OnWorldStateDirty);
        _Engage_AsPlanner = utils_goap_planner::PromoteActionToPlanner(
            _Engage_AsAction, EngagePlannerParams);

        // ------------------------------------------------------------------
        // Tier 2 — LightAttacks + HeavyAttacks composites under Engage.
        // ------------------------------------------------------------------
        auto LightAttacksActionParams = FCk_Goap_Action_Spec(
            UCk_GoapGym_CombatBrain_LightAttacks);
        _LightAttacks_AsAction = utils_goap_planner::AddAction(
            _Engage_AsPlanner, LightAttacksActionParams);

        auto HeavyAttacksActionParams = FCk_Goap_Action_Spec(
            UCk_GoapGym_CombatBrain_HeavyAttacks);
        _HeavyAttacks_AsAction = utils_goap_planner::AddAction(
            _Engage_AsPlanner, HeavyAttacksActionParams);

        // Always-valid-plan tenet fallback for Engage sub-Planner — see
        // CkGoap/CLAUDE.md § "Design tenets".
        utils_goap_planner::AddAction(_Engage_AsPlanner,
            FCk_Goap_Action_Spec(UCk_GoapGym_CombatBrain_Engage_HoldFire));

        // Promote LightAttacks: sub-goal EnemyHit=true.
        auto LightAttacksGoal = TArray<FCk_GoapWS_Condition_Authored>();
        LightAttacksGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.CombatBrain.EnemyHit"),
            true));
        auto LightAttacksPlannerParams = FCk_Goap_Planner_Spec(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.ActionSet.CombatBrain.LightAttacks"));
        LightAttacksPlannerParams.Set_Goal(LightAttacksGoal);
        LightAttacksPlannerParams.Set_ReplanPolicy(ECk_Goap_ReplanPolicy::OnWorldStateDirty);
        _LightAttacks_AsPlanner = utils_goap_planner::PromoteActionToPlanner(
            _LightAttacks_AsAction, LightAttacksPlannerParams);

        // Promote HeavyAttacks: sub-goal EnemyHit=true (sibling planner).
        auto HeavyAttacksGoal = TArray<FCk_GoapWS_Condition_Authored>();
        HeavyAttacksGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.CombatBrain.EnemyHit"),
            true));
        auto HeavyAttacksPlannerParams = FCk_Goap_Planner_Spec(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.ActionSet.CombatBrain.HeavyAttacks"));
        HeavyAttacksPlannerParams.Set_Goal(HeavyAttacksGoal);
        HeavyAttacksPlannerParams.Set_ReplanPolicy(ECk_Goap_ReplanPolicy::OnWorldStateDirty);
        _HeavyAttacks_AsPlanner = utils_goap_planner::PromoteActionToPlanner(
            _HeavyAttacks_AsAction, HeavyAttacksPlannerParams);

        // ------------------------------------------------------------------
        // Tier 3 — atomic leaves under each promoted composite.
        // ------------------------------------------------------------------
        utils_goap_planner::AddAction(_LightAttacks_AsPlanner,
            FCk_Goap_Action_Spec(UCk_GoapGym_CombatBrain_Light1));
        utils_goap_planner::AddAction(_LightAttacks_AsPlanner,
            FCk_Goap_Action_Spec(UCk_GoapGym_CombatBrain_Light2));
        utils_goap_planner::AddAction(_LightAttacks_AsPlanner,
            FCk_Goap_Action_Spec(UCk_GoapGym_CombatBrain_Light3));

        utils_goap_planner::AddAction(_HeavyAttacks_AsPlanner,
            FCk_Goap_Action_Spec(UCk_GoapGym_CombatBrain_Heavy1));
        utils_goap_planner::AddAction(_HeavyAttacks_AsPlanner,
            FCk_Goap_Action_Spec(UCk_GoapGym_CombatBrain_Heavy2));

        // ---- Label maps ----
        _KnownClasses_Alive.Add(UCk_GoapGym_CombatBrain_Engage);
        _KnownLabels_Alive.Add("Engage");
        _KnownClasses_Alive.Add(UCk_GoapGym_CombatBrain_Win);
        _KnownLabels_Alive.Add("Win");
        _KnownClasses_Alive.Add(UCk_GoapGym_CombatBrain_Standby);
        _KnownLabels_Alive.Add("Standby");

        _KnownClasses_Engage.Add(UCk_GoapGym_CombatBrain_LightAttacks);
        _KnownLabels_Engage.Add("LightAttacks");
        _KnownClasses_Engage.Add(UCk_GoapGym_CombatBrain_HeavyAttacks);
        _KnownLabels_Engage.Add("HeavyAttacks");
        _KnownClasses_Engage.Add(UCk_GoapGym_CombatBrain_Engage_HoldFire);
        _KnownLabels_Engage.Add("HoldFire");

        _KnownClasses_Light.Add(UCk_GoapGym_CombatBrain_Light1);
        _KnownLabels_Light.Add("Light1");
        _KnownClasses_Light.Add(UCk_GoapGym_CombatBrain_Light2);
        _KnownLabels_Light.Add("Light2");
        _KnownClasses_Light.Add(UCk_GoapGym_CombatBrain_Light3);
        _KnownLabels_Light.Add("Light3");

        _KnownClasses_Heavy.Add(UCk_GoapGym_CombatBrain_Heavy1);
        _KnownLabels_Heavy.Add("Heavy1");
        _KnownClasses_Heavy.Add(UCk_GoapGym_CombatBrain_Heavy2);
        _KnownLabels_Heavy.Add("Heavy2");

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnDisplayTick"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    void Reset_WS()
    {
        if (ck::Is_NOT_Valid(_WS)) { return; }
        SetWS(n"Gym.Goap.WS.CombatBrain.EnemyVisible", false);
        SetWS(n"Gym.Goap.WS.CombatBrain.WeaponEquipped", false);
        SetWS(n"Gym.Goap.WS.CombatBrain.StaminaHigh", false);
        SetWS(n"Gym.Goap.WS.CombatBrain.EnemyHit", false);
        SetWS(n"Gym.Goap.WS.CombatBrain.EnemyAttacked", false);
        SetWS(n"Gym.Goap.WS.CombatBrain.EnemyDead", false);
    }

    void SetWS(FName InKey, bool InValue)
    {
        utils_goap_world_state::Set_Value(_WS,
            utils_gameplay_tag::ResolveGameplayTag(InKey), InValue);
    }

    private bool GetWS(FName InKey)
    {
        return utils_goap_world_state::Get_Value(_WS,
            utils_gameplay_tag::ResolveGameplayTag(InKey));
    }

    UFUNCTION()
    private void OnDisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (ck::Is_NOT_Valid(_AlivePlanner)) { return; }

        auto EnemyVisible    = GetWS(n"Gym.Goap.WS.CombatBrain.EnemyVisible");
        auto WeaponEquipped  = GetWS(n"Gym.Goap.WS.CombatBrain.WeaponEquipped");
        auto StaminaHigh     = GetWS(n"Gym.Goap.WS.CombatBrain.StaminaHigh");
        auto EnemyHit        = GetWS(n"Gym.Goap.WS.CombatBrain.EnemyHit");
        auto EnemyAttacked   = GetWS(n"Gym.Goap.WS.CombatBrain.EnemyAttacked");
        auto EnemyDead       = GetWS(n"Gym.Goap.WS.CombatBrain.EnemyDead");

        auto Chain = utils_goap_planner::Get_ActiveChain(_AlivePlanner);
        auto ChainLen = Chain.Num();

        // Top-level Alive.
        auto AliveStatus = utils_goap_planner::Get_PlanStatus(_AlivePlanner);
        auto AlivePlan   = utils_goap_planner::Get_PlanClasses(_AlivePlanner);

        // Tier-1 Engage (only meaningful once activation reaches it).
        auto EngageStatusStr = "(not yet active)";
        auto EngagePlanStr   = "(waiting)";
        if (ChainLen >= 1 && ck::IsValid(_Engage_AsAction))
        {
            EngageStatusStr = CkGoapGym_Common::Format_PlanStatus(
                utils_goap_action::Get_PlanStatus(_Engage_AsAction));
            EngagePlanStr = CkGoapGym_Common::Format_Plan(
                utils_goap_action::Get_Plan(_Engage_AsAction),
                _KnownClasses_Engage, _KnownLabels_Engage);
        }

        // Tier-2 LightAttacks.
        auto LightStatusStr = "(not yet active)";
        auto LightPlanStr   = "(waiting)";
        if (ChainLen >= 2 && ck::IsValid(_LightAttacks_AsAction))
        {
            LightStatusStr = CkGoapGym_Common::Format_PlanStatus(
                utils_goap_action::Get_PlanStatus(_LightAttacks_AsAction));
            LightPlanStr = CkGoapGym_Common::Format_Plan(
                utils_goap_action::Get_Plan(_LightAttacks_AsAction),
                _KnownClasses_Light, _KnownLabels_Light);
        }

        // Tier-2 HeavyAttacks.
        auto HeavyStatusStr = "(not yet active)";
        auto HeavyPlanStr   = "(waiting)";
        if (ChainLen >= 2 && ck::IsValid(_HeavyAttacks_AsAction))
        {
            HeavyStatusStr = CkGoapGym_Common::Format_PlanStatus(
                utils_goap_action::Get_PlanStatus(_HeavyAttacks_AsAction));
            HeavyPlanStr = CkGoapGym_Common::Format_Plan(
                utils_goap_action::Get_Plan(_HeavyAttacks_AsAction),
                _KnownClasses_Heavy, _KnownLabels_Heavy);
        }

        auto Body = "World State\n"
            + f"  EnemyVisible    {CkGoapGym_Common::Render_Bool(EnemyVisible)}\n"
            + f"  WeaponEquipped  {CkGoapGym_Common::Render_Bool(WeaponEquipped)}\n"
            + f"  StaminaHigh     {CkGoapGym_Common::Render_Bool(StaminaHigh)}\n"
            + f"  EnemyHit        {CkGoapGym_Common::Render_Bool(EnemyHit)}\n"
            + f"  EnemyAttacked   {CkGoapGym_Common::Render_Bool(EnemyAttacked)}\n"
            + f"  EnemyDead       {CkGoapGym_Common::Render_Bool(EnemyDead)}\n\n"
            + "Top Alive Planner (goal: EnemyDead=true)\n"
            + f"  Status          {CkGoapGym_Common::Format_PlanStatus(AliveStatus)}\n"
            + f"  Plan            {CkGoapGym_Common::Format_Plan(AlivePlan, _KnownClasses_Alive, _KnownLabels_Alive)}\n"
            + f"  Chain length    {ChainLen}\n\n"
            + "Tier-1 Engage Planner (goal: EnemyAttacked=true)\n"
            + f"  Status          {EngageStatusStr}\n"
            + f"  Plan            {EngagePlanStr}\n\n"
            + "Tier-2 LightAttacks Planner (goal: EnemyHit=true)\n"
            + f"  Status          {LightStatusStr}\n"
            + f"  Plan            {LightPlanStr}\n\n"
            + "Tier-2 HeavyAttacks Planner (goal: EnemyHit=true)\n"
            + f"  Status          {HeavyStatusStr}\n"
            + f"  Plan            {HeavyPlanStr}\n\n"
            + "Console (Goap.CombatBrain.*)\n"
            + "  Set/Clear EnemyVisible / WeaponEquipped / StaminaHigh\n"
            + "  Reset / Complete";

        CkGym_Common::Update_StationDisplay(ck::ToEntity(this),
            "STATION 6 / COMBAT BRAIN", Body,
            "Canonical 3-tier Planner (spec 2.2).\nAlive -> Engage -> Light/Heavy -> atomic leaves.");
    }
}
