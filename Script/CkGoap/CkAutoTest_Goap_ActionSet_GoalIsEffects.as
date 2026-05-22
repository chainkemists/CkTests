// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: ACTIONSET GOAL IS OWN EFFECTS (NOT PARENT'S)
//============================================================================
//
// Validates: when a composite child Action activates, its runtime goal is
// set from the CHILD's own declared Effects (_GoalFromEffects), NOT from
// the parent Action's effects or goal.
//
// Discrimination mechanism:
//   - Root CDO effect: AKey=true  (_GoalFromEffects = {AKey=true})
//   - Root _InitialGoal_RootOnly: {BKey=true}  (root plans to achieve BKey)
//   - Mid CDO effect: BKey=true   (_GoalFromEffects = {BKey=true})
//     * Mid satisfies Root's goal {BKey=true} → Root's plan = [Mid]
//     * Mid's own correct goal = {BKey=true} → Mid plans → picks Leaf_B
//     * WRONG goal (from Root's _GoalFromEffects) = {AKey=true} → Mid would
//       pick Leaf_A (distractor) instead. Test fails on that regression.
//
// Setup:
//   - WS: AKey=false, BKey=false
//   - Root child: Mid (composite — has Leaf_B and Leaf_A as children)
//   - Mid children: Leaf_B (effect BKey=true), Leaf_A (effect AKey=true)
//
// Expected:
//   1. Root's plan = [Mid]
//   2. After Mid activates and plans: Get_Plan(Mid)[0] == Leaf_B
//      (not Leaf_A — which would indicate wrong goal injection)
//============================================================================

class UCk_AutoTest_Goap_ActionSet_GoalIsEffects : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_Goap_Action _RootAction;
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

        auto ActionSetParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        _ActionSet = utils_goap_planner::Add(Local, ActionSetParams);
        Assert_True(ck::IsValid(_ActionSet), "AddActionSet should return a valid handle");

        // Root's planning goal = {BKey=true}. Root's CDO effect = AKey=true
        // (_GoalFromEffects = {AKey=true}). These differ intentionally:
        // if Mid's goal were injected from Root's _GoalFromEffects instead of
        // Mid's own effects, Mid would pick Leaf_A rather than Leaf_B.
        auto InitialGoal = TArray<FCk_GoapWS_Condition_Authored>();
        InitialGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.BKey"),
            true));
        auto RootParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Root_GoalIsEffects);
        RootParams.Set_InitialGoal_RootOnly(InitialGoal);

        _RootAction = utils_goap_planner::SetRootAction(_ActionSet, RootParams, WS);
        Assert_True(ck::IsValid(_RootAction), "SetRootAction should return a valid handle");

        // Add Mid as a child of Root. Mid is composite (will have Leaf_B and
        // Leaf_A as its children below).
        auto MidParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Mid_GoalIsEffects);
        auto MidAction = utils_goap_action::AddAction_ToAction(_RootAction, MidParams);
        Assert_True(ck::IsValid(MidAction), "Mid AddAction_ToAction should succeed");

        // Add Leaf_B and Leaf_A as children of Mid.
        auto LeafBParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_LeafB_GoalIsEffects);
        auto LeafBAction = utils_goap_action::AddAction_ToAction(MidAction, LeafBParams);
        Assert_True(ck::IsValid(LeafBAction), "Leaf_B AddAction_ToAction should succeed");

        auto LeafAParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_LeafA_GoalIsEffects);
        auto LeafAAction = utils_goap_action::AddAction_ToAction(MidAction, LeafAParams);
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
        // (its _Goal is empty until ChainUpdate runs DoInjectGoalSynchronous).
        // Skip those early empty-plan fires — we're validating the AFTER-activation
        // plan that's driven by Mid's _GoalFromEffects={BKey=true}.
        auto MidPlan = utils_goap_action::Get_Plan(InAction);
        if (MidPlan.Num() == 0) { return; }

        Assert_True(utils_goap_action::Get_PlanStatus(InAction) == ECk_GoapPlanStatus::PlanFound,
            "Mid PlanStatus should be PlanFound after activation");

        Assert_True(MidPlan.Num() == 1,
            f"Mid plan should have exactly 1 entry (got {MidPlan.Num()})");
        Assert_True(MidPlan.Num() > 0 && MidPlan[0] == UCk_AutoTestAction_Goap_ActionSet_LeafB_GoalIsEffects,
            "Mid Plan[0] should be Leaf_B (BKey=true), NOT Leaf_A (AKey=true) — goal must come from Mid's own effects");

        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_ActionSet_GoalIsEffects_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_ActionSet_GoalIsEffects;
    default _TimeoutSeconds = 10.0f;
}
