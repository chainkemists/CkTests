// Language=angelscript

//============================================================================
// CK GOAP - AUTOMATION TEST: RESET ACTIVE CHAIN ENDING IN AN ATOMIC LEAF
//============================================================================
//
// Regression gate for the atomic-leaf guard in Request_ResetActiveChain:
// Get_ActiveChain includes an atomic leaf Action (no Planner role, no
// Activation fragment) as a chain step, but the reset loop used to call
// DoDeactivatePlanner on every node - tripping a CkEnsure on the leaf (the
// harness escalates that to a failure, which is this test's red condition
// without the guard).
//
// The minimal shape IS the shape that hit production: a top-level planner
// whose OWN Plan[0] is an atomic action - the chain is then [leaf] with no
// composite anywhere (BusterBlock's tourist Intent chain [Roam]). Sibling
// DeactivateChildren never covers this: its only chain node is a promoted
// composite, and a goal-less composite never extends the chain further.
//
// Fixture: goal {BKey=true}; LeafB (atomic, effect BKey=true) as the
// planner's only child. Plan = [LeafB] -> chain = [LeafB].
//
// Pinned contract for resetting that chain:
//   - no ensure fires (implicit - harness-enforced)
//   - the completion delegate reports Succeeded
//   - the chain still reports [LeafB] afterwards: an atomic Plan[0] is
//     included unconditionally by the walk, and a reset does not clear the
//     planner's own plan - reset means "deactivate", and an atomic leaf has
//     nothing to deactivate
//============================================================================

class UCk_AutoTest_Goap_Planner_ResetChainWithAtomicLeaf : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_Planner _Planner;
    private bool _ResetHandled = false;
    private bool _ResetSucceeded = false;

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

        // The planner's ONLY child is atomic - Plan[0] lands directly on it.
        auto LeafBParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_LeafB_GoalIsEffects);
        auto LeafBAction = utils_goap_planner::AddAction(_Planner, LeafBParams);
        Assert_True(ck::IsValid(LeafBAction), "LeafB AddAction should succeed");

        WaitUntil(n"Check_AtomicLeafInChain", n"OnChainReady");
    }

    UFUNCTION()
    private void Check_AtomicLeafInChain(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_goap_planner::Get_ActiveChain(_Planner).Num() >= 1);
    }

    UFUNCTION()
    private void OnChainReady(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Chain = utils_goap_planner::Get_ActiveChain(_Planner);
        Assert_True(Chain.Num() == 1,
            f"chain should be exactly the atomic leaf (got {Chain.Num()})");
        // Guard against fixture drift: the whole point is a chain node WITHOUT
        // the Planner role. If this fires, the fixture stopped being atomic.
        Assert_True(Chain.Num() == 1 && utils_goap_planner::Has(Chain[0]) == false,
            "chain node must be a bare atomic Action (no Planner role)");

        // Pre-guard, this tripped the Activation-fragment ensure on the atomic
        // leaf; the harness escalates ensures, so surviving this call IS the test.
        utils_goap_planner::Request_ResetActiveChain(_Planner,
            FCk_Delegate_Request_OnCompleted(this, n"OnResetCompleted"));

        Assert_True(_ResetHandled && _ResetSucceeded,
            "Request_ResetActiveChain is an immediate mutator - completion fires Succeeded synchronously");

        auto ChainAfter = utils_goap_planner::Get_ActiveChain(_Planner);
        Assert_True(ChainAfter.Num() == 1,
            f"atomic Plan[0] is included unconditionally and a reset does not clear the plan - chain still [leaf] (got {ChainAfter.Num()})");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnResetCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _ResetHandled = true;
        _ResetSucceeded = InResult == ECk_Request_OperationResult::Succeeded;
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
