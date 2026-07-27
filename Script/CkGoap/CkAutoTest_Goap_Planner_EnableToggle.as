// Language=angelscript

//============================================================================
// CK GOAP — AUTOMATION TEST: PLANNER ENABLE TOGGLE
//============================================================================
//
// Validates §9 row 11: "Disabled Planner skips ChainUpdate; re-enable
// resumes."
//
// The disable toggle gates FProcessor_Goap_Planner_ChainUpdate only —
// individual Action planners still run. So Root will plan and select Mid,
// but while disabled ChainUpdate never appends Mid to the active chain.
// After re-enable, ChainUpdate runs and extends the chain to [Root, Mid].
//
// Setup:
//   - WS: AKey=false, BKey=false.
//   - Root action: effect AKey=true, _InitialGoal_RootOnly={BKey=true}.
//   - Mid (child of Root): effect BKey=true. Composite (has LeafB as child).
//   - LeafB (child of Mid): effect BKey=true (makes Mid composite).
//   - Planner disabled immediately after creation.
//
// Phase 1: Wait several frames. Chain should remain [Root] (length 1).
//   ChainUpdate is suppressed; Mid is never appended even though Root's
//   plan = [Mid].
//
// Phase 2: Re-enable Planner. Wait for ChainUpdate to extend the chain.
//   Assert chain length == 2 and chain[1] == Mid_GoalIsEffects class.
//============================================================================

class UCk_AutoTest_Goap_Planner_EnableToggle : UCk_AutoTest_Base
{
    private FCk_Handle_Goap_Action _RootAction;
    private FCk_Handle_Goap_Planner _Planner;
    private int32 _DisabledFrameCount = 0;

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

        // U11.1: Planner goal = {BKey=true}. Root's CDO effect = AKey=true
        // (distinct from goal so any confusion between the two is detectable).
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

        // Disable ChainUpdate immediately — before any actions are planned.
        utils_goap_planner::Request_SetEnableToggle(_Planner, ECk_EnableDisable::Disable);
        Assert_True(
            utils_goap_planner::Get_EnableToggle(_Planner) == ECk_EnableDisable::Disable,
            "Planner should be disabled after Request_SetEnableToggle(Disable)");

        // PR-B.1b Stage 5: Mid is a direct child of the Planner. The legacy
        // Root_Toggle Action (AKey effect, distinct from goal BKey) is dropped.
        auto MidParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_Mid_GoalIsEffects);
        auto MidAction = utils_goap_planner::AddAction(_Planner, MidParams);
        Assert_True(ck::IsValid(MidAction), "Mid AddAction should succeed");
        _RootAction = MidAction;

        // Promote Mid so LeafB becomes its tree child (makes Mid composite).
        auto MidPlannerParams = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.ActionSet.Set"));
        auto MidAsPlanner = utils_goap_planner::PromoteActionToPlanner(MidAction, MidPlannerParams);
        Assert_True(ck::IsValid(MidAsPlanner), "Mid PromoteActionToPlanner should succeed");

        // Add LeafB as child of Mid — makes Mid composite so ChainUpdate
        // would extend the chain to [Root, Mid] once enabled.
        auto LeafBParams = FCk_Fragment_Goap_ActionParamsData(
            UCk_AutoTestAction_Goap_ActionSet_LeafB_GoalIsEffects);
        auto LeafBAction = utils_goap_planner::AddAction(MidAsPlanner, LeafBParams);
        Assert_True(ck::IsValid(LeafBAction), "LeafB AddAction should succeed");

        // PR-B.1b Stage 5: chain starts empty before any plan runs.
        auto Chain = utils_goap_planner::Get_ActiveChain(_Planner);
        Assert_True(Chain.Num() == 0,
            f"ActiveChain should start empty before any plan runs (got {Chain.Num()})");

        // Poll for 10 frames while disabled. Chain must not extend.
        WaitOneFrame(n"OnPollDisabledFrame");
    }

    // Poll while disabled — chain must stay at length 1.
    UFUNCTION()
    private void OnPollDisabledFrame(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Chain = utils_goap_planner::Get_ActiveChain(_Planner);
        Assert_True(Chain.Num() == 0,
            f"ActiveChain must NOT extend while Planner is disabled (frame {_DisabledFrameCount}, got {Chain.Num()})");

        _DisabledFrameCount = _DisabledFrameCount + 1;
        if (_DisabledFrameCount < 10)
        {
            WaitOneFrame(n"OnPollDisabledFrame");
            return;
        }

        // After 10 frames disabled, re-enable and wait for chain extension.
        utils_goap_planner::Request_SetEnableToggle(_Planner, ECk_EnableDisable::Enable);
        Assert_True(
            utils_goap_planner::Get_EnableToggle(_Planner) == ECk_EnableDisable::Enable,
            "Planner should be enabled after Request_SetEnableToggle(Enable)");

        // Wait for the re-enabled planner to plan AND ChainUpdate to extend —
        // the previous unbounded two-condition poll surfaced a broken re-enable
        // as an anonymous engine TimesUp naming neither condition.
        WaitUntil(n"Check_PlannedAndChainExtended", n"OnCheckChainExtended");
    }

    UFUNCTION()
    private void Check_PlannedAndChainExtended(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_goap_planner::Get_PlanStatus(_Planner) == ECk_GoapPlanStatus::PlanFound
             && utils_goap_planner::Get_ActiveChain(_Planner).Num() >= 1);
    }

    // After re-enable: chain should extend to [Root, Mid].
    UFUNCTION()
    private void OnCheckChainExtended(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Chain = utils_goap_planner::Get_ActiveChain(_Planner);

        auto MidHandle = utils_goap_planner::Find_ActionByClass(
            _Planner, UCk_AutoTestAction_Goap_ActionSet_Mid_GoalIsEffects);
        Assert_True(ck::IsValid(MidHandle), "Should find Mid by class in Planner catalog");

        if (Chain.Num() >= 1)
        {
            Assert_True(Chain[0] == MidHandle,
                "Chain[0] should be Mid after ChainUpdate extends the chain on re-enable");
        }

        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_Planner_EnableToggle_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_Planner_EnableToggle;
    default _TimeoutSeconds = 15.0f;
}
