// Language=angelscript

//============================================================================
// CK JOLT — AUTOMATION TEST: RESTING BODY SLEEPS, WAKE REQUEST REACTIVATES
//============================================================================
//
// Jolt puts a settled dynamic body to sleep; CkJolt must raise
// OnJoltBodySleepStateChanged on the sleep edge, and a Request_SetSleepState(Awake)
// must raise the wake edge and reactivate the body:
//
//   1. Static floor + a Dynamic box dropped onto it.
//   2. PRIMARY: an OnJoltBodySleepStateChanged(Asleep) signal fires once the body
//      settles (Jolt's sleep timer needs ~0.5s of sub-threshold motion). SECONDARY:
//      the tag-level Get_SleepState mirror also reads Asleep.
//   3. Request_SetSleepState(Awake) -> PRIMARY: an OnJoltBodySleepStateChanged(Awake)
//      signal fires; SECONDARY: Get_SleepState reads Awake.
//
// Placed at an isolated Y from other autotests.
//============================================================================

class UCk_AutoTest_CkJolt_RestingBodySleepsAndWakeRequestReactivates : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 25.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_JoltBody _Body;

    private FVector _FloorCenter = FVector(0.0, 42000.0, 0.0);

    private int _Phase = 0;   // 0 = waiting to sleep, 1 = waiting to wake
    private float _Elapsed = 0.0;
    private float _ElapsedSinceWake = 0.0;

    private bool _AsleepSignalFired = false;
    private bool _AwakeSignalAfterWake = false;

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
        auto FloorParams = FCk_JoltBody_Spec(ECk_JoltBody_ShapeSource::ExplicitShape);
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
        auto BoxParams = FCk_JoltBody_Spec(ECk_JoltBody_ShapeSource::ExplicitShape);
        BoxParams.Set_ShapeDimensions(BoxShape);
        BoxParams.Set_MotionType(ECk_MotionType::Dynamic);
        _Body = utils_jolt_body::Add(BoxEntity, BoxParams);

        utils_jolt_body::BindTo_OnJoltBodySleepStateChanged(_Body,
            FCk_Delegate_JoltBody_OnSleepStateChanged(this, n"OnSleepStateChanged"));

        utils_timer::Create_Tick(_SelfHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnSleepStateChanged(FCk_Handle_JoltBody InHandle, ECk_Jolt_SleepState InSleepState)
    {
        if (IsFinished()) { return; }

        if (_Phase == 0)
        {
            if (InSleepState == ECk_Jolt_SleepState::Asleep)
            { _AsleepSignalFired = true; }
        }
        else if (InSleepState == ECk_Jolt_SleepState::Awake)
        {
            _AwakeSignalAfterWake = true;
        }
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _Elapsed += float(InDeltaT.Get_Seconds());

        if (_Phase == 0)
        {
            // PRIMARY: the sleep edge must arrive via the signal.
            if (_AsleepSignalFired)
            {
                // SECONDARY: the tag-level mirror agrees.
                Assert_True(utils_jolt_body::Get_SleepState(_Body) == ECk_Jolt_SleepState::Asleep,
                    "Tag-level Get_SleepState should also read Asleep once the sleep signal has fired");

                utils_jolt_body::Request_SetSleepState(_Body,
                    FCk_Request_JoltBody_SetSleepState(ECk_Jolt_SleepState::Awake));
                _ElapsedSinceWake = 0.0;
                _Phase = 1;
                return;
            }

            if (_Elapsed > 15.0)
            { FinishFailure(f"Resting body never raised an Asleep sleep-state signal after {_Elapsed} seconds"); }

            return;
        }

        // Phase 1 — the wake request must raise an Awake signal and reactivate the body.
        _ElapsedSinceWake += float(InDeltaT.Get_Seconds());

        if (_AwakeSignalAfterWake)
        {
            Assert_True(utils_jolt_body::Get_SleepState(_Body) == ECk_Jolt_SleepState::Awake,
                "Tag-level Get_SleepState should read Awake after the wake signal has fired");
            FinishSuccess();
            return;
        }

        if (_ElapsedSinceWake > 0.25)
        { FinishFailure("Body did not raise an Awake sleep-state signal after Request_SetSleepState(Awake)"); }
    }
}
