// Language=angelscript

namespace ck_test_traverses_ramp_and_wall
{
    // A lap turns at four corners: floor to ramp, ramp to wall, wall to ramp and ramp to floor.
    const int32 MaxSupportFlipsPerLap = 4;
    // At the floor-to-ramp corner the down ray sees the ramp first and the body coasts for the confirm time before it turns, which
    // leaves the root 0.36 of its clearance nearer the ramp than the clearance at worst; the bound allows 0.1 more.
    const float MaxRootDepthFraction = 0.46;
}

class UCk_AutoTest_ProceduralAnimation_TraversesRampAndWall : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 74.0f;
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
            Complete = Complete && Crawler.Progress.Traversals > 0 && Crawler.Evidence.SawWall;
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
            Assert_True(Flips <= ck_test_traverses_ramp_and_wall::MaxSupportFlipsPerLap, f"The accepted support turns more than 30 degrees at most at the course's corners in a lap (got {Flips})");
            Assert_True(Depth <= ck_test_traverses_ramp_and_wall::MaxRootDepthFraction, f"The root never sits deeper than the bound inside its clearance (got {Depth :.3} of it)");
            Assert_True(Crawler.Evidence.SawWall && Crawler.Progress.Traversals > 0, "Actual contact normals and ordered spatial milestones prove the wall traversal");
            Assert_True(Crawler.Evidence.WallSupportSamples > 0 && Crawler.Evidence.WallSupportLost == false,
                "The accepted support normal stays on the wall while the body advances above the ramp");
            Assert_True(Crawler.Evidence.InvalidOutput == false, "Root and foot outputs stayed finite across surface transitions");
            Assert_Equals_Int(Crawler.Get_ReplantedCount(), Crawler.Layout.LegCount, "All legs acquired a plant after swinging");
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
