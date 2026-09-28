// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_PillarsEngageSteppedTops : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 90.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Fixture;
    private TArray<int32> _LegOffsets;
    private TArray<bool> _TopWitnesses;
    private TArray<float> _HighestBodyZ;
    private int32 _TrustedSamples = 0;
    private float _MaxReachExcess = 0.0;
    private FString _WorstReach;
    private float _LastTraceAt = -1.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        if (_Fixture.Create_WithRoster(InHandle, FVector(120000.0, 392000.0, 600.0),
            ECkProceduralAnimationGym_Course::Pillars,
            ck_procedural_gym::Get_StressRoster(ECkProceduralAnimationGym_Course::Pillars), false) == false)
        {
            FinishFailure("The isolated stepping-pillar fixture could not be created");
            return;
        }
        Add_Step_WaitUntil("the stepping pillars and walkers are ready", n"Check_Ready", 0, 10.0f);
        Add_Step("verify every route intersects the authored blocks", n"Step_CheckGeometry");
        Add_Step_WaitUntil("all walkers cross the stepping pillars and return", n"Check_Traversal", 0, 65.0f);
        Add_Step("verify distinct trusted top engagement and reach", n"Step_Check");
        Add_Step("retire the fixture", n"Step_Destroy");
        Add_Step_WaitUntil("entities and stepping collision are gone", n"Check_Destroyed", 0, 10.0f);
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        auto Result = OutResult;
        Result.Set(_Fixture.Get_AllReady());
    }

    UFUNCTION()
    private void Step_CheckGeometry(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Columns = ck_procedural_gym::PillarColumnCount;
        for (auto Crawler : _Fixture.Crawlers)
        {
            _LegOffsets.Add(_TopWitnesses.Num());
            _HighestBodyZ.Add(0.0);
            for (auto Leg : Crawler.Handles.Legs)
            {
                for (auto Column = 0; Column < Columns; Column++)
                {
                    _TopWitnesses.Add(false);
                }
            }
            for (auto Column = 0; Column < Columns; Column++)
            {
                auto Center = ck_procedural_gym::Get_PillarCenter(Column, Crawler.Layout.LaneY);
                auto Above = Crawler.Layout.Origin + FVector(Center.X, Crawler.Layout.LaneY, ck_procedural_gym::Get_PillarHeight(Column) + 50.0);
                auto Below = Above - FVector(0.0, 0.0, ck_procedural_gym::Get_PillarHeight(Column) + 100.0);
                auto Hit = utils_jolt_query::Get_RayCast(Above, Below, FCk_Jolt_QueryFilter());
                Assert_True(Hit.Get_HasHit() && Hit.Get_Normal().Z > 0.99 &&
                    Math::Abs(Hit.Get_Position().Z - Crawler.Layout.Origin.Z - ck_procedural_gym::Get_PillarHeight(Column)) < 1.0,
                    "Each route centreline intersects a real stepping pillar, with no straight corridor between rows");
            }
        }
    }

    UFUNCTION()
    private void Check_Traversal(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        auto Complete = _Fixture.Get_AllReady();
        auto Columns = ck_procedural_gym::PillarColumnCount;
        for (auto Walker = 0; Walker < _Fixture.Crawlers.Num(); Walker++)
        {
            auto Crawler = _Fixture.Crawlers[Walker];
            if (Crawler.Evidence.InvalidOutput)
            {
                FinishFailure("A stepping-pillar walker produced invalid output or lost readiness");
                return;
            }
            auto Simulation = utils_transform::Get_EntityCurrentTransform(Crawler.Handles.Root);
            auto Posed = utils_procedural_body_pose::Get_Offset(Crawler.Handles.BodyPose) * Simulation;
            auto Local = Simulation.GetLocation() - Crawler.Layout.Origin;
            _HighestBodyZ[Walker] = Math::Max(_HighestBodyZ[Walker], Local.Z);
            for (auto Index = 0; Index < Crawler.Handles.Legs.Num(); Index++)
            {
                auto Leg = Crawler.Handles.Legs[Index];
                auto Foot = utils_procedural_leg::Get_Foot(Leg);
                if (Foot.Get_Phase() != ECk_ProceduralLeg_FootPhase::Planted ||
                    Foot.Get_Contact() != ECk_ProceduralLeg_FootContact::Trusted)
                {
                    continue;
                }
                _TrustedSamples++;
                auto Column = ck_procedural_gym::Get_PillarTopIndex(Foot.Get_Position() - Crawler.Layout.Origin, Crawler.Layout.LaneY);
                if (Column >= 0 && Foot.Get_Normal().Z > 0.99)
                {
                    _TopWitnesses[_LegOffsets[Walker] + Index * Columns + Column] = true;
                }
                auto Reach = 0.0;
                for (auto Length : utils_procedural_leg::Get_ChainGeometry(Leg).Get_SegmentLengths())
                {
                    Reach += Length;
                }
                auto HipLocal = utils_procedural_leg::Get_Placement(Leg).Get_HipLocal();
                auto Excess = Math::Max((Foot.Get_Position() - Simulation.TransformPosition(HipLocal)).Size(),
                    (Foot.Get_Position() - Posed.TransformPosition(HipLocal)).Size()) - Reach;
                if (Excess > _MaxReachExcess)
                {
                    _MaxReachExcess = Excess;
                    _WorstReach = f"{ck_procedural_gym::Get_SpeciesName(Crawler.Layout.Species)} {utils_procedural_leg::Get_Id(Leg)} x {Local.X :.1}";
                }
            }
            Complete = Complete && Crawler.Progress.Traversals >= 1 && Crawler.Get_HasCompletedCourse();
        }
        auto Now = float(System::GetGameTimeInSeconds());
        if (_LastTraceAt < 0.0 || Now - _LastTraceAt >= 5.0)
        {
            _LastTraceAt = Now;
            for (auto Crawler : _Fixture.Crawlers)
            {
                auto Local = utils_transform::Get_EntityCurrentLocation(Crawler.Handles.Root) - Crawler.Layout.Origin;
                ck::Trace(f"[SteppingPillars] {ck_procedural_gym::Get_SpeciesName(Crawler.Layout.Species)} stage {Crawler.Progress.RouteStage} x {Local.X :.1} z {Local.Z :.1} returns {Crawler.Progress.Traversals} worstReach {_MaxReachExcess :.3}");
            }
        }
        auto Result = OutResult;
        Result.Set(Complete);
    }

    UFUNCTION()
    private void Step_Check(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Columns = ck_procedural_gym::PillarColumnCount;
        Assert_True(_TrustedSamples > 0, "Precondition: actual trusted planted feet were sampled");
        Assert_True(_MaxReachExcess <= 0.5, f"Trusted planted simulation and posed hips stay reachable ({_MaxReachExcess :.3} cm at {_WorstReach})");
        for (auto Walker = 0; Walker < _Fixture.Crawlers.Num(); Walker++)
        {
            auto Crawler = _Fixture.Crawlers[Walker];
            auto Species = ck_procedural_gym::Get_SpeciesName(Crawler.Layout.Species);
            auto Clearance = ck_procedural_gym::Get_SpeciesProfile(Crawler.Layout.Species).Clearance;
            Assert_True(_HighestBodyZ[Walker] >= ck_procedural_gym::PillarHeight + Clearance * 0.8,
                f"{Species} climbed the high stepping tops instead of bypassing the field ({_HighestBodyZ[Walker] :.1} cm)");
            Assert_True(Crawler.Progress.Traversals >= 1, f"{Species} completed the outward crossing and return");
            for (auto Leg = 0; Leg < Crawler.Handles.Legs.Num(); Leg++)
            {
                auto Distinct = 0;
                for (auto Column = 0; Column < Columns; Column++)
                {
                    if (_TopWitnesses[_LegOffsets[Walker] + Leg * Columns + Column])
                    {
                        Distinct++;
                    }
                }
                Assert_True(Distinct >= 2, f"Each {Species} leg planted with trusted top contact on distinct pillars ({Distinct} tops)");
            }
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