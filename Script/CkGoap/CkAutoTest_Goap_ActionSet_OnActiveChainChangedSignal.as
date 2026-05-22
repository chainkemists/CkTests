// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: ACTIONSET OnActiveChainChanged SIGNAL
//============================================================================
//
// Validates utils_goap_planner::BindTo_OnActiveChainChanged and the
// FCk_Goap_Payload_OnActiveChainChanged payload.
//
// Per CkGoap_ActionSet_Processor.cpp (ChainUpdate): the signal fires
// whenever the active chain mutates (extension OR truncation) — with the
// pre-mutation chain snapshot in the payload's _OldChain. The new chain
// is readable via Get_ActiveChain inside the handler.
//
// Setup mirrors ChainGrowth: Root with composite Mid (which has LeafB).
// Initial chain is [Root]; ChainUpdate extends it to [Root, Mid].
//
// Phase 1:
//   - Bind OnActiveChainChanged in DoBeginPlay (before ChainUpdate runs)
//     with FireIfPayloadInFlightThisFrame so a same-frame fire is caught.
//   - When the signal fires, verify:
//       _OldChain.Num() == 1  (chain was [Root] before extension)
//       _OldChain[0] == Root handle
//       Get_ActiveChain.Num() == 2  (chain is now [Root, Mid])
//       Get_ActiveChain[1] == Mid handle
//   - FinishSuccess.
//============================================================================

class UCk_AutoTest_Goap_ActionSet_OnActiveChainChangedSignal : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_Planner _ActionSet;
    private FCk_Handle_Goap_Action _RootAction;
    private FCk_Handle_Goap_Action _MidAction;
    private int32 _SignalFiredCount = 0;
    private bool _PayloadVerified = false;

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

        // U11.1: Planner goal={BKey=true}. Mid satisfies it.
        auto InitialGoal = TArray<FCk_GoapWS_Condition_Authored>();
        InitialGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.BKey"),
            true));

        auto ActionSetParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        ActionSetParams.Set_Goal(InitialGoal);
        _ActionSet = utils_goap_planner::Add(Local, ActionSetParams);
        Assert_True(ck::IsValid(_ActionSet), "AddActionSet should return a valid handle");

        auto RootParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Root_GoalIsEffects);

        _RootAction = utils_goap_planner::SetRootAction(_ActionSet, RootParams, WS);
        Assert_True(ck::IsValid(_RootAction), "SetRootAction should return a valid handle");

        // Mid (composite, effect BKey=true).
        auto MidParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Mid_GoalIsEffects);
        _MidAction = utils_goap_action::AddAction_ToAction(_RootAction, MidParams);
        Assert_True(ck::IsValid(_MidAction), "Mid AddAction_ToAction should succeed");

        // LeafB makes Mid composite so ChainUpdate extends to [Root, Mid].
        auto LeafBParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_LeafB_GoalIsEffects);
        auto LeafBAction = utils_goap_action::AddAction_ToAction(_MidAction, LeafBParams);
        Assert_True(ck::IsValid(LeafBAction), "LeafB AddAction_ToAction should succeed");

        // Bind the signal NOW — before any ChainUpdate runs. Default policy
        // (FireIfPayloadInFlightThisFrame) catches even a same-frame fire.
        utils_goap_planner::BindTo_OnActiveChainChanged(_ActionSet,
            FCk_Delegate_Goap_OnActiveChainChanged(this, n"OnChainChanged"));

        // Sanity: initial chain has only Root.
        auto Chain = utils_goap_planner::Get_ActiveChain(_ActionSet);
        Assert_True(Chain.Num() == 1,
            f"ActiveChain should start with only Root (got {Chain.Num()})");
    }

    UFUNCTION()
    private void OnChainChanged(
        FCk_Handle_Goap_Planner InActionSet,
        FCk_Goap_Payload_OnActiveChainChanged InPayload)
    {
        if (IsFinished()) { return; }

        _SignalFiredCount = _SignalFiredCount + 1;

        // First firing: the chain extension from [Root] to [Root, Mid].
        if (_PayloadVerified) { return; }
        _PayloadVerified = true;

        // Payload contains the OLD chain (pre-mutation snapshot).
        auto OldChain = InPayload.Get_OldChain();
        Assert_True(OldChain.Num() == 1,
            f"_OldChain should be the pre-mutation snapshot [Root] (length 1, got {OldChain.Num()})");

        if (OldChain.Num() >= 1)
        {
            Assert_True(OldChain[0] == _RootAction,
                "_OldChain[0] should be Root (pre-mutation chain was [Root])");
        }

        // Current chain (post-mutation) is queryable via Get_ActiveChain.
        auto NewChain = utils_goap_planner::Get_ActiveChain(_ActionSet);
        Assert_True(NewChain.Num() == 2,
            f"Get_ActiveChain inside OnChainChanged handler should reflect new chain [Root, Mid] (got {NewChain.Num()})");

        if (NewChain.Num() >= 2)
        {
            Assert_True(NewChain[0] == _RootAction,
                "NewChain[0] should be Root");
            Assert_True(NewChain[1] == _MidAction,
                "NewChain[1] should be Mid (the appended composite)");
        }

        Assert_True(_SignalFiredCount >= 1,
            f"OnActiveChainChanged should have fired at least once (fired {_SignalFiredCount})");

        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_ActionSet_OnActiveChainChangedSignal_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_ActionSet_OnActiveChainChangedSignal;
    default _TimeoutSeconds = 15.0f;
}
