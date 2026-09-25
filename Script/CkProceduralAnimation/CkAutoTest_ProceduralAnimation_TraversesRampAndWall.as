// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_TraversesRampAndWall : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 55.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Fixture;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        if (_Fixture.Create(InHandle, FVector(120000.0, 35000.0, 600.0),
            ECkProceduralAnimationGym_Course::RampWall, false) == false)
        {
            FinishFailure("The isolated ramp-to-wall fixture could not be created");
            return;
        }
        Add_Step_WaitUntil("every rig climbs the wall and returns across the ramp", n"Check_Traversal", 5000);
        Add_Step("check observed wall contacts and completed foot steps", n"Step_Check");
        Add_Step("retire the fixture", n"Step_Destroy");
        Add_Step_WaitUntil("fixture lifetime subtree is gone", n"Check_Destroyed");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_Traversal(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        auto Complete = _Fixture.Get_HasObservedWalking();
        for (auto Crawler : _Fixture.Crawlers)
        {
            Complete = Complete && Crawler.Traversals > 0 && Crawler.SawWall;
        }
        auto Result = OutResult;
        Result.Set(Complete);
    }

    UFUNCTION()
    private void Step_Check(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        for (auto Crawler : _Fixture.Crawlers)
        {
            Assert_True(Crawler.SawWall && Crawler.Traversals > 0, "Actual contact normals and ordered spatial milestones prove the wall traversal");
            Assert_True(Crawler.WallSupportSamples > 0 && Crawler.WallSupportLost == false,
                "The accepted support normal stays on the wall while the body advances above the ramp");
            Assert_True(Crawler.InvalidOutput == false, "Root and foot outputs stayed finite across surface transitions");
            Assert_Equals_Int(Crawler.Get_ReplantedCount(), Crawler.LegCount, "All legs acquired a plant after swinging");
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
