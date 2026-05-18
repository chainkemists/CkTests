// Language=angelscript
//
// CK ENTITY TAG — AUTOMATION TEST: Add(FName) round-trip
// Add an FName tag; Has reports true; Get_AllTags lists it.

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
        Assert_True(utils_entity_tag::Get_AllTags(LocalHandle).Contains(n"AutoTest_Foo"),
            "Get_AllTags should list the added FName tag");

        FinishSuccess();
    }
}
