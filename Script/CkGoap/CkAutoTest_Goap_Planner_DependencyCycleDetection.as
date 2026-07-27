// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: PLANNER DEPENDENCY CYCLE DETECTION
//============================================================================
//
// Validates utils_goap_planner::Get_DependencyCycles(Planner).
//
// Per spec §7.1-7.2: Setup runs an iterative Tarjan SCC over the Planner's
// direct children's PRECONDITION/EFFECT dependency graph. For sibling
// Actions A and B, an edge A -> B exists iff some effect (Key,Value) in A
// satisfies some precondition (Key,Value) in B. Any non-trivial SCC
// (size > 1, or size 1 with a self-loop) is recorded as a diagnostic and
// surfaces via Get_DependencyCycles. The planner does not refuse cyclic
// catalogs — the diagnostic is informational.
//
// Setup:
//   - WS: AKey=false, BKey=false.
//   - Implicit-root Action (Root_GoalIsEffects, effect AKey=true).
//   - Sibling direct children that form a 2-cycle:
//       CycleA: precondition BKey=true, effect AKey=true
//       CycleB: precondition AKey=true, effect BKey=true
//     Edge CycleA -> CycleB (A's AKey-effect satisfies B's AKey-precondition).
//     Edge CycleB -> CycleA (B's BKey-effect satisfies A's BKey-precondition).
//     SCC = {CycleA, CycleB}, size 2.
//
// Assertions:
//   - Get_DependencyCycles(Planner).Num() >= 1   (real cycle detected).
//   - The cycle's _ActionsInCycle contains BOTH CycleA and CycleB classes.
//   - The cycle's _CycleConditions contains AKey AND BKey.
//   - FinishSuccess.
//
// Expected log noise: FProcessor_Goap_Planner_Setup emits a Warning when
// cycles are found ("Planner [...] has [N] dependency cycle(s) ..."). The
// actor wrapper registers that pattern in Get_ExpectedLogErrors so the
// automation framework doesn't auto-fail the test on its own deliberate
// diagnostic output.
//============================================================================

class UCk_AutoTest_Goap_Planner_DependencyCycleDetection : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_Planner _Planner;
    private FCk_Handle_Goap_Action _RootAction;

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
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.AKey"),
            false);
        utils_goap_world_state::Set_Value(WS,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.BKey"),
            false);

        // Goal AKey=true so Root has SOMETHING to plan toward; the cycle is
        // among the sibling Actions, not on Root itself.
        auto InitialGoal = TArray<FCk_GoapWS_Condition_Authored>();
        InitialGoal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.AKey"),
            true));

        auto PlannerParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        PlannerParams.Set_Goal(InitialGoal);
        PlannerParams.Set_WorldStateSource(WS);
        _Planner = utils_goap_planner::Add(Local, PlannerParams);
        Assert_True(ck::IsValid(_Planner), "Add Planner should return a valid handle");

        // First AddAction = implicit-root Action.
        auto RootParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Root_GoalIsEffects);
        _RootAction = utils_goap_planner::AddAction(_Planner, RootParams);
        Assert_True(ck::IsValid(_RootAction), "AddAction (implicit-root) should return a valid handle");

        // Two sibling Actions forming a precondition/effect cycle. These
        // become direct children of the implicit root (== direct children of
        // the Planner per FProcessor_Goap_Planner_Setup).
        auto CycleAParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_CycleA);
        auto CycleAAction = utils_goap_planner::AddAction(_Planner, CycleAParams);
        Assert_True(ck::IsValid(CycleAAction), "CycleA AddAction should succeed");

        auto CycleBParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_CycleB);
        auto CycleBAction = utils_goap_planner::AddAction(_Planner, CycleBParams);
        Assert_True(ck::IsValid(CycleBAction), "CycleB AddAction should succeed");

        // Per-Action Setup runs first, then per-Planner Setup detects cycles.
        // There is no terminal signal to bind to (the cycle Actions can never
        // plan — they need each other's effects, which start false), but the
        // diagnostic surfacing IS the observable: wait for Get_DependencyCycles
        // to become non-empty instead of guessing a frame count.
        WaitUntil(n"Check_CyclesDetected", n"OnSettleTick");
    }

    UFUNCTION()
    private void Check_CyclesDetected(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_goap_planner::Get_DependencyCycles(_Planner).Num() >= 1);
    }

    UFUNCTION()
    private void OnSettleTick(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Cycles = utils_goap_planner::Get_DependencyCycles(_Planner);

        // ---- Verify the cycle's class list contains BOTH CycleA and CycleB.
        bool FoundCycleWithBoth = false;
        bool AllAKeyAndBKey = false;
        for (int32 i = 0; i < Cycles.Num(); i++)
        {
            auto Diagnostic = Cycles[i];
            auto Classes = Diagnostic.Get_ActionsInCycle();

            bool HasA = false;
            bool HasB = false;
            for (int32 j = 0; j < Classes.Num(); j++)
            {
                if (Classes[j] == UCk_AutoTestAction_Goap_ActionSet_CycleA) { HasA = true; }
                if (Classes[j] == UCk_AutoTestAction_Goap_ActionSet_CycleB) { HasB = true; }
            }

            if (HasA && HasB)
            {
                FoundCycleWithBoth = true;

                auto Conditions = Diagnostic.Get_CycleConditions();
                bool HasAKey = false;
                bool HasBKey = false;
                auto AKey = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.AKey");
                auto BKey = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.WS.BKey");
                for (int32 k = 0; k < Conditions.Num(); k++)
                {
                    if (Conditions[k] == AKey) { HasAKey = true; }
                    if (Conditions[k] == BKey) { HasBKey = true; }
                }
                if (HasAKey && HasBKey) { AllAKeyAndBKey = true; }
                break;
            }
        }

        Assert_True(FoundCycleWithBoth,
            "A reported cycle must list BOTH CycleA and CycleB as members");
        Assert_True(AllAKeyAndBKey,
            "The cycle's _CycleConditions must include both AKey and BKey (the WS keys that close the loop)");

        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_Planner_DependencyCycleDetection_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_Planner_DependencyCycleDetection;
    default _TimeoutSeconds = 15.0f;

    // The Planner Setup processor emits a Warning when it detects cycles; this
    // test deliberately constructs a cycle to validate the diagnostic, so the
    // warning is expected. Register the pattern so the automation framework
    // doesn't auto-fail the test on its own deliberate diagnostic output.
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        Out.Add("dependency cycle");
        return Out;
    }
}
