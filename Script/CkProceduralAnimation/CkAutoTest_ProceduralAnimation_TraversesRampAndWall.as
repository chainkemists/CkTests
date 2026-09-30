// Language=angelscript

namespace ck_test_traverses_ramp_and_wall
{
    // A lap turns at four corners: floor to ramp, ramp to wall, wall to ramp and ramp to floor.
    const int32 MaxSupportFlipsPerLap = 4;
    // At the floor-to-ramp corner the down ray sees the ramp first and the body coasts for the confirm time before it turns, which
    // leaves the root 0.36 of its clearance nearer the ramp than the clearance at worst; the bound allows 0.1 more.
    const float MaxRootDepthFraction = 0.46;
    // Preserve the former 5000-poll budget at nominal 60 Hz (two harness polls per tick).
    const float TraversalBudgetSeconds = 5000.0 / 120.0;
}

class UCk_AutoTest_ProceduralAnimation_TraversesRampAndWall : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 74.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Fixture;
    private int32 _TraversalPolls = 0;
    private bool _DidLogTraversalBoundary = false;
    private float _FirstRoutePollAt = -1.0;
    private float _LastRouteTraceAt = -1.0;
    private TArray<int32> _LoggedStages;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        if (_Fixture.Create(InHandle, FVector(120000.0, 35000.0, 600.0),
            ECkProceduralAnimationGym_Course::RampWall, false) == false)
        {
            FinishFailure("The isolated ramp-to-wall fixture could not be created");
            return;
        }
        Add_Step_WaitUntil("every rig climbs the wall and returns across the ramp", n"Check_Traversal", 0,
            ck_test_traverses_ramp_and_wall::TraversalBudgetSeconds);
        Add_Step("check observed wall contacts and completed foot steps", n"Step_Check");
        Add_Step("retire the fixture", n"Step_Destroy");
        Add_Step_WaitUntil("fixture lifetime subtree is gone", n"Check_Destroyed");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_Traversal(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _TraversalPolls++;
        _Fixture.Update();
        auto Now = float(System::GetGameTimeInSeconds());
        if (_FirstRoutePollAt < 0.0)
        {
            _FirstRoutePollAt = Now;
        }
        if (_Fixture.Get_AllReady())
        {
            auto StageChanged = false;
            while (_LoggedStages.Num() < _Fixture.Crawlers.Num())
            {
                _LoggedStages.Add(-1);
            }
            for (auto Index = 0; Index < _Fixture.Crawlers.Num(); Index++)
            {
                auto Stage = _Fixture.Crawlers[Index].Progress.RouteStage;
                if (_LoggedStages[Index] != Stage)
                {
                    StageChanged = true;
                    _LoggedStages[Index] = Stage;
                }
            }
            if (StageChanged || _LastRouteTraceAt < 0.0 || Now - _LastRouteTraceAt >= 2.0)
            {
                _LastRouteTraceAt = Now;
                auto Detail = f"[RAMP-WALL-PROGRESS] t {Now - _FirstRoutePollAt :.2} poll {_TraversalPolls} stageChange {StageChanged}";
                for (auto Crawler : _Fixture.Crawlers)
                {
                    auto Local = utils_transform::Get_EntityCurrentLocation(Crawler.Handles.Root) - Crawler.Layout.Origin;
                    auto Motion = Crawler.Handles.Motion;
                    auto Normal = utils_surface_motion::Get_SupportNormal(Motion);
                    Detail = f"{Detail}; {Crawler.Layout.LegCount} legs ({Local.X :.1},{Local.Y :.1},{Local.Z :.1}) stage {Crawler.Progress.RouteStage} laps {Crawler.Progress.Traversals} support {int32(utils_surface_motion::Get_Support(Motion))}/{int32(utils_surface_motion::Get_ContactQuery(Motion))} normal ({Normal.X :.2},{Normal.Y :.2},{Normal.Z :.2}) pace {utils_surface_motion::Get_ReachPaceScale(Motion) :.3}/{int32(utils_surface_motion::Get_ReachPaceState(Motion))} obstruction {int32(utils_surface_motion::Get_Obstruction(Motion))} wall {Crawler.Evidence.SawWall} replanted {Crawler.Get_ReplantedCount()}/{Crawler.Layout.LegCount} invalid {Crawler.Evidence.InvalidOutput}";
                }
                LogDisplay(Detail);
            }
        }
        auto Complete = _Fixture.Get_HasObservedWalking();
        for (auto Crawler : _Fixture.Crawlers)
        {
            Complete = Complete && Crawler.Progress.Traversals > 0 && Crawler.Evidence.SawWall;
        }
        auto BudgetSeconds = ck_test_traverses_ramp_and_wall::TraversalBudgetSeconds;
        if (Complete == false && _DidLogTraversalBoundary == false &&
            Now - _FirstRoutePollAt >= BudgetSeconds - 0.25)
        {
            _DidLogTraversalBoundary = true;
            auto Elapsed = Now - _FirstRoutePollAt;
            auto Detail = f"[RAMP-WALL-BOUNDARY] gameTime {Elapsed :.2}/{BudgetSeconds :.2}, poll {_TraversalPolls}: ready {_Fixture.Get_AllReady()}, walking {_Fixture.Get_HasObservedWalking()}, crawlers {_Fixture.Crawlers.Num()}";
            for (auto Crawler : _Fixture.Crawlers)
            {
                if (Crawler.Get_AllReady() == false)
                {
                    Detail = f"{Detail}; {Crawler.Layout.LegCount} legs not ready, invalid {Crawler.Evidence.InvalidOutput}";
                    continue;
                }
                auto Local = utils_transform::Get_EntityCurrentLocation(Crawler.Handles.Root) - Crawler.Layout.Origin;
                auto Grounded = utils_surface_motion::Get_Support(Crawler.Handles.Motion) == ECk_SurfaceMotion_Support::Grounded;
                Detail = f"{Detail}; {Crawler.Layout.LegCount} legs at ({Local.X :.1}, {Local.Y :.1}, {Local.Z :.1}), stage {Crawler.Progress.RouteStage}, laps {Crawler.Progress.Traversals}, wall {Crawler.Evidence.SawWall}, support samples {Crawler.Evidence.WallSupportSamples}, support lost {Crawler.Evidence.WallSupportLost}, replanted {Crawler.Get_ReplantedCount()}/{Crawler.Layout.LegCount}, grounded {Grounded}, invalid {Crawler.Evidence.InvalidOutput}";
            }
            LogDisplay(Detail);
        }
        auto Result = OutResult;
        Result.Set(Complete);
    }

    UFUNCTION()
    private void Step_Check(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        for (auto Crawler : _Fixture.Crawlers)
        {
            auto Legs = Crawler.Layout.LegCount;
            auto Flips = Crawler.Evidence.SupportFlips;
            auto Depth = Crawler.Evidence.WorstRootDepthFraction;
            ck::Trace(f"[SupportEvidence] {Legs} legs: support flips over 30 degrees in the first lap {Flips}, worst root depth {Depth :.3} of the clearance",
                n"SupportEvidence", 0.0f);
            Assert_True(Flips <= ck_test_traverses_ramp_and_wall::MaxSupportFlipsPerLap, f"The accepted support turns more than 30 degrees at most at the course's corners in a lap (got {Flips})");
            Assert_True(Depth <= ck_test_traverses_ramp_and_wall::MaxRootDepthFraction, f"The root never sits deeper than the bound inside its clearance (got {Depth :.3} of it)");
            Assert_True(Crawler.Evidence.SawWall && Crawler.Progress.Traversals > 0, "Actual contact normals and ordered spatial milestones prove the wall traversal");
            Assert_True(Crawler.Evidence.WallSupportSamples > 0 && Crawler.Evidence.WallSupportLost == false,
                "The accepted support normal stays on the wall while the body advances above the ramp");
            Assert_True(Crawler.Evidence.InvalidOutput == false, "Root and foot outputs stayed finite across surface transitions");
            Assert_Equals_Int(Crawler.Get_ReplantedCount(), Crawler.Layout.LegCount, "All legs acquired a plant after swinging");
        }
    }

    UFUNCTION()
    private void Step_Destroy(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Fixture.Request_Destroy();
    }

    UFUNCTION()
    private void Check_Destroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Fixture.Get_IsDestroyed());
    }
}
