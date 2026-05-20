// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: ACTIONSET DEFER ONE FRAME
//============================================================================
//
// Validates §9 row 13: "Newly-appended Action does NOT plan in activation
// frame; plans in frame+1."
//
// ChainUpdate appends Mid to the chain and adds FTag_Goap_Action_RequiresInitialPlan.
// AutoReplan picks this up on the NEXT frame to enqueue a plan request.
// Therefore Mid's PlanStatus must still be Idle in the same frame that
// ChainUpdate fires.
//
// Setup (reuses GoalIsEffects hierarchy):
//   - WS: AKey=false, BKey=false.
//   - Root: _InitialGoal_RootOnly={BKey=true}. CDO effect=AKey=true.
//   - Mid (child of Root): CDO effect=BKey=true. Composite (has Leaf_B).
//   - Leaf_B (child of Mid): CDO effect=BKey=true. Atomic.
//
// Note: Mid is created with _PlanOnStart=false so it does NOT start planning
//   before ChainUpdate activates it. This isolates the "deferred planning on
//   activation" property. AddAction_ToAction resolves Mid's WS immediately from
//   Root's resolved WS, so Setup runs early — but without _PlanOnStart=true and
//   without ChainUpdate yet having added RequiresInitialPlan, Mid stays Idle.
//
// Phase 1: Root plans and finds Mid (satisfies BKey=true). OnPlanComplete
//   fires for Root.
//
// Phase 2: In OnRootPlan, retrieve Mid via Find_ActionByClass. ChainUpdate has
//   NOT yet run for this frame (HandleResult fires OnPlanComplete before
//   ChainUpdate processes). Mid's PlanStatus must be Idle — ChainUpdate hasn't
//   added RequiresInitialPlan yet and _PlanOnStart=false prevents early planning.
//
// Phase 3: Wait one frame (ChainUpdate runs, appends Mid to chain, adds
//   RequiresInitialPlan). Then poll until Mid has PlanFound — AutoReplan picks
//   up RequiresInitialPlan on the NEXT frame after ChainUpdate.
//
// The key invariant: Mid is Idle in the same frame as Root's HandleResult
// (activation frame). Mid plans in frame+1 or later, not the same frame.
//============================================================================

class UCk_AutoTest_Goap_ActionSet_DeferOneFrame : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 15.0f;

    private FCk_Handle_Goap_Action _RootAction;
    private FCk_Handle_Goap_ActionSet _ActionSet;
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

        auto Goap = utils_goap::Add(Local, FCk_Fragment_Goap_RootParamsData());

        auto ActionSetParams = FCk_Fragment_Goap_ActionSetParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        _ActionSet = utils_goap_action_set::AddActionSet(Goap, ActionSetParams);
        Assert_True(ck::IsValid(_ActionSet), "AddActionSet should return a valid handle");

        // Root goal: {BKey=true}. Root CDO effect: AKey=true (distinct intentionally).
        // Mid's CDO effect: BKey=true → Root's planner picks Mid.
        auto InitialGoal = TArray<FCk_GoapWS_Condition_Authored>();
        InitialGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.BKey"),
            true));
        auto RootParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Root_GoalIsEffects);
        RootParams.Set_InitialGoal_RootOnly(InitialGoal);

        _RootAction = utils_goap_action_set::SetRootAction(_ActionSet, RootParams, WS);
        Assert_True(ck::IsValid(_RootAction), "SetRootAction should return a valid handle");

        // Add Mid as a composite child of Root.
        // Set _PlanOnStart=false so Mid does NOT start planning before ChainUpdate
        // activates it. This isolates the "deferred planning on activation" property:
        // Mid stays Idle until ChainUpdate appends it to the chain and adds
        // RequiresInitialPlan; only then does AutoReplan enqueue Mid's first plan
        // (on the subsequent frame).
        auto MidParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Mid_GoalIsEffects);
        MidParams.Set_PlanOnStart(false);
        auto MidAction = utils_goap_action::AddAction_ToAction(_RootAction, MidParams);
        Assert_True(ck::IsValid(MidAction), "Mid AddAction_ToAction should succeed");

        // Add Leaf_B as child of Mid (makes Mid composite).
        auto LeafBParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_LeafB_GoalIsEffects);
        auto LeafBAction = utils_goap_action::AddAction_ToAction(MidAction, LeafBParams);
        Assert_True(ck::IsValid(LeafBAction), "Leaf_B AddAction_ToAction should succeed");

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

        // At this moment (inside HandleResult's signal callback), ChainUpdate
        // has NOT yet run for this frame. Mid has _PlanOnStart=false and no
        // RequiresInitialPlan, so its PlanStatus must be Idle.
        auto MidHandle = utils_goap_action_set::Find_ActionByClass(
            _ActionSet, UCk_AutoTestAction_Goap_ActionSet_Mid_GoalIsEffects);
        Assert_True(ck::IsValid(MidHandle), "Should find Mid by class in ActionSet catalog");

        if (ck::IsValid(MidHandle))
        {
            auto MidStatusBeforeChainUpdate = utils_goap_action::Get_PlanStatus(MidHandle);
            Assert_True(MidStatusBeforeChainUpdate == ECk_GoapPlanStatus::Idle,
                "Mid PlanStatus must be Idle before ChainUpdate runs (_PlanOnStart=false, no RequiresInitialPlan yet)");
        }

        // Wait one frame so ChainUpdate appends Mid and sets RequiresInitialPlan.
        WaitOneFrame(n"OnCheckAfterChainUpdate");
    }

    UFUNCTION()
    private void OnCheckAfterChainUpdate(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto MidHandle = utils_goap_action_set::Find_ActionByClass(
            _ActionSet, UCk_AutoTestAction_Goap_ActionSet_Mid_GoalIsEffects);
        Assert_True(ck::IsValid(MidHandle), "Should still find Mid by class after one frame");

        if (ck::IsValid(MidHandle) == false)
        {
            FinishSuccess();
            return;
        }

        // ChainUpdate should have appended Mid to the chain by now.
        auto Chain = utils_goap_action_set::Get_ActiveChain(_ActionSet);
        if (Chain.Num() < 2)
        {
            // ChainUpdate may need another frame — poll.
            WaitOneFrame(n"OnCheckAfterChainUpdate");
            return;
        }

        Assert_True(Chain.Num() == 2,
            f"ActiveChain should be [Root, Mid] after one frame (got {Chain.Num()})");
        Assert_True(Chain.Num() >= 2 && Chain[1] == MidHandle,
            "Chain[1] should be Mid after ChainUpdate appended it");

        // Mid has been appended. Now poll until Mid has PlanFound to verify
        // that the deferred plan fires on frame+1 (not the same frame as appending).
        WaitOneFrame(n"OnWaitForMidPlan");
    }

    UFUNCTION()
    private void OnWaitForMidPlan(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto MidHandle = utils_goap_action_set::Find_ActionByClass(
            _ActionSet, UCk_AutoTestAction_Goap_ActionSet_Mid_GoalIsEffects);
        if (ck::IsValid(MidHandle) == false)
        {
            Assert_True(false, "Mid handle lost while waiting for its plan");
            return;
        }

        auto MidStatus = utils_goap_action::Get_PlanStatus(MidHandle);
        if (MidStatus == ECk_GoapPlanStatus::Planning || MidStatus == ECk_GoapPlanStatus::Idle)
        {
            // Still in progress — give it another frame.
            WaitOneFrame(n"OnWaitForMidPlan");
            return;
        }

        Assert_True(MidStatus == ECk_GoapPlanStatus::PlanFound,
            "Mid PlanStatus should eventually be PlanFound after deferred plan");

        auto MidPlan = utils_goap_action::Get_Plan(MidHandle);
        Assert_True(MidPlan.Num() == 1,
            f"Mid plan should have exactly 1 entry after deferred planning (got {MidPlan.Num()})");
        Assert_True(MidPlan.Num() > 0 && MidPlan[0] == UCk_AutoTestAction_Goap_ActionSet_LeafB_GoalIsEffects,
            "Mid Plan[0] should be Leaf_B");

        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_ActionSet_DeferOneFrame_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_ActionSet_DeferOneFrame;
    default _TimeoutSeconds = 15.0f;
}
