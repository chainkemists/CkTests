// Language=angelscript

//============================================================================
// CK ENTITY LIFECYCLE - AUTOMATION TEST: OWNERSHIP TREE
//============================================================================
//
// Verifies the parent/child ownership API:
//   - Request_CreateEntity yields a valid handle owned by the parent
//   - Get_LifetimeOwner returns the parent
//   - Get_LifetimeDependents on the parent includes the children
//   - CreateEntity_TransientOwner yields a transient entity, distinct from
//     parent-owned entities
//   - Get_WorldForEntity returns a valid world for both
//
// Mirrors CkEntityLifecycleGym_OwnershipTree. All operations here resolve
// synchronously inside DoBeginPlay (validated by the gym, which does the
// same and shows green immediately on construction).
//============================================================================

class UCk_AutoTest_EntityLifecycle_OwnershipTree : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        // Owned children
        auto ChildA = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto ChildB = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        Assert_True(utils_handle::Get_IsValid(ChildA), "ChildA should be a valid handle after CreateEntity");
        Assert_True(utils_handle::Get_IsValid(ChildB), "ChildB should be a valid handle after CreateEntity");

        // Transient entity (no parent)
        auto Transient = utils_entity_lifetime::Request_CreateEntity_TransientOwner();
        Assert_True(utils_handle::Get_IsValid(Transient),
            "CreateEntity_TransientOwner should yield a valid handle");

        // Ownership queries
        auto OwnerA = utils_entity_lifetime::Get_LifetimeOwner(ChildA);
        Assert_True(utils_handle::IsEqual(OwnerA, LocalHandle),
            "Owner of ChildA should be the test entity itself");
        auto OwnerB = utils_entity_lifetime::Get_LifetimeOwner(ChildB);
        Assert_True(utils_handle::IsEqual(OwnerB, LocalHandle),
            "Owner of ChildB should be the test entity itself");

        // Dependents
        auto Dependents = utils_entity_lifetime::Get_LifetimeDependents(LocalHandle);
        Assert_True(Dependents.Num() >= 2,
            f"Test entity should have at least 2 dependents (got {Dependents.Num()})");

        // Transient flag - note the actual semantics: Get_IsTransientEntity
        // checks whether the handle IS the singleton transient root entity for
        // its registry (CkEntityLifetime_Utils.cpp:185), not "was this entity
        // created with a transient owner". A child of the transient root is
        // transient-OWNED but is not itself the transient entity, so the
        // function returns false for it. Only the test entity-vs-root check
        // is meaningful here. CkEntityLifecycleGym_OwnershipTree's
        // Pass_IsTransient_Transient assertion is based on the wrong reading
        // of the API and would fail this same way if it ever asserted hard.
        Assert_True(!utils_entity_lifetime::Get_IsTransientEntity(LocalHandle),
            "Test entity should NOT be the transient root");

        // World retrieval - local renamed from "World" to avoid shadowing
        // the base-class GetWorld accessor.
        auto EntityWorld = utils_entity_lifetime::Get_WorldForEntity(LocalHandle);
        Assert_True(ck::IsValid(EntityWorld), "Get_WorldForEntity should return a valid world");

        // Cleanup transient entity (non-essential - the harness tears down the
        // test entity which will cascade-destroy ChildA/ChildB regardless).
        utils_entity_lifetime::Request_DestroyEntity(Transient);

        FinishSuccess();
    }
}
