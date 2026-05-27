#pragma once

#include "CkActorRelay/CkActorRelay_Actor.h"

#include "CkActorRelay_TestProbe.generated.h"

// --------------------------------------------------------------------------------------------------------------------

// Test-only relay subclass for CkActorRelay net tests. Carries one NetMulticast RPC
// (server->all-clients) and one Server RPC (client->server) plus static per-world receive
// counters so the .spec.cpp tests can assert receipt.
//
// Static counter state lives in the .cpp; tests reset before-and-after and read via the
// public accessors below.
UCLASS()
class CKTESTS_API ACk_ActorRelay_TestProbe_UE : public ACk_ActorRelay_UE
{
    GENERATED_BODY()

public:
    CK_GENERATED_BODY(ACk_ActorRelay_TestProbe_UE);

public:
    // Server->all-clients. Reliable so test timing is deterministic.
    UFUNCTION(NetMulticast, Reliable)
    void
    Multicast_Ping(
        int32 InValue);

    // Client->server. Reliable so test timing is deterministic.
    UFUNCTION(Server, Reliable)
    void
    Server_Pong(
        int32 InValue);

public:
    // Test introspection - read the per-world receive counters. UWorld* keys are weak; entries
    // accumulate across the test session and are cleared by Reset_Counters.
    static auto
    Get_MulticastReceiveCount(UWorld* InWorld) -> int32;

    static auto
    Get_ServerReceiveCount(UWorld* InServerWorld) -> int32;

    // Read the last value an RPC carried for a given world. Pair with the count to check that
    // it's the value the test sent (not a leftover from a previous test).
    static auto
    Get_LastMulticastValue(UWorld* InWorld) -> int32;

    static auto
    Get_LastServerValue(UWorld* InServerWorld) -> int32;

    static auto
    Reset_Counters() -> void;
};

// --------------------------------------------------------------------------------------------------------------------
