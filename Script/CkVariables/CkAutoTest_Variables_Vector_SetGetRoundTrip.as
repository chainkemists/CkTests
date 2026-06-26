// Language=angelscript
//
// CK VARIABLES — AUTOMATION TEST: Vector Set→Get round-trip

class UCk_AutoTest_Variables_Vector_SetGetRoundTrip : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private const FVector SeedValue = FVector(10.0f, -20.0f, 30.0f);
    private const float32 ToleranceCm = 0.001f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Entity = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto Tag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Variables.Vector");

        utils_variables_vector::Set(Entity, Tag, SeedValue);

        ECk_SucceededFailed Status = ECk_SucceededFailed::Failed;
        auto Value = utils_variables_vector::Get_ByName(Entity, Tag.GetTagName(), ECk_Recursion::NotRecursive, Status);
        Assert_True(Status == ECk_SucceededFailed::Succeeded,
            "Get_ByName on a Set variable should report Succeeded");
        Assert_True(Value.Equals(SeedValue, ToleranceCm),
            f"Vector round-trip should preserve the value; expected {SeedValue}, got {Value}");

        FinishSuccess();
    }
}
