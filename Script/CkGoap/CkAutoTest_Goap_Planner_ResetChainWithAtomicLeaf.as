// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: RESET ACTIVE CHAIN ENDING IN AN ATOMIC LEAF
//============================================================================
//
// Regression gate for the atomic-leaf guard in Request_ResetActiveChain:
// Get_ActiveChain deliberately includes an atomic leaf Action (no Planner
// role, no Activation fragment) as the final chain step, but the reset loop
// used to call DoDeactivatePlanner on every node — tripping a CkEnsure on the
// leaf (the harness escalates that to a test failure, which is this test's
// red condition pre-guard).
//
// Sibling DeactivateChildren resets as soon as chain.Num() >= 1, which races
// ahead of Mid's own sub-plan — its chain is composite-only at reset time, so
// it never covered this path. This test explicitly WAITS for the chain to
// extend through Mid to an atomic leaf (Num() >= 2) before resetting.
//
// Reuses the GoalIsEffects action fixtures:
//   - Planner goal {BKey=true}; Mid (effect BKey=true) promoted composite
//     with atomic children LeafB (BKey=true) and LeafA (AKey=true).
//
// Assertions after Request_ResetActiveChain on the extended chain:
//   - no ensure fired (implicit — harness-enforced)
//   - chain collapses to [] (the walk stops at the now-inactive Mid)
//   - OnPlannerDeactivated fired exactly once, for Mid — never for the leaf
//============================================================================

class UCk_AutoTest_Goap_Planner_ResetChainWithAtomicLeaf : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_Planner _Planner;
    private FCk_Handle_Goap_Planner _MidAsPlanner;
    private bool _ChainSeenExtended = false;
    private int32 _DeactivatedCount = 0;

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

        auto InitialGoal = TArray<FCk_GoapWS_Condition_Authored>();
        InitialGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.BKey"),
            true));

        auto PlannerParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        PlannerParams.Set_Goal(InitialGoal);
        PlannerParams.Set_WorldStateSource(WS);
        _Planner = utils_goap_planner::Add(Local, PlannerParams);
        Assert_True(ck::IsValid(_Planner), "Add Planner should return a valid handle");

        auto MidParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Mid_GoalIsEffects);
        auto MidAction = utils_goap_planner::AddAction(_Planner, MidParams);
        Assert_True(ck::IsValid(MidAction), "Mid AddAction should succeed");

        auto MidPlannerParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        _MidAsPlanner = utils_goap_planner::PromoteActionToPlanner(MidAction, MidPlannerParams);
        Assert_True(ck::IsValid(_MidAsPlanner), "Mid PromoteActionToPlanner should succeed");
        auto MidAsPlanner = _MidAsPlanner;

        auto LeafBParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_LeafB_GoalIsEffects);
        auto LeafBAction = utils_goap_planner::AddAction(MidAsPlanner, LeafBParams);
        Assert_True(ck::IsValid(LeafBAction), "LeafB AddAction should succeed");

        auto LeafAParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_LeafA_GoalIsEffects);
        auto LeafAAction = utils_goap_planner::AddAction(MidAsPlanner, LeafAParams);
        Assert_True(ck::IsValid(LeafAAction), "LeafA AddAction should succeed");

        // The whole point: reset only once the chain has extended THROUGH Mid
        // to one of its atomic leaves.
        WaitUntil(n"Check_ChainReachesAtomicLeaf", n"OnChainExtended");
    }

    UFUNCTION()
    private void Check_ChainReachesAtomicLeaf(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_goap_planner::Get_ActiveChain(_Planner).Num() >= 2);
    }

    UFUNCTION()
    private void OnChainExtended(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        if (_ChainSeenExtended) { return; }
        _ChainSeenExtended = true;

        auto Chain = utils_goap_planner::Get_ActiveChain(_Planner);
        Assert_True(Chain.Num() >= 2,
            f"chain should reach through Mid to an atomic leaf before reset (got {Chain.Num()})");

        utils_goap_planner::BindTo_OnPlannerDeactivated(_MidAsPlanner,
            FCk_Delegate_Goap_OnPlannerDeactivated(this, n"OnMidDeactivated"));

        // Pre-guard this tripped the Activation-fragment ensure on the atomic
        // leaf; the harness escalates ensures, so surviving this call IS the test.
        utils_goap_planner::Request_ResetActiveChain(_Planner);

        auto ChainAfter = utils_goap_planner::Get_ActiveChain(_Planner);
        Assert_True(ChainAfter.Num() == 0,
            f"chain should collapse to [] after reset (walk stops at inactive Mid; got {ChainAfter.Num()})");

        // Prevent ChainUpdate re-extension next frame — we test the reset, not re-extension.
        utils_goap_planner::Request_SetEnableToggle(_Planner, ECk_EnableDisable::Disable);

        WaitOneFrame(n"OnCheckDeactivation");
    }

    UFUNCTION()
    private void OnMidDeactivated(
        FCk_Handle_Goap_Planner InPlanner,
        FCk_Goap_Payload_OnPlannerDeactivated InPayload)
    {
        _DeactivatedCount = _DeactivatedCount + 1;
    }

    UFUNCTION()
    private void OnCheckDeactivation(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(_DeactivatedCount == 1,
            f"OnPlannerDeactivated should fire exactly once, for Mid only — atomic leaves are skipped, not deactivated (fired {_DeactivatedCount} times)");

        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_Planner_ResetChainWithAtomicLeaf_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_Planner_ResetChainWithAtomicLeaf;
    default _TimeoutSeconds = 15.0f;
}
