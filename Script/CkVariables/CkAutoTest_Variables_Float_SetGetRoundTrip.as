// Language=angelscript
//
// CK VARIABLES — AUTOMATION TEST: Float Set→Get round-trip

class UCk_AutoTest_Variables_Float_SetGetRoundTrip : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Entity = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto Tag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Variables.Float");

        utils_variables_float::Set(Entity, Tag, 3.5f);

        ECk_SucceededFailed Status;
        auto Value = utils_variables_float::Get_ByName(Entity, Tag.GetTagName(), ECk_Recursion::NotRecursive, Status);
        Assert_True(Status == ECk_SucceededFailed::Succeeded,
            "Get_ByName on a Set variable should report Succeeded");
        Assert_True(Math::Abs(Value - 3.5f) < 0.001f,
            f"Float round-trip should preserve the value; got {Value}");

        FinishSuccess();
    }
}
