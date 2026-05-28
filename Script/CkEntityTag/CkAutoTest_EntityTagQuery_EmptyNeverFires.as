// Language=angelscript

//============================================================================
// CK ENTITY TAG QUERY — AUTOMATION TEST: EMPTY QUERY NEVER FIRES
//============================================================================
//
// Add a query, bind OnSatisfied, but never add any requirements. After
// several settle frames, OnSatisfied must NOT have fired. An empty
// requirement list is not vacuously satisfied — the query stays idle.
//============================================================================

class UCk_AutoTest_EntityTagQuery_EmptyNeverFires : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_EntityTagQuery _Query;
    private int32                     _FireCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner = InHandle;

        _Query = utils_entity_tag_query::Add(_Owner);

        utils_entity_tag_query::BindTo_OnSatisfied(_Query,
            ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing,
            FCk_Delegate_EntityTagQuery_OnSatisfied(this, n"OnSatisfied"));

        // No requirements added — query sits idle.
        WaitOneFrame(n"Settle1");
    }

    UFUNCTION()
    private void Settle1(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        WaitOneFrame(n"Settle2");
    }

    UFUNCTION()
    private void Settle2(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        WaitOneFrame(n"Settle3");
    }

    UFUNCTION()
    private void Settle3(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_FireCount, 0,
            "Query with no requirements must never fire OnSatisfied");
        Assert_True(utils_entity_tag_query::Get_IsSatisfied(_Query) == false,
            "Empty query must report Get_IsSatisfied == false (not vacuously satisfied)");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnSatisfied(FCk_Handle_EntityTagQuery InQuery, const TArray<FCk_EntityTagQuery_Result>&in InResults)
    {
        _FireCount += 1;
    }
}
