// Language=angelscript

//============================================================================
// CK ISKM RENDERER — PERF READOUT AUTOTESTS (batched crowd vs per-SKMC)
//============================================================================
//
// Measured (not estimated) frame-time readouts, logged for A/B comparison:
//   - BatchedPerf: 600 batched GPU-skinned members, ALL moving every tick (the worst-case production write
//     path — per-frame member transform writes + tile migrations), driven by the same
//     UCk_EntityScript_IskmRendererBatched_MovingCrowd class the gyms use.
//   - SkmcPerf:    150 per-SKMC Plan-1 proxies, moving (UCk_EntityScript_IskmRendererGym_StressArmy).
//
// Each warms up (WarmupSeconds), then samples per-tick delta time for SampleSeconds and logs
// avg / max frame ms + effective FPS. Under --no-nullrhi this includes real render submission; under
// -nullrhi it still measures the game-thread crowd-driver cost. The numbers are RELATIVE (same harness,
// same machine) — compare the two tests' logs, and normalize per instance (600 vs 150).
//
// No pass/fail threshold on timing (machine-dependent); the tests fail only on setup failure.
//============================================================================

class UCk_AutoTest_IskmRenderer_BatchedPerf : UCk_AutoTest_Base
{
    private float _Elapsed = 0.0f;
    private float _SampleSum = 0.0f;
    private float _SampleMax = 0.0f;
    private int32 _SampleCount = 0;

    const float WarmupSeconds = 3.0f;
    const float SampleSeconds = 6.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Collection = iskm_assets::AnimCollection_Demo();
        if (ck::Is_NOT_Valid(Collection))
        {
            FinishFailure("iskm_assets::AnimCollection_Demo() invalid — registry may need regeneration.");
            return;
        }

        // Uncap so deltas measure work, not vsync.
        System::ExecuteConsoleCommand("t.MaxFPS 0");
        System::ExecuteConsoleCommand("r.VSync 0");

        // 600 moving batched members via the same parameterized station class the stress gym uses.
        auto Params = FCkIskmBatchedGym_CrowdSpawnParams();
        Params.InitialTransform = FTransform(FVector(0.0f, 0.0f, 100.0f));
        Params.Count = 600;
        Params.AreaExtent = 6000.0f;
        Params.TileSize = 2500.0f;
        utils_entity_script::Request_SpawnEntity(InHandle, UCk_EntityScript_IskmRendererBatched_MovingCrowd, FInstancedStruct::Make(Params));

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
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
        Log(f"[CkIskm PERF][Batched moving 600] frames={_SampleCount} avg={AvgMs} ms  max={MaxMs} ms  fps={Fps}");
        FinishSuccess();
    }
}

class ACk_AutoTest_IskmRenderer_BatchedPerf_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_IskmRenderer_BatchedPerf;
    default _TimeoutSeconds = 45.0f;
}

class UCk_AutoTest_IskmRenderer_SkmcPerf : UCk_AutoTest_Base
{
    private float _Elapsed = 0.0f;
    private float _SampleSum = 0.0f;
    private float _SampleMax = 0.0f;
    private int32 _SampleCount = 0;

    const float WarmupSeconds = 3.0f;
    const float SampleSeconds = 6.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto RendererData = iskm_assets::RendererData_Demo();
        if (ck::Is_NOT_Valid(RendererData))
        {
            FinishFailure("iskm_assets::RendererData_Demo() invalid — registry may need regeneration.");
            return;
        }

        System::ExecuteConsoleCommand("t.MaxFPS 0");
        System::ExecuteConsoleCommand("r.VSync 0");

        // 150 per-SKMC moving proxies via the existing Plan-1 stress station class.
        auto Params = FCkIskmRenderer_GymStationSpawnParams();
        Params.InitialTransform = FTransform(FVector(0.0f, 0.0f, 100.0f));
        Params.Count = 150;
        Params.Moving = true;
        utils_entity_script::Request_SpawnEntity(InHandle, UCk_EntityScript_IskmRendererGym_StressArmy, FInstancedStruct::Make(Params));

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
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
        Log(f"[CkIskm PERF][SKMC moving 150] frames={_SampleCount} avg={AvgMs} ms  max={MaxMs} ms  fps={Fps}");
        FinishSuccess();
    }
}

class ACk_AutoTest_IskmRenderer_SkmcPerf_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_IskmRenderer_SkmcPerf;
    default _TimeoutSeconds = 45.0f;
}
