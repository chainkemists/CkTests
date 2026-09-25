// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_CompletesConcaveLoop : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 60.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Fixture;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        if (_Fixture.Create(InHandle, FVector(120000.0, 40000.0, 600.0),
            ECkProceduralAnimationGym_Course::Ring, false) == false)
        {
            FinishFailure("The isolated 24-slab concave loop fixture could not be created");
            return;
        }
        Add_Step_WaitUntil("all rigs walk floor -> wall -> ceiling -> wall -> floor", n"Check_Loop", 6000);
        Add_Step("verify inverted contacts and completed support cycles", n"Step_Check");
        Add_Step("retire the fixture", n"Step_Destroy");
        Add_Step_WaitUntil("fixture lifetime subtree is gone", n"Check_Destroyed");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_Loop(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        auto Complete = _Fixture.Get_HasObservedWalking();
        for (auto Crawler : _Fixture.Crawlers)
        {
            Complete = Complete && Crawler.Traversals > 0 && Crawler.SawWall && Crawler.SawCeiling;
        }
        auto Result = OutResult;
        Result.Set(Complete);
    }

    UFUNCTION()
    private void Step_Check(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        for (auto Crawler : _Fixture.Crawlers)
        {
            Assert_True(Crawler.SawCeiling, "At least one trusted foot contact normal faced down on the ceiling");
            Assert_True(Crawler.SawWall && Crawler.Traversals > 0, "Ordered location milestones prove a complete loop");
            Assert_True(Crawler.InvalidOutput == false, "Body and foot outputs remained finite through inversion");
            Assert_Equals_Int(Crawler.Get_ReplantedCount(), Crawler.LegCount, "Every leg completed swing and reacquired support");
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
