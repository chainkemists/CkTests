// Language=angelscript

//============================================================================
// CK ENTITY TAG - AUTOMATION TEST: ANY-ENTITY LISTENER FIRES ON ENTITY DESTROY
//============================================================================
//
// Verifies J2 - the FProcessor_EntityTag_BroadcastOnDestroy fan-out fires
// Removed for every tag a dying entity carried, so listeners observe a clean
// 1->0 transition without having to poll for entity validity.
//
// Entity destruction is deferred, so the second phase waits on the fan-out
// arriving; that it arrives exactly once stays an assertion.
//============================================================================

class UCk_AutoTest_EntityTag_AnyEntity_FiresOnEntityDestroy : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle              _Listener;
    private FCk_Handle              _Subject;
    private int32                   _AddedFireCount   = 0;
    private int32                   _RemovedFireCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Listener = InHandle;

        utils_entity_tag::BindTo_OnTagUpdated_AnyEntity(_Listener,
            n"AutoTestEt_Any_DieTag",
            ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing,
            FCk_Delegate_EntityTag_OnTagUpdated_AnyEntity(this, n"OnAnyTag"));

        _Subject = utils_entity_lifetime::Request_CreateEntity(_Listener);
        utils_entity_tag::Add(_Subject, n"AutoTestEt_Any_DieTag");

        Add_Step_WaitUntil("listener sees the Added fan-out",         n"Check_Added");
        Add_Step(          "destroy the tagged subject entity",       n"Step_Destroy");
        Add_Step_WaitUntil("destroy fans out Removed for that tag",   n"Check_Removed");
        Add_Step(          "assert the fan-out fired exactly once",   n"Step_AssertOnce");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_Destroy(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_AddedFireCount, 1,
            "Listener must have fired Added once after the initial tag add");

        utils_entity_lifetime::Request_DestroyEntity(_Subject);
    }

    UFUNCTION()
    private void Step_AssertOnce(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_RemovedFireCount, 1,
            "Entity destruction must fan-out Removed for each tag the dying entity carried");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_Added(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_AddedFireCount >= 1);
    }

    UFUNCTION()
    private void Check_Removed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_RemovedFireCount >= 1);
    }

    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnAnyTag(FName InTag, FCk_Handle InEntity, ECk_EntityTagUpdate InUpdate)
    {
        if (InUpdate == ECk_EntityTagUpdate::Added)
        {
            _AddedFireCount += 1;
        }
        else
        {
            _RemovedFireCount += 1;
        }
    }
}
