// Language=angelscript
//
// CK UNREAL COMPONENT — AUTOMATION TEST: Get_OwningEntity round-trip
// Get_OwningEntity should return the entity that hosted the Add call.

class UCk_AutoTest_UnrealComponent_GetOwningEntity : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(Owner, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        const auto Params = utils_unreal_component::Make_Params(
            UStaticMeshComponent, ECk_UnrealComponent_TickPolicy::DoNotTick, n"AutoTest");
        auto CompHandle = utils_unreal_component::Add(Owner, Params);

        auto OwningEntity = utils_unreal_component::Get_OwningEntity(CompHandle);
        Assert_True(utils_handle::IsEqual(OwningEntity, Owner),
            "Get_OwningEntity should return the entity that owned the Add call");

        FinishSuccess();
    }
}
