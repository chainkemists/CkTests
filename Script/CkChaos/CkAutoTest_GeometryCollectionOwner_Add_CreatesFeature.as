// Language=angelscript

//============================================================================
// CK CHAOS — AUTOMATION TEST: GEOMETRY COLLECTION OWNER ADD
//============================================================================
//
// First-coverage seed for CkChaos. GeometryCollectionOwner Add ensures
// the entity has FFragment_OwningActor_Current, so the test spawns an
// actor-backed entity via ACkAutoTest_ActorEntity_Helper, waits for the
// entity to be ready, then verifies the owner Add succeeds.
//============================================================================

class UCk_AutoTest_GeometryCollectionOwner_Add_CreatesFeature : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private ACkAutoTest_ActorEntity_Helper _Helper;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Helper = Cast<ACkAutoTest_ActorEntity_Helper>(SpawnActor(
            ACkAutoTest_ActorEntity_Helper, FVector::ZeroVector, FRotator::ZeroRotator));
        if (ck::Is_NOT_Valid(_Helper))
        {
            FinishFailure("Failed to spawn ActorEntity helper");
            return;
        }

        utils_pending_entity_script::Promise_OnConstructed(
            _Helper.PendingEntity,
            FCk_Delegate_EntityScript_Constructed(this, n"OnEntityReady"));
    }

    UFUNCTION()
    private void OnEntityReady(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        if (IsFinished()) { return; }

        auto OwnedEntity = FCk_Handle(InEntityScriptHandle);
        auto Owner = utils_geometry_collection_owner::Add(OwnedEntity, ECk_Replication::DoesNotReplicate);

        Assert_True(ck::IsValid(Owner),
            "utils_geometry_collection_owner::Add should return a valid handle once the entity has an OwningActor");
        Assert_True(utils_geometry_collection_owner::Has(OwnedEntity),
            "After Add, Has on the owning entity should report true");

        FinishSuccess();
    }
}
