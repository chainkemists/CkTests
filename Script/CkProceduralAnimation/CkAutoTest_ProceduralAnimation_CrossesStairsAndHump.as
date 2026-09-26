// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_CrossesStairsAndHump : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 60.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Stairs;
    private FCkProceduralAnimationGym_Fixture _Hump;
    private FVector _StairsOrigin = FVector(120000.0, 110000.0, 600.0);
    private FVector _HumpOrigin = FVector(120000.0, 115000.0, 600.0);
    private float _PhaseStart = 0.0;
    private float _StairsMaxZ = 0.0;
    private float _HumpMaxZ = 0.0;
    private float _StairsMinSupportZ = 1.0;
    private bool _StairsCrossed = false;
    private bool _HumpCrossed = false;

    float Get_Elapsed() const
    {
        return float(System::GetGameTimeInSeconds()) - _PhaseStart;
    }

    FVector Get_RootLocal(FCkProceduralAnimationGym_Crawler InCrawler) const
    {
        return utils_transform::Get_EntityCurrentLocation(InCrawler.Handles.Root) - InCrawler.Layout.Origin;
    }

    bool Get_HasPassedTurnaround(FCkProceduralAnimationGym_Crawler InCrawler) const
    {
        return InCrawler.Progress.RouteStage == 1 || InCrawler.Progress.Traversals > 0;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto StairsRoster = TArray<ECkProceduralAnimationGym_Species>();
        StairsRoster.Add(ECkProceduralAnimationGym_Species::Beast);
        auto HumpRoster = TArray<ECkProceduralAnimationGym_Species>();
        HumpRoster.Add(ECkProceduralAnimationGym_Species::Spider);
        auto Created = _Stairs.Create_WithRoster(InHandle, _StairsOrigin, ECkProceduralAnimationGym_Course::Stairs, StairsRoster, false);
        Created = _Hump.Create_WithRoster(InHandle, _HumpOrigin, ECkProceduralAnimationGym_Course::Hump, HumpRoster, false) && Created;
        if (Created == false)
        {
            FinishFailure("The isolated stairs and hump fixtures could not be created");
            return;
        }
        Add_Step_WaitUntil("both walkers are composed and evaluated", n"Check_Ready", 1200);
        Add_Step_WaitUntil("both walkers pass the turnaround or 40 s pass", n"Check_Crossed", 0, 45.0f);
        Add_Step("check the climbs, the crossings and the stair support", n"Step_Check");
        Add_Step("retire both fixtures", n"Step_Destroy");
        Add_Step_WaitUntil("both fixture lifetime subtrees are gone", n"Check_Destroyed");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Stairs.Update();
        _Hump.Update();
        if (_Stairs.CompositionError.IsEmpty() == false || _Hump.CompositionError.IsEmpty() == false)
        {
            FinishFailure(f"A walker could not be composed: '{_Stairs.CompositionError}' '{_Hump.CompositionError}'");
            return;
        }
        auto Ready = _Stairs.Get_AllReady() && _Hump.Get_AllReady();
        if (Ready)
        {
            _PhaseStart = float(System::GetGameTimeInSeconds());
        }
        auto Result = OutResult;
        Result.Set(Ready);
    }

    UFUNCTION()
    private void Check_Crossed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Stairs.Update();
        _Hump.Update();
        if (_Stairs.Crawlers[0].Get_AllReady())
        {
            auto Crawler = _Stairs.Crawlers[0];
            _StairsMaxZ = Math::Max(_StairsMaxZ, Get_RootLocal(Crawler).Z);
            _StairsMinSupportZ = Math::Min(_StairsMinSupportZ, utils_surface_motion::Get_SupportNormal(Crawler.Handles.Motion).Z);
            _StairsCrossed = _StairsCrossed || Get_HasPassedTurnaround(Crawler);
        }
        if (_Hump.Crawlers[0].Get_AllReady())
        {
            auto Crawler = _Hump.Crawlers[0];
            _HumpMaxZ = Math::Max(_HumpMaxZ, Get_RootLocal(Crawler).Z);
            _HumpCrossed = _HumpCrossed || Get_HasPassedTurnaround(Crawler);
        }
        auto Result = OutResult;
        Result.Set((_StairsCrossed && _HumpCrossed) || Get_Elapsed() >= 40.0);
    }

    UFUNCTION()
    private void Step_Check(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto StairsWalker = _Stairs.Crawlers[0];
        auto HumpWalker = _Hump.Crawlers[0];
        auto StairsTarget = ck_procedural_gym::StairsLandingZ + 0.8 * ck_procedural_gym::Get_SpeciesProfile(StairsWalker.Layout.Species).Clearance;
        auto HumpTarget = ck_procedural_gym::HumpTopZ + 0.5 * ck_procedural_gym::Get_SpeciesProfile(HumpWalker.Layout.Species).Clearance;
        auto StairsLocal = Get_RootLocal(StairsWalker);
        auto HumpLocal = Get_RootLocal(HumpWalker);
        auto Elapsed = Get_Elapsed();
        ck::Trace(f"[STAIRS-HUMP] after {Elapsed :.2} s: stairs beast crossed={_StairsCrossed} stage={StairsWalker.Progress.RouteStage} at x {StairsLocal.X :.1} z {StairsLocal.Z :.1}, max z {_StairsMaxZ :.1} of {StairsTarget :.1}, min support z {_StairsMinSupportZ :.4}, replanted {StairsWalker.Get_ReplantedCount()}/{StairsWalker.Layout.LegCount}, invalid={StairsWalker.Evidence.InvalidOutput}");
        ck::Trace(f"[STAIRS-HUMP] after {Elapsed :.2} s: hump spider crossed={_HumpCrossed} stage={HumpWalker.Progress.RouteStage} at x {HumpLocal.X :.1} z {HumpLocal.Z :.1}, max z {_HumpMaxZ :.1} of {HumpTarget :.1}, replanted {HumpWalker.Get_ReplantedCount()}/{HumpWalker.Layout.LegCount}, invalid={HumpWalker.Evidence.InvalidOutput}");

        Assert_True(_StairsCrossed, f"The beast climbs the stairs, crosses the landing and passes the turnaround (stopped at x {StairsLocal.X :.1}, z {StairsLocal.Z :.1})");
        Assert_True(_HumpCrossed, f"The spider crests the hump and passes the turnaround (stopped at x {HumpLocal.X :.1}, z {HumpLocal.Z :.1})");
        Assert_True(StairsWalker.Evidence.InvalidOutput == false, "The beast's root, feet and rigs stayed valid on the stairs");
        Assert_True(HumpWalker.Evidence.InvalidOutput == false, "The spider's root, feet and rigs stayed valid on the hump");
        Assert_Equals_Int(StairsWalker.Get_ReplantedCount(), StairsWalker.Layout.LegCount, "Every beast leg swung and replanted on the stairs");
        Assert_Equals_Int(HumpWalker.Get_ReplantedCount(), HumpWalker.Layout.LegCount, "Every spider leg swung and replanted on the hump");
        Assert_True(_StairsMaxZ >= StairsTarget, f"The beast's body rises onto the landing ({_StairsMaxZ :.1} >= {StairsTarget :.1} cm)");
        Assert_True(_HumpMaxZ >= HumpTarget, f"The spider's body rises over the crest ({_HumpMaxZ :.1} >= {HumpTarget :.1} cm)");
        Assert_True(_StairsMinSupportZ > 0.5, f"The beast never takes a riser as its support surface (lowest support normal Z {_StairsMinSupportZ :.3})");
    }

    UFUNCTION()
    private void Step_Destroy(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Stairs.Request_Destroy();
        _Hump.Request_Destroy();
    }

    UFUNCTION()
    private void Check_Destroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Stairs.Get_IsDestroyed() && _Hump.Get_IsDestroyed());
    }
}
