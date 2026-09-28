// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_CirclesCylinderUpAndDown : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 80.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Fixture;
    private int32 _WrongCylinderPlants = 0;
    private int32 _OwnWallPlantSamples = 0;
    private FString _FirstWrongCylinder;
    private int32 _AirbornePlantSamples = 0;
    private FString _FirstAirbornePlant;
    private TArray<float> _AirHoldStartedAt;
    private TArray<float> _MaxAirHoldSeconds;
    private float _LastAirObservationAt = -1.0;
    private float _LastProgressTraceAt = -1.0;
    private float _SpiderLastAdvanceAt = -1.0;
    private float _SpiderLastAngle = -1.0;
    private int32 _SpiderStallSamples = 0;
    private FVector _SpiderPreviousLocal;
    private FVector _SpiderPreviousRadial;
    private bool _SpiderHasPrevious = false;
    // Flat storage keeps only the most recent 60 observations of each of eight Spider legs. No gameplay state is changed.
    private TArray<FString> _ContactHistory;
    private int32 _ContactHistoryFrame = 0;
    private bool _ContactHistoryDumped = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Roster = ck_procedural_gym::Get_StressRoster(ECkProceduralAnimationGym_Course::Cylinder);
        if (Roster.Num() != 3 || Roster[0] != ECkProceduralAnimationGym_Species::Spider ||
            Roster[1] != ECkProceduralAnimationGym_Species::Biped || Roster[2] != ECkProceduralAnimationGym_Species::SmallCrawler4)
        {
            FinishFailure("The cylinders must roster Spider, Biped and SmallCrawler4 without the rigid centipede");
            return;
        }
        if (_Fixture.Create_WithRoster(InHandle, FVector(120000.0, 310000.0, 600.0),
            ECkProceduralAnimationGym_Course::Cylinder, Roster, false) == false)
        {
            FinishFailure("The isolated cylinder fixture could not be created");
            return;
        }
        Add_Step("verify observed angle continuity across wall grace and genuine support gaps", n"Step_CheckAngleTracker");
        Add_Step_WaitUntil("all three isolated walkers complete two up-and-down cylinder cycles", n"Check_Loops", 0, 60.0f);
        Add_Step("verify sustained trusted wall contact and plants", n"Step_Check");
        Add_Step("retire the fixture", n"Step_Destroy");
        Add_Step_WaitUntil("fixture lifetime subtree is gone", n"Check_Destroyed", 0, 10.0f);
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_CheckAngleTracker(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto TrustedGrace = FCkProceduralAnimationGym_CrawlerProgress();
        TrustedGrace.Observe_HelixRadial(FVector(1.0, 0.0, 0.0), true, false);
        TrustedGrace.Observe_HelixRadial(FVector(Math::Cos(0.1f), Math::Sin(0.1f), 0.0), true, false);
        TrustedGrace.Observe_HelixRadial(FVector(Math::Cos(0.2f), Math::Sin(0.2f), 0.0), false, true);
        TrustedGrace.Observe_HelixRadial(FVector(Math::Cos(0.3f), Math::Sin(0.3f), 0.0), true, false);
        Assert_True(Math::Abs(TrustedGrace.HelixAngle - 0.3f) < 0.001f,
            f"Observed angle includes adjacent Grounded wall grace between trusted contacts ({TrustedGrace.HelixAngle :.4} rad)");

        auto Unsupported = FCkProceduralAnimationGym_CrawlerProgress();
        Unsupported.Observe_HelixRadial(FVector(1.0, 0.0, 0.0), true, false);
        Unsupported.Observe_HelixRadial(FVector(Math::Cos(0.1f), Math::Sin(0.1f), 0.0), true, false);
        Unsupported.Observe_HelixRadial(FVector(Math::Cos(0.2f), Math::Sin(0.2f), 0.0), false, false);
        Unsupported.Observe_HelixRadial(FVector(Math::Cos(0.3f), Math::Sin(0.3f), 0.0), true, false);
        Unsupported.Observe_HelixRadial(FVector(Math::Cos(0.4f), Math::Sin(0.4f), 0.0), true, false);
        Assert_True(Math::Abs(Unsupported.HelixAngle - 0.2f) < 0.001f,
            f"Airborne or offside samples break angle continuity without bridging the gap ({Unsupported.HelixAngle :.4} rad)");

        auto Stationary = FCkProceduralAnimationGym_CrawlerProgress();
        Stationary.Observe_HelixRadial(FVector(1.0, 0.0, 0.0), true, false);
        Stationary.Observe_HelixRadial(FVector(1.0, 0.0, 0.0), false, true);
        Stationary.Observe_HelixRadial(FVector(1.0, 0.0, 0.0), true, false);
        Assert_True(Math::Abs(Stationary.HelixAngle) < 0.001f,
            f"Repeated same-position observations add no angular credit ({Stationary.HelixAngle :.4} rad)");
    }

    UFUNCTION()
    private void Check_Loops(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        if (_Fixture.CompositionError.IsEmpty() == false)
        {
            FinishFailure(_Fixture.CompositionError);
            return;
        }
        auto Now = float(System::GetGameTimeInSeconds());
        if (_Fixture.Crawlers.Num() > 0 && _Fixture.Crawlers[0].Layout.Species == ECkProceduralAnimationGym_Species::Spider)
        {
            auto Spider = _Fixture.Crawlers[0];
            if (Spider.Progress.RouteStage == 2 && Spider.Progress.HelixAngle > 8.0f)
            {
                auto Position = utils_transform::Get_EntityCurrentLocation(Spider.Handles.Root);
                auto Local = Position - Spider.Layout.Origin;
                auto Radial = FVector(Local.X, Local.Y - Spider.Layout.LaneY, 0.0);
                if (_SpiderLastAdvanceAt < 0.0f || Spider.Progress.HelixAngle > _SpiderLastAngle + 0.02f)
                {
                    _SpiderLastAdvanceAt = Now;
                    _SpiderLastAngle = Spider.Progress.HelixAngle;
                }
                if (_SpiderStallSamples == 0 && Now - _SpiderLastAdvanceAt >= 1.0f)
                {
                    _SpiderStallSamples = 1;
                }
                if (_SpiderStallSamples >= 1 && _SpiderStallSamples <= 24)
                {
                    auto Motion = Spider.Handles.Motion;
                    auto Radius = Radial.Size();
                    auto RadialDirection = Radial.GetSafeNormal();
                    auto Normal = utils_surface_motion::Get_SupportNormal(Motion);
                    auto Query = utils_surface_motion::Get_ContactQuery(Motion);
                    auto Support = utils_surface_motion::Get_Support(Motion);
                    auto Clearance = ck_procedural_gym::Get_SpeciesProfile(Spider.Layout.Species).Clearance;
                    auto OnSide = Math::Abs(Normal.Z) < 0.3f && Normal.GetSafeNormal().DotProduct(RadialDirection) > 0.7f
                        && Radius > Spider.Layout.CylinderRadius * 0.75f
                        && Radius < Spider.Layout.CylinderRadius + Clearance * 2.0f + 20.0f
                        && Local.Z > 0.0f && Local.Z < ck_procedural_gym::CylinderHeight;
                    auto Grace = Query == ECk_SurfaceMotion_ContactQuery::Missed && OnSide
                        && Support == ECk_SurfaceMotion_Support::Grounded;
                    auto Move = _SpiderHasPrevious ? Local - _SpiderPreviousLocal : FVector::ZeroVector;
                    auto MeasuredAngle = _SpiderHasPrevious ? Math::Atan2(_SpiderPreviousRadial.CrossProduct(Radial).Z,
                        _SpiderPreviousRadial.DotProduct(Radial)) : 0.0f;
                    auto Obstruction = utils_surface_motion::Get_Obstruction(Motion);
                    auto ObstructionNormal = utils_surface_motion::Get_ObstructionNormal(Motion);
                    auto SideValue = OnSide ? 1 : 0;
                    auto GraceValue = Grace ? 1 : 0;
                    auto PaceState = int32(utils_surface_motion::Get_ReachPaceState(Motion));
                    auto PaceScale = utils_surface_motion::Get_ReachPaceScale(Motion);
                    ck::Trace(f"[CylinderStall] sample {_SpiderStallSamples} t {Now :.4} local ({Local.X :.3},{Local.Y :.3},{Local.Z :.3}) radius {Radius :.3} move ({Move.X :.4},{Move.Y :.4},{Move.Z :.4}) measuredAngle {MeasuredAngle :.5} creditedAngle {Spider.Progress.HelixAngle :.5} query {int32(Query)} support {int32(Support)} normal ({Normal.X :.3},{Normal.Y :.3},{Normal.Z :.3}) side {SideValue} grace {GraceValue} paceState {PaceState} pace {PaceScale :.3} obstruction {int32(Obstruction)} obstructionNormal ({ObstructionNormal.X :.2},{ObstructionNormal.Y :.2},{ObstructionNormal.Z :.2})",
                        n"CylinderStall", 0.0f);
                    if (_SpiderStallSamples == 1 || _SpiderStallSamples == 24)
                    {
                        for (auto Leg : Spider.Handles.Legs)
                        {
                            auto Snapshot = UCk_Utils_AutoTest_UE::Get_ProceduralAnimationLegSnapshot(Spider.Handles.Root,
                                utils_procedural_leg::Get_Id(Leg), Spider.Layout.Origin);
                            ck::Trace(f"[CylinderStallLeg] sample {_SpiderStallSamples} {Snapshot}", n"CylinderStall", 0.0f);
                        }
                    }
                    _SpiderStallSamples++;
                }
                _SpiderPreviousLocal = Local;
                _SpiderPreviousRadial = Radial;
                _SpiderHasPrevious = true;
            }
            else if (_SpiderStallSamples == 0)
            {
                _SpiderLastAdvanceAt = -1.0f;
                _SpiderLastAngle = -1.0f;
                _SpiderHasPrevious = false;
            }
        }
        if (_LastProgressTraceAt < 0.0 || Now - _LastProgressTraceAt >= 5.0)
        {
            _LastProgressTraceAt = Now;
            for (auto Crawler : _Fixture.Crawlers)
            {
                if (ck::Is_NOT_Valid(Crawler.Handles.Root))
                {
                    continue;
                }
                auto Species = ck_procedural_gym::Get_SpeciesName(Crawler.Layout.Species);
                auto LocalZ = utils_transform::Get_EntityCurrentLocation(Crawler.Handles.Root).Z - Crawler.Layout.Origin.Z;
                auto PlantedWallLegs = Crawler.Get_CylinderCycleWallPlantCount();
                ck::Trace(f"[CylinderLoop] {Species}{Crawler.Layout.LegCount}: stage {Crawler.Progress.RouteStage}, angle {Crawler.Progress.HelixAngle :.2}, z {LocalZ :.1}, loops {Crawler.Progress.Traversals}, body wall {Crawler.Progress.HelixCycleWallSamples}/{Crawler.Progress.HelixCycleSamples}, planted wall legs {PlantedWallLegs}/{Crawler.Layout.LegCount}",
                    n"CylinderLoop", 0.0f);
            }
        }
        if (_Fixture.Get_AllReady())
        {
            DoRecord_AirbornePlants(Now);
            for (auto Crawler : _Fixture.Crawlers)
            {
                for (auto Leg : Crawler.Handles.Legs)
                {
                    auto Foot = utils_procedural_leg::Get_Foot(Leg);
                    if (Crawler.Get_IsPlantedCylinderWallFoot(Foot))
                    {
                        _OwnWallPlantSamples++;
                    }
                    if (Foot.Get_Phase() != ECk_ProceduralLeg_FootPhase::Planted ||
                        Foot.Get_Contact() != ECk_ProceduralLeg_FootContact::Trusted)
                    {
                        continue;
                    }
                    for (auto Other : _Fixture.Crawlers)
                    {
                        if (Other.Layout.LaneY == Crawler.Layout.LaneY)
                        {
                            continue;
                        }
                        auto Local = Foot.Get_Position() - Other.Layout.Origin;
                        auto Radial = FVector(Local.X, Local.Y - Other.Layout.LaneY, 0.0);
                        if (Local.Z > 0.0 && Local.Z < ck_procedural_gym::CylinderHeight &&
                            Math::Abs(Radial.Size() - Other.Layout.CylinderRadius) < 5.0 &&
                            Foot.Get_Normal().GetSafeNormal().DotProduct(Radial.GetSafeNormal()) > 0.7)
                        {
                            _WrongCylinderPlants++;
                            if (_FirstWrongCylinder.IsEmpty())
                            {
                                _FirstWrongCylinder = f"{ck_procedural_gym::Get_SpeciesName(Crawler.Layout.Species)} {utils_procedural_leg::Get_Id(Leg)} on lane {Other.Layout.LaneY :.0} at ({Local.X :.2},{Local.Y :.2},{Local.Z :.2})";
                            }
                        }
                    }
                }
            }
        }
        auto Complete = _Fixture.Get_AllReady() && _Fixture.Crawlers.Num() == 3 && _Fixture.Get_HasObservedWalking();
        for (auto Crawler : _Fixture.Crawlers)
        {
            if (Crawler.Evidence.InvalidOutput)
            {
                FinishFailure("The cylinder walker produced invalid output or lost readiness");
                return;
            }
            Complete = Complete && Crawler.Progress.Traversals >= 2 && Crawler.Get_HasCompletedCourse();
        }
        auto Result = OutResult;
        Result.Set(Complete);
    }

    // Signed distance to the actual closed native cylinder, including its caps. Interior points are negative;
    // this check reports open-air holds rather than calling solid penetration an airborne plant.
    private float Get_CylinderDistance(FVector InLocal, float InLaneY, float InRadius) const
    {
        auto Radial = FVector(InLocal.X, InLocal.Y - InLaneY, 0.0).Size() - InRadius;
        auto HalfHeight = ck_procedural_gym::CylinderHeight * 0.5;
        auto Vertical = Math::Abs(InLocal.Z - HalfHeight) - HalfHeight;
        auto OutsideRadial = Math::Max(Radial, 0.0);
        auto OutsideVertical = Math::Max(Vertical, 0.0);
        return Math::Sqrt(OutsideRadial * OutsideRadial + OutsideVertical * OutsideVertical) +
            Math::Min(Math::Max(Radial, Vertical), 0.0);
    }

    private void DoRecord_AirbornePlants(float InNow)
    {
        // Step polling can observe the same engine frame twice; elapsed holds and sample counts use one observation.
        if (InNow == _LastAirObservationAt)
        {
            return;
        }
        _LastAirObservationAt = InNow;
        if (_ContactHistory.Num() == 0)
        {
            _ContactHistory.SetNum(8 * 60);
        }
        if (_AirHoldStartedAt.Num() == 0)
        {
            for (auto Crawler : _Fixture.Crawlers)
            {
                for (auto Leg : Crawler.Handles.Legs)
                {
                    _AirHoldStartedAt.Add(-1.0);
                    _MaxAirHoldSeconds.Add(0.0);
                }
            }
        }
        auto Slot = 0;
        for (auto Crawler : _Fixture.Crawlers)
        {
            auto BodyLocal = utils_transform::Get_EntityCurrentLocation(Crawler.Handles.Root) - Crawler.Layout.Origin;
            auto InMiddleHelix = Crawler.Progress.RouteStage >= 1 && Crawler.Progress.RouteStage <= 2 &&
                BodyLocal.Z >= ck_procedural_gym::HelixBottomZ + 30.0 && BodyLocal.Z <= ck_procedural_gym::HelixTopZ - 30.0;
            for (auto Leg : Crawler.Handles.Legs)
            {
                auto Foot = utils_procedural_leg::Get_Foot(Leg);
                auto FootLocal = Foot.Get_Position() - Crawler.Layout.Origin;
                auto CylinderDistance = Get_CylinderDistance(FootLocal, Crawler.Layout.LaneY, Crawler.Layout.CylinderRadius);
                auto AirbornePlant = InMiddleHelix && Foot.Get_Phase() == ECk_ProceduralLeg_FootPhase::Planted &&
                    Foot.Get_Contact() == ECk_ProceduralLeg_FootContact::Guessed && CylinderDistance > 5.0 &&
                    Math::Abs(FootLocal.Z) > 5.0;
                auto IsSpiderHistory = Crawler.Layout.Species == ECkProceduralAnimationGym_Species::Spider && Slot < 8;
                if (IsSpiderHistory && _ContactHistoryDumped == false)
                {
                    auto HistorySnapshot = UCk_Utils_AutoTest_UE::Get_ProceduralAnimationLegSnapshot(Crawler.Handles.Root,
                        utils_procedural_leg::Get_Id(Leg), Crawler.Layout.Origin);
                    _ContactHistory[(Slot * 60) + (_ContactHistoryFrame % 60)] = f"t {InNow :.4} {HistorySnapshot}";
                    if (AirbornePlant)
                    {
                        auto Count = Math::Min(_ContactHistoryFrame + 1, 60);
                        auto First = (_ContactHistoryFrame + 1 - Count) % 60;
                        for (int32 Row = 0; Row < Count; Row++)
                        {
                            auto History = _ContactHistory[(Slot * 60) + ((First + Row) % 60)];
                            ck::Trace(f"[CylinderContactHistory] {History}", n"CylinderContactHistory", 0.0f);
                        }
                        _ContactHistoryDumped = true;
                    }
                }
                if (AirbornePlant)
                {
                    _AirbornePlantSamples++;
                    if (_AirHoldStartedAt[Slot] < 0.0)
                    {
                        _AirHoldStartedAt[Slot] = InNow;
                    }
                    _MaxAirHoldSeconds[Slot] = Math::Max(_MaxAirHoldSeconds[Slot], InNow - _AirHoldStartedAt[Slot]);
                    if (_FirstAirbornePlant.IsEmpty())
                    {
                        auto Id = utils_procedural_leg::Get_Id(Leg);
                        _FirstAirbornePlant = f"{ck_procedural_gym::Get_SpeciesName(Crawler.Layout.Species)} {Id} bodyZ {BodyLocal.Z :.2} foot ({FootLocal.X :.2},{FootLocal.Y :.2},{FootLocal.Z :.2}) cylinder distance {CylinderDistance :.2} cm";
                        auto Snapshot = UCk_Utils_AutoTest_UE::Get_ProceduralAnimationLegSnapshot(Crawler.Handles.Root,
                            Id, Crawler.Layout.Origin);
                        ck::Trace(f"[CylinderAirPlant] first t {InNow :.4} {_FirstAirbornePlant} {Snapshot}", n"CylinderAirPlant", 0.0f);
                    }
                }
                else
                {
                    _AirHoldStartedAt[Slot] = -1.0;
                }
                Slot++;
            }
        }
        _ContactHistoryFrame++;
    }

    UFUNCTION()
    private void Step_Check(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_OwnWallPlantSamples > 0, "Precondition: actual trusted planted wall feet were sampled");
        Assert_Equals_Int(_WrongCylinderPlants, 0, f"No walker plants on a neighboring cylinder ({_FirstWrongCylinder})");
        auto Slot = 0;
        for (auto Crawler : _Fixture.Crawlers)
        {
            for (auto Leg : Crawler.Handles.Legs)
            {
                ck::Trace(f"[CylinderAirPlant] {ck_procedural_gym::Get_SpeciesName(Crawler.Layout.Species)} {utils_procedural_leg::Get_Id(Leg)} max consecutive open-air planted hold {_MaxAirHoldSeconds[Slot] :.4} s",
                    n"CylinderAirPlant", 0.0f);
                Slot++;
            }
        }
        Assert_Equals_Int(_AirbornePlantSamples, 0,
            f"No guessed planted foot is held over 5 cm away from its real cylinder and floor during the middle helix ({_FirstAirbornePlant})");
        auto Small = ck_procedural_gym::Get_SpeciesProfile(ECkProceduralAnimationGym_Species::SmallCrawler4);
        Assert_True(Small.Rig.Get_Legs().Num() == 4 && Math::Abs(Small.Clearance - 39.0) < 0.01 &&
            Math::Abs(Small.BodyHalfExtents.X - 12.72) < 0.01 && Small.VisualScale == 0.6,
            "The third walker is an authored smaller four-leg crawler with scaled body and feet");
        for (auto LegSpec : Small.Rig.Get_Legs())
        {
            auto Reach = 0.0;
            for (auto Length : LegSpec.Get_Chain().Get_SegmentLengths())
            {
                Reach += Length;
            }
            Assert_True(Math::Abs(Reach - 84.0) < 0.01, "Each small crawler chain is 60 percent of the original reach");
        }
        for (auto Index = 0; Index < _Fixture.Crawlers.Num(); Index++)
        {
            auto Crawler = _Fixture.Crawlers[Index];
            auto Species = ck_procedural_gym::Get_SpeciesName(Crawler.Layout.Species);
            auto ExpectedRadius = ck_procedural_gym::CylinderRadiusWide;
            Assert_True(Crawler.Layout.CylinderRadius == ExpectedRadius,
                f"{Species} kept its authored cylinder radius");
            auto Axis = Crawler.Layout.Origin + FVector(0.0, Crawler.Layout.LaneY,
                ck_procedural_gym::CylinderHeight * 0.5);
            auto RadialHit = utils_jolt_query::Get_RayCast(Axis + FVector(ExpectedRadius + 100.0, 0.0, 0.0),
                Axis, FCk_Jolt_QueryFilter());
            Assert_True(RadialHit.Get_HasHit() &&
                Math::Abs(RadialHit.Get_Position().X - Axis.X - ExpectedRadius) <= 2.0,
                f"{Species} climbed a solid cylinder with its authored radius");
            Assert_True(Crawler.Progress.Traversals >= 2, f"{Species} finished two complete up-and-down cycles");
            Assert_True(Crawler.Evidence.CylinderMinZ <= ck_procedural_gym::HelixBottomZ + ck_procedural_gym::HelixTurnToleranceZ,
                f"{Species} returned to the cylinder's lower band while wall supported");
            Assert_True(Crawler.Evidence.CylinderMaxZ >= ck_procedural_gym::HelixTopZ - ck_procedural_gym::HelixTurnToleranceZ,
                f"{Species} reached the cylinder's upper band while wall supported");
            Assert_True(Crawler.Evidence.CylinderMinCycleWallCoverage >= ck_procedural_gym::HelixMinWallCoverage,
                f"{Species} kept trusted radial wall contact throughout each completed circuit");
            for (auto WallPlantCycles : Crawler.Evidence.CylinderWallPlantCycles)
            {
                Assert_True(WallPlantCycles >= 2, f"Each {Species} leg acquired a trusted planted hold on the cylinder in both cycles");
            }
            Assert_True(Crawler.Evidence.InvalidOutput == false, f"{Species} kept finite output and ready features");
            Assert_Equals_Int(Crawler.Get_ReplantedCount(), Crawler.Layout.LegCount, f"{Species} replanted every leg on trusted contact");
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
