// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: ACTIONSET/TIER SMOKE — ROOT TIER PLANS ONE ACTION
//============================================================================
//
// Smoke test for the new ActionSet/Tier model end-to-end:
//   1. Spawn a WorldState entity.
//   2. Add a Goap root container on this entity.
//   3. AddActionSet (one action set).
//   4. AddTier (first AddTier on the action set becomes the root):
//        - WorldStateSource override = our WS
//        - Initial goal = { Ready = true }
//   5. AddAction (the trivial UCk_AutoTestAction_Goap_ActionSet_Simple).
//   6. BindTo_OnPlanComplete on the root tier.
//
// Expected: within a couple of frames, the planner fires OnPlanComplete
//           with a 1-element plan (the Simple action). PlanCost ~= 1.0.
//
// This exercises: Add, AddActionSet, AddTier (root path with WS override +
//                 initial goal), AddAction, Tier_Setup (CDO extraction +
//                 root goal seeding), AutoReplan (initial-plan tag),
//                 HandleRequests (Plan build), Execute (A* search),
//                 HandleResult (path → action sequence + signal).
//============================================================================

class UCk_AutoTest_Goap_ActionSet_RootOnly : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_Tier _RootTier;
    private bool _PlanReceived = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Local = InHandle;
        utils_transform::Add(Local, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        // World state — initial state has Ready=false implicitly (all keys
        // default to false).
        auto WS = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS"),
            FCk_Fragment_Goap_WorldState_ParamsData());

        // Goap root container.
        auto Goap = utils_goap::Add(Local, FCk_Fragment_Goap_RootParamsData());
        Assert_True(utils_goap::Has(Goap), "Has(Goap) should be true after Add");

        // ActionSet.
        auto ActionSetParams = FCk_Fragment_Goap_ActionSetParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.ActionSet"));
        auto ActionSet = utils_goap_action_set::AddActionSet(Goap, ActionSetParams);
        Assert_True(ck::IsValid(ActionSet), "AddActionSet should return a valid handle");

        // Root tier — first AddTier on an action set becomes the root.
        auto TierParams = FCk_Fragment_Goap_TierParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Tier.Root"));
        TierParams.Set_WorldStateSource_Override(WS);

        // Initial goal: Ready = true.
        auto Goal = TArray<FCk_GoapWS_Condition_Authored>();
        Goal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.Ready"),
            true));
        TierParams.Set_InitialGoal_RootOnly(Goal);

        _RootTier = utils_goap_tier::AddTier(ActionSet, TierParams);
        Assert_True(ck::IsValid(_RootTier), "AddTier should return a valid handle");

        utils_goap_tier::AddAction(_RootTier, UCk_AutoTestAction_Goap_ActionSet_Simple);

        // Active chain should contain the root immediately.
        auto Active = utils_goap_action_set::Get_ActiveTiers(ActionSet);
        Assert_True(Active.Num() == 1,
            f"ActiveTiers should contain just the root after AddTier (got {Active.Num()})");

        utils_goap_tier::BindTo_OnPlanComplete(_RootTier,
            FCk_Delegate_Goap_OnTierPlanComplete(this, n"OnPlan"));
    }

    UFUNCTION()
    private void OnPlan(FCk_Handle_Goap_Tier InTier, FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }
        if (_PlanReceived) { return; }   // first plan only
        _PlanReceived = true;

        const auto Actions = InPayload.Get_Actions();
        Assert_True(Actions.Num() == 1,
            f"Plan should contain exactly 1 action (got {Actions.Num()})");

        Assert_True(utils_goap_tier::Get_PlanStatus(_RootTier) == ECk_GoapPlanStatus::PlanFound,
            "Tier _PlanStatus should be PlanFound");

        Assert_True(InPayload.Get_TotalCost() > 0.0f,
            f"Plan cost should be > 0 (got {InPayload.Get_TotalCost()})");

        FinishSuccess();
    }
}
