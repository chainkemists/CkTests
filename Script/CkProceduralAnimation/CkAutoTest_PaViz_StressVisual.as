// Language=angelscript

// One HighResShot side capture of each stress course's middle walker at the course's feature, plus a top-down one of the
// spin, for docs/campaigns/procedural-animation/viz, through the shared shot plan (CkPaViz_ShotPlan.as). Needs a real RHI
// (--no-nullrhi); under -nullrhi it still passes and the captures are black.
class UCk_AutoTest_PaViz_StressVisual : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 75.0f;
    default _AutoStageOriginField = false;
    private FCkPaViz_ShotPlan _Shots;
    // The middle walker is shot over the third lane and down onto the feature.
    private float _SideHeight = 200.0;
    private float _TopDownHeight = 600.0;
    private int32 _Middle = 1;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Courses = TArray<ECkProceduralAnimationGym_Course>();
        Courses.Add(ECkProceduralAnimationGym_Course::StepField);
        Courses.Add(ECkProceduralAnimationGym_Course::Ledge);
        Courses.Add(ECkProceduralAnimationGym_Course::Ridge);
        Courses.Add(ECkProceduralAnimationGym_Course::Log);
        Courses.Add(ECkProceduralAnimationGym_Course::Beam);
        Courses.Add(ECkProceduralAnimationGym_Course::Pillars);
        Courses.Add(ECkProceduralAnimationGym_Course::Spin);
        auto Created = true;
        for (auto Index = 0; Index < Courses.Num(); Index++)
        {
            Created = _Shots.Add_Fixture(InHandle, Courses[Index], FVector(120000.0, 200000.0 + 5000.0 * Index, 600.0),
                ck_procedural_gym::Get_StressRoster(Courses[Index])) && Created;
        }
        if (Created == false)
        {
            FinishFailure("The isolated rendered stress fixtures could not be created");
            return;
        }

        // The features: the 40 cm riser, halfway up the ledge's wall, the ridge's crest, the log's top, along the beam, the
        // first pillar, and midway through the spin.
        _Shots.Add_Shot(0, _Middle, "riser-40cm", -270.0, 0, false, _SideHeight);
        _Shots.Add_Shot(1, _Middle, "wall", -260.0, 0, false, _SideHeight, 130.0);
        _Shots.Add_Shot(2, _Middle, "crest", -20.0, 0, false, _SideHeight);
        _Shots.Add_Shot(3, _Middle, "top", -40.0, 0, false, _SideHeight);
        _Shots.Add_Shot(4, _Middle, "along", -400.0, 0, false, _SideHeight);
        _Shots.Add_Shot(5, _Middle, "first-pillar", -980.0, 0, false, _SideHeight);
        _Shots.Add_Shot(6, _Middle, "spinning", -100000.0, 0, false, _SideHeight, -100000.0, 3.0);
        _Shots.Add_Shot(6, _Middle, "spinning-topdown", -100000.0, 0, true, _TopDownHeight, -100000.0, 4.5);

        // HighResShot rewrites these three and does not always put them back; snapshot them so the base does.
        Snapshot_CVarForTest(n"r.ForceLOD");
        Snapshot_CVarForTest(n"r.SceneColorFormat");
        Snapshot_CVarForTest(n"r.PostProcessingColorFormat");
        // The AutoTests level has no lighting. `viewmode` is a command, not a variable, so Step_Finish puts it back by hand,
        // as the shot plan does the camera's field of view.
        System::ExecuteConsoleCommand("viewmode unlit");

        Add_Step_WaitUntil("the stress-course walkers are composed and evaluated", n"Check_Ready", 1200, 30.0f);
        Add_Step_WaitUntil("every planned capture is taken or 40 s pass", n"Check_Captured", 0, 45.0f);
        Add_Step("restore the lit view mode and retire the fixtures", n"Step_Finish");
        Add_Step_WaitUntil("the fixtures are gone", n"Check_Destroyed", 0, 10.0f);
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Ready = _Shots.Update_Ready();
        if (_Shots.CompositionError.IsEmpty() == false)
        {
            FinishFailure(f"A walker could not be composed: {_Shots.CompositionError}");
            return;
        }
        auto Result = OutResult;
        Result.Set(Ready);
    }

    UFUNCTION()
    private void Check_Captured(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Shots.Update_Captured(40.0));
    }

    UFUNCTION()
    private void Step_Finish(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        System::ExecuteConsoleCommand("viewmode lit");
        _Shots.Finish();
    }

    UFUNCTION()
    private void Check_Destroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Shots.Get_IsDestroyed());
    }
}
