// Language=angelscript

//============================================================================
// CK GOAP - AUTOMATION TEST: U11.3 PROMOTE ACTION TO PLANNER
//============================================================================
//
// Validates U11.3 - the PromoteActionToPlanner API:
//
//   utils_goap_planner::PromoteActionToPlanner(InAction, InParams)
//     - Augments an existing Action entity with the Planner-role identity
//       (FFragment_Goap_Planner_Params + _Current + _ActionCatalogIndex).
//     - Stamps the InParams' authored goal onto the entity's
//       FFragment_Goap_Planner_Goal._GoalAuthored. The goal is independent
//       of any Action-role effects on the same entity.
//     - Returns the Planner-cast handle.
//
// Both casts succeed on the promoted entity:
//     utils_goap_action::Has(handle)  == true   (Action role preserved)
//     utils_goap_planner::Has(handle) == true   (Planner role stamped)
//
// Discrimination mechanism (similar to GoalIsEffects but goal is set via
// PromoteActionToPlanner params instead of a separate Request_SetGoal call):
//
//   - Root planner goal: {BKey=true} (set via top-level PlannerParams._Goal)
//   - Mid CDO effect:    BKey=true   (Mid satisfies Root's goal -> Root plan = [Mid])
//   - Mid PROMOTED with planner goal {AKey=true}
//     (independent of Mid's effects; set via PromoteActionToPlanner)
//   - Mid children: Leaf_A (effect AKey=true), Leaf_B (effect BKey=true)
//
// Expected:
//   * Root picks Mid (Mid's effect BKey=true satisfies Root's goal).
//   * Mid's promoted planner plans toward {AKey=true} -> picks Leaf_A.
//
// If PromoteActionToPlanner failed to update _GoalAuthored on Mid:
//   * Mid would plan with the previously-empty _GoalAuthored -> empty plan,
//     never picks Leaf_A -> assertion fails.
//============================================================================

class UCk_AutoTest_Goap_Planner_PromoteActionToPlanner : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_Action _RootAction;
    private FCk_Handle_Goap_Action _MidAction;
    private FCk_Handle_Goap_Planner _MidAsPlanner;
    private FCk_Handle_Goap_Planner _RootPlanner;
    private bool _RootPlanReceived = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Local = InHandle;
        utils_transform::Add(Local, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto WS = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS"),
            FCk_Fragment_Goap_WorldState_ParamsData());
        utils_goap_world_state::Set_Value(WS,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.AKey"),
            false);
        utils_goap_world_state::Set_Value(WS,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.BKey"),
            false);

        // Top-level Planner with authored goal {BKey=true}.
        auto RootGoal = TArray<FCk_GoapWS_Condition_Authored>();
        RootGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.BKey"),
            true));

        auto PlannerParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        PlannerParams.Set_Goal(RootGoal);
        PlannerParams.Set_WorldStateSource(WS);
        _RootPlanner = utils_goap_planner::Add(Local, PlannerParams);
        Assert_True(ck::IsValid(_RootPlanner), "Add Planner should return a valid handle");

        auto RootParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Root_GoalIsEffects);
        _RootAction = utils_goap_planner::AddAction(_RootPlanner, RootParams);
        Assert_True(ck::IsValid(_RootAction), "AddAction (implicit-root) should return a valid handle");

        // Mid is a composite child of Root.
        auto MidParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Mid_GoalIsEffects);
        _MidAction = utils_goap_planner::AddAction(_RootPlanner, MidParams);
        Assert_True(ck::IsValid(_MidAction), "Mid AddAction should succeed");

        // ---------------------------------------------------------------
        // U11.3 CORE - Promote Mid to a Planner with goal {AKey=true}.
        // Independent of Mid's CDO effect (BKey=true).
        // ---------------------------------------------------------------
        auto MidGoal = TArray<FCk_GoapWS_Condition_Authored>();
        MidGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.AKey"),
            true));

        auto PromoteParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        PromoteParams.Set_Goal(MidGoal);

        _MidAsPlanner = utils_goap_planner::PromoteActionToPlanner(_MidAction, PromoteParams);
        Assert_True(ck::IsValid(_MidAsPlanner),
            "PromoteActionToPlanner should return a valid Planner-cast handle");

        // Mid's children - Leaf_A (effect AKey=true) and Leaf_B (effect BKey=true).
        // Under PR-A, every child must be registered under the planner host that
        // owns it. Mid is now a promoted Planner, so AddAction(MidAsPlanner, ...)
        // wires Leaf_A/Leaf_B as direct tree children of Mid.
        auto LeafAParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_LeafA_GoalIsEffects);
        auto LeafAAction = utils_goap_planner::AddAction(_MidAsPlanner, LeafAParams);
        Assert_True(ck::IsValid(LeafAAction), "Leaf_A AddAction should succeed");

        auto LeafBParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_LeafB_GoalIsEffects);
        auto LeafBAction = utils_goap_planner::AddAction(_MidAsPlanner, LeafBParams);
        Assert_True(ck::IsValid(LeafBAction), "Leaf_B AddAction should succeed");

        // ---------------------------------------------------------------
        // U11.3 - Both casts must succeed on the promoted entity.
        // ---------------------------------------------------------------
        auto MidAsGenericFromAction = FCk_Handle(_MidAction);
        auto MidAsGenericFromPlanner = FCk_Handle(_MidAsPlanner);

        Assert_True(utils_goap_action::Has(MidAsGenericFromAction),
            "Promoted entity should still satisfy Goap Action Has() - Action role preserved");
        Assert_True(utils_goap_planner::Has(MidAsGenericFromPlanner),
            "Promoted entity should satisfy Goap Planner Has() - Planner role stamped");

        // Bind to Root's OnPlanComplete to drive the test forward.
        utils_goap_planner::BindTo_OnPlanComplete(_RootPlanner,
            FCk_Delegate_Goap_OnPlanComplete(this, n"OnRootPlan"));
    }

    UFUNCTION()
    private void OnRootPlan(FCk_Handle_Goap_Planner InPlanner, FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }
        if (_RootPlanReceived) { return; }
        _RootPlanReceived = true;

        Assert_True(utils_goap_planner::Get_PlanStatus(_RootPlanner) == ECk_GoapPlanStatus::PlanFound,
            "Root PlanStatus should be PlanFound");

        auto RootPlan = utils_goap_planner::Get_PlanClasses(_RootPlanner);
        Assert_True(RootPlan.Num() == 1,
            f"Root plan should have exactly 1 entry (got {RootPlan.Num()})");
        Assert_True(RootPlan.Num() > 0 && RootPlan[0] == UCk_AutoTestAction_Goap_ActionSet_Mid_GoalIsEffects,
            "Root Plan[0] should be Mid");

        // Bind to Mid's OnPlanComplete now (before ChainUpdate activates Mid)
        // so we capture the post-activation plan.
        utils_goap_planner::BindTo_OnPlanComplete(_MidAsPlanner,
            FCk_Delegate_Goap_OnPlanComplete(this, n"OnMidPlan"));
    }

    UFUNCTION()
    private void OnMidPlan(FCk_Handle_Goap_Planner InPlanner, FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }

        // Mid may receive empty-plan PlanComplete fires before activation re-
        // resolves its goal. Skip those - we want the post-activation plan
        // driven by Mid's promoted planner goal {AKey=true}.
        auto MidPlan = utils_goap_action::Get_Plan(_MidAction);
        if (MidPlan.Num() == 0) { return; }

        Assert_True(utils_goap_action::Get_PlanStatus(_MidAction) == ECk_GoapPlanStatus::PlanFound,
            "Mid PlanStatus should be PlanFound after activation");

        // U11.3 verification: Mid's promoted planner goal is {AKey=true},
        // so it picks Leaf_A (effect AKey=true), NOT Leaf_B (effect BKey=true).
        Assert_True(MidPlan.Num() == 1,
            f"Mid plan should have exactly 1 entry (got {MidPlan.Num()})");
        Assert_True(MidPlan.Num() > 0 && MidPlan[0] == UCk_AutoTestAction_Goap_ActionSet_LeafA_GoalIsEffects,
            "Mid Plan[0] should be Leaf_A (AKey=true) - goal set by PromoteActionToPlanner");

        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_Planner_PromoteActionToPlanner_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_Planner_PromoteActionToPlanner;
    default _TimeoutSeconds = 15.0f;
}
