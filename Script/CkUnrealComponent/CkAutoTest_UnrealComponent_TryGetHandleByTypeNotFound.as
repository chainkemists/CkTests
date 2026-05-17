// Language=angelscript
//
// CK UNREAL COMPONENT — AUTOMATION TEST: TryGet_HandleByType returns invalid for missing type
// Adding a UStaticMeshComponent does not satisfy a TryGet for UPointLightComponent.

class UCk_AutoTest_UnrealComponent_TryGetHandleByTypeNotFound : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(Owner, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        const auto Params = utils_unreal_component::Make_Params(
            UStaticMeshComponent, ECk_UnrealComponent_TickPolicy::DoNotTick, n"AutoTest");
        utils_unreal_component::Add(Owner, Params);

        auto Missing = utils_unreal_component::TryGet_HandleByType(Owner, UPointLightComponent);
        Assert_True(!utils_handle::Get_IsValid(Missing),
            "TryGet_HandleByType for an unadded type should return an invalid handle");

        FinishSuccess();
    }
}
