// Language=angelscript

namespace ck_test_completes_concave_loop
{
    // The loop turns 15 degrees at every slab, below any flip.
    const int32 MaxSupportFlipsPerLap = 0;
    // The loop keeps the root within 0.02 of its clearance of every slab; the bound allows 0.1 more.
    const float MaxRootDepthFraction = 0.12;
}

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
            Complete = Complete && Crawler.Progress.Traversals > 0 && Crawler.Evidence.SawWall && Crawler.Evidence.SawCeiling;
        }
        auto Result = OutResult;
        Result.Set(Complete);
    }

    UFUNCTION()
    private void Step_Check(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        for (auto Crawler : _Fixture.Crawlers)
        {
            auto Legs = Crawler.Layout.LegCount;
            auto Flips = Crawler.Evidence.SupportFlips;
            auto Depth = Crawler.Evidence.WorstRootDepthFraction;
            ck::Trace(f"[SupportEvidence] {Legs} legs: support flips over 30 degrees in the first lap {Flips}, worst root depth {Depth :.3} of the clearance",
                n"SupportEvidence", 0.0f);
            Assert_True(Flips <= ck_test_completes_concave_loop::MaxSupportFlipsPerLap, f"The accepted support turns more than 30 degrees at most at the course's corners in a lap (got {Flips})");
            Assert_True(Depth <= ck_test_completes_concave_loop::MaxRootDepthFraction, f"The root never sits deeper than the bound inside its clearance (got {Depth :.3} of it)");
            Assert_True(Crawler.Evidence.SawCeiling, "At least one trusted foot contact normal faced down on the ceiling");
            Assert_True(Crawler.Evidence.SawWall && Crawler.Progress.Traversals > 0, "Ordered location milestones prove a complete loop");
            Assert_True(Crawler.Evidence.InvalidOutput == false, "Body and foot outputs remained finite through inversion");
            Assert_Equals_Int(Crawler.Get_ReplantedCount(), Crawler.Layout.LegCount, "Every leg completed swing and reacquired support");
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
