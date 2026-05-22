// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: ACTIONSET WS OVERRIDE (spec §9 row 7)
//============================================================================
//
// Validates: a child Action WITH an explicit _WorldStateSource_Override has
// a different resolved WS than the parent Action.
//
// Setup:
//   - WS_Parent: WorldState for Root. Registers AKey=false.
//   - WS_Child:  WorldState for Mid override. Registers AKey=false.
//   - Root Action: effect AKey=true, _InitialGoal_RootOnly={AKey=true}.
//     SetRootAction with WS_Parent → Root resolved WS = WS_Parent.
//   - Mid Action: effect AKey=true, _WorldStateSource_Override = WS_Child.
//     AddAction_ToAction(Root, MidParamsWithOverride) → Mid resolved WS = WS_Child.
//
// Assert (synchronous — WS resolution is eager at AddAction_ToAction time):
//   Get_WorldStateSource(RootAction) == WS_Parent
//   Get_WorldStateSource(MidAction)  == WS_Child
//   WS_Parent != WS_Child  (distinct entities)
//   Get_WorldStateSource(MidAction) != Get_WorldStateSource(RootAction)
//
// The test does NOT need to wait for planning; WS resolution is performed
// synchronously inside AddAction_ToAction (eager-resolve).
//============================================================================

class UCk_AutoTest_Goap_ActionSet_WSOverride : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Local = InHandle;
        utils_transform::Add(Local, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        // Create WS_Parent — used as the Root's WorldState source.
        auto WS_Parent = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS"),
            FCk_Fragment_Goap_WorldState_ParamsData());
        utils_goap_world_state::Set_Value(WS_Parent,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.AKey"),
            false);

        // Create WS_Child — used as Mid's WS override. Use a distinct label tag
        // so this WS entity is a separate entity from WS_Parent.
        auto WS_Child = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.Child"),
            FCk_Fragment_Goap_WorldState_ParamsData());
        utils_goap_world_state::Set_Value(WS_Child,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.AKey"),
            false);

        Assert_True(ck::IsValid(WS_Parent), "WS_Parent should be a valid handle");
        Assert_True(ck::IsValid(WS_Child),  "WS_Child should be a valid handle");

        // The two WS handles must be distinct (different entities).
        Assert_True(!(WS_Parent == WS_Child),
            "WS_Parent and WS_Child should be different handles");

        // Goap root container.

        // ActionSet.
        auto ActionSetParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        auto ActionSet = utils_goap_planner::Add(Local, ActionSetParams);
        Assert_True(ck::IsValid(ActionSet), "AddActionSet should return a valid handle");

        // Root Action: _InitialGoal_RootOnly={AKey=true}, WS source = WS_Parent.
        auto InitialGoal = TArray<FCk_GoapWS_Condition_Authored>();
        InitialGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.AKey"),
            true));
        auto RootParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Root_WSInheritance);
        RootParams.Set_InitialGoal_RootOnly(InitialGoal);

        auto RootAction = utils_goap_planner::SetRootAction(ActionSet, RootParams, WS_Parent);
        Assert_True(ck::IsValid(RootAction), "SetRootAction should return a valid handle");

        // Mid Action: explicit WS override = WS_Child.
        auto MidParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Mid_WSInheritance);
        MidParams.Set_WorldStateSource_Override(WS_Child);

        auto MidAction = utils_goap_action::AddAction_ToAction(RootAction, MidParams);
        Assert_True(ck::IsValid(MidAction), "AddAction_ToAction should return a valid handle");

        // WS resolution is synchronous (eager-resolve in AddAction_ToAction).
        auto RootWS = utils_goap_action::Get_WorldStateSource(RootAction);
        auto MidWS  = utils_goap_action::Get_WorldStateSource(MidAction);

        Assert_True(ck::IsValid(RootWS),
            "Root's resolved WorldState source should be valid");
        Assert_True(ck::IsValid(MidWS),
            "Mid's resolved WorldState source should be valid (explicit override)");

        // Root must resolve to WS_Parent.
        Assert_True(RootWS == WS_Parent,
            "Root's resolved WS should equal WS_Parent");

        // Mid must resolve to WS_Child (override), NOT to WS_Parent (inherited).
        Assert_True(MidWS == WS_Child,
            "Mid's resolved WS should equal WS_Child (explicit override)");
        Assert_True(!(MidWS == WS_Parent),
            "Mid's resolved WS should NOT equal WS_Parent — override must take precedence");

        // Root and Mid must have DIFFERENT resolved WS sources.
        Assert_True(!(MidWS == RootWS),
            "Mid's resolved WS should differ from Root's resolved WS");

        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_ActionSet_WSOverride_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_ActionSet_WSOverride;
}
