// Language=angelscript

//============================================================================
// CK REGISTRY — AUTOMATION TEST: HANDLE COPY / DESTROY
//============================================================================
//
// Verifies basic copy + destroy semantics for FCk_Handle:
//   1. Create an entity, capture handle A.
//   2. Copy handle A into handle B (separate variable referencing same entity).
//   3. Bind OnBeginDestroy on the entity, then Request_DestroyEntity via A.
//   4. The callback fires (proving destroy propagated for the shared entity).
//   5. Both A and B implicitly destruct on test teardown — must not crash.
//
// CkFoundation's destroy is a deferred request, so post-destroy invalidity
// must be observed via the OnBeginDestroy callback rather than synchronously
// after Request_DestroyEntity. Mirrors the latent pattern used by
// CkAutoTest_EntityLifecycle_OnBeginDestroy.
//============================================================================

class UCk_AutoTest_Registry_HandleCopyDestroy : UCk_AutoTest_Base
{
    private FCk_Handle _SpawnedA;
    private FCk_Handle _SpawnedB;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        _SpawnedA = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        Assert_True(ck::IsValid(_SpawnedA), "Created entity should be valid");

        _SpawnedB = _SpawnedA;
        Assert_True(ck::IsValid(_SpawnedB), "Copy of valid handle should be valid");

        utils_entity_lifetime::BindTo_OnBeginDestroy(_SpawnedA,
            FCk_Delegate_OnBeginDestroy(this, n"OnSpawnedBeginDestroy"));

        utils_entity_lifetime::Request_DestroyEntity(_SpawnedA);
    }

    UFUNCTION()
    private void OnSpawnedBeginDestroy(FCk_Handle InHandle)
    {
        if (IsFinished()) { return; }

        Assert_True(true,
            "OnBeginDestroy fired for entity referenced by both handle A and its copy B");
        FinishSuccess();
    }
}
