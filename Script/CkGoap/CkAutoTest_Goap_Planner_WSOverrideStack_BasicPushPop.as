// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: WORLDSTATE OVERRIDE STACK — BASIC PUSH/POP
//============================================================================
//
// Validates the override stack read path: push flips effective WS values,
// the planner replans through the override, pop restores the base.
//
// Setup:
//   - WS: KeyA=true, KeyB=false (base store).
//   - Planner goal {Goal=true}.
//   - OpA: precondition KeyA=true, effect Goal=true, cost 1.0.
//   - OpB: precondition KeyB=true, effect Goal=true, cost 1.0.
//
// Phase A — initial plan: KeyA is true in base, so only OpA is viable.
//   Plan = [OpA].
//
// Phase B — Push_Override("test", {KeyA=false, KeyB=true}):
//   Override shadows base. Effective KeyA=false → OpA blocked. Effective
//   KeyB=true → OpB viable. Replan triggered by dirty signal.
//   Plan = [OpB].
//
// Phase C — Pop_Override_ByName("test"):
//   Layer removed; effective view reverts to base. KeyA=true again → OpA
//   viable; KeyB=false → OpB blocked. Replan triggered by dirty signal.
//   Plan = [OpA].
//============================================================================

class UCk_AutoTest_Goap_Planner_WSOverrideStack_BasicPushPop : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_Action _RootAction;
    private FCk_Handle_Goap_Planner _Planner;
    private FCk_Handle_Goap_WorldState _WS;
    private int32 _PlansReceived = 0;
    private int32 _SettleFrameCount = 0;
    private bool _PushDone = false;
    private bool _PopDone = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Local = InHandle;
        utils_transform::Add(Local, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        _WS = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.WSOverrideStack.WS"),
            FCk_Fragment_Goap_WorldState_ParamsData());
        utils_goap_world_state::Set_Value(_WS,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.WSOverrideStack.KeyA"),
            true);
        utils_goap_world_state::Set_Value(_WS,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.WSOverrideStack.KeyB"),
            false);
        utils_goap_world_state::Set_Value(_WS,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.WSOverrideStack.Goal"),
            false);

        auto Goal = TArray<FCk_GoapWS_Condition_Authored>();
        Goal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.WSOverrideStack.Goal"),
            true));

        auto PlannerParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.WSOverrideStack.Planner"));
        PlannerParams.Set_Goal(Goal);
        PlannerParams.Set_WorldStateSource(_WS);
        _Planner = utils_goap_planner::Add(Local, PlannerParams);
        Assert_True(ck::IsValid(_Planner), "Add Planner should return a valid handle");

        // Implicit root host.
        auto RootParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_WSOverrideStack_Root);
        _RootAction = utils_goap_planner::AddAction(_Planner, RootParams);
        Assert_True(ck::IsValid(_RootAction), "AddAction (root) should return a valid handle");

        // OpA — precondition KeyA=true.
        auto OpAParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_WSOverrideStack_OpA);
        auto OpA = utils_goap_planner::AddAction(_Planner, OpAParams);
        Assert_True(ck::IsValid(OpA), "AddAction (OpA) should return a valid handle");

        // OpB — precondition KeyB=true.
        auto OpBParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_WSOverrideStack_OpB);
        auto OpB = utils_goap_planner::AddAction(_Planner, OpBParams);
        Assert_True(ck::IsValid(OpB), "AddAction (OpB) should return a valid handle");

        utils_goap_planner::BindTo_OnPlanComplete(_Planner,
            FCk_Delegate_Goap_OnPlanComplete(this, n"OnRootPlan"));
    }

    UFUNCTION()
    private void OnRootPlan(FCk_Handle_Goap_Planner InPlanner, FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }

        _PlansReceived = _PlansReceived + 1;

        Assert_True(utils_goap_planner::Get_PlanStatus(_Planner) == ECk_GoapPlanStatus::PlanFound,
            "PlanStatus should be PlanFound");

        auto Plan = utils_goap_planner::Get_PlanClasses(_Planner);

        if (_PlansReceived == 1)
        {
            // Phase A — base WS: KeyA=true, KeyB=false → only OpA viable.
            Assert_True(Plan.Num() == 1,
                f"Phase A: plan should have 1 entry (got {Plan.Num()})");
            Assert_True(Plan.Num() > 0 && Plan[0] == UCk_AutoTestAction_Goap_WSOverrideStack_OpA,
                "Phase A: Plan[0] should be OpA (KeyA=true in base)");

            // Push the override layer: KeyA=false, KeyB=true. Effective view
            // flips so OpB becomes viable and OpA blocked.
            utils_goap_world_state::Push_Override_SingleKey(_WS, n"test",
                utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.WSOverrideStack.KeyA"),
                false);
            utils_goap_world_state::Push_Override_SingleKey(_WS, n"test",
                utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.WSOverrideStack.KeyB"),
                true);
            _PushDone = true;

            Assert_True(utils_goap_world_state::Get_OverrideDepth(_WS) == 1,
                f"Override depth should be 1 after push (got {utils_goap_world_state::Get_OverrideDepth(_WS)})");
            return;
        }

        if (_PlansReceived == 2)
        {
            // Phase B — override flipped effective view. OpB now viable.
            Assert_True(_PushDone, "Phase B should only fire after the push");
            Assert_True(Plan.Num() == 1,
                f"Phase B: plan should have 1 entry (got {Plan.Num()})");
            Assert_True(Plan.Num() > 0 && Plan[0] == UCk_AutoTestAction_Goap_WSOverrideStack_OpB,
                "Phase B: Plan[0] should be OpB (override flipped KeyA=false, KeyB=true)");

            // Pop the override layer; base view restored.
            utils_goap_world_state::Pop_Override_ByName(_WS, n"test");
            _PopDone = true;

            Assert_True(utils_goap_world_state::Get_OverrideDepth(_WS) == 0,
                f"Override depth should be 0 after pop (got {utils_goap_world_state::Get_OverrideDepth(_WS)})");
            return;
        }

        // Phase C — pop restored base view, OpA viable again.
        Assert_True(_PopDone, "Phase C should only fire after the pop");
        Assert_True(Plan.Num() == 1,
            f"Phase C: plan should have 1 entry (got {Plan.Num()})");
        Assert_True(Plan.Num() > 0 && Plan[0] == UCk_AutoTestAction_Goap_WSOverrideStack_OpA,
            "Phase C: Plan[0] should be OpA (override popped, base restored)");

        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR
//============================================================================

class ACk_AutoTest_Goap_Planner_WSOverrideStack_BasicPushPop_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_Planner_WSOverrideStack_BasicPushPop;
    default _TimeoutSeconds = 15.0f;
}
