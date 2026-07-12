#include "CkTests/Net/CkAutoTest_NetSubject_M2aProbe.h"

// --------------------------------------------------------------------------------------------------------------------

std::atomic<int32> UCk_AutoTest_NetSubject_M2aProbe_EntityScript_UE::GEndPlayCount{0};

auto
    UCk_AutoTest_NetSubject_M2aProbe_EntityScript_UE::
    EndPlay()
    -> void
{
    GEndPlayCount.fetch_add(1, std::memory_order_relaxed);
    Super::EndPlay();
}

auto
    UCk_AutoTest_NetSubject_M2aProbe_EntityScript_UE::
    Get_IsSnapshotRespawnable() const
    -> bool
{
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

ACk_AutoTest_NetSubject_M2aProbe::
    ACk_AutoTest_NetSubject_M2aProbe()
{
    _EntityScriptClass = UCk_AutoTest_NetSubject_M2aProbe_EntityScript_UE::StaticClass();
}
