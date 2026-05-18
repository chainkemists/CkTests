// Language=angelscript

//============================================================================
// CK ENTITY TAG — AUTOMATION TEST: REMOVE GAMEPLAY TAG REJECTS PARTIAL
//============================================================================
//
// Adding A.B.C registers A.B.C explicitly and A.B / A as parent FNames.
// Calling Request_TryRemove_UsingGameplayTag(A.B) must fail — A.B is not an
// explicitly-added gameplay tag, just a parent of A.B.C. Removing it would
// break the parent count for the genuinely-added A.B.C.
//
// This is the HasTagExact-style boundary guard.
//============================================================================

class UCk_AutoTest_EntityTag_RemoveGameplayTagRejectsPartial : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        auto LeafTag   = utils_gameplay_tag::ResolveGameplayTag(n"AutoTestEt.A.B.C");
        auto ParentTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTestEt.A.B");

        utils_entity_tag::Add_UsingGameplayTag(LocalHandle, LeafTag);

        auto Result = utils_entity_tag::Request_TryRemove_UsingGameplayTag(LocalHandle, ParentTag);
        Assert_True(Result == ECk_SucceededFailed::Failed,
            "Removing a parent gameplay tag that was never explicitly added must Fail");

        // Leaf must still be intact.
        Assert_True(utils_entity_tag::Has(LocalHandle, n"AutoTestEt.A.B.C"),
            "Leaf A.B.C must still be present after the rejected parent remove");
        Assert_True(utils_entity_tag::Has(LocalHandle, n"AutoTestEt.A.B"),
            "Parent FName A.B must still be present after the rejected parent remove");

        FinishSuccess();
    }
}
