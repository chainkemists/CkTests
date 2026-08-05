#pragma once

#include "CkTests/Net/CkAutoTest_NetSubject.h"

#include "CkVoiceChat/VoiceChannel/CkVoiceChannel_Fragment_Data.h"
#include "CkVoiceChat/VoiceTalker/CkVoiceTalker_Fragment_Data.h"

#include "CkAutoTest_NetSubject_VoiceChat.generated.h"

// --------------------------------------------------------------------------------------------------------------------

// Variant of ACk_AutoTest_NetSubject that bridges to the VoiceChat-flavoured entity-script
// (UCk_AutoTest_NetSubject_VoiceChatEntityScript_UE). The entity-script's Construct composes ONE
// VoiceChannel child (tag "VoiceChat.Channel.AutoTest.Net") plus a VoiceTalker on the bridged
// entity, on both worlds (symmetric composition — the control-plane rep handler returns NotReady
// until TryGet by channel name resolves).
//
// `_TestChannel` / `_TestTalker` are transient, local-only fields — NOT replicated. Each world's
// entity-script independently populates its own world's actor. The control plane replicates via
// the FCk_RepData_VoiceChat container on the bridged entity.

UCLASS()
class CKTESTS_API ACk_AutoTest_NetSubject_VoiceChat_UE : public ACk_AutoTest_NetSubject
{
    GENERATED_BODY()

public:
    ACk_AutoTest_NetSubject_VoiceChat_UE();

public:
    UPROPERTY(Transient, BlueprintReadOnly, Category = "Ck|AutoTest")
    FCk_Handle_VoiceChannel _TestChannel;

    UPROPERTY(Transient, BlueprintReadOnly, Category = "Ck|AutoTest")
    FCk_Handle_VoiceTalker _TestTalker;
};

// --------------------------------------------------------------------------------------------------------------------
