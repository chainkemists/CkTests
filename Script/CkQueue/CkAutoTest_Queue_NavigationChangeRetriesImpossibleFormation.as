// Language=angelscript
// Settle questions go to the neutral nav surface, and on CkGroundNav the fixture stages its own field
// over the origin floor, so it runs unchanged on any provider.

class UCk_AutoTest_Queue_NavigationChangeRetriesImpossibleFormation : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCkAutoTest_GroundNavFixture _Field;

    private FCk_Handle             _QueueOwner;
    private FCk_Handle_Queue       _Queue;
    private FCk_Handle             _Member;
    private FCk_Handle_NavSurfaceMarkup _Markup;
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
        // On CkGroundNav nothing in the shared level carries a field, so the fixture stages one over
        // the origin floor; on Recast the level's own navmesh is the surface and nothing is staged.
        if (utils_nav_surface::Get_Provider() == ECk_NavSurface_Provider::GroundNav &&
            _Field.Request_StageOriginField(InHandle) == false)
        {
            FinishFailure(_Field.Get_StagingError());
            return;
        }

        utils_nav_surface::Request_SurfaceRebuild_ForTesting();

        Add_Step_WaitUntil("the nav surface settled", n"Check_SurfaceSettled");
        Add_Step_WaitUntil("front location is navigable before null markup", n"Check_FrontNavigable");
        Add_Step("compose a queue and paint a null area over its only front", n"Step_ComposeBlockedQueue");
        Add_Step_WaitUntil("the nav surface settled", n"Check_SurfaceSettled");
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
        _Field.Do_ReportCrossover("Queue_NavigationChangeRetriesImpossibleFormation", IsFinished() ? "finished" : "unfinished");
        _Field.Request_ReleaseOriginField();

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
    private void Check_SurfaceSettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(utils_nav_surface::Get_IsSurfaceSettled());
    }

    UFUNCTION()
    private void Check_FrontNavigable(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        const auto Projected = Do_ProjectOntoSurface(
            FVector(200.0f, 0.0f, 0.0f), FVector(20.0f, 20.0f, 300.0f));
        const bool Projects = Projected.Get_Status() == ECk_NavSurface_QueryStatus::Success;
        if (Projects) { _FrontWorld = Projected.Get_Location(); }
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
        auto Params = FCk_Fragment_Queue_ParamsData();
        Params.Set_MaxNavigationRetries(1);
        Params.Set_NavigationRetryDelaySeconds(0.0f);
        _Queue = utils_queue::Add(_QueueOwner, Params);
        _Queue.BindTo_OnQueueFormationStateChanged(
            FCk_Delegate_Queue_OnFormationStateChanged(this, n"OnFormationStateChanged"));
        _Member = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto MarkupRequest = FCk_Request_NavSurface_AreaMarkup(
            utils_shapes::Make_Box(FCk_ShapeBox_Dimensions(FVector(180.0f, 180.0f, 300.0f))),
            FGameplayTag());
        MarkupRequest.Set_WorldTransform(FTransform(FRotator::ZeroRotator, _FrontWorld, FVector::OneVector));

        _Markup = utils_nav_surface::Request_ImpassableBox(MarkupRequest);
        utils_nav_surface::Request_SurfaceRebuild_ForTesting();
    }

    UFUNCTION()
    private void Check_FrontBlocked(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        const auto ProbeExtents = FVector(20.0f, 20.0f, 300.0f);
        const bool FrontProjects = Do_ProjectOntoSurface(
            _FrontWorld, ProbeExtents).Get_Status() == ECk_NavSurface_QueryStatus::Success;
        const bool ApproachProjects = Do_ProjectOntoSurface(
            _FrontWorld + FVector(-500.0f, 0.0f, 0.0f), ProbeExtents).Get_Status() == ECk_NavSurface_QueryStatus::Success;
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
        Assert_True(Do_ProjectOntoSurface(
                _FrontWorld + FVector(-500.0f, 0.0f, 0.0f),
                FVector(20.0f, 20.0f, 300.0f)).Get_Status() == ECk_NavSurface_QueryStatus::Success,
            "target-only null markup preserves the queue approach navigation area");
    }

    UFUNCTION()
    private void Step_RemoveMarkupAndRebuild(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        // The markup entity's destroy is deferred; its EndPlay unpaint unregisters the nav-relevant
        // object, which dirties the affected tiles and drives exactly ONE rebuild by itself. An
        // explicit rebuild here would run BEFORE the deferred unpaint (baking the markup back in)
        // and then be followed by the unpaint's own rebuild - two generation events where
        // Check_NavigationChanged requires exactly one.
        DestroyMarkup();
    }

    UFUNCTION()
    private void Check_NavigationChanged(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        const bool FrontRestored = Do_ProjectOntoSurface(
            _FrontWorld, FVector(20.0f, 20.0f, 300.0f)).Get_Status() == ECk_NavSurface_QueryStatus::Success;
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

    private FCk_NavSurface_ProjectionResult Do_ProjectOntoSurface(FVector InPoint, FVector InSearchHalfExtents) const
    {
        auto Query = FCk_NavSurface_ProjectionQuery(InPoint);
        Query.Set_Mode(ECk_NavSurface_ProjectionMode::Closest);
        Query.Set_SearchHalfExtents(InSearchHalfExtents);

        return utils_nav_surface::Try_ProjectPoint(Query);
    }

    private void DestroyMarkup()
    {
        if (ck::Is_NOT_Valid(_Markup)) { return; }
        utils_entity_lifetime::Request_DestroyEntity(FCk_Handle(_Markup));
        _Markup = FCk_Handle_NavSurfaceMarkup();
    }
}
