// Language=angelscript

//============================================================================
// CK ENTITY LIFECYCLE - AUTOMATION TEST: IS-TRANSIENT-ENTITY SEMANTICS
//============================================================================
//
// Disambiguates the `Get_IsTransientEntity` contract that the existing
// OwnershipTree test only sketches in a comment:
//
//   "Get_IsTransientEntity checks whether the handle IS the singleton
//    transient root entity for its registry, not 'was this entity created
//    with a transient owner'. A child of the transient root is transient-
//    OWNED but is not itself the transient entity, so the function returns
//    false for it."  - CkEntityLifetime_Utils.cpp:185
//
// Three handles are checked:
//
//   1. The test entity (a normal owned entity)            - expect false
//   2. A child created via Request_CreateEntity_TransientOwner
//      (transient-OWNED, not itself the transient root)   - expect false
//   3. The transient root itself (Get_LifetimeOwner of #2) - expect true
//
// If these collapse to the same answer, the API is no longer disambiguating
// "is the singleton root" from "lives under the transient root" - that's
// the semantic confusion this test pins down.
//============================================================================

class UCk_AutoTest_EntityLifecycle_IsTransientEntityVsContext : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        // Case 1: normal owned test entity is NOT the transient root.
        Assert_True(utils_entity_lifetime::Get_IsTransientEntity(LocalHandle) == false,
            "Test entity (a normal owned entity) should NOT be the transient root");

        // Case 2: a transient-owned child is NOT itself the transient root.
        auto TransientOwned = utils_entity_lifetime::Request_CreateEntity_TransientOwner();
        Assert_True(utils_entity_lifetime::Get_IsTransientEntity(TransientOwned) == false,
            "A child of the transient root is transient-OWNED, not itself the transient root - Get_IsTransientEntity should return false");

        // Case 3: the actual transient root reports true.
        auto TransientRoot = utils_entity_lifetime::Get_LifetimeOwner(TransientOwned);
        Assert_True(ck::IsValid(TransientRoot),
            "Get_LifetimeOwner of a transient-owned entity should be a valid handle (the transient root)");
        Assert_True(utils_entity_lifetime::Get_IsTransientEntity(TransientRoot) == true,
            "The singleton transient root entity must report Get_IsTransientEntity=true");

        utils_entity_lifetime::Request_DestroyEntity(TransientOwned);
        FinishSuccess();
    }
}
