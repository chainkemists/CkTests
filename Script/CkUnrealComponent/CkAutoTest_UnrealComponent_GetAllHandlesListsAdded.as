// Language=angelscript
//
// CK UNREAL COMPONENT - AUTOMATION TEST: Get_AllHandles lists every added component
// Two Add calls populate Get_AllHandles with N=2 entries.

class UCk_AutoTest_UnrealComponent_GetAllHandlesListsAdded : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(Owner, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        const auto MeshParams = utils_unreal_component::Make_Params(
            UStaticMeshComponent, ECk_UnrealComponent_TickPolicy::DoNotTick, n"AutoTest_Mesh");
        utils_unreal_component::Add(Owner, MeshParams);

        const auto LightParams = utils_unreal_component::Make_Params(
            UPointLightComponent, ECk_UnrealComponent_TickPolicy::DoNotTick, n"AutoTest_Light");
        utils_unreal_component::Add(Owner, LightParams);

        auto All = utils_unreal_component::Get_AllHandles(Owner);
        Assert_Equals_Int(All.Num(), 2,
            "Get_AllHandles should report one handle per Add call");

        FinishSuccess();
    }
}
