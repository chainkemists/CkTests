// Language=angelscript

//============================================================================
// CK ACTOR — AUTOMATION TEST: AddActorComponent IsUnique=false ALLOWS DUPLICATE
//============================================================================
//
// Pins the _IsUnique=false escape hatch on Request_AddActorComponent.
//
// The default _IsUnique=true path goes through a CK_ENSURE_IF_NOT (in
// Request_AddNewActorComponent) when a same-class component already exists,
// so the rejection path cannot be exercised by an AutoTest without
// triggering an ensure-escalation failure. The opt-out _IsUnique=false
// path skips that check and produces a second, distinct component.
//
// Flow:
//   1. Add UStaticMeshComponent #1 with _IsUnique=false.
//   2. After delegate #1 fires and captures Component_A, add #2 with the
//      same class + _IsUnique=false.
//   3. Wait for delegate #2 to capture Component_B.
//   4. Assert both components are valid AND Component_A != Component_B.
//============================================================================

class UCk_AutoTest_Actor_AddActorComponent_IsUniqueFalse_AllowsDuplicate : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private ACkAutoTest_ActorEntity_Helper _Helper;
    private FCk_Handle _OwnedEntity;
    private UActorComponent _ComponentA;
    private UActorComponent _ComponentB;
    private int32 _DelegateFireCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
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

        // Dispatch both adds upfront, each binding its own request-fulfilled
        // signal. Dispatching the second from inside the first delegate
        // callback is unsafe (the originating request entity is being
        // destroyed by the processor that just fired the signal). Each
        // dispatch creates an independent RequestEntity, so the two
        // bindings don't collide.
        DispatchAdd(n"OnAddA");
        DispatchAdd(n"OnAddB");

        WaitOneFrame(n"OnSettled");
    }

    private void DispatchAdd(FName InCallbackName)
    {
        auto ComponentParams = FCk_AddActorComponent_Params();
        ComponentParams.Set_Parent(_Helper.SceneRoot);
        ComponentParams.Set_AttachmentType(ECk_ActorComponent_AttachmentPolicy::DoNotAttach);

        auto Req = FCk_Request_ActorModifier_AddActorComponent(UStaticMeshComponent);
        Req.Set_ComponentParams(ComponentParams);
        Req.Set_IsUnique(false);

        utils_actor_modifier::Request_AddActorComponent(
            _OwnedEntity,
            Req,
            FInstancedStruct(),
            FCk_Delegate_ActorModifier_OnActorComponentAdded(this, InCallbackName));
    }

    UFUNCTION()
    private void OnAddA(
        AActor InOwner,
        UActorComponent InActorComponentAdded,
        const FInstancedStruct &in InOptionalPayload)
    {
        _DelegateFireCount++;
        _ComponentA = InActorComponentAdded;
    }

    UFUNCTION()
    private void OnAddB(
        AActor InOwner,
        UActorComponent InActorComponentAdded,
        const FInstancedStruct &in InOptionalPayload)
    {
        _DelegateFireCount++;
        _ComponentB = InActorComponentAdded;
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_DelegateFireCount, 2,
            "Both OnComponentAdded delegates should have fired");
        Assert_True(ck::IsValid(_ComponentA),
            "First added component should be valid");
        Assert_True(ck::IsValid(_ComponentB),
            "Second added component should be valid");
        Assert_True(_ComponentA != _ComponentB,
            "With _IsUnique=false, the two AddActorComponent calls should produce distinct components");
        FinishSuccess();
    }
}
