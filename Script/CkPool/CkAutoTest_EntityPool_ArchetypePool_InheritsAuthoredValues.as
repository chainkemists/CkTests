// Language=angelscript

//============================================================================
// CK POOL — AUTOMATION TEST: ARCHETYPE POOL INHERITS AUTHORED VALUES
//============================================================================
//
// Covers the archetype flavor of EntityPool params plus the one-shot
// Request_Acquire_WithPoolParams:
//   1. Author an EntityScript INSTANCE at runtime (ArchetypeMarker = 42;
//      class CDO default is 0) — the stand-in for an instance authored on
//      disk or configured on a placed spawner.
//   2. Acquire via Request_Acquire_WithPoolParams whose pool params carry
//      the archetype + a pool name (archetype pools must be named).
//   3. The delivered instance must have been constructed FROM the archetype:
//      its receiver hook publishes ArchetypeMarker, which must read 42.
//============================================================================

class UCk_AutoTest_EntityPool_ArchetypePool_InheritsAuthoredValues : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    // rooted via the test instance while the pool takes its own strong pin at creation
    UPROPERTY()
    UCk_PoolTest_PooledReceiver_EntityScript Archetype;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        Archetype = Cast<UCk_PoolTest_PooledReceiver_EntityScript>(
            NewObject(this, UCk_PoolTest_PooledReceiver_EntityScript));
        Assert_True(ck::IsValid(Archetype), "authored archetype instance created");
        if (IsFinished()) { return; }

        Archetype.ArchetypeMarker = 42;

        FCk_Fragment_EntityPool_ParamsData PoolParams;
        PoolParams.Set_EntityScriptArchetype(Archetype);
        PoolParams.Set_PoolName(utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Pool.ArchetypePool"));

        auto Pending = utils_entity_pool::Request_Acquire_WithPoolParams(PoolParams, FInstancedStruct());
        Pending.Promise_OnAcquired(FCk_Delegate_EntityPool_Acquired(this, n"OnAcquired"));
    }

    UFUNCTION()
    private void OnAcquired(FCk_EntityPool_AcquireResult InResult)
    {
        auto _CkPerfScope = ck::ScopedStat();
        if (IsFinished()) { return; }

        Assert_True(InResult.Get_Result() == ECk_SucceededFailed::Succeeded, "archetype-pool acquire fulfilled with Succeeded");

        auto Entity = InResult.Get_AcquiredEntity();
        ECk_SucceededFailed Status = ECk_SucceededFailed::Failed;
        auto Marker = utils_variables_int32::Get_ByName(Entity, n"AutoTest.Pool.ArchetypeMarker", ECk_Recursion::NotRecursive, Status);

        Assert_True(Status == ECk_SucceededFailed::Succeeded, "instance published its ArchetypeMarker");
        Assert_Equals_Int(Marker, 42, "pooled instance constructed FROM the archetype (42), not the class CDO (0)");

        auto Pool = UCk_Utils_EntityPool_UE::TryGet_Pool_ByName(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Pool.ArchetypePool"));
        Assert_True(ck::IsValid(Pool), "named archetype pool is discoverable by name");

        FinishSuccess();
    }
}
