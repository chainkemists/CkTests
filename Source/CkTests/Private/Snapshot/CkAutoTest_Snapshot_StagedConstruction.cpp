#include "CkTests/Snapshot/CkAutoTest_Snapshot_StagedConstruction.h"

#include "CkAttribute/FloatAttribute/CkFloatAttribute_Utils.h"
#include "CkAttribute/IntegerAttribute/CkIntegerAttribute_Utils.h"

#include "CkCore/Ensure/CkEnsure.h"
#include "CkCore/Enums/CkEnums.h"

#include "CkEcs/EntityScript/CkEntityScript_Fragment.h"
#include "CkEcs/EntityScript/CkEntityScript_Utils.h"
#include "CkEcs/Scheduler/CkProcessorRegistration.h"

#include "CkLabel/CkLabel_Utils.h"

#include <NativeGameplayTags.h>

// --------------------------------------------------------------------------------------------------------------------

CK_REGISTER_PROCESSOR(ck::FProcessor_AutoTest_StagedConstruction_Setup);

// --------------------------------------------------------------------------------------------------------------------

namespace ck_autotest_staged_construction
{
    UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_StagedConstruction_Slot0, TEXT("Ck.AutoTest.StagedConstruction.Slot0"));
    UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_StagedConstruction_Slot1, TEXT("Ck.AutoTest.StagedConstruction.Slot1"));
    UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_StagedConstruction_Slot2, TEXT("Ck.AutoTest.StagedConstruction.Slot2"));
    UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_StagedConstruction_Value, TEXT("Ck.AutoTest.StagedConstruction.Value"));
    UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_StagedConstruction_Meter, TEXT("Ck.AutoTest.StagedConstruction.Meter"));

    auto
        Get_SlotLabel(
            int32 InSlotIndex)
        -> FGameplayTag
    {
        switch (InSlotIndex)
        {
            case 0: return TAG_StagedConstruction_Slot0;
            case 1: return TAG_StagedConstruction_Slot1;
            case 2: return TAG_StagedConstruction_Slot2;
            default: return FGameplayTag::EmptyTag;
        }
    }

    auto
        Get_ValueAttributeName()
        -> FGameplayTag
    {
        return TAG_StagedConstruction_Value;
    }

    auto
        Get_MeterAttributeName()
        -> FGameplayTag
    {
        return TAG_StagedConstruction_Meter;
    }
}

// --------------------------------------------------------------------------------------------------------------------

namespace ck
{
    auto
        FProcessor_AutoTest_StagedConstruction_Setup::
        ForEachEntity(
            TimeType InDeltaT,
            HandleType InHandle)
        -> void
    {
        InHandle.Remove<MarkedDirtyBy>();

        auto* Script = Cast<UCk_AutoTest_Snapshot_StagedChild_EntityScript_UE>(
            InHandle.Get<FFragment_EntityScript_Current>().Get_Script().Get());

        const auto ScriptIsValid = ck::IsValid(Script, ck::IsValid_Policy_NullptrOnly{});
        CK_ENSURE_IF_NOT(ScriptIsValid,
            TEXT("StagedConstruction NeedsSetup tag on entity [{}] whose script is not a StagedChild"), InHandle)
        {}
        if (NOT ScriptIsValid)
        { return; }

        Script->FinishStagedConstruction();
    }
}

// --------------------------------------------------------------------------------------------------------------------

UCk_AutoTest_Snapshot_StagedChild_EntityScript_UE::
    UCk_AutoTest_Snapshot_StagedChild_EntityScript_UE()
{
    _Replication = ECk_Replication::DoesNotReplicate;
    _InstancingPolicy = ECk_EntityScript_InstancingPolicy::InstancedPerEntity;
}

auto
    UCk_AutoTest_Snapshot_StagedChild_EntityScript_UE::
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams)
    -> ECk_EntityScript_ConstructionFlow
{
    constexpr auto BaseValue = 1.0f;
    auto Params = FCk_Fragment_FloatAttribute_ParamsData{
        ck_autotest_staged_construction::Get_ValueAttributeName(), BaseValue};
    UCk_Utils_FloatAttribute_UE::Add(InHandle, Params, ECk_Replication::DoesNotReplicate);

    // The equal-label sibling pair: an integer meter whose refill is composed as a FLOAT attribute sibling
    // labeled with the SAME name (IntegerAttribute::Add labels the refill child by RefillAttributeName). The
    // save then holds two ConstructSpawned rows under one (owner, label) adopt key — the loader must bind them
    // apart by excluding already-claimed children, or the refill's float payloads land on the integer meter
    // and drop as forever-NotReady.
    constexpr auto MeterBase = 3;
    constexpr auto MeterFillRate = -0.2f;
    auto MeterParams = FCk_Fragment_IntegerAttribute_ParamsData{
        ck_autotest_staged_construction::Get_MeterAttributeName(), MeterBase};
    MeterParams.Set_EnableRefill(true);
    MeterParams.Set_RefillParams(
        FCk_Fragment_IntegerAttributeRefill_ParamsData{
            ck_autotest_staged_construction::Get_MeterAttributeName(), MeterFillRate}
        .Set_RefillBehavior(ECk_Attribute_Refill_Policy::Variable)
        .Set_StartingState(ECk_Attribute_RefillState::Paused));
    UCk_Utils_IntegerAttribute_UE::Add(InHandle, MeterParams, ECk_Replication::DoesNotReplicate);

    InHandle.Add<ck::FTag_AutoTest_StagedConstruction_NeedsSetup>();
    return ECk_EntityScript_ConstructionFlow::Continue;
}

auto
    UCk_AutoTest_Snapshot_StagedChild_EntityScript_UE::
    FinishStagedConstruction()
    -> void
{
    DoFinishConstruction();
}

// --------------------------------------------------------------------------------------------------------------------

UCk_AutoTest_Snapshot_StagedParent_EntityScript_UE::
    UCk_AutoTest_Snapshot_StagedParent_EntityScript_UE()
{
    _Replication = ECk_Replication::DoesNotReplicate;
    _InstancingPolicy = ECk_EntityScript_InstancingPolicy::InstancedPerEntity;
}

auto
    UCk_AutoTest_Snapshot_StagedParent_EntityScript_UE::
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams)
    -> ECk_EntityScript_ConstructionFlow
{
    _PendingSlots.Reset();
    _RemainingChildren = ck_autotest_staged_construction::NumSlots;

    for (auto SlotIndex = 0; SlotIndex < ck_autotest_staged_construction::NumSlots; ++SlotIndex)
    {
        auto Pending = UCk_Utils_EntityScript_UE::Request_SpawnEntity(
            InHandle, UCk_AutoTest_Snapshot_StagedChild_EntityScript_UE::StaticClass(), FInstancedStruct{}, {});

        _PendingSlots.Add(Pending.Get_EntityUnderConstruction(), SlotIndex);

        auto Delegate = FCk_Delegate_EntityScript_Constructed{};
        Delegate.BindDynamic(this, &UCk_AutoTest_Snapshot_StagedParent_EntityScript_UE::OnChildConstructed);
        UCk_Utils_PendingEntityScript_UE::Promise_OnConstructed(Pending, Delegate);
    }

    return ECk_EntityScript_ConstructionFlow::Continue;
}

auto
    UCk_AutoTest_Snapshot_StagedParent_EntityScript_UE::
    Get_IsSnapshotRespawnable() const
    -> bool
{
    return true;
}

auto
    UCk_AutoTest_Snapshot_StagedParent_EntityScript_UE::
    OnChildConstructed(
        FCk_Handle_EntityScript InEntityScriptHandle)
    -> void
{
    auto ChildHandle = FCk_Handle{InEntityScriptHandle};

    const auto* SlotIndex = _PendingSlots.Find(ChildHandle);
    const auto SlotIsKnown = SlotIndex != nullptr;
    CK_ENSURE_IF_NOT(SlotIsKnown,
        TEXT("StagedParent OnChildConstructed fired for [{}] which is not a pending child"), ChildHandle)
    {}
    if (NOT SlotIsKnown)
    { return; }

    // Stamped ON COMPLETION, not at request time, on purpose — this is the racy shape the loader must survive:
    // the adopt key does not exist until a gated processor lets the child finish constructing.
    UCk_Utils_GameplayLabel_UE::Add(ChildHandle, ck_autotest_staged_construction::Get_SlotLabel(*SlotIndex));
    _PendingSlots.Remove(ChildHandle);

    --_RemainingChildren;
    if (_RemainingChildren == 0)
    { DoFinishConstruction(); }
}
