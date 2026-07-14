#include "CkTests/Net/CkAutoTest_NetSubject_EntityCollectionEntityScript.h"

#include "CkTests/Net/CkAutoTest_NetSubject_EntityCollection.h"
#include "CkTests/CkTests_Fragment_Data.h"

#include "CkEntityCollection/CkEntityCollection_Utils.h"

#include "CkEcs/OwningActor/CkOwningActor_Utils.h"

#include "GameplayTagContainer.h"

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_NetSubject_EntityCollectionEntityScript_UE::
    Get_IsSnapshotRespawnable() const
    -> bool
{
    return true;
}

auto
    UCk_AutoTest_NetSubject_EntityCollectionEntityScript_UE::
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams)
    -> ECk_EntityScript_ConstructionFlow
{
    const auto Flow = Super::Construct(InHandle, InSpawnParams);

    // Native-registered tag (CkTests_Fragment_Data) — NOT FGameplayTag::RequestGameplayTag on a
    // string. The EntityCollection SyncReplication processor keys its client-side local-collection
    // lookup by the replicated _CollectionName; an unregistered name resolves to TAG_NOT_SET and
    // the lookup fails forever. See the EC_DIAG investigation 2026-05-28.
    const auto CollectionTag = TAG_EntityCollection_AutoTest_Net.GetTag();

    auto Params = FCk_Fragment_EntityCollection_ParamsData{CollectionTag};
    auto Collection = UCk_Utils_EntityCollection_UE::Add(InHandle, Params, ECk_Replication::Replicates);

    auto* OwningActor = UCk_Utils_OwningActor_UE::Get_EntityOwningActor(InHandle);
    if (auto* CollectionActor = Cast<ACk_AutoTest_NetSubject_EntityCollection_UE>(OwningActor))
    {
        CollectionActor->_TestCollection = Collection;
    }

    return Flow;
}

// --------------------------------------------------------------------------------------------------------------------
