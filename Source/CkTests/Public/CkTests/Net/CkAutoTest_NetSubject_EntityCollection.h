#pragma once

#include "CkTests/Net/CkAutoTest_NetSubject.h"

#include "CkEntityCollection/CkEntityCollection_Fragment_Data.h"

#include "CkAutoTest_NetSubject_EntityCollection.generated.h"

// --------------------------------------------------------------------------------------------------------------------

// Variant of ACk_AutoTest_NetSubject that bridges to the EntityCollection-flavoured entity-script
// (UCk_AutoTest_NetSubject_EntityCollectionEntityScript_UE). The entity-script's Construct creates
// a `Replicates` empty collection on the subject's own entity on each world (symmetric setup) and
// writes the resulting handle to `_TestCollection`. AS net-test bodies cast the SubjectActor to
// this class and read `_TestCollection` to operate on the collection without depending on a
// `TryGet_Entity_EntityCollection_InOwnershipChain` helper (the by-tag helper exists but the
// stash matches the CkInventory pattern, which is already validated).
//
// `_TestCollection` is a transient, local-only field — NOT replicated. The collection's contents
// (entries) replicate via the FCk_RepData_EntityCollections rep handler.

UCLASS()
class CKTESTS_API ACk_AutoTest_NetSubject_EntityCollection_UE : public ACk_AutoTest_NetSubject
{
    GENERATED_BODY()

public:
    ACk_AutoTest_NetSubject_EntityCollection_UE();

public:
    UPROPERTY(Transient, BlueprintReadOnly, Category = "Ck|AutoTest")
    FCk_Handle_EntityCollection _TestCollection;
};

// --------------------------------------------------------------------------------------------------------------------
