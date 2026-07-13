#pragma once

#include "CkEcs/Handle/CkHandle.h"
#include "CkCore/Macros/CkMacros.h"

#include <CoreMinimal.h>
#include <NativeGameplayTags.h>

#include "CkTests_Fragment_Data.generated.h"

// --------------------------------------------------------------------------------------------------------------------
//
// FCk_Fragment_AutoTest_HandleHolder
//
// Test-only fragment that stores a single FCk_Handle inside an entity. Used by
// the Phase-0 generational-handle migration AutoTests to characterise the
// "handle stored in a fragment that lives in the same registry the handle
// references" cycle scenario. Pre-migration this requires Registry::Shutdown()
// to break the cycle; post-migration the handle is just (slot, gen) bytes
// and there should be no cycle to break.
//
// --------------------------------------------------------------------------------------------------------------------

USTRUCT(BlueprintType)
struct CKTESTS_API FCk_Fragment_AutoTest_HandleHolder
{
    GENERATED_BODY()

public:
    CK_GENERATED_BODY(FCk_Fragment_AutoTest_HandleHolder);

private:
    UPROPERTY(EditAnywhere, BlueprintReadWrite,
              meta = (AllowPrivateAccess = true))
    FCk_Handle _StoredHandle;

public:
    CK_PROPERTY(_StoredHandle);
};

// --------------------------------------------------------------------------------------------------------------------

CKTESTS_API UE_DECLARE_GAMEPLAY_TAG_EXTERN(TAG_FloatAttribute_A);
CKTESTS_API UE_DECLARE_GAMEPLAY_TAG_EXTERN(TAG_FloatAttribute_B);
CKTESTS_API UE_DECLARE_GAMEPLAY_TAG_EXTERN(TAG_FloatAttribute_C);

// --------------------------------------------------------------------------------------------------------------------

CKTESTS_API UE_DECLARE_GAMEPLAY_TAG_EXTERN(TAG_ByteAttribute_Intent_R);

// --------------------------------------------------------------------------------------------------------------------

CKTESTS_API UE_DECLARE_GAMEPLAY_TAG_EXTERN(TAG_Resolver_DataBundle_Phase_Ck_Gyms_Phase1);
CKTESTS_API UE_DECLARE_GAMEPLAY_TAG_EXTERN(TAG_Resolver_DataBundle_Phase_Ck_Gyms_Phase2);
CKTESTS_API UE_DECLARE_GAMEPLAY_TAG_EXTERN(TAG_Resolver_DataBundle_Phase_Ck_Gyms_Phase3);

// --------------------------------------------------------------------------------------------------------------------

CKTESTS_API UE_DECLARE_GAMEPLAY_TAG_EXTERN(TAG_Timer_Tests);

// --------------------------------------------------------------------------------------------------------------------

CKTESTS_API UE_DECLARE_GAMEPLAY_TAG_EXTERN(TAG_Ism_Renderer_Test_Cube);
CKTESTS_API UE_DECLARE_GAMEPLAY_TAG_EXTERN(TAG_Ism_Renderer_Test_Cylinder);
CKTESTS_API UE_DECLARE_GAMEPLAY_TAG_EXTERN(TAG_Ism_Renderer_Test_Sphere);

// --------------------------------------------------------------------------------------------------------------------

CKTESTS_API UE_DECLARE_GAMEPLAY_TAG_EXTERN(TAG_Gyms_Ability_Jump);
CKTESTS_API UE_DECLARE_GAMEPLAY_TAG_EXTERN(TAG_Gyms_Ability_Cue_JumpTakeOff);

CKTESTS_API UE_DECLARE_GAMEPLAY_TAG_EXTERN(TAG_Gyms_Probe_A);
CKTESTS_API UE_DECLARE_GAMEPLAY_TAG_EXTERN(TAG_Gyms_Probe_B);
CKTESTS_API UE_DECLARE_GAMEPLAY_TAG_EXTERN(TAG_Gyms_Probe_C);

CKTESTS_API UE_DECLARE_GAMEPLAY_TAG_EXTERN(TAG_Gyms_Probe_InteractA);
CKTESTS_API UE_DECLARE_GAMEPLAY_TAG_EXTERN(TAG_Gyms_Probe_InteractB);

// --------------------------------------------------------------------------------------------------------------------

// EntityCollection net-test collection name. Must be a *registered* tag — the EntityCollection
// SyncReplication processor keys its local-collection lookup by the replicated _CollectionName
// (TryGet_EntityCollection(owner, name)), so an unregistered/empty tag (TAG_NOT_SET) makes the
// client-side lookup fail permanently. FGameplayTag::RequestGameplayTag on an unregistered name
// returns empty, which is exactly the bug this native definition avoids.
CKTESTS_API UE_DECLARE_GAMEPLAY_TAG_EXTERN(TAG_EntityCollection_AutoTest_Net);

// --------------------------------------------------------------------------------------------------------------------

// Spatial inventory net-test name. Must be a *registered* tag — the inventory SyncReplication path
// keys its client-side inventory lookup by the inventory's name label (Record entry matched via
// MatchesGameplayLabelExact). The default net subject now carries BOTH a DataOnly and a Spatial
// inventory, so the Spatial one needs a distinct, valid name or the client can't disambiguate it
// (an unregistered name resolves to empty/None and collides). Same lesson as
// TAG_EntityCollection_AutoTest_Net above.
// The DataOnly inventory needs a registered name for the SAME reason as the Spatial one below: an
// unregistered name resolves to empty/None → the inventory gets an unnamed GameplayLabel → the v3
// snapshot capture refuses to persist it (Rule 3 requires a named label) → its items can't round-trip.
CKTESTS_API UE_DECLARE_GAMEPLAY_TAG_EXTERN(TAG_Inventory_AutoTest_Net);

// --------------------------------------------------------------------------------------------------------------------

CKTESTS_API UE_DECLARE_GAMEPLAY_TAG_EXTERN(TAG_Inventory_AutoTest_Net_Spatial);

// --------------------------------------------------------------------------------------------------------------------

// AnimPlan net-test goal/cluster/state tags. AnimPlan state is pure tag data (no skeletal mesh
// needed); the rep handler keys the client AnimPlan lookup by the goal label, so these must be
// registered. Two states let the server move A->B and the client observe the replicated change.
CKTESTS_API UE_DECLARE_GAMEPLAY_TAG_EXTERN(TAG_AnimPlan_AutoTest_Net_Goal);
CKTESTS_API UE_DECLARE_GAMEPLAY_TAG_EXTERN(TAG_AnimPlan_AutoTest_Net_Cluster);
CKTESTS_API UE_DECLARE_GAMEPLAY_TAG_EXTERN(TAG_AnimPlan_AutoTest_Net_State_A);
CKTESTS_API UE_DECLARE_GAMEPLAY_TAG_EXTERN(TAG_AnimPlan_AutoTest_Net_State_B);

// --------------------------------------------------------------------------------------------------------------------

// Rotator-attribute name tag for the net subject. The rep handler and the snapshot parity gate key
// the attribute lookup by this name, so it must be registered (natively — no host-project .ini edit).
CKTESTS_API UE_DECLARE_GAMEPLAY_TAG_EXTERN(TAG_RotatorAttribute_AutoTest_Net);

// --------------------------------------------------------------------------------------------------------------------

