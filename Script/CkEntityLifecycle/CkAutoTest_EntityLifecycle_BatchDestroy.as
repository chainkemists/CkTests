// Language=angelscript

//============================================================================
// CK ENTITY LIFECYCLE — AUTOMATION TEST: BATCH DESTROY
//============================================================================
//
// Verifies Request_DestroyEntities (the batch variant): given an array of
// child handles, every child fires OnBeginDestroy. Test finishes once all
// children have been observed.
//
// Mirrors the batch-destroy phase in CkEntityLifecycleGym_DestroyCallbacks.
//============================================================================

class UCk_AutoTest_EntityLifecycle_BatchDestroy : UCk_AutoTest_Base
{
    private int32 _DestroyCallbackCount = 0;
    private const int32 _ExpectedDestroyCount = 3;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto ToDestroy = TArray<FCk_Handle>();
        for (int32 i = 0; i < _ExpectedDestroyCount; i++)
        {
            auto Child = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
            utils_handle::Set_DebugName(Child, n"AutoTest_BatchChild");
            utils_entity_lifetime::BindTo_OnBeginDestroy(Child,
                FCk_Delegate_OnBeginDestroy(this, n"OnChildBeginDestroy"));
            ToDestroy.Add(Child);
        }

        utils_entity_lifetime::Request_DestroyEntities(ToDestroy);
    }

    UFUNCTION()
    private void OnChildBeginDestroy(FCk_Handle InHandle)
    {
        if (IsFinished()) { return; }

        _DestroyCallbackCount++;
        if (_DestroyCallbackCount >= _ExpectedDestroyCount)
        {
            Assert_Equals_Int(_DestroyCallbackCount, _ExpectedDestroyCount,
                "OnBeginDestroy should fire once per entity in the batch");
            FinishSuccess();
        }
    }
}
