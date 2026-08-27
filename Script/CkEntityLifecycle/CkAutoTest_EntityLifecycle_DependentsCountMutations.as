// Language=angelscript

//============================================================================
// CK ENTITY LIFECYCLE - AUTOMATION TEST: DEPENDENTS COUNT TREE MUTATIONS
//============================================================================
//
// Verifies that Get_LifetimeDependents reflects mutations of the ownership
// tree:
//
//   1. Capture baseline dependents count (test entity may already have
//      framework-spawned children).
//   2. Add 3 owned children -> count grows by exactly 3.
//   3. Destroy one child -> tick-poll until count drops by 1.
//
// Existing OwnershipTree test only asserts `count >= 2` after creating two
// children; this test pins the *delta* between mutations to catch silent
// double-counting or stale-entry regressions.
//============================================================================

class UCk_AutoTest_EntityLifecycle_DependentsCountMutations : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private FCk_Handle _MyEntity;
    private FCk_Handle _ChildA;
    private FCk_Handle _ChildB;
    private FCk_Handle _ChildC;
    private int32 _BaselineCount = 0;
    private int32 _CountAfterAdd = 0;
    private bool _DestroyObserved = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _MyEntity = InHandle;

        _BaselineCount = utils_entity_lifetime::Get_LifetimeDependents(_MyEntity).Num();

        _ChildA = utils_entity_lifetime::Request_CreateEntity(_MyEntity);
        _ChildB = utils_entity_lifetime::Request_CreateEntity(_MyEntity);
        _ChildC = utils_entity_lifetime::Request_CreateEntity(_MyEntity);

        _CountAfterAdd = utils_entity_lifetime::Get_LifetimeDependents(_MyEntity).Num();
        Assert_Equals_Int(_CountAfterAdd, _BaselineCount + 3,
            f"After creating 3 owned children, dependents count should be baseline+3 (baseline={_BaselineCount}, after={_CountAfterAdd})");

        utils_entity_lifetime::Request_DestroyEntity(_ChildB);
        utils_timer::Create_Tick(_MyEntity, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        if (_DestroyObserved) { return; }

        auto Count = utils_entity_lifetime::Get_LifetimeDependents(_MyEntity).Num();
        if (Count == _CountAfterAdd - 1)
        {
            _DestroyObserved = true;
            Assert_Equals_Int(Count, _BaselineCount + 2,
                f"After destroying ChildB, dependents count should be baseline+2 (got {Count})");
            FinishSuccess();
        }
    }
}
