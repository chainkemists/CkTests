// Language=angelscript

//============================================================================
// CK REGISTRY - AUTOMATION TEST: ALLOCATOR + DESTROY-QUEUE STRESS
//============================================================================
//
// Validates that allocating N entities + destroying them all in the same PIE
// session does not produce slot-allocator or destroy-queue pathologies.
//
// Stress pattern:
//   1. Spawn N child entities off a long-lived test handle.
//   2. Verify each is valid (allocator throughput).
//   3. Bind OnBeginDestroy on the LAST one (the cheapest synchronisation point).
//   4. Request destroy on all of them.
//   5. Finish from the last entity's OnBeginDestroy callback.
//
// Cross-PIE coverage (the originally-named "PIE start/stop" intent) is NOT
// achievable from inside one AutoTest run - that stays operator-driven by
// running the suite repeatedly.
//============================================================================

class UCk_AutoTest_Registry_AllocatorStress : UCk_AutoTest_Base
{
    private const int32 _Count = 1000;
    private TArray<FCk_Handle> _Spawned;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        _Spawned.Reserve(_Count);
        for (int32 I = 0; I < _Count; ++I)
        {
            auto E = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
            Assert_True(ck::IsValid(E),
                "CreateEntity must produce valid handle during allocator stress");
            _Spawned.Add(E);
        }

        // Bind on the last one as the finish trigger; destroys are deferred,
        // so we need a latent point to confirm the queue actually drained.
        auto Last = _Spawned[_Spawned.Num() - 1];
        utils_entity_lifetime::BindTo_OnBeginDestroy(Last,
            FCk_Delegate_OnBeginDestroy(this, n"OnLastBeginDestroy"));

        // Enqueue destroys for all of them.
        for (int32 I = 0; I < _Spawned.Num(); ++I)
        {
            utils_entity_lifetime::Request_DestroyEntity(_Spawned[I]);
        }
    }

    UFUNCTION()
    private void OnLastBeginDestroy(FCk_Handle InHandle)
    {
        if (IsFinished()) { return; }
        FinishSuccess();
    }
}
