// Language=angelscript
//
// CK VARIABLES - AUTOMATION TEST: Int32 Set->Get round-trip

class UCk_AutoTest_Variables_Int32_SetGetRoundTrip : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Entity = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto Tag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Variables.Int32");

        utils_variables_int32::Set(Entity, Tag, 42);

        ECk_SucceededFailed Status = ECk_SucceededFailed::Failed;
        auto Value = utils_variables_int32::Get_ByName(Entity, Tag.GetTagName(), ECk_Recursion::NotRecursive, Status);
        Assert_True(Status == ECk_SucceededFailed::Succeeded,
            "Get_ByName on a Set variable should report Succeeded");
        Assert_Equals_Int(Value, 42, "Int32 round-trip should preserve the value");

        FinishSuccess();
    }
}
