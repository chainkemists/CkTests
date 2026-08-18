#include "CkTests/Snapshot/CkAutoTest_Snapshot_PromiseListener.h"

#include "CkSnapshot/CkSnapshot_Utils.h"

// --------------------------------------------------------------------------------------------------------------------

void
    UCk_AutoTest_Snapshot_PromiseListener_UE::
    OnPreLoad(
        FCk_Handle InHandle)
{
    if (_ArmCount > 0)
    { return; }

    ++_ArmCount;

    auto Delegate = FCk_Delegate_Snapshot_OnLoadComplete{};
    Delegate.BindUFunction(this, TEXT("OnLoadComplete"));

    UCk_Utils_Snapshot_UE::Promise_OnLoadComplete(InHandle, Delegate);
}

// --------------------------------------------------------------------------------------------------------------------

void
    UCk_AutoTest_Snapshot_PromiseListener_UE::
    OnLoadComplete(
        FCk_Handle InHandle,
        FCk_Snapshot_LoadReport InReport)
{
    ++_FireCount;
    _LastResult = InReport.Get_Result();
    _LastHandleWasValid = ck::IsValid(InHandle);

    if (NOT _ReArmInsideCallback)
    { return; }

    auto ReArmDelegate = FCk_Delegate_Snapshot_OnLoadComplete{};
    ReArmDelegate.BindUFunction(this, TEXT("OnReArmedFire"));

    const auto ReArm = UCk_Utils_Snapshot_UE::Promise_OnLoadComplete(InHandle, ReArmDelegate);

    _ReArmReturnedNoLoadInProgress = ReArm == ECk_Snapshot_PromiseResult::NoLoadInProgress;
}

// --------------------------------------------------------------------------------------------------------------------

void
    UCk_AutoTest_Snapshot_PromiseListener_UE::
    OnReArmedFire(
        FCk_Handle /*InHandle*/,
        FCk_Snapshot_LoadReport InReport)
{
    ++_ReArmFireCount;
    _ReArmResult = InReport.Get_Result();
}

// --------------------------------------------------------------------------------------------------------------------
