// Language=angelscript

//============================================================================
// CK ENTITY TAG QUERY — AUTOMATION TEST: ON CONTINUOUS UPDATE FIRES EVERY PASS
//============================================================================
//
// Verifies improvement I2 — when a delegate is bound to OnContinuousUpdate,
// the query broadcasts that signal on every pump pass, regardless of
// satisfaction state. The counter must strictly increase frame over frame.
//
// Strategy: add a query with one requirement that nothing in the world satisfies
// (so IsSatisfied stays false the whole time), bind OnContinuousUpdate, then
// observe _FireCount across three successive frames.
//============================================================================

class UCk_AutoTest_EntityTagQuery_ContinuousUpdateFiresEveryPass : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_EntityTagQuery _Query;
    private int32                     _FireCount = 0;
    private int32                     _PassCountAfterFirstFrame  = 0;
    private int32                     _PassCountAfterSecondFrame = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner = InHandle;

        _Query = utils_entity_tag_query::Add(_Owner);

        utils_entity_tag_query::BindTo_OnContinuousUpdate(_Query,
            ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing,
            FCk_Delegate_EntityTagQuery_OnContinuousUpdate(this, n"OnContinuous"));

        auto Req = utils_entity_tag_query::Make_Requirement_Single(n"AutoTestEtq_Cont");
        utils_entity_tag_query::Request_AddRequirement(_Query,
            FCk_Request_EntityTagQuery_AddRequirement(Req));

        WaitOneFrame(n"AfterAddRequirement");
    }

    UFUNCTION()
    private void AfterAddRequirement(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _PassCountAfterFirstFrame = _FireCount;
        WaitOneFrame(n"AfterFrame2");
    }

    UFUNCTION()
    private void AfterFrame2(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _PassCountAfterSecondFrame = _FireCount;
        Assert_True(_PassCountAfterSecondFrame > _PassCountAfterFirstFrame,
            "OnContinuousUpdate must have fired at least once more during the second pump pass");

        WaitOneFrame(n"AfterFrame3");
    }

    UFUNCTION()
    private void AfterFrame3(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(_FireCount > _PassCountAfterSecondFrame,
            "OnContinuousUpdate must keep firing every pass — third frame must increment the counter again");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnContinuous(
        FCk_Handle_EntityTagQuery InQuery,
        bool InIsSatisfied,
        const TArray<FCk_EntityTagQuery_Result>& InResults)
    {
        // No matching entity exists, so the query must report unsatisfied
        // on every continuous-update broadcast.
        Assert_True(InIsSatisfied == false,
            "OnContinuousUpdate must surface the current IsSatisfied state — no matches exist, so it must be false");

        _FireCount += 1;
    }
}
