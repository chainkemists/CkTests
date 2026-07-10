// Language=angelscript

//============================================================================
// CK POOL — AUTOMATION TEST: RELEASE-TIME VETO DESTROYS THE INSTANCE
//============================================================================
//
// Covers FCk_Pool_PoolableReceiver's _CanBePooled veto on the EntityPool:
//   1. Acquire with VetoNextRelease=true — the subject flips _CanBePooled
//      to false inside its OnAcquiredFromPool hook.
//   2. Release → the pool must DESTROY the instance instead of parking it
//      dormant (steal-path counter reconciliation).
//   3. A second acquire therefore spawns a FRESH instance: NumAcquired==1,
//      generation 1, and crucially NO NumReleased variable (a broken veto
//      would park + recycle the vetoed instance, which carries NumReleased==1
//      and NumAcquired==2).
//   4. Both acquires were pool misses (nothing dormant was ever vendable).
//
// The vetoed entity's destruction itself is deferred through the multi-phase
// pipeline, so this test discriminates parked-vs-destroyed via the fresh
// instance's state rather than asserting on destroy timing.
//============================================================================

class UCk_AutoTest_EntityPool_ReceiverVetoDestroys : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle _VetoedEntity;
    private int32 _Step = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Step = 1;

        FCk_PoolTest_PerUse PerUse;
        PerUse.Marker = n"CkPoolTest.VetoMarker";
        PerUse.VetoNextRelease = true;

        auto Pending = utils_entity_pool::Request_Acquire(UCk_PoolTest_PooledReceiverVeto_EntityScript, PerUse);
        Pending.Promise_OnAcquired(FCk_Delegate_EntityPool_Acquired(this, n"OnAcquired"));
    }

    private int32 Get_SubjectCounter(FCk_Handle InEntity, FName InVariableName)
    {
        auto _CkPerfScope = ck::ScopedStat();
        ECk_SucceededFailed Status = ECk_SucceededFailed::Failed;
        auto Value = utils_variables_int32::Get_ByName(InEntity, InVariableName, ECk_Recursion::NotRecursive, Status);
        return Status == ECk_SucceededFailed::Succeeded ? Value : -1;
    }

    UFUNCTION()
    private void OnAcquired(FCk_EntityPool_AcquireResult InResult)
    {
        auto _CkPerfScope = ck::ScopedStat();
        if (IsFinished()) { return; }

        if (_Step == 1)
        {
            Assert_True(InResult.Get_Result() == ECk_SucceededFailed::Succeeded, "acquire #1 fulfilled with Succeeded");

            _VetoedEntity = InResult.Get_AcquiredEntity();
            Assert_Equals_Int(Get_SubjectCounter(_VetoedEntity, n"AutoTest.Pool.NumAcquired"), 1,
                "receiver OnAcquiredFromPool fired (veto armed)");

            if (IsFinished()) { return; }

            // Release (vetoed → destroy) then re-acquire — must be a fresh spawn
            _Step = 2;
            utils_entity_pool::Request_ReleaseToPool(_VetoedEntity);

            FCk_PoolTest_PerUse PerUse;
            PerUse.Marker = n"CkPoolTest.FreshMarker";
            auto Pending = utils_entity_pool::Request_Acquire(UCk_PoolTest_PooledReceiverVeto_EntityScript, PerUse);
            Pending.Promise_OnAcquired(FCk_Delegate_EntityPool_Acquired(this, n"OnAcquired"));
            return;
        }

        if (_Step == 2)
        {
            auto FreshEntity = InResult.Get_AcquiredEntity();

            // a recycled (= wrongly parked) instance would carry NumReleased==1 and
            // NumAcquired==2; a fresh spawn has no release history and one acquire
            Assert_Equals_Int(Get_SubjectCounter(FreshEntity, n"AutoTest.Pool.NumReleased"), -1,
                "vetoed instance was NOT parked/recycled (fresh instance has no release history)");
            Assert_Equals_Int(Get_SubjectCounter(FreshEntity, n"AutoTest.Pool.NumAcquired"), 1,
                "second acquire delivered a fresh instance");
            Assert_Equals_Int(UCk_Utils_EntityPool_UE::Get_UseGeneration(FreshEntity), 1, "fresh instance is generation 1");

            auto Pool = UCk_Utils_EntityPool_UE::TryGet_Pool_ByClass(UCk_PoolTest_PooledReceiverVeto_EntityScript);
            auto Stats = Pool.Get_Stats();
            Assert_Equals_Int(Stats.Get_NumMisses(), 2, "both acquires missed (nothing dormant to vend)");

            FinishSuccess();
        }
    }
}
