// Language=angelscript

//============================================================================
// CK POOL — AUTOMATION TEST: ACQUIRE/RELEASE ROUND TRIP
//============================================================================
//
// End-to-end EntityPool coverage through the AS-facing surface:
//   1. Bare Request_Acquire auto-creates the default pool for the subject
//      class and (Grow policy) spawns a fresh instance — promise fulfills
//      with Succeeded once construction completes.
//   2. The subject's FCk_Pool_PoolableReceiver hooks fired: NumAcquired==1,
//      and the per-use Marker (MarkerA) was delivered through the receiver.
//   3. Release + immediate re-Acquire (same request queue, FIFO): the SAME
//      instance is recycled — NumAcquired==2 / NumReleased==1 on one entity,
//      UseGeneration bumped to 2, pool stats show 1 hit / 1 live instance.
//
// Evidence rides CkVariables stamped by the subject (immediate set/get; see
// CkPoolTest_Subjects.as) — no test-only framework API needed.
//============================================================================

class UCk_AutoTest_EntityPool_ReceiverRoundTrip : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle _FirstEntity;
    private int32 _Step = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Step = 1;

        FCk_PoolTest_PerUse PerUse;
        PerUse.Marker = n"CkPoolTest.MarkerA";

        auto Pending = utils_entity_pool::Request_Acquire(UCk_PoolTest_PooledReceiverRoundTrip_EntityScript, PerUse);
        Pending.Promise_OnAcquired(FCk_Delegate_EntityPool_Acquired(this, n"OnAcquired"));
    }

    private int32 Get_SubjectCounter(FCk_Handle InEntity, FName InVariableName)
    {
        auto _CkPerfScope = ck::ScopedStat();
        ECk_SucceededFailed Status = ECk_SucceededFailed::Failed;
        auto Value = utils_variables_int32::Get_ByName(InEntity, InVariableName, ECk_Recursion::NotRecursive, Status);
        return Status == ECk_SucceededFailed::Succeeded ? Value : -1;
    }

    private FName Get_SubjectMarker(FCk_Handle InEntity)
    {
        auto _CkPerfScope = ck::ScopedStat();
        ECk_SucceededFailed Status = ECk_SucceededFailed::Failed;
        auto Value = utils_variables_name::Get_ByName(InEntity, n"AutoTest.Pool.LastMarker", ECk_Recursion::NotRecursive, Status);
        return Status == ECk_SucceededFailed::Succeeded ? Value : NAME_None;
    }

    UFUNCTION()
    private void OnAcquired(FCk_EntityPool_AcquireResult InResult)
    {
        auto _CkPerfScope = ck::ScopedStat();
        if (IsFinished()) { return; }

        if (_Step == 1)
        {
            Assert_True(InResult.Get_Result() == ECk_SucceededFailed::Succeeded, "acquire #1 fulfilled with Succeeded");

            _FirstEntity = InResult.Get_AcquiredEntity();
            Assert_True(ck::IsValid(_FirstEntity), "acquired entity is valid");
            Assert_True(UCk_Utils_EntityPool_UE::Get_IsPooledEntity(_FirstEntity), "entity is pool-tracked");
            Assert_Equals_Int(UCk_Utils_EntityPool_UE::Get_UseGeneration(_FirstEntity), 1, "use generation after first acquire");

            Assert_Equals_Int(Get_SubjectCounter(_FirstEntity, n"AutoTest.Pool.NumAcquired"), 1,
                "receiver OnAcquiredFromPool fired on the subject");
            Assert_True(Get_SubjectMarker(_FirstEntity) == n"CkPoolTest.MarkerA",
                "per-use params delivered through the receiver");

            if (IsFinished()) { return; }

            // Release then immediately re-acquire — both requests drain FIFO on the
            // pool, so the released instance must be re-vended (recycled), not respawned
            _Step = 2;
            utils_entity_pool::Request_ReleaseToPool(_FirstEntity);

            FCk_PoolTest_PerUse PerUse;
            PerUse.Marker = n"CkPoolTest.MarkerB";
            auto Pending = utils_entity_pool::Request_Acquire(UCk_PoolTest_PooledReceiverRoundTrip_EntityScript, PerUse);
            Pending.Promise_OnAcquired(FCk_Delegate_EntityPool_Acquired(this, n"OnAcquired"));
            return;
        }

        if (_Step == 2)
        {
            auto RecycledEntity = InResult.Get_AcquiredEntity();

            // same subject instance: its per-instance counters advanced (2 acquires,
            // 1 release) and the pooled entity's generation bumped — a fresh spawn
            // would sit at NumAcquired==1 / generation 1
            Assert_Equals_Int(Get_SubjectCounter(RecycledEntity, n"AutoTest.Pool.NumReleased"), 1,
                "receiver OnReleasedToPool fired on release");
            Assert_Equals_Int(Get_SubjectCounter(RecycledEntity, n"AutoTest.Pool.NumAcquired"), 2,
                "same instance re-acquired (receiver fired twice)");
            Assert_True(Get_SubjectMarker(RecycledEntity) == n"CkPoolTest.MarkerB",
                "per-use params of the second acquire delivered");
            Assert_Equals_Int(UCk_Utils_EntityPool_UE::Get_UseGeneration(RecycledEntity), 2, "use generation after recycle");

            auto Pool = UCk_Utils_EntityPool_UE::TryGet_Pool_ByClass(UCk_PoolTest_PooledReceiverRoundTrip_EntityScript);
            Assert_True(ck::IsValid(Pool), "auto-created default pool is discoverable by class");

            auto Stats = Pool.Get_Stats();
            Assert_Equals_Int(Stats.Get_NumHits(), 1, "second acquire was a pool hit");
            Assert_Equals_Int(Stats.Get_NumLiveInstances(), 1, "recycling kept a single live instance");

            FinishSuccess();
        }
    }
}
