// Language=angelscript
//
// CK UNREAL COMPONENT — AUTOMATION TEST: Add happy path
// Add a UStaticMeshComponent to a transform-bearing entity; returned handle
// is valid and Get_Component returns a non-null UActorComponent after the
// Setup processor has ticked.

class UCk_AutoTest_UnrealComponent_AddHappyPath : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle_UnrealComponent _CompHandle;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(Owner, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        const auto Params = utils_unreal_component::Make_Params(
            UStaticMeshComponent, ECk_UnrealComponent_TickPolicy::DoNotTick, n"AutoTest_Mesh");
        _CompHandle = utils_unreal_component::Add(Owner, Params);

        Assert_True(utils_handle::Get_IsValid(_CompHandle),
            "Add should return a valid FCk_Handle_UnrealComponent (synchronously)");

        // Component instantiation is deferred — FProcessor_UnrealComponent_Setup
        // runs on the next tick and calls NewObject(Host, Class). Wait for it.
        WaitOneFrame(n"OnSetupComplete");
    }

    UFUNCTION()
    private void OnSetupComplete(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Comp = utils_unreal_component::Get_Component(_CompHandle);
        Assert_True(ck::IsValid(Comp),
            "Get_Component should return a non-null UActorComponent after Setup ticks");

        FinishSuccess();
    }
}
