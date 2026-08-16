// Language=angelscript

//============================================================================
// CK RESOLVER — AUTOMATION TEST: CONCURRENT BUNDLES STAY INDEPENDENT
//============================================================================
//
// Three resolutions initiated from ONE source in the SAME tick must resolve to
// three independent values, and all of them must still drain inside the tick
// budget.
//
// This is the realistic load: combat resolves several hits at once (a swing that
// clips two NPCs, a shotgun spread, an AoE), and every one of those bundles now
// walks its phases inside the same frame's pump passes rather than being spread
// across frames. Bundles that used to be separated in time are now interleaved,
// so any shared-state assumption in the phase machinery — a value accumulating
// on the wrong bundle, one bundle's pending operations resolving into another —
// surfaces here and nowhere else.
//
// Seeds are distinct and non-overlapping so a cross-talk failure is legible in
// the numbers rather than showing up as a plausible-looking total.
//============================================================================

namespace constants_autotest_resolver_concurrent
{
    const int32   k_BundleCount = 3;
    const float32 k_SeedA = 100.0f;
    const float32 k_SeedB = 200.0f;
    const float32 k_SeedC = 400.0f;
}

class UCk_AutoTest_Resolver_Cascade_ConcurrentBundlesStayIndependent : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle_ResolverSource _Source;
    private FCk_Handle_ResolverTarget _Target;

    private int64           _TickAtInitiate = -1;
    private int64           _TickAtLastComplete = -1;
    private TArray<float32> _FinalValues;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        Add_Step(          "arrange source + target",              n"Step_Arrange");
        Add_Step(          "initiate 3 resolutions in one tick",   n"Step_InitiateAll");
        Add_Step_WaitUntil("all 3 cascades report completion",     n"Check_AllComplete");
        Add_Step(          "assert independence + latency",        n"Step_Assert");
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
    private void Step_InitiateAll(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto _CkPerfScope = ck::ScopedStat();

        _TickAtInitiate = utils_time::Get_FrameCounter();

        Initiate(InHandle, constants_autotest_resolver_concurrent::k_SeedA);
        Initiate(InHandle, constants_autotest_resolver_concurrent::k_SeedB);
        Initiate(InHandle, constants_autotest_resolver_concurrent::k_SeedC);
    }

    private void Initiate(FCk_Handle InCauser, float32 InSeed)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto Request = utils_resolver_source::Make_InitiateNewResolution(
            autotest_resolver_cascade::BundleName(),
            _Target,
            InCauser,
            FCk_ResolverDataBundle_MetadataOperation_Conditional(),
            autotest_resolver_cascade::Make_Modifier(
                InSeed,
                ECk_ResolverDataBundle_ModifierComponent::BaseValue,
                ECk_ArithmeticOperations_Basic::Add));

        utils_resolver_source::Request_InitiateNewResolution(
            _Source, Request,
            FCk_Delegate_ResolverSource_OnNewResolverDataBundle(this, n"OnNewDataBundle"));
    }

    UFUNCTION()
    private void Check_AllComplete(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Res = OutResult;
        Res.Set(_FinalValues.Num() >= constants_autotest_resolver_concurrent::k_BundleCount);
    }

    UFUNCTION()
    private void Step_Assert(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto _CkPerfScope = ck::ScopedStat();

        Assert_Equals_Int(_FinalValues.Num(), constants_autotest_resolver_concurrent::k_BundleCount,
            f"Three concurrent resolutions produce exactly three completions — got {_FinalValues.Num()}");

        Assert_ContainsOnce(constants_autotest_resolver_concurrent::k_SeedA);
        Assert_ContainsOnce(constants_autotest_resolver_concurrent::k_SeedB);
        Assert_ContainsOnce(constants_autotest_resolver_concurrent::k_SeedC);

        const auto LatencyTicks = int32(_TickAtLastComplete - _TickAtInitiate);
        const auto Budget = autotest_resolver_cascade::k_MaxCascadeTicks;

        Assert_True(LatencyTicks <= Budget,
            f"Three concurrent 3-phase cascades all drain within {Budget} ECS tick(s)"
            + f" — measured {LatencyTicks}. Concurrency must not serialise the pump.");
    }

    // Each seed must survive to exactly one completion. Appearing twice means one
    // bundle's value leaked into another; appearing zero times means a bundle
    // resolved to something it was never seeded with.
    private void Assert_ContainsOnce(float32 InExpected)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto MatchCount = 0;
        for (auto Value : _FinalValues)
        {
            if (Math::Abs(Value - InExpected) <= 0.01f)
            { MatchCount += 1; }
        }

        Assert_Equals_Int(MatchCount, 1,
            f"Exactly one bundle resolves to its own seed {InExpected} — matched {MatchCount}."
            + " A count other than 1 means concurrent bundles shared state.");
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
        _FinalValues.Add(InPayload.Get_FinalValue());
        _TickAtLastComplete = utils_time::Get_FrameCounter();
    }
}
