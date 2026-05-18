// Language=angelscript

//============================================================================
// CK ENTITY TAG — AUTOMATION TEST: GAMEPLAY TAG PARENT UNCOUNTS CLEANLY
//============================================================================
//
// Adds two sibling gameplay tags (A.B.C and A.B.D). Each shares the parent
// chain A.B / A. Removing A.B.C must NOT remove the parent FNames — they
// are still held by A.B.D. Only after removing A.B.D as well do the parent
// FNames go away.
//
// This pins the counted parent-chain semantics: parents are reference-
// counted across all gameplay tags that contain them.
//============================================================================

class UCk_AutoTest_EntityTag_GameplayTagParentUncountsCleanly : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        auto TagC = utils_gameplay_tag::ResolveGameplayTag(n"AutoTestEt.A.B.C");
        auto TagD = utils_gameplay_tag::ResolveGameplayTag(n"AutoTestEt.A.B.D");

        utils_entity_tag::Add_UsingGameplayTag(LocalHandle, TagC);
        utils_entity_tag::Add_UsingGameplayTag(LocalHandle, TagD);

        Assert_True(utils_entity_tag::Has(LocalHandle, n"AutoTestEt.A.B"),
            "Parent A.B must be present after adding two children");

        // Remove A.B.C — parent A.B must still be present (held by A.B.D).
        auto R1 = utils_entity_tag::Request_TryRemove_UsingGameplayTag(LocalHandle, TagC);
        Assert_True(R1 == ECk_SucceededFailed::Succeeded,
            "Remove of present gameplay tag must Succeed");
        Assert_True(!utils_entity_tag::Has(LocalHandle, n"AutoTestEt.A.B.C"),
            "Leaf A.B.C must be absent after its single Remove");
        Assert_True(utils_entity_tag::Has(LocalHandle, n"AutoTestEt.A.B"),
            "Parent A.B must STILL be present after removing only A.B.C (A.B.D still holds it)");

        // Remove A.B.D — now parents finally drop.
        auto R2 = utils_entity_tag::Request_TryRemove_UsingGameplayTag(LocalHandle, TagD);
        Assert_True(R2 == ECk_SucceededFailed::Succeeded,
            "Second Remove must Succeed");
        Assert_True(!utils_entity_tag::Has(LocalHandle, n"AutoTestEt.A.B"),
            "Parent A.B must now be absent (no children left holding it)");
        Assert_True(!utils_entity_tag::Has(LocalHandle, n"AutoTestEt.A"),
            "Grandparent A must now be absent");

        FinishSuccess();
    }
}
