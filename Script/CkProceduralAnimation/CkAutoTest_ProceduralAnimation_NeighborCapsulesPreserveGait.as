// Language=angelscript

// Paired real-Jolt fixtures differ only in rig sibling-clearance participation. Actual published capsule metrics
// must improve without changing body motion, gait feet, rigid links or foot anchors. Residual overlaps are reported.
class UCk_AutoTest_ProceduralAnimation_NeighborCapsulesPreserveGait : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 40.0f;
    default _AutoStageOriginField = false;
    private TArray<FCkProceduralAnimationGym_Fixture> _Fixtures;
    private TArray<int32> _Samples;
    private TArray<int64> _LastSequence;
    private TArray<float> _LastSampleTime;
    private TArray<float> _PenaltyOff;
    private TArray<float> _PenaltyOn;
    private TArray<float> _MaximumOff;
    private TArray<float> _MaximumOn;
    private TArray<int32> _OverlappingOff;
    private TArray<int32> _OverlappingOn;
    private TArray<bool> _Improved;
    private TArray<float> _WorstPenalty;
    private TArray<float> _WorstPenetration;
    private TArray<float> _WorstPenaltyTime;
    private TArray<float> _WorstPenetrationTime;
    private TArray<FString> _WorstPenaltySnapshots;
    private TArray<FString> _WorstPenetrationSnapshots;
    private float _StartedAt = -1.0;
    private float _MaximumBodyDifference = 0.0;
    private float _MaximumFrameDifference = 0.0;
    private float _MaximumFootDifference = 0.0;
    private int32 _StateMismatches = 0;
    private bool _CapturedFirstMismatch = false;
    private float _MaximumJointGap = 0.0;
    private float _MaximumFootGap = 0.0;
    private int32 _WorstEndpointCourse = -1;
    private bool _WorstEndpointAvoidance = false;
    private float _WorstEndpointTime = 0.0;
    private int64 _WorstEndpointSequence = -1;
    private TArray<FString> _WorstEndpointSnapshots;

    private bool DoCreate_Fixture(FCk_Handle InOwner, ECkProceduralAnimationGym_Course InCourse,
        FVector InOrigin, bool InSiblingAvoidance)
    {
        auto Roster = TArray<ECkProceduralAnimationGym_Species>();
        Roster.Add(ECkProceduralAnimationGym_Species::Spider);
        auto Fixture = FCkProceduralAnimationGym_Fixture();
        if (Fixture.Create_WithRoster(InOwner, InOrigin, InCourse, Roster, false,
            ECk_ProceduralBodyPose_ConformMode::PlantedFeet, ECkProceduralAnimationGym_HeightSource::Species,
            0.0, FCkProceduralAnimationGym_WallOverride(), InSiblingAvoidance) == false)
        {
            return false;
        }
        _Fixtures.Add(Fixture);
        return true;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        if (DoCreate_Fixture(InHandle, ECkProceduralAnimationGym_Course::StepField,
            FVector(120000.0, 500000.0, 600.0), false) == false ||
            DoCreate_Fixture(InHandle, ECkProceduralAnimationGym_Course::Ledge,
            FVector(120000.0, 510000.0, 600.0), false) == false)
        {
            FinishFailure("The paired sibling-clearance fixtures could not be created");
            return;
        }
        for (auto Pair = 0; Pair < 2; Pair++)
        {
            _Samples.Add(0);
            _LastSequence.Add(-1);
            _LastSampleTime.Add(-1.0);
            _PenaltyOff.Add(0.0);
            _PenaltyOn.Add(0.0);
            _MaximumOff.Add(0.0);
            _MaximumOn.Add(0.0);
            _OverlappingOff.Add(0);
            _OverlappingOn.Add(0);
            _Improved.Add(false);
            _WorstPenalty.Add(-1.0);
            _WorstPenetration.Add(-1.0);
            _WorstPenaltyTime.Add(0.0);
            _WorstPenetrationTime.Add(0.0);
            for (auto LegIndex = 0; LegIndex < 8; LegIndex++)
            {
                _WorstPenaltySnapshots.Add("");
                _WorstPenetrationSnapshots.Add("");
            }
        }
        Add_Step_WaitUntil("sample paired actual poses through the intact approaches", n"Check_Sampled", 0, 25.0f);
        Add_Step("verify preserved gait and improved capsule separation", n"Step_Check");
        Add_Step("retire the paired fixtures", n"Step_Destroy");
        Add_Step_WaitUntil("the paired fixture subtrees and collision are gone", n"Check_Destroyed", 0, 10.0f);
        Run_Steps(InHandle);
    }

    private TArray<float32> Get_RenderedRadii(const FCkProceduralAnimationGym_Crawler& InCrawler) const
    {
        auto Radii = TArray<float32>();
        auto Scale = ck_procedural_gym::Get_SpeciesProfile(InCrawler.Layout.Species).VisualScale;
        for (auto Leg : InCrawler.Handles.Legs)
        {
            auto Lengths = utils_procedural_leg::Get_ChainGeometry(Leg).Get_SegmentLengths();
            for (auto Link = 0; Link < Lengths.Num(); Link++)
            {
                auto HalfExtents = ck_procedural_gym::Get_SegmentHalfExtents(Lengths, Link, Scale);
                Radii.Add(float32(Math::Sqrt(HalfExtents.Y * HalfExtents.Y + HalfExtents.Z * HalfExtents.Z)));
            }
        }
        return Radii;
    }

    // All eight strings are captured synchronously from one accepted solve; later printing never reads live poses.
    private void DoCapture_Worst(int32 InPair, float InElapsed, bool InPenalty,
        const FCkProceduralAnimationGym_Crawler& InCrawler)
    {
        for (auto LegIndex = 0; LegIndex < InCrawler.Handles.Legs.Num(); LegIndex++)
        {
            auto Id = utils_procedural_leg::Get_Id(InCrawler.Handles.Legs[LegIndex]);
            auto Snapshot = UCk_Utils_AutoTest_UE::Get_ProceduralAnimationLegSnapshot(
                InCrawler.Handles.Root, Id, InCrawler.Layout.Origin);
            if (InPenalty)
            {
                _WorstPenaltySnapshots[InPair * 8 + LegIndex] = Snapshot;
            }
            else
            {
                _WorstPenetrationSnapshots[InPair * 8 + LegIndex] = Snapshot;
            }
        }
        if (InPenalty)
        {
            _WorstPenaltyTime[InPair] = InElapsed;
        }
        else
        {
            _WorstPenetrationTime[InPair] = InElapsed;
        }
    }

    private void DoMeasure_Pair(int32 InPair, float InNow)
    {
        auto Off = _Fixtures[InPair].Crawlers[0];
        auto On = _Fixtures[InPair].Crawlers[1];
        auto OffMetrics = UCk_Utils_AutoTest_UE::Get_ProceduralAnimationRigMetrics(Off.Handles.Root, Get_RenderedRadii(Off));
        auto OnMetrics = UCk_Utils_AutoTest_UE::Get_ProceduralAnimationRigMetrics(On.Handles.Root, Get_RenderedRadii(On));
        if (OffMetrics.Get_Ready() == false || OnMetrics.Get_Ready() == false ||
            OffMetrics.Get_SampleSequence() != OnMetrics.Get_SampleSequence() ||
            OffMetrics.Get_SampleSequence() == _LastSequence[InPair])
        {
            return;
        }
        if (OnMetrics.Get_TotalPenetrationSquared() > _WorstPenalty[InPair])
        {
            _WorstPenalty[InPair] = OnMetrics.Get_TotalPenetrationSquared();
            DoCapture_Worst(InPair, InNow - _StartedAt, true, On);
        }
        if (OnMetrics.Get_MaximumPenetration() > _WorstPenetration[InPair])
        {
            _WorstPenetration[InPair] = OnMetrics.Get_MaximumPenetration();
            DoCapture_Worst(InPair, InNow - _StartedAt, false, On);
        }
        _Samples[InPair]++;
        _LastSequence[InPair] = OffMetrics.Get_SampleSequence();
        auto DeltaTime = _LastSampleTime[InPair] < 0.0 ? 0.0 : InNow - _LastSampleTime[InPair];
        _LastSampleTime[InPair] = InNow;
        _PenaltyOff[InPair] += OffMetrics.Get_TotalPenetrationSquared() * DeltaTime;
        _PenaltyOn[InPair] += OnMetrics.Get_TotalPenetrationSquared() * DeltaTime;
        _MaximumOff[InPair] = Math::Max(_MaximumOff[InPair], OffMetrics.Get_MaximumPenetration());
        _MaximumOn[InPair] = Math::Max(_MaximumOn[InPair], OnMetrics.Get_MaximumPenetration());
        _OverlappingOff[InPair] += OffMetrics.Get_OverlappingPairs();
        _OverlappingOn[InPair] += OnMetrics.Get_OverlappingPairs();
        _Improved[InPair] = _Improved[InPair] ||
            OnMetrics.Get_TotalPenetrationSquared() + 0.01 < OffMetrics.Get_TotalPenetrationSquared();
        _MaximumJointGap = Math::Max(_MaximumJointGap,
            Math::Max(OffMetrics.Get_MaximumJointGap(), OnMetrics.Get_MaximumJointGap()));
        auto ObservedFootGap = Math::Max(OffMetrics.Get_MaximumFootGap(), OnMetrics.Get_MaximumFootGap());
        if (ObservedFootGap > _MaximumFootGap && ObservedFootGap > 0.5)
        {
            _WorstEndpointCourse = InPair;
            _WorstEndpointAvoidance = OnMetrics.Get_MaximumFootGap() >= OffMetrics.Get_MaximumFootGap();
            _WorstEndpointTime = InNow - _StartedAt;
            _WorstEndpointSequence = OnMetrics.Get_SampleSequence();
            _WorstEndpointSnapshots.Empty();
            auto WorstCrawler = _WorstEndpointAvoidance ? On : Off;
            for (auto Leg : WorstCrawler.Handles.Legs)
            {
                auto Snapshot = UCk_Utils_AutoTest_UE::Get_ProceduralAnimationLegSnapshot(
                    WorstCrawler.Handles.Root, utils_procedural_leg::Get_Id(Leg), WorstCrawler.Layout.Origin);
                auto Rig = utils_procedural_rig::DoCastChecked(Leg);
                auto MeshFoot = utils_procedural_rig::Get_Chain(Rig).Get_Foot();
                if (ck::IsValid(MeshFoot))
                {
                    auto LocalMeshFoot = utils_transform::Get_EntityCurrentLocation(MeshFoot) - WorstCrawler.Layout.Origin;
                    Snapshot += f" meshFoot ({LocalMeshFoot.X :.6},{LocalMeshFoot.Y :.6},{LocalMeshFoot.Z :.6})";
                }
                else
                {
                    Snapshot += " meshFoot unavailable";
                }
                _WorstEndpointSnapshots.Add(Snapshot);
            }
        }
        _MaximumFootGap = Math::Max(_MaximumFootGap, ObservedFootGap);

        auto OffBody = utils_transform::Get_EntityCurrentTransform(Off.Handles.Root);
        auto OnBody = utils_transform::Get_EntityCurrentTransform(On.Handles.Root);
        auto BodyDifference = ((OffBody.GetLocation() - Off.Layout.Origin) -
            (OnBody.GetLocation() - On.Layout.Origin)).Size();
        _MaximumBodyDifference = Math::Max(_MaximumBodyDifference, BodyDifference);
        _MaximumFrameDifference = Math::Max(_MaximumFrameDifference,
            Math::Max((OffBody.GetRotation().GetForwardVector() - OnBody.GetRotation().GetForwardVector()).Size(),
                (OffBody.GetRotation().GetUpVector() - OnBody.GetRotation().GetUpVector()).Size()));
        for (auto Index = 0; Index < Off.Handles.Legs.Num(); Index++)
        {
            auto OffFoot = utils_procedural_leg::Get_Foot(Off.Handles.Legs[Index]);
            auto OnFoot = utils_procedural_leg::Get_Foot(On.Handles.Legs[Index]);
            auto FootDifference =
                ((OffFoot.Get_Position() - Off.Layout.Origin) - (OnFoot.Get_Position() - On.Layout.Origin)).Size();
            _MaximumFootDifference = Math::Max(_MaximumFootDifference, FootDifference);
            if (_CapturedFirstMismatch == false && FootDifference > 0.05)
            {
                _CapturedFirstMismatch = true;
                ck::Trace(f"[SiblingFirstMismatch] course {InPair} t {InNow - _StartedAt :.6} leg {Index} gap {FootDifference :.6} seq {OnMetrics.Get_SampleSequence()}");
                for (auto LegIndex = 0; LegIndex < Off.Handles.Legs.Num(); LegIndex++)
                {
                    auto Id = utils_procedural_leg::Get_Id(Off.Handles.Legs[LegIndex]);
                    auto OffSnapshot = UCk_Utils_AutoTest_UE::Get_ProceduralAnimationLegSnapshot(Off.Handles.Root, Id, Off.Layout.Origin);
                    auto OnSnapshot = UCk_Utils_AutoTest_UE::Get_ProceduralAnimationLegSnapshot(On.Handles.Root, Id, On.Layout.Origin);
                    ck::Trace(f"[SiblingFirstMismatch] OFF {OffSnapshot}");
                    ck::Trace(f"[SiblingFirstMismatch] ON {OnSnapshot}");
                }
            }
            if (OffFoot.Get_Phase() != OnFoot.Get_Phase() || OffFoot.Get_Contact() != OnFoot.Get_Contact())
            {
                _StateMismatches++;
            }
        }
    }

    UFUNCTION()
    private void Check_Sampled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Ready = true;
        for (auto Index = 0; Index < _Fixtures.Num(); Index++)
        {
            // Spawn two independent walkers before either receives its first route update. They share every Jolt
            // collider and the exact world transform; passive rig parts do not add collision geometry.
            if (_Fixtures[Index].Spawn.Pending && _Fixtures[Index].Get_AreSurfacesReady())
            {
                _Fixtures[Index].Spawn.SiblingAvoidance = false;
                _Fixtures[Index].SpawnCrawler(0);
                _Fixtures[Index].Spawn.SiblingAvoidance = true;
                _Fixtures[Index].SpawnCrawler(0);
                _Fixtures[Index].Spawn.Pending = false;
            }
            _Fixtures[Index].Update();
            if (_Fixtures[Index].CompositionError.IsEmpty() == false)
            {
                FinishFailure(_Fixtures[Index].CompositionError);
                return;
            }
            // This diagnostic intentionally has two walkers for the single authored collision lane.
            Ready = Ready && _Fixtures[Index].Spawn.Pending == false && _Fixtures[Index].Crawlers.Num() == 2 &&
                _Fixtures[Index].Get_AreSurfacesReady();
            for (auto Crawler : _Fixtures[Index].Crawlers)
            {
                Ready = Ready && Crawler.Get_AllReady();
            }
        }
        if (Ready == false)
        {
            return;
        }
        auto Now = float(System::GetGameTimeInSeconds());
        if (_StartedAt < 0.0)
        {
            _StartedAt = Now;
        }
        for (auto Pair = 0; Pair < 2; Pair++)
        {
            DoMeasure_Pair(Pair, Now);
        }
        auto Result = OutResult;
        Result.Set(Now - _StartedAt >= 18.0);
    }

    UFUNCTION()
    private void Step_Check(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_MaximumBodyDifference <= 0.05, f"Rig avoidance preserves paired body motion ({_MaximumBodyDifference :.4} cm)");
        Assert_True(_MaximumFrameDifference <= 0.0001, f"Rig avoidance preserves paired body orientation ({_MaximumFrameDifference :.6})");
        Assert_True(_MaximumFootDifference <= 0.05, f"Rig avoidance preserves the gait's published foot positions ({_MaximumFootDifference :.4} cm)");
        Assert_Equals_Int(_StateMismatches, 0, "Rig avoidance preserves foot phase and contact states");
        Assert_True(_MaximumJointGap <= 0.5, f"Published rigid chains remain connected to their hips and neighboring links ({_MaximumJointGap :.3} cm)");
        if (_WorstEndpointCourse >= 0)
        {
            for (auto Snapshot : _WorstEndpointSnapshots)
            {
                ck::Trace(f"[SiblingEndpointWorst] course {_WorstEndpointCourse} avoidance {_WorstEndpointAvoidance} t {_WorstEndpointTime :.6} gap {_MaximumFootGap :.6} seq {_WorstEndpointSequence} {Snapshot}");
            }
        }
        Assert_True(_MaximumFootGap <= 0.5, f"Actual foot meshes and chain endpoints keep their foot anchors ({_MaximumFootGap :.3} cm)");
        for (auto Pair = 0; Pair < 2; Pair++)
        {
            auto CourseName = Pair == 0 ? "StepField" : "Ledge";
            Assert_True(_Samples[Pair] > 100, f"{CourseName} captured fresh paired poses with matching accepted solve sequences ({_Samples[Pair]})");
            Assert_True(_PenaltyOn[Pair] <= _PenaltyOff[Pair] + 0.01,
                f"{CourseName} integrated actual capsule penetration does not increase ({_PenaltyOff[Pair] :.3} to {_PenaltyOn[Pair] :.3} cm2 s)");
            Assert_True(_Improved[Pair], f"{CourseName} contains an observed strict reduction in actual capsule penetration");
            ck::Trace(f"[SiblingCapsules] {CourseName} fresh paired samples {_Samples[Pair]} integrated penalty off {_PenaltyOff[Pair] :.3} on {_PenaltyOn[Pair] :.3} cm2 s, maximum penetration off {_MaximumOff[Pair] :.3} on {_MaximumOn[Pair] :.3} cm, overlapping pairs off {_OverlappingOff[Pair]} on {_OverlappingOn[Pair]}");
            ck::Trace(f"[SiblingWorst] {CourseName} worst total penalty {_WorstPenalty[Pair] :.6} cm2 at {_WorstPenaltyTime[Pair] :.6}s, worst penetration {_WorstPenetration[Pair] :.6} cm at {_WorstPenetrationTime[Pair] :.6}s");
            for (auto LegIndex = 0; LegIndex < 8; LegIndex++)
            {
                ck::Trace(f"[INTACT-APPROACH] course {Pair} t {_WorstPenaltyTime[Pair] :.6} witness penalty {_WorstPenalty[Pair] :.6} {_WorstPenaltySnapshots[Pair * 8 + LegIndex]}");
                ck::Trace(f"[INTACT-APPROACH] course {Pair} t {_WorstPenetrationTime[Pair] :.6} witness penetration {_WorstPenetration[Pair] :.6} {_WorstPenetrationSnapshots[Pair * 8 + LegIndex]}");
            }
        }
    }

    UFUNCTION()
    private void Step_Destroy(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        for (auto Index = 0; Index < _Fixtures.Num(); Index++)
        {
            _Fixtures[Index].Request_Destroy();
        }
    }

    UFUNCTION()
    private void Check_Destroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Destroyed = true;
        for (auto Index = 0; Index < _Fixtures.Num(); Index++)
        {
            Destroyed = Destroyed && _Fixtures[Index].Get_IsDestroyed();
        }
        auto Result = OutResult;
        Result.Set(Destroyed);
    }
}
