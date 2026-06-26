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
//============================================================================

class UCk_AutoTest_EntityTag_AddIsCounted : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle _Entity;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Entity = InHandle;
        const FName Tag = n"AutoTestEt_Counted";

        utils_entity_tag::Add(_Entity, Tag);
        utils_entity_tag::Add(_Entity, Tag);
        utils_entity_tag::Add(_Entity, Tag);

        WaitOneFrame(n"AfterAdds");
    }

    UFUNCTION()
    private void AfterAdds(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        const FName Tag = n"AutoTestEt_Counted";

        // Two removes — still present (count 3 -> 2 -> 1).
        auto R1 = utils_entity_tag::Request_TryRemove(_Entity, Tag);
        auto R2 = utils_entity_tag::Request_TryRemove(_Entity, Tag);
        Assert_True(R1 == ECk_SucceededFailed::Succeeded, "First Remove on counted tag must Succeed");
        Assert_True(R2 == ECk_SucceededFailed::Succeeded, "Second Remove on counted tag must Succeed");

        WaitOneFrame(n"AfterTwoRemoves");
    }

    UFUNCTION()
    private void AfterTwoRemoves(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        const FName Tag = n"AutoTestEt_Counted";

        Assert_True(utils_entity_tag::Has(_Entity, Tag),
            "After 3 Adds and 2 Removes, Has must still be true (count is 1)");

        // Third remove takes count to zero.
        auto R3 = utils_entity_tag::Request_TryRemove(_Entity, Tag);
        Assert_True(R3 == ECk_SucceededFailed::Succeeded, "Third Remove must Succeed");

        WaitOneFrame(n"AfterThirdRemove");
    }

    UFUNCTION()
    private void AfterThirdRemove(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        const FName Tag = n"AutoTestEt_Counted";

        Assert_True(!utils_entity_tag::Has(_Entity, Tag),
            "After 3 Adds and 3 Removes, Has must be false (count is 0)");

        FinishSuccess();
    }
}
