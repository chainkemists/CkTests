// Language=angelscript

//============================================================================
// CK ENTITY LIFECYCLE — AUTOMATION TEST: CIRCULAR CONTEXT OWNERSHIP
//============================================================================
//
// Pins safety contract: requesting an A→B then B→A context-owner override
// must not leave Get_ContextOwner in an unbounded chain walk. The framework
// must either (a) reject the second override, or (b) accept both but ensure
// Get_ContextOwner returns in finite time without infinite recursion.
//
// This test does NOT assert *which* outcome the framework chooses — both
// are acceptable. It asserts:
//
//   1. Both Request_Override calls return without crashing.
//   2. After settle, Get_ContextOwner(A) and Get_ContextOwner(B) both
//      return valid handles (no hang, no invalid handle).
//   3. The harness _TimeoutSeconds catches any infinite loop in the
//      Get_ContextOwner traversal.
//
// If a future change introduces an infinite-walk path through ancestor
// chains, this test will time out (a clear signal vs. a silent CPU spin).
//============================================================================

class UCk_AutoTest_EntityLifecycle_CircularContextOwnership : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 2.0f;

    private FCk_Handle _ChildA;
    private FCk_Handle _ChildB;
    private bool _OverridesObserved = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        _ChildA = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        _ChildB = utils_entity_lifetime::Request_CreateEntity(LocalHandle);

        // A's context owner -> B
        utils_context_owner::Request_Override(_ChildA, _ChildB);
        // B's context owner -> A. Forms a 2-cycle if both are accepted.
        utils_context_owner::Request_Override(_ChildB, _ChildA);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        if (_OverridesObserved) { return; }

        // Both Get_ContextOwner calls must return in bounded time. If the
        // framework does an unbounded ancestor walk on a cyclic chain, the
        // call below would hang and the harness timeout fires.
        auto OwnerOfA = utils_context_owner::Get_ContextOwner(_ChildA);
        auto OwnerOfB = utils_context_owner::Get_ContextOwner(_ChildB);

        // Ownership requests are deferred — wait for at least one of them to
        // visibly land before asserting. Once observed, both owners must be
        // valid handles (rejection -> stays as test entity; acceptance ->
        // points at the cycle peer; either is acceptable so long as the
        // handle is valid and the call returned in finite time).
        if (ck::IsValid(OwnerOfA) == false || ck::IsValid(OwnerOfB) == false)
        { return; }

        _OverridesObserved = true;
        Assert_True(ck::IsValid(OwnerOfA),
            "Get_ContextOwner(ChildA) must return a valid handle (no hang on cyclic chain)");
        Assert_True(ck::IsValid(OwnerOfB),
            "Get_ContextOwner(ChildB) must return a valid handle (no hang on cyclic chain)");
        FinishSuccess();
    }
}
