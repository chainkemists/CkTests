// Language=angelscript

//============================================================================
// CK RESOLVER — AUTOMATION TEST: PHASE CASCADE DRAINS IN ONE TICK
//============================================================================
//
// The regression guard. A 3-phase resolution must reach AllPhasesComplete
// within k_MaxCascadeTicks of the InitiateNewResolution request.
//
// This is the framework-level twin of BusterBlock's
// Bb_AutoTest_CombatReceiver_DamageLatency. It belongs HERE because the defect
// it guards lives in CkResolver, not in any consuming project: a processor in
// the chain losing its `MarkedDirtyBy` drops it out of the scheduler's
// _PumpOrder, and since Calculate is also what advances the phase
// (DoTryStartNewPhase), the whole cascade silently degrades to one phase per
// frame. Nothing errors, nothing warns, and every correctness assertion in this
// module still passes — only a tick count catches it.
//
// The failure message reports the MEASURED delta so a red run is the
// measurement, not just a verdict.
//============================================================================

class UCk_AutoTest_Resolver_Cascade_DrainsInOneTick : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle_ResolverSource _Source;
    private FCk_Handle_ResolverTarget _Target;

    private int64 _TickAtInitiate         = -1;
    private int64 _TickAtAllPhasesComplete = -1;
    private int32 _AllPhasesCompleteCount  = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        Add_Step(          "arrange source + target",          n"Step_Arrange");
        Add_Step(          "initiate a 3-phase resolution",    n"Step_Initiate");
        Add_Step_WaitUntil("the cascade reports all phases",   n"Check_Complete");
        Add_Step(          "assert the cascade drained in-tick", n"Step_AssertLatency");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto SourceEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        _Source = utils_resolver_source::Add(
            SourceEntity,
            FCk_Fragment_ResolverSource_ParamsData(autotest_resolver_cascade::Make_ThreePhases()));

        auto TargetEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        _Target = utils_resolver_target::Add(TargetEntity, FCk_Fragment_ResolverTarget_ParamsData());
    }

    UFUNCTION()
    private void Step_Initiate(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto Request = utils_resolver_source::Make_InitiateNewResolution(
            autotest_resolver_cascade::BundleName(),
            _Target,
            InHandle,
            FCk_ResolverDataBundle_MetadataOperation_Conditional(),
            autotest_resolver_cascade::Make_Modifier(
                autotest_resolver_cascade::k_SeedBaseValue,
                ECk_ResolverDataBundle_ModifierComponent::BaseValue,
                ECk_ArithmeticOperations_Basic::Add));

        // Stamp the tick immediately before the request so nothing between the
        // two reads as pipeline latency.
        _TickAtInitiate = utils_time::Get_FrameCounter();

        utils_resolver_source::Request_InitiateNewResolution(
            _Source, Request,
            FCk_Delegate_ResolverSource_OnNewResolverDataBundle(this, n"OnNewDataBundle"));
    }

    UFUNCTION()
    private void Check_Complete(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Res = OutResult;
        Res.Set(_AllPhasesCompleteCount > 0);
    }

    UFUNCTION()
    private void Step_AssertLatency(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto _CkPerfScope = ck::ScopedStat();

        const auto LatencyTicks = int32(_TickAtAllPhasesComplete - _TickAtInitiate);
        const auto Budget = autotest_resolver_cascade::k_MaxCascadeTicks;

        Assert_True(LatencyTicks <= Budget,
            f"A 3-phase resolution completes within {Budget} ECS tick(s) — measured {LatencyTicks}."
            + " A larger number means a processor in the ResolverSource -> ResolverDataBundle chain"
            + " stopped being pump-eligible; check that each one still declares MarkedDirtyBy,"
            + " Calculate included.");
    }

    UFUNCTION()
    private void OnNewDataBundle(
        FCk_Handle_ResolverSource InSource,
        FCk_Handle InCauser,
        FCk_Handle_ResolverDataBundle InDataBundle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        utils_resolver_data_bundle::BindTo_OnAllPhasesComplete(
            InDataBundle, FCk_Delegate_ResolverDataBundle_OnAllPhasesComplete(this, n"OnAllPhasesComplete"));
    }

    UFUNCTION()
    private void OnAllPhasesComplete(
        FCk_Handle_ResolverDataBundle InDataBundle,
        FCk_Payload_ResolverDataBundle_Resolved InPayload)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _AllPhasesCompleteCount += 1;
        if (_TickAtAllPhasesComplete < 0)
        { _TickAtAllPhasesComplete = utils_time::Get_FrameCounter(); }
    }
}
