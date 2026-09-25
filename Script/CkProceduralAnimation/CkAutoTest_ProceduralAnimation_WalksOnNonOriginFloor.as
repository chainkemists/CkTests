// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_WalksOnNonOriginFloor : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 12.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Fixture;
    private FVector _Origin = FVector(120000.0, 30000.0, 600.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        if (_Fixture.Create(InHandle, _Origin, ECkProceduralAnimationGym_Course::Flat, false) == false)
        {
            FinishFailure("The isolated three-rig floor fixture could not be created");
            return;
        }
        Add_Step_WaitUntil("all 4/6/8-leg rigs move and complete a swing on every leg", n"Check_Walking", 1200);
        Add_Step("verify real contacts above the non-origin floor", n"Step_CheckContacts");
        Add_Step("retire the fixture", n"Step_Destroy");
        Add_Step_WaitUntil("all owned parts and collision bodies are destroyed", n"Check_Destroyed");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_Walking(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        auto Result = OutResult;
        Result.Set(_Fixture.Get_HasObservedWalking());
    }

    UFUNCTION()
    private void Step_CheckContacts(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_Fixture.Crawlers.Num(), 3, "The fixture contains three distinct authored leg counts");
        for (auto Crawler : _Fixture.Crawlers)
        {
            Assert_True(utils_surface_motion::Get_Support(Crawler.Handles.Motion) == ECk_SurfaceMotion_Support::Grounded, "The body found the actual Jolt floor");
            Assert_True(Crawler.Get_ReplantedCount() == Crawler.Layout.LegCount,
                "Every leg completed a swing and acquired a trusted plant");
            auto Position = utils_transform::Get_EntityCurrentLocation(Crawler.Handles.Root);
            Assert_Equals_Float(Position.Z, _Origin.Z + ck_procedural_gym::BodyClearance, 8.0,
                "The body holds its authored ground clearance");
            auto Contacts = 0;
            for (auto Index = 0; Index < Crawler.Handles.Legs.Num(); Index++)
            {
                auto Foot = utils_procedural_leg::Get_Foot(Crawler.Handles.Legs[Index]);
                if (Foot.Get_Phase() == ECk_ProceduralLeg_FootPhase::Planted && Foot.Get_Contact() == ECk_ProceduralLeg_FootContact::Trusted)
                {
                    Contacts++;
                    Assert_Equals_Float(Foot.Get_Position().Z, _Origin.Z, 3.0,
                        "Trusted planted feet touch Z=600 rather than a failed query's world origin");
                    Assert_True(Foot.Get_Normal().Z > 0.99, "The contact normal matches the actual floor");
                    auto VisibleFoot = utils_transform::Get_EntityCurrentLocation(Crawler.Handles.VisibleFeet[Index]);
                    Assert_Equals_Float(VisibleFoot.Z, _Origin.Z, 8.0,
                        "The real rig output moves the authored foot entity to the floor contact");
                }
            }
            Assert_True(Contacts > 0, "At least one trusted support foot is present at the assertion");
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
        auto Hit = utils_jolt_query::Get_RayCast(_Origin + FVector(0.0, 0.0, 100.0),
            _Origin - FVector(0.0, 0.0, 100.0), FCk_Jolt_QueryFilter());
        Result.Set(_Fixture.Get_IsDestroyed() && Hit.Get_HasHit() == false);
    }
}
