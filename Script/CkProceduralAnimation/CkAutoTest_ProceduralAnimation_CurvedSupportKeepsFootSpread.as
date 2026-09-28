// Language=angelscript

namespace ck
{
    asset ProceduralTest_CurvedSpreadRig of UCk_ProceduralRig_Data
    {
        auto Lengths = TArray<float32>();
        Lengths.Add(50.0f);
        Lengths.Add(60.0f);
        Lengths.Add(60.0f);
        Lengths.Add(50.0f);
        _Legs.Add(ck_procedural_gym_assets::MakeLegWithLengths(n"Leading", FVector(34.0, -14.1, 0.0),
            FVector(168.0, -47.0, -90.0), FVector(98.7, -40.9, 150.0), 0.0f, Lengths));
        _Legs.Add(ck_procedural_gym_assets::MakeLegWithLengths(n"Bound", FVector(0.0, 30.0, 0.0),
            FVector(0.0, 60.0, -90.0), FVector(0.0, 60.0, 150.0), 0.5f, Lengths));
    }
}

class UCk_AutoTest_ProceduralAnimation_CurvedSupportKeepsFootSpread : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Fixture;
    private FVector _Origin = FVector(120000.0, 482000.0, 600.0);
    private FCk_Handle_Transform _Body;
    private FCk_Handle_ProceduralGait _Gait;
    private FCk_Handle_ProceduralLeg _Leg;
    private float _WatchStart = -1.0;
    private int32 _Samples = 0;
    private int32 _Supported = 0;
    private FString _Snapshot;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        if (_Fixture.Create(InHandle, _Origin, ECkProceduralAnimationGym_Course::Flat, false, 1) == false)
        {
            FinishFailure("The curved support fixture could not be created");
            return;
        }
        _Fixture.AddCylinder(FVector(0.0, 0.0, 250.0), 90.0, 250.0, FLinearColor::White);
        Add_Step_WaitUntil("the curved support is queryable", n"Check_SurfacesReady");
        Add_Step("compose the leading-foot query beside a convex support", n"Step_Compose");
        Add_Step_WaitUntil("the leading foot is observed", n"Check_Observed", 0, 3.0f);
        Add_Step("verify surface contact retains lateral foot spread", n"Step_Check");
        Add_Step("retire the fixture", n"Step_Destroy");
        Add_Step_WaitUntil("entities and curved collision are gone", n"Check_Destroyed");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_SurfacesReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Fixture.Get_AreSurfacesReady());
    }

    UFUNCTION()
    private void Step_Compose(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Root = utils_entity_lifetime::Request_CreateEntity(_Fixture.SceneRoot);
        Root.Request_OverrideToSelf();
        _Fixture.Entities.Add(Root);
        _Body = utils_transform::Add(Root, FTransform(FRotator(0.0, 0.0, -90.0),
            _Origin + FVector(0.0, -180.0, 200.0)), ECk_Replication::DoesNotReplicate);
        auto Walker = utils_procedural_animation::Add_Walker(_Body, ck::ProceduralTest_CurvedSpreadRig,
            ck::ProceduralGym_GaitSpider, TArray<FCk_ProceduralWalker_LegChain>());
        _Gait = Walker.Get_Gait();
        _Leg = Walker.Get_Legs()[0];
    }

    UFUNCTION()
    private void Check_Observed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        if (utils_procedural_gait::Get_Status(_Gait) != ECk_ProceduralAnimation_Status::Ready)
        {
            return;
        }
        auto Now = float(System::GetGameTimeInSeconds());
        if (_WatchStart < 0.0)
        {
            _WatchStart = Now;
        }
        auto Foot = utils_procedural_leg::Get_Foot(_Leg);
        auto Local = Foot.Get_Position() - _Origin;
        auto Radius = FVector(Local.X, Local.Y, 0.0).Size();
        auto Body = utils_transform::Get_EntityCurrentTransform(_Body);
        auto FootInBody = Body.InverseTransformPosition(Foot.Get_Position());
        _Samples++;
        if (Foot.Get_Phase() == ECk_ProceduralLeg_FootPhase::Planted &&
            Foot.Get_Contact() == ECk_ProceduralLeg_FootContact::Trusted &&
            Math::Abs(Radius - 90.0) <= 0.5 && FootInBody.Y < -25.0)
        {
            _Supported++;
        }
        _Snapshot = UCk_Utils_AutoTest_UE::Get_ProceduralAnimationLegSnapshot(_Body, n"Leading", _Origin);
        auto Result = OutResult;
        Result.Set(Now - _WatchStart >= 0.3);
    }

    UFUNCTION()
    private void Step_Check(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        ck::Trace(f"[CURVED-SPREAD] {_Snapshot}");
        Assert_True(_Samples > 0, "The stationary leading foot was observed");
        Assert_Equals_Int(_Supported, _Samples,
            "Every leading-foot sample plants on the convex surface outside the body band");
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
