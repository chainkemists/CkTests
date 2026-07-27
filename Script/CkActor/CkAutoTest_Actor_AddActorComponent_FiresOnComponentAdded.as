// Language=angelscript

//============================================================================
// CK ACTOR — AUTOMATION TEST: Request_AddActorComponent FIRES OnComponentAdded
//============================================================================
//
// Pins the Request_AddActorComponent → OnActorComponentAdded delegate
// contract end-to-end:
//   1. Spawn an actor-backed entity via the shared scaffold so it carries
//      the OwningActor fragment that Request_AddActorComponent ensures on.
//   2. Build the request with ComponentToAdd = UStaticMeshComponent and
//      AttachmentPolicy = DoNotAttach (so no parent USceneComponent is
//      required).
//   3. Dispatch and wait one frame for the deferred processor to handle it.
//   4. Assert the delegate fired with valid owner + component handles.
//
// Bind-signature note: the delegate's third param is `const FInstancedStruct&`
// (const-ref), so the AS UFUNCTION must declare `const FInstancedStruct &in`
// — bare `FInstancedStruct` fails compile with "Specified function is not
// compatible with delegate function". See feedback_as_delegate_const_ref_signature.md.
//============================================================================

class UCk_AutoTest_Actor_AddActorComponent_FiresOnComponentAdded : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private ACkAutoTest_ActorEntity_Helper _Helper;
    private bool _DelegateFired = false;
    private bool _OwnerValid = false;
    private bool _ComponentValid = false;

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

        auto OwnedEntity = FCk_Handle(InEntityScriptHandle);

        // The processor's Request_AddActorComponent path ensures on a valid
        // ComponentParent regardless of AttachmentType — it dereferences
        // ComponentParent->GetOwner() to resolve the actor. Pass the helper's
        // SceneRoot to satisfy the validity ensure; DoNotAttach then skips
        // the actual attachment step.
        auto ComponentParams = FCk_AddActorComponent_Params(_Helper.SceneRoot);
        ComponentParams.Set_AttachmentType(ECk_ActorComponent_AttachmentPolicy::DoNotAttach);

        auto Req = FCk_Request_ActorModifier_AddActorComponent(UStaticMeshComponent);
        Req.Set_ComponentParams(ComponentParams);

        utils_actor_modifier::Request_AddActorComponent(
            OwnedEntity,
            Req,
            FInstancedStruct(),
            FCk_Delegate_ActorModifier_OnActorComponentAdded(this, n"OnComponentAdded"));

        WaitUntil(n"Check_DelegateFired", n"OnSettled");
    }

    UFUNCTION()
    private void Check_DelegateFired(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_DelegateFired);
    }

    UFUNCTION()
    private void OnComponentAdded(
        AActor InOwner,
        UActorComponent InActorComponentAdded,
        const FInstancedStruct &in InOptionalPayload)
    {
        _DelegateFired = true;
        _OwnerValid = ck::IsValid(InOwner);
        _ComponentValid = ck::IsValid(InActorComponentAdded);
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        Assert_True(_DelegateFired,
            "FCk_Delegate_ActorModifier_OnActorComponentAdded should fire after Request_AddActorComponent");
        Assert_True(_OwnerValid,
            "OnComponentAdded should fire with a valid InOwner actor");
        Assert_True(_ComponentValid,
            "OnComponentAdded should fire with a valid InActorComponentAdded");
        FinishSuccess();
    }
}
