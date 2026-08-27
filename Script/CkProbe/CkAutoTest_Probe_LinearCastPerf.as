// Language=angelscript

//============================================================================
// CK PROBE - PERF READOUT AUTOTEST (LinearCast sweep fleet)
//============================================================================
//
// Measured (not estimated) frame-time readout for the LinearCast pipeline:
// 200 LinearCast kinematic sphere probes ping-pong along X in separate
// Y-lanes, crossing a line of static wall probes every cycle - so every
// frame pays 200 shape casts plus periodic begin/update/end overlap churn.
//
// Warms up (WarmupSeconds), samples per-tick delta for SampleSeconds, then
// logs avg / max frame ms + effective FPS. Under -nullrhi this measures the
// game-thread cost - exactly where FProcessor_Probe_UpdateTransform_LinearCast
// runs. Numbers are RELATIVE (same harness, same machine): compare logs from
// before/after a change to the LinearCast processor.
//
// No pass/fail threshold on timing (machine-dependent); fails only on setup.
//============================================================================

namespace ck_probe_linearcast_perf
{
    asset Asset_ProbeLinearCastPerf_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"CkTests.Probe.LinearCastPerf.Wall");
        GameplayTags.Add(n"CkTests.Probe.LinearCastPerf.Mover");
    }
}

class UCk_AutoTest_Probe_LinearCastPerf : UCk_AutoTest_Base
{
    private TArray<FCk_Handle_Transform> _Movers;
    private TArray<float> _Directions;

    private float _Elapsed = 0.0f;
    private float _SampleSum = 0.0f;
    private float _SampleMax = 0.0f;
    private int32 _SampleCount = 0;

    // Sized to SATURATE the headless 120fps frame budget (~8.33 ms) in the serial
    // implementation - below saturation, frame deltas measure the frame cap, not the work.
    const int32 MoverCount = 800;
    const int32 WallEvery = 4;          // every 4th lane gets a static wall at X=500
    const float StepPerTick = 40.0f;
    const float TurnaroundX = 800.0f;
    const float WarmupSeconds = 3.0f;
    const float SampleSeconds = 6.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        // Uncap so deltas measure work, not vsync.
        Set_CVarForTest(n"t.MaxFPS", "0");
        Set_CVarForTest(n"r.VSync", "0");

        auto WallTag = utils_gameplay_tag::ResolveGameplayTag(n"CkTests.Probe.LinearCastPerf.Wall");
        auto MoverTag = utils_gameplay_tag::ResolveGameplayTag(n"CkTests.Probe.LinearCastPerf.Mover");

        auto MoverFilter = FGameplayTagContainer();
        MoverFilter.AddTag(WallTag);

        for (int32 i = 0; i < MoverCount; i++)
        {
            const float LaneY = float(i) * 100.0f;

            // ---- Mover: LinearCast kinematic sphere ----
            auto Mover = utils_entity_lifetime::Request_CreateEntity(InHandle);
            Mover.Request_OverrideToSelf();
            auto MoverTransform = utils_transform::Add(
                Mover, FTransform(FRotator::ZeroRotator, FVector(0.0, LaneY, 300.0)), ECk_Replication::DoesNotReplicate);

            auto MoverParams = FCk_Fragment_Probe_ParamsData(MoverTag);
            MoverParams.Set_MotionType(ECk_MotionType::Kinematic);
            MoverParams.Set_MotionQuality(ECk_MotionQuality::LinearCast);
            MoverParams.Set_ResponsePolicy(ECk_ProbeResponse_Policy::Notify);
            MoverParams.Set_Filter(MoverFilter);
            utils_probe::Add_Sphere(MoverTransform, 25.0, MoverParams, FCk_Probe_DebugInfo());

            _Movers.Add(MoverTransform);
            _Directions.Add(1.0f);

            // ---- Wall: static sphere probe on every WallEvery-th lane ----
            if (i % WallEvery == 0)
            {
                auto Wall = utils_entity_lifetime::Request_CreateEntity(InHandle);
                Wall.Request_OverrideToSelf();
                auto WallTransform = utils_transform::Add(
                    Wall, FTransform(FRotator::ZeroRotator, FVector(500.0, LaneY, 300.0)), ECk_Replication::DoesNotReplicate);

                auto WallParams = FCk_Fragment_Probe_ParamsData(WallTag);
                WallParams.Set_MotionType(ECk_MotionType::Static);
                WallParams.Set_ResponsePolicy(ECk_ProbeResponse_Policy::Silent);
                utils_probe::Add_Sphere(WallTransform, 200.0, WallParams, FCk_Probe_DebugInfo());
            }
        }

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // Drive every mover every tick (constant across A/B - the same request volume is
        // issued whichever processor implementation is under test).
        for (int32 i = 0; i < _Movers.Num(); i++)
        {
            auto CurrentX = utils_transform::Get_EntityCurrentLocation(_Movers[i]).X;
            if (CurrentX > TurnaroundX) { _Directions[i] = -1.0f; }
            else if (CurrentX < -TurnaroundX) { _Directions[i] = 1.0f; }

            utils_transform::Request_AddLocationOffset(
                _Movers[i], FVector(StepPerTick * _Directions[i], 0.0, 0.0), ECk_LocalWorld::World);
        }

        const float Dt = float(InDeltaT.Get_Seconds());
        _Elapsed += Dt;

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
        Log(f"[CkProbe PERF][LinearCast movers={MoverCount}] frames={_SampleCount} avg={AvgMs} ms  max={MaxMs} ms  fps={Fps}");
        FinishSuccess();
    }
}

class ACk_AutoTest_Probe_LinearCastPerf_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Probe_LinearCastPerf;
    default _TimeoutSeconds = 45.0f;
}
