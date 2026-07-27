// Language=angelscript

//============================================================================
// CK ENTITY TAG — AUTOMATION TEST: ADD IS COUNTED
//============================================================================
//
// Adds the same FName tag three times, then removes twice. The tag is still
// present (count went 0->1->2->3, then 3->2->1). A third remove takes it to
// zero and Has reports false.
//
// Pins the counted-Add contract: presence is gated by net count, not by a
// single boolean. This is the core semantics change vs the pre-PR
// idempotent-Add behavior.
//
// The 3->1 hop is a FIXED-FRAME settle on purpose: no count accessor is
// exposed to script (CkEntityTag_Utils.h:103 keeps the {name -> count} map
// off the UFUNCTION surface), and Has is true on both sides of that hop, so
// there is no condition to wait on. The two hops that DO cross a presence
// flip (0->1 and 1->0) are condition waits.
//============================================================================

class UCk_AutoTest_EntityTag_AddIsCounted : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle _Entity;
    private FName _Tag = n"AutoTestEt_Counted";

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Entity = InHandle;

        utils_entity_tag::Add(_Entity, _Tag);
        utils_entity_tag::Add(_Entity, _Tag);
        utils_entity_tag::Add(_Entity, _Tag);

        Add_Step_WaitUntil( "the thrice-added tag becomes present",     n"Check_Present");
        Add_Step(           "remove twice (count 3 -> 1)",              n"Step_RemoveTwice");
        Add_Step_WaitFrames("let both removes drain",                   2);
        Add_Step(           "assert still present, then remove again",  n"Step_AssertPresentAndRemoveThird");
        Add_Step_WaitUntil( "the tag finally becomes absent",           n"Check_Absent");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_RemoveTwice(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto R1 = utils_entity_tag::Request_TryRemove(_Entity, _Tag);
        auto R2 = utils_entity_tag::Request_TryRemove(_Entity, _Tag);
        Assert_True(R1 == ECk_SucceededFailed::Succeeded, "First Remove on counted tag must Succeed");
        Assert_True(R2 == ECk_SucceededFailed::Succeeded, "Second Remove on counted tag must Succeed");
    }

    UFUNCTION()
    private void Step_AssertPresentAndRemoveThird(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_entity_tag::Has(_Entity, _Tag),
            "After 3 Adds and 2 Removes, Has must still be true (count is 1)");

        auto R3 = utils_entity_tag::Request_TryRemove(_Entity, _Tag);
        Assert_True(R3 == ECk_SucceededFailed::Succeeded, "Third Remove must Succeed");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_Present(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_entity_tag::Has(_Entity, _Tag));
    }

    UFUNCTION()
    private void Check_Absent(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_entity_tag::Has(_Entity, _Tag) == false);
    }
}
