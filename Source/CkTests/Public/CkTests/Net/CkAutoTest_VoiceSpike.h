#pragma once

#include <GameFramework/Actor.h>

#include "CkAutoTest_VoiceSpike.generated.h"

// --------------------------------------------------------------------------------------------------------------------
//
// THROWAWAY spike vehicles for the CkVoiceChat P0 transport spike (delete with the campaign's
// P0 artifacts): sustained-rate Unreliable unicast Client-direction RPCs under the fork's Iris
// stack. The channel actor copies the wire-relevant shape of an ActorRelay per-player channel
// exactly — bReplicates + bAlwaysRelevant (CkActorRelay_Actor.cpp:23-24) with Owner set to the
// target player's PlayerState (CkActorRelay_GroupSubsystem.cpp:452) — without the group-subsystem
// registration machinery, which adds no netcode.
//
// Server side drives sends from Tick (authority-gated) off a budget configured by the spec;
// client side tallies arrivals in the RPC bodies. The pressure actor churns every byte of a
// replicated payload each tick so delta serialization cannot shrink it, saturating the
// connection with competing state data.
//
// --------------------------------------------------------------------------------------------------------------------

UCLASS(NotBlueprintable)
class CKTESTS_API ACk_AutoTest_VoiceSpikeChannel_UE : public AActor
{
    GENERATED_BODY()

public:
    ACk_AutoTest_VoiceSpikeChannel_UE();

public:
    auto
    Tick(
        float InDeltaSeconds) -> void override;

public:
    UFUNCTION(Client, Unreliable)
    void
    Client_ReceiveVoiceBundle(
        int32 InSeq,
        const TArray<uint8>& InBytes);

    UFUNCTION(Client, Reliable)
    void
    Client_ReceiveControl(
        int32 InSeq);

public:
    static auto
    Find(
        UWorld* InWorld) -> ACk_AutoTest_VoiceSpikeChannel_UE*;

public:
    // server-side drive config (set via RunOnServer; consumed by the authority Tick)
    int32 _BundlesPerTick = 0;
    int32 _BundleBytes = 190;
    int32 _RemainingBundleBudget = 0;
    int32 _ControlEveryNTicks = 0;

    // server-side tallies
    int32 _NextSeq = 0;
    int32 _SentBundles = 0;
    int32 _SentControls = 0;
    int32 _TicksSeen = 0;

    // client-side tallies (mutated only by the RPC bodies, on the receiving world's instance)
    int32 _ReceivedBundles = 0;
    int32 _ReceivedControls = 0;
    int32 _HighestSeq = -1;
    int32 _OutOfOrderArrivals = 0;
    int64 _ReceivedPayloadBytes = 0;
};

// --------------------------------------------------------------------------------------------------------------------

UCLASS(NotBlueprintable)
class CKTESTS_API ACk_AutoTest_VoiceSpikePressure_UE : public AActor
{
    GENERATED_BODY()

public:
    ACk_AutoTest_VoiceSpikePressure_UE();

public:
    auto
    Tick(
        float InDeltaSeconds) -> void override;

    auto
    GetLifetimeReplicatedProps(
        TArray<FLifetimeProperty>& OutLifetimeProps) const -> void override;

public:
    static auto
    Find(
        UWorld* InWorld) -> ACk_AutoTest_VoiceSpikePressure_UE*;

public:
    // server-side: when > 0, every byte of _Payload is rewritten each tick
    int32 _ChurnBytesPerTick = 0;
    int32 _ChurnCounter = 0;

private:
    UPROPERTY(Replicated)
    TArray<uint8> _Payload;
};

// --------------------------------------------------------------------------------------------------------------------
