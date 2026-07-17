// Language=angelscript

//============================================================================
// CK JOLT — AUTOMATION TEST: RESTING BODY SLEEPS, WAKE REQUEST REACTIVATES
//============================================================================
//
// Jolt puts a settled dynamic body to sleep; the JoltBody sleep-state mirror
// must reflect that on the tag-level Get_SleepState, and a Request_SetSleepState
// (Awake) must reactivate it promptly.
//
//   1. Static floor + a Dynamic box dropped onto it.
//   2. Poll Get_SleepState until it reports Asleep (Jolt's sleep timer needs
//      ~0.5s of sub-threshold motion — generous budget).
//   3. Request_SetSleepState(Awake).
//   4. Assert Get_SleepState reports Awake within 2 polls.
//
// Signal-level sleep/wake coverage is Phase 4 — this pins only the tag-level
// state and the wake request. Placed at an isolated Y from other autotests.
//============================================================================

class UCk_AutoTest_CkJolt_RestingBodySleepsAndWakeRequestReactivates : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 25.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_JoltBody _Body;

    private FVector _FloorCenter = FVector(0.0, 42000.0, 0.0);

    private int _Phase = 0;   // 0 = waiting to sleep, 1 = waiting to wake
    private int _FramesWaited = 0;
    private int _PollsSinceWake = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        // ---- Static floor ---------------------------------------------------------------------
        auto FloorEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        FloorEntity.Request_OverrideToSelf();
        utils_transform::Add(FloorEntity, FTransform(FRotator::ZeroRotator, _FloorCenter),
            ECk_Replication::DoesNotReplicate);

        auto FloorShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        FloorShape.Set_HalfExtents(FVector(500.0, 500.0, 25.0));
        auto FloorParams = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        FloorParams.Set_ShapeDimensions(FloorShape);
        FloorParams.Set_MotionType(ECk_MotionType::Static);
        utils_jolt_body::Add(FloorEntity, FloorParams);

        // ---- Dynamic box dropped a short distance so it settles quickly -----------------------
        auto BoxStart = _FloorCenter + FVector(0.0, 0.0, 120.0);
        auto BoxEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        BoxEntity.Request_OverrideToSelf();
        utils_transform::Add(BoxEntity, FTransform(FRotator::ZeroRotator, BoxStart),
            ECk_Replication::DoesNotReplicate);

        auto BoxShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        BoxShape.Set_HalfExtents(FVector(50.0, 50.0, 50.0));
        auto BoxParams = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        BoxParams.Set_ShapeDimensions(BoxShape);
        BoxParams.Set_MotionType(ECk_MotionType::Dynamic);
        _Body = utils_jolt_body::Add(BoxEntity, BoxParams);

        utils_timer::Create_Tick(_SelfHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _FramesWaited++;

        if (_Phase == 0)
        {
            if (utils_jolt_body::Get_SleepState(_Body) == ECk_Jolt_SleepState::Asleep)
            {
                // Request reactivation and start the tight wake-latency window.
                utils_jolt_body::Request_SetSleepState(_Body,
                    FCk_Request_JoltBody_SetSleepState(ECk_Jolt_SleepState::Awake));
                _PollsSinceWake = 0;
                _Phase = 1;
                return;
            }

            if (_FramesWaited > 900)
            { FinishFailure(f"Resting body never slept after {_FramesWaited} frames"); }

            return;
        }

        // Phase 1 — the body must report Awake within 2 polls of the wake request.
        _PollsSinceWake++;

        if (utils_jolt_body::Get_SleepState(_Body) == ECk_Jolt_SleepState::Awake)
        {
            FinishSuccess();
            return;
        }

        if (_PollsSinceWake > 2)
        { FinishFailure(f"Body did not wake within 2 polls of Request_SetSleepState(Awake)"); }
    }
}
