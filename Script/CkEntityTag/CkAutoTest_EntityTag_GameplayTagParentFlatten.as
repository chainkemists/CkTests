// Language=angelscript

//============================================================================
// CK ENTITY TAG — AUTOMATION TEST: GAMEPLAY TAG PARENT FLATTEN
//============================================================================
//
// Adding gameplay tag AutoTestEt.A.B.C must register every ancestor in the
// FName tag set, so that Has(parent FName) and ForEach_Entity(parent FName)
// can find this entity by any ancestor.
//
// Tags declared in CkAutoTest_EntityTag_SharedTags.as.
//============================================================================

class UCk_AutoTest_EntityTag_GameplayTagParentFlatten : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle _Entity;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Entity = InHandle;
        auto LeafTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTestEt.A.B.C");

        utils_entity_tag::Add_UsingGameplayTag(_Entity, LeafTag);

        WaitOneFrame(n"AfterAdd");
    }

    UFUNCTION()
    private void AfterAdd(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(utils_entity_tag::Has(_Entity, n"AutoTestEt.A.B.C"),
            "Has(leaf FName) must be true after Add_UsingGameplayTag(leaf)");
        Assert_True(utils_entity_tag::Has(_Entity, n"AutoTestEt.A.B"),
            "Has(parent FName) must be true after Add_UsingGameplayTag(leaf)");
        Assert_True(utils_entity_tag::Has(_Entity, n"AutoTestEt.A"),
            "Has(grandparent FName) must be true after Add_UsingGameplayTag(leaf)");
        Assert_True(utils_entity_tag::Has(_Entity, n"AutoTestEt"),
            "Has(root FName) must be true after Add_UsingGameplayTag(leaf)");

        FinishSuccess();
    }
}
