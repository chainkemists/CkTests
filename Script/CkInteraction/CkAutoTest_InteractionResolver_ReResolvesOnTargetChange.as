// Language=angelscript

//============================================================================
// CK INTERACTION - AUTOMATION TEST: RESOLVER RE-RESOLVES ON TARGET CHANGE
//============================================================================
//
// The resolver's cached best-target set must be LIVE while an intent is held:
// FTag_InteractionResolver_ResolveDirty is stamped by any handler that really
// mutates _AvailableTargets (CkInteractionResolver_Processor.cpp:157 add,
// :180 remove, :216-217 remove-all-by-channel), never by their no-op early
// returns (:150-154, :173-177), and a target with a live interaction from this
// resolver is pinned ahead of the distance sort + MaxConcurrentInteractions
// truncation (CkInteractionResolver_Utils.cpp:271-294).
//
// Four claims, in an ORDER that is load-bearing:
//   a) Intent FIRST, settle, THEN add a target -> OnBestTargetsChanged fires.
//      A test that adds targets BEFORE Request_StartIntent false-greens on the
//      old code: the intent edge stamped the re-resolve tag anyway
//      (CkInteractionResolver_Processor.cpp:87), so the resolve that noticed
//      the target would have been the intent's, not the add's. The settle
//      between the intent draining and the add is what guarantees the intent
//      edge's stamp is already SPENT when the add lands.
//   c) A no-op add (already present) and a remove of a non-member broadcast
//      NOTHING. (Runs before A is disturbed, while phase a's real broadcast is
//      the fresh positive proof that the signal machinery is live - wait-rule
//      1.) NOTE the honest limit: with the set unchanged, even a spurious
//      dirty stamp would resolve to an identical set and stay silent
//      (CkInteractionResolver_Processor.cpp:293-325 broadcasts only on
//      change), so what this pins is the consumer-visible contract - no
//      signal spam on no-op churn - not the internal stamp placement.
//   d) THE PIN: with a live Timed interaction on far A, a NEARER same-channel
//      B appears mid-hold -> A stays the picked target, no broadcast, and A's
//      interaction is not cancelled. This is the test that stops the R1
//      displacement regression (re-resolve landing without the pin) from
//      being re-litigated. The source composes NO InteractSource on purpose:
//      the pin is keyed on UCk_Utils_Interaction_UE::TryGet (the interaction
//      record), deliberately NOT on Get_CanInteractWith's AlreadyExists,
//      which is decided against the InteractSource CAST of the source
//      (CkInteractTarget_Utils.cpp:217-238) and is unreachable here.
//   b) Remove the currently-picked A mid-hold -> A arrives in RemovedTargets
//      and the set becomes the next-best B. Runs LAST so it doubles as the
//      guard that fails the file on fully-old code even though phase d is
//      vacuous there (no re-resolve on add = no displacement to pin against).
//
// On the PRE-FIX code this file goes red at phase a ("resolver notices A
// while the intent is held" never becomes true - AddInteractTarget stamped
// nothing), and phase b's wait would fail the same way. On the halfway state
// (dirty stamp without the pin - the R1 regression) phase d fails: best
// flips to [B] and the eviction broadcast bumps the count.
//
// API provenance (every call verified against a green usage or landed source):
//   - child entity + Request_OverrideToSelf + utils_transform::Add:
//     CkAutoTest_Compass_RangeCull.as:32-35,51-54 (OverrideToSelf makes each
//     entity its own context root so DoSortByDistance reads ITS transform
//     CkInteractionResolver_Utils.cpp:308,321-322 resolves locations via
//     Get_ContextOwner).
//   - resolver mapping/params/Add/BindTo_OnBestTargetsChanged/Request_*:
//     CkInteractionGym_Resolver.as:37-59,84-124; Get_BestInteractTargets
//     :165. Delegate signature :139.
//   - utils_interact_target::Add + Set_CompletionPolicy/Set_InteractionDuration
//     + Request_StartInteraction + BindTo_OnInteractionFinished:
//     CkAutoTest_Interaction_Timed.as:41-59. A source with no InteractSource
//     may start an interaction: CkInteractTarget_Processor.cpp:139-144 casts
//     and guards.
//   - utils_interaction::TryGet(owner, source, target, channel):
//     Script/Generated/utils_interaction.as:14-18 (record lives on the
//     target: CkInteraction_Utils.cpp:124-137).
//   - utils_interact_target::Get_InteractionCompletionPolicy: pre-existing pure getter
//     (CkInteractTarget_Utils.h:176-182). Called as the direct static so this
//     file does not depend on the generated-wrapper regen having run before
//     the test boot's AS compile (stale-wrapper boots are a known trap);
//     direct-static precedent: CkAutoTest_Base.as:167.
//   - completion delegate signature (FCk_Handle, ECk_Request_OperationResult):
//     CkAutoTest_Crowd_Stop_CancelsQueuedNavQuery.as:74-79.
//   - gym tag helpers: CkInteractionGym_Shared.as:134-150.
//
// Every entity here is a child of the runner entity, so the harness teardown
// cascade covers cleanup - no Track_ForCleanup needed.
//============================================================================

class UCk_AutoTest_InteractionResolver_ReResolvesOnTargetChange : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    // Isolated band in the shared PIE world. The resolver only sees targets
    // explicitly added to it, so this is hygiene, not a correctness need.
    private FVector k_Base = FVector(0.0, 87000.0, 0.0);

    private FCk_Handle _SelfHandle;
    private FCk_Handle _ResolverOwner;
    private FCk_Handle_InteractionResolver _Resolver;
    private FCk_Handle_InteractTarget _TargetA;   // far  (+300uu)
    private FCk_Handle_InteractTarget _TargetB;   // near (+100uu) - the would-be evictor
    private FCk_Handle_InteractTarget _TargetD;   // valid but NEVER added - the no-op remove subject

    private bool _IntentStartCompleted = false;
    private bool _AInteractionFinished = false;

    private int32 _BroadcastCount = 0;
    private TArray<FCk_Handle_InteractTarget> _LastNewTargets;
    private TArray<FCk_Handle_InteractTarget> _LastRemovedTargets;

    private int32 _CountAtAddA = 0;
    private int32 _CountAtChurn = 0;
    private int32 _CountAtAddB = 0;
    private int32 _CountAtRemoveA = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _SelfHandle = InHandle;

        // Resolver owner: transform for the distance sort, NO InteractSource
        // (see header - the pin must work for exactly this consumer class).
        _ResolverOwner = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _ResolverOwner.Request_OverrideToSelf();
        utils_transform::Add(_ResolverOwner, FTransform(FRotator::ZeroRotator, k_Base),
            ECk_Replication::DoesNotReplicate);

        auto Channels = TArray<FGameplayTag>();
        Channels.Add(interaction_gym_helpers::DefaultChannel());

        auto Mapping = FCk_InteractionResolver_IntentChannelMapping(
            interaction_gym_helpers::UseIntent(), Channels);
        Mapping.Set_DistanceSorting(ECk_InteractionResolver_DistanceSorting::Enabled);
        Mapping.Set_MaxConcurrentInteractions(1);

        auto Mappings = TArray<FCk_InteractionResolver_IntentChannelMapping>();
        Mappings.Add(Mapping);

        _Resolver = utils_interaction_resolver::Add(_ResolverOwner,
            FCk_InteractionResolver_ParamsData(Mappings), ECk_Replication::DoesNotReplicate);

        utils_interaction_resolver::BindTo_OnBestTargetsChanged(_Resolver,
            FCk_Delegate_InteractionResolver_OnBestTargetsChanged(this, n"OnBestTargetsChanged"));

        _TargetA = DoSpawnTarget(FVector(300.0, 0.0, 0.0));
        _TargetB = DoSpawnTarget(FVector(100.0, 0.0, 0.0));
        _TargetD = DoSpawnTarget(FVector(500.0, 0.0, 0.0));

        utils_interact_target::BindTo_OnInteractionFinished(_TargetA,
            FCk_Delegate_InteractTarget_OnInteractionFinished(this, n"OnTargetAInteractionFinished"));

        // ---- phase a: intent BEFORE any target (the ordering is the test) ----
        Add_Step(          "start the intent with ZERO targets",              n"Step_StartIntent");
        Add_Step_WaitUntil("StartIntent request drains",                      n"Check_IntentStarted");
        // No public observable exists for "the resolve pass consumed the
        // dirty tag", so this settle is a genuine fixed-frame wait: it
        // guarantees the intent edge's stamp is spent before the add lands,
        // which is precisely what makes phase a discriminating.
        Add_Step_WaitFrames("spend the intent-edge ResolveDirty stamp",       5);
        Add_Step(          "add far target A mid-hold",                       n"Step_AddA");
        Add_Step_WaitUntil("resolver notices A while the intent is held",     n"Check_BestIsA");
        Add_Step(          "assert A's arrival broadcast",                    n"Step_AssertPhaseA");
        // ---- phase c: no-op churn stays silent ----
        Add_Step(          "no-op churn: re-add A, remove non-member D",      n"Step_NoOpChurn");
        Add_Step_WaitSeconds("window for a broadcast that must not come", 0.167f);
        Add_Step(          "assert no-op churn stayed silent",                n"Step_AssertNoOpSilence");
        // ---- phase d: the pin ----
        Add_Step(          "start a Timed interaction on A (source = owner)", n"Step_StartInteractionOnA");
        Add_Step_WaitUntil("interaction on A is live",                        n"Check_InteractionLiveOnA");
        Add_Step(          "add NEARER same-channel B mid-interaction",       n"Step_AddNearerB");
        Add_Step_WaitSeconds("window for the eviction that must not happen", 0.167f);
        Add_Step(          "assert the pin: A still picked, interaction alive", n"Step_AssertPin");
        // ---- phase b: remove the picked target mid-hold ----
        Add_Step(          "remove the picked target A mid-hold",             n"Step_RemoveA");
        Add_Step_WaitUntil("resolver falls back to next-best B",              n"Check_BestIsB");
        Add_Step(          "assert A's removal broadcast",                    n"Step_AssertRemoval");

        Run_Steps(InHandle);
    }

    private FCk_Handle_InteractTarget DoSpawnTarget(FVector InOffset)
    {
        auto Owner = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        Owner.Request_OverrideToSelf();
        utils_transform::Add(Owner, FTransform(FRotator::ZeroRotator, k_Base + InOffset),
            ECk_Replication::DoesNotReplicate);

        auto TargetParams = FCk_Fragment_InteractTarget_ParamsData(
            interaction_gym_helpers::DefaultChannel());
        TargetParams.Set_CompletionPolicy(ECk_Interaction_CompletionPolicy::Timed);
        // Long enough that the pin phase runs against a provably in-progress
        // interaction; the test never waits for completion.
        TargetParams.Set_InteractionDuration(FCk_Time(30.0f));
        return utils_interact_target::Add(Owner, TargetParams, ECk_Replication::DoesNotReplicate);
    }

    private bool DoContains(TArray<FCk_Handle_InteractTarget> InTargets, FCk_Handle_InteractTarget InTarget)
    {
        // Local copy before iterating: AS treats by-value params as read-only
        // references (CkAutoTest_Base.as documents the same rule for
        // FCk_SharedBool), and the copy keeps the ranged-for unambiguous.
        auto Targets = InTargets;
        for (auto Target : Targets)
        {
            if (Target == InTarget)
            { return true; }
        }
        return false;
    }

    private TArray<FCk_Handle_InteractTarget> DoGet_Best()
    {
        return utils_interaction_resolver::Get_BestInteractTargets(
            _Resolver, interaction_gym_helpers::UseIntent());
    }

    private FCk_Handle_Interaction DoGet_LiveInteractionOnA()
    {
        return utils_interaction::TryGet(FCk_Handle(_TargetA), _ResolverOwner,
            FCk_Handle(_TargetA), interaction_gym_helpers::DefaultChannel());
    }

    //------------------------------------------------------------------------
    // Signal handlers
    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnBestTargetsChanged(
        FCk_Handle_InteractionResolver InResolver,
        FGameplayTag InIntent,
        const TArray<FCk_Handle_InteractTarget>&in InPreviousTargets,
        const TArray<FCk_Handle_InteractTarget>&in InNewTargets,
        const TArray<FCk_Handle_InteractTarget>&in InRemovedTargets)
    {
        _BroadcastCount++;
        _LastNewTargets = InNewTargets;
        _LastRemovedTargets = InRemovedTargets;
    }

    UFUNCTION()
    private void OnTargetAInteractionFinished(
        FCk_Handle_InteractTarget InTarget,
        FCk_Handle_Interaction InInteraction,
        ECk_SucceededFailed InResult)
    {
        _AInteractionFinished = true;
    }

    UFUNCTION()
    private void OnStartIntentCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        if (InResult != ECk_Request_OperationResult::Succeeded)
        { FinishFailure(f"StartIntent completed {InResult} instead of Succeeded"); return; }
        _IntentStartCompleted = true;
    }

    //------------------------------------------------------------------------
    // Phase a - intent first, target second
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_StartIntent(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_interaction_resolver::Request_StartIntent(_Resolver,
            FCk_Request_InteractionResolver_StartIntent(interaction_gym_helpers::UseIntent()),
            FCk_Delegate_Request_OnCompleted(this, n"OnStartIntentCompleted"));
    }

    UFUNCTION()
    private void Check_IntentStarted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_IntentStartCompleted);
    }

    UFUNCTION()
    private void Step_AddA(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _CountAtAddA = _BroadcastCount;
        utils_interaction_resolver::Request_AddInteractTarget(_Resolver,
            FCk_Request_InteractionResolver_AddInteractTarget(_TargetA));
    }

    // Never true on the pre-fix code: AddInteractTarget stamped no re-resolve
    // tag, so a target appearing mid-hold was invisible until the next intent
    // edge. The step times out and the failure names this condition.
    UFUNCTION()
    private void Check_BestIsA(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Best = DoGet_Best();
        auto Res = OutResult;
        Res.Set(Best.Num() == 1 && Best[0] == _TargetA);
    }

    UFUNCTION()
    private void Step_AssertPhaseA(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_BroadcastCount, _CountAtAddA + 1,
            "adding A mid-hold broadcast OnBestTargetsChanged exactly once");
        Assert_True(DoContains(_LastNewTargets, _TargetA),
            "A arrived in NewTargets");
        Assert_Equals_Int(_LastRemovedTargets.Num(), 0,
            "A's arrival removed nothing");
    }

    //------------------------------------------------------------------------
    // Phase c - no-op churn is silent
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_NoOpChurn(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _CountAtChurn = _BroadcastCount;

        // Already a member - the handler's early return at
        // CkInteractionResolver_Processor.cpp:150-154.
        utils_interaction_resolver::Request_AddInteractTarget(_Resolver,
            FCk_Request_InteractionResolver_AddInteractTarget(_TargetA));

        // Valid target, never added - the early return at :173-177.
        utils_interaction_resolver::Request_RemoveInteractTarget(_Resolver,
            FCk_Request_InteractionResolver_RemoveInteractTarget(_TargetD));
    }

    UFUNCTION()
    private void Step_AssertNoOpSilence(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_BroadcastCount, _CountAtChurn,
            "no-op add of a member and remove of a non-member broadcast nothing");

        auto Best = DoGet_Best();
        Assert_True(Best.Num() == 1 && Best[0] == _TargetA,
            "best target undisturbed by no-op churn");
    }

    //------------------------------------------------------------------------
    // Phase d - the pin
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_StartInteractionOnA(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        // Guards this phase's premise: the pin exists to protect an in-progress
        // TIMED interaction, so assert A really is Timed before trusting the result.
        Assert_True(utils_interact_target::Get_InteractionCompletionPolicy(_TargetA)
                == ECk_Interaction_CompletionPolicy::Timed,
            "Get_InteractionCompletionPolicy reads back the Timed policy A was composed with");

        auto Request = FCk_Try_InteractTarget_StartInteraction();
        Request.Set_InteractSource(_ResolverOwner);
        Request.Set_InteractInstigator(_ResolverOwner);
        utils_interact_target::Request_StartInteraction(_TargetA, Request);
    }

    UFUNCTION()
    private void Check_InteractionLiveOnA(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(ck::IsValid(DoGet_LiveInteractionOnA()));
    }

    UFUNCTION()
    private void Step_AddNearerB(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _CountAtAddB = _BroadcastCount;
        utils_interaction_resolver::Request_AddInteractTarget(_Resolver,
            FCk_Request_InteractionResolver_AddInteractTarget(_TargetB));
    }

    // On the pinless halfway state (the R1 regression) B sorts ahead, the
    // SetNum truncation evicts A, and both the best-set assert and the
    // broadcast-count assert here go red. The add DID schedule a resolve
    // (phase a proved adds do that); with the pin its outcome is "nothing
    // changed", which is why this is a settle window rather than a wait.
    UFUNCTION()
    private void Step_AssertPin(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Best = DoGet_Best();
        Assert_True(Best.Num() == 1 && Best[0] == _TargetA,
            "A with the live interaction is still the picked target - nearer B must not evict it");
        Assert_Equals_Int(_BroadcastCount, _CountAtAddB,
            "no eviction broadcast when the nearer B appeared");
        Assert_True(ck::IsValid(DoGet_LiveInteractionOnA()),
            "A's Timed interaction survived B's arrival");
        Assert_False(_AInteractionFinished,
            "A's interaction was never cancelled (no OnInteractionFinished)");
    }

    //------------------------------------------------------------------------
    // Phase b - removing the picked target mid-hold falls back to next-best
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_RemoveA(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _CountAtRemoveA = _BroadcastCount;
        utils_interaction_resolver::Request_RemoveInteractTarget(_Resolver,
            FCk_Request_InteractionResolver_RemoveInteractTarget(_TargetA));
    }

    // Never true on the pre-fix code: RemoveInteractTarget stamped nothing,
    // so the cached set kept naming the removed A. Also the guard that keeps
    // this file red on fully-old code, where phase d passes vacuously.
    UFUNCTION()
    private void Check_BestIsB(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Best = DoGet_Best();
        auto Res = OutResult;
        Res.Set(Best.Num() == 1 && Best[0] == _TargetB);
    }

    UFUNCTION()
    private void Step_AssertRemoval(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_BroadcastCount, _CountAtRemoveA + 1,
            "removing the picked target broadcast exactly once");
        Assert_True(DoContains(_LastRemovedTargets, _TargetA),
            "removed A arrived in RemovedTargets");
        Assert_True(_LastNewTargets.Num() == 1 && _LastNewTargets[0] == _TargetB,
            "the set became the next-best B");
        // Last step: the sequencer finishes the test on its own.
    }
}
