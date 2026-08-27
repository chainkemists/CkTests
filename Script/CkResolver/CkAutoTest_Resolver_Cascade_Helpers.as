// Language=angelscript

//============================================================================
// CK RESOLVER — PHASE-CASCADE AUTOTEST SCAFFOLDING
//============================================================================
//
// Shared arrange for the Resolver_Cascade_* tests, which are the first tests in
// this suite to drive an ACTUAL resolution. Every other CkResolver test asserts
// composition only (Add / Create / Has returns a valid handle), so until these
// landed the module had no coverage of the thing it exists to do: walk a data
// bundle through its declared phases and report a value.
//
// That gap was not theoretical. FProcessor_ResolverDataBundle_Calculate shipped
// without a `MarkedDirtyBy`, which silently excluded it from the scheduler's
// _PumpOrder and re-gated the entire phase cascade to ONE PHASE PER FRAME while
// every other processor in the chain drained inside a single frame's pump. A
// 3-wave x 3-phase damage resolution measured 5 ticks end to end. Every
// composition test stayed green throughout, because none of them advanced a
// phase.
//
// The invariants these tests pin are therefore deliberately about BEHAVIOUR
// UNDER THE PUMP, not about return values:
//   - the cascade drains inside one tick                (DrainsInOneTick)
//   - each phase fires exactly once, in declared order  (PhasesFireOnceInOrder)
//   - operations stay bound to their phase              (AccumulatesAcrossPhases)
//   - concurrent bundles do not smear into each other   (ConcurrentBundlesStayIndependent)
//
// The last three matter specifically BECAUSE the cascade now collapses: running
// nine phase-advances inside one frame is exactly the condition under which a
// double-dispatch or a cross-bundle leak would appear, and none of it would be
// visible as a wrong final handle.
//============================================================================

namespace ck
{
    asset Asset_AutoTest_Resolver_Cascade_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"AutoTest.Resolver.Cascade.Bundle");
        GameplayTags.Add(n"AutoTest.Resolver.Cascade.Phase.One");
        GameplayTags.Add(n"AutoTest.Resolver.Cascade.Phase.Two");
        GameplayTags.Add(n"AutoTest.Resolver.Cascade.Phase.Three");
    }
}

namespace autotest_resolver_cascade
{
    // Ticks allowed between the InitiateNewResolution request and the
    // AllPhasesComplete broadcast.
    //
    // MEASURED 0 on a 3-phase bundle: every processor in the chain
    // (ResolverSource_HandleRequests -> ResolverDataBundle_StartNewPhase ->
    // HandleRequests -> ResolveOperations -> Calculate) is pump-eligible, and the
    // scheduler re-runs pump-eligible processors in execution order until nothing
    // is dirty, so one pump pass advances one full phase.
    //
    // Budgeted at 1 rather than 0 as slack for a benign one-tick scheduling nudge.
    // The regression this guards costs one tick PER PHASE, so a single tick of
    // headroom does not blunt it.
    const int32 k_MaxCascadeTicks = 1;

    // Generous on purpose: a regressed pipeline must still be allowed to FINISH,
    // so the tick assertion reports a real measured number rather than degrading
    // into "the cascade never completed".
    const float32 k_SettleSeconds = 1.0f;

    // Seed pushed into BaseValue via the resolution request's initial modifier.
    const float32 k_SeedBaseValue = 100.0f;

    // Added to BonusValue at the start of phase Two.
    const float32 k_PhaseTwoBonus = 25.0f;

    // Applied to TotalMultiplier at the start of phase Three.
    const float32 k_PhaseThreeMultiplier = 1.5f;

    FGameplayTag BundleName() { return utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Resolver.Cascade.Bundle"); }
    FGameplayTag Phase_One()  { return utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Resolver.Cascade.Phase.One"); }
    FGameplayTag Phase_Two()  { return utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Resolver.Cascade.Phase.Two"); }
    FGameplayTag Phase_Three(){ return utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Resolver.Cascade.Phase.Three"); }

    // Three phases so ordering and per-phase binding are observable — two would
    // let a swapped pair still look sorted, and one would not exercise a cascade
    // at all.
    TArray<FCk_Fragment_ResolverDataBundle_PhaseInfo> Make_ThreePhases()
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Phases = TArray<FCk_Fragment_ResolverDataBundle_PhaseInfo>();
        Phases.Add(FCk_Fragment_ResolverDataBundle_PhaseInfo(
            Phase_One(), ECk_ResolverDataBundle_AllowedOperationsInPhase::ModifierAndMetadata));
        Phases.Add(FCk_Fragment_ResolverDataBundle_PhaseInfo(
            Phase_Two(), ECk_ResolverDataBundle_AllowedOperationsInPhase::ModifierAndMetadata));
        Phases.Add(FCk_Fragment_ResolverDataBundle_PhaseInfo(
            Phase_Three(), ECk_ResolverDataBundle_AllowedOperationsInPhase::ModifierAndMetadata));
        return Phases;
    }

    // A conditional modifier with empty tag requirements, i.e. always applies.
    FCk_ResolverDataBundle_ModifierOperation_Conditional Make_Modifier(
        float32 InValue,
        ECk_ResolverDataBundle_ModifierComponent InComponent,
        ECk_ArithmeticOperations_Basic InOperation)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Modifier = FCk_ResolverDataBundle_ModifierOperation(InValue);
        Modifier.Set_ResolverComponent(InComponent);
        Modifier.Set_ModifierOperation(InOperation);
        return FCk_ResolverDataBundle_ModifierOperation_Conditional(FGameplayTagRequirements(), Modifier);
    }
}
