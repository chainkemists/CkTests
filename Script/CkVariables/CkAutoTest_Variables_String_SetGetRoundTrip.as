// Language=angelscript
//
// CK VARIABLES — AUTOMATION TEST: String Set→Get round-trip

class UCk_AutoTest_Variables_String_SetGetRoundTrip : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Entity = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto Tag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Variables.String");

        utils_variables_string::Set(Entity, Tag, "hello world");

        ECk_SucceededFailed Status;
        auto Value = utils_variables_string::Get_ByName(Entity, Tag.GetTagName(), ECk_Recursion::NotRecursive, Status);
        Assert_True(Status == ECk_SucceededFailed::Succeeded,
            "Get_ByName on a Set variable should report Succeeded");
        Assert_Equals_String(Value, "hello world",
            "String round-trip should preserve the value");

        FinishSuccess();
    }
}
