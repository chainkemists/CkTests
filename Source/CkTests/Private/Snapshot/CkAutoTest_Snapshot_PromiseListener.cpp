#include "CkTests/Snapshot/CkAutoTest_Snapshot_PromiseListener.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"

#include "CkSnapshot/CkSnapshot_Utils.h"
#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include <Engine/GameInstance.h>
#include <Engine/World.h>

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

    _AccountingClosedAtFire = InReport.Get_IsAccountingClosed();
    _ConvergenceUnmetAtFire = InReport.Get_ConvergenceUnmet().Num();

    if (auto* World = UCk_Utils_EntityLifetime_UE::Get_WorldForEntity(InHandle);
        ck::IsValid(World))
    {
        if (auto* GameInstance = World->GetGameInstance();
            GameInstance != nullptr)
        {
            if (auto* Subsystem = GameInstance->GetSubsystem<UCk_Snapshot_Subsystem_UE>();
                Subsystem != nullptr)
            {
                _ReadyToResumeAtFire = Subsystem->Get_IsReadyToResume();
                _LoadInProgressAtFire = Subsystem->Get_IsLoadInProgress();
            }
        }
    }

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
