// Language=angelscript

// Covers the live Queue gym regression: after servicing a ClaimFirst front member,
// real Crowd adapters must offer and claim a new front without manual movement outcomes.
class UCk_AutoTest_Queue_ClaimFirstPostAdvanceCrowdProgress : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 30.0f;

    private const FVector k_OwnerTargetLocation = FVector(600.0f, 0.0f, 0.0f);
    private const float k_SlotSpacingUu = 120.0f;
    private const float k_AgentRadiusUu = 42.0f;
    private const float k_ClaimRadiusUu = 30.0f;
    private const float k_SettleRadiusUu = 10.0f;
    private const float k_ReacquireRadiusUu = 20.0f;

    private FCk_Handle                         _QueueOwner;
    private FCk_Handle_Queue                   _Queue;
    private TArray<FCk_Handle_CrowdAgent>      _Agents;
    private FCk_Handle_CrowdAgent              _FirstServed;
    private FCk_Handle_CrowdAgent              _SecondFront;
    private FVector                            _FirstFrontLocation;
    private FVector                            _FirstExitGoal;
    private int32                              _AdvanceCompletions = 0;
    private ECk_Request_OperationResult        _FirstAdvanceResult = ECk_Request_OperationResult::Failed;
    private ECk_Request_OperationResult        _SecondAdvanceResult = ECk_Request_OperationResult::Failed;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        utils_transform::Add(LocalHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        Add_Step_WaitUntil("queue approach and owner target are navigable", n"Check_NavigationReady");
        Add_Step("compose a ClaimFirst queue with three real Crowd agents", n"Step_ComposeQueueAndAgents");
        Add_Step_WaitUntil("queue setup completes", n"Check_QueueReady");
        Add_Step("join the queue through each Crowd adapter", n"Step_RequestJoins");
        Add_Step_WaitUntil("all three adapters claim the initial linear ranks", n"Check_InitialRanksClaimed", 1200);
        Add_Step("advance the real arrived front member", n"Step_RequestFirstAdvance");
        Add_Step_WaitUntil("the first advance succeeds and removes its serving member", n"Check_FirstAdvanceCompleted");
        Add_Step("teleport the served member clear of the old front", n"Step_ClearFirstServedWithTransform");
        Add_Step_WaitUntil("the served member transform clears the old front", n"Check_FirstServedCleared");
        Add_Step_WaitUntil("a surviving Crowd adapter claims the reopened front", n"Check_SurvivorReachedFront", 1200);
        Add_Step("advance the new real arrived front member", n"Step_RequestSecondAdvance");
        Add_Step_WaitUntil("the second advance succeeds", n"Check_SecondAdvanceCompleted");
        Add_Step("assert post-advance Crowd progress", n"Step_AssertPostAdvanceProgress");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void OnAdvanceCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _AdvanceCompletions += 1;
        if (_AdvanceCompletions == 1) { _FirstAdvanceResult = InResult; }
        else if (_AdvanceCompletions == 2) { _SecondAdvanceResult = InResult; }
    }

    UFUNCTION()
    private void Check_NavigationReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Context = InHandle;
        auto EveryInitialSlotIsNavigable = true;
        for (auto Rank = 0; Rank < 3; ++Rank)
        {
            FVector Projected;
            const auto SlotLocation = k_OwnerTargetLocation - FVector(k_SlotSpacingUu * Rank, 0.0f, 0.0f);
            if (utils_nav::Try_ProjectOntoNavmesh(Context, SlotLocation, 100.0f, Projected, 300.0f) == false)
            { EveryInitialSlotIsNavigable = false; break; }
        }
        auto Result = OutResult;
        Result.Set(EveryInitialSlotIsNavigable);
    }

    UFUNCTION()
    private void Step_ComposeQueueAndAgents(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _QueueOwner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_QueueOwner, FTransform(k_OwnerTargetLocation), ECk_Replication::DoesNotReplicate);

        auto Params = FCk_Fragment_Queue_ParamsData();
        Params.Set_LayoutAlgorithm(ECk_Queue_LayoutAlgorithm::Linear);
        Params.Set_SlotSpacingUu(k_SlotSpacingUu);
        Params.Set_AgentRadiusUu(k_AgentRadiusUu);
        Params.Set_SlotClaimRadiusUu(k_ClaimRadiusUu);
        Params.Set_SlotSettleRadiusUu(k_SettleRadiusUu);
        Params.Set_SlotReacquireRadiusUu(k_ReacquireRadiusUu);
        Params.Set_SlotClaimPolicy(ECk_Queue_SlotClaimPolicy::ClaimFirstAvailableOnReach);
        Params.Set_HardLimit(3);
        Params.Set_SoftLimit(3);
        _Queue = utils_queue::Add(_QueueOwner, Params);

        for (auto Index = 0; Index < 3; ++Index)
        {
            const auto InitialSlot = k_OwnerTargetLocation - FVector(k_SlotSpacingUu * Index, 0.0f, 0.0f);
            _Agents.Add(CreateCrowdAgent(InHandle, InitialSlot));
        }
    }

    UFUNCTION()
    private void Check_QueueReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(ck::IsValid(_Queue) && _Queue.Get_State() == ECk_Queue_State::Ready && _Agents.Num() == 3);
    }

    UFUNCTION()
    private void Step_RequestJoins(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        for (int32 AgentIndex = 0; AgentIndex < _Agents.Num(); ++AgentIndex)
        {
            auto Agent = _Agents[AgentIndex];
            auto Queue = _Queue;
            Agent.Request_JoinQueue(Queue);
        }
    }

    UFUNCTION()
    private void Check_InitialRanksClaimed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto ClaimedCount = 0;
        auto HasFront = false;
        auto HasRankOne = false;
        auto HasRankTwo = false;
        for (const auto& Member : _Queue.Get_Members())
        {
            if (Member.Get_State() != ECk_Queue_MemberState::AtFront
                && Member.Get_State() != ECk_Queue_MemberState::AtSlot)
            { continue; }
            ClaimedCount += 1;
            if (Member.Get_Rank() == 0)
            {
                HasFront = true;
                _FirstFrontLocation = Member.Get_TargetWorldTransform().GetLocation();
                _FirstServed = FindAgent(Member.Get_Member());
            }
            else if (Member.Get_Rank() == 1) { HasRankOne = true; }
            else if (Member.Get_Rank() == 2) { HasRankTwo = true; }
        }
        auto Result = OutResult;
        Result.Set(ClaimedCount == 3 && HasFront && HasRankOne && HasRankTwo && ck::IsValid(_FirstServed));
    }

    UFUNCTION()
    private void Step_RequestFirstAdvance(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Queue.Request_Advance(FCk_Request_Queue_Advance(),
            FCk_Delegate_Request_OnCompleted(this, n"OnAdvanceCompleted"));
    }

    UFUNCTION()
    private void Check_FirstAdvanceCompleted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_AdvanceCompletions == 1 && _FirstAdvanceResult == ECk_Request_OperationResult::Succeeded
            && _Queue.Get_MemberCount() == 2 && _Queue.Get_IsMember(FCk_Handle(_FirstServed)) == false);
    }

    UFUNCTION()
    private void Step_ClearFirstServedWithTransform(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _FirstExitGoal = _FirstFrontLocation + FVector(0.0f, 400.0f, 0.0f);
        utils_transform::Request_SetLocation(
            _FirstServed.As_Transform(), _FirstExitGoal, ECk_LocalWorld::World);
    }

    UFUNCTION()
    private void Check_FirstServedCleared(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        const auto Position = utils_transform::Get_EntityCurrentLocation(_FirstServed.As_Transform());
        auto Result = OutResult;
        Result.Set(Position.Equals(_FirstExitGoal, 1.0f)
            && float((Position - _FirstFrontLocation).Size()) > 300.0f);
    }

    UFUNCTION()
    private void Check_SurvivorReachedFront(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _SecondFront = FCk_Handle_CrowdAgent();
        for (const auto& Member : _Queue.Get_Members())
        {
            if (Member.Get_Rank() == 0 && Member.Get_State() == ECk_Queue_MemberState::AtFront)
            {
                _SecondFront = FindAgent(Member.Get_Member());
                break;
            }
        }
        auto Result = OutResult;
        Result.Set(ck::IsValid(_SecondFront) && _SecondFront != _FirstServed);
    }

    UFUNCTION()
    private void Step_RequestSecondAdvance(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Queue.Request_Advance(FCk_Request_Queue_Advance(),
            FCk_Delegate_Request_OnCompleted(this, n"OnAdvanceCompleted"));
    }

    UFUNCTION()
    private void Check_SecondAdvanceCompleted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_AdvanceCompletions == 2 && _SecondAdvanceResult == ECk_Request_OperationResult::Succeeded
            && _Queue.Get_MemberCount() == 1 && _Queue.Get_IsMember(FCk_Handle(_SecondFront)) == false);
    }

    UFUNCTION()
    private void Step_AssertPostAdvanceProgress(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_FirstAdvanceResult == ECk_Request_OperationResult::Succeeded,
            "the first real Crowd-backed ClaimFirst advance succeeds");
        Assert_True(_SecondAdvanceResult == ECk_Request_OperationResult::Succeeded,
            "a survivor reaches AtFront and permits a second advance without a manual movement outcome");
        Assert_Equals_Int(_Queue.Get_MemberCount(), 1,
            "two successful advances remove exactly two of the three Crowd-backed members");
    }

    private FCk_Handle_CrowdAgent CreateCrowdAgent(FCk_Handle InOwner, FVector InLocation)
    {
        auto Entity = utils_entity_lifetime::Request_CreateEntity(InOwner);
        auto Transform = utils_transform::Add(Entity,
            FTransform(FRotator::ZeroRotator, InLocation, FVector::OneVector), ECk_Replication::DoesNotReplicate);
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(k_AgentRadiusUu, 192.0f);
        Params.Set_MaxSpeed(600.0f);
        auto Agent = utils_crowd_agent::Add(Transform, Params);
        utils_velocity::Add(Entity,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(Entity,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(Entity);
        return Agent;
    }

    private FCk_Handle_CrowdAgent FindAgent(FCk_Handle InMember) const
    {
        for (auto Agent : _Agents)
        {
            if (FCk_Handle(Agent) == InMember) { return Agent; }
        }
        return FCk_Handle_CrowdAgent();
    }
}
