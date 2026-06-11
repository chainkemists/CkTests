#include "CkTests/Net/CkAutoTest_NetSubject.h"

#include "CkTests/Net/CkAutoTest_NetSubject_EntityScript.h"

#include "CkEcsExt/EntityScript/CkEntityScript_WithActor_Utils.h"

#include "Components/SceneComponent.h"
#include "EngineUtils.h"
#include "Engine/World.h"

// --------------------------------------------------------------------------------------------------------------------

ACk_AutoTest_NetSubject::
    ACk_AutoTest_NetSubject()
{
    bReplicates = true;
    bAlwaysRelevant = true;
    bReplicateUsingRegisteredSubObjectList = true;
    PrimaryActorTick.bCanEverTick = false;

    // A USceneComponent root with Movable mobility is required for UCk_EntityScript_WithActor_UE::Construct
    // to add the Transform fragment to the bridged entity (it guards on GetRootComponent() != nullptr).
    // Without it, CkTransform's FCk_RepData_Location/Rotation/Scale handlers have no entity to drive on
    // the client. Mobility=Movable also avoids the "non-movable RootComponent" ensure that
    // FProcessor_Transform_HandleRequests fires when a transform request lands on a static-rooted entity.
    auto* Root = CreateDefaultSubobject<USceneComponent>(TEXT("DefaultSceneRoot"));
    Root->SetMobility(EComponentMobility::Movable);
    RootComponent = Root;

    // Default — the standard test entity script that adds a single Float attribute (no refill).
    // Subclasses set this to their own UCk_EntityScript_WithActor_UE subclass in their own ctor
    // to drive different per-test setups.
    _EntityScriptClass = UCk_AutoTest_NetSubject_EntityScript_UE::StaticClass();
}

// --------------------------------------------------------------------------------------------------------------------

auto
    ACk_AutoTest_NetSubject::
    Find(
        UWorld* InWorld)
    -> ACk_AutoTest_NetSubject*
{
    if (InWorld == nullptr)
    { return nullptr; }

    for (auto It = TActorIterator<ACk_AutoTest_NetSubject>(InWorld); It; ++It)
    { return *It; }

    return nullptr;
}

// --------------------------------------------------------------------------------------------------------------------

auto
    ACk_AutoTest_NetSubject::
    BeginPlay()
    -> void
{
    Super::BeginPlay();

    // Mirror of ACk_ActorRelay_UE::BeginPlay — spawn a WithActor-based entity that owns the
    // bridge to this actor. The configured _EntityScriptClass (set per-subclass in ctor) is the
    // test-harness entity script that adds whatever per-test fragments Construct on both worlds
    // (Float attribute by default; refill-enabled attribute in the Refill subclass).
    // Authority-gating + spawn boilerplate live inside the helper.
    if (ck::Is_NOT_Valid(_EntityScriptClass))
    { return; }

    UCk_Utils_EntityScript_WithActor_UE::Request_SpawnEntityScript_OnActor(this, _EntityScriptClass);
}

// --------------------------------------------------------------------------------------------------------------------
