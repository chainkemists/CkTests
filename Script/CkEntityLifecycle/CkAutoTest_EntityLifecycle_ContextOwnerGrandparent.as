// Language=angelscript

//============================================================================
// CK ENTITY LIFECYCLE - AUTOMATION TEST: CONTEXT-OWNER GRANDPARENT WALK
//============================================================================
//
// Pins the contract of Get_ContextOwner traversal across a 3-deep chain.
// The existing ContextOwnerOverride test only verifies single-hop overrides.
// This test pins:
//
//   1. Get_ContextOwner returns the IMMEDIATE owner (one hop up), not the
//      transitive root.
//   2. Repeatedly applying Get_ContextOwner walks up the chain - Get(Get(A))
//      reaches the grandparent.
//
// Setup: chain A -> B -> C via Request_Override. Then:
//   Get_ContextOwner(A) == B
//   Get_ContextOwner(B) == C
//   Get_ContextOwner(Get_ContextOwner(A)) == C
//
// If the API ever silently switches to "transitive root" semantics, the
// first assertion fails. If the chain is broken at any link, the third
// assertion fails. Either signal regresses cleanly.
//============================================================================

class UCk_AutoTest_EntityLifecycle_ContextOwnerGrandparent : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private FCk_Handle _A;
    private FCk_Handle _B;
    private FCk_Handle _C;
    private bool _ChainObserved = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        _A = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        _B = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        _C = utils_entity_lifetime::Request_CreateEntity(LocalHandle);

        utils_handle::Set_DebugName(_A, n"AutoTest_GrandparentA");
        utils_handle::Set_DebugName(_B, n"AutoTest_GrandparentB");
        utils_handle::Set_DebugName(_C, n"AutoTest_GrandparentC");

        // Chain: A -> B -> C
        utils_context_owner::Request_Override(_A, _B);
        utils_context_owner::Request_Override(_B, _C);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        if (_ChainObserved) { return; }

        auto OwnerOfA = utils_context_owner::Get_ContextOwner(_A);
        auto OwnerOfB = utils_context_owner::Get_ContextOwner(_B);

        // Wait for both overrides to land.
        if (utils_handle::IsEqual(OwnerOfA, _B) == false) { return; }
        if (utils_handle::IsEqual(OwnerOfB, _C) == false) { return; }

        _ChainObserved = true;
        Assert_True(utils_handle::IsEqual(OwnerOfA, _B),
            "Get_ContextOwner(A) must return the IMMEDIATE owner B (one hop), not the chain root");
        Assert_True(utils_handle::IsEqual(OwnerOfB, _C),
            "Get_ContextOwner(B) must return C (one hop)");

        // Walk: applying Get_ContextOwner twice should reach the grandparent.
        auto Grandparent = utils_context_owner::Get_ContextOwner(OwnerOfA);
        Assert_True(utils_handle::IsEqual(Grandparent, _C),
            "Get_ContextOwner(Get_ContextOwner(A)) must reach C - chain traversal works by composition");

        FinishSuccess();
    }
}
