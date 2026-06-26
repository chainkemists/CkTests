// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: WORLDSTATE OVERRIDE STACK — DIRTY SIGNAL
//============================================================================
//
// Validates that Push_Override / Pop_Override fire the dirty signal so the
// planner replans — but only when the effective view actually changes.
// Idempotent re-push of the same values is a quiet no-op (no spurious replan).
//
// Setup:
//   - WS: KeyA=true, KeyB=false, Goal=false.
//   - Planner goal {Goal=true}.
//   - OpA (precondition KeyA=true → Goal=true).
//   - OpB (precondition KeyB=true → Goal=true).
//
// Sequence — OnPlanComplete fire counter:
//   1. Initial plan completes (KeyA=true → OpA picked).             count = 1
//   2. Push_Override("test", {KeyA=false, KeyB=true}) — effective
//      view flips. Dirty signal fires → planner replans (Plan=[OpB]). count = 2
//   3. Push_Override("test", same values) — idempotent re-push.
//      Effective view unchanged → no dirty fire, no replan.          count = 2
//   4. Pop_Override_ByName("test") — effective view flips back.
//      Dirty signal fires → planner replans (Plan=[OpA]).            count = 3
//
// We use a settle-frame wait after the idempotent re-push to be sure no
// spurious replan fires before declaring success.
//============================================================================

class UCk_AutoTest_Goap_Planner_WSOverrideStack_DirtyFiresOnPushPop : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_Action _RootAction;
    private FCk_Handle_Goap_Planner _Planner;
    private FCk_Handle_Goap_WorldState _WS;
    private int32 _PlansReceived = 0;
    private int32 _IdempotentSettleFrames = 0;
    private bool _IdempotentRePushDone = false;
    private bool _PopDone = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
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
        // Framework test catalog — opt out of always-valid-plan tenet enforcement
        // (CkGoap/CLAUDE.md § "Design tenets"). Game-content must never opt out.
        PlannerParams.Set_AllowPlanFailed(true);
        _Planner = utils_goap_planner::Add(Local, PlannerParams);
        Assert_True(ck::IsValid(_Planner), "Add Planner should return a valid handle");

        auto RootParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_WSOverrideStack_Root);
        _RootAction = utils_goap_planner::AddAction(_Planner, RootParams);
        Assert_True(ck::IsValid(_RootAction), "AddAction (root) should return a valid handle");

        auto OpAParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_WSOverrideStack_OpA);
        auto OpA = utils_goap_planner::AddAction(_Planner, OpAParams);
        Assert_True(ck::IsValid(OpA), "AddAction (OpA) should return a valid handle");

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

        if (_PlansReceived == 1)
        {
            // Initial plan completed. Push overrides → dirty should fire → replan.
            utils_goap_world_state::Push_Override_SingleKey(_WS, n"test",
                utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.WSOverrideStack.KeyA"),
                false);
            utils_goap_world_state::Push_Override_SingleKey(_WS, n"test",
                utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.WSOverrideStack.KeyB"),
                true);
            return;
        }

        if (_PlansReceived == 2)
        {
            // Push caused replan (count = 2 as expected). Now idempotent
            // re-push with SAME values — must NOT trigger a replan.
            utils_goap_world_state::Push_Override_SingleKey(_WS, n"test",
                utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.WSOverrideStack.KeyA"),
                false);
            utils_goap_world_state::Push_Override_SingleKey(_WS, n"test",
                utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.WSOverrideStack.KeyB"),
                true);
            _IdempotentRePushDone = true;

            // Settle a few frames to make sure no spurious replan fires.
            _IdempotentSettleFrames = 0;
            WaitOneFrame(n"OnIdempotentSettle");
            return;
        }

        // If a third plan completes BEFORE the idempotent settle window ends,
        // the re-push leaked a dirty signal — fail.
        if (_PlansReceived == 3 && _IdempotentRePushDone && !_PopDone)
        {
            Assert_True(false,
                "Idempotent Push_Override re-push should NOT trigger a replan (no effective view change)");
            return;
        }

        // After the pop, this branch fires.
        Assert_True(_PopDone, "Phase 3 should only fire after the pop");
        Assert_True(_PlansReceived == 3,
            f"Should have exactly 3 plan completes by now (got {_PlansReceived})");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnIdempotentSettle(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _IdempotentSettleFrames = _IdempotentSettleFrames + 1;
        if (_IdempotentSettleFrames < 5)
        {
            WaitOneFrame(n"OnIdempotentSettle");
            return;
        }

        // No spurious replan fired during the settle window. _PlansReceived
        // must still be 2 — assert and then perform the pop.
        Assert_True(_PlansReceived == 2,
            f"Plans should still be 2 after idempotent re-push (got {_PlansReceived})");

        utils_goap_world_state::Pop_Override_ByName(_WS, n"test");
        _PopDone = true;
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR
//============================================================================

class ACk_AutoTest_Goap_Planner_WSOverrideStack_DirtyFiresOnPushPop_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_Planner_WSOverrideStack_DirtyFiresOnPushPop;
    default _TimeoutSeconds = 20.0f;
}
