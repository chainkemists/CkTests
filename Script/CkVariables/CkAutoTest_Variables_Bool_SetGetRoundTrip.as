// Language=angelscript
//
// CK VARIABLES — AUTOMATION TEST: Bool Set→Get round-trip
// Set a bool variable via tag; Get_ByName retrieves the same value and
// reports Succeeded.

class UCk_AutoTest_Variables_Bool_SetGetRoundTrip : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Entity = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto Tag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Variables.Bool");

        utils_variables_bool::Set(Entity, Tag, true);

        ECk_SucceededFailed Status = ECk_SucceededFailed::Failed;
        auto Value = utils_variables_bool::Get_ByName(Entity, Tag.GetTagName(), ECk_Recursion::NotRecursive, Status);
        Assert_True(Status == ECk_SucceededFailed::Succeeded,
            "Get_ByName on a Set variable should report Succeeded");
        Assert_True(Value == true,
            "Bool round-trip should yield the original value");

        FinishSuccess();
    }
}
