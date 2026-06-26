// Language=angelscript
//
// CK UNREAL COMPONENT — AUTOMATION TEST: Get_AllComponents resolves to live UActorComponents
// After the Setup processor ticks, Get_AllComponents returns one entry per
// Add and every entry is a live UActorComponent.

class UCk_AutoTest_UnrealComponent_GetAllComponentsListsAdded : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle _Owner;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_Owner, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        const auto MeshParams = utils_unreal_component::Make_Params(
            UStaticMeshComponent, ECk_UnrealComponent_TickPolicy::DoNotTick, n"AutoTest_Mesh");
        utils_unreal_component::Add(_Owner, MeshParams);

        const auto LightParams = utils_unreal_component::Make_Params(
            UPointLightComponent, ECk_UnrealComponent_TickPolicy::DoNotTick, n"AutoTest_Light");
        utils_unreal_component::Add(_Owner, LightParams);

        WaitOneFrame(n"OnSetupComplete");
    }

    UFUNCTION()
    private void OnSetupComplete(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Comps = utils_unreal_component::Get_AllComponents(_Owner);
        Assert_Equals_Int(Comps.Num(), 2,
            "Get_AllComponents should report one UActorComponent per Add call");

        for (auto Comp : Comps)
        {
            Assert_True(ck::IsValid(Comp),
                "Every entry in Get_AllComponents should be a live UActorComponent");
        }

        FinishSuccess();
    }
}
