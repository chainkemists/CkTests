// Language=angelscript
//
// CK UNREAL COMPONENT — AUTOMATION TEST: TryGet_HandleByType returns the match
// After the Setup processor has instantiated the component, looking it up
// by class returns the same handle that Add returned.

class UCk_AutoTest_UnrealComponent_TryGetHandleByTypeFound : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle _Owner;
    private FCk_Handle_UnrealComponent _AddedHandle;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_Owner, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        const auto Params = utils_unreal_component::Make_Params(
            UStaticMeshComponent, ECk_UnrealComponent_TickPolicy::DoNotTick, n"AutoTest");
        _AddedHandle = utils_unreal_component::Add(_Owner, Params);

        WaitUntil(n"Check_ComponentInstantiated", n"OnSetupComplete");
    }

    UFUNCTION()
    private void Check_ComponentInstantiated(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(ck::IsValid(utils_unreal_component::Get_Component(_AddedHandle)));
    }

    UFUNCTION()
    private void OnSetupComplete(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto Found = utils_unreal_component::TryGet_HandleByType(_Owner, UStaticMeshComponent);
        Assert_True(utils_handle::Get_IsValid(Found),
            "TryGet_HandleByType should return a valid handle for an added component type");
        Assert_True(utils_handle::IsEqual(Found, _AddedHandle),
            "TryGet_HandleByType should return the handle from Add");

        FinishSuccess();
    }
}
