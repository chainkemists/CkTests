// Language=angelscript

namespace ck
{
    asset ProceduralTest_RecordedPostSearchRig of UCk_ProceduralRig_Data
    {
        _Legs.Add(ck_procedural_gym_assets::MakeLeg(n"RecordedTarget", FVector(27.716, 11.481, 0.0),
            FVector(116.056, 34.175, -65.0), FVector(116.056, 34.175, 65.0), 0.0f, 2));
        // An enabled second hip preserves the recorded crawler's lateral body bound for UnderBody validation.
        _Legs.Add(ck_procedural_gym_assets::MakeLeg(n"BoundLeg", FVector(0.0, -27.716, 0.0),
            FVector(0.0, -100.0, -65.0), FVector(0.0, -100.0, 65.0), 0.5f, 2));
    }
}

class UCk_AutoTest_ProceduralAnimation_FaceIdealFindsNarrowTopInReach : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Fixture;
    private FVector _Origin = FVector(120000.0, 342500.0, 600.0);
    private float _BodyHeight = 235.0;
    private float _FaceY = 103.0;
    private float _TopDepth = 20.0;
    private float _SceneHalfLength = 50.0;
    private float _Tolerance = 1.0;
    private FCk_Handle_ProceduralGait _Gait;
    private FCk_Handle_ProceduralLeg _Leg;
    private float _WatchStartTime = -1.0;
    private int32 _WatchedFrames = 0;
    private int32 _Violations = 0;
    private FString _FirstViolation;
    private FVector _RecordedOrigin = FVector(120000.0, 376000.0, 600.0);
    private FCk_Handle_Transform _RecordedBody;
    private FCk_Handle_ProceduralGait _RecordedGait;
    private FCk_Handle_ProceduralLeg _RecordedLeg;
    private float _RecordedWatchStart = -1.0f;
    private int32 _RecordedFrames = 0;
    private int32 _RecordedInwardUnreachable = 0;
    private int32 _RecordedTopPlants = 0;
    private int32 _RecordedOffTopPlants = 0;
    private FString _RecordedFirstOffTop;
    private FString _RecordedAcceptedSnapshot;

    float Get_TopZ() const
    {
        return _BodyHeight - ck_procedural_gym_assets::RestDrop;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        if (_Fixture.Create(InHandle, _Origin, ECkProceduralAnimationGym_Course::Flat, false, 1) == false)
        {
            FinishFailure("The narrow-top fixture could not be created");
            return;
        }

        // The +Y rest foot is 3 cm short of the near face. A 42 cm search ring steps past the 20 cm top.
        // The opposite leg stands on a platform; no surface-motion component moves the body.
        auto Color = FLinearColor(0.18, 0.25, 0.31, 1.0);
        auto BlockHalf = FVector(_SceneHalfLength, _TopDepth * 0.5, Get_TopZ() * 0.5);
        _Fixture.AddSurface(FVector(0.0, _FaceY + BlockHalf.Y, BlockHalf.Z), FRotator::ZeroRotator, BlockHalf, Color);
        auto PlatformHalf = FVector(_SceneHalfLength, 50.0, Get_TopZ() * 0.5);
        _Fixture.AddSurface(FVector(0.0, -ck_procedural_gym_assets::SideRestOffset, PlatformHalf.Z),
            FRotator::ZeroRotator, PlatformHalf, Color);

        Add_Step_WaitUntil("the narrow top is queryable", n"Check_SurfacesReady");
        Add_Step("compose the gait-only side walker", n"Step_ComposeGait");
        Add_Step_WaitUntil("the gait is ready", n"Check_GaitReady");
        Add_Step("start watching the +Y foot", n"Step_StartWatch");
        Add_Step_WaitUntil("the +Y foot is watched", n"Check_Watched", 0, 3.0f);
        Add_Step("verify the narrow top is chosen over its face", n"Step_Verify");
        Add_Step("retire the fixture and gait", n"Step_Destroy");
        Add_Step_WaitUntil("entities and collision are gone", n"Check_Destroyed");
        Add_Step("create the captured searched-face post geometry", n"Step_CreateRecordedFixture");
        Add_Step_WaitUntil("the captured post is queryable", n"Check_SurfacesReady");
        Add_Step("verify the captured face and admissible top strip", n"Step_CheckRecordedGeometry");
        Add_Step("compose the stationary captured-query walker", n"Step_ComposeRecordedGait");
        Add_Step_WaitUntil("the captured-query gait is ready", n"Check_RecordedGaitReady");
        Add_Step("start watching the searched-face target", n"Step_StartRecordedWatch");
        Add_Step_WaitUntil("the captured-query foot is watched", n"Check_RecordedWatched", 0, 3.0f);
        Add_Step("verify a searched face yields to the admissible narrow top", n"Step_VerifyRecorded");
        Add_Step("retire the captured-query fixture", n"Step_Destroy");
        Add_Step_WaitUntil("the captured-query collision and gait are gone", n"Check_Destroyed");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_SurfacesReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Fixture.Get_AreSurfacesReady());
    }

    UFUNCTION()
    private void Step_ComposeGait(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Root = utils_entity_lifetime::Request_CreateEntity(_Fixture.SceneRoot);
        Root.Request_OverrideToSelf();
        _Fixture.Entities.Add(Root);
        auto Body = utils_transform::Add(Root, FTransform(_Origin + FVector(0.0, 0.0, _BodyHeight)),
            ECk_Replication::DoesNotReplicate);
        auto Walker = utils_procedural_animation::Add_Walker(Body, ck::ProceduralTest_SideRig, ck::ProceduralGym_Gait,
            TArray<FCk_ProceduralWalker_LegChain>());
        _Gait = Walker.Get_Gait();
        for (auto Leg : Walker.Get_Legs())
        {
            if (utils_procedural_leg::Get_Placement(Leg).Get_HipLocal().Y > 0.0)
            {
                _Leg = Leg;
                break;
            }
        }
        Assert_True(ck::IsValid(_Gait) && ck::IsValid(_Leg), "The gait-only side walker has a +Y leg");
    }

    UFUNCTION()
    private void Check_GaitReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(utils_procedural_gait::Get_Status(_Gait) == ECk_ProceduralAnimation_Status::Ready);
    }

    UFUNCTION()
    private void Step_StartWatch(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _WatchStartTime = float(System::GetGameTimeInSeconds());
    }

    UFUNCTION()
    private void Check_Watched(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _WatchedFrames++;
        auto Foot = utils_procedural_leg::Get_Foot(_Leg);
        auto Local = Foot.Get_Position() - _Origin;
        auto OnTop = Math::Abs(Local.X) <= _SceneHalfLength - _Tolerance
            && Math::Abs(Local.Z - Get_TopZ()) <= _Tolerance
            && Local.Y >= _FaceY + _Tolerance && Local.Y <= _FaceY + _TopDepth + _Tolerance;
        auto PlantedTrusted = Foot.Get_Phase() == ECk_ProceduralLeg_FootPhase::Planted
            && Foot.Get_Contact() == ECk_ProceduralLeg_FootContact::Trusted;
        auto UpNormal = Foot.Get_Normal().GetSafeNormal().Z > 0.99;
        if (OnTop == false || PlantedTrusted == false || UpNormal == false
            || Foot.Get_Foothold() == ECk_ProceduralLeg_Foothold::Ideal)
        {
            _Violations++;
            if (_FirstViolation.IsEmpty())
            {
                auto Source = int32(Foot.Get_Foothold());
                auto Verdict = int32(utils_procedural_leg::Get_IdealVerdict(_Leg));
                auto Phase = int32(Foot.Get_Phase());
                auto Contact = int32(Foot.Get_Contact());
                auto Normal = Foot.Get_Normal();
                _FirstViolation = f"frame {_WatchedFrames}: foot ({Local.X :.1}, {Local.Y :.1}, {Local.Z :.1}), normal ({Normal.X :.2}, {Normal.Y :.2}, {Normal.Z :.2}), phase {Phase}, contact {Contact}, source {Source}, ideal verdict {Verdict}";
            }
        }
        auto Result = OutResult;
        Result.Set(float(System::GetGameTimeInSeconds()) - _WatchStartTime >= 0.3);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_WatchedFrames > 0, "Precondition: the +Y foot was watched");
        Assert_True(_Violations == 0,
            f"A face ideal yields to a trusted plant on a 20 cm deep top in reach ({_Violations} of {_WatchedFrames} frames otherwise; first: {_FirstViolation})");
    }

    UFUNCTION()
    private void Step_CreateRecordedFixture(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        if (_Fixture.Create(InHandle, _RecordedOrigin, ECkProceduralAnimationGym_Course::Flat, false, 1) == false)
        {
            FinishFailure("The captured-query fixture could not be created after the original fixture retired");
            return;
        }
        _Fixture.AddSurface(FVector(-350.0, 0.0, 75.0), FRotator::ZeroRotator, FVector(25.0, 25.0, 75.0),
            FLinearColor(0.18, 0.25, 0.31, 1.0));
        // The captured leaned ideal ray first meets the original second landing at x -300.
        _Fixture.AddSurface(FVector(-100.0, 0.0, 75.0), FRotator::ZeroRotator, FVector(200.0, 300.0, 75.0),
            FLinearColor(0.18, 0.25, 0.31, 1.0));
    }

    UFUNCTION()
    private void Step_CheckRecordedGeometry(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto TopPoint = FVector(-374.617, 24.0, 150.0);
        auto Top = utils_jolt_query::Get_RayCast(_RecordedOrigin + TopPoint + FVector(0.0, 0.0, 100.0),
            _RecordedOrigin + TopPoint - FVector(0.0, 0.0, 50.0), FCk_Jolt_QueryFilter());
        auto Face = utils_jolt_query::Get_RayCast(_RecordedOrigin + FVector(-374.617, 40.0, 136.841),
            _RecordedOrigin + FVector(-374.617, 0.0, 136.841), FCk_Jolt_QueryFilter());
        Assert_True(Top.Get_HasHit() && Math::Abs(Top.Get_Position().Z - (_RecordedOrigin.Z + 150.0)) < 1.0f
            && Top.Get_Normal().Z > 0.99f, "Precondition: the recorded post has a real top at y=24");
        Assert_True(Face.Get_HasHit() && Math::Abs(Face.Get_Position().Y - (_RecordedOrigin.Y + 25.0)) < 1.0f
            && Face.Get_Normal().Y > 0.99f, "Precondition: the same recorded post has the observed +Y face");
        auto Hip = FVector(-427.194, 11.481, 215.0);
        Assert_True((TopPoint - Hip).Size() < 112.0f && TopPoint.Y > 27.716f - 5.0f,
            "Precondition: the near-edge top strip is within target reach and outside the recorded UnderBody lateral bound");
    }

    UFUNCTION()
    private void Step_ComposeRecordedGait(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Root = utils_entity_lifetime::Request_CreateEntity(_Fixture.SceneRoot);
        Root.Request_OverrideToSelf();
        _Fixture.Entities.Add(Root);
        _RecordedBody = utils_transform::Add(Root, FTransform(_RecordedOrigin + FVector(-454.910, 0.0, 215.0)),
            ECk_Replication::DoesNotReplicate);
        // Keep the captured Crawler8 preset, including its default 100 cm probe-up span.
        auto Walker = utils_procedural_animation::Add_Walker(_RecordedBody, ck::ProceduralTest_RecordedPostSearchRig,
            ck::ProceduralGym_Gait, TArray<FCk_ProceduralWalker_LegChain>());
        _RecordedGait = Walker.Get_Gait();
        for (auto Leg : Walker.Get_Legs())
        {
            if (utils_procedural_leg::Get_Id(Leg) == n"RecordedTarget")
            {
                _RecordedLeg = Leg;
                break;
            }
        }
        Assert_True(ck::IsValid(_RecordedGait) && ck::IsValid(_RecordedLeg), "The stationary recorded-query walker has its target leg");
    }

    private void DoRecord_RecordedFoot()
    {
        _RecordedFrames++;
        auto Foot = utils_procedural_leg::Get_Foot(_RecordedLeg);
        auto Local = Foot.Get_Position() - _RecordedOrigin;
        auto Source = Foot.Get_Foothold();
        auto Verdict = utils_procedural_leg::Get_IdealVerdict(_RecordedLeg);
        if (Source == ECk_ProceduralLeg_Foothold::Inward && Verdict == ECk_ProceduralLeg_FootholdVerdict::Unreachable)
        {
            _RecordedInwardUnreachable++;
        }
        if (Foot.Get_Phase() != ECk_ProceduralLeg_FootPhase::Planted ||
            Foot.Get_Contact() != ECk_ProceduralLeg_FootContact::Trusted)
        {
            return;
        }
        auto OnTop = Local.X >= -375.0f - _Tolerance && Local.X <= -325.0f + _Tolerance
            && Local.Y >= 22.716f && Local.Y <= 25.0f + _Tolerance
            && Math::Abs(Local.Z - 150.0f) <= _Tolerance && Foot.Get_Normal().Z > 0.99f;
        if (OnTop)
        {
            _RecordedTopPlants++;
        }
        else
        {
            _RecordedOffTopPlants++;
            if (_RecordedFirstOffTop.IsEmpty())
            {
                auto Normal = Foot.Get_Normal();
                _RecordedFirstOffTop = f"foot ({Local.X :.3},{Local.Y :.3},{Local.Z :.3}), normal ({Normal.X :.3},{Normal.Y :.3},{Normal.Z :.3}), source {int32(Source)}, ideal verdict {int32(Verdict)}";
            }
        }
    }

    UFUNCTION()
    private void Check_RecordedGaitReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Ready = utils_procedural_gait::Get_Status(_RecordedGait) == ECk_ProceduralAnimation_Status::Ready;
        if (Ready)
        {
            DoRecord_RecordedFoot();
        }
        auto Result = OutResult;
        Result.Set(Ready);
    }

    UFUNCTION()
    private void Step_StartRecordedWatch(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _RecordedWatchStart = float(System::GetGameTimeInSeconds());
    }

    UFUNCTION()
    private void Check_RecordedWatched(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        DoRecord_RecordedFoot();
        if (_RecordedAcceptedSnapshot.IsEmpty())
        {
            auto Snapshot = UCk_Utils_AutoTest_UE::Get_ProceduralAnimationLegSnapshot(_RecordedBody,
                utils_procedural_leg::Get_Id(_RecordedLeg), _RecordedOrigin);
            if (Snapshot.Contains("accepted 1"))
            {
                _RecordedAcceptedSnapshot = Snapshot;
                ck::Trace(f"[RECORDED-TOP-ACCEPTED] {_RecordedAcceptedSnapshot}");
            }
        }
        auto Result = OutResult;
        Result.Set(float(System::GetGameTimeInSeconds()) - _RecordedWatchStart >= 0.3f);
    }

    UFUNCTION()
    private void Step_VerifyRecorded(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_RecordedFrames > 0, "Precondition: the captured-query target leg was watched");
        Assert_True(_RecordedInwardUnreachable > 0,
            f"Precondition: the actual acquisition used Inward search with an Unreachable ideal ({_RecordedInwardUnreachable} samples; {_RecordedAcceptedSnapshot})");
        Assert_True(_RecordedTopPlants > 0,
            f"The searched +Y face yields to a trusted plant on its reachable near-edge top ({_RecordedTopPlants} top samples, {_RecordedOffTopPlants} off-top; first {_RecordedFirstOffTop})");
        Assert_True(_RecordedOffTopPlants == 0,
            f"The captured-query leg never trusted-plants on the searched face instead of the available top ({_RecordedOffTopPlants} samples; first {_RecordedFirstOffTop})");
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
