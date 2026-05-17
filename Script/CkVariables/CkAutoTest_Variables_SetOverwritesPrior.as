// Language=angelscript
//
// CK VARIABLES — AUTOMATION TEST: Set overwrites a prior value at the same name
// Confirms the keyed-map semantics: a second Set under the same name replaces,
// not appends.

class UCk_AutoTest_Variables_SetOverwritesPrior : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Entity = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto Tag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Variables.OverwriteSlot");

        utils_variables_int32::Set(Entity, Tag, 10);
        utils_variables_int32::Set(Entity, Tag, 25);

        ECk_SucceededFailed Status;
        auto Value = utils_variables_int32::Get_ByName(Entity, Tag.GetTagName(), ECk_Recursion::NotRecursive, Status);
        Assert_True(Status == ECk_SucceededFailed::Succeeded,
            "Get_ByName should still report Succeeded after re-Set");
        Assert_Equals_Int(Value, 25,
            "The second Set should overwrite the first under the same name");

        FinishSuccess();
    }
}
