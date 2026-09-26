// Language=angelscript

// PaViz telemetry on the second stress courses (the log, the beams and the pillar field) and on the ramp-to-wall and
// closed-loop courses with the 4, 6 and 8-leg crawlers, where the body turns fastest and its attitude lag is largest. The
// recorder (CkPaViz_TelemetryRecorder.as) traces the [PAVIZ] lines; the data is the product, so the test passes once the
// sequence completes.
class UCk_AutoTest_PaViz_StressTelemetryB : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 90.0f;
    default _AutoStageOriginField = false;
    private FCkPaViz_TelemetryRecorder _Recorder;

    private bool DoAdd_StressFixture(FCk_Handle InOwner, FString InName, ECkProceduralAnimationGym_Course InCourse, FVector InOrigin)
    {
        return _Recorder.Add_Fixture(InOwner, InName, InCourse, InOrigin, ck_procedural_gym::Get_StressRoster(InCourse));
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Created = DoAdd_StressFixture(InHandle, "Log", ECkProceduralAnimationGym_Course::Log, FVector(120000.0, 170000.0, 600.0));
        Created = DoAdd_StressFixture(InHandle, "Beam", ECkProceduralAnimationGym_Course::Beam, FVector(120000.0, 175000.0, 600.0)) && Created;
        Created = DoAdd_StressFixture(InHandle, "Pillars", ECkProceduralAnimationGym_Course::Pillars, FVector(120000.0, 180000.0, 600.0)) && Created;
        Created = _Recorder.Add_CrawlerFixture(InHandle, "RampWall", ECkProceduralAnimationGym_Course::RampWall, FVector(120000.0, 185000.0, 600.0)) && Created;
        Created = _Recorder.Add_CrawlerFixture(InHandle, "Ring", ECkProceduralAnimationGym_Course::Ring, FVector(120000.0, 190000.0, 600.0)) && Created;
        if (Created == false)
        {
            FinishFailure("The isolated log, beam, pillar, ramp-to-wall and closed-loop fixtures could not be created");
            return;
        }
        Add_Step_WaitUntil("every walker on the log, beam, pillar, ramp-to-wall and closed-loop courses is composed and evaluated", n"Check_Ready",
            1200, 30.0f);
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
