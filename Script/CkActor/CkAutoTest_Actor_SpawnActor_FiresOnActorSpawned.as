// Language=angelscript

//============================================================================
// CK ACTOR — AUTOMATION TEST: Request_SpawnActor FIRES OnActorSpawned
//============================================================================
//
// Pins the Request_SpawnActor → OnActorSpawned delegate contract:
//   1. Build a SpawnActor_Params for AActor in the test world (the helper
//      actor is used as the UObject world-context).
//   2. Dispatch Request_SpawnActor with a OnActorSpawned delegate bound.
//   3. Wait one frame for the deferred processor to fire.
//   4. Assert the delegate fired with a valid newly-spawned actor.
//
// Bind-signature note: const FInstancedStruct& on the delegate side requires
// `const FInstancedStruct &in` on the AS bound function. See
// feedback_as_delegate_const_ref_signature.md.
//============================================================================

class UCk_AutoTest_Actor_SpawnActor_FiresOnActorSpawned : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private ACkAutoTest_ActorEntity_Helper _Helper;
    private bool _DelegateFired = false;
    private bool _SpawnedValid = false;

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

        auto SpawnParams = FCk_Utils_Actor_SpawnActor_Params(_Helper, AActor);

        auto Req = FCk_Request_ActorModifier_SpawnActor(SpawnParams);
        // The default SpawnPolicy (SpawnOnInstanceWithOwnership) requires the
        // owning actor to have RemoteRole != ROLE_None (i.e. be replicated).
        // Our helper actor uses bReplicates=false so that path silently
        // early-returns. SpawnOnServer instead only needs the world to NOT
        // be a NetMode_Client — true under standalone PIE — so the spawn
        // proceeds and the OnActorSpawned signal broadcasts.
        Req.Set_SpawnPolicy(ECk_SpawnActor_SpawnPolicy::SpawnOnServer);

        utils_actor_modifier::Request_SpawnActor(
            OwnedEntity,
            Req,
            FInstancedStruct(),
            FCk_Delegate_ActorModifier_OnActorSpawned(this, n"OnSpawned"));

        WaitOneFrame(n"OnSettled");
    }

    UFUNCTION()
    private void OnSpawned(
        AActor InActorSpawned,
        const FInstancedStruct &in InOptionalPayload)
    {
        _DelegateFired = true;
        _SpawnedValid = ck::IsValid(InActorSpawned);
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(_DelegateFired,
            "FCk_Delegate_ActorModifier_OnActorSpawned should fire after Request_SpawnActor");
        Assert_True(_SpawnedValid,
            "OnActorSpawned should fire with a valid InActorSpawned");
        FinishSuccess();
    }
}
