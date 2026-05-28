#include "CkTests/Net/CkAutoTest_NetSubject_EntityCollectionEntityScript.h"

#include "CkTests/Net/CkAutoTest_NetSubject_EntityCollection.h"

#include "CkEntityCollection/CkEntityCollection_Utils.h"

#include "CkEcs/OwningActor/CkOwningActor_Utils.h"

#include "GameplayTagContainer.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck::auto_test::netsubject_entitycollection
{
    constexpr auto CollectionTagName = TEXT("EntityCollection.AutoTest_Net");
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_NetSubject_EntityCollectionEntityScript_UE::
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams)
    -> ECk_EntityScript_ConstructionFlow
{
    const auto Flow = Super::Construct(InHandle, InSpawnParams);

    using namespace ck::auto_test::netsubject_entitycollection;

    const auto CollectionTag = FGameplayTag::RequestGameplayTag(FName{CollectionTagName});

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
