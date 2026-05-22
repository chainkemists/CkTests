// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: ACTIONSET ENABLE TOGGLE
//============================================================================
//
// Validates §9 row 11: "Disabled ActionSet skips ChainUpdate; re-enable
// resumes."
//
// The disable toggle gates FProcessor_Goap_ActionSet_ChainUpdate only —
// individual Action planners still run. So Root will plan and select Mid,
// but while disabled ChainUpdate never appends Mid to the active chain.
// After re-enable, ChainUpdate runs and extends the chain to [Root, Mid].
//
// Setup:
//   - WS: AKey=false, BKey=false.
//   - Root action: effect AKey=true, _InitialGoal_RootOnly={BKey=true}.
//   - Mid (child of Root): effect BKey=true. Composite (has LeafB as child).
//   - LeafB (child of Mid): effect BKey=true (makes Mid composite).
//   - ActionSet disabled immediately after creation.
//
// Phase 1: Wait several frames. Chain should remain [Root] (length 1).
//   ChainUpdate is suppressed; Mid is never appended even though Root's
//   plan = [Mid].
//
// Phase 2: Re-enable ActionSet. Wait for ChainUpdate to extend the chain.
//   Assert chain length == 2 and chain[1] == Mid_GoalIsEffects class.
//============================================================================

class UCk_AutoTest_Goap_ActionSet_Toggle : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_Action _RootAction;
    private FCk_Handle_Goap_Planner _ActionSet;
    private int32 _DisabledFrameCount = 0;

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

        // U11.1: Planner goal = {BKey=true}. Root's CDO effect = AKey=true
        // (distinct from goal so any confusion between the two is detectable).
        auto InitialGoal = TArray<FCk_GoapWS_Condition_Authored>();
        InitialGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.BKey"),
            true));

        auto ActionSetParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        ActionSetParams.Set_Goal(InitialGoal);
        _ActionSet = utils_goap_planner::Add(Local, ActionSetParams);
        Assert_True(ck::IsValid(_ActionSet), "AddActionSet should return a valid handle");

        // Disable ChainUpdate immediately — before any actions are planned.
        utils_goap_planner::Request_SetEnableToggle(_ActionSet, ECk_EnableDisable::Disable);
        Assert_True(
            utils_goap_planner::Get_EnableToggle(_ActionSet) == ECk_EnableDisable::Disable,
            "ActionSet should be disabled after Request_SetEnableToggle(Disable)");

        auto RootParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Root_Toggle);

        _RootAction = utils_goap_planner::SetRootAction(_ActionSet, RootParams, WS);
        Assert_True(ck::IsValid(_RootAction), "SetRootAction should return a valid handle");

        // Add Mid as composite child of Root. Mid's effect = BKey=true →
        // Root's planner picks Mid to satisfy {BKey=true}.
        auto MidParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Mid_GoalIsEffects);
        auto MidAction = utils_goap_action::AddAction_ToAction(_RootAction, MidParams);
        Assert_True(ck::IsValid(MidAction), "Mid AddAction_ToAction should succeed");

        // Add LeafB as child of Mid — makes Mid composite so ChainUpdate
        // would extend the chain to [Root, Mid] once enabled.
        auto LeafBParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_LeafB_GoalIsEffects);
        auto LeafBAction = utils_goap_action::AddAction_ToAction(MidAction, LeafBParams);
        Assert_True(ck::IsValid(LeafBAction), "LeafB AddAction_ToAction should succeed");

        // Initial chain has only Root.
        auto Chain = utils_goap_planner::Get_ActiveChain(_ActionSet);
        Assert_True(Chain.Num() == 1,
            f"ActiveChain should have only Root at start (got {Chain.Num()})");

        // Poll for 10 frames while disabled. Chain must not extend.
        WaitOneFrame(n"OnPollDisabledFrame");
    }

    // Poll while disabled — chain must stay at length 1.
    UFUNCTION()
    private void OnPollDisabledFrame(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Chain = utils_goap_planner::Get_ActiveChain(_ActionSet);
        Assert_True(Chain.Num() == 1,
            f"ActiveChain must NOT extend while ActionSet is disabled (frame {_DisabledFrameCount}, got {Chain.Num()})");

        _DisabledFrameCount = _DisabledFrameCount + 1;
        if (_DisabledFrameCount < 10)
        {
            WaitOneFrame(n"OnPollDisabledFrame");
            return;
        }

        // After 10 frames disabled, re-enable and wait for chain extension.
        utils_goap_planner::Request_SetEnableToggle(_ActionSet, ECk_EnableDisable::Enable);
        Assert_True(
            utils_goap_planner::Get_EnableToggle(_ActionSet) == ECk_EnableDisable::Enable,
            "ActionSet should be enabled after Request_SetEnableToggle(Enable)");

        // Wait for ChainUpdate to run and extend the chain.
        WaitOneFrame(n"OnCheckChainExtended");
    }

    // After re-enable: chain should extend to [Root, Mid].
    UFUNCTION()
    private void OnCheckChainExtended(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Chain = utils_goap_planner::Get_ActiveChain(_ActionSet);

        // If Root hasn't planned yet (PlanStatus != PlanFound), wait one more frame.
        auto RootStatus = utils_goap_action::Get_PlanStatus(_RootAction);
        if (RootStatus != ECk_GoapPlanStatus::PlanFound)
        {
            WaitOneFrame(n"OnCheckChainExtended");
            return;
        }

        // Root has planned. ChainUpdate may need one more frame to extend.
        if (Chain.Num() < 2)
        {
            WaitOneFrame(n"OnCheckChainExtended");
            return;
        }

        Assert_True(Chain.Num() == 2,
            f"ActiveChain should be [Root, Mid] after re-enable (got {Chain.Num()})");

        auto MidHandle = utils_goap_planner::Find_ActionByClass(
            _ActionSet, UCk_AutoTestAction_Goap_ActionSet_Mid_GoalIsEffects);
        Assert_True(ck::IsValid(MidHandle), "Should find Mid by class in ActionSet catalog");

        if (Chain.Num() >= 2)
        {
            Assert_True(Chain[1] == MidHandle,
                "Chain[1] should be Mid after ChainUpdate extends the chain on re-enable");
        }

        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_ActionSet_Toggle_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_ActionSet_Toggle;
    default _TimeoutSeconds = 15.0f;
}
