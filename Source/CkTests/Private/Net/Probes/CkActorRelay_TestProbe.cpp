#include "CkTests/Net/Probes/CkActorRelay_TestProbe.h"

#include "Engine/World.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_actorrelay_testprobe_storage
{
    // Per-world receive counters. Multi-PIE is single-threaded so plain TMap is safe.
    // Keys are TWeakObjectPtr because PIE tears worlds down between test runs.
    static TMap<TWeakObjectPtr<UWorld>, int32> sg_MulticastReceiveCount_ByWorld;
    static TMap<TWeakObjectPtr<UWorld>, int32> sg_ServerReceiveCount_ByWorld;
    static TMap<TWeakObjectPtr<UWorld>, int32> sg_LastMulticastValue_ByWorld;
    static TMap<TWeakObjectPtr<UWorld>, int32> sg_LastServerValue_ByWorld;
}

// --------------------------------------------------------------------------------------------------------------------

auto
    ACk_ActorRelay_TestProbe_UE::
    Multicast_Ping_Implementation(
        int32 InValue)
    -> void
{
    auto* World = GetWorld();
    if (World == nullptr)
    { return; }

    auto& Count = ck_actorrelay_testprobe_storage::sg_MulticastReceiveCount_ByWorld.FindOrAdd(World, 0);
    ++Count;
    ck_actorrelay_testprobe_storage::sg_LastMulticastValue_ByWorld.FindOrAdd(World, 0) = InValue;
}

auto
    ACk_ActorRelay_TestProbe_UE::
    Server_Pong_Implementation(
        int32 InValue)
    -> void
{
    auto* World = GetWorld();
    if (World == nullptr)
    { return; }

    auto& Count = ck_actorrelay_testprobe_storage::sg_ServerReceiveCount_ByWorld.FindOrAdd(World, 0);
    ++Count;
    ck_actorrelay_testprobe_storage::sg_LastServerValue_ByWorld.FindOrAdd(World, 0) = InValue;
}

auto
    ACk_ActorRelay_TestProbe_UE::
    Get_MulticastReceiveCount(
        UWorld* InWorld)
    -> int32
{
    if (const auto* Found = ck_actorrelay_testprobe_storage::sg_MulticastReceiveCount_ByWorld.Find(InWorld))
    { return *Found; }
    return 0;
}

auto
    ACk_ActorRelay_TestProbe_UE::
    Get_ServerReceiveCount(
        UWorld* InServerWorld)
    -> int32
{
    if (const auto* Found = ck_actorrelay_testprobe_storage::sg_ServerReceiveCount_ByWorld.Find(InServerWorld))
    { return *Found; }
    return 0;
}

auto
    ACk_ActorRelay_TestProbe_UE::
    Get_LastMulticastValue(
        UWorld* InWorld)
    -> int32
{
    if (const auto* Found = ck_actorrelay_testprobe_storage::sg_LastMulticastValue_ByWorld.Find(InWorld))
    { return *Found; }
    return 0;
}

auto
    ACk_ActorRelay_TestProbe_UE::
    Get_LastServerValue(
        UWorld* InServerWorld)
    -> int32
{
    if (const auto* Found = ck_actorrelay_testprobe_storage::sg_LastServerValue_ByWorld.Find(InServerWorld))
    { return *Found; }
    return 0;
}

auto
    ACk_ActorRelay_TestProbe_UE::
    Reset_Counters()
    -> void
{
    ck_actorrelay_testprobe_storage::sg_MulticastReceiveCount_ByWorld.Reset();
    ck_actorrelay_testprobe_storage::sg_ServerReceiveCount_ByWorld.Reset();
    ck_actorrelay_testprobe_storage::sg_LastMulticastValue_ByWorld.Reset();
    ck_actorrelay_testprobe_storage::sg_LastServerValue_ByWorld.Reset();
}

// --------------------------------------------------------------------------------------------------------------------
