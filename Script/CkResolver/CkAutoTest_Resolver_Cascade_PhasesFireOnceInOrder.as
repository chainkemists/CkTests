// Language=angelscript

//============================================================================
// CK RESOLVER - AUTOMATION TEST: PHASES FIRE EXACTLY ONCE, IN DECLARED ORDER
//============================================================================
//
// Guards the cost of making the cascade drain in one tick.
//
// Calculate is pump-eligible, so within a single frame the scheduler re-runs it
// on every pump pass while anything is dirty. The invariant that keeps that safe
// is that Calculate CONSUMES its readiness marker
// (FTag_ResolverDataBundle_NeedsCalculate) before re-arming StartNewPhase. If
// that consume were dropped, a later pump pass in the same frame would
// re-Calculate a phase that already finished - double-broadcasting PhaseComplete
// and double-applying whatever a listener does in response (in BusterBlock: HP
// deducted twice from one hit).
//
// A pure latency test would not catch that: the cascade would still finish in
// one tick, just wrongly. So this test asserts DISPATCH COUNTS and ORDER rather
// than timing:
//   - PhaseStart fires once per declared phase, in declared order
//   - PhaseComplete likewise
//   - AllPhasesComplete fires exactly once
//============================================================================

class UCk_AutoTest_Resolver_Cascade_PhasesFireOnceInOrder : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle_ResolverSource _Source;
    private FCk_Handle_ResolverTarget _Target;
    private bool                      _BundleBound = false;

    private TArray<FGameplayTag> _PhaseStarts;
    private TArray<FGameplayTag> _PhaseCompletes;
    private int32                _AllPhasesCompleteCount = 0;
    private int32                _NewBundleCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        Add_Step(          "arrange source + target",        n"Step_Arrange");
        Add_Step(          "initiate a 3-phase resolution",  n"Step_Initiate");
        Add_Step_WaitUntil("the cascade reports all phases", n"Check_Complete");
        Add_Step(          "assert dispatch counts + order", n"Step_AssertDispatch");
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
    private void Step_AssertDispatch(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto _CkPerfScope = ck::ScopedStat();

        Assert_Equals_Int(_PhaseStarts.Num(), 3,
            f"PhaseStart fires once per declared phase - got {_PhaseStarts.Num()} for 3 phases."
            + " More than 3 means a phase was re-entered inside the pump.");

        Assert_Equals_Int(_PhaseCompletes.Num(), 3,
            f"PhaseComplete fires once per declared phase - got {_PhaseCompletes.Num()} for 3 phases."
            + " More than 3 means Calculate ran twice for one phase, which is what consuming"
            + " FTag_ResolverDataBundle_NeedsCalculate prevents.");

        Assert_Equals_Int(_AllPhasesCompleteCount, 1,
            f"AllPhasesComplete fires exactly once - got {_AllPhasesCompleteCount}");

        // Reported rather than silently absorbed by the _BundleBound guard below:
        // one resolution request should surface one bundle to its own delegate.
        Assert_Equals_Int(_NewBundleCount, 1,
            f"One resolution request surfaces its bundle once to the requesting delegate"
            + f" - got {_NewBundleCount}");

        Assert_Ordered(_PhaseStarts,    "PhaseStart");
        Assert_Ordered(_PhaseCompletes, "PhaseComplete");
    }

    // Declared order is One -> Two -> Three. Collapsing the cascade into a single
    // frame must not reorder it.
    private void Assert_Ordered(const TArray<FGameplayTag>& InObserved, const FString& InSignalName)
    {
        auto _CkPerfScope = ck::ScopedStat();
        if (InObserved.Num() != 3)
        { return; }

        Assert_True(InObserved[0] == autotest_resolver_cascade::Phase_One(),
            f"{InSignalName}[0] is phase One - got {InObserved[0].ToString()}");
        Assert_True(InObserved[1] == autotest_resolver_cascade::Phase_Two(),
            f"{InSignalName}[1] is phase Two - got {InObserved[1].ToString()}");
        Assert_True(InObserved[2] == autotest_resolver_cascade::Phase_Three(),
            f"{InSignalName}[2] is phase Three - got {InObserved[2].ToString()}");
    }

    UFUNCTION()
    private void OnNewDataBundle(
        FCk_Handle_ResolverSource InSource,
        FCk_Handle InCauser,
        FCk_Handle_ResolverDataBundle InDataBundle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _NewBundleCount += 1;

        // The source processor broadcasts OnNewResolverDataBundle on both the
        // request handle and the source entity. Binding the phase delegates twice
        // would double every count below and read as a framework double-dispatch,
        // so guard our own subscription rather than measuring our own mistake
        // the counter above still reports it, so nothing is swallowed.
        if (_BundleBound)
        { return; }
        _BundleBound = true;

        utils_resolver_data_bundle::BindTo_OnPhaseStart(
            InDataBundle, FCk_Delegate_ResolverDataBundle_OnPhaseStart(this, n"OnPhaseStart"));
        utils_resolver_data_bundle::BindTo_OnPhaseComplete(
            InDataBundle, FCk_Delegate_ResolverDataBundle_OnPhaseComplete(this, n"OnPhaseComplete"));
        utils_resolver_data_bundle::BindTo_OnAllPhasesComplete(
            InDataBundle, FCk_Delegate_ResolverDataBundle_OnAllPhasesComplete(this, n"OnAllPhasesComplete"));
    }

    UFUNCTION()
    private void OnPhaseStart(FCk_Handle_ResolverDataBundle InDataBundle, FGameplayTag InPhase)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _PhaseStarts.Add(InPhase);
    }

    UFUNCTION()
    private void OnPhaseComplete(
        FCk_Handle_ResolverDataBundle InDataBundle,
        FGameplayTag InPhase,
        FCk_Payload_ResolverDataBundle_Resolved InPayload)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _PhaseCompletes.Add(InPhase);
    }

    UFUNCTION()
    private void OnAllPhasesComplete(
        FCk_Handle_ResolverDataBundle InDataBundle,
        FCk_Payload_ResolverDataBundle_Resolved InPayload)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _AllPhasesCompleteCount += 1;
    }
}
