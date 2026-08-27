// Language=angelscript

//============================================================================
// CK ENTITY TAG - AUTOMATION TEST: GAMEPLAY TAG PARENT UNCOUNTS CLEANLY
//============================================================================
//
// Adds two sibling gameplay tags (A.B.C and A.B.D). Each shares the parent
// chain A.B / A. Removing A.B.C must NOT remove the parent FNames - they
// are still held by A.B.D. Only after removing A.B.D as well do the parent
// FNames go away.
//
// This pins the counted parent-chain semantics: parents are reference-
// counted across all gameplay tags that contain them.
//
// Each wait targets the LEAF or PARENT presence flip that phase actually
// crosses; "the parent survives the first remove" stays an assertion,
// because a wait on it would be true on entry and prove nothing.
//============================================================================

class UCk_AutoTest_EntityTag_GameplayTagParentUncountsCleanly : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle _Entity;
    private FGameplayTag _TagC;
    private FGameplayTag _TagD;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Entity = InHandle;
        _TagC = utils_gameplay_tag::ResolveGameplayTag(n"AutoTestEt.A.B.C");
        _TagD = utils_gameplay_tag::ResolveGameplayTag(n"AutoTestEt.A.B.D");

        utils_entity_tag::Add_UsingGameplayTag(_Entity, _TagC);
        utils_entity_tag::Add_UsingGameplayTag(_Entity, _TagD);

        Add_Step_WaitUntil("parent A.B becomes present via its children", n"Check_ParentPresent");
        Add_Step(          "remove child A.B.C",                          n"Step_RemoveC");
        Add_Step_WaitUntil("leaf A.B.C becomes absent",                   n"Check_LeafCAbsent");
        Add_Step(          "assert A.B survives, then remove A.B.D",      n"Step_AssertParentHeldAndRemoveD");
        Add_Step_WaitUntil("parent A.B becomes absent",                   n"Check_ParentAbsent");
        Add_Step(          "assert the grandparent uncounted too",        n"Step_AssertGrandparent");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_RemoveC(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto R1 = utils_entity_tag::Request_TryRemove_UsingGameplayTag(_Entity, _TagC);
        Assert_True(R1 == ECk_SucceededFailed::Succeeded,
            "Remove of present gameplay tag must Succeed");
    }

    UFUNCTION()
    private void Step_AssertParentHeldAndRemoveD(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_entity_tag::Has(_Entity, n"AutoTestEt.A.B"),
            "Parent A.B must STILL be present after removing only A.B.C (A.B.D still holds it)");

        auto R2 = utils_entity_tag::Request_TryRemove_UsingGameplayTag(_Entity, _TagD);
        Assert_True(R2 == ECk_SucceededFailed::Succeeded,
            "Second Remove must Succeed");
    }

    UFUNCTION()
    private void Step_AssertGrandparent(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(!utils_entity_tag::Has(_Entity, n"AutoTestEt.A"),
            "Grandparent A must now be absent");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_ParentPresent(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_entity_tag::Has(_Entity, n"AutoTestEt.A.B"));
    }

    UFUNCTION()
    private void Check_LeafCAbsent(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_entity_tag::Has(_Entity, n"AutoTestEt.A.B.C") == false);
    }

    UFUNCTION()
    private void Check_ParentAbsent(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_entity_tag::Has(_Entity, n"AutoTestEt.A.B") == false);
    }
}
