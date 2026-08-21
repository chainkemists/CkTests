// Language=angelscript

class UCk_AutoTest_Queue_NavigationChangeRetriesImpossibleFormation : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle             _QueueOwner;
    private FCk_Handle_Queue       _Queue;
    private FCk_Handle             _Member;
    private UCk_NavAreaMarkup_UE   _Markup = nullptr;
    private FVector                _FrontWorld;
    private int32                  _RetryExhaustedEvents = 0;
    private int32                  _NavigationChangedEvents = 0;
    private int32                  _RetryExhaustedRevision = 0;
    private int32                  _NavigationChangedRevision = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        utils_transform::Add(LocalHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        Add_Step_WaitUntil("front location is navigable before null markup", n"Check_FrontNavigable");
        Add_Step("compose a queue and paint a null area over its only front", n"Step_ComposeBlockedQueue");
        Add_Step_WaitUntil("null markup removes the front from navigation", n"Check_FrontBlocked");
        Add_Step("join a member into the impossible formation", n"Step_RequestJoin");
        Add_Step_WaitUntil("queue exhausts its one navigation retry", n"Check_RetryExhausted");
        Add_Step("assert no assignment was published while topology was impossible", n"Step_AssertExhausted");
        Add_Step("remove null markup and request a navigation rebuild", n"Step_RemoveMarkupAndRebuild");
        Add_Step_WaitUntil("navigation change reopens formation", n"Check_NavigationChanged");
        Add_Step_WaitUntil("reopened formation publishes an assignment", n"Check_RecoveredAssignment");
        Add_Step("assert recovery revision and assignment contract", n"Step_AssertRecovered");
        Run_Steps(InHandle);
    }

    UFUNCTION(BlueprintOverride)
    void DoEndPlay(FCk_Handle InHandle)
    {
        DestroyMarkup();
    }

    UFUNCTION()
    private void OnFormationStateChanged(FCk_Handle_Queue InQueue, FCk_Queue_FormationState InState)
    {
        if (InQueue != _Queue) { return; }
        if (InState.Get_Reason() == ECk_Queue_EventReason::NavigationRetryExhausted)
        {
            _RetryExhaustedEvents += 1;
            _RetryExhaustedRevision = InState.Get_QueueRevision();
        }
        else if (InState.Get_Reason() == ECk_Queue_EventReason::NavigationChanged)
        {
            _NavigationChangedEvents += 1;
            _NavigationChangedRevision = InState.Get_QueueRevision();
        }
    }

    UFUNCTION()
    private void Check_FrontNavigable(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FVector Projected;
        auto Context = InHandle;
        const bool Projects = utils_nav::Try_ProjectOntoNavmesh(
            Context, FVector(200.0f, 0.0f, 0.0f), 20.0f, Projected, 300.0f);
        if (Projects) { _FrontWorld = Projected; }
        auto Result = OutResult;
        Result.Set(Projects);
    }

    UFUNCTION()
    private void Step_ComposeBlockedQueue(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _QueueOwner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_QueueOwner,
            FTransform(FRotator::ZeroRotator, _FrontWorld, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        auto Origins = TArray<FCk_Queue_Origin>();
        Origins.Add(FCk_Queue_Origin(FTransform::Identity));
        auto Params = FCk_Fragment_Queue_ParamsData(Origins);
        Params.Set_MaxNavigationRetries(1);
        Params.Set_NavigationRetryDelaySeconds(0.0f);
        _Queue = utils_queue::Add(_QueueOwner, Params);
        _Queue.BindTo_OnQueueFormationStateChanged(
            FCk_Delegate_Queue_OnFormationStateChanged(this, n"OnFormationStateChanged"));
        _Member = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto MarkupOwner = InHandle;
        _Markup = utils_nav_area_markup::Request_Create(MarkupOwner,
            FTransform(FRotator::ZeroRotator, _FrontWorld, FVector::OneVector),
            FVector(180.0f, 180.0f, 300.0f), UNavArea_Null);
        utils_nav::Request_NavigationRebuild_ForTesting(MarkupOwner);
    }

    UFUNCTION()
    private void Check_FrontBlocked(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FVector FrontProjected;
        FVector ApproachProjected;
        auto Context = InHandle;
        const bool FrontProjects = utils_nav::Try_ProjectOntoNavmesh(
            Context, _FrontWorld, 20.0f, FrontProjected, 300.0f);
        const bool ApproachProjects = utils_nav::Try_ProjectOntoNavmesh(
            Context, _FrontWorld + FVector(-500.0f, 0.0f, 0.0f), 20.0f, ApproachProjected, 300.0f);
        auto Result = OutResult;
        Result.Set(ck::IsValid(_Markup) && FrontProjects == false && ApproachProjects);
    }

    UFUNCTION()
    private void Step_RequestJoin(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Queue.Request_Join(FCk_Request_Queue_Join(_Member));
    }

    UFUNCTION()
    private void Check_RetryExhausted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Snapshot;
        const bool HasSnapshot = _Queue.TryGet_MemberSnapshot(_Member, Snapshot);
        auto Result = OutResult;
        Result.Set(_RetryExhaustedEvents == 1
            && _Queue.Get_State() == ECk_Queue_State::WaitingForNavigationChange
            && HasSnapshot && Snapshot.Get_AssignmentRevision() == 0);
    }

    UFUNCTION()
    private void Step_AssertExhausted(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Snapshot;
        Assert_True(_Queue.TryGet_MemberSnapshot(_Member, Snapshot),
            "pending member remains represented while navigation is impossible");
        Assert_Equals_Int(_RetryExhaustedEvents, 1,
            "one configured navigation retry produces exactly one retry-exhausted event");
        Assert_True(Snapshot.Get_AssignmentRevision() == 0,
            "impossible formation publishes no target assignment revision");
        Assert_True(Snapshot.Get_State() == ECk_Queue_MemberState::PendingAdmission,
            "member remains pending rather than falsely arriving on blocked topology");
        FVector ApproachProjected;
        auto Context = InHandle;
        Assert_True(utils_nav::Try_ProjectOntoNavmesh(
                Context, _FrontWorld + FVector(-500.0f, 0.0f, 0.0f), 20.0f, ApproachProjected, 300.0f),
            "target-only null markup preserves the queue approach navigation area");
    }

    UFUNCTION()
    private void Step_RemoveMarkupAndRebuild(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DestroyMarkup();
        auto Context = InHandle;
        utils_nav::Request_NavigationRebuild_ForTesting(Context);
    }

    UFUNCTION()
    private void Check_NavigationChanged(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FVector Projected;
        auto Context = InHandle;
        const bool FrontRestored = utils_nav::Try_ProjectOntoNavmesh(
            Context, _FrontWorld, 20.0f, Projected, 300.0f);
        auto Result = OutResult;
        Result.Set(FrontRestored && _NavigationChangedEvents == 1
            && _NavigationChangedRevision > _RetryExhaustedRevision);
    }

    UFUNCTION()
    private void Check_RecoveredAssignment(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Snapshot;
        const bool HasSnapshot = _Queue.TryGet_MemberSnapshot(_Member, Snapshot);
        auto Result = OutResult;
        Result.Set(HasSnapshot && _Queue.Get_State() == ECk_Queue_State::Ready
            && Snapshot.Get_AssignmentRevision() > _NavigationChangedRevision
            && Snapshot.Get_State() == ECk_Queue_MemberState::Assigned);
    }

    UFUNCTION()
    private void Step_AssertRecovered(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        FCk_Queue_MemberSnapshot Snapshot;
        Assert_True(_Queue.TryGet_MemberSnapshot(_Member, Snapshot),
            "member survives navigation waiting and recovers after topology returns");
        Assert_Equals_Int(_NavigationChangedEvents, 1,
            "one markup removal/rebuild produces one NavigationChanged event");
        Assert_True(_NavigationChangedRevision > _RetryExhaustedRevision,
            "navigation recovery advances the formation revision after exhaustion");
        Assert_True(Snapshot.Get_AssignmentRevision() > _NavigationChangedRevision,
            "recovered topology publishes a fresh assignment after NavigationChanged");
    }

    private void DestroyMarkup()
    {
        if (ck::Is_NOT_Valid(_Markup)) { return; }
        utils_nav_area_markup::Request_Destroy(_Markup);
        _Markup = nullptr;
    }
}
