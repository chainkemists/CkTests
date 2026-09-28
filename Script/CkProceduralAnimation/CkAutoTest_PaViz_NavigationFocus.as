// Language=angelscript

// Focused real-RHI captures of the reported navigation features: three isolated cylinders, mandatory stepping
// pillars, all three crawler sizes on the ramp, and Spider approach plants on the step field and ledge.
// Seven isolated fixtures contain eleven walkers and share the existing shot plan.
class UCk_AutoTest_PaViz_NavigationFocus : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 75.0f;
    default _AutoStageOriginField = false;
    private FCkPaViz_ShotPlan _Shots;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Created = _Shots.Add_Fixture(InHandle, ECkProceduralAnimationGym_Course::Cylinder,
            FVector(120000.0, 400000.0, 600.0),
            ck_procedural_gym::Get_StressRoster(ECkProceduralAnimationGym_Course::Cylinder));
        Created = _Shots.Add_Fixture(InHandle, ECkProceduralAnimationGym_Course::Pillars,
            FVector(120000.0, 405000.0, 600.0),
            ck_procedural_gym::Get_StressRoster(ECkProceduralAnimationGym_Course::Pillars)) && Created;
        auto CrawlerRoster = TArray<ECkProceduralAnimationGym_Species>();
        CrawlerRoster.Add(ECkProceduralAnimationGym_Species::Crawler4);
        Created = _Shots.Add_Fixture(InHandle, ECkProceduralAnimationGym_Course::RampWall,
            FVector(120000.0, 410000.0, 600.0), CrawlerRoster) && Created;
        auto SpiderRoster = TArray<ECkProceduralAnimationGym_Species>();
        SpiderRoster.Add(ECkProceduralAnimationGym_Species::Spider);
        Created = _Shots.Add_Fixture(InHandle, ECkProceduralAnimationGym_Course::StepField,
            FVector(120000.0, 415000.0, 600.0), SpiderRoster) && Created;
        Created = _Shots.Add_Fixture(InHandle, ECkProceduralAnimationGym_Course::Ledge,
            FVector(120000.0, 420000.0, 600.0), SpiderRoster) && Created;
        auto Crawler6Roster = TArray<ECkProceduralAnimationGym_Species>();
        Crawler6Roster.Add(ECkProceduralAnimationGym_Species::Crawler6);
        Created = _Shots.Add_Fixture(InHandle, ECkProceduralAnimationGym_Course::RampWall,
            FVector(120000.0, 425000.0, 600.0), Crawler6Roster) && Created;
        auto Crawler8Roster = TArray<ECkProceduralAnimationGym_Species>();
        Crawler8Roster.Add(ECkProceduralAnimationGym_Species::Crawler8);
        Created = _Shots.Add_Fixture(InHandle, ECkProceduralAnimationGym_Course::RampWall,
            FVector(120000.0, 430000.0, 600.0), Crawler8Roster) && Created;
        if (Created == false)
        {
            FinishFailure("The focused rendered navigation fixtures could not be created");
            return;
        }

        // Side cameras on cylinders follow each body's outward radial so the cylinder cannot hide its feet.
        for (auto Walker = 0; Walker < 3; Walker++)
        {
            _Shots.Add_Shot(0, Walker, "cylinder-ascending", 100000.0, 1, false, 200.0, 250.0);
        }
        // The upper bound excludes the turnaround: this view requires actual descent into the middle band.
        _Shots.Add_Shot(0, 0, "cylinder-descending", 100000.0, 2, true, 600.0, 250.0, 0.0, 350.0);
        _Shots.Add_Shot(1, 1, "stepping-tops", 0.0, 0, false, 200.0, 200.0);
        _Shots.Add_Shot(1, 1, "stepping-tops-topdown", 0.0, 0, true, 600.0, 200.0);
        // The slab rises from X400/Z0 to X1280/Z738.4; these upper-ramp windows end before the wall's
        // west face at X1280 and its nominal body standoff at X1215. Camera settling still advances the walkers.
        _Shots.Add_Shot(2, 0, "ramp-upper-approach", 950.0, 0, false, 200.0, 550.0, 0.0, 850.0, 1180.0);
        _Shots.Add_Shot(2, 0, "ramp-upper-approach-topdown", 1050.0, 0, true, 600.0, 600.0, 0.0, 850.0, 1180.0);
        _Shots.Add_Shot(3, 0, "riser-40cm", -270.0, 0, false, 200.0);
        _Shots.Add_Shot(4, 0, "wall-approach", -260.0, 0, false, 200.0, 130.0);
        _Shots.Add_Shot(5, 0, "ramp-upper-approach", 950.0, 0, false, 200.0, 550.0, 0.0, 850.0, 1180.0);
        _Shots.Add_Shot(5, 0, "ramp-upper-approach-topdown", 1050.0, 0, true, 600.0, 600.0, 0.0, 850.0, 1180.0);
        _Shots.Add_Shot(6, 0, "ramp-upper-approach", 950.0, 0, false, 200.0, 550.0, 0.0, 850.0, 1180.0);
        _Shots.Add_Shot(6, 0, "ramp-upper-approach-topdown", 1050.0, 0, true, 600.0, 600.0, 0.0, 850.0, 1180.0);

        Snapshot_CVarForTest(n"r.ForceLOD");
        Snapshot_CVarForTest(n"r.SceneColorFormat");
        Snapshot_CVarForTest(n"r.PostProcessingColorFormat");
        System::ExecuteConsoleCommand("viewmode unlit");
        Add_Step_WaitUntil("the eleven focused walkers are composed and evaluated", n"Check_Ready", 0, 10.0f);
        Add_Step_WaitUntil("all fourteen focused captures are taken", n"Check_Captured", 0, 55.0f);
        Add_Step("verify captures, restore view mode and retire fixtures", n"Step_Finish");
        Add_Step_WaitUntil("the focused fixture subtrees and collision are gone", n"Check_Destroyed", 0, 10.0f);
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Ready = _Shots.Update_Ready();
        if (_Shots.CompositionError.IsEmpty() == false)
        {
            FinishFailure(f"A focused walker could not be composed: {_Shots.CompositionError}");
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
        Assert_Equals_Int(_Shots.Taken, 14, "All fourteen focused navigation shots were captured");
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
