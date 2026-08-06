// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: PLANNER 4-TIER DEEP NESTING
//============================================================================
//
// Coverage gap filler: the design spec §2.2 illustrates a 4-tier hierarchy
//
//   Alive (Planner)
//     ├─ Win (atomic Action)
//     └─ Engage (Planner + Action — tier 2)
//          └─ LightAttacks (Planner + Action — tier 3)
//               ├─ Light1 (atomic Action — tier 4)
//               └─ Light2 (atomic Action — tier 4)
//
// but no regression test exercises 4+ tiers end-to-end. The U11.6 Patrol gym
// is only 3 tiers. This test fills that gap and is the canonical "the spec's
// flagship example actually works" check.
//
// World-state setup (all keys initially false):
//   - EnemyHit, EnemyAttacked, EnemyDead.
//
// Goal cascade:
//   - Alive planner goal:        {EnemyDead=true}
//   - Engage promoted goal:      {EnemyAttacked=true}
//   - LightAttacks promoted goal:{EnemyHit=true}
//
// Action wiring:
//   - Alive_Root (under Alive)    : effect EnemyDead=true (root host; not selected as op).
//   - Win (under Alive)           : pre EnemyAttacked=true, effect EnemyDead=true, cost 1.0.
//   - Engage (under Alive)        : effect EnemyAttacked=true, cost 1.0.
//   - LightAttacks (under Engage) : effect EnemyAttacked=true, cost 1.0.
//   - Light1 (under LightAttacks) : effect EnemyHit=true, cost 1.0.
//   - Light2 (under LightAttacks) : effect EnemyHit=true, cost 2.0 (distractor).
//
// Expected plans (each tier verified via Get_PlanClasses):
//   - Alive plan         = [Engage, Win]     — regressive: Win needs EnemyAttacked,
//                                              only Engage produces it; plan is sequenced
//                                              in execution order.
//   - Engage promoted    = [LightAttacks]    — goal EnemyAttacked, LightAttacks satisfies.
//   - LightAttacks prom. = [Light1]          — goal EnemyHit; Light1 cheaper than Light2.
//
// Flow:
//   1. DoBeginPlay wires the full hierarchy and binds OnPlanComplete on the
//      Alive root, Engage, and LightAttacks Action handles.
//   2. OnAlivePlan asserts Alive plan, then sub-planners must activate via
//      ChainUpdate. Each sub-planner's OnPlanComplete fires when its plan
//      is produced (after activation extends the chain).
//   3. After all three plans are observed, FinishSuccess.
//============================================================================

namespace Ck
{
    asset Asset_AutoTest_Goap_DeepNesting_Tags of UCk_GameplayTags
    {
        // Top-tier goal.
        GameplayTags.Add(n"AutoTest.Goap.DeepNesting.WS.EnemyDead");
        // Tier-2 (Engage) goal — produced by LightAttacks' effect.
        GameplayTags.Add(n"AutoTest.Goap.DeepNesting.WS.EnemyAttacked");
        // Tier-3 (LightAttacks) goal — produced by Light1/Light2.
        GameplayTags.Add(n"AutoTest.Goap.DeepNesting.WS.EnemyHit");
        // Planner-name tag (one Planner per tier reuses this name — they live
        // on different host entities so collisions don't matter).
        GameplayTags.Add(n"AutoTest.Goap.DeepNesting.Planner");
        // WS entity name tag.
        GameplayTags.Add(n"AutoTest.Goap.DeepNesting.WS");
    }
}

class UCk_AutoTest_Goap_Planner_DeepNesting : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_Planner _Alive;
    private FCk_Handle_Goap_Planner _Engage_AsPlanner;
    private FCk_Handle_Goap_Planner _LightAttacks_AsPlanner;
    private FCk_Handle_Goap_Action _AliveRoot;
    private FCk_Handle_Goap_Action _Engage;
    private FCk_Handle_Goap_Action _LightAttacks;

    private bool _AlivePlanOK = false;
    private bool _EngagePlanOK = false;
    private bool _LightAttacksPlanOK = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Local = InHandle;
        utils_transform::Add(Local, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        // ---- World state: all goal keys start false. ----
        auto WS = utils_goap_world_state::Create(Local,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.DeepNesting.WS"),
            FCk_Goap_WorldState_Spec());
        utils_goap_world_state::Set_Value(WS,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.DeepNesting.WS.EnemyHit"),
            false);
        utils_goap_world_state::Set_Value(WS,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.DeepNesting.WS.EnemyAttacked"),
            false);
        utils_goap_world_state::Set_Value(WS,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.DeepNesting.WS.EnemyDead"),
            false);

        // ---- Tier 1: Alive top-level Planner ----
        auto AliveGoal = TArray<FCk_GoapWS_Condition_Authored>();
        AliveGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.DeepNesting.WS.EnemyDead"),
            true));

        auto AliveParams = FCk_Goap_Planner_Spec(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.DeepNesting.Planner"));
        AliveParams.Set_Goal(AliveGoal);
        AliveParams.Set_WorldStateSource(WS);
        // Framework test catalog — minimal planner shape, no fallback Action.
        // Opt out of the always-valid-plan tenet enforcement (see CkGoap/CLAUDE.md
        // § "Design tenets"). Game-content Planners must NEVER set this true.
        AliveParams.Set_AllowPlanFailed(true);
        _Alive = utils_goap_planner::Add(Local, AliveParams);
        Assert_True(ck::IsValid(_Alive), "Add Alive Planner should return a valid handle");

        // PR-B.1b Stage 5: no implicit-root Action. The legacy Alive class is
        // dropped — its effect (EnemyDead=true cost 0) would short-circuit the
        // plan to a single-step Alive_Root instead of the [Engage, Win] chain.

        // ---- Tier 2: Engage Action (direct child of Alive Planner) ----
        auto EngageParams = FCk_Goap_Action_Spec(
            UCk_AutoTestAction_Goap_DeepNesting_Engage);
        _Engage = utils_goap_planner::AddAction(_Alive, EngageParams);
        Assert_True(ck::IsValid(_Engage), "Engage AddAction (under Alive) should succeed");
        _AliveRoot = _Engage;

        // Win — atomic finisher under Alive (precondition EnemyAttacked=true).
        auto WinParams = FCk_Goap_Action_Spec(
            UCk_AutoTestAction_Goap_DeepNesting_Win);
        auto Win = utils_goap_planner::AddAction(_Alive, WinParams);
        Assert_True(ck::IsValid(Win), "Win AddAction (under Alive) should succeed");

        // Promote Engage to a Planner with its own goal {EnemyAttacked=true}.
        auto EngageGoal = TArray<FCk_GoapWS_Condition_Authored>();
        EngageGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.DeepNesting.WS.EnemyAttacked"),
            true));
        auto EngagePlannerParams = FCk_Goap_Planner_Spec(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.DeepNesting.Planner"));
        EngagePlannerParams.Set_Goal(EngageGoal);
        EngagePlannerParams.Set_AllowPlanFailed(true);  // framework test — see top
        _Engage_AsPlanner = utils_goap_planner::PromoteActionToPlanner(_Engage, EngagePlannerParams);
        Assert_True(ck::IsValid(_Engage_AsPlanner),
            "PromoteActionToPlanner(Engage) should return a valid Planner handle");

        // ---- Tier 3: LightAttacks Action (under Engage's promoted planner) ----
        auto LightAttacksParams = FCk_Goap_Action_Spec(
            UCk_AutoTestAction_Goap_DeepNesting_LightAttacks);
        _LightAttacks = utils_goap_planner::AddAction(_Engage_AsPlanner, LightAttacksParams);
        Assert_True(ck::IsValid(_LightAttacks), "LightAttacks AddAction (under Engage) should succeed");

        // Promote LightAttacks to a Planner with goal {EnemyHit=true}.
        auto LightAttacksGoal = TArray<FCk_GoapWS_Condition_Authored>();
        LightAttacksGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.DeepNesting.WS.EnemyHit"),
            true));
        auto LightAttacksPlannerParams = FCk_Goap_Planner_Spec(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.DeepNesting.Planner"));
        LightAttacksPlannerParams.Set_Goal(LightAttacksGoal);
        LightAttacksPlannerParams.Set_AllowPlanFailed(true);  // framework test — see top
        _LightAttacks_AsPlanner = utils_goap_planner::PromoteActionToPlanner(_LightAttacks, LightAttacksPlannerParams);
        Assert_True(ck::IsValid(_LightAttacks_AsPlanner),
            "PromoteActionToPlanner(LightAttacks) should return a valid Planner handle");

        // ---- Tier 4: Light1 / Light2 atomic leaves under LightAttacks ----
        auto Light1Params = FCk_Goap_Action_Spec(
            UCk_AutoTestAction_Goap_DeepNesting_Light1);
        auto Light1 = utils_goap_planner::AddAction(_LightAttacks_AsPlanner, Light1Params);
        Assert_True(ck::IsValid(Light1), "Light1 AddAction should succeed");

        auto Light2Params = FCk_Goap_Action_Spec(
            UCk_AutoTestAction_Goap_DeepNesting_Light2);
        auto Light2 = utils_goap_planner::AddAction(_LightAttacks_AsPlanner, Light2Params);
        Assert_True(ck::IsValid(Light2), "Light2 AddAction should succeed");

        // ---- Bind plan-complete on all three planning entities ----
        // Bind early — sub-planners may fire before/during ChainUpdate activation.
        // FireIfPayloadInFlightThisFrame (default) catches same-frame fires.
        utils_goap_planner::BindTo_OnPlanComplete(_Alive,
            FCk_Delegate_Goap_OnPlanComplete(this, n"OnAlivePlan"));
        utils_goap_planner::BindTo_OnPlanComplete(_Engage_AsPlanner,
            FCk_Delegate_Goap_OnPlanComplete(this, n"OnEngagePlan"));
        utils_goap_planner::BindTo_OnPlanComplete(_LightAttacks_AsPlanner,
            FCk_Delegate_Goap_OnPlanComplete(this, n"OnLightAttacksPlan"));
    }

    UFUNCTION()
    private void OnAlivePlan(FCk_Handle_Goap_Planner InPlanner, FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }
        if (_AlivePlanOK) { return; }

        auto Plan = utils_goap_planner::Get_PlanClasses(_Alive);
        // The first PlanComplete fire on Alive may produce an empty plan
        // before all child catalogs are visible — skip empty fires.
        if (Plan.Num() == 0) { return; }

        Assert_True(utils_goap_planner::Get_PlanStatus(_Alive) == ECk_GoapPlanStatus::PlanFound,
            "Alive PlanStatus should be PlanFound");
        Assert_True(Plan.Num() == 2,
            f"Alive plan should have 2 entries [Engage, Win] (got {Plan.Num()})");
        if (Plan.Num() == 2)
        {
            Assert_True(Plan[0] == UCk_AutoTestAction_Goap_DeepNesting_Engage,
                "Alive Plan[0] should be Engage (establishes EnemyAttacked)");
            Assert_True(Plan[1] == UCk_AutoTestAction_Goap_DeepNesting_Win,
                "Alive Plan[1] should be Win (consumes EnemyAttacked, sets EnemyDead)");
        }

        _AlivePlanOK = true;
        MaybeFinish();
    }

    UFUNCTION()
    private void OnEngagePlan(FCk_Handle_Goap_Planner InPlanner, FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }
        if (_EngagePlanOK) { return; }

        auto Plan = utils_goap_action::Get_Plan(_Engage);
        if (Plan.Num() == 0) { return; }

        Assert_True(utils_goap_action::Get_PlanStatus(_Engage) == ECk_GoapPlanStatus::PlanFound,
            "Engage PlanStatus should be PlanFound after activation");
        Assert_True(Plan.Num() == 1,
            f"Engage promoted-planner plan should have 1 entry [LightAttacks] (got {Plan.Num()})");
        if (Plan.Num() == 1)
        {
            Assert_True(Plan[0] == UCk_AutoTestAction_Goap_DeepNesting_LightAttacks,
                "Engage Plan[0] should be LightAttacks (satisfies EnemyAttacked goal)");
        }

        _EngagePlanOK = true;
        MaybeFinish();
    }

    UFUNCTION()
    private void OnLightAttacksPlan(FCk_Handle_Goap_Planner InPlanner, FCk_Goap_Payload_OnPlanComplete InPayload)
    {
        if (IsFinished()) { return; }
        if (_LightAttacksPlanOK) { return; }

        auto Plan = utils_goap_action::Get_Plan(_LightAttacks);
        if (Plan.Num() == 0) { return; }

        Assert_True(utils_goap_action::Get_PlanStatus(_LightAttacks) == ECk_GoapPlanStatus::PlanFound,
            "LightAttacks PlanStatus should be PlanFound after activation");
        Assert_True(Plan.Num() == 1,
            f"LightAttacks promoted-planner plan should have 1 entry (got {Plan.Num()})");
        if (Plan.Num() == 1)
        {
            Assert_True(Plan[0] == UCk_AutoTestAction_Goap_DeepNesting_Light1,
                "LightAttacks Plan[0] should be Light1 (cost 1.0 < Light2 cost 2.0)");
        }

        _LightAttacksPlanOK = true;
        MaybeFinish();
    }

    private void MaybeFinish()
    {
        if (_AlivePlanOK && _EngagePlanOK && _LightAttacksPlanOK)
        {
            FinishSuccess();
        }
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_Planner_DeepNesting_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_Planner_DeepNesting;
    default _TimeoutSeconds = 20.0f;
}
