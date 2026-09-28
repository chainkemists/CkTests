// Language=angelscript

// An intact Spider should acquire the visible approach face before its body turns onto the ledge.
class UCk_AutoTest_ProceduralAnimation_FrontFootAnticipatesLedge : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 25.0f;
    default _AutoStageOriginField = false;

    private FCkProceduralAnimationGym_Fixture _Fixture;
    private float _StartTime = -1.0;
    private float _FirstTurnTime = -1.0;
    private float _FirstFacePlantTime = -1.0;
    private float _LastTraceTime = -1.0;
    private int32 _OccludedIdealSamples = 0;
    private int32 _ReadySamples = 0;
    private bool _FaceBeforeTurn = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Roster = TArray<ECkProceduralAnimationGym_Species>();
        Roster.Add(ECkProceduralAnimationGym_Species::Spider);
        if (_Fixture.Create_WithRoster(InHandle, FVector(120000.0, 480000.0, 600.0),
            ECkProceduralAnimationGym_Course::Ledge, Roster, false) == false)
        {
            FinishFailure("The isolated intact Spider ledge approach could not be created");
            return;
        }
        Add_Step_WaitUntil("observe the first seven seconds of ledge approach", n"Check_Approach", 0, 15.0f);
        Add_Step("verify proactive front contact", n"Step_Check");
        Add_Step("retire the ledge fixture", n"Step_Destroy");
        Add_Step_WaitUntil("fixture lifetime subtree is gone", n"Check_Destroyed", 0, 5.0f);
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_Approach(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        if (_Fixture.CompositionError.IsEmpty() == false)
        {
            FinishFailure(_Fixture.CompositionError);
            return;
        }
        if (_Fixture.Get_AllReady() == false)
        {
            return;
        }
        auto Now = float(System::GetGameTimeInSeconds());
        if (_StartTime < 0.0)
        {
            _StartTime = Now;
        }
        auto Elapsed = Now - _StartTime;
        auto Crawler = _Fixture.Crawlers[0];
        auto Body = utils_transform::Get_EntityCurrentTransform(Crawler.Handles.Root);
        auto Local = Body.GetLocation() - Crawler.Layout.Origin;
        auto Turned = Body.GetRotation().GetUpVector().Z < 0.995;
        if (Turned && _FirstTurnTime < 0.0)
        {
            _FirstTurnTime = Elapsed;
        }
        _ReadySamples++;
        auto TraceNow = Elapsed >= 4.5 && Elapsed <= 6.5 &&
            (_LastTraceTime < 0.0 || Elapsed - _LastTraceTime >= 0.1);
        if (TraceNow)
        {
            _LastTraceTime = Elapsed;
        }
        for (auto Leg : Crawler.Handles.Legs)
        {
            auto Id = utils_procedural_leg::Get_Id(Leg);
            if (Id != n"Leg0" && Id != n"Leg7")
            {
                continue;
            }
            if (utils_procedural_leg::Get_IdealVerdict(Leg) == ECk_ProceduralLeg_FootholdVerdict::Occluded)
            {
                _OccludedIdealSamples++;
            }
            auto Foot = utils_procedural_leg::Get_Foot(Leg);
            auto FacePlant = Foot.Get_Phase() == ECk_ProceduralLeg_FootPhase::Planted &&
                Foot.Get_Contact() == ECk_ProceduralLeg_FootContact::Trusted && Foot.Get_Normal().X < -0.9;
            if (FacePlant && _FirstFacePlantTime < 0.0)
            {
                _FirstFacePlantTime = Elapsed;
                _FaceBeforeTurn = _FirstTurnTime < 0.0;
            }
            if (TraceNow)
            {
                auto Snapshot = UCk_Utils_AutoTest_UE::Get_ProceduralAnimationLegSnapshot(
                    Crawler.Handles.Root, Id, Crawler.Layout.Origin);
                ck::Trace(f"[LEDGE-ANTICIPATION] t {Elapsed :.3} body ({Local.X :.3},{Local.Y :.3},{Local.Z :.3}) turned {Turned} {Snapshot}");
            }
        }
        auto Result = OutResult;
        Result.Set(Elapsed >= 7.0);
    }

    UFUNCTION()
    private void Step_Check(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Crawler = _Fixture.Crawlers[0];
        Assert_True(_ReadySamples > 100 && Crawler.Evidence.InvalidOutput == false,
            "The intact Spider produced finite ready ledge approach samples");
        Assert_True(_OccludedIdealSamples > 0,
            f"The approach exercised blocked front-leg ideals ({_OccludedIdealSamples})");
        Assert_True(_FirstTurnTime >= 0.0,
            f"The body reached the first climb transition (t {_FirstTurnTime :.3})");
        Assert_True(_FaceBeforeTurn,
            f"A front foot planted on the approach face before body rotation (face {_FirstFacePlantTime :.3}, turn {_FirstTurnTime :.3})");
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
