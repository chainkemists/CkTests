// Language=angelscript
//============================================================================
// CK NAVIGATION - AUTOMATION TEST: WHAT A REFERENCE POPULATION OF PATH QUERIES COSTS
//============================================================================
//
// A measurement, not a contract. The product target is a little over a hundred simultaneous
// agents, so the interesting question about the Recast path service is not whether one query
// answers - it is what happens when every agent asks at once against a per-frame drain budget
// of UCk_Utils_Nav_Settings_UE::Get_MaxPathQueriesPerFrame().
//
// 128 entities are placed on the level floor and each issues one FindPath across it in the SAME
// frame. What is then recorded, once per frame, is how many of them reached a terminal status
// that frame. That yields three numbers a budget can be reasoned about from: how many frames the
// whole population took to drain, how many queries actually completed per frame against the
// configured budget, and - from the result's own diagnostics - the wall time a single Recast
// search took, separate from the frames it waited in the queue.
//
// The assertions are sanity bounds only: every query must reach a terminal status inside a
// generous window, and the population must not have been made of failures (a run where nothing
// pathed would satisfy every count in here while measuring nothing). Anything tighter would be
// asserting the numbers this test exists to discover - and in particular the completions-per-frame
// figure is a SAMPLE: the per-frame poll has no contracted position within the frame relative to
// the nav processor, so it is reported and never asserted on.
//
// Everything spawned here is released and destroyed before the test finishes - the PIE world is
// shared with every other autotest.
//============================================================================

class UCk_AutoTest_NavSurface_RecastBudgets_PathThroughput : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 60.0f;

    // The product target is ~110-130 simultaneous agents; 128 sits in that band.
    private const int32 AgentCount = 128;

    // 128 queries at a default budget of 8/frame drain in ~16 frames. 600 is far enough above
    // that to survive a slow headless frame without becoming a second, hidden timeout.
    private const int32 DrainFrameBudget = 600;

    // Query endpoints stay inside the rim by this fraction, so a start or goal is never sitting
    // on the eroded edge of the navmesh where projection is the variable under test.
    private const float RimInset = 0.9;

    private const float GoldenAngleRad = 2.39996323;
    private const float ProjectionExtentUu = 300.0;
    private const float ProjectionVerticalExtentUu = 500.0;

    private FVector _FloorOrigin = FVector::ZeroVector;
    private FVector _FloorExtent = FVector::ZeroVector;
    private FVector _RimOrigin = FVector::ZeroVector;
    private FVector _RimExtent = FVector::ZeroVector;

    private TArray<FCk_Handle> _Agents;
    private TArray<FVector> _Goals;

    // Frames since the issue frame at which each agent's slot went terminal; -1 while in flight.
    private TArray<int32> _LatencyFrames;

    // Terminal completions observed in each sampled frame, in order.
    private TArray<int32> _PerFrameCompletions;

    private int32 _Budget = 0;
    private int64 _IssueFrame = 0;
    private int64 _LastSampledFrame = -1;
    private int32 _CompletedCount = 0;
    private int32 _ReadyCount = 0;
    private int32 _FailedCount = 0;
    private int32 _PartialCount = 0;

    private float32 _QueryMsTotal = 0.0f;
    private float32 _QueryMsMin = 100000.0f;
    private float32 _QueryMsMax = 0.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step_WaitUntil("the nav surface provider settles at Ready",   n"Check_ProviderIsReady", 900);
        Add_Step(          "find the level floor and its rectangle",      n"Step_FindFloor");
        Add_Step(          "ask the provider and the navmesh to build",   n"Step_KickRebuild");
        Add_Step_WaitUntil("the floor projects onto a built navmesh",     n"Check_FloorProjects", 900);
        Add_Step(          "place the agents on the surface",             n"Step_PlaceAgents");
        Add_Step(          "issue every path query in one frame",         n"Step_IssueQueries");
        Add_Step_WaitUntil("every query reaches a terminal status",       n"Check_AllTerminal", DrainFrameBudget);
        Add_Step(          "report what the population cost",             n"Step_Report");
        Add_Step(          "release every path and destroy every agent",  n"Step_Cleanup");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_ProviderIsReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_nav_surface::Get_ProviderHealth() == ECk_NavSurface_ProviderHealth::Ready);
    }

    UFUNCTION()
    private void Step_FindFloor(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Floor = assets::StaticMeshActor_1().Get();

        if (!System::IsValid(Floor))
        {
            FinishFailure("staging failed: the level floor StaticMeshActor_1 could not be reached - the fixture, not the path service, is broken");
            return;
        }

        Floor.GetActorBounds(false, _FloorOrigin, _FloorExtent);

        auto Volume = assets::NavMeshBoundsVolume_1().Get();

        if (!System::IsValid(Volume))
        {
            FinishFailure("staging failed: the level nav bounds volume NavMeshBoundsVolume_1 could not be reached - the fixture, not the path service, is broken");
            return;
        }

        auto VolumeOrigin = FVector::ZeroVector;
        auto VolumeExtent = FVector::ZeroVector;
        Volume.GetActorBounds(false, VolumeOrigin, VolumeExtent);

        const auto FloorMin = _FloorOrigin - _FloorExtent;
        const auto FloorMax = _FloorOrigin + _FloorExtent;
        const auto VolumeMin = VolumeOrigin - VolumeExtent;
        const auto VolumeMax = VolumeOrigin + VolumeExtent;

        const auto RimMin = FVector(Math::Max(FloorMin.X, VolumeMin.X), Math::Max(FloorMin.Y, VolumeMin.Y), FloorMin.Z);
        const auto RimMax = FVector(Math::Min(FloorMax.X, VolumeMax.X), Math::Min(FloorMax.Y, VolumeMax.Y), FloorMax.Z);

        _RimOrigin = (RimMin + RimMax) * 0.5;
        _RimExtent = (RimMax - RimMin) * 0.5;

        _Budget = utils_nav_settings::Get_MaxPathQueriesPerFrame();

        ck::nav::Display(f"[RECAST-BUDGET] throughput fixture: rim origin={_RimOrigin} extent={_RimExtent} | agents={AgentCount} | MaxPathQueriesPerFrame={_Budget}");

        if (_RimExtent.X <= 0.0 || _RimExtent.Y <= 0.0)
        {
            FinishFailure(f"staging failed: the floor and the surface bounds do not overlap (rim extent {_RimExtent})");
            return;
        }
    }

    // A fresh session reports the provider Ready before it holds any tiles, so both the surface
    // and the navmesh are asked for explicitly and then waited for as the condition they are -
    // the floor projecting - rather than assumed from the health alone.
    UFUNCTION()
    private void Step_KickRebuild(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto LocalHandle = InHandle;

        utils_nav_surface::Request_SurfaceRebuild_ForTesting();
        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);
    }

    // Projection through utils_nav, not the surface API: this is the projection FindPath itself
    // performs on a start and a goal, so it is the readiness that actually gates the measurement.
    // Both the centre and a rim corner are probed, because a partial bake can cover one and not
    // the other, and every query below runs between two such points.
    UFUNCTION()
    private void Check_FloorProjects(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        auto Snapped = FVector::ZeroVector;

        const auto FloorTopZ = _FloorOrigin.Z + _FloorExtent.Z;
        const auto Centre = FVector(_RimOrigin.X, _RimOrigin.Y, FloorTopZ);
        const auto Corner = FVector(
            _RimOrigin.X + _RimExtent.X * RimInset,
            _RimOrigin.Y + _RimExtent.Y * RimInset,
            FloorTopZ);

        if (utils_nav::Try_ProjectOntoNavmesh(InHandle, Centre, float32(ProjectionExtentUu), Snapped, float32(ProjectionVerticalExtentUu)) == false)
        {
            Res.Set(false);
            return;
        }

        Res.Set(utils_nav::Try_ProjectOntoNavmesh(InHandle, Corner, float32(ProjectionExtentUu), Snapped, float32(ProjectionVerticalExtentUu)));
    }

    // Deterministic, seedless placement: a golden-angle spiral spreads the population over the
    // rim without a random generator, so two runs measure the same 128 queries. Each agent's goal
    // is the spiral point half a population away, which puts every query across the floor rather
    // than between neighbours.
    private FVector Get_SpiralPoint(int32 InIndex) const
    {
        const auto Angle = float(InIndex) * GoldenAngleRad;
        const auto Radius = Math::Sqrt((float(InIndex) + 0.5) / float(AgentCount));

        return FVector(
            _RimOrigin.X + Math::Cos(Angle) * Radius * _RimExtent.X * RimInset,
            _RimOrigin.Y + Math::Sin(Angle) * Radius * _RimExtent.Y * RimInset,
            _FloorOrigin.Z + _FloorExtent.Z);
    }

    UFUNCTION()
    private void Step_PlaceAgents(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto LocalHandle = InHandle;
        const auto GoalStride = Math::IntegerDivisionTrunc(AgentCount, 2);

        for (auto Index = 0; Index < AgentCount; ++Index)
        {
            auto Agent = utils_entity_lifetime::Request_CreateEntity(LocalHandle);

            const auto StartPoint = Get_SpiralPoint(Index);
            const auto GoalPoint = Get_SpiralPoint((Index + GoalStride) % AgentCount);

            auto Start = FVector::ZeroVector;
            if (utils_nav::Try_ProjectOntoNavmesh(Agent, StartPoint, float32(ProjectionExtentUu), Start, float32(ProjectionVerticalExtentUu)) == false)
            {
                FinishFailure(f"staging failed: the start point {StartPoint} for agent {Index} does not project onto the navmesh, so its query would measure a projection failure rather than a search");
                return;
            }

            auto Goal = FVector::ZeroVector;
            if (utils_nav::Try_ProjectOntoNavmesh(Agent, GoalPoint, float32(ProjectionExtentUu), Goal, float32(ProjectionVerticalExtentUu)) == false)
            {
                FinishFailure(f"staging failed: the goal point {GoalPoint} for agent {Index} does not project onto the navmesh, so its query would measure a projection failure rather than a search");
                return;
            }

            utils_transform::Add(Agent,
                FTransform(FRotator::ZeroRotator, Start, FVector::OneVector),
                ECk_Replication::DoesNotReplicate);

            _Agents.Add(Agent);
            _Goals.Add(Goal);
            _LatencyFrames.Add(-1);
        }
    }

    UFUNCTION()
    private void Step_IssueQueries(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _IssueFrame = utils_time::Get_FrameCounter();
        _LastSampledFrame = _IssueFrame - 1;

        for (auto Index = 0; Index < _Agents.Num(); ++Index)
        {
            auto Agent = _Agents[Index];
            utils_nav::Request_FindPath(Agent, FCk_Request_Nav_FindPath(_Goals[Index]));
        }
    }

    // Sampled once per frame - the sequencer polls this every frame, and the frame-counter gate
    // means a second poll in the same frame can never double-count a completion into the
    // per-frame histogram this test exists to produce.
    UFUNCTION()
    private void Check_AllTerminal(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;

        const auto Frame = utils_time::Get_FrameCounter();

        if (Frame > _LastSampledFrame)
        {
            _LastSampledFrame = Frame;

            auto CompletedThisFrame = 0;

            for (auto Index = 0; Index < _Agents.Num(); ++Index)
            {
                if (_LatencyFrames[Index] >= 0)
                { continue; }

                const auto Status = utils_nav::Get_PathStatus(_Agents[Index]);

                if (Status == ECk_Nav_PathStatus::None || Status == ECk_Nav_PathStatus::Pending)
                { continue; }

                _LatencyFrames[Index] = int32(Frame - _IssueFrame);
                ++CompletedThisFrame;

                if (Status == ECk_Nav_PathStatus::Ready)        { ++_ReadyCount; }
                else if (Status == ECk_Nav_PathStatus::Partial) { ++_PartialCount; }
                else                                            { ++_FailedCount; }

                const auto DurationMs = utils_nav::Get_PathResult(_Agents[Index]).Get_Diagnostics().Get_LastQueryDurationMs();
                _QueryMsTotal += DurationMs;
                if (DurationMs < _QueryMsMin)
                { _QueryMsMin = DurationMs; }

                if (DurationMs > _QueryMsMax)
                { _QueryMsMax = DurationMs; }
            }

            _CompletedCount += CompletedThisFrame;
            _PerFrameCompletions.Add(CompletedThisFrame);
        }

        Res.Set(_CompletedCount >= _Agents.Num());
    }

    UFUNCTION()
    private void Step_Report(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        int32 MinLatency = DrainFrameBudget;
        auto MaxLatency = 0;
        auto LatencyTotal = 0;

        for (auto Index = 0; Index < _LatencyFrames.Num(); ++Index)
        {
            const auto Latency = _LatencyFrames[Index];
            if (Latency < 0)
            { continue; }

            if (Latency < MinLatency)
            { MinLatency = Latency; }

            if (Latency > MaxLatency)
            { MaxLatency = Latency; }

            LatencyTotal += Latency;
        }

        const auto DrainFrames = MaxLatency + 1;

        int32 MinPerFrame = AgentCount;
        auto MaxPerFrame = 0;
        auto ActiveFrames = 0;
        FString Histogram = "";

        for (auto Index = 0; Index < _PerFrameCompletions.Num(); ++Index)
        {
            const auto Count = _PerFrameCompletions[Index];
            Histogram += f" {Count}";

            if (Count <= 0)
            { continue; }

            if (Count < MinPerFrame)
            { MinPerFrame = Count; }

            if (Count > MaxPerFrame)
            { MaxPerFrame = Count; }

            ++ActiveFrames;
        }

        const auto Completed = _CompletedCount;
        float32 MeanPerFrame = 0.0f;
        float32 MeanLatency = 0.0f;
        float32 MeanMs = 0.0f;
        float32 MinMs = 0.0f;

        if (ActiveFrames > 0)
        { MeanPerFrame = float32(Completed) / float32(ActiveFrames); }

        if (Completed > 0)
        {
            MeanLatency = float32(LatencyTotal) / float32(Completed);
            MeanMs = _QueryMsTotal / float32(Completed);
            MinMs = _QueryMsMin;
        }

        const auto MaxMs = _QueryMsMax;
        const auto Budget = _Budget;

        ck::nav::Display(f"[RECAST-BUDGET] drain of {Completed}/{AgentCount} queries took {DrainFrames} frames: ready={_ReadyCount} partial={_PartialCount} failed={_FailedCount}");
        ck::nav::Display(f"[RECAST-BUDGET] completions per frame over {ActiveFrames} active frames: min={MinPerFrame} max={MaxPerFrame} mean={MeanPerFrame :.2} vs MaxPathQueriesPerFrame={Budget}");
        ck::nav::Display(f"[RECAST-BUDGET] completions per frame, in order:{Histogram}");
        ck::nav::Display(f"[RECAST-BUDGET] queue latency in frames (queueing included, NOT search cost): min={MinLatency} max={MaxLatency} mean={MeanLatency :.2}");
        ck::nav::Display(f"[RECAST-BUDGET] per-query Recast search time from result diagnostics: min={MinMs :.4}ms max={MaxMs :.4}ms mean={MeanMs :.4}ms");

        Assert_True(Completed == AgentCount,
            f"every issued query must reach a terminal status within {DrainFrameBudget} frames - {Completed} of {AgentCount} did");

        Assert_True(_ReadyCount + _PartialCount > 0,
            f"a population in which every query failed measures nothing about search cost (ready={_ReadyCount} partial={_PartialCount} failed={_FailedCount})");
    }

    UFUNCTION()
    private void Step_Cleanup(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        for (auto Index = 0; Index < _Agents.Num(); ++Index)
        {
            auto Agent = _Agents[Index];
            utils_nav::Request_AbandonPath(Agent, FCk_Request_Nav_AbandonPath(0));
            utils_entity_lifetime::Request_DestroyEntity(Agent);
        }

        _Agents.Reset();
        _Goals.Reset();
    }
}
