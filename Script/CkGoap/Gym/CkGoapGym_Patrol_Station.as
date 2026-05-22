// Language=angelscript

//============================================================================
// CkGoapGym — Patrol Route station entity
//
// Composite Action that extends the active chain. Tree:
//   Root           goal {Complete=true}
//     └── DoPatrol (composite — has 3 children below)
//           ├── WalkToB     pre {AtPostA}  eff {AtPostB}
//           ├── WalkToC     pre {AtPostB}  eff {AtPostC}
//           └── MarkComplete pre {AtPostC} eff {Complete}
//
// Initial WS: AtPostA=true, all others false.
//
// Expected runtime:
//   1. Root plans → picks DoPatrol → chain extends to [Root, DoPatrol].
//   2. DoPatrol plans → backchain produces [WalkToB, WalkToC, MarkComplete].
//   3. Player drives sub-plan progression by toggling AtPostB, AtPostC, etc.
//      Each toggle triggers a DoPatrol replan.
//
// Player commands:
//   Goap.Patrol.AdvanceB / AdvanceC / Complete — set per-waypoint WS keys.
//   Goap.Patrol.Reset                            — back to AtPostA only.
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

    private FCk_Handle_Goap_Planner _ActionSet;
    private FCk_Handle_Goap_Action _RootAction;
    private FCk_Handle_Goap_Action _DoPatrolAction;
    private FCk_Handle_Goap_WorldState _WS;
    private TArray<TSubclassOf<UCk_GoapAction_EntityScript>> _KnownClasses_Root;
    private TArray<FString> _KnownLabels_Root;
    private TArray<TSubclassOf<UCk_GoapAction_EntityScript>> _KnownClasses_Patrol;
    private TArray<FString> _KnownLabels_Patrol;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

        _WS = utils_goap_world_state::Create(InHandle,
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.Patrol"),
            FCk_Fragment_Goap_WorldState_ParamsData());
        Reset_WS();

        // U11.1: Planner goal Complete=true on PlannerParams.
        auto Goal = TArray<FCk_GoapWS_Condition_Authored>();
        Goal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.WS.Patrol.Complete"),
            true));

        auto ActionSetParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.Goap.ActionSet.Patrol"));
        ActionSetParams.Set_Goal(Goal);
        _ActionSet = utils_goap_planner::Add(InHandle, ActionSetParams);

        auto RootParams = FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_Patrol_Root);
        RootParams.Set_ReplanPolicy(ECk_Goap_ReplanPolicy::OnWorldStateDirty);
        _RootAction = utils_goap_planner::SetRootAction(_ActionSet, RootParams, _WS);

        // DoPatrol — composite child of Root.
        auto DoPatrolParams = FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_Patrol_DoPatrol);
        DoPatrolParams.Set_ReplanPolicy(ECk_Goap_ReplanPolicy::OnWorldStateDirty);
        _DoPatrolAction = utils_goap_action::AddAction_ToAction(_RootAction, DoPatrolParams);

        // Atomic children of DoPatrol.
        utils_goap_action::AddAction_ToAction(_DoPatrolAction,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_Patrol_WalkToB));
        utils_goap_action::AddAction_ToAction(_DoPatrolAction,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_Patrol_WalkToC));
        utils_goap_action::AddAction_ToAction(_DoPatrolAction,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapGym_Patrol_MarkComplete));

        _KnownClasses_Root.Add(UCk_GoapGym_Patrol_DoPatrol);
        _KnownLabels_Root.Add("DoPatrol");

        _KnownClasses_Patrol.Add(UCk_GoapGym_Patrol_WalkToB);      _KnownLabels_Patrol.Add("WalkToB");
        _KnownClasses_Patrol.Add(UCk_GoapGym_Patrol_WalkToC);      _KnownLabels_Patrol.Add("WalkToC");
        _KnownClasses_Patrol.Add(UCk_GoapGym_Patrol_MarkComplete); _KnownLabels_Patrol.Add("MarkComplete");

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnDisplayTick"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    private void Reset_WS()
    {
        if (ck::Is_NOT_Valid(_WS)) { return; }
        Set(n"Gym.Goap.WS.Patrol.AtPostA", true);
        Set(n"Gym.Goap.WS.Patrol.AtPostB", false);
        Set(n"Gym.Goap.WS.Patrol.AtPostC", false);
        Set(n"Gym.Goap.WS.Patrol.Complete", false);
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
        if (ck::Is_NOT_Valid(_RootAction)) { return; }

        auto AtA = Get(n"Gym.Goap.WS.Patrol.AtPostA");
        auto AtB = Get(n"Gym.Goap.WS.Patrol.AtPostB");
        auto AtC = Get(n"Gym.Goap.WS.Patrol.AtPostC");
        auto Done = Get(n"Gym.Goap.WS.Patrol.Complete");

        auto RootStatus = utils_goap_action::Get_PlanStatus(_RootAction);
        auto RootPlan = utils_goap_action::Get_Plan(_RootAction);

        auto Chain = utils_goap_planner::Get_ActiveChain(_ActionSet);
        auto ChainLen = Chain.Num();

        // Patrol composite's own planner may not be active until ChainUpdate
        // extends the chain to include it. Read its plan defensively.
        auto PatrolStatusLabel = "(not yet active)";
        auto PatrolPlanLabel = "(waiting for chain to extend)";
        if (ChainLen >= 2 && ck::IsValid(_DoPatrolAction))
        {
            PatrolStatusLabel = CkGoapGym_Common::Format_PlanStatus(
                utils_goap_action::Get_PlanStatus(_DoPatrolAction));
            PatrolPlanLabel = CkGoapGym_Common::Format_Plan(
                utils_goap_action::Get_Plan(_DoPatrolAction),
                _KnownClasses_Patrol, _KnownLabels_Patrol);
        }

        auto Body = "World State\n"
            + f"  AtPostA        {CkGoapGym_Common::Render_Bool(AtA)}\n"
            + f"  AtPostB        {CkGoapGym_Common::Render_Bool(AtB)}\n"
            + f"  AtPostC        {CkGoapGym_Common::Render_Bool(AtC)}\n"
            + f"  Complete       {CkGoapGym_Common::Render_Bool(Done)}\n\n"
            + "Root planner\n"
            + f"  Status         {CkGoapGym_Common::Format_PlanStatus(RootStatus)}\n"
            + f"  Plan           {CkGoapGym_Common::Format_Plan(RootPlan, _KnownClasses_Root, _KnownLabels_Root)}\n"
            + f"  Chain length   {ChainLen}\n\n"
            + "DoPatrol planner (composite child)\n"
            + f"  Status         {PatrolStatusLabel}\n"
            + f"  Plan           {PatrolPlanLabel}\n\n"
            + "Buttons\n"
            + "  Goap.Patrol.AdvanceB / AdvanceC / Complete\n"
            + "  Goap.Patrol.Reset";

        CkGym_Common::Update_StationDisplay(ck::ToEntity(this),
            "STATION 4 / PATROL ROUTE", Body,
            "Composite Action: chain extends to [Root, DoPatrol].\nSub-plan = [WalkToB, WalkToC, MarkComplete].");
    }
}
