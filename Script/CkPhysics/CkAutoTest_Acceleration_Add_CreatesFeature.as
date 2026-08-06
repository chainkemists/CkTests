// Language=angelscript

//============================================================================
// CK PHYSICS — AUTOMATION TEST: ACCELERATION ADD CREATES FEATURE
//============================================================================
//
// First-coverage seed for CkPhysics. Acceleration is the building
// block for movement / projectile / force application. The seed pins
// the parameter round-trip: Add stores the configured starting
// acceleration and Get_CurrentAcceleration returns it immediately.
//
// Uses the actor-entity scaffold for the OwningActor fragment that
// the replicated path requires (we still pass DoesNotReplicate to
// skip the rep-fragment add; the scaffold gives a stable entity
// anyway for symmetry with other physics seeds).
//============================================================================

class UCk_AutoTest_Acceleration_Add_CreatesFeature : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private const FVector StartingAcceleration = FVector(100.0f, -50.0f, 25.0f);
    private ACkAutoTest_ActorEntity_Helper _Helper;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
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
        auto Params = FCk_Acceleration_Spec(ECk_LocalWorld::World, StartingAcceleration);
        auto Acceleration = utils_acceleration::Add(OwnedEntity, Params, ECk_Replication::DoesNotReplicate);

        Assert_True(ck::IsValid(Acceleration),
            "utils_acceleration::Add should return a valid FCk_Handle_Acceleration");
        Assert_True(utils_acceleration::Has(OwnedEntity),
            "After Add, Has on the owning entity should report true");

        auto Returned = utils_acceleration::Get_CurrentAcceleration(Acceleration);
        Assert_True(Returned.X == StartingAcceleration.X && Returned.Y == StartingAcceleration.Y && Returned.Z == StartingAcceleration.Z,
            f"Get_CurrentAcceleration should round-trip the configured StartingAcceleration (expected {StartingAcceleration.X},{StartingAcceleration.Y},{StartingAcceleration.Z}; got {Returned.X},{Returned.Y},{Returned.Z})");

        FinishSuccess();
    }
}
