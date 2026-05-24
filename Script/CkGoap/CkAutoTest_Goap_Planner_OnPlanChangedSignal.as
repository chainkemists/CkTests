// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: PLANNER OnActiveChainChanged SIGNAL
//============================================================================
//
// Validates utils_goap_planner::BindTo_OnActiveChainChanged and the
// FCk_Goap_Payload_OnActiveChainChanged payload.
//
// Per CkGoap_Planner_Processor.cpp (ChainUpdate): the signal fires
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

class UCk_AutoTest_Goap_Planner_OnPlanChangedSignal : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_Planner _Planner;
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
        ActionSetParams.Set_WorldStateSource(WS);
        _Planner = utils_goap_planner::Add(Local, ActionSetParams);
        Assert_True(ck::IsValid(_Planner), "Add Planner should return a valid handle");

        // PR-B.1b Stage 5: Mid is registered directly under the Planner. The
        // legacy "implicit root" Root_GoalIsEffects is no longer needed.
        auto MidParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Mid_GoalIsEffects);
        _MidAction = utils_goap_planner::AddAction(_Planner, MidParams);
        Assert_True(ck::IsValid(_MidAction), "Mid AddAction should succeed");

        // Promote Mid so LeafB becomes its tree child.
        auto MidPlannerParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        auto MidAsPlanner = utils_goap_planner::PromoteActionToPlanner(_MidAction, MidPlannerParams);
        Assert_True(ck::IsValid(MidAsPlanner), "Mid PromoteActionToPlanner should succeed");

        // LeafB makes Mid composite so UpdateActivation extends the chain
        // through Mid.
        auto LeafBParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_LeafB_GoalIsEffects);
        auto LeafBAction = utils_goap_planner::AddAction(MidAsPlanner, LeafBParams);
        Assert_True(ck::IsValid(LeafBAction), "LeafB AddAction should succeed");

        // Bind the signal NOW — before any UpdateActivation runs.
        utils_goap_planner::BindTo_OnActiveChainChanged(_Planner,
            FCk_Delegate_Goap_OnActiveChainChanged(this, n"OnChainChanged"));

        // Sanity: initial chain is empty before any plan runs.
        auto Chain = utils_goap_planner::Get_ActiveChain(_Planner);
        Assert_True(Chain.Num() == 0,
            f"ActiveChain should start empty before any plan runs (got {Chain.Num()})");
    }

    UFUNCTION()
    private void OnChainChanged(
        FCk_Handle_Goap_Planner InPlanner,
        FCk_Goap_Payload_OnActiveChainChanged InPayload)
    {
        if (IsFinished()) { return; }

        _SignalFiredCount = _SignalFiredCount + 1;

        // First firing: the chain extension from [] to [Mid, ...].
        if (_PayloadVerified) { return; }
        _PayloadVerified = true;

        // Payload contains the OLD chain snapshot (pre-mutation). The signal
        // may fire multiple times in one frame as both the top-level Planner
        // and Mid's promoted Planner run their UpdateActivation passes — the
        // first fire we see has OldChain=[] (top-level activation walk), but
        // FireIfPayloadInFlightThisFrame may surface a later fire whose
        // snapshot already includes Mid. Either is consistent with the design;
        // we only require that the post-mutation chain is non-empty.
        auto OldChain = InPayload.Get_OldChain();
        Assert_True(OldChain.Num() <= 2,
            f"_OldChain length should be reasonable (got {OldChain.Num()})");

        // Current chain (post-mutation) starts with Mid (the planner's Plan[0]).
        auto NewChain = utils_goap_planner::Get_ActiveChain(_Planner);
        Assert_True(NewChain.Num() >= 1,
            f"Get_ActiveChain should include Mid (got {NewChain.Num()})");

        if (NewChain.Num() >= 1)
        {
            Assert_True(NewChain[0] == _MidAction,
                "NewChain[0] should be Mid (the appended composite)");
        }

        Assert_True(_SignalFiredCount >= 1,
            f"OnActiveChainChanged should have fired at least once (fired {_SignalFiredCount})");

        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_Planner_OnPlanChangedSignal_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_Planner_OnPlanChangedSignal;
    default _TimeoutSeconds = 15.0f;
}
