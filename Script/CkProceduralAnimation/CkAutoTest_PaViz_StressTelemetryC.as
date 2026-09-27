// Language=angelscript

// PaViz telemetry on the third stress courses: the pillar crossing (a ramp onto a field of pillar tops and down again)
// with three rosters, the posts, the cylinder and the pillar field walked between its rows. The recorder
// (CkPaViz_TelemetryRecorder.as) traces the [PAVIZ] lines; the data is the product, so the test passes once the sequence
// completes. Course names are unique across the PaViz tests, because the renderer merges their logs by course and walker.
class UCk_AutoTest_PaViz_StressTelemetryC : UCk_AutoTest_Base
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
        auto CentipedeRoster = TArray<ECkProceduralAnimationGym_Species>();
        CentipedeRoster.Add(ECkProceduralAnimationGym_Species::Centipede);
        auto Created = DoAdd_StressFixture(InHandle, "PillarCrossing", ECkProceduralAnimationGym_Course::PillarCrossing, FVector(120000.0, 240000.0, 600.0));
        Created = _Recorder.Add_Fixture(InHandle, "PillarCrossingMixed", ECkProceduralAnimationGym_Course::PillarCrossing, FVector(120000.0, 245000.0, 600.0),
            ck_paviz_telemetry::MakeRoster(ECkProceduralAnimationGym_Species::Crawler4, ECkProceduralAnimationGym_Species::Crawler6,
                ECkProceduralAnimationGym_Species::Beast)) && Created;
        Created = _Recorder.Add_Fixture(InHandle, "PillarCrossingCentipede", ECkProceduralAnimationGym_Course::PillarCrossing,
            FVector(120000.0, 250000.0, 600.0), CentipedeRoster) && Created;
        Created = DoAdd_StressFixture(InHandle, "Posts", ECkProceduralAnimationGym_Course::Posts, FVector(120000.0, 255000.0, 600.0)) && Created;
        Created = DoAdd_StressFixture(InHandle, "Cylinder", ECkProceduralAnimationGym_Course::Cylinder, FVector(120000.0, 260000.0, 600.0)) && Created;
        Created = DoAdd_StressFixture(InHandle, "PillarRows", ECkProceduralAnimationGym_Course::Pillars, FVector(120000.0, 265000.0, 600.0)) && Created;
        if (Created == false)
        {
            FinishFailure("The isolated pillar-crossing, posts, cylinder and pillar-field fixtures could not be created");
            return;
        }
        Add_Step_WaitUntil("every walker on the pillar-crossing, posts, cylinder and pillar-field courses is composed and evaluated", n"Check_Ready",
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
