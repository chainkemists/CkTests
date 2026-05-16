// Language=angelscript
//
// CK ENTITY TAG — AUTOMATION TEST: Has(absent) → false
// Add one tag; Has on a different tag returns false (does not blanket-match).

class UCk_AutoTest_EntityTag_HasAbsentTagFalse : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        utils_entity_tag::Add(LocalHandle, n"Foo");

        Assert_True(utils_entity_tag::Has(LocalHandle, n"Foo"),
            "Has should return true for the added tag");
        Assert_True(!utils_entity_tag::Has(LocalHandle, n"Bar"),
            "Has should return false for a tag that was never added");

        FinishSuccess();
    }
}
