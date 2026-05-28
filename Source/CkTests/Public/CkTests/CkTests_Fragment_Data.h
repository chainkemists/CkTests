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

