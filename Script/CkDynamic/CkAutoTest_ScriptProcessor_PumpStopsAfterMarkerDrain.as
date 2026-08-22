// Language=angelscript

//============================================================================
// CK DYNAMIC — AUTOMATION TEST: pump stops once the marker pool is drained
//============================================================================
//
// Sibling of CkAutoTest_ScriptProcessor_PumpDrainsSameFrame. That test pins
// that the cascade DOES drain in one frame; this one pins that the scheduler
// stops pumping the node once no LIVE entity carries the marker any more.
//
// Mechanism: every Ck fragment pool is in_place_delete, so removing the last
// marker leaves a tombstone and Has_AnyEntityWith (storage->empty()) reports
// the pool as non-empty forever after. The pump's dirty checker used that
// predicate, so the version bump from the final removal forced one more
// dispatch on a provably empty live view — a phantom pass, per node, per
// cascade. The tombstone-aware Has_AnyLiveEntityWith removes it.
//
// Shape: seed a throwaway entity with RemainingCascades = 0 so the fixture
// consumes and removes its marker, guaranteeing a leading hole in the pool
// regardless of how EnTT handles a last-element erase. Then run the real
// three-generation cascade on a second entity and read the fixture node's
// PumpCountThisFrame for the seed frame: 2 (generations 2 and 3) is the whole
// of the real work; 3 means the drained pool still looked dirty.
//============================================================================

class UCk_AutoTest_ScriptProcessor_PumpStopsAfterMarkerDrain : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle _SelfEntity;
    private FCk_Handle _TombstoneSeedEntity;
    private FCk_Handle _CascadeEntity;
    private int64      _SeedFrame = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        _SelfEntity = InHandle;

        auto Seed = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _TombstoneSeedEntity = Seed;

        Seed.Add_Fragment(FCk_Fragment_DynamicTest_PumpCascadeResults());

        auto& SeedMarker = Seed.AddOrGet_Fragment(FCk_Fragment_DynamicTest_PumpCascadeMarker);
        SeedMarker.RemainingCascades = 0;

        WaitOneFrame(n"OnTombstoneSeeded");
    }

    UFUNCTION()
    private void OnTombstoneSeeded(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto Seed = _TombstoneSeedEntity;
        auto& SeedResults = Seed.Get_Fragment(FCk_Fragment_DynamicTest_PumpCascadeResults);

        Assert_Equals_Int(SeedResults.ConsumedFrames.Num(), 1,
            "the tombstone seeder's marker must have been consumed (and removed) before the cascade is seeded — without that removal the pool carries no hole and the phantom pass cannot be observed");

        auto Cascade = utils_entity_lifetime::Request_CreateEntity(_SelfEntity);
        _CascadeEntity = Cascade;

        Cascade.Add_Fragment(FCk_Fragment_DynamicTest_PumpCascadeResults());

        auto& Marker = Cascade.AddOrGet_Fragment(FCk_Fragment_DynamicTest_PumpCascadeMarker);
        Marker.RemainingCascades = 2;

        _SeedFrame = utils_time::Get_FrameCounter();

        WaitOneFrame(n"OnSettled");
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto _CkPerfScope = ck::ScopedStat();

        const FName FixtureNodeName = n"/Script/Angelscript.Ck_TESTONLY_ScriptProcessor_PumpCascade";

        auto Cascade = _CascadeEntity;
        auto& Results = Cascade.Get_Fragment(FCk_Fragment_DynamicTest_PumpCascadeResults);

        Assert_Equals_Int(Results.ConsumedFrames.Num(), 3,
            "all three cascade generations must have been consumed by settle time");

        auto AllInSeedFrame = Results.ConsumedFrames.Num() == 3;
        for (int32 Index = 0; Index < Results.ConsumedFrames.Num(); ++Index)
        {
            if (Results.ConsumedFrames[Index] != _SeedFrame)
            {
                AllInSeedFrame = false;
            }
        }

        Assert_True(AllInSeedFrame,
            f"all three cascade generations must drain in the SEED frame [{_SeedFrame}] — otherwise the pump-count reading below is taken against the wrong frame");

        const int32 PumpCount = UCk_Utils_EcsWorld_Subsystem_UE::Get_Debug_ProcessorPumpCountForFrame(
            this, FixtureNodeName, _SeedFrame);

        const int32 FramePumpIterations = UCk_Utils_EcsWorld_Subsystem_UE::Get_Debug_FramePumpIterationCount(
            this, _SeedFrame);

        Assert_Equals_Int(PumpCount, 2,
            f"fixture must be pump-dispatched exactly twice (gen 2, gen 3); N>2 means a phantom dispatch on a tombstone-only marker (pump dirty check is not tombstone-aware). -1 means the node name [{FixtureNodeName}] or the seed frame [{_SeedFrame}] did not resolve in the scheduler debug history. Frame pump-iteration count for that frame: [{FramePumpIterations}]");

        const int32 QuietFramePumpIterations = UCk_Utils_EcsWorld_Subsystem_UE::Get_Debug_FramePumpIterationCount(
            this, _SeedFrame - 1);

        // Group-local settle shares the pump BUDGET with the global loop but is reported separately, so a
        // frame whose global count looks wrong can be read against what settle spent on the same frame.
        const int32 SeedLocalSettlePasses = UCk_Utils_EcsWorld_Subsystem_UE::Get_Debug_FrameLocalSettlePassCount(
            this, _SeedFrame);

        const int32 QuietLocalSettlePasses = UCk_Utils_EcsWorld_Subsystem_UE::Get_Debug_FrameLocalSettlePassCount(
            this, _SeedFrame - 1);

        Assert_Equals_Int(FramePumpIterations, QuietFramePumpIterations + 2,
            f"the seed frame must cost exactly two more pump passes than the quiet frame before it (the two real cascade passes) — got [{FramePumpIterations}] vs quiet [{QuietFramePumpIterations}]; a larger delta means a phantom pass still keeps the whole pump loop alive. Local-settle passes that frame: seed [{SeedLocalSettlePasses}] quiet [{QuietLocalSettlePasses}] — those share the pump budget but are deliberately NOT part of the counts above");

        FinishSuccess();
    }
}
