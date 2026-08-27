// Language=angelscript
//
// CK UNREAL COMPONENT - AUTOMATION TEST: TryGet_OwningHandle_FromComponent reverse lookup
// Given a raw UActorComponent pointer (recovered via Get_Component after the
// Setup tick), the reverse lookup yields the original FCk_Handle_UnrealComponent.

class UCk_AutoTest_UnrealComponent_TryGetOwningHandleFromComponent : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle_UnrealComponent _Original;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(Owner, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        const auto Params = utils_unreal_component::Make_Params(
            UStaticMeshComponent, ECk_UnrealComponent_TickPolicy::DoNotTick, n"AutoTest");
        _Original = utils_unreal_component::Add(Owner, Params);

        WaitUntil(n"Check_ComponentInstantiated", n"OnSetupComplete");
    }

    UFUNCTION()
    private void Check_ComponentInstantiated(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(ck::IsValid(utils_unreal_component::Get_Component(_Original)));
    }

    UFUNCTION()
    private void OnSetupComplete(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto Comp = utils_unreal_component::Get_Component(_Original);
        Assert_True(ck::IsValid(Comp), "Pre-condition: Get_Component should return a non-null component");

        auto Recovered = utils_unreal_component::TryGet_OwningHandle_FromComponent(Comp);
        Assert_True(utils_handle::Get_IsValid(Recovered),
            "TryGet_OwningHandle_FromComponent should return a valid handle for a known component");
        Assert_True(utils_handle::IsEqual(Recovered, _Original),
            "Reverse lookup should yield the same handle that Add returned");

        FinishSuccess();
    }
}
