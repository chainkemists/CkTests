// Language=angelscript
//
// CK VARIABLES — AUTOMATION TEST: GameplayTag Set→Get round-trip

class UCk_AutoTest_Variables_GameplayTag_SetGetRoundTrip : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Entity = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto SlotTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Variables.GameplayTagSlot");
        auto Stored = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Variables.GameplayTagPayload");

        utils_variables_gameplay_tag::Set(Entity, SlotTag, Stored);

        ECk_SucceededFailed Status;
        auto Value = utils_variables_gameplay_tag::Get_ByName(Entity, SlotTag.GetTagName(), ECk_Recursion::NotRecursive, Status);
        Assert_True(Status == ECk_SucceededFailed::Succeeded,
            "Get_ByName on a Set variable should report Succeeded");
        Assert_True(Value == Stored,
            "GameplayTag round-trip should preserve the value");

        FinishSuccess();
    }
}
