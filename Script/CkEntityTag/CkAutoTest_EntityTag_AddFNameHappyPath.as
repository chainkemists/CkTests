// Language=angelscript
//
// CK ENTITY TAG — AUTOMATION TEST: Add(FName) round-trip
// Add an FName tag; Has reports true; TryGet returns the same tag.

class UCk_AutoTest_EntityTag_AddFNameHappyPath : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        utils_entity_tag::Add(LocalHandle, n"AutoTest_Foo");

        Assert_True(utils_entity_tag::Has(LocalHandle, n"AutoTest_Foo"),
            "Has should return true for the just-added FName tag");
        Assert_True(utils_entity_tag::TryGet_Tag(LocalHandle) == n"AutoTest_Foo",
            "TryGet_Tag should return the added FName tag");

        FinishSuccess();
    }
}
