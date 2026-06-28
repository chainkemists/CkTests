// Language=angelscript

//============================================================================
// CK ENTITY TAG QUERY — AUTOMATION TEST: ON CONTINUOUS UPDATE FIRES ONLY ON CHANGE
//============================================================================
//
// NOTE ON NAME: the class/file retains its historical "FiresEveryPass" name so
// renaming it does not churn the generated autotest wrapper + the placed actor in
// AutoTests_CkTests_Level. Its CONTRACT changed: OnContinuousUpdate is now
// change-gated — it broadcasts ONLY on a pump pass whose result set actually
// changed (an entity entered or left a requirement), and stays SILENT on
// no-change passes. (Broadcasting every pass cost a per-frame payload alloc +
// broadcast + delegate call per bound query even when nothing changed; every
// consumer reacts to the _Added / _Removed deltas, so a no-change pass has nothing
// to deliver.)
//
// Strategy: bind OnContinuousUpdate to a query whose requirement nothing satisfies
// yet, prove it stays silent across idle passes, then add a matching entity and
// prove exactly that change fires it — and that it goes silent again afterwards.
//============================================================================

class UCk_AutoTest_EntityTagQuery_ContinuousUpdateFiresEveryPass : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_EntityTagQuery _Query;
    private FCk_Handle                _E1;
    private int32                     _FireCount         = 0;
    private int32                     _FireCountIdle     = 0;
    private int32                     _FireCountAfterAdd = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Owner = InHandle;

        _Query = utils_entity_tag_query::Add(_Owner);

        utils_entity_tag_query::BindTo_OnContinuousUpdate(_Query,
            ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing,
            FCk_Delegate_EntityTagQuery_OnContinuousUpdate(this, n"OnContinuous"));

        auto Req = utils_entity_tag_query::Make_Requirement_Single(n"AutoTestEtq_Cont");
        utils_entity_tag_query::Request_AddRequirement(_Query,
            FCk_Request_EntityTagQuery_AddRequirement(Req));

        // One frame for HandleRequests to install the requirement so the query is
        // actively evaluating before we assert on its (non-)firing.
        WaitOneFrame(n"AfterAddRequirement");
    }

    UFUNCTION()
    private void AfterAddRequirement(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // No matching entity exists, so the evaluate produced no delta and must not fire.
        Assert_Equals_Int(_FireCount, 0,
            "OnContinuousUpdate must NOT fire while the result set is empty/unchanged");

        _FireCountIdle = _FireCount;
        WaitOneFrame(n"AfterIdle");
    }

    UFUNCTION()
    private void AfterIdle(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // A further idle pass (query active, still no change) must remain silent.
        Assert_Equals_Int(_FireCount, _FireCountIdle,
            "An idle pass with no result-set change must NOT fire OnContinuousUpdate");

        // Now introduce a real change: tag a matching entity.
        _E1 = utils_entity_lifetime::Request_CreateEntity(_Owner);
        utils_entity_tag::Add(_E1, n"AutoTestEtq_Cont");
        WaitOneFrame(n"AfterAdd");
    }

    UFUNCTION()
    private void AfterAdd(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // The entity entering the result set is a change — it must fire.
        Assert_True(_FireCount > _FireCountIdle,
            "A result-set change (entity added) must fire OnContinuousUpdate");

        _FireCountAfterAdd = _FireCount;
        WaitOneFrame(n"AfterSettle");
    }

    UFUNCTION()
    private void AfterSettle(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // Once the change has settled, subsequent no-change passes must be silent again.
        Assert_Equals_Int(_FireCount, _FireCountAfterAdd,
            "After the change settles, an idle pass must NOT re-fire OnContinuousUpdate");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnContinuous(
        FCk_Handle_EntityTagQuery InQuery,
        bool InIsSatisfied,
        const TArray<FCk_EntityTagQuery_Result>&in InResults)
    {
        _FireCount += 1;
    }
}
