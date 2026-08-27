// Language=angelscript
//
// CK ENTITY EXTENSION - AUTOMATION TEST: Add happy path
// Add a child entity as an extension to the owner; the returned handle is
// valid and Get_ExtensionOwner reports the owner.

class UCk_AutoTest_EntityExtension_AddHappyPath : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto Child = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto Extension = utils_entity_extension::Add(Owner, Child);

        Assert_True(utils_handle::Get_IsValid(Extension),
            "Add should return a valid extension handle");

        auto FoundOwner = utils_entity_extension::Get_ExtensionOwner(Extension);
        Assert_True(utils_handle::IsEqual(FoundOwner, Owner),
            "Get_ExtensionOwner should return the original owner entity");

        FinishSuccess();
    }
}
