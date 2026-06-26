// Language=angelscript
//
// CK ENTITY TAG — AUTOMATION TEST: Add(FName) round-trip
// Add an FName tag; Has reports true; Get_AllTags lists it.

class UCk_AutoTest_EntityTag_AddFNameHappyPath : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle _Entity;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Entity = InHandle;
        utils_entity_tag::Add(_Entity, n"AutoTest_Foo");

        WaitOneFrame(n"AfterAdd");
    }

    UFUNCTION()
    private void AfterAdd(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(utils_entity_tag::Has(_Entity, n"AutoTest_Foo"),
            "Has should return true for the just-added FName tag");
        Assert_True(utils_entity_tag::Get_AllTags(_Entity).Contains(n"AutoTest_Foo"),
            "Get_AllTags should list the added FName tag");

        FinishSuccess();
    }
}
