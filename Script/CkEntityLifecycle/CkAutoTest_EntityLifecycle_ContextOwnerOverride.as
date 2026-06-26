// Language=angelscript

//============================================================================
// CK ENTITY LIFECYCLE — AUTOMATION TEST: CONTEXT OWNER OVERRIDE
//============================================================================
//
// Verifies the context-ownership chain API:
//   1. Spawn ChildA and ChildB as children of the test entity.
//   2. Override ChildA's context owner to ChildB (Request_Override).
//   3. Get_ContextOwner(ChildA) returns ChildB.
//   4. Override ChildA's context owner to itself (Request_OverrideToSelf).
//   5. Get_ContextOwner(ChildA) returns ChildA.
//
// Pins down the runtime mutability contract for context ownership —
// gameplay code (e.g. ability transfer, possession swap) relies on
// being able to swing the owner pointer at runtime.
//============================================================================

class UCk_AutoTest_EntityLifecycle_ContextOwnerOverride : UCk_AutoTest_Base
{
    private FCk_Handle _ChildA;
    private FCk_Handle _ChildB;
    private bool _OverrideToBObserved = false;
    private int32 _TicksSinceOverride = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        _ChildA = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        utils_handle::Set_DebugName(_ChildA, n"AutoTest_ContextChildA");
        _ChildB = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        utils_handle::Set_DebugName(_ChildB, n"AutoTest_ContextChildB");

        // Override A's context owner to B; the change is request-deferred,
        // so we poll on tick until Get_ContextOwner reports B.
        utils_context_owner::Request_Override(_ChildA, _ChildB);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (!_OverrideToBObserved)
        {
            auto OwnerOfA = utils_context_owner::Get_ContextOwner(_ChildA);
            if (utils_handle::IsEqual(OwnerOfA, _ChildB))
            {
                _OverrideToBObserved = true;
                Assert_True(true, "Get_ContextOwner(ChildA) should equal ChildB after Request_Override");
                utils_context_owner::Request_OverrideToSelf(_ChildA);
            }
            return;
        }

        _TicksSinceOverride++;
        auto OwnerOfA = utils_context_owner::Get_ContextOwner(_ChildA);
        if (utils_handle::IsEqual(OwnerOfA, _ChildA))
        {
            Assert_True(true, "Get_ContextOwner(ChildA) should equal ChildA after Request_OverrideToSelf");
            FinishSuccess();
        }
    }
}
