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
//
// Both hops cross a real observable transition — invalid→valid on Add, then
// valid→invalid on the cascade — so neither is a fixed delay.
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

        Add_Step_WaitUntil("the query handle becomes valid",            n"Check_QueryValid");
        Add_Step(          "destroy the query's owner",                 n"Step_DestroyOwner");
        Add_Step_WaitUntil("the cascade invalidates the query handle",  n"Check_QueryInvalid");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_DestroyOwner(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_entity_lifetime::Request_DestroyEntity(_OwnerChild);
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_QueryValid(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(ck::IsValid(_Query));
    }

    UFUNCTION()
    private void Check_QueryInvalid(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(ck::Is_NOT_Valid(_Query));
    }
}
