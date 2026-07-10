// Language=angelscript

//============================================================================
// CK POOL — AUTOMATION TEST: PER-USE PARAMS INJECT INTO SCRIPT PROPERTIES
//============================================================================
//
// Pooled "respawn" semantics requested in review: on EVERY acquire, the
// per-use FInstancedStruct is injected into MATCHING script properties
// (the same injector the spawn path uses for spawn params), BEFORE the
// acquire hooks fire — so hooks that read properties see per-use values.
//
// The subject has an FName 'Marker' property matching FCk_PoolTest_PerUse's
// Marker field; its OnAcquiredFromPool hook publishes the PROPERTY value
// (AutoTest.Pool.InjectedMarker), distinct from the payload value:
//   acquire #1 (Marker=X) → property reads X inside the hook
//   release + acquire #2 (Marker=Y) → property re-stomped to Y
//============================================================================

class UCk_AutoTest_EntityPool_PerUseParams_InjectIntoProperties : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private int32 _Step = 0;
    private FCk_Handle _Entity;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Step = 1;

        FCk_PoolTest_PerUse PerUse;
        PerUse.Marker = n"CkPoolTest.InjectFirst";

        auto Pending = utils_entity_pool::Request_Acquire(UCk_PoolTest_InjectSubject_EntityScript, PerUse);
        Pending.Promise_OnAcquired(FCk_Delegate_EntityPool_Acquired(this, n"OnAcquired"));
    }

    private FName Get_InjectedMarker(FCk_Handle InEntity)
    {
        auto _CkPerfScope = ck::ScopedStat();
        ECk_SucceededFailed Status = ECk_SucceededFailed::Failed;
        auto Value = utils_variables_name::Get_ByName(InEntity, n"AutoTest.Pool.InjectedMarker", ECk_Recursion::NotRecursive, Status);
        return Status == ECk_SucceededFailed::Succeeded ? Value : NAME_None;
    }

    UFUNCTION()
    private void OnAcquired(FCk_EntityPool_AcquireResult InResult)
    {
        auto _CkPerfScope = ck::ScopedStat();
        if (IsFinished()) { return; }

        Assert_True(InResult.Get_Result() == ECk_SucceededFailed::Succeeded, "acquire fulfilled with Succeeded");

        if (_Step == 1)
        {
            _Entity = InResult.Get_AcquiredEntity();
            Assert_True(Get_InjectedMarker(_Entity) == n"CkPoolTest.InjectFirst",
                "per-use Marker injected into the script PROPERTY before the hook fired");

            if (IsFinished()) { return; }

            _Step = 2;
            utils_entity_pool::Request_ReleaseToPool(_Entity);

            FCk_PoolTest_PerUse PerUse;
            PerUse.Marker = n"CkPoolTest.InjectSecond";
            auto Pending = utils_entity_pool::Request_Acquire(UCk_PoolTest_InjectSubject_EntityScript, PerUse);
            Pending.Promise_OnAcquired(FCk_Delegate_EntityPool_Acquired(this, n"OnAcquired"));
            return;
        }

        if (_Step == 2)
        {
            Assert_Equals_Int(UCk_Utils_EntityPool_UE::Get_UseGeneration(InResult.Get_AcquiredEntity()), 2,
                "second acquire recycled the same instance");
            Assert_True(Get_InjectedMarker(InResult.Get_AcquiredEntity()) == n"CkPoolTest.InjectSecond",
                "property RE-stomped with the second acquire's per-use value");

            FinishSuccess();
        }
    }
}
