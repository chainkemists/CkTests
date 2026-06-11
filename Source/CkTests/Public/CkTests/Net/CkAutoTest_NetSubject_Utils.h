#pragma once

#include "CoreMinimal.h"

#include "GameplayTagContainer.h"
#include "Kismet/BlueprintFunctionLibrary.h"

#include "CkEcs/EntityScript/CkEntityScript_Fragment_Data.h"
#include "CkEcs/Handle/CkHandle.h"

#include "CkAutoTest_NetSubject_Utils.generated.h"

class UWorld;
class ACk_AutoTest_NetSubject;

// --------------------------------------------------------------------------------------------------------------------
//
// Thin BPFL wrapper exposing `ACk_AutoTest_NetSubject::Find` to AngelScript via the canonical
// `utils_auto_test_net_subject` namespace. AS-authored multi-client tests use this to locate the
// harness-spawned subject actor on their world before resolving the bridged entity.
//
// Lives in CkTests rather than CkFoundation because the subject actor itself is a test-harness
// concept — the project's runtime modules don't depend on it.
//
// --------------------------------------------------------------------------------------------------------------------

UCLASS(NotBlueprintable)
class CKTESTS_API UCk_Utils_AutoTest_NetSubject_UE : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()

public:
    UFUNCTION(BlueprintPure,
              Category = "Ck|Utils|AutoTest",
              DisplayName = "[Ck][AutoTest] Find Net Subject")
    static ACk_AutoTest_NetSubject*
    Find_NetSubject(
        const UWorld* InWorld);
};

// --------------------------------------------------------------------------------------------------------------------
//
// UObject helper used by `FCk_Latent_RunAsTestOnAllWorlds` to capture the constructed entity
// handle from each world's per-world Promise_OnConstructed callback. Required because
// `FCk_Delegate_EntityScript_Constructed` is a dynamic delegate (Hazelight AS, BP-bindable) that
// can only bind to a UObject's UFUNCTION method — IAutomationLatentCommand isn't a UObject so
// it can't bind directly. The latent command owns one of these via TStrongObjectPtr for the
// duration of the spawn-and-poll cycle.
//
// --------------------------------------------------------------------------------------------------------------------

UCLASS()
class CKTESTS_API UCk_AutoTest_BodyCapturer_UE : public UObject
{
    GENERATED_BODY()

public:
    // Bound to FCk_Delegate_EntityScript_Constructed via Promise_OnConstructed per world.
    // Appends the constructed handle's underlying FCk_Handle to _CapturedBodies in arrival
    // order. Arrival order is per-world spawn order — server first if spawned first in
    // FCk_Latent_RunAsTestOnAllWorlds's loop.
    UFUNCTION()
    void
    OnBodyConstructed(
        struct FCk_Handle_EntityScript InEntityScriptHandle);

    // Public so the latent command's Update() can iterate and poll result fragments. Not a
    // UPROPERTY because FCk_Handle isn't reflected (it's the ECS entity reference, kept alive
    // by the registry itself for the duration of the test session).
    TArray<FCk_Handle> _CapturedBodies;
};

// --------------------------------------------------------------------------------------------------------------------
//
// UObject helper for specs that assert on state INSIDE an OnReplicationComplete callback.
// FCk_Delegate_EntityReplicationDriver_OnReplicationComplete is a dynamic delegate, so the
// spec's latent commands (not UObjects) can't bind a lambda — they bind this capturer's
// UFUNCTION instead and inspect the snapshot it records at fire time. The spec owns the
// instance via TStrongObjectPtr shared across its latent commands.
//
// --------------------------------------------------------------------------------------------------------------------

UCLASS()
class CKTESTS_API UCk_AutoTest_RepCompleteCapturer_UE : public UObject
{
    GENERATED_BODY()

public:
    // Bound via UCk_Utils_EntityReplicationDriver_UE::Promise_OnReplicationComplete. Snapshots
    // the Float attribute identified by _AttributeTag from the firing entity — the value the
    // lifecycle contract guarantees is already applied when this callback runs.
    UFUNCTION()
    void
    OnReplicationComplete(
        FCk_Handle InHandle);

    // Set by the spec before binding. Not UPROPERTYs — the spec reaches in directly, mirroring
    // UCk_AutoTest_BodyCapturer_UE::_CapturedBodies.
    FGameplayTag _AttributeTag;

    bool _Fired = false;
    bool _AttributeWasPresentAtFire = false;
    float _FinalValueAtFire = 0.0f;
};

// --------------------------------------------------------------------------------------------------------------------
//
// UObject helper for specs that assert on state INSIDE a Promise_OnActorEcsReady callback.
// FCk_Delegate_OwningActor_OnEcsReady is a dynamic delegate, so latent commands bind this
// capturer's UFUNCTION and inspect the snapshot it records at fire time. One instance per
// bound promise — the spec owns each via TStrongObjectPtr shared across its latent commands.
//
// --------------------------------------------------------------------------------------------------------------------

UCLASS()
class CKTESTS_API UCk_AutoTest_EcsReadyCapturer_UE : public UObject
{
    GENERATED_BODY()

public:
    // Bound via UCk_Utils_OwningActor_UE::Promise_OnActorEcsReady. Snapshots the firing
    // entity's replication-completion state and (when _AttributeTag is set) the Float
    // attribute the harness entity-script bakes during Construct.
    UFUNCTION()
    void
    OnActorEcsReady(
        AActor* InActor,
        FCk_Handle InEntity);

    // Set by the spec before binding. Not UPROPERTYs — the spec reaches in directly.
    FGameplayTag _AttributeTag;

    bool _Fired = false;
    int32 _FireCount = 0;
    bool _EntityWasValidAtFire = false;
    bool _ReplicationWasCompleteAtFire = false;
    bool _AttributeWasPresentAtFire = false;
    float _FinalValueAtFire = 0.0f;
};
