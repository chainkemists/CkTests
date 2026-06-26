// Language=angelscript

//============================================================================
// CK ACTOR — AUTOMATION TEST: SpawnActor SpawnTransform APPLIED TO SPAWNED ACTOR
//============================================================================
//
// Pins the contract that FCk_Utils_Actor_SpawnActor_Params::_SpawnTransform
// is applied to the resulting actor's world transform when
// Request_SpawnActor runs.
//
// Implementation note — actor class choice:
//   Spawning a bare `AActor` for this test fails not because the transform
//   doesn't propagate, but because AActor has no root component. UE's
//   World->SpawnActor calls SetActorTransform under the hood, which silently
//   returns false when the spawned actor has no RootComponent. So the
//   spawned actor reports (0,0,0,Identity) for GetActorLocation/Rotation
//   regardless of what SpawnTransform was set. The companion diagnostic
//   `CkAutoTest_Actor_SpawnTransform_SetterWritesValue_Diagnostic` proves
//   the AS-side propagation (Set / Get / Request ctor copy) is correct in
//   isolation — the loss only happens for rootless spawn targets.
//
//   This test uses a local AActor subclass with a USceneComponent root, so
//   the spawn-time transform survives all the way to GetActorLocation().
//
// Flow:
//   1. Build SpawnParams targeting the rooted test actor with a non-identity
//      SpawnTransform.
//   2. Dispatch Request_SpawnActor with SpawnOnServer policy.
//   3. In OnActorSpawned, capture the spawned actor's world transform.
//   4. Assert location + rotation match the requested transform.
//============================================================================

class ACkAutoTest_RootedSpawnTarget : AActor
{
    default bReplicates = false;

    UPROPERTY(DefaultComponent, RootComponent)
    USceneComponent SceneRoot;

    default SceneRoot.Mobility = EComponentMobility::Movable;
}

class UCk_AutoTest_Actor_SpawnActor_SpawnTransform_AppliedToSpawnedActor : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private const FVector ExpectedLocation = FVector(450.0f, 250.0f, 75.0f);
    private const FRotator ExpectedRotation = FRotator(0.0f, 45.0f, 0.0f);
    private const float32 PositionToleranceCm = 1.0f;
    private const float32 RotationToleranceDeg = 1.0f;

    private ACkAutoTest_ActorEntity_Helper _Helper;
    private FVector _ObservedLocation;
    private FRotator _ObservedRotation;
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

        auto SpawnParams = FCk_Utils_Actor_SpawnActor_Params(_Helper, ACkAutoTest_RootedSpawnTarget);
        SpawnParams.Set_SpawnTransform(FTransform(ExpectedRotation, ExpectedLocation, FVector::OneVector));

        auto Req = FCk_Request_ActorModifier_SpawnActor(SpawnParams);
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
        if (_SpawnedValid)
        {
            _ObservedLocation = InActorSpawned.GetActorLocation();
            _ObservedRotation = InActorSpawned.GetActorRotation();
        }
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(_DelegateFired, "OnActorSpawned should have fired");
        Assert_True(_SpawnedValid, "InActorSpawned should be valid");
        Assert_True(_ObservedLocation.Equals(ExpectedLocation, PositionToleranceCm),
            f"Spawned actor location | expected {ExpectedLocation}, got {_ObservedLocation}");
        Assert_True(_ObservedRotation.Equals(ExpectedRotation, RotationToleranceDeg),
            f"Spawned actor rotation | expected {ExpectedRotation}, got {_ObservedRotation}");
        FinishSuccess();
    }
}
