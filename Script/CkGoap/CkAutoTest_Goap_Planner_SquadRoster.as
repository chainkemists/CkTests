// Language=angelscript

//============================================================================
// CK GOAP - AUTOMATION TEST: SQUAD ROSTER
//============================================================================
//
// A compact, asset-free roster for planner inspection.  The three top-level
// planners are named through stable gameplay tags and deliberately occupy
// three different terminal states:
//
//   AutoTest.Goap.FallbackVsChain  -> PLAN FOUND (the cheap two-step chain)
//   AutoTest.Goap.FallbackOnly     -> PLAN FOUND (the 999-cost fallback)
//   AutoTest.Goap.ActionSet.Set    -> COST THRESHOLD
//
// The fixture exposes an explicit replan pulse for a collector to invoke after
// its first snapshot, while the AutoTest drives two world-state flips. Both
// paths give a debugger's future per-planner sparkline real attempt-count
// transitions instead of a static authored snapshot.
//============================================================================

// Persistent PIE subject for debugger/screenshots. It is intentionally not an
// AutoTest runner: the actor owns its EntityScript, which owns the planner
// tree, so the rows remain alive until the PIE actor receives EndPlay.
class UCk_Goap_Planner_SquadRosterPieFixture_EntityScript : UCk_EntityScript_WithActor_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        Create_FallbackVsChainPlanner(InHandle,
            n"AutoTest.Goap.FallbackVsChain.WS", n"AutoTest.Goap.FallbackVsChain", 0.0f);
        Create_FallbackOnlyPlanner(InHandle);
        Create_FallbackVsChainPlanner(InHandle,
            n"AutoTest.Goap.ActionSet.WS", n"AutoTest.Goap.ActionSet.Set", 0.5f);
    }

    private void Create_FallbackVsChainPlanner(
        FCk_Handle InOwner, FName InWorldStateName, FName InPlannerName, float32 InCostThreshold)
    {
        auto WorldState = utils_goap_world_state::Create(InOwner,
            utils_gameplay_tag::ResolveGameplayTag(InWorldStateName),
            FCk_Fragment_Goap_WorldState_ParamsData());
        utils_goap_world_state::Set_Value(WorldState,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.FallbackVsChain.WS.MidStep"), false);
        utils_goap_world_state::Set_Value(WorldState,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.FallbackVsChain.WS.Goal"), false);

        auto Goal = TArray<FCk_GoapWS_Condition_Authored>();
        Goal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.FallbackVsChain.WS.Goal"), true));
        auto Params = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(InPlannerName));
        Params.Set_Goal(Goal);
        Params.Set_WorldStateSource(WorldState);
        Params.Set_CostThreshold(InCostThreshold);
        auto Planner = utils_goap_planner::Create(InOwner,
            utils_gameplay_tag::ResolveGameplayTag(InPlannerName), Params);
        utils_goap_planner::AddAction(Planner,
            FCk_Fragment_Goap_ActionParamsData(UCk_AutoTestAction_Goap_FallbackVsChain_Setup));
        utils_goap_planner::AddAction(Planner,
            FCk_Fragment_Goap_ActionParamsData(UCk_AutoTestAction_Goap_FallbackVsChain_Finalize));
        utils_goap_planner::AddAction(Planner,
            FCk_Fragment_Goap_ActionParamsData(UCk_AutoTestAction_Goap_FallbackVsChain_Fallback));
    }

    private void Create_FallbackOnlyPlanner(FCk_Handle InOwner)
    {
        auto WorldState = utils_goap_world_state::Create(InOwner,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.FallbackOnly.WS"),
            FCk_Fragment_Goap_WorldState_ParamsData());
        utils_goap_world_state::Set_Value(WorldState,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.FallbackOnly.WS.Unreachable"), false);
        utils_goap_world_state::Set_Value(WorldState,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.FallbackOnly.WS.Goal"), false);

        auto Goal = TArray<FCk_GoapWS_Condition_Authored>();
        Goal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.FallbackOnly.WS.Goal"), true));
        auto Params = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.FallbackOnly"));
        Params.Set_Goal(Goal);
        Params.Set_WorldStateSource(WorldState);
        auto Planner = utils_goap_planner::Create(InOwner,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.FallbackOnly"), Params);
        utils_goap_planner::AddAction(Planner,
            FCk_Fragment_Goap_ActionParamsData(UCk_AutoTestAction_Goap_FallbackOnly_Gated));
        utils_goap_planner::AddAction(Planner,
            FCk_Fragment_Goap_ActionParamsData(UCk_AutoTestAction_Goap_FallbackOnly_Fallback));
    }
}

UCLASS(Blueprintable)
class ACk_Goap_Planner_SquadRosterPieFixture : AActor
{
    default bReplicates = false;

    UPROPERTY(DefaultComponent, RootComponent)
    USceneComponent SceneRoot;

    default SceneRoot.Mobility = EComponentMobility::Movable;

    private FCk_Handle _FixtureEntity;
    private bool _HasEndedPlay = false;
    private int32 _QueuedReplanPulseSerial = 0;

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Pending = utils_entity_script_with_actor::Request_SpawnEntityScript_OnActor(
            this, UCk_Goap_Planner_SquadRosterPieFixture_EntityScript);
        utils_pending_entity_script::Promise_OnConstructed(Pending,
            FCk_Delegate_EntityScript_Constructed(this, n"OnFixtureConstructed"));
    }

    UFUNCTION()
    private void OnFixtureConstructed(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        auto FixtureEntity = FCk_Handle(InEntityScriptHandle);
        if (ck::Is_NOT_Valid(FixtureEntity)) { return; }
        if (_HasEndedPlay)
        {
            utils_entity_lifetime::Request_DestroyEntity(FixtureEntity);
            return;
        }

        _FixtureEntity = FixtureEntity;
    }

    UFUNCTION(BlueprintOverride)
    void EndPlay(EEndPlayReason EndPlayReason)
    {
        _HasEndedPlay = true;
        if (ck::IsValid(_FixtureEntity))
        { utils_entity_lifetime::Request_DestroyEntity(_FixtureEntity); }
    }

    // Call only after the collector has observed its baseline snapshot. The
    // collector verifies the resulting attempt-count increase rather than
    // treating this queued-pulse result as completion telemetry.
    UFUNCTION(BlueprintCallable)
    int32 RequestReplanPulse()
    {
        if (_HasEndedPlay) { return -1; }
        if (ck::Is_NOT_Valid(_FixtureEntity)) { return -2; }

        FCk_Handle_Goap_WorldState FallbackVsChainWorldState;
        FCk_Handle_Goap_WorldState FallbackOnlyWorldState;
        FCk_Handle_Goap_WorldState ActionSetWorldState;
        auto Result = ResolveWorldStateByPlannerName(
            n"AutoTest.Goap.FallbackVsChain", FallbackVsChainWorldState, -3, -4);
        if (Result != 0) { return Result; }
        Result = ResolveWorldStateByPlannerName(
            n"AutoTest.Goap.FallbackOnly", FallbackOnlyWorldState, -5, -6);
        if (Result != 0) { return Result; }
        Result = ResolveWorldStateByPlannerName(
            n"AutoTest.Goap.ActionSet.Set", ActionSetWorldState, -7, -8);
        if (Result != 0) { return Result; }

        auto MidStepKey = utils_gameplay_tag::ResolveGameplayTag(
            n"AutoTest.Goap.FallbackVsChain.WS.MidStep");
        auto NextValue = !utils_goap_world_state::Get_Value(
            FallbackVsChainWorldState, MidStepKey);
        utils_goap_world_state::Set_Value(FallbackVsChainWorldState,
            MidStepKey, NextValue);
        utils_goap_world_state::Set_Value(FallbackOnlyWorldState,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.FallbackOnly.WS.Unreachable"),
            NextValue);
        utils_goap_world_state::Set_Value(ActionSetWorldState,
            MidStepKey, NextValue);
        _QueuedReplanPulseSerial++;
        return _QueuedReplanPulseSerial;
    }

    private int32 ResolveWorldStateByPlannerName(FName InPlannerName,
        FCk_Handle_Goap_WorldState& OutWorldState, int32 InPlannerFailureCode,
        int32 InWorldStateFailureCode)
    {
        auto Planner = utils_goap_planner::Find_Planner(_FixtureEntity,
            utils_gameplay_tag::ResolveGameplayTag(InPlannerName));
        if (ck::Is_NOT_Valid(Planner)) { return InPlannerFailureCode; }

        auto WorldState = utils_goap_planner::Get_WorldStateSource(Planner);
        if (ck::Is_NOT_Valid(WorldState)) { return InWorldStateFailureCode; }

        OutWorldState = WorldState;
        return 0;
    }
}

class UCk_AutoTest_Goap_Planner_SquadRoster : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle_Goap_Planner _PlannedPlanner;
    private FCk_Handle_Goap_Planner _FallbackPlanner;
    private FCk_Handle_Goap_Planner _ThresholdPlanner;

    private FCk_Handle_Goap_WorldState _PlannedWorldState;
    private FCk_Handle_Goap_WorldState _FallbackWorldState;
    private FCk_Handle_Goap_WorldState _ThresholdWorldState;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Local = InHandle;
        utils_transform::Add(Local, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        Create_PlannedPlanner(Local);
        Create_FallbackPlanner(Local);
        Create_ThresholdPlanner(Local);

        Add_Step_WaitUntil("the planned, fallback, and threshold roster settles", n"Check_InitialRosterSettled");
        Add_Step("verify the initial roster states", n"Step_AssertInitialRoster");
        Add_Step("make every squad member replan", n"Step_MakeSquadReplan");
        Add_Step_WaitUntil("every squad member records its first replan", n"Check_FirstReplansSettled");
        Add_Step("verify the first replan states", n"Step_AssertFirstReplans");
        Add_Step("restore the squad's original world states", n"Step_RestoreSquadWorldStates");
        Add_Step_WaitUntil("every squad member records its second replan", n"Check_SecondReplansSettled");
        Add_Step("verify restored roster states", n"Step_AssertRestoredRoster");
        Run_Steps(InHandle);
    }

    private void Create_PlannedPlanner(FCk_Handle InOwner)
    {
        _PlannedWorldState = Create_FallbackVsChainWorldState(
            InOwner, n"AutoTest.Goap.FallbackVsChain.WS");
        _PlannedPlanner = Create_FallbackVsChainPlanner(
            InOwner, n"AutoTest.Goap.FallbackVsChain", _PlannedWorldState, 0.0f);
    }

    private void Create_FallbackPlanner(FCk_Handle InOwner)
    {
        _FallbackWorldState = utils_goap_world_state::Create(InOwner,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.FallbackOnly.WS"),
            FCk_Fragment_Goap_WorldState_ParamsData());
        utils_goap_world_state::Set_Value(_FallbackWorldState,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.FallbackOnly.WS.Unreachable"), false);
        utils_goap_world_state::Set_Value(_FallbackWorldState,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.FallbackOnly.WS.Goal"), false);

        auto Goal = TArray<FCk_GoapWS_Condition_Authored>();
        Goal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.FallbackOnly.WS.Goal"), true));
        auto Params = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.FallbackOnly"));
        Params.Set_Goal(Goal);
        Params.Set_WorldStateSource(_FallbackWorldState);
        _FallbackPlanner = utils_goap_planner::Create(InOwner,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.FallbackOnly"), Params);
        utils_goap_planner::AddAction(_FallbackPlanner,
            FCk_Fragment_Goap_ActionParamsData(UCk_AutoTestAction_Goap_FallbackOnly_Gated));
        utils_goap_planner::AddAction(_FallbackPlanner,
            FCk_Fragment_Goap_ActionParamsData(UCk_AutoTestAction_Goap_FallbackOnly_Fallback));
    }

    private void Create_ThresholdPlanner(FCk_Handle InOwner)
    {
        _ThresholdWorldState = Create_FallbackVsChainWorldState(
            InOwner, n"AutoTest.Goap.ActionSet.WS");
        _ThresholdPlanner = Create_FallbackVsChainPlanner(
            InOwner, n"AutoTest.Goap.ActionSet.Set", _ThresholdWorldState, 0.5f);
    }

    private FCk_Handle_Goap_WorldState Create_FallbackVsChainWorldState(
        FCk_Handle InOwner, FName InName)
    {
        auto WorldState = utils_goap_world_state::Create(InOwner,
            utils_gameplay_tag::ResolveGameplayTag(InName),
            FCk_Fragment_Goap_WorldState_ParamsData());
        utils_goap_world_state::Set_Value(WorldState,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.FallbackVsChain.WS.MidStep"), false);
        utils_goap_world_state::Set_Value(WorldState,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.FallbackVsChain.WS.Goal"), false);
        return WorldState;
    }

    private FCk_Handle_Goap_Planner Create_FallbackVsChainPlanner(
        FCk_Handle InOwner, FName InName, FCk_Handle_Goap_WorldState InWorldState, float32 InCostThreshold)
    {
        auto Goal = TArray<FCk_GoapWS_Condition_Authored>();
        Goal.Add(FCk_GoapWS_Condition_Authored(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.FallbackVsChain.WS.Goal"), true));
        auto Params = FCk_Fragment_Goap_PlannerParamsData(
            utils_gameplay_tag::ResolveGameplayTag(InName));
        Params.Set_Goal(Goal);
        Params.Set_WorldStateSource(InWorldState);
        Params.Set_CostThreshold(InCostThreshold);
        auto Planner = utils_goap_planner::Create(InOwner,
            utils_gameplay_tag::ResolveGameplayTag(InName), Params);
        utils_goap_planner::AddAction(Planner,
            FCk_Fragment_Goap_ActionParamsData(UCk_AutoTestAction_Goap_FallbackVsChain_Setup));
        utils_goap_planner::AddAction(Planner,
            FCk_Fragment_Goap_ActionParamsData(UCk_AutoTestAction_Goap_FallbackVsChain_Finalize));
        utils_goap_planner::AddAction(Planner,
            FCk_Fragment_Goap_ActionParamsData(UCk_AutoTestAction_Goap_FallbackVsChain_Fallback));
        return Planner;
    }

    UFUNCTION()
    private void Check_InitialRosterSettled(
        FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(HasInitialRosterStates());
    }

    UFUNCTION()
    private void Step_AssertInitialRoster(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(HasInitialRosterStates(),
            "the squad roster must expose planned, fallback, and cost-threshold terminal states");
        Assert_PlannedChain(_PlannedPlanner, "initial planned roster entry");
        Assert_Fallback(_FallbackPlanner, "initial fallback roster entry");
        Assert_True(utils_goap_planner::Get_PlanStatus(_ThresholdPlanner) == ECk_GoapPlanStatus::CostThresholdReached,
            "initial threshold roster entry must be CostThresholdReached");
    }

    UFUNCTION()
    private void Step_MakeSquadReplan(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_goap_world_state::Set_Value(_PlannedWorldState,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.FallbackVsChain.WS.MidStep"), true);
        utils_goap_world_state::Set_Value(_FallbackWorldState,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.FallbackOnly.WS.Unreachable"), true);
        utils_goap_world_state::Set_Value(_ThresholdWorldState,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.FallbackVsChain.WS.MidStep"), true);
    }

    UFUNCTION()
    private void Check_FirstReplansSettled(
        FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(HasFirstReplanStates());
    }

    UFUNCTION()
    private void Step_AssertFirstReplans(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(HasFirstReplanStates(),
            "the first squad world-state flip must produce a real replan for every roster entry");
        Assert_DirectFinalize(_PlannedPlanner, "first planned replan");
        Assert_GatedPlan(_FallbackPlanner, "first fallback replan");
        Assert_True(utils_goap_planner::Get_PlanStatus(_ThresholdPlanner) == ECk_GoapPlanStatus::CostThresholdReached,
            "first threshold replan must remain CostThresholdReached");
    }

    UFUNCTION()
    private void Step_RestoreSquadWorldStates(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_goap_world_state::Set_Value(_PlannedWorldState,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.FallbackVsChain.WS.MidStep"), false);
        utils_goap_world_state::Set_Value(_FallbackWorldState,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.FallbackOnly.WS.Unreachable"), false);
        utils_goap_world_state::Set_Value(_ThresholdWorldState,
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Goap.FallbackVsChain.WS.MidStep"), false);
    }

    UFUNCTION()
    private void Check_SecondReplansSettled(
        FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(HasInitialRosterStates()
            && utils_goap_planner::Get_PlanAttemptCount(_PlannedPlanner) >= 3
            && utils_goap_planner::Get_PlanAttemptCount(_FallbackPlanner) >= 3
            && utils_goap_planner::Get_PlanAttemptCount(_ThresholdPlanner) >= 3);
    }

    UFUNCTION()
    private void Step_AssertRestoredRoster(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(HasInitialRosterStates(),
            "restoring squad world state must restore the original terminal states");
        Assert_True(utils_goap_planner::Get_PlanAttemptCount(_PlannedPlanner) >= 3,
            "planned roster entry must include initial planning plus two real replans");
        Assert_True(utils_goap_planner::Get_PlanAttemptCount(_FallbackPlanner) >= 3,
            "fallback roster entry must include initial planning plus two real replans");
        Assert_True(utils_goap_planner::Get_PlanAttemptCount(_ThresholdPlanner) >= 3,
            "threshold roster entry must include initial planning plus two real replans");
    }

    private bool HasInitialRosterStates()
    {
        return utils_goap_planner::Get_PlanStatus(_PlannedPlanner) == ECk_GoapPlanStatus::PlanFound
            && utils_goap_planner::Get_PlanStatus(_FallbackPlanner) == ECk_GoapPlanStatus::PlanFound
            && utils_goap_planner::Get_PlanStatus(_ThresholdPlanner) == ECk_GoapPlanStatus::CostThresholdReached
            && utils_goap_planner::Get_PlanAttemptCount(_PlannedPlanner) >= 1
            && utils_goap_planner::Get_PlanAttemptCount(_FallbackPlanner) >= 1
            && utils_goap_planner::Get_PlanAttemptCount(_ThresholdPlanner) >= 1;
    }

    private bool HasFirstReplanStates()
    {
        return utils_goap_planner::Get_PlanStatus(_PlannedPlanner) == ECk_GoapPlanStatus::PlanFound
            && utils_goap_planner::Get_PlanStatus(_FallbackPlanner) == ECk_GoapPlanStatus::PlanFound
            && utils_goap_planner::Get_PlanStatus(_ThresholdPlanner) == ECk_GoapPlanStatus::CostThresholdReached
            && utils_goap_planner::Get_PlanAttemptCount(_PlannedPlanner) >= 2
            && utils_goap_planner::Get_PlanAttemptCount(_FallbackPlanner) >= 2
            && utils_goap_planner::Get_PlanAttemptCount(_ThresholdPlanner) >= 2;
    }

    private void Assert_PlannedChain(FCk_Handle_Goap_Planner InPlanner, const FString& InLabel)
    {
        auto Plan = utils_goap_planner::Get_PlanClasses(InPlanner);
        Assert_True(Plan.Num() == 2, f"{InLabel} must use the two-step planned chain");
        if (Plan.Num() != 2) { return; }
        Assert_True(Plan[0] == UCk_AutoTestAction_Goap_FallbackVsChain_Setup,
            f"{InLabel} must begin with Setup");
        Assert_True(Plan[1] == UCk_AutoTestAction_Goap_FallbackVsChain_Finalize,
            f"{InLabel} must finish with Finalize");
    }

    private void Assert_DirectFinalize(FCk_Handle_Goap_Planner InPlanner, const FString& InLabel)
    {
        auto Plan = utils_goap_planner::Get_PlanClasses(InPlanner);
        Assert_True(Plan.Num() == 1, f"{InLabel} must collapse to a direct Finalize plan");
        if (Plan.Num() != 1) { return; }
        Assert_True(Plan[0] == UCk_AutoTestAction_Goap_FallbackVsChain_Finalize,
            f"{InLabel} must select Finalize when MidStep is already true");
    }

    private void Assert_Fallback(FCk_Handle_Goap_Planner InPlanner, const FString& InLabel)
    {
        auto Plan = utils_goap_planner::Get_PlanClasses(InPlanner);
        Assert_True(Plan.Num() == 1, f"{InLabel} must expose exactly one fallback action");
        if (Plan.Num() != 1) { return; }
        Assert_True(Plan[0] == UCk_AutoTestAction_Goap_FallbackOnly_Fallback,
            f"{InLabel} must select the unconditional fallback");
    }

    private void Assert_GatedPlan(FCk_Handle_Goap_Planner InPlanner, const FString& InLabel)
    {
        auto Plan = utils_goap_planner::Get_PlanClasses(InPlanner);
        Assert_True(Plan.Num() == 1, f"{InLabel} must expose exactly one gated action");
        if (Plan.Num() != 1) { return; }
        Assert_True(Plan[0] == UCk_AutoTestAction_Goap_FallbackOnly_Gated,
            f"{InLabel} must select Gated when Unreachable is supplied by world state");
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by auto-generator when present)
//============================================================================

class ACk_AutoTest_Goap_Planner_SquadRoster_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Goap_Planner_SquadRoster;
    default _TimeoutSeconds = 20.0f;
}
