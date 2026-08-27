// Language=angelscript

//============================================================================
// CK QUEUE - PERF READOUT (synchronised DistanceThenTicket refresh bursts)
//============================================================================
//
// Five hundred twelve independent ReserveOnFormation queues each admit twelve
// transform-backed members. Every 0.25 seconds, six members in every queue
// switch between near and far positions together, making the timed
// DistanceThenTicket refresh work relevant throughout the warmup and sample.
//
// This measures frame time only: setup failures fail the test, but no timing
// threshold is applied because the readout is machine-dependent.
//============================================================================

class UCk_AutoTest_Queue_ReserveDistanceRefreshPerf : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 45.0f;

    private TArray<FCk_Handle_Queue> _Queues;
    private TArray<FCk_Handle> _Members;
    private TArray<FCk_Handle> _MovingMembers;
    private TArray<FVector> _MovingNearLocations;
    private TArray<FVector> _MovingFarLocations;

    private float _Elapsed = 0.0f;
    private float _RefreshElapsed = 0.0f;
    private float _SampleSum = 0.0f;
    private float _SampleMax = 0.0f;
    private int32 _SampleCount = 0;
    private bool _JoinsRequested = false;
    private bool _BenchmarkStarted = false;
    private bool _MovingMembersNear = false;

    const int32 QueueCount = 512;
    const int32 MembersPerQueue = 12;
    const int32 MovingMembersPerQueue = 6;
    const float RefreshSeconds = 0.25f;
    const float WarmupSeconds = 3.0f;
    const float SampleSeconds = 6.0f;
    const bool PhaseSpreadEnabled = true;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        // Uncap so the sampled delta represents the workload rather than a frame cap.
        Set_CVarForTest(n"t.MaxFPS", "0");
        Set_CVarForTest(n"r.VSync", "0");

        if (SpawnWorkload(InHandle) == false)
        {
            FinishFailure("failed to compose the Queue distance-refresh workload");
            return;
        }

        utils_nav::Request_NavigationRebuild_ForTesting(InHandle);
        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (_BenchmarkStarted == false)
        {
            if (TryStartBenchmark() == false) { return; }
            return;
        }

        const float Dt = float(InDeltaT.Get_Seconds());
        _Elapsed += Dt;
        _RefreshElapsed += Dt;
        if (_RefreshElapsed >= RefreshSeconds)
        {
            _RefreshElapsed = _RefreshElapsed - RefreshSeconds;
            _MovingMembersNear = !_MovingMembersNear;
            ApplySynchronizedMoverRefresh();
        }

        if (_Elapsed <= WarmupSeconds)
        { return; }

        if (_Elapsed <= WarmupSeconds + SampleSeconds)
        {
            _SampleSum += Dt;
            if (Dt > _SampleMax) { _SampleMax = Dt; }
            ++_SampleCount;
            return;
        }

        if (_SampleCount == 0)
        {
            FinishFailure("no frames sampled");
            return;
        }

        const float AvgMs = (_SampleSum / float(_SampleCount)) * 1000.0f;
        const float MaxMs = _SampleMax * 1000.0f;
        const float Fps = float(_SampleCount) / _SampleSum;
        Log(f"[CkQueue PERF][DistanceRefresh queues={QueueCount} members={QueueCount * MembersPerQueue} movers={QueueCount * MovingMembersPerQueue} refresh={RefreshSeconds}s phaseSpread={PhaseSpreadEnabled}] frames={_SampleCount} avg={AvgMs} ms  max={MaxMs} ms  fps={Fps}");
        FinishSuccess();
    }

    private bool SpawnWorkload(FCk_Handle InHandle)
    {
        for (int32 QueueIndex = 0; QueueIndex < QueueCount; ++QueueIndex)
        {
            const FVector QueueLocation = FVector::ZeroVector;
            auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
            utils_transform::Add(Owner,
                FTransform(FRotator::ZeroRotator, QueueLocation, FVector::OneVector),
                ECk_Replication::DoesNotReplicate);

            auto Params = FCk_Fragment_Queue_ParamsData();
            Params.Set_LayoutAlgorithm(ECk_Queue_LayoutAlgorithm::OrthogonalSnake);
            Params.Set_SlotSpacingUu(120.0f);
            Params.Set_AgentRadiusUu(30.0f);
            Params.Set_AgentHalfHeightUu(88.0f);
            Params.Set_HardLimit(MembersPerQueue);
            Params.Set_SlotClaimPolicy(ECk_Queue_SlotClaimPolicy::ReserveOnFormation);
            Params.Set_ReserveAssignmentPolicy(ECk_Queue_ReserveAssignmentPolicy::DistanceThenTicket);
            Params.Set_ReserveAssignmentRefreshSeconds(RefreshSeconds);
            Params.Set_ReserveAssignmentRefreshPhaseSpread(PhaseSpreadEnabled
                ? ECk_EnableDisable::Enable
                : ECk_EnableDisable::Disable);
            Params.Set_ReserveAssignmentHysteresisUu(0.0f);
            auto Queue = utils_queue::Add(Owner, Params);
            if (ck::Is_NOT_Valid(Queue)) { return false; }
            _Queues.Add(Queue);

            for (int32 MemberIndex = 0; MemberIndex < MembersPerQueue; ++MemberIndex)
            {
                const bool IsMoving = MemberIndex < MovingMembersPerQueue;
                const FVector InitialLocation = QueueLocation + FVector(
                    -1600.0f - float(MemberIndex) * 80.0f,
                    float((MemberIndex % 6) - 3) * 100.0f,
                    0.0f);
                const auto Member = utils_entity_lifetime::Request_CreateEntity(InHandle);
                utils_transform::Add(Member,
                    FTransform(FRotator::ZeroRotator, InitialLocation, FVector::OneVector),
                    ECk_Replication::DoesNotReplicate);
                _Members.Add(Member);

                if (IsMoving)
                {
                    _MovingMembers.Add(Member);
                    _MovingNearLocations.Add(QueueLocation + FVector(
                        -100.0f - float(MemberIndex) * 35.0f,
                        float(MemberIndex - 3) * 90.0f,
                        0.0f));
                    _MovingFarLocations.Add(QueueLocation + FVector(
                        -2800.0f - float(MemberIndex) * 125.0f,
                        float(MemberIndex - 3) * 90.0f,
                        0.0f));
                }
            }
        }

        return _Queues.Num() == QueueCount
            && _MovingMembers.Num() == QueueCount * MovingMembersPerQueue;
    }

    private bool TryStartBenchmark()
    {
        if (_JoinsRequested == false)
        {
            for (auto Queue : _Queues)
            {
                if (ck::Is_NOT_Valid(Queue))
                {
                    FinishFailure("a distance-refresh benchmark queue invalidated during setup");
                    return false;
                }
                if (Queue.Get_State() != ECk_Queue_State::Ready) { return false; }
            }

            for (int32 MemberIndex = 0; MemberIndex < _Members.Num(); ++MemberIndex)
            {
                auto Queue = _Queues[Math::IntegerDivisionTrunc(MemberIndex, MembersPerQueue)];
                auto Join = FCk_Request_Queue_Join(_Members[MemberIndex]);
                Join.Set_Mover(_Members[MemberIndex]);
                Queue.Request_Join(Join);
            }
            _JoinsRequested = true;
            return false;
        }

        for (auto Queue : _Queues)
        {
            if (ck::Is_NOT_Valid(Queue))
            {
                FinishFailure("a distance-refresh benchmark queue invalidated during setup");
                return false;
            }
            if (Queue.Get_State() != ECk_Queue_State::Ready || Queue.Get_MemberCount() != MembersPerQueue)
            { return false; }
        }

        _Elapsed = 0.0f;
        _RefreshElapsed = 0.0f;
        _SampleSum = 0.0f;
        _SampleMax = 0.0f;
        _SampleCount = 0;
        _BenchmarkStarted = true;
        return true;
    }

    private void ApplySynchronizedMoverRefresh()
    {
        for (int32 MoverIndex = 0; MoverIndex < _MovingMembers.Num(); ++MoverIndex)
        {
            const FVector Location = _MovingMembersNear
                ? _MovingNearLocations[MoverIndex]
                : _MovingFarLocations[MoverIndex];
            utils_transform::Request_SetLocation(_MovingMembers[MoverIndex], Location, ECk_LocalWorld::World);
        }
    }
}

// Hand-authored wrapper is intentional: warmup plus sample exceeds the standard 5 second timeout.
class ACk_AutoTest_Queue_ReserveDistanceRefreshPerf_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Queue_ReserveDistanceRefreshPerf;
    default _TimeoutSeconds = 45.0f;
}
