// Language=angelscript

//============================================================================
// CkGoapGym — Patrol Route station entity  (PR-A canonical multi-tier)
//
// Canonical multi-tier Planner example demonstrating spec §2.2.
//
// Construction pattern (PR-A canonical idiom — only one construction verb):
//   1. utils_goap_planner::Add                → top-level Planner
//                                                (Set_WorldStateSource + Set_Goal
//                                                 on PlannerParams)
//   2. utils_goap_planner::AddAction          → first child = implicit root of
//                                                Patrol_Planner (runs A*)
//   3. utils_goap_planner::AddAction          → tree children of implicit root
//                                                (GoToWaypoint / Observe / MarkDone)
//   4. utils_goap_planner::PromoteActionToPlanner(GoToWaypoint, subParams)
//        → GoToWaypoint is now ALSO a Planner with goal AtWaypoint=true
//   5. utils_goap_planner::AddAction(GoToWaypoint_AsPlanner, RunParams)
//      utils_goap_planner::AddAction(GoToWaypoint_AsPlanner, WalkParams)
//        → Tier-3 leaves: direct tree children of the promoted GoToWaypoint
//   6. Repeat for Observe composite (goal AreaScanned=true)
//
// Entity hierarchy after construction:
//   Owner entity
//     Patrol_Planner              [Planner only]     goal: AreaPatrolled=true
//       Root                      [Action + implicit root]  eff: AreaPatrolled=true
//         GoToWaypoint            [Action+Planner]   eff: AtWaypoint=true
//           Run                   [Action]            eff: AtWaypoint=true (cost 1)
//           Walk                  [Action]            eff: AtWaypoint=true (cost 2)
//         Observe                 [Action+Planner]   eff: AreaScanned=true
//           LookAround            [Action]            eff: AreaScanned=true (cost 1)
//           WaitAtPost            [Action]            eff: AreaScanned=true (cost 3)
//         MarkDone                [Action]            eff: AreaPatrolled=true
//
// Player commands:
//   Goap.Patrol.SetAtWaypoint    — set AtWaypoint=true
//   Goap.Patrol.SetAreaScanned   — set AreaScanned=true
//   Goap.Patrol.Complete         — set AreaPatrolled=true
//   Goap.Patrol.Reset            — all back to false
//============================================================================

USTRUCT()
struct FCk_GoapGym_Patrol_Station_SpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;
}

class UCk_EntityScript_GoapGym_Patrol_Station : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    // ---- Tier-1 ----
    private FCk_Handle_Goap_Planner _TopPlanner;
    private FCk_Handle_Goap_Action  _RootAction;

    // ---- Tier-2 composites (Action+Planner) ----
    private FCk_Handle_Goap_Action  _GoToWaypoint_AsAction;
    private FCk_Handle_Goap_Planner _GoToWaypoint_AsPlanner;
    private FCk_Handle_Goap_Action  _Observe_AsAction;
    private FCk_Handle_Goap_Planner _Observe_AsPlanner;

    // ---- WorldState ----
    private FCk_Handle_Goap_WorldState _WS;

    // ---- Label maps for plan rendering ----
    private TArray<TSubclassOf<UCk_GoapAction_EntityScript>> _KnownClasses_Root;
    private TArray<FString> _KnownLabels_Root;
    private TArray<TSubclassOf<UCk_GoapAction_EntityScript>> _KnownClasses_GoTo;
    private TArray<FString> _KnownLabels_GoTo;
    private TArray<TSubclassOf<UCk_GoapAction_EntityScript>> _KnownClasses_Observe;
    private TArray<FString> _KnownLabels_Observe;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

        // ------------------------------------------------------------------
        // WorldState — all keys start false.
        // ------------------------------------------------------------------
        _WS = utils_goap_world_state::Create(InHandle,
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.Patrol"),
            FCk_Fragment_Goap_WorldState_ParamsData());
        Reset_WS();

        // ------------------------------------------------------------------
        // Tier 1 — Top-level Planner, goal: AreaPatrolled=true.
        // ------------------------------------------------------------------
        auto Goal = TArray<FCk_GoapWS_Condition_Authored>();
        Goal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.Patrol.AreaPatrolled"),
            true));

        auto PlannerParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.ActionSet.Patrol"));
        PlannerParams.Set_Goal(Goal);
        PlannerParams.Set_WorldStateSource(_WS);
        _TopPlanner = utils_goap_planner::Add(InHandle, PlannerParams);

        // Root action: first AddAction = implicit root that runs A*.
        // ReplanPolicy OnWorldStateDirty so WS changes auto-trigger replans.
        auto RootParams = FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_Patrol_Root);
        RootParams.Set_ReplanPolicy(ECk_Goap_ReplanPolicy::OnWorldStateDirty);
        _RootAction = utils_goap_planner::AddAction(_TopPlanner, RootParams);

        // ------------------------------------------------------------------
        // Tier 2a — GoToWaypoint composite.
        // Step 1: AddAction on the top-level Planner wires GoToWaypoint as a
        //         tree child of the implicit root (Root_Action).
        // Step 2: Promote to Planner with its own independent goal (AtWaypoint=true).
        // Step 3: Add Tier-3 leaf actions under its promoted Planner role.
        // ------------------------------------------------------------------
        auto GoToWaypointActionParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_GoapGym_Patrol_GoToWaypoint);
        GoToWaypointActionParams.Set_ReplanPolicy(ECk_Goap_ReplanPolicy::OnWorldStateDirty);
        _GoToWaypoint_AsAction = utils_goap_planner::AddAction(_TopPlanner, GoToWaypointActionParams);

        // Promote: GoToWaypoint entity now carries BOTH Action and Planner roles.
        auto GoToWaypointGoal = TArray<FCk_GoapWS_Condition_Authored>();
        GoToWaypointGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.Patrol.AtWaypoint"),
            true));
        auto GoToWaypointPlannerParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.ActionSet.Patrol.GoToWaypoint"));
        GoToWaypointPlannerParams.Set_Goal(GoToWaypointGoal);
        // Note: replan policy is carried by the ActionParamsData (set above on
        // GoToWaypointActionParams), not by PlannerParamsData.
        _GoToWaypoint_AsPlanner = utils_goap_planner::PromoteActionToPlanner(
            _GoToWaypoint_AsAction, GoToWaypointPlannerParams);

        // Tier-3 leaves under GoToWaypoint's Planner (direct tree children of
        // the promoted host — PR-A IsPromotedMidTier branch).
        utils_goap_planner::AddAction(_GoToWaypoint_AsPlanner,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_Patrol_Run));
        utils_goap_planner::AddAction(_GoToWaypoint_AsPlanner,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_Patrol_Walk));

        // ------------------------------------------------------------------
        // Tier 2b — Observe composite (same promotion pattern).
        // ------------------------------------------------------------------
        auto ObserveActionParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_GoapGym_Patrol_Observe);
        ObserveActionParams.Set_ReplanPolicy(ECk_Goap_ReplanPolicy::OnWorldStateDirty);
        _Observe_AsAction = utils_goap_planner::AddAction(_TopPlanner, ObserveActionParams);

        auto ObserveGoal = TArray<FCk_GoapWS_Condition_Authored>();
        ObserveGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.Patrol.AreaScanned"),
            true));
        auto ObservePlannerParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.ActionSet.Patrol.Observe"));
        ObservePlannerParams.Set_Goal(ObserveGoal);
        // Note: replan policy carried by ObserveActionParams (OnWorldStateDirty).
        _Observe_AsPlanner = utils_goap_planner::PromoteActionToPlanner(
            _Observe_AsAction, ObservePlannerParams);

        utils_goap_planner::AddAction(_Observe_AsPlanner,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_Patrol_LookAround));
        utils_goap_planner::AddAction(_Observe_AsPlanner,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_Patrol_WaitAtPost));

        // ------------------------------------------------------------------
        // Tier 2c — MarkDone atomic leaf (no Planner promotion needed).
        // ------------------------------------------------------------------
        utils_goap_planner::AddAction(_TopPlanner,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_Patrol_MarkDone));

        // ---- Label maps ----
        _KnownClasses_Root.Add(UCk_GoapGym_Patrol_GoToWaypoint); _KnownLabels_Root.Add("GoToWaypoint");
        _KnownClasses_Root.Add(UCk_GoapGym_Patrol_Observe);      _KnownLabels_Root.Add("Observe");
        _KnownClasses_Root.Add(UCk_GoapGym_Patrol_MarkDone);     _KnownLabels_Root.Add("MarkDone");

        _KnownClasses_GoTo.Add(UCk_GoapGym_Patrol_Run);  _KnownLabels_GoTo.Add("Run");
        _KnownClasses_GoTo.Add(UCk_GoapGym_Patrol_Walk); _KnownLabels_GoTo.Add("Walk");

        _KnownClasses_Observe.Add(UCk_GoapGym_Patrol_LookAround); _KnownLabels_Observe.Add("LookAround");
        _KnownClasses_Observe.Add(UCk_GoapGym_Patrol_WaitAtPost); _KnownLabels_Observe.Add("WaitAtPost");

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnDisplayTick"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    void Reset_WS()
    {
        if (ck::Is_NOT_Valid(_WS)) { return; }
        SetWS(n"Gym.Goap.WS.Patrol.AtWaypoint", false);
        SetWS(n"Gym.Goap.WS.Patrol.AreaScanned", false);
        SetWS(n"Gym.Goap.WS.Patrol.AreaPatrolled", false);
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
        if (ck::Is_NOT_Valid(_RootAction)) { return; }

        auto AtWaypoint   = GetWS(n"Gym.Goap.WS.Patrol.AtWaypoint");
        auto AreaScanned  = GetWS(n"Gym.Goap.WS.Patrol.AreaScanned");
        auto AreaPatrolled = GetWS(n"Gym.Goap.WS.Patrol.AreaPatrolled");

        auto Chain = utils_goap_planner::Get_ActiveChain(_TopPlanner);
        auto ChainLen = Chain.Num();

        // Root tier display.
        auto RootStatus = utils_goap_planner::Get_PlanStatus(_TopPlanner);
        auto RootPlan = utils_goap_planner::Get_PlanClasses(_TopPlanner);

        // GoToWaypoint sub-planner — only meaningful once chain reaches Tier-2.
        auto GoToStatus = "(not yet active)";
        auto GotoPlan = "(waiting)";
        if (ChainLen >= 2 && ck::IsValid(_GoToWaypoint_AsAction))
        {
            GoToStatus = CkGoapGym_Common::Format_PlanStatus(
                utils_goap_action::Get_PlanStatus(_GoToWaypoint_AsAction));
            GotoPlan = CkGoapGym_Common::Format_Plan(
                utils_goap_action::Get_Plan(_GoToWaypoint_AsAction),
                _KnownClasses_GoTo, _KnownLabels_GoTo);
        }

        // Observe sub-planner.
        auto ObserveStatus = "(not yet active)";
        auto ObservePlan = "(waiting)";
        if (ChainLen >= 2 && ck::IsValid(_Observe_AsAction))
        {
            ObserveStatus = CkGoapGym_Common::Format_PlanStatus(
                utils_goap_action::Get_PlanStatus(_Observe_AsAction));
            ObservePlan = CkGoapGym_Common::Format_Plan(
                utils_goap_action::Get_Plan(_Observe_AsAction),
                _KnownClasses_Observe, _KnownLabels_Observe);
        }

        auto Body = "World State\n"
            + f"  AtWaypoint      {CkGoapGym_Common::Render_Bool(AtWaypoint)}\n"
            + f"  AreaScanned     {CkGoapGym_Common::Render_Bool(AreaScanned)}\n"
            + f"  AreaPatrolled   {CkGoapGym_Common::Render_Bool(AreaPatrolled)}\n\n"
            + "Tier-1 Root Planner (goal: AreaPatrolled=true)\n"
            + f"  Status          {CkGoapGym_Common::Format_PlanStatus(RootStatus)}\n"
            + f"  Plan            {CkGoapGym_Common::Format_Plan(RootPlan, _KnownClasses_Root, _KnownLabels_Root)}\n"
            + f"  Chain length    {ChainLen}\n\n"
            + "Tier-2a GoToWaypoint Planner (goal: AtWaypoint=true)\n"
            + f"  Status          {GoToStatus}\n"
            + f"  Plan            {GotoPlan}\n\n"
            + "Tier-2b Observe Planner (goal: AreaScanned=true)\n"
            + f"  Status          {ObserveStatus}\n"
            + f"  Plan            {ObservePlan}\n\n"
            + "Console\n"
            + "  Goap.Patrol.SetAtWaypoint  / SetAreaScanned\n"
            + "  Goap.Patrol.Complete       / Reset";

        CkGym_Common::Update_StationDisplay(ck::ToEntity(this),
            "STATION 4 / PATROL ROUTE", Body,
            "Multi-tier Planner (U11.6). 3-deep chain:\n[Root, GoToWaypoint/Observe, Run/LookAround].");
    }
}
