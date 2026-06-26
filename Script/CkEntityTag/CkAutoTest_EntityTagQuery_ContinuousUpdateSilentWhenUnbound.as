// Language=angelscript

//============================================================================
// CK ENTITY TAG QUERY — AUTOMATION TEST: CONTINUOUS UPDATE SILENT WHEN UNBOUND
//============================================================================
//
// Verifies improvement I2's pay-for-what-you-use guarantee: when no delegate
// is bound to OnContinuousUpdate, the signal must not fire at all (the
// refcount gate inside the broadcaster short-circuits the work). Run a query
// for several pump passes without binding anything and confirm _FireCount
// stays at zero.
//
// The OnContinuous callback is declared so the signature is reachable, but
// it is never registered via BindTo_OnContinuousUpdate.
//============================================================================

class UCk_AutoTest_EntityTagQuery_ContinuousUpdateSilentWhenUnbound : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_EntityTagQuery _Query;
    private int32                     _FireCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Owner = InHandle;

        _Query = utils_entity_tag_query::Add(_Owner);

        // Intentionally NOT binding OnContinuousUpdate (and also not OnSatisfied —
        // we want the entire query running silently to prove the refcount gate
        // holds when no listener is attached).
        auto Req = utils_entity_tag_query::Make_Requirement_Single(n"AutoTestEtq_Silent");
        utils_entity_tag_query::Request_AddRequirement(_Query,
            FCk_Request_EntityTagQuery_AddRequirement(Req));

        WaitOneFrame(n"AfterFrame1");
    }

    UFUNCTION()
    private void AfterFrame1(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        WaitOneFrame(n"AfterFrame2");
    }

    UFUNCTION()
    private void AfterFrame2(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        WaitOneFrame(n"AfterFrame3");
    }

    UFUNCTION()
    private void AfterFrame3(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_FireCount, 0,
            "OnContinuousUpdate must not fire when no delegate is bound — refcount gate must hold");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnContinuous(
        FCk_Handle_EntityTagQuery InQuery,
        bool InIsSatisfied,
        const TArray<FCk_EntityTagQuery_Result>& InResults)
    {
        // Declared but never bound — if this is ever invoked, the refcount
        // gate failed and the test will fail in the AfterFrame3 assertion.
        _FireCount += 1;
    }
}
