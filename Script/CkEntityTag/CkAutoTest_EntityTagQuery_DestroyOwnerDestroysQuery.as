// Language=angelscript

//============================================================================
// CK ENTITY TAG QUERY — AUTOMATION TEST: DESTROY-OWNER CASCADES TO QUERY
//============================================================================
//
// The query lives as a child entity under its owner. Destroying the owner
// must cascade-destroy the query entity, leaving the FCk_Handle_EntityTagQuery
// invalid on the next pump.
//
// Setup: create a dedicated child entity to act as the owner (so the test
// entity itself isn't destroyed mid-callback). Add a query under it, then
// destroy the child.
//============================================================================

class UCk_AutoTest_EntityTagQuery_DestroyOwnerDestroysQuery : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle                _OwnerChild;
    private FCk_Handle_EntityTagQuery _Query;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        // Sub-owner so the test's own entity (and this script) stay alive
        // through the cascade.
        _OwnerChild = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Query = utils_entity_tag_query::Add(_OwnerChild);

        WaitOneFrame(n"AfterAdd");
    }

    UFUNCTION()
    private void AfterAdd(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(ck::IsValid(_Query),
            "Query handle must be valid after Add");

        utils_entity_lifetime::Request_DestroyEntity(_OwnerChild);

        WaitOneFrame(n"AfterDestroy");
    }

    UFUNCTION()
    private void AfterDestroy(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(ck::Is_NOT_Valid(_Query),
            "Destroying the owner must cascade-destroy the child query entity; handle should be invalid after one settle frame");

        FinishSuccess();
    }
}
