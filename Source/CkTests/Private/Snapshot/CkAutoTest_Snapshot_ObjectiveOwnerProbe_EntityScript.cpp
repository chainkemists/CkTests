#include "CkTests/Snapshot/CkAutoTest_Snapshot_ObjectiveOwnerProbe_EntityScript.h"

#include "CkCore/Enums/CkEnums.h"

#include "CkObjective/ObjectiveOwner/CkObjectiveOwner_Utils.h"

#include <NativeGameplayTags.h>

// --------------------------------------------------------------------------------------------------------------------

UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_Test_Objective_ProbeLeafA, "Test.Objective.ProbeLeafA");
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_Test_Objective_ProbeLeafB, "Test.Objective.ProbeLeafB");

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_Snapshot_ObjectiveProbe_Leaf_EntityScript_UE::
    DoSet_ObjectiveName(
        const FGameplayTag& InName)
    -> void
{
    auto* NameProperty = CastField<FStructProperty>(GetClass()->FindPropertyByName(TEXT("_ObjectiveName")));

    CK_ENSURE_IF_NOT(NameProperty != nullptr,
        TEXT("UCk_Objective_EntityScript no longer reflects [_ObjectiveName] — the objective probe fixture "
             "would compose with an empty name and its GameplayLabel would collide"))
    { return; }

    *NameProperty->ContainerPtrToValuePtr<FGameplayTag>(this) = InName;
}

// --------------------------------------------------------------------------------------------------------------------

UCk_AutoTest_Snapshot_ObjectiveProbe_LeafA_EntityScript_UE::
    UCk_AutoTest_Snapshot_ObjectiveProbe_LeafA_EntityScript_UE()
{
    _Replication = ECk_Replication::DoesNotReplicate;
    DoSet_ObjectiveName(TAG_Test_Objective_ProbeLeafA);
}

UCk_AutoTest_Snapshot_ObjectiveProbe_LeafB_EntityScript_UE::
    UCk_AutoTest_Snapshot_ObjectiveProbe_LeafB_EntityScript_UE()
{
    _Replication = ECk_Replication::DoesNotReplicate;
    DoSet_ObjectiveName(TAG_Test_Objective_ProbeLeafB);
}

// --------------------------------------------------------------------------------------------------------------------

UCk_AutoTest_Snapshot_ObjectiveOwnerProbe_EntityScript_UE::
    UCk_AutoTest_Snapshot_ObjectiveOwnerProbe_EntityScript_UE()
{
    _Replication = ECk_Replication::DoesNotReplicate;
    _InstancingPolicy = ECk_EntityScript_InstancingPolicy::InstancedPerEntity;
}

auto
    UCk_AutoTest_Snapshot_ObjectiveOwnerProbe_EntityScript_UE::
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams)
    -> ECk_EntityScript_ConstructionFlow
{
    const auto Ret = Super::Construct(InHandle, InSpawnParams);

    // Deliberately ungated on the load: this replaying during the rebuild is what the gate measures.
    const auto Defaults = TArray<TSubclassOf<UCk_Objective_EntityScript>>
    {
        UCk_AutoTest_Snapshot_ObjectiveProbe_LeafA_EntityScript_UE::StaticClass(),
        UCk_AutoTest_Snapshot_ObjectiveProbe_LeafB_EntityScript_UE::StaticClass()
    };

    UCk_Utils_ObjectiveOwner_UE::Add(InHandle, FCk_ObjectiveOwner_ParamsData{Defaults});

    return Ret;
}

auto
    UCk_AutoTest_Snapshot_ObjectiveOwnerProbe_EntityScript_UE::
    Get_IsSnapshotRespawnable() const
    -> bool
{
    return true;
}
