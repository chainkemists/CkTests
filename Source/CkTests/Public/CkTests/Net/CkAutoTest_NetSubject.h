#pragma once

#include "CoreMinimal.h"

#include "GameFramework/Actor.h"
#include "Templates/SubclassOf.h"

#include "CkTagSet/CkTagSet_Fragment_Data.h"

#include "CkAutoTest_NetSubject.generated.h"

class UCk_EntityScript_WithActor_UE;

// --------------------------------------------------------------------------------------------------------------------
//
// Subject actor used by the multi-client AutoTest harness as the "subject" of a replication test.
//
// CkFoundation's replicated entities must live under a replicated AActor — the replication driver
// walks the entity's ownership chain looking for a replicated outer Actor to bind the driver
// UObject to.
//
// IMPORTANT — on `BeginPlay` (authority only) the actor spawns a `UCk_EntityScript_WithActor_UE`
// entity. This is the same pattern `ACk_ActorRelay_UE` uses, and it matters specifically because
// `UCk_EntityScript_WithActor_UE::Construct` calls `SetupActorEntityLink`, which adds the
// `UCk_EntityOwningActor_ActorComponent_UE` component to the actor. That Construct runs on both
// server and client via the entity-script lifecycle's replication path — so the component (and
// the `Actor → Entity` reverse lookup it backs) ends up on the client too. The bare
// `Request_CreateEntity` + manual `OwningActor::Add` pattern (used by the SM ServerAuthReplay
// test) does NOT establish the component on the client; that's why those tests use per-world
// recorders instead of direct cross-world entity lookup.
//
// The actor is otherwise minimal — no components, no Tick. The test spec spawns it on the
// server, waits a few ticks for ECS construction to complete, then attaches whatever replicated
// fragment the test exercises (e.g. a Float attribute) to the bridged entity via
// `UCk_Utils_OwningActor_UE::Get_ActorEntityHandle(Subject)`.
//
// --------------------------------------------------------------------------------------------------------------------

UCLASS(BlueprintType)
class CKTESTS_API ACk_AutoTest_NetSubject : public AActor
{
    GENERATED_BODY()

public:
    ACk_AutoTest_NetSubject();

    // Discovery helper — walks the world for the first ACk_AutoTest_NetSubject and returns it,
    // or nullptr if none exists yet. Test specs use this on both the server world and each
    // client world to locate the subject before resolving its bridged entity and attribute(s).
    // There is at most one subject per world in the harness's current design (one server-spawned
    // actor that replicates to clients); if a test ever needs multiple subjects, this helper
    // needs to grow a discriminator argument.
    static auto
    Find(
        class UWorld* InWorld) -> ACk_AutoTest_NetSubject*;

protected:
    virtual auto BeginPlay() -> void override;

    // Which entity-script class to spawn on BeginPlay (authority side). Subclasses override the
    // default via their constructor (e.g. ACk_AutoTest_NetSubject_Refill swaps in a refill-
    // enabled entity script). Kept as a UPROPERTY rather than a virtual so test code can inspect
    // the configured class via reflection if needed, and so a hypothetical "configure-by-data-
    // asset" path remains open. Must be a UCk_EntityScript_WithActor_UE subclass — the actor↔entity
    // bridge contract depends on the WithActor `Construct` running on both worlds.
    UPROPERTY()
    TSubclassOf<UCk_EntityScript_WithActor_UE> _EntityScriptClass;

public:
    // Stashed by the default entity-script (UCk_AutoTest_NetSubject_EntityScript_UE) which adds a
    // Replicates TagSet alongside the Float/Byte/Integer/Vector attributes. Transient, local-only;
    // each world's entity-script populates its own. Used by the CkTagSet net test to drive
    // Request_AddTag on the server and poll HasTag on the client without a by-name lookup (a
    // TagSet is single-per-entity). Subjects spawned with a non-default entity-script leave this
    // unset, which is fine — only the TagSet test reads it.
    UPROPERTY(Transient, BlueprintReadOnly, Category = "Ck|AutoTest")
    FCk_Handle_TagSet _TestTagSet;
};
