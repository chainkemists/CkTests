// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: ACTIONSET SWAP ROOT ACTION
//============================================================================
//
// Validates utils_goap_planner::Request_SetRootAction(ActionSet,
// NewRootParams, InitialWorldState).
//
// Per spec §3.4 + §4.2: swapping the root truncates the active chain,
// designates the new root, stores the new WS source on the ActionSet, and
// resolves the new root's WS. After the swap, planning runs against the new
// WS and the new root becomes the chain's [0].
//
// Setup:
//   - WS_1: Ready=true (so Root_A's plan trivially succeeds).
//   - Root_A = Simple action class (effect Ready=true → goal already met).
//   - Wait for Root_A's OnPlanComplete to confirm initial plan landed.
//
// Phase 2:
//   - WS_2: Ready=true (so Root_B's plan trivially succeeds too).
//   - Call Request_SetRootAction(ActionSet, Root_B_Params, WS_2) using the
//     AtomicLeaf root action class.
//   - Assert Get_RootAction returns the new root (not Root_A).
//   - Assert chain == [Root_B] (length 1, contains the new root).
//   - Bind OnPlanComplete on Root_B (via Find_ActionByClass).
//   - Wait for Root_B's plan to settle.
//   - Assert Root_B PlanStatus == PlanFound.
//============================================================================

class UCk_AutoTest_Goap_ActionSet_SwapRootAction : UCk_AutoTest_Base
{
    private FCk_Handle _OwnerEntity;
    private FCk_Handle_Goap_Planner _ActionSet;
    private FCk_Handle_Goap_Action _RootA;
    private FCk_Handle_Goap_Action _RootB;
    private FCk_Handle_Goap_WorldState _WS_1;
    private FCk_Handle_Goap_WorldState _WS_2;

    private bool _RootAPlanReceived = false;
    private bool _SwapPerformed = false;
    private bool _RootBPlanReceived = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Local = InHandle;
        _OwnerEntity = InHandle;
        utils_transform::Add(Local, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        // WS_1: Ready=true so Root_A (effect Ready=true) trivially satisfies goal.
        _WS_1 = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS"),
            FCk_Fragment_Goap_WorldState_ParamsData());
        utils_goap_world_state::Set_Value(_WS_1,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.Ready"),
            true);

        auto ActionSetParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        _ActionSet = utils_goap_planner::Add(Local, ActionSetParams);
        Assert_True(ck::IsValid(_ActionSet), "AddActionSet should return a valid handle");

        // Root_A = Simple. Effect Ready=true IS the goal in the unified model.
        auto RootAParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Simple);

        _RootA = utils_goap_planner::SetRootAction(_ActionSet, RootAParams, _WS_1);
        Assert_True(ck::IsValid(_RootA), "SetRootAction (Root_A) should return a valid handle");

        // Sanity: root before swap.
        auto CurrentRoot = utils_goap_planner::Get_RootAction(_ActionSet);
        Assert_True(CurrentRoot == _RootA,
            "Get_RootAction should equal Root_A handle before swap");

        utils_goap_action::BindTo_OnPlanComplete(_RootA,
            FCk_Delegate_Goap_OnActionPlanComplete(this, n"OnRootAPlan"));
    }

    UFUNCTION()
    private void OnRootAPlan(
        FCk_Handle_Goap_Action InAction,
        FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }
        if (_RootAPlanReceived) { return; }
        _RootAPlanReceived = true;

        Assert_True(utils_goap_action::Get_PlanStatus(_RootA) == ECk_GoapPlanStatus::PlanFound,
            "Root_A PlanStatus should be PlanFound");

        // Perform the swap. WS_2 mirrors WS_1 (Ready=true) so the new root
        // plans successfully too — discriminator is that the chain root
        // changes to the new class.
        _WS_2 = utils_goap_world_state::Create(_OwnerEntity,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS2"),
            FCk_Fragment_Goap_WorldState_ParamsData());
        utils_goap_world_state::Set_Value(_WS_2,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.Ready"),
            true);

        auto RootBParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Root_AtomicLeaf);

        utils_goap_planner::Request_SetRootAction(_ActionSet, RootBParams, _WS_2);
        _SwapPerformed = true;

        // After swap: chain should collapse to [Root_B] (length 1).
        auto Chain = utils_goap_planner::Get_ActiveChain(_ActionSet);
        Assert_True(Chain.Num() == 1,
            f"After Request_SetRootAction, chain should contain only the new root (got {Chain.Num()})");

        // Get_RootAction should return Root_B's handle.
        _RootB = utils_goap_planner::Get_RootAction(_ActionSet);
        Assert_True(ck::IsValid(_RootB),
            "Get_RootAction should return a valid handle after Request_SetRootAction");

        // The new root should NOT be the old root (different class → different entity).
        Assert_True(_RootB != _RootA,
            "Get_RootAction should return a different handle after swapping to a new root class");

        // Catalog lookup by class should resolve to the same handle.
        auto FoundByClass = utils_goap_planner::Find_ActionByClass(
            _ActionSet, UCk_AutoTestAction_Goap_ActionSet_Root_AtomicLeaf);
        Assert_True(ck::IsValid(FoundByClass),
            "Find_ActionByClass should locate the new Root_B in the catalog");
        Assert_True(FoundByClass == _RootB,
            "Find_ActionByClass(Root_B) should equal Get_RootAction after swap");

        // Chain[0] should be Root_B.
        if (Chain.Num() >= 1)
        {
            Assert_True(Chain[0] == _RootB,
                "Chain[0] should be the new root (Root_B) after Request_SetRootAction");
        }

        // Bind on the new root and wait for its plan.
        utils_goap_action::BindTo_OnPlanComplete(_RootB,
            FCk_Delegate_Goap_OnActionPlanComplete(this, n"OnRootBPlan"));
    }

    UFUNCTION()
    private void OnRootBPlan(
        FCk_Handle_Goap_Action InAction,
        FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }
        if (!_SwapPerformed) { return; }
        if (_RootBPlanReceived) { return; }
        _RootBPlanReceived = true;

        Assert_True(utils_goap_action::Get_PlanStatus(_RootB) == ECk_GoapPlanStatus::PlanFound,
            "Root_B PlanStatus should be PlanFound after swap");

        // Root should still be Root_B (chain unchanged since plan is empty —
        // Root_B is atomic from the planner's POV: no children registered).
        auto CurrentRoot = utils_goap_planner::Get_RootAction(_ActionSet);
        Assert_True(CurrentRoot == _RootB,
            "Get_RootAction should still equal Root_B after Root_B plans");

        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_ActionSet_SwapRootAction_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_ActionSet_SwapRootAction;
    default _TimeoutSeconds = 15.0f;
}
