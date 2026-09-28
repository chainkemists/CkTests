// Language=angelscript

// PaViz telemetry on the hump, stairs, uneven and rubble courses, and body-pose spring steps on the rear legs of a beast
// that walks a flat course without conform. The recorder (CkPaViz_TelemetryRecorder.as) traces the [PAVIZ] lines; the data is the product, so the test passes
// once the sequence completes.
class UCk_AutoTest_PaViz_Telemetry : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 75.0f;
    default _AutoStageOriginField = false;
    private FCkPaViz_TelemetryRecorder _Recorder;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Created = _Recorder.Add_Fixture(InHandle, "Hump", ECkProceduralAnimationGym_Course::Hump, FVector(120000.0, 120000.0, 600.0),
            ck_paviz_telemetry::MakeRoster(ECkProceduralAnimationGym_Species::Tentacled, ECkProceduralAnimationGym_Species::Spider,
                ECkProceduralAnimationGym_Species::Beast));
        Created = _Recorder.Add_Fixture(InHandle, "Stairs", ECkProceduralAnimationGym_Course::Stairs, FVector(120000.0, 125000.0, 600.0),
            ck_paviz_telemetry::MakeRoster(ECkProceduralAnimationGym_Species::Tentacled, ECkProceduralAnimationGym_Species::Spider,
                ECkProceduralAnimationGym_Species::Beast)) && Created;
        Created = _Recorder.Add_Fixture(InHandle, "Uneven", ECkProceduralAnimationGym_Course::Uneven, FVector(120000.0, 135000.0, 600.0),
            ck_paviz_telemetry::MakeRoster(ECkProceduralAnimationGym_Species::Crawler4, ECkProceduralAnimationGym_Species::Crawler6,
                ECkProceduralAnimationGym_Species::Crawler8)) && Created;
        Created = _Recorder.Add_Fixture(InHandle, "Rubble", ECkProceduralAnimationGym_Course::Rubble, FVector(120000.0, 140000.0, 600.0),
            ck_paviz_telemetry::MakeRoster(ECkProceduralAnimationGym_Species::Spider, ECkProceduralAnimationGym_Species::Tentacled,
                ECkProceduralAnimationGym_Species::Beast)) && Created;
        auto SpringRoster = TArray<ECkProceduralAnimationGym_Species>();
        SpringRoster.Add(ECkProceduralAnimationGym_Species::Beast);
        Created = _Recorder.Add_Fixture(InHandle, "Flat", ECkProceduralAnimationGym_Course::Flat, FVector(120000.0, 145000.0, 600.0),
            SpringRoster, ECk_ProceduralBodyPose_ConformMode::None) && Created;
        _Recorder.Enable_SpringSteps(4, 0);
        if (Created == false)
        {
            FinishFailure("The isolated hump, stairs, uneven, rubble and flat fixtures could not be created");
            return;
        }
        Add_Step_WaitUntil("every walker on the five courses is composed and evaluated", n"Check_Ready", 1200, 20.0f);
        Add_Step_WaitUntil("every walker passes the turnaround and 34 s pass, or 45 s pass, while each frame is traced", n"Check_Sampled", 0, 48.0f);
        Add_Step("trace the run summary and retire the fixtures", n"Step_Finish");
        Add_Step_WaitUntil("every fixture lifetime subtree is gone", n"Check_Destroyed", 0, 10.0f);
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Ready = _Recorder.Update_Ready();
        if (_Recorder.CompositionError.IsEmpty() == false)
        {
            FinishFailure(f"A walker could not be composed: '{_Recorder.CompositionError}'");
            return;
        }
        auto Result = OutResult;
        Result.Set(Ready);
    }

    UFUNCTION()
    private void Check_Sampled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Recorder.Update_Sampled());
    }

    UFUNCTION()
    private void Step_Finish(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Recorder.Finish();
    }

    UFUNCTION()
    private void Check_Destroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Recorder.Get_IsDestroyed());
    }
}
