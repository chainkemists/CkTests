// Language=angelscript

//============================================================================
// CkGoapFEAR_Gym — single-station F.E.A.R. combat AI
//
// Canonical "this is what GOAP is for" demo. Adapted from Jeff Orkin's
// F.E.A.R. AI paper. One top-level Planner (FEAR_Combatant) with a
// sub-Planner promoted at AttackEnemy.
//
// PR-B.1b Stage 5: the implicit-root model is gone — every Tier-1 Action is
// a direct child of FEAR_Combatant.
//
// Construction sequence:
//   1. utils_goap_world_state::Create(InHandle, "Gym.GoapFEAR.WS.Combatant", ...)
//        → WS entity. All keys reset by Reset_WS().
//   2. utils_goap_planner::Add(InHandle, CombatantPlannerParams)
//        → top-level FEAR_Combatant Planner (goal: EnemyNeutralized=true)
//   3. utils_goap_planner::AddAction(_Combatant, AttackEnemyParams)
//        → AttackEnemy as a tier-1 Action.
//   4. utils_goap_planner::AddAction(_Combatant, ...)
//        → Flank, TakeCover, Reload, Investigate, Patrol siblings.
//   5. utils_goap_planner::PromoteActionToPlanner(_AttackEnemy, ...)
//        → AttackEnemy gains the Planner role with sub-goal EnemyNeutralized.
//   6. utils_goap_planner::AddAction(_AttackEnemy_AsPlanner, ...)
//        → AttackFromCover, AttackFromFlank, AttackOpen leaves.
//
// Scenarios (toggle WS keys via Goap.FEAR.* console commands):
//
//   Default reset                                  [WaitForEnemy]                   cost 999  (fallback)
//   EnemyVisible=true                              [AttackEnemy -> AttackOpen]      cost 2.0
//   EnemyVisible=true, AtCover=true                [AttackEnemy -> AttackFromCover] cost 1.0
//   EnemyVisible=true, BehindEnemy=true            [AttackEnemy -> AttackFromFlank] cost 0.5  ← iconic
//   HeardSound=true, EnemyVisible=false            [Investigate -> AttackEnemy -> AttackOpen]
//   HasAmmo=false, HasAmmoReserve=true, Visible    [Reload -> AttackEnemy -> AttackOpen]
//   HasAmmo=false, Reserve=false, Visible          [WaitForEnemy] cost 999  (can't attack, can't reload — fall back)
//
// The WaitForEnemy fallback (no preconditions, cost 999, effect EnemyNeutralized)
// guarantees the top planner always returns a valid plan. "No plan" should
// always indicate a misconfigured Action catalog — never a normal operational
// state.
//
// The AttackEnemy SUB-Planner has its own fallback (AttackEnemy_Standby, cost
// 999) for the same reason: AttackFromCover/Flank/Open all carry HasAmmo +
// EnemyVisible preconditions, so without an unconditional sub-leaf the sub-
// Planner would hit PlanFailed whenever no concrete attack is viable. Both
// fallbacks comply with CkGoap/CLAUDE.md § "Design tenets / Every Planner
// must always produce a valid plan".
//============================================================================

USTRUCT()
struct FCk_GoapFEARGym_Combatant_Station_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;
}

class UCk_EntityScript_GoapFEARGym_Combatant_Station : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    // ---- Top-level Planner + Tier-1 ----
    private FCk_Handle_Goap_Planner _Combatant;
    private FCk_Handle_Goap_Action  _AttackEnemy_AsAction;
    private FCk_Handle_Goap_Planner _AttackEnemy_AsPlanner;
    private FCk_Handle_Goap_Action  _Flank;
    private FCk_Handle_Goap_Action  _TakeCover;
    private FCk_Handle_Goap_Action  _Reload;
    private FCk_Handle_Goap_Action  _Investigate;
    private FCk_Handle_Goap_Action  _Patrol;

    // ---- WS ----
    private FCk_Handle_Goap_WorldState _WS;

    // ---- Label maps for plan rendering ----
    private TArray<TSubclassOf<UCk_GoapAction_EntityScript>> _KnownClasses_Combatant;
    private TArray<FString> _KnownLabels_Combatant;
    private TArray<TSubclassOf<UCk_GoapAction_EntityScript>> _KnownClasses_Attack;
    private TArray<FString> _KnownLabels_Attack;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

        // ------------------------------------------------------------------
        // WorldState — see Reset_WS() for initial values.
        // ------------------------------------------------------------------
        _WS = utils_goap_world_state::Create(InHandle,
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.GoapFEAR.WS.Combatant"),
            FCk_Fragment_Goap_WorldState_ParamsData());
        Reset_WS();

        // ------------------------------------------------------------------
        // FEAR_Combatant top-level Planner.
        // Goal: EnemyNeutralized=true.
        // ------------------------------------------------------------------
        auto Goal = TArray<FCk_GoapWS_Condition_Authored>();
        Goal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.GoapFEAR.WS.Combatant.EnemyNeutralized"),
            true));

        auto PlannerParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.GoapFEAR.ActionSet.Combatant"));
        PlannerParams.Set_Goal(Goal);
        PlannerParams.Set_WorldStateSource(_WS);
        PlannerParams.Set_ReplanPolicy(ECk_Goap_ReplanPolicy::OnWorldStateDirty);
        _Combatant = utils_goap_planner::Add(InHandle, PlannerParams);

        // ------------------------------------------------------------------
        // Tier 1 children of FEAR_Combatant.
        // AttackEnemy comes first because it will be promoted next.
        // ------------------------------------------------------------------
        auto AttackEnemyParams = FCk_Fragment_Goap_ActionParamsData(UCk_GoapFEARGym_AttackEnemy);
        _AttackEnemy_AsAction = utils_goap_planner::AddAction(_Combatant, AttackEnemyParams);

        _Flank = utils_goap_planner::AddAction(_Combatant,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapFEARGym_Flank));
        _TakeCover = utils_goap_planner::AddAction(_Combatant,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapFEARGym_TakeCover));
        _Reload = utils_goap_planner::AddAction(_Combatant,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapFEARGym_Reload));
        _Investigate = utils_goap_planner::AddAction(_Combatant,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapFEARGym_Investigate));
        _Patrol = utils_goap_planner::AddAction(_Combatant,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapFEARGym_Patrol));

        // WaitForEnemy: fallback satisfying EnemyNeutralized at very high cost
        // so the planner ALWAYS has a valid plan even when no combat operator
        // is viable. "No plan" is treated as a misconfiguration error in
        // gameplay, never a normal idle state.
        utils_goap_planner::AddAction(_Combatant,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapFEARGym_WaitForEnemy));

        // ------------------------------------------------------------------
        // Promote AttackEnemy: sub-goal EnemyNeutralized=true.
        // The sub-Planner expands AttackEnemy into one of three concrete
        // attacks based on which preconditions are satisfied.
        // ------------------------------------------------------------------
        auto AttackGoal = TArray<FCk_GoapWS_Condition_Authored>();
        AttackGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.GoapFEAR.WS.Combatant.EnemyNeutralized"),
            true));
        auto AttackPlannerParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.GoapFEAR.ActionSet.Combatant.AttackEnemy"));
        AttackPlannerParams.Set_Goal(AttackGoal);
        AttackPlannerParams.Set_ReplanPolicy(ECk_Goap_ReplanPolicy::OnWorldStateDirty);
        _AttackEnemy_AsPlanner = utils_goap_planner::PromoteActionToPlanner(
            _AttackEnemy_AsAction, AttackPlannerParams);

        // ------------------------------------------------------------------
        // Tier 2 leaves under AttackEnemy's promoted Planner.
        // ------------------------------------------------------------------
        utils_goap_planner::AddAction(_AttackEnemy_AsPlanner,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapFEARGym_AttackFromCover));
        utils_goap_planner::AddAction(_AttackEnemy_AsPlanner,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapFEARGym_AttackFromFlank));
        utils_goap_planner::AddAction(_AttackEnemy_AsPlanner,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapFEARGym_AttackOpen));
        // Always-valid-plan tenet fallback for AttackEnemy sub-Planner — see
        // CkGoap/CLAUDE.md § "Design tenets".
        utils_goap_planner::AddAction(_AttackEnemy_AsPlanner,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapFEARGym_AttackEnemy_Standby));

        // ---- Label maps ----
        _KnownClasses_Combatant.Add(UCk_GoapFEARGym_AttackEnemy);
        _KnownLabels_Combatant.Add("AttackEnemy");
        _KnownClasses_Combatant.Add(UCk_GoapFEARGym_Flank);
        _KnownLabels_Combatant.Add("Flank");
        _KnownClasses_Combatant.Add(UCk_GoapFEARGym_TakeCover);
        _KnownLabels_Combatant.Add("TakeCover");
        _KnownClasses_Combatant.Add(UCk_GoapFEARGym_Reload);
        _KnownLabels_Combatant.Add("Reload");
        _KnownClasses_Combatant.Add(UCk_GoapFEARGym_Investigate);
        _KnownLabels_Combatant.Add("Investigate");
        _KnownClasses_Combatant.Add(UCk_GoapFEARGym_Patrol);
        _KnownLabels_Combatant.Add("Patrol");
        _KnownClasses_Combatant.Add(UCk_GoapFEARGym_WaitForEnemy);
        _KnownLabels_Combatant.Add("WaitForEnemy");

        _KnownClasses_Attack.Add(UCk_GoapFEARGym_AttackFromCover);
        _KnownLabels_Attack.Add("AttackFromCover");
        _KnownClasses_Attack.Add(UCk_GoapFEARGym_AttackFromFlank);
        _KnownLabels_Attack.Add("AttackFromFlank");
        _KnownClasses_Attack.Add(UCk_GoapFEARGym_AttackOpen);
        _KnownLabels_Attack.Add("AttackOpen");
        _KnownClasses_Attack.Add(UCk_GoapFEARGym_AttackEnemy_Standby);
        _KnownLabels_Attack.Add("AttackEnemy_Standby");

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnDisplayTick"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    void Reset_WS()
    {
        if (ck::Is_NOT_Valid(_WS)) { return; }
        SetWS(n"Gym.GoapFEAR.WS.Combatant.HasAmmo",          true);
        SetWS(n"Gym.GoapFEAR.WS.Combatant.HasAmmoReserve",   true);
        SetWS(n"Gym.GoapFEAR.WS.Combatant.EnemyVisible",     false);
        SetWS(n"Gym.GoapFEAR.WS.Combatant.EnemyNeutralized", false);
        SetWS(n"Gym.GoapFEAR.WS.Combatant.AtCover",          false);
        SetWS(n"Gym.GoapFEAR.WS.Combatant.BehindEnemy",      false);
        SetWS(n"Gym.GoapFEAR.WS.Combatant.HeardSound",       false);
        SetWS(n"Gym.GoapFEAR.WS.Combatant.Patrolling",       false);
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
        if (ck::Is_NOT_Valid(_Combatant)) { return; }

        auto EnemyVisible     = GetWS(n"Gym.GoapFEAR.WS.Combatant.EnemyVisible");
        auto EnemyNeutralized = GetWS(n"Gym.GoapFEAR.WS.Combatant.EnemyNeutralized");
        auto HasAmmo          = GetWS(n"Gym.GoapFEAR.WS.Combatant.HasAmmo");
        auto HasAmmoReserve   = GetWS(n"Gym.GoapFEAR.WS.Combatant.HasAmmoReserve");
        auto AtCover          = GetWS(n"Gym.GoapFEAR.WS.Combatant.AtCover");
        auto BehindEnemy      = GetWS(n"Gym.GoapFEAR.WS.Combatant.BehindEnemy");
        auto HeardSound       = GetWS(n"Gym.GoapFEAR.WS.Combatant.HeardSound");
        auto Patrolling       = GetWS(n"Gym.GoapFEAR.WS.Combatant.Patrolling");

        auto Chain = utils_goap_planner::Get_ActiveChain(_Combatant);
        auto ChainLen = Chain.Num();

        // Tier-1 FEAR_Combatant.
        auto TopStatus = utils_goap_planner::Get_PlanStatus(_Combatant);
        auto TopPlan   = utils_goap_planner::Get_PlanClasses(_Combatant);
        auto TopCost   = utils_goap_planner::Get_PlanCost(_Combatant);

        // Tier-2 AttackEnemy sub-Planner (only meaningful once activation reaches it).
        auto AttackStatusStr = "(not yet active)";
        auto AttackPlanStr   = "(waiting)";
        if (ChainLen >= 1 && ck::IsValid(_AttackEnemy_AsAction))
        {
            AttackStatusStr = CkGoapGym_Common::Format_PlanStatus(
                utils_goap_action::Get_PlanStatus(_AttackEnemy_AsAction));
            AttackPlanStr = CkGoapGym_Common::Format_Plan(
                utils_goap_action::Get_Plan(_AttackEnemy_AsAction),
                _KnownClasses_Attack, _KnownLabels_Attack);
        }

        auto Body = "A canonical GOAP enemy AI — adapted from Jeff Orkin's F.E.A.R.\n"
            + "paper. Toggle WS keys via the Console list below to see how\n"
            + "the planner adapts. Or click WS keys directly in the\n"
            + "debugger's WORLDSTATE panel.\n\n"
            + "WorldState\n"
            + f"  EnemyVisible       {CkGoapGym_Common::Render_Bool(EnemyVisible)}     (the target)\n"
            + f"  EnemyNeutralized   {CkGoapGym_Common::Render_Bool(EnemyNeutralized)}     (goal)\n"
            + f"  HasAmmo            {CkGoapGym_Common::Render_Bool(HasAmmo)}\n"
            + f"  HasAmmoReserve     {CkGoapGym_Common::Render_Bool(HasAmmoReserve)}\n"
            + f"  AtCover            {CkGoapGym_Common::Render_Bool(AtCover)}\n"
            + f"  BehindEnemy        {CkGoapGym_Common::Render_Bool(BehindEnemy)}\n"
            + f"  HeardSound         {CkGoapGym_Common::Render_Bool(HeardSound)}\n"
            + f"  Patrolling         {CkGoapGym_Common::Render_Bool(Patrolling)}\n\n"
            + "Top-level Planner (goal: EnemyNeutralized = true)\n"
            + f"  Status   {CkGoapGym_Common::Format_PlanStatus(TopStatus)}\n"
            + f"  Plan     {CkGoapGym_Common::Format_Plan(TopPlan, _KnownClasses_Combatant, _KnownLabels_Combatant)}\n"
            + f"  Cost     {TopCost}\n\n"
            + "AttackEnemy sub-Planner (goal: EnemyNeutralized = true)\n"
            + f"  Status   {AttackStatusStr}\n"
            + f"  Plan     {AttackPlanStr}\n\n"
            + "Console (Goap.FEAR.*)\n"
            + "  SetTargetVisible / ClearTargetVisible\n"
            + "  ToggleAtCover\n"
            + "  ToggleBehindEnemy\n"
            + "  ToggleHasAmmo\n"
            + "  ToggleHasAmmoReserve\n"
            + "  SetHeardSound / ClearHeardSound\n"
            + "  Reset\n"
            + "  IdealAmbush";

        CkGym_Common::Update_StationDisplay(ck::ToEntity(this),
            "STATION 1 / F.E.A.R. COMBATANT", Body,
            "Canonical GOAP demo — F.E.A.R.-style enemy AI.\nToggle WS keys to see the planner adapt.");
    }
}
