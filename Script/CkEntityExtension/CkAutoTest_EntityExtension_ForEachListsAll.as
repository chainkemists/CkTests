// Language=angelscript
//
// CK ENTITY EXTENSION — AUTOMATION TEST: ForEach lists all attached extensions
// Attach three extensions to an owner; ForEach_EntityExtension with an unbound
// delegate returns a 3-element array containing all of them.

class UCk_AutoTest_EntityExtension_ForEachListsAll : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto C1 = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto C2 = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto C3 = utils_entity_lifetime::Request_CreateEntity(InHandle);

        utils_entity_extension::Add(Owner, C1);
        utils_entity_extension::Add(Owner, C2);
        utils_entity_extension::Add(Owner, C3);

        auto Extensions = utils_entity_extension::ForEach_EntityExtension(
            Owner, FInstancedStruct(), FCk_Lambda_InHandle());

        Assert_Equals_Int(Extensions.Num(), 3,
            "ForEach_EntityExtension should return one entry per Add call");

        FinishSuccess();
    }
}
