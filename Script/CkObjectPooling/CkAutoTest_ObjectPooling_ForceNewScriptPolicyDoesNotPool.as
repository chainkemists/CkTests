// Language=angelscript
//
// CK OBJECT POOLING — AUTOMATION TEST: force-new EntityScript policy never pools
//
// The complement to the poolable-recycle test. A default InstancedPerEntity script
// is pinned-unique (DestroyOnRelease) and never enters a recycle pool. Across a
// spawn -> destroy -> spawn cycle the (class, archetype) pool stats must stay
// zeroed — no free list, no hits, no live pool instances — proving nothing was
// recycled.

class UCk_AutoTest_ObjectPooling_ForceNewScriptPolicyDoesNotPool : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle _FirstEntity;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto Pending = utils_entity_script::Request_SpawnEntity(
            InHandle, UCk_ObjectPoolingTest_ForceNewScript, FInstancedStruct());
        utils_pending_entity_script::Promise_OnConstructed(
            Pending, FCk_Delegate_EntityScript_Constructed(this, n"OnFirstConstructed"));
    }

    UFUNCTION()
    private void OnFirstConstructed(FCk_Handle_EntityScript InEntity)
    {
        if (IsFinished()) { return; }

        _FirstEntity = FCk_Handle(InEntity);

        // no recycle pool exists for a force-new class — stats are zeroed
        auto Stats = utils_object::Get_ObjectPoolStats(this, UCk_ObjectPoolingTest_ForceNewScript, nullptr);
        Assert_Equals_Int(Stats.Get_NumInUse(), 0, "spawn #1: force-new must not create a recycle pool (0 in use)");
        Assert_Equals_Int(Stats.Get_NumLiveInstances(), 0, "spawn #1: no pooled live instances");
        if (IsFinished()) { return; }

        utils_entity_lifetime::Request_DestroyEntity(_FirstEntity);
        WaitOneFrame(n"OnDestroySettled");
    }

    UFUNCTION()
    private void OnDestroySettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Pending = utils_entity_script::Request_SpawnEntity(
            DoGet_ScriptEntity(), UCk_ObjectPoolingTest_ForceNewScript, FInstancedStruct());
        utils_pending_entity_script::Promise_OnConstructed(
            Pending, FCk_Delegate_EntityScript_Constructed(this, n"OnSecondConstructed"));
    }

    UFUNCTION()
    private void OnSecondConstructed(FCk_Handle_EntityScript InEntity)
    {
        if (IsFinished()) { return; }

        auto Stats = utils_object::Get_ObjectPoolStats(this, UCk_ObjectPoolingTest_ForceNewScript, nullptr);
        Assert_Equals_Int(Stats.Get_NumHits(), 0, "spawn #2: force-new must never recycle (0 hits)");
        Assert_Equals_Int(Stats.Get_NumFree(), 0, "spawn #2: force-new must never park an instance (0 free)");
        Assert_Equals_Int(Stats.Get_NumLiveInstances(), 0, "spawn #2: no pool was ever created");

        FinishSuccess();
    }
}
