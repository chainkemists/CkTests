// Language=angelscript
//
// CK OBJECT POOLING - AUTOMATION TEST: poolable EntityScript policy recycles
//
// Proves the policy WIRING through the public pool-stats surface only (no reach
// into the script instance). Spawn a poolable EntityScript, destroy the entity
// (EndPlay releases the script to its pool), spawn the same class again. The
// second spawn must be a pool HIT reusing the parked instance - NumHits == 1,
// NumLiveInstances == 1.

class UCk_AutoTest_ObjectPooling_PoolableScriptPolicyRecycles : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle _FirstEntity;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto Pending = utils_entity_script::Request_SpawnEntity(
            InHandle, UCk_ObjectPoolingTest_PoolableScript, FInstancedStruct());
        utils_pending_entity_script::Promise_OnConstructed(
            Pending, FCk_Delegate_EntityScript_Constructed(this, n"OnFirstConstructed"));
    }

    UFUNCTION()
    private void OnFirstConstructed(FCk_Handle_EntityScript InEntity)
    {
        if (IsFinished()) { return; }

        _FirstEntity = FCk_Handle(InEntity);

        // spawn #1 is a miss that creates the instance
        auto Stats = utils_object::Get_ObjectPoolStats(this, UCk_ObjectPoolingTest_PoolableScript, nullptr);
        Assert_Equals_Int(Stats.Get_NumInUse(), 1, "spawn #1: exactly 1 instance in use");
        if (IsFinished()) { return; }

        utils_entity_lifetime::Request_DestroyEntity(_FirstEntity);
        WaitUntil(n"Check_InstanceParked", n"OnDestroySettled");
    }

    UFUNCTION()
    private void Check_InstanceParked(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_object::Get_ObjectPoolStats(this, UCk_ObjectPoolingTest_PoolableScript, nullptr).Get_NumFree() >= 1);
    }

    UFUNCTION()
    private void OnDestroySettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto Stats = utils_object::Get_ObjectPoolStats(this, UCk_ObjectPoolingTest_PoolableScript, nullptr);
        Assert_Equals_Int(Stats.Get_NumFree(), 1, "after destroy: EndPlay must park the instance (1 free)");
        Assert_Equals_Int(Stats.Get_NumInUse(), 0, "after destroy: 0 in use");
        if (IsFinished()) { return; }

        auto Pending = utils_entity_script::Request_SpawnEntity(
            DoGet_ScriptEntity(), UCk_ObjectPoolingTest_PoolableScript, FInstancedStruct());
        utils_pending_entity_script::Promise_OnConstructed(
            Pending, FCk_Delegate_EntityScript_Constructed(this, n"OnSecondConstructed"));
    }

    UFUNCTION()
    private void OnSecondConstructed(FCk_Handle_EntityScript InEntity)
    {
        if (IsFinished()) { return; }

        auto Stats = utils_object::Get_ObjectPoolStats(this, UCk_ObjectPoolingTest_PoolableScript, nullptr);
        Assert_Equals_Int(Stats.Get_NumHits(), 1, "spawn #2: must recycle the parked instance (1 hit)");
        Assert_Equals_Int(Stats.Get_NumLiveInstances(), 1,
            "spawn #2: exactly 1 live instance total - the pool reused, not re-created");

        FinishSuccess();
    }
}
