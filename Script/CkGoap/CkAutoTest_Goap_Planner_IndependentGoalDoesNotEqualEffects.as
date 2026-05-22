// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: PLANNER INDEPENDENT GOAL (goal != effects)
//============================================================================
//
// Validates U11.1: a Planner's goal is independent of any Action-role effects
// the same entity carries. The old "composite Action's goal = its effects"
// hardwiring is REMOVED — a composite Action's effects describe what it
// accomplishes for its PARENT's planner (the candidate-operator interface),
// while the Action's own planner-role goal is whatever was authored (here:
// set via utils_goap_planner::Request_SetGoal after construction).
//
// Discrimination mechanism (inverted from U10):
//   - Root planner goal: {BKey=true} (set via PlannerParams._Goal)
//   - Mid CDO effect:    BKey=true   (Mid satisfies Root's goal → Root plan = [Mid])
//   - Mid planner goal:  {AKey=true} (set explicitly via utils_goap_action's
//                                     Request_SetGoalWorldState — different
//                                     from Mid's effects)
//   - Mid children: Leaf_B (effect BKey=true), Leaf_A (effect AKey=true)
//
// If U11.1 is implemented correctly:
//   * Root picks Mid (Mid's effect BKey=true satisfies Root's goal).
//   * Mid plans toward {AKey=true} (its INDEPENDENT goal) → picks Leaf_A.
//
// If the goal=effects coupling were still present (U10 regression):
//   * Mid's goal would have been auto-injected as {BKey=true} from its own
//     effects → Mid would pick Leaf_B.
//
// Assertion inversion: we now check Mid's Plan[0] == Leaf_A (goal independence)
// where the U10 test checked == Leaf_B (goal coupled to effects).
//============================================================================

class UCk_AutoTest_Goap_Planner_IndependentGoalDoesNotEqualEffects : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_Goap_Action _RootAction;
    private FCk_Handle_Goap_Action _MidAction;
    private FCk_Handle_Goap_Planner _ActionSet;
    private bool _RootPlanReceived = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
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

        // Root planner goal = {BKey=true}. Mid's effect BKey=true satisfies it.
        // U11.1: goal authored on PlannerParams.
        auto RootGoal = TArray<FCk_GoapWS_Condition_Authored>();
        RootGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.BKey"),
            true));

        auto ActionSetParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        ActionSetParams.Set_Goal(RootGoal);
        _ActionSet = utils_goap_planner::Add(Local, ActionSetParams);
        Assert_True(ck::IsValid(_ActionSet), "AddActionSet should return a valid handle");

        auto RootParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Root_GoalIsEffects);

        _RootAction = utils_goap_planner::SetRootAction(_ActionSet, RootParams, WS);
        Assert_True(ck::IsValid(_RootAction), "SetRootAction should return a valid handle");

        // Add Mid as a child of Root. Mid is composite (will have Leaf_B and
        // Leaf_A as its children below).
        auto MidParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Mid_GoalIsEffects);
        _MidAction = utils_goap_action::AddAction_ToAction(_RootAction, MidParams);
        Assert_True(ck::IsValid(_MidAction), "Mid AddAction_ToAction should succeed");

        // U11.1 INVERSION — set Mid's planner goal to {AKey=true} EXPLICITLY,
        // diverging from Mid's own CDO effect ({BKey=true}). The U10 implicit
        // "Mid's goal = Mid's effects" rule is gone. With independent goals,
        // Mid plans toward AKey and picks Leaf_A. Setting the goal here on the
        // Action-level Request_SetGoalWorldState updates the same authored slot
        // that ChainUpdate re-resolves at activation — so the goal sticks.
        auto MidGoal = TArray<FCk_GoapWS_Condition_Authored>();
        MidGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.AKey"),
            true));
        utils_goap_action::Request_SetGoalWorldState(_MidAction, MidGoal);

        // Add Leaf_B and Leaf_A as children of Mid.
        auto LeafBParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_LeafB_GoalIsEffects);
        auto LeafBAction = utils_goap_action::AddAction_ToAction(_MidAction, LeafBParams);
        Assert_True(ck::IsValid(LeafBAction), "Leaf_B AddAction_ToAction should succeed");

        auto LeafAParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_LeafA_GoalIsEffects);
        auto LeafAAction = utils_goap_action::AddAction_ToAction(_MidAction, LeafAParams);
        Assert_True(ck::IsValid(LeafAAction), "Leaf_A AddAction_ToAction should succeed");

        utils_goap_action::BindTo_OnPlanComplete(_RootAction,
            FCk_Delegate_Goap_OnActionPlanComplete(this, n"OnRootPlan"));
    }

    UFUNCTION()
    private void OnRootPlan(FCk_Handle_Goap_Action InAction, FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }
        if (_RootPlanReceived) { return; }
        _RootPlanReceived = true;

        Assert_True(utils_goap_action::Get_PlanStatus(_RootAction) == ECk_GoapPlanStatus::PlanFound,
            "Root PlanStatus should be PlanFound");

        auto RootPlan = utils_goap_action::Get_Plan(_RootAction);
        Assert_True(RootPlan.Num() == 1,
            f"Root plan should have exactly 1 entry (got {RootPlan.Num()})");
        Assert_True(RootPlan.Num() > 0 && RootPlan[0] == UCk_AutoTestAction_Goap_ActionSet_Mid_GoalIsEffects,
            "Root Plan[0] should be Mid");

        // Retrieve Mid's handle and bind to its OnPlanComplete.
        // ChainUpdate runs after HandleResult in this frame; it will activate
        // Mid and add RequiresInitialPlan. Mid will plan on the next frame.
        // We bind now (before ChainUpdate fires) so we don't miss Mid's plan.
        auto MidHandle = utils_goap_planner::Find_ActionByClass(
            _ActionSet, UCk_AutoTestAction_Goap_ActionSet_Mid_GoalIsEffects);
        Assert_True(ck::IsValid(MidHandle), "Should find Mid by class in ActionSet catalog");

        if (ck::IsValid(MidHandle))
        {
            utils_goap_action::BindTo_OnPlanComplete(MidHandle,
                FCk_Delegate_Goap_OnActionPlanComplete(this, n"OnMidPlan"));
        }
    }

    UFUNCTION()
    private void OnMidPlan(FCk_Handle_Goap_Action InAction, FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }

        // Mid receives an initial empty-plan PlanComplete BEFORE chain activation
        // (its _Goal is empty until ChainUpdate runs DoInjectGoalSynchronous,
        // which re-resolves Mid's authored goal). Skip those early empty-plan
        // fires — we're validating the AFTER-activation plan driven by Mid's
        // EXPLICITLY-SET independent goal {AKey=true}.
        auto MidPlan = utils_goap_action::Get_Plan(InAction);
        if (MidPlan.Num() == 0) { return; }

        Assert_True(utils_goap_action::Get_PlanStatus(InAction) == ECk_GoapPlanStatus::PlanFound,
            "Mid PlanStatus should be PlanFound after activation");

        // U11.1 INVERSION: Mid's independent goal {AKey=true} should make it
        // pick Leaf_A. If the old goal=effects rule were still wired up, Mid
        // would have planned toward its effects {BKey=true} and picked Leaf_B.
        Assert_True(MidPlan.Num() == 1,
            f"Mid plan should have exactly 1 entry (got {MidPlan.Num()})");
        Assert_True(MidPlan.Num() > 0 && MidPlan[0] == UCk_AutoTestAction_Goap_ActionSet_LeafA_GoalIsEffects,
            "Mid Plan[0] should be Leaf_A (AKey=true) — Mid's independent planner goal, NOT its effects (which still equal BKey=true for Root's benefit)");

        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_Planner_IndependentGoalDoesNotEqualEffects_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_Planner_IndependentGoalDoesNotEqualEffects;
    default _TimeoutSeconds = 10.0f;
}
