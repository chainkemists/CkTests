// Language=angelscript

// Side and top-down HighResShot captures of the hump walkers and side captures of the uneven-course crawlers for
// docs/campaigns/procedural-animation/viz, through the shared shot plan (CkPaViz_ShotPlan.as). Needs a real RHI
// (--no-nullrhi); under -nullrhi it still passes and the captures are black.
class UCk_AutoTest_PaViz_Visual : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 75.0f;
    default _AutoStageOriginField = false;
    private FCkPaViz_ShotPlan _Shots;
    private float _SideHeight = 80.0;
    // Uneven lanes are 280 cm apart, so the centre crawler is shot over its neighbour from higher up.
    private float _UnevenSideHeight = 220.0;
    private float _TopDownHeight = 600.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Created = _Shots.Add_Fixture(InHandle, ECkProceduralAnimationGym_Course::Hump, FVector(120000.0, 130000.0, 600.0),
            ck_paviz_telemetry::MakeRoster(ECkProceduralAnimationGym_Species::Tentacled, ECkProceduralAnimationGym_Species::Spider,
                ECkProceduralAnimationGym_Species::Beast));
        Created = _Shots.Add_Fixture(InHandle, ECkProceduralAnimationGym_Course::Uneven, FVector(120000.0, 150000.0, 600.0),
            ck_paviz_telemetry::MakeRoster(ECkProceduralAnimationGym_Species::Crawler4, ECkProceduralAnimationGym_Species::Crawler6,
                ECkProceduralAnimationGym_Species::Crawler8)) && Created;
        if (Created == false)
        {
            FinishFailure("The isolated rendered hump and uneven fixtures could not be created");
            return;
        }

        // Hump side shots run on the outbound crossing (the hump spans x -700..700, steepest at +-350, crest at 0); the
        // top-down shots on the return. The uneven crawlers are shot on the first ridge (x -300, 65 cm up).
        auto SidePhases = TArray<FString>();
        SidePhases.Add("approach");
        SidePhases.Add("climbing");
        SidePhases.Add("crest");
        SidePhases.Add("descending");
        auto SideX = TArray<float>();
        SideX.Add(-900.0);
        SideX.Add(-350.0);
        SideX.Add(0.0);
        SideX.Add(350.0);
        for (auto PhaseIndex = 0; PhaseIndex < SidePhases.Num(); PhaseIndex++)
        {
            for (auto Walker = 0; Walker < 3; Walker++)
            {
                _Shots.Add_Shot(0, Walker, SidePhases[PhaseIndex], SideX[PhaseIndex], 0, false, _SideHeight);
            }
        }
        for (auto Walker = 0; Walker < 3; Walker++)
        {
            _Shots.Add_Shot(1, Walker, "ridge", -300.0, 0, false, _UnevenSideHeight);
        }
        for (auto Walker = 0; Walker < 3; Walker++)
        {
            _Shots.Add_Shot(0, Walker, "topdown-slope", 350.0, 1, true, _TopDownHeight);
        }
        for (auto Walker = 0; Walker < 3; Walker++)
        {
            _Shots.Add_Shot(0, Walker, "topdown-crest", 0.0, 1, true, _TopDownHeight);
        }

        // HighResShot rewrites these three and does not always put them back; snapshot them so the base does.
        Snapshot_CVarForTest(n"r.ForceLOD");
        Snapshot_CVarForTest(n"r.SceneColorFormat");
        Snapshot_CVarForTest(n"r.PostProcessingColorFormat");
        // The AutoTests level has no lighting. `viewmode` is a command, not a variable, so Step_Finish puts it back by hand,
        // as the shot plan does the camera's field of view.
        System::ExecuteConsoleCommand("viewmode unlit");

        Add_Step_WaitUntil("the hump and uneven walkers are composed and evaluated", n"Check_Ready", 1200, 20.0f);
        Add_Step_WaitUntil("every planned capture is taken or 50 s pass", n"Check_Captured", 0, 55.0f);
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
        Result.Set(_Shots.Update_Captured(50.0));
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
