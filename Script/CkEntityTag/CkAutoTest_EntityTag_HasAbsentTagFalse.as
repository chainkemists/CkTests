// Language=angelscript
//
// CK ENTITY TAG — AUTOMATION TEST: Has(absent) → false
// Add one tag; Has on a different tag returns false (does not blanket-match).

class UCk_AutoTest_EntityTag_HasAbsentTagFalse : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle _Entity;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Entity = InHandle;
        utils_entity_tag::Add(_Entity, n"Foo");

        WaitUntil(n"Check_TagAdded", n"AfterAdd");
    }

    UFUNCTION()
    private void Check_TagAdded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_entity_tag::Has(_Entity, n"Foo"));
    }

    UFUNCTION()
    private void AfterAdd(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        Assert_True(utils_entity_tag::Has(_Entity, n"Foo"),
            "Has should return true for the added tag");
        Assert_True(!utils_entity_tag::Has(_Entity, n"Bar"),
            "Has should return false for a tag that was never added");

        FinishSuccess();
    }
}
