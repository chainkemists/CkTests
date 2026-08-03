#include "CkTests/Net/CkAutoTest_VoiceSpike.h"

#include <EngineUtils.h>
#include <Net/UnrealNetwork.h>
#include <Net/Core/PushModel/PushModel.h>

// --------------------------------------------------------------------------------------------------------------------

ACk_AutoTest_VoiceSpikeChannel_UE::ACk_AutoTest_VoiceSpikeChannel_UE()
{
    bReplicates = true;
    bAlwaysRelevant = true;

    PrimaryActorTick.bCanEverTick = true;
    PrimaryActorTick.bStartWithTickEnabled = true;
}

auto
    ACk_AutoTest_VoiceSpikeChannel_UE::
    Tick(
        float InDeltaSeconds)
    -> void
{
    Super::Tick(InDeltaSeconds);

    if (GetLocalRole() != ROLE_Authority)
    { return; }

    ++_TicksSeen;

    if (_ControlEveryNTicks > 0 && (_TicksSeen % _ControlEveryNTicks) == 0)
    {
        Client_ReceiveControl(_SentControls);
        ++_SentControls;
    }

    if (_BundlesPerTick <= 0 || _RemainingBundleBudget <= 0)
    { return; }

    const auto BundlesThisTick = FMath::Min(_BundlesPerTick, _RemainingBundleBudget);

    for (auto Bundle = 0; Bundle < BundlesThisTick; ++Bundle)
    {
        auto Payload = TArray<uint8>{};
        Payload.SetNumUninitialized(_BundleBytes);
        for (auto Idx = 0; Idx < Payload.Num(); ++Idx)
        {
            Payload[Idx] = static_cast<uint8>((_NextSeq * 31 + Idx) & 0xFF);
        }

        Client_ReceiveVoiceBundle(_NextSeq, Payload);

        ++_NextSeq;
        ++_SentBundles;
        --_RemainingBundleBudget;
    }
}

void
    ACk_AutoTest_VoiceSpikeChannel_UE::
    Client_ReceiveVoiceBundle_Implementation(
        int32 InSeq,
        const TArray<uint8>& InBytes)
{
    ++_ReceivedBundles;
    _ReceivedPayloadBytes += InBytes.Num();

    if (InSeq < _HighestSeq)
    { ++_OutOfOrderArrivals; }
    else
    { _HighestSeq = InSeq; }
}

void
    ACk_AutoTest_VoiceSpikeChannel_UE::
    Client_ReceiveControl_Implementation(
        int32 InSeq)
{
    ++_ReceivedControls;
}

auto
    ACk_AutoTest_VoiceSpikeChannel_UE::
    Find(
        UWorld* InWorld)
    -> ACk_AutoTest_VoiceSpikeChannel_UE*
{
    if (InWorld == nullptr)
    { return nullptr; }

    for (auto It = TActorIterator<ACk_AutoTest_VoiceSpikeChannel_UE>{InWorld}; It; ++It)
    { return *It; }

    return nullptr;
}

// --------------------------------------------------------------------------------------------------------------------

ACk_AutoTest_VoiceSpikePressure_UE::ACk_AutoTest_VoiceSpikePressure_UE()
{
    bReplicates = true;
    bAlwaysRelevant = true;

    PrimaryActorTick.bCanEverTick = true;
    PrimaryActorTick.bStartWithTickEnabled = true;
}

auto
    ACk_AutoTest_VoiceSpikePressure_UE::
    Tick(
        float InDeltaSeconds)
    -> void
{
    Super::Tick(InDeltaSeconds);

    if (GetLocalRole() != ROLE_Authority)
    { return; }

    if (_ChurnBytesPerTick <= 0)
    { return; }

    ++_ChurnCounter;

    _Payload.SetNumUninitialized(_ChurnBytesPerTick);
    for (auto Idx = 0; Idx < _Payload.Num(); ++Idx)
    {
        _Payload[Idx] = static_cast<uint8>((_ChurnCounter + Idx) & 0xFF);
    }

    MARK_PROPERTY_DIRTY_FROM_NAME(ACk_AutoTest_VoiceSpikePressure_UE, _Payload, this);
}

auto
    ACk_AutoTest_VoiceSpikePressure_UE::
    GetLifetimeReplicatedProps(
        TArray<FLifetimeProperty>& OutLifetimeProps) const
    -> void
{
    Super::GetLifetimeReplicatedProps(OutLifetimeProps);

    auto Params = FDoRepLifetimeParams{};
    Params.bIsPushBased = true;

    DOREPLIFETIME_WITH_PARAMS_FAST(ACk_AutoTest_VoiceSpikePressure_UE, _Payload, Params);
}

auto
    ACk_AutoTest_VoiceSpikePressure_UE::
    Find(
        UWorld* InWorld)
    -> ACk_AutoTest_VoiceSpikePressure_UE*
{
    if (InWorld == nullptr)
    { return nullptr; }

    for (auto It = TActorIterator<ACk_AutoTest_VoiceSpikePressure_UE>{InWorld}; It; ++It)
    { return *It; }

    return nullptr;
}

// --------------------------------------------------------------------------------------------------------------------
