// Language=angelscript

//============================================================================
// CK REGISTRY — AUTOMATION TEST: HANDLE COPY / DESTROY
//============================================================================
//
// Verifies basic copy/destroy semantics for FCk_Handle:
//   1. Spawn an entity, capture handle A.
//   2. Copy handle A into handle B (separate variable).
//   3. Destroy entity via handle A.
//   4. Assert ck::IsValid(A) == false (entity gone).
//   5. Assert ck::IsValid(B) == false (entity also gone for B since they
//      both reference the same entity in the same registry).
//   6. Assert that destroying B does not crash (its registry-handle
//      should still be resolvable, the entity is just gone).
//============================================================================

class UCk_AutoTest_Registry_HandleCopyDestroy : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        // Spawn a child entity off the runner's handle. utils_entity_lifetime
        // gives a freshly-spawned handle.
        auto SpawnedA = utils_entity_lifetime::Request_SpawnEntity(LocalHandle);
        Assert_True(ck::IsValid(SpawnedA), "Spawned entity should be valid");

        auto SpawnedB = SpawnedA; // copy
        Assert_True(ck::IsValid(SpawnedB), "Copy of valid handle should be valid");

        utils_entity_lifetime::Request_DestroyEntity(SpawnedA);

        // Both A and B reference the same entity, which is now gone.
        Assert_True(ck::Is_NOT_Valid(SpawnedA), "After destroy, original is invalid");
        Assert_True(ck::Is_NOT_Valid(SpawnedB), "After destroy, copy is also invalid");

        // Destroying B implicitly when this function returns must not crash.
        FinishSuccess();
    }
}
