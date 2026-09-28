// Language=angelscript

// Real published Spider chain joints and clear cached poles through the intact Ledge route. No new runtime API is used.
class UCk_AutoTest_ProceduralAnimation_SwivelPreservesAuthoredBend : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 40.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Fixture;
    private FVector _Origin = FVector(120000.0, 540000.0, 600.0);
    private float _StartedAt = -1.0;
    private int64 _LastSequence = -1;
    private int32 _Samples = 0;
    private int32 _SwivelSamples = 0;
    private int32 _AuthoredSamples = 0;
    private float _MinimumPoleSide = 0.0;
    private float _MinimumKneeSide = 0.0;
    private float _MinimumKneeBend = 0.0;
    private float _MinimumAuthoredKneeBend = 0.0;
    private float _MaximumEndpointGap = 0.0;
    private float _WorstEndpointTime = 0.0;
    private FString _WorstEndpointSnapshot = "";
    private bool _CapturedViolation = false;
    private int32 _PoseMismatchSamples = 0;
    private float _MaximumPoseMismatch = 0.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Roster = TArray<ECkProceduralAnimationGym_Species>();
        Roster.Add(ECkProceduralAnimationGym_Species::Spider);
        if (_Fixture.Create_WithRoster(InHandle, _Origin, ECkProceduralAnimationGym_Course::Ledge,
            Roster, false, ECk_ProceduralBodyPose_ConformMode::PlantedFeet,
            ECkProceduralAnimationGym_HeightSource::Species, 0.0,
            FCkProceduralAnimationGym_WallOverride(), true) == false)
        {
            FinishFailure("The intact Ledge Spider fixture could not be created");
            return;
        }
        Add_Step_WaitUntil("measure authored bend through the intact Ledge approach and return", n"Check_Sampled", 0, 25.0f);
        Add_Step("verify swivel keeps the authored pole side and actual knee branch", n"Step_Check");
        Add_Step("retire the isolated fixture", n"Step_Destroy");
        Add_Step_WaitUntil("the fixture and its collision are gone", n"Check_Destroyed", 0, 10.0f);
        Run_Steps(InHandle);
    }

    private TArray<float32> Get_Radii(const FCkProceduralAnimationGym_Crawler& InCrawler) const
    {
        auto Radii = TArray<float32>();
        for (auto Leg : InCrawler.Handles.Legs)
        {
            auto Lengths = utils_procedural_leg::Get_ChainGeometry(Leg).Get_SegmentLengths();
            for (auto Link = 0; Link < Lengths.Num(); Link++)
            {
                auto Extents = ck_procedural_gym::Get_SegmentHalfExtents(Lengths, Link);
                Radii.Add(float32(Math::Sqrt(Extents.Y * Extents.Y + Extents.Z * Extents.Z)));
            }
        }
        return Radii;
    }

    private FVector Project(FVector InVector, FVector InNormal) const
    {
        return InVector - InNormal * InVector.DotProduct(InNormal);
    }

    private void DoSample(const FCkProceduralAnimationGym_Crawler& InCrawler, float InElapsed)
    {
        auto Metrics = UCk_Utils_AutoTest_UE::Get_ProceduralAnimationRigMetrics(InCrawler.Handles.Root, Get_Radii(InCrawler));
        if (Metrics.Get_Ready() == false || Metrics.Get_SampleSequence() == _LastSequence)
        {
            return;
        }
        _LastSequence = Metrics.Get_SampleSequence();

        auto Body = utils_transform::Get_EntityCurrentTransform(InCrawler.Handles.Root);
        auto Posed = utils_procedural_body_pose::Get_Offset(InCrawler.Handles.BodyPose) * Body;
        auto Up = Posed.GetRotation().GetUpVector();
        auto Coherent = true;
        for (auto Leg : InCrawler.Handles.Legs)
        {
            auto Rig = utils_procedural_rig::DoCastChecked(Leg);
            auto Segments = utils_procedural_rig::Get_Chain(Rig).Get_Segments();
            auto Lengths = utils_procedural_leg::Get_ChainGeometry(Leg).Get_SegmentLengths();
            auto First = utils_transform::Get_EntityCurrentTransform(Segments[0]);
            auto Hip = First.GetLocation() - First.GetRotation().GetForwardVector() * (Lengths[0] * 0.5);
            auto ExpectedHip = Posed.TransformPosition(utils_procedural_leg::Get_Placement(Leg).Get_HipLocal());
            auto Difference = (Hip - ExpectedHip).Size();
            _MaximumPoseMismatch = Math::Max(_MaximumPoseMismatch, Difference);
            Coherent = Coherent && Difference <= 0.05;
        }
        if (Coherent == false)
        {
            _PoseMismatchSamples++;
            return;
        }
        _Samples++;
        if (Metrics.Get_MaximumFootGap() > _MaximumEndpointGap)
        {
            _MaximumEndpointGap = Metrics.Get_MaximumFootGap();
            _WorstEndpointTime = InElapsed;
            auto WorstGap = -1.0;
            for (auto Leg : InCrawler.Handles.Legs)
            {
                auto Rig = utils_procedural_rig::DoCastChecked(Leg);
                auto Chain = utils_procedural_rig::Get_Chain(Rig);
                auto Lengths = utils_procedural_leg::Get_ChainGeometry(Leg).Get_SegmentLengths();
                auto LastIndex = Chain.Get_Segments().Num() - 1;
                auto Last = utils_transform::Get_EntityCurrentTransform(Chain.Get_Segments()[LastIndex]);
                auto End = Last.GetLocation() + Last.GetRotation().GetForwardVector() * (Lengths[LastIndex] * 0.5);
                auto Gap = (End - utils_procedural_leg::Get_Foot(Leg).Get_Position()).Size();
                if (ck::IsValid(Chain.Get_Foot()))
                {
                    Gap = Math::Max(Gap, (End - utils_transform::Get_EntityCurrentLocation(Chain.Get_Foot())).Size());
                }
                if (Gap > WorstGap)
                {
                    WorstGap = Gap;
                    _WorstEndpointSnapshot = UCk_Utils_AutoTest_UE::Get_ProceduralAnimationLegSnapshot(
                        InCrawler.Handles.Root, utils_procedural_leg::Get_Id(Leg), _Origin);
                }
            }
        }
        for (auto Leg : InCrawler.Handles.Legs)
        {
            auto Rig = utils_procedural_rig::DoCastChecked(Leg);
            auto Segments = utils_procedural_rig::Get_Chain(Rig).Get_Segments();
            auto Geometry = utils_procedural_leg::Get_ChainGeometry(Leg);
            if (Segments.Num() < 2)
            {
                continue;
            }
            auto First = utils_transform::Get_EntityCurrentTransform(Segments[0]);
            auto HalfAxis = First.GetRotation().GetForwardVector() * (Geometry.Get_SegmentLengths()[0] * 0.5);
            auto Hip = First.GetLocation() - HalfAxis;
            auto Knee = First.GetLocation() + HalfAxis;
            auto Target = utils_procedural_leg::Get_Foot(Leg).Get_Position();
            auto Along = (Target - Hip).GetSafeNormal();
            auto AuthoredPole = Posed.TransformPosition(Geometry.Get_PoleLocal());
            auto AuthoredVector = AuthoredPole - Hip;
            auto Tangent = Project(AuthoredVector, Up).GetSafeNormal();
            auto Bend = Project(AuthoredVector, Along).GetSafeNormal();
            auto KneeSide = (Knee - Hip).DotProduct(Tangent);
            auto KneeBend = (Knee - Hip).DotProduct(Bend);
            _MinimumKneeSide = Math::Min(_MinimumKneeSide, KneeSide);
            _MinimumKneeBend = Math::Min(_MinimumKneeBend, KneeBend);
            auto Degrees = utils_procedural_rig::Get_SwivelDegrees(Rig);
            if (Math::Abs(Degrees) < 0.001 && utils_procedural_rig::Get_ChainState(Rig) == ECk_ProceduralRig_ChainState::Clear)
            {
                _AuthoredSamples++;
                _MinimumAuthoredKneeBend = Math::Min(_MinimumAuthoredKneeBend, KneeBend);
            }
            // Nonzero cache is the actual angle of a world/body-clear pose, even when siblings still overlap.
            // Zero cache can mean a nonclear fallback; reconstruct zero only when the public full chain state is Clear.
            if (Math::Abs(Degrees) < 0.001 && utils_procedural_rig::Get_ChainState(Rig) != ECk_ProceduralRig_ChainState::Clear)
            {
                continue;
            }
            auto Radians = Degrees * Math::PI / 180.0;
            auto ChosenVector = AuthoredVector * Math::Cos(Radians) +
                Along.CrossProduct(AuthoredVector) * Math::Sin(Radians) +
                Along * AuthoredVector.DotProduct(Along) * (1.0 - Math::Cos(Radians));
            auto PoleSide = ChosenVector.DotProduct(Tangent);
            _MinimumPoleSide = Math::Min(_MinimumPoleSide, PoleSide);
            if (Math::Abs(Degrees) > 0.001)
            {
                _SwivelSamples++;
            }
            if (_CapturedViolation == false && (PoleSide < -0.01 || KneeBend < -0.01))
            {
                _CapturedViolation = true;
                auto Snapshot = UCk_Utils_AutoTest_UE::Get_ProceduralAnimationLegSnapshot(
                    InCrawler.Handles.Root, utils_procedural_leg::Get_Id(Leg), _Origin);
                ck::Trace(f"[AuthoredBend] t {InElapsed :.6} poleSide {PoleSide :.6} kneeSide {KneeSide :.6} kneeBend {KneeBend :.6} {Snapshot}");
            }
        }
    }

    UFUNCTION()
    private void Check_Sampled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        if (_Fixture.CompositionError.IsEmpty() == false)
        {
            FinishFailure(_Fixture.CompositionError);
            return;
        }
        if (_Fixture.Spawn.Pending || _Fixture.Crawlers.Num() != 1 || _Fixture.Crawlers[0].Get_AllReady() == false)
        {
            return;
        }
        auto Now = float(System::GetGameTimeInSeconds());
        if (_StartedAt < 0.0)
        {
            _StartedAt = Now;
        }
        DoSample(_Fixture.Crawlers[0], Now - _StartedAt);
        auto Result = OutResult;
        Result.Set(Now - _StartedAt >= 18.0);
    }

    UFUNCTION()
    private void Step_Check(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_Samples > 100 && _SwivelSamples > 0 && _AuthoredSamples > 0,
            f"Fresh actual authored and swivelled poses were sampled ({_Samples} frames, {_SwivelSamples} swivel, {_AuthoredSamples} authored)");
        Assert_True(_MinimumAuthoredKneeBend >= -0.01,
            f"Precondition: the Spider's un-swivelled poses do not author an inverted knee ({_MinimumAuthoredKneeBend :.4} cm)");
        Assert_True(_MinimumPoleSide >= -0.01,
            f"Clear swivel poles preserve the authored body-facing side ({_MinimumPoleSide :.4} cm)");
        Assert_True(_MinimumKneeBend >= -0.01,
            f"Actual first joints preserve the authored bend branch ({_MinimumKneeBend :.4} cm; lateral signed-distance diagnostic {_MinimumKneeSide :.4} cm)");
        // Authored lateral J1 may itself be negative. The native tests compare its no-worse signed baseline;
        // this real-rig test asserts the actual bend branch and clear pole direction, without assuming J1 radial shape.
        ck::Trace(f"[AuthoredBendFinal] coherent frames {_Samples} stale {_PoseMismatchSamples} maxHipMismatch {_MaximumPoseMismatch :.6} poleSide {_MinimumPoleSide :.6} kneeSide {_MinimumKneeSide :.6} kneeBend {_MinimumKneeBend :.6} authoredBend {_MinimumAuthoredKneeBend :.6} swivelSamples {_SwivelSamples} authoredSamples {_AuthoredSamples}");
        ck::Trace(f"[AuthoredEndpointWorst] t {_WorstEndpointTime :.6} gap {_MaximumEndpointGap :.6} {_WorstEndpointSnapshot}");
        Assert_True(_MaximumEndpointGap <= 0.5,
            f"Rendered chain endpoints retain the published foot anchors ({_MaximumEndpointGap :.4} cm)");
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
