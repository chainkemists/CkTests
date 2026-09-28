// Language=angelscript

// A slow, reach-limited centipede must still finish the authored posts out-and-return route.
class UCk_AutoTest_ProceduralAnimation_PostsCentipedeReturns : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 140.0f;
    default _AutoStageOriginField = false;

    private FCkProceduralAnimationGym_Fixture _Fixture;
    private float _MaxX = -100000.0;
    private float _MinXAfterTurn = 100000.0;
    private int32 _TrustedPlantedSamples = 0;
    private int32 _BlockedSamples = 0;
    private int32 _BlockedClockPairs = 0;
    private float _BlockedClockProgress = 0.0;
    private float _LastBlockedClock = 0.0;
    private bool _WasBlocked = false;
    private bool _SawReverse = false;
    private float _LastTraceAt = -1.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Roster = TArray<ECkProceduralAnimationGym_Species>();
        Roster.Add(ECkProceduralAnimationGym_Species::Centipede);
        if (_Fixture.Create_WithRoster(InHandle, FVector(120000.0, 355000.0, 600.0),
            ECkProceduralAnimationGym_Course::Posts, Roster, false) == false)
        {
            FinishFailure("The isolated real-Jolt Centipede posts course could not be created");
            return;
        }
        Add_Step_WaitUntil("the Centipede crosses the posts and returns", n"Check_Traversal", 0, 120.0f);
        Add_Step("verify complete posts traversal and replants", n"Step_Check");
        Add_Step("retire the fixture", n"Step_Destroy");
        Add_Step_WaitUntil("fixture lifetime subtree is gone", n"Check_Destroyed", 0, 10.0f);
        Run_Steps(InHandle);
    }

    void Sample()
    {
        if (_Fixture.Get_AllReady() == false || _Fixture.Crawlers.Num() != 1)
        {
            return;
        }
        auto Crawler = _Fixture.Crawlers[0];
        auto Body = utils_transform::Get_EntityCurrentTransform(Crawler.Handles.Root);
        auto LocalX = Body.GetLocation().X - Crawler.Layout.Origin.X;
        _MaxX = Math::Max(_MaxX, LocalX);
        if (Crawler.Progress.RouteStage == 1)
        {
            _SawReverse = true;
        }
        if (_SawReverse)
        {
            _MinXAfterTurn = Math::Min(_MinXAfterTurn, LocalX);
        }
        auto PaceState = utils_surface_motion::Get_ReachPaceState(Crawler.Handles.Motion);
        if (PaceState == ECk_SurfaceMotion_ReachPaceState::Blocked)
        {
            _BlockedSamples++;
        }
        auto GroundedBlocked = PaceState == ECk_SurfaceMotion_ReachPaceState::Blocked &&
            utils_surface_motion::Get_Support(Crawler.Handles.Motion) == ECk_SurfaceMotion_Support::Grounded;
        if (GroundedBlocked)
        {
            auto Clock = utils_procedural_gait::Get_GaitClock(Crawler.Handles.Gait);
            if (_WasBlocked)
            {
                _BlockedClockPairs++;
                _BlockedClockProgress += Clock >= _LastBlockedClock ? Clock - _LastBlockedClock : Clock + 1.0 - _LastBlockedClock;
            }
            _LastBlockedClock = Clock;
        }
        _WasBlocked = GroundedBlocked;
        for (auto Leg : Crawler.Handles.Legs)
        {
            if (ck::Is_NOT_Valid(Leg) || utils_procedural_leg::Get_EnableDisable(Leg) != ECk_EnableDisable::Enable)
            {
                continue;
            }
            auto Foot = utils_procedural_leg::Get_Foot(Leg);
            if (Foot.Get_Phase() == ECk_ProceduralLeg_FootPhase::Planted &&
                Foot.Get_Contact() == ECk_ProceduralLeg_FootContact::Trusted)
            {
                _TrustedPlantedSamples++;
            }
        }
    }

    UFUNCTION()
    private void Check_Traversal(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        if (_Fixture.CompositionError.IsEmpty() == false)
        {
            FinishFailure(_Fixture.CompositionError);
            return;
        }
        Sample();
        auto Now = float(System::GetGameTimeInSeconds());
        if (_LastTraceAt < 0.0 || Now - _LastTraceAt >= 5.0)
        {
            _LastTraceAt = Now;
            auto Stage = _Fixture.Crawlers.Num() == 1 ? _Fixture.Crawlers[0].Progress.RouteStage : -1;
            auto Traversals = _Fixture.Crawlers.Num() == 1 ? _Fixture.Crawlers[0].Progress.Traversals : 0;
            ck::Trace(f"[PostsCentipede] stage {Stage}, traversals {Traversals}, x {_MaxX :.1} to {_MinXAfterTurn :.1}, blocked {_BlockedSamples}, blocked clock pairs {_BlockedClockPairs}, progress {_BlockedClockProgress :.2}, trusted plants {_TrustedPlantedSamples}",
                n"PostsCentipede", 0.0f);
        }
        auto Complete = _Fixture.Crawlers.Num() == 1 && _Fixture.Crawlers[0].Get_HasCompletedCourse() &&
            _Fixture.Get_HasObservedWalking();
        auto Result = OutResult;
        Result.Set(Complete);
    }

    UFUNCTION()
    private void Step_Check(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Crawler = _Fixture.Crawlers[0];
        Assert_True(_SawReverse && Crawler.Progress.Traversals > 0 &&
            _MaxX > ck_procedural_gym::TurnaroundX && _MinXAfterTurn < -ck_procedural_gym::TurnaroundX,
            f"The Centipede crossed the posts and returned (x {_MaxX :.1} to {_MinXAfterTurn :.1})");
        Assert_Equals_Int(Crawler.Get_ReplantedCount(), Crawler.Layout.LegCount,
            "Every Centipede leg replanted on trusted contact");
        Assert_True(_TrustedPlantedSamples > 100,
            f"The posts traversal sampled trusted planted feet ({_TrustedPlantedSamples})");
        Assert_True(_BlockedClockPairs > 10 && _BlockedClockProgress > 0.1,
            f"Grounded blocked frames kept opening gait phase windows ({_BlockedClockPairs} pairs, {_BlockedClockProgress :.2} cycles)");
        Assert_True(Crawler.Evidence.InvalidOutput == false, "The posts route kept finite ready output");
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
