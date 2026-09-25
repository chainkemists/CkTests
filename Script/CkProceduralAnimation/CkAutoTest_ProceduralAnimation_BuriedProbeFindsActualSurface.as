// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_BuriedProbeFindsActualSurface : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Fixture;
    private FCk_Handle_ProceduralGait _Gait;
    private FVector _Origin = FVector(120000.0, 55000.0, 600.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        if (_Fixture.Create(InHandle, _Origin, ECkProceduralAnimationGym_Course::Flat, false, 1) == false)
        {
            FinishFailure("The isolated buried-probe floor fixture could not be created");
            return;
        }
        // Do not call fixture.Update: only its actual Jolt floor is needed. A surface mover
        // would lift this intentionally buried root and conceal the gait probe defect.
        Add_Step_WaitUntil("actual Jolt floor is queryable", n"Check_FloorReady");
        Add_Step("compose gait alone with its first two ray starts inside the floor", n"Step_ComposeGait");
        Add_Step_WaitUntil("gait publishes its initial planted feet", n"Check_GaitReady");
        Add_Step("verify wider probing found the exterior floor surface", n"Step_CheckFeet");
        Add_Step("retire the owned floor and gait", n"Step_Destroy");
        Add_Step_WaitUntil("entities and actual collision are gone", n"Check_Destroyed");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_FloorReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Fixture.Get_AreSurfacesReady());
    }

    UFUNCTION()
    private void Step_ComposeGait(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Owner = _Fixture.SceneRoot;
        auto Root = utils_entity_lifetime::Request_CreateEntity(Owner);
        Root.Request_OverrideToSelf();
        _Fixture.Entities.Add(Root);
        utils_transform::Add(Root, FTransform(_Origin + FVector(0.0, 0.0, 10.0)), ECk_Replication::DoesNotReplicate);

        auto Legs = TArray<FCk_ProceduralGait_Leg>();
        for (auto Index = 0; Index < 2; Index++)
        {
            auto Side = Index == 0 ? -1.0 : 1.0;
            auto Leg = FCk_ProceduralGait_Leg();
            Leg.Set_Id(FName(f"BuriedLeg{Index}"));
            Leg.Set_HipLocal(FVector(0.0, Side * 30.0, 0.0));
            Leg.Set_RestFootLocal(FVector(0.0, Side * 100.0, -65.0));
            Leg.Set_PhaseOffset(Index == 0 ? 0.0f : 0.5f);
            Legs.Add(Leg);
        }
        auto Params = FCk_Fragment_ProceduralGait_ParamsData();
        Params.Set_Legs(Legs);
        Params.Set_ProbeUp(10.0f);
        Params.Set_ProbeDown(200.0f);
        Params.Set_OutwardProbeLean(0.0f);
        _Gait = utils_procedural_gait::Add(Root, Params);
        Assert_True(ck::IsValid(_Gait), "Gait admits the valid authored legs without any mover or rig");

        // Fixture floor spans local Z [-50, 0]. Ideal feet are at -55, so the first
        // ray begins at -45 INSIDE the floor. Jolt reports that as a zero-fraction hit.
        auto Hit = utils_jolt_query::Get_RayCast(_Origin + FVector(0.0, 100.0, -45.0),
            _Origin + FVector(0.0, 100.0, -255.0), FCk_Jolt_QueryFilter());
        Assert_True(Hit.Get_HasHit(), "The precondition actually exercises an inside-solid ray");
        Assert_Equals_Float(Hit.Get_Fraction(), 0.0, 0.0001, "Jolt reports the buried start at fraction zero");
    }

    UFUNCTION()
    private void Check_GaitReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(ck::IsValid(_Gait) && utils_procedural_gait::Get_IsReady(_Gait));
    }

    UFUNCTION()
    private void Step_CheckFeet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Feet = utils_procedural_gait::Get_Feet(_Gait);
        Assert_Equals_Int(Feet.Num(), 2, "Both authored feet have outputs");
        for (auto Foot : Feet)
        {
            Assert_True(Foot.Get_Planted() && Foot.Get_ContactTrusted(), "The exterior surface is a trusted initial plant");
            Assert_Equals_Float(Foot.Get_Position().Z, _Origin.Z, 0.5,
                "A wider probe must find Z=600, rather than treating the buried Z=555 start as the floor");
            Assert_True(Foot.Get_Normal().Z > 0.99, "The accepted normal is the exterior upward floor normal");
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
