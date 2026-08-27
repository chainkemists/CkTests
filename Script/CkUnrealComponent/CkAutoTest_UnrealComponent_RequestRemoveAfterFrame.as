// Language=angelscript
//
// CK UNREAL COMPONENT - AUTOMATION TEST: Request_Remove tears down the child entity
// After Request_Remove the child entity is destroyed, leaving the handle invalid
// and the owner's Get_AllHandles list empty.

class UCk_AutoTest_UnrealComponent_RequestRemoveAfterFrame : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle _Owner;
    private FCk_Handle_UnrealComponent _CompHandle;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_Owner, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        const auto Params = utils_unreal_component::Make_Params(
            UStaticMeshComponent, ECk_UnrealComponent_TickPolicy::DoNotTick, n"AutoTest");
        _CompHandle = utils_unreal_component::Add(_Owner, Params);

        Assert_True(utils_handle::Get_IsValid(_CompHandle),
            "Pre-Remove: component handle should be valid");

        utils_unreal_component::Request_Remove(_CompHandle);
        WaitUntil(n"Check_HandleReleased", n"OnSettled");
    }

    UFUNCTION()
    private void Check_HandleReleased(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_handle::Get_IsValid(_CompHandle) == false);
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        Assert_True(!utils_handle::Get_IsValid(_CompHandle),
            "Post-Remove: handle should be invalid after one frame");

        auto Remaining = utils_unreal_component::Get_AllHandles(_Owner);
        Assert_Equals_Int(Remaining.Num(), 0,
            "Owner's Get_AllHandles should be empty after Remove settles");

        FinishSuccess();
    }
}
