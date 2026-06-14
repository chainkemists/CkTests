// Language=angelscript
//============================================================================
// CK GOAP — AUTOMATION TEST: dynamic action cost flips the plan
//============================================================================
// Two no-precondition actions both satisfy goal Reached=true:
//   Cheap  cost 3  |  Pricey cost 5  -> initial plan [Cheap].
// Push Cheap's cost to 7 -> plan must flip to [Pricey].
// This task uses the existing Request_SetChildActionCost; a later task adds
// the register/introspection veneer.
//============================================================================

namespace Ck
{
    asset Asset_Tags_GoapCostProvider of UCk_GameplayTags
    {
        GameplayTags.Add(n"Gym.GoapCostProvider.WS.Reached");
        GameplayTags.Add(n"Gym.GoapCostProvider.ActionSet");
    }
}

class UCk_GoapCostProviderTest_Cheap : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(n"Gym.GoapCostProvider.WS.Reached"), true);
        SetCost(3.0f);
    }
}

class UCk_GoapCostProviderTest_Pricey : UCk_GoapAction_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineAction()
    {
        AddEffect(utils_gameplay_tag::ResolveGameplayTag(n"Gym.GoapCostProvider.WS.Reached"), true);
        SetCost(5.0f);
    }
}

class UCk_AutoTest_Goap_Planner_CostProviderFlip : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_Planner _Planner;
    private bool _SawCheapFirst = false;
    private bool _PushedAlready  = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Local = InHandle;
        utils_transform::Add(Local, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto WS = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.GoapCostProvider.ActionSet"),
            FCk_Fragment_Goap_WorldState_ParamsData());
        utils_goap_world_state::Set_Value(WS,
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.GoapCostProvider.WS.Reached"), false);

        auto Goal = TArray<FCk_GoapWS_Condition_Authored>();
        Goal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.GoapCostProvider.WS.Reached"), true));

        auto PlannerParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Gym.GoapCostProvider.ActionSet"));
        PlannerParams.Set_Goal(Goal);
        PlannerParams.Set_WorldStateSource(WS);
        PlannerParams.Set_ReplanPolicy(ECk_Goap_ReplanPolicy::OnCostDirty);
        _Planner = utils_goap_planner::Add(Local, PlannerParams);

        utils_goap_planner::AddAction(_Planner,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapCostProviderTest_Cheap));
        utils_goap_planner::AddAction(_Planner,
            FCk_Fragment_Goap_ActionParamsData(UCk_GoapCostProviderTest_Pricey));

        utils_goap_planner::BindTo_OnPlanComplete(_Planner,
            FCk_Delegate_Goap_OnPlanComplete(this, n"OnPlan"));
    }

    UFUNCTION()
    private void OnPlan(FCk_Handle_Goap_Planner InPlanner, FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }

        auto Plan = utils_goap_planner::Get_PlanClasses(_Planner);
        if (Plan.Num() != 1) { return; }

        if (_SawCheapFirst == false)
        {
            Assert_True(Plan[0] == UCk_GoapCostProviderTest_Cheap,
                f"initial plan should be [Cheap] (cheapest goal-satisfier), head was not Cheap");
            _SawCheapFirst = true;

            if (_PushedAlready == false)
            {
                _PushedAlready = true;
                utils_goap_planner::Request_SetChildActionCost(
                    _Planner, UCk_GoapCostProviderTest_Cheap, 7.0f);
            }
            return;
        }

        Assert_True(Plan[0] == UCk_GoapCostProviderTest_Pricey,
            "after pushing Cheap to 7, plan should flip to [Pricey] (5 < 7)");
        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_Planner_CostProviderFlip_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_Planner_CostProviderFlip;
    default _TimeoutSeconds = 20.0f;
}
