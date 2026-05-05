// Language=angelscript

//============================================================================
// CK REGISTRY — AUTOMATION TEST: HANDLE-IN-FRAGMENT LIFECYCLE
//============================================================================
//
// Verifies that storing FCk_Handle inside a fragment of an entity that lives
// in the same registry the handle references does not break the destruction
// cascade.
//
//   1. Create parent and child entities (child parented to parent for
//      lifetime ownership cascade).
//   2. Store the child handle inside FCk_Fragment_AutoTest_HandleHolder on
//      the parent.
//   3. Bind OnBeginDestroy on both parent and child.
//   4. Request_DestroyEntity on the parent.
//   5. Both callbacks must fire (parent + cascade-to-child).
//
// Pre-migration: cycle is benign because Request_DestroyEntity tears entities
// down through the standard request flow, not via shared-ptr release. The
// test locks in the contract: stashing a handle in a fragment must NOT change
// the destroy lifecycle of the entity that handle points to.
// Post-migration: the handle is just (slot, gen) bytes — there is no
// ref-cycle to break — and the same observed behaviour must hold.
//
// Uses the latent OnBeginDestroy pattern because Request_DestroyEntity is
// deferred; synchronous post-destroy assertions wouldn't see the destruction.
//============================================================================

class UCk_AutoTest_Registry_HandleInFragmentLifecycle : UCk_AutoTest_Base
{
    private FCk_Handle _Parent;
    private FCk_Handle _Child;
    private bool       _ParentDestroyed = false;
    private bool       _ChildDestroyed  = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        _Parent = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        Assert_True(ck::IsValid(_Parent), "Parent must be valid after CreateEntity");

        _Child = utils_entity_lifetime::Request_CreateEntity(_Parent);
        Assert_True(ck::IsValid(_Child), "Child must be valid after CreateEntity");

        // Store the child handle inside a fragment on the parent. Locks in the
        // contract that this is benign for the destroy cascade.
        auto Frag = FCk_Fragment_AutoTest_HandleHolder();
        Frag.Set_StoredHandle(_Child);
        _Parent.Add_Fragment(Frag);

        // Bind both ends so we can confirm the cascade fully propagates.
        utils_entity_lifetime::BindTo_OnBeginDestroy(_Parent,
            FCk_Delegate_OnBeginDestroy(this, n"OnParentBeginDestroy"));

        utils_entity_lifetime::BindTo_OnBeginDestroy(_Child,
            FCk_Delegate_OnBeginDestroy(this, n"OnChildBeginDestroy"));

        utils_entity_lifetime::Request_DestroyEntity(_Parent);
    }

    UFUNCTION()
    private void OnParentBeginDestroy(FCk_Handle InHandle)
    {
        if (IsFinished()) { return; }
        _ParentDestroyed = true;
        TryFinish();
    }

    UFUNCTION()
    private void OnChildBeginDestroy(FCk_Handle InHandle)
    {
        if (IsFinished()) { return; }
        _ChildDestroyed = true;
        TryFinish();
    }

    private void TryFinish()
    {
        if (_ParentDestroyed && _ChildDestroyed)
        {
            Assert_True(true,
                "Both parent and child OnBeginDestroy fired; fragment-stored handle did not block cascade");
            FinishSuccess();
        }
    }
}
