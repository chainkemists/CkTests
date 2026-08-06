// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: PLANNER WS INHERITANCE (spec §9 row 6)
//============================================================================
//
// Validates: a child Action without a WS override inherits the parent
// Action's resolved WorldState source.
//
// Setup:
//   - WS_Parent: single WorldState entity, pre-registers AKey=false.
//   - Root Action: effect AKey=true. Planner _Goal = {AKey=true}.
//     Planner._WorldStateSource = WS_Parent → first AddAction's implicit root
//     resolves Root's WS = WS_Parent.
//   - Mid Action: effect AKey=true, no _WorldStateSource_Override set.
//     AddAction(Planner, MidParams) — Mid inherits the implicit root's WS.
//
// Assert (synchronous — WS resolution is eager at AddAction time):
//   Get_WorldStateSource(MidAction) == Get_WorldStateSource(RootAction)
//   Both equal WS_Parent.
//
// The test does NOT need to wait for planning; WS resolution is performed
// synchronously inside AddAction (eager-resolve).
//============================================================================

class UCk_AutoTest_Goap_Planner_WSInheritance : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Local = InHandle;
        utils_transform::Add(Local, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        // Create a single WorldState entity. Register AKey so the planner
        // can reason over it.
        auto WS_Parent = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS"),
            FCk_Goap_WorldState_Spec());
        utils_goap_world_state::Set_Value(WS_Parent,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.AKey"),
            false);

        Assert_True(ck::IsValid(WS_Parent), "WS_Parent should be a valid handle");

        // Goap root container.

        // U11.1: Planner goal={AKey=true} (was _InitialGoal_RootOnly on RootParams).
        auto InitialGoal = TArray<FCk_GoapWS_Condition_Authored>();
        InitialGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.AKey"),
            true));

        // Planner.
        auto ActionSetParams = FCk_Goap_Planner_Spec(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        ActionSetParams.Set_Goal(InitialGoal);
        ActionSetParams.Set_WorldStateSource(WS_Parent);
        auto Planner = utils_goap_planner::Add(Local, ActionSetParams);
        Assert_True(ck::IsValid(Planner), "Add Planner should return a valid handle");

        // Root Action: WS source = WS_Parent (inherited from PlannerParams).
        auto RootParams = FCk_Goap_Action_Spec(
            UCk_AutoTestAction_Goap_ActionSet_Root_WSInheritance);

        auto RootAction = utils_goap_planner::AddAction(Planner, RootParams);
        Assert_True(ck::IsValid(RootAction), "AddAction (implicit-root) should return a valid handle");

        // Mid Action: no WS override — should inherit Root's WS.
        auto MidParams = FCk_Goap_Action_Spec(
            UCk_AutoTestAction_Goap_ActionSet_Mid_WSInheritance);
        // NOTE: No Set_WorldStateSource_Override call — Mid must inherit.
        auto MidAction = utils_goap_planner::AddAction(Planner, MidParams);
        Assert_True(ck::IsValid(MidAction), "AddAction should return a valid handle");

        // WS resolution is synchronous (eager-resolve in AddAction).
        auto RootWS = utils_goap_planner::Get_WorldStateSource(Planner);
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

class ACk_AutoTest_Goap_Planner_WSInheritance_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_Planner_WSInheritance;
}
