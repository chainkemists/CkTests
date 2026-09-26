// Language=angelscript

// PaViz telemetry on the first stress courses: the step field, the ledge, the sharp ridge and the spin in place (each
// walker turns in place for 6 s, then walks the flat course). The recorder (CkPaViz_TelemetryRecorder.as) traces the
// [PAVIZ] lines; the data is the product, so the test passes once the sequence completes.
class UCk_AutoTest_PaViz_StressTelemetryA : UCk_AutoTest_Base
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
        auto Created = DoAdd_StressFixture(InHandle, "StepField", ECkProceduralAnimationGym_Course::StepField, FVector(120000.0, 150000.0, 600.0));
        Created = DoAdd_StressFixture(InHandle, "Ledge", ECkProceduralAnimationGym_Course::Ledge, FVector(120000.0, 155000.0, 600.0)) && Created;
        Created = DoAdd_StressFixture(InHandle, "Ridge", ECkProceduralAnimationGym_Course::Ridge, FVector(120000.0, 160000.0, 600.0)) && Created;
        Created = DoAdd_StressFixture(InHandle, "Spin", ECkProceduralAnimationGym_Course::Spin, FVector(120000.0, 165000.0, 600.0)) && Created;
        if (Created == false)
        {
            FinishFailure("The isolated step field, ledge, ridge and spin fixtures could not be created");
            return;
        }
        Add_Step_WaitUntil("every walker on the step field, ledge, ridge and spin courses is composed and evaluated", n"Check_Ready", 1200, 30.0f);
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
