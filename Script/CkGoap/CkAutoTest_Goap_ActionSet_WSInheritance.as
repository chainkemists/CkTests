// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: ACTIONSET WS INHERITANCE (spec §9 row 6)
//============================================================================
//
// Validates: a child Action without a WS override inherits the parent
// Action's resolved WorldState source.
//
// Setup:
//   - WS_Parent: single WorldState entity, pre-registers AKey=false.
//   - Root Action: effect AKey=true, _InitialGoal_RootOnly={AKey=true}.
//     SetRootAction called with WS_Parent → Root's resolved WS = WS_Parent.
//   - Mid Action: effect AKey=true, no _WorldStateSource_Override set.
//     AddAction_ToAction(Root, MidParams) — Mid inherits Root's WS.
//
// Assert (synchronous — WS resolution is eager at AddAction_ToAction time):
//   Get_WorldStateSource(MidAction) == Get_WorldStateSource(RootAction)
//   Both equal WS_Parent.
//
// The test does NOT need to wait for planning; WS resolution is performed
// synchronously inside AddAction_ToAction (eager-resolve).
//============================================================================

class UCk_AutoTest_Goap_ActionSet_WSInheritance : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Local = InHandle;
        utils_transform::Add(Local, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        // Create a single WorldState entity. Register AKey so the planner
        // can reason over it.
        auto WS_Parent = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS"),
            FCk_Fragment_Goap_WorldState_ParamsData());
        utils_goap_world_state::Set_Value(WS_Parent,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.AKey"),
            false);

        Assert_True(ck::IsValid(WS_Parent), "WS_Parent should be a valid handle");

        // Goap root container.
        auto Goap = utils_goap::Add(Local, FCk_Fragment_Goap_RootParamsData());

        // ActionSet.
        auto ActionSetParams = FCk_Fragment_Goap_ActionSetParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        auto ActionSet = utils_goap_action_set::AddActionSet(Goap, ActionSetParams);
        Assert_True(ck::IsValid(ActionSet), "AddActionSet should return a valid handle");

        // Root Action: _InitialGoal_RootOnly={AKey=true}, WS source = WS_Parent.
        auto InitialGoal = TArray<FCk_GoapWS_Condition_Authored>();
        InitialGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.AKey"),
            true));
        auto RootParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Root_WSInheritance);
        RootParams.Set_InitialGoal_RootOnly(InitialGoal);

        auto RootAction = utils_goap_action_set::SetRootAction(ActionSet, RootParams, WS_Parent);
        Assert_True(ck::IsValid(RootAction), "SetRootAction should return a valid handle");

        // Mid Action: no WS override — should inherit Root's WS.
        auto MidParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Mid_WSInheritance);
        // NOTE: No Set_WorldStateSource_Override call — Mid must inherit.
        auto MidAction = utils_goap_action::AddAction_ToAction(RootAction, MidParams);
        Assert_True(ck::IsValid(MidAction), "AddAction_ToAction should return a valid handle");

        // WS resolution is synchronous (eager-resolve in AddAction_ToAction).
        auto RootWS = utils_goap_action::Get_WorldStateSource(RootAction);
        auto MidWS  = utils_goap_action::Get_WorldStateSource(MidAction);

        Assert_True(ck::IsValid(RootWS),
            "Root's resolved WorldState source should be valid");
        Assert_True(ck::IsValid(MidWS),
            "Mid's resolved WorldState source should be valid (inherited from Root)");

        // Mid must have inherited Root's WS source — they must be the same entity.
        Assert_True(RootWS == WS_Parent,
            "Root's resolved WS should equal WS_Parent");
        Assert_True(MidWS == WS_Parent,
            "Mid's resolved WS should equal WS_Parent (inherited, no override set)");
        Assert_True(MidWS == RootWS,
            "Mid's resolved WS should equal Root's resolved WS (inheritance)");

        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_ActionSet_WSInheritance_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_ActionSet_WSInheritance;
}
