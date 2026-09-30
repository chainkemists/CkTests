// Language=angelscript

namespace ck_test_completes_concave_loop
{
    // The loop turns 15 degrees at every slab, below any flip.
    const int32 MaxSupportFlipsPerLap = 0;
    // The loop keeps the root within 0.02 of its clearance of every slab; the bound allows 0.1 more.
    const float MaxRootDepthFraction = 0.12;
    // Preserve the former 6000-poll budget at nominal 60 Hz (two harness polls per tick).
    const float TraversalBudgetSeconds = 6000.0 / 120.0;
}

class UCk_AutoTest_ProceduralAnimation_CompletesConcaveLoop : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 60.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Fixture;
    private int32 _LoopPolls = 0;
    private float _LoopStartTime = -1.0;
    private float _LastLoopLogTime = -1.0;
    private bool _DidLogLoopBoundary = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        if (_Fixture.Create(InHandle, FVector(120000.0, 40000.0, 600.0),
            ECkProceduralAnimationGym_Course::Ring, false) == false)
        {
            FinishFailure("The isolated 24-slab concave loop fixture could not be created");
            return;
        }
        Add_Step_WaitUntil("all rigs walk floor -> wall -> ceiling -> wall -> floor", n"Check_Loop", 0,
            ck_test_completes_concave_loop::TraversalBudgetSeconds);
        Add_Step("verify inverted contacts and completed support cycles", n"Step_Check");
        Add_Step("retire the fixture", n"Step_Destroy");
        Add_Step_WaitUntil("fixture lifetime subtree is gone", n"Check_Destroyed");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_Loop(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        _LoopPolls++;
        auto Now = float(System::GetGameTimeInSeconds());
        if (_LoopStartTime < 0.0)
        {
            _LoopStartTime = Now;
        }
        auto Elapsed = Now - _LoopStartTime;
        auto Complete = _Fixture.Get_HasObservedWalking();
        for (auto Crawler : _Fixture.Crawlers)
        {
            Complete = Complete && Crawler.Progress.Traversals > 0 && Crawler.Evidence.SawWall && Crawler.Evidence.SawCeiling;
        }
        auto BudgetSeconds = ck_test_completes_concave_loop::TraversalBudgetSeconds;
        auto AtBudget = Complete == false && _DidLogLoopBoundary == false && Elapsed >= BudgetSeconds - 0.25;
        if (_LastLoopLogTime < 0.0 || Now - _LastLoopLogTime >= 2.0 || AtBudget || Complete)
        {
            _LastLoopLogTime = Now;
            _DidLogLoopBoundary = _DidLogLoopBoundary || AtBudget;
            LogDisplay(f"[CONCAVE-LOOP] poll {_LoopPolls} gameTime {Elapsed :.2}/{BudgetSeconds :.2} nearBudget {AtBudget} complete {Complete} walking {_Fixture.Get_HasObservedWalking()} fixtureReady {_Fixture.Get_AllReady()} crawlers {_Fixture.Crawlers.Num()}");
            for (auto Crawler : _Fixture.Crawlers)
            {
                auto Ready = Crawler.Get_AllReady();
                auto RootValid = ck::IsValid(Crawler.Handles.Root);
                auto MotionValid = ck::IsValid(Crawler.Handles.Motion);
                auto Local = RootValid ? utils_transform::Get_EntityCurrentTransform(Crawler.Handles.Root).GetLocation() - Crawler.Layout.Origin : FVector::ZeroVector;
                auto Grounded = MotionValid && utils_surface_motion::Get_Support(Crawler.Handles.Motion) == ECk_SurfaceMotion_Support::Grounded;
                LogDisplay(f"[CONCAVE-LOOP] legs {Crawler.Layout.LegCount} ready {Ready} root {RootValid} motion {MotionValid} local ({Local.X :.1}, {Local.Y :.1}, {Local.Z :.1}) stage {Crawler.Progress.RouteStage} laps {Crawler.Progress.Traversals} furthest {Crawler.Progress.FurthestDistance :.1} grounded {Grounded} wall {Crawler.Evidence.SawWall} ceiling {Crawler.Evidence.SawCeiling} replanted {Crawler.Get_ReplantedCount()}/{Crawler.Layout.LegCount} invalid {Crawler.Evidence.InvalidOutput}");
            }
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
            Assert_True(Flips <= ck_test_completes_concave_loop::MaxSupportFlipsPerLap, f"The accepted support turns more than 30 degrees at most at the course's corners in a lap (got {Flips})");
            Assert_True(Depth <= ck_test_completes_concave_loop::MaxRootDepthFraction, f"The root never sits deeper than the bound inside its clearance (got {Depth :.3} of it)");
            Assert_True(Crawler.Evidence.SawCeiling, "At least one trusted foot contact normal faced down on the ceiling");
            Assert_True(Crawler.Evidence.SawWall && Crawler.Progress.Traversals > 0, "Ordered location milestones prove a complete loop");
            Assert_True(Crawler.Evidence.InvalidOutput == false, "Body and foot outputs remained finite through inversion");
            Assert_Equals_Int(Crawler.Get_ReplantedCount(), Crawler.Layout.LegCount, "Every leg completed swing and reacquired support");
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
