// Language=angelscript

//============================================================================
// CK ACTOR — AUTOMATION TEST: Request_RemoveActorComponent FIRES OnComponentRemoved
//============================================================================
//
// Pins the Request_RemoveActorComponent → OnActorComponentRemoved delegate
// contract. Flow:
//   1. Add a UStaticMeshComponent to the helper actor via Request_AddActorComponent.
//   2. Capture the added component's reference inside the OnComponentAdded
//      delegate.
//   3. Dispatch Request_RemoveActorComponent against the captured component.
//   4. Wait a frame for the deferred remove processor.
//   5. Assert the OnComponentRemoved delegate fired with a valid owner +
//      removed-component-class.
//
// Note: OnComponentRemoved's middle param is `TSubclassOf<UActorComponent>`
// (the *class* of the removed component, not the instance) — so the AS bound
// function signature uses `TSubclassOf<UActorComponent>` there.
//============================================================================

class UCk_AutoTest_Actor_RemoveActorComponent_FiresOnComponentRemoved : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private ACkAutoTest_ActorEntity_Helper _Helper;
    private FCk_Handle _OwnedEntity;
    private UActorComponent _AddedComponent;
    private bool _AddDelegateFired = false;
    private bool _RemoveDelegateFired = false;
    private bool _RemovedOwnerValid = false;
    private bool _RemovedClassValid = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Helper = Cast<ACkAutoTest_ActorEntity_Helper>(SpawnActor(
            ACkAutoTest_ActorEntity_Helper, FVector::ZeroVector, FRotator::ZeroRotator));
        if (ck::Is_NOT_Valid(_Helper))
        {
            FinishFailure("Failed to spawn ActorEntity helper");
            return;
        }

        utils_pending_entity_script::Promise_OnConstructed(
            _Helper.PendingEntity,
            FCk_Delegate_EntityScript_Constructed(this, n"OnEntityReady"));
    }

    UFUNCTION()
    private void OnEntityReady(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        if (IsFinished()) { return; }

        _OwnedEntity = FCk_Handle(InEntityScriptHandle);

        auto ComponentParams = FCk_AddActorComponent_Params(_Helper.SceneRoot);
        ComponentParams.Set_AttachmentType(ECk_ActorComponent_AttachmentPolicy::DoNotAttach);

        auto Req = FCk_Request_ActorModifier_AddActorComponent(UStaticMeshComponent);
        Req.Set_ComponentParams(ComponentParams);

        utils_actor_modifier::Request_AddActorComponent(
            _OwnedEntity,
            Req,
            FInstancedStruct(),
            FCk_Delegate_ActorModifier_OnActorComponentAdded(this, n"OnComponentAdded"));
    }

    UFUNCTION()
    private void OnComponentAdded(
        AActor InOwner,
        UActorComponent InActorComponentAdded,
        const FInstancedStruct &in InOptionalPayload)
    {
        _AddDelegateFired = true;
        _AddedComponent = InActorComponentAdded;

        if (ck::Is_NOT_Valid(_AddedComponent))
        {
            FinishFailure("AddActorComponent fired but returned an invalid component handle");
            return;
        }

        auto RemoveReq = FCk_Request_ActorModifier_RemoveActorComponent(_AddedComponent);
        utils_actor_modifier::Request_RemoveActorComponent(
            _OwnedEntity,
            RemoveReq,
            FInstancedStruct(),
            FCk_Delegate_ActorModifier_OnActorComponentRemoved(this, n"OnComponentRemoved"));

        WaitUntil(n"Check_DelegateFired", n"OnSettled");
    }

    UFUNCTION()
    private void Check_DelegateFired(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_RemoveDelegateFired);
    }

    UFUNCTION()
    private void OnComponentRemoved(
        AActor InOwner,
        TSubclassOf<UActorComponent> InActorComponentTypeRemoved,
        const FInstancedStruct &in InOptionalPayload)
    {
        _RemoveDelegateFired = true;
        _RemovedOwnerValid = ck::IsValid(InOwner);
        _RemovedClassValid = ck::IsValid(InActorComponentTypeRemoved);
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        Assert_True(_AddDelegateFired,
            "Prerequisite: AddActorComponent delegate should have fired");
        Assert_True(_RemoveDelegateFired,
            "FCk_Delegate_ActorModifier_OnActorComponentRemoved should fire after Request_RemoveActorComponent");
        Assert_True(_RemovedOwnerValid,
            "OnComponentRemoved should fire with a valid InOwner actor");
        Assert_True(_RemovedClassValid,
            "OnComponentRemoved should fire with a valid InActorComponentTypeRemoved class");
        FinishSuccess();
    }
}
