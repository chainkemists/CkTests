// Language=angelscript
//============================================================================
// CK NAV - NET AUTOMATION TEST: THE DEFERRED-PATH QUEUE IS PER WORLD
//============================================================================
//
// CkNavigation parks a FindPath whose start point cannot be projected and
// re-drives it later. That queue used to be a process-wide static
// (`GDeferredNavRequests`), which is not multi-PIE-safe; it now lives on each
// world's transient entity as FFragment_Nav_DeferredRequests. This test runs
// two PIE worlds and pins that each world's episodes are answered by that
// world's own queue, on that world's own clock, and that releasing one world's
// episode does not touch the other's.
//
// FIXTURE. The net harness runs its worlds on /Engine/Maps/Entry, which bakes
// no navmesh at all, so every FindPath issued in either world is unprojectable
// by construction - no volume to stage, no rebuild to wait on.
//
// WHAT EACH WORLD PROVES.
//
//   Authority world - the only world that can hold a deferred entry, because
//   Request_FindPath refuses a non-authority caller before the queue is ever
//   reached (ECk_Nav_PathFailReason::NotAuthority):
//     1. an episode parks at Pending  -> the entry is in THIS world's queue;
//     2. it force-fails at ck.Nav.MaxDeferralSeconds with NoNavData and
//        reaches its caller exactly once -> this world's watchdog ran on this
//        world's clock, uninterrupted by the other world's ticking;
//     3. a SECOND parked episode, abandoned, completes Failed_Cancelled and
//        the slot returns to None -> AbandonPath purged an entry that was in
//        this world's queue;
//     4. and it STAYS None past a full deferral horizon -> nothing in the
//        other world resurrected or re-failed the released entry.
//
//   Non-authority world, over the same wall clock:
//     5. its own request resolves with an IMMEDIATE local refusal (NotAuthority,
//        or NoNavSystem - the requester is locally spawned so it holds local
//        authority, and client worlds spawn no nav system on this map) and
//     6. still reads that same local refusal a full deferral horizon later -
//        the other world's NoNavData watchdog never landed here.
//
// WHAT THIS TEST CANNOT PROVE, AND WHY. The symmetric shape the phase doc
// describes - "two worlds each hold in-flight deferred requests" - is not
// reachable from script: the client world cannot enqueue a nav request at all,
// so only one world can ever hold a deferred entry through the public API.
// Cross-world leakage is therefore observed one-directionally (world A's
// activity leaving world B's slot untouched, in both directions), not as two
// symmetric queues. Closing that gap needs a C++ Layer-1 test that can address
// both worlds' queue fragments directly.
//
// The 7s horizon waits are wall-clock CkTimers, not frame counts: they guard
// NEGATIVES ("nothing further happened"), and the thing they must outlast -
// ck.Nav.MaxDeferralSeconds, 5s - is measured in seconds, not in frames.
//============================================================================

class UCk_AutoTest_Net_DeferredQueue_PerWorldIsolation : UCk_AutoTest_NetBase
{
    // Inside the net harness's hard 30s per-world AS deadline, with room for the
    // 5s watchdog plus the 7s horizon and staging.
    default _TimeoutSeconds = 26.0f;

    // The default 240 polls is ~4s at 60fps - far short of the 5s watchdog and the 7s horizon.
    default _DefaultWaitFrameBudget = 3000;

    // Far above anything that could ever be navmesh, so the start point is unprojectable whether
    // or not the world happens to have NavData. Same trick as Crowd_Watchdog_PendingTimeoutFailsEpisodeOnce.
    private const FVector UnprojectableStart = FVector(0.0, 0.0, 100000.0);
    private const FVector Goal = FVector(300.0, 0.0, 0.0);

    // Must outlast ck.Nav.MaxDeferralSeconds (5s default) with margin.
    private const float HorizonSeconds = 7.0;

    private FCk_Handle _SelfHandle;
    private FCk_Handle _Requester;

    private int32 _PathFailedCount = 0;
    private int32 _CompletionCount = 0;
    private ECk_Request_OperationResult _LastCompletionResult = ECk_Request_OperationResult::Failed;
    private bool _HorizonElapsed = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        // Branch on the SUBJECT's authority, not this test entity's. The harness spawns the test
        // entity on every PIE world's transient entity, locally in each - so it is authoritative in
        // its own world and utils_net::Get_HasAuthority(InHandle) is TRUE on the client too, which
        // sent the client world down the authority branch and hung it on Check_SlotIsPending. The
        // replicated NetSubject is the only handle here that carries real net role
        // (CkAutoTest_NetBase.as:20-37 documents this as the authoring pattern).
        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        {
            FinishFailure("net subject not found - harness misconfigured?");
            return;
        }

        if (utils_net::Get_HasAuthority(Subject))
        {
            Add_Step(          "park an episode this world cannot answer",        n"Step_ArrangeAuthority");
            Add_Step_WaitUntil("it parks in this world's deferral queue",          n"Check_SlotIsPending");
            Add_Step_WaitUntil("this world's deferral watchdog fails it",          n"Check_SlotIsFailed");
            Add_Step(          "the failure is this world's own, reported once",   n"Step_AssertWatchdogFailedLocally");
            Add_Step(          "park a second episode",                            n"Step_ReArmSecondEpisode");
            Add_Step_WaitUntil("the second episode parks too",                     n"Check_SlotIsPending");
            Add_Step(          "abandon it and start the horizon clock",           n"Step_AbandonAndArmHorizon");
            Add_Step_WaitUntil("a full deferral horizon passes",                   n"Check_HorizonElapsed");
            Add_Step(          "the released slot stayed released",                n"Step_AssertReleasedSlotStaysReleased");
        }
        else
        {
            Add_Step(          "issue the same request from a non-authority world", n"Step_ArrangeNonAuthority");
            Add_Step_WaitUntil("this world resolves it locally",                    n"Check_SlotResolved");
            Add_Step(          "it was refused here, not queued anywhere",          n"Step_AssertRefusedLocally");
            Add_Step(          "start the horizon clock",                           n"Step_ArmHorizon");
            Add_Step_WaitUntil("a full deferral horizon passes",                    n"Check_HorizonElapsed");
            Add_Step(          "the other world's watchdog never landed here",      n"Step_AssertStillRefusedLocally");
        }

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Shared staging
    //------------------------------------------------------------------------

    private void Do_CreateUnprojectableRequester()
    {
        _Requester = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _Requester.Set_DebugName(n"DeferredQueueIsolation_Requester");

        utils_transform::Add(_Requester,
            FTransform(FRotator::ZeroRotator, UnprojectableStart, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        utils_nav::BindTo_OnPathFailed(_Requester,
            FCk_Delegate_Nav_OnPathFailed(this, n"OnPathFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
    }

    UFUNCTION()
    private void OnPathFailed(FCk_Handle InHandle)
    {
        _PathFailedCount += 1;
    }

    UFUNCTION()
    private void OnRequestCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _CompletionCount += 1;
        _LastCompletionResult = InResult;
    }

    //------------------------------------------------------------------------
    // Authority world
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_ArrangeAuthority(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Do_CreateUnprojectableRequester();

        utils_nav::Request_FindPath(_Requester, FCk_Request_Nav_FindPath(Goal),
            FCk_Delegate_Request_OnCompleted(this, n"OnRequestCompleted"));
    }

    UFUNCTION()
    private void Check_SlotIsPending(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_nav::Get_PathStatus(_Requester) == ECk_Nav_PathStatus::Pending);
    }

    UFUNCTION()
    private void Check_SlotIsFailed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_nav::Get_PathStatus(_Requester) == ECk_Nav_PathStatus::Failed);
    }

    UFUNCTION()
    private void Step_AssertWatchdogFailedLocally(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Reason = utils_nav::Get_PathResult(_Requester).Get_Diagnostics().Get_LastFailReason();
        Assert_True(Reason == ECk_Nav_PathFailReason::NoNavData,
            f"a parked episode that timed out must name the deferral watchdog's own reason, not inherit one from elsewhere - got {Reason}");

        Assert_Equals_Int(_PathFailedCount, 1,
            "the deferral watchdog owns the terminal for a parked episode and must fire it exactly once");
        Assert_Equals_Int(_CompletionCount, 1,
            "a request completion is a fire-exactly-once guarantee, and the deferral queue is the only site that can honour it for a parked entry");
        Assert_True(_LastCompletionResult == ECk_Request_OperationResult::Failed,
            f"an episode nothing could answer completes Failed - got {_LastCompletionResult}");
    }

    UFUNCTION()
    private void Step_ReArmSecondEpisode(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_nav::Request_FindPath(_Requester, FCk_Request_Nav_FindPath(Goal),
            FCk_Delegate_Request_OnCompleted(this, n"OnRequestCompleted"));
    }

    UFUNCTION()
    private void Step_AbandonAndArmHorizon(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_nav::Request_AbandonPath(_Requester, FCk_Request_Nav_AbandonPath(1));

        // Abandon releases on the calling stack: purge the queue entry, then clear the slot.
        Assert_Equals_Int(_CompletionCount, 2,
            "abandoning must complete the entry it purged - a silent purge strands the caller that was waiting on it");
        Assert_True(_LastCompletionResult == ECk_Request_OperationResult::Failed_Cancelled,
            f"the purged entry was parked in THIS world's queue, so its completion is Failed_Cancelled - got {_LastCompletionResult}");

        const auto Status = utils_nav::Get_PathStatus(_Requester);
        Assert_True(Status == ECk_Nav_PathStatus::None,
            f"abandoning ENDS the episode - a slot left reading anything else keeps every consumer waiting on a query that no longer exists (reads {Status})");

        Do_ArmHorizonTimer();
    }

    UFUNCTION()
    private void Step_AssertReleasedSlotStaysReleased(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Status = utils_nav::Get_PathStatus(_Requester);
        Assert_True(Status == ECk_Nav_PathStatus::None,
            f"a full deferral horizon passed with another PIE world ticking its own nav queue alongside this one - the released slot must still be released, and reads {Status}");

        Assert_Equals_Int(_PathFailedCount, 1,
            "the abandoned episode was purged before the watchdog could reach it, so no second terminal is owed");
        Assert_Equals_Int(_CompletionCount, 2,
            "nothing else was enqueued, so no further completion is owed - a third means a purged entry was answered twice");
    }

    //------------------------------------------------------------------------
    // Non-authority world
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_ArrangeNonAuthority(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Do_CreateUnprojectableRequester();

        // No completion delegate here on purpose: the non-authority refusal path removes the queued
        // request without firing one, and this test is not the place to bless or contest that.
        utils_nav::Request_FindPath(_Requester, FCk_Request_Nav_FindPath(Goal));
    }

    UFUNCTION()
    private void Check_SlotResolved(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        const auto Status = utils_nav::Get_PathStatus(_Requester);
        auto Res = OutResult;
        Res.Set(Status != ECk_Nav_PathStatus::None && Status != ECk_Nav_PathStatus::Pending);
    }

    UFUNCTION()
    private void Step_AssertRefusedLocally(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Status = utils_nav::Get_PathStatus(_Requester);
        Assert_True(Status == ECk_Nav_PathStatus::Failed,
            f"pathing is authority-only, so a non-authority world resolves its own request immediately - reads {Status}");

        // The requester is spawned locally in each PIE world, so even the client world holds local
        // authority over it - a client refusal therefore reads NoNavSystem (client worlds spawn no
        // nav system on this map), not NotAuthority. Either is an IMMEDIATE local refusal; only
        // NoNavData would mean the request sat in a deferral queue, which is the one thing this
        // world must never do.
        const auto Reason = utils_nav::Get_PathResult(_Requester).Get_Diagnostics().Get_LastFailReason();
        Assert_True(Reason == ECk_Nav_PathFailReason::NotAuthority || Reason == ECk_Nav_PathFailReason::NoNavSystem,
            f"the refusal must be an immediate local one (NotAuthority or NoNavSystem) - NoNavData or anything queue-flavored means this world consulted a nav queue it has no business in (got {Reason})");
    }

    UFUNCTION()
    private void Step_AssertStillRefusedLocally(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Reason = utils_nav::Get_PathResult(_Requester).Get_Diagnostics().Get_LastFailReason();
        Assert_True(Reason != ECk_Nav_PathFailReason::NoNavData,
            "NoNavData is the OTHER world's deferral watchdog reason - seeing it here means one world's queue answered another world's entity");
        Assert_True(Reason == ECk_Nav_PathFailReason::NotAuthority || Reason == ECk_Nav_PathFailReason::NoNavSystem,
            f"a full deferral horizon passed while the authority world drained and force-failed its own queue; this world's slot must still read its own immediate local refusal - got {Reason}");

        Assert_Equals_Int(_PathFailedCount, 0,
            "the authority world broadcast OnPathFailed for its own episode over this same horizon - one arriving here would mean the signal crossed worlds");
    }

    //------------------------------------------------------------------------
    // Horizon clock - wall-clock, because the thing it must outlast
    // (ck.Nav.MaxDeferralSeconds) is measured in seconds, not frames.
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_ArmHorizon(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Do_ArmHorizonTimer();
    }

    private void Do_ArmHorizonTimer()
    {
        auto Params = FCk_Fragment_Timer_ParamsData(FCk_Time(HorizonSeconds));
        Params.Set_StartingState(ECk_Timer_State::Running)
              .Set_Behavior(ECk_Timer_Behavior::StopOnDone);

        auto Timer = utils_timer::Add(_SelfHandle, Params);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnHorizonElapsed"));
    }

    UFUNCTION()
    private void OnHorizonElapsed(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        _HorizonElapsed = true;
    }

    UFUNCTION()
    private void Check_HorizonElapsed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_HorizonElapsed);
    }
}
