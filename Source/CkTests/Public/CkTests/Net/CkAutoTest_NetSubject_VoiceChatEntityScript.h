#pragma once

#include "CoreMinimal.h"

#include "CkEcsExt/EntityScript/CkEntityScript_WithActor.h"

#include "CkAutoTest_NetSubject_VoiceChatEntityScript.generated.h"

// --------------------------------------------------------------------------------------------------------------------
//
// Entity-script for the VoiceChat net subject. Construct composes a VoiceChannel child (tag
// "VoiceChat.Channel.AutoTest.Net") and a VoiceTalker on the bridged entity. Runs on both server
// and client via the entity-script lifecycle's replication path — the symmetric composition the
// control-plane rep handler requires.
//
// --------------------------------------------------------------------------------------------------------------------

UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_NetSubject_VoiceChatEntityScript_UE : public UCk_EntityScript_WithActor_UE
{
    GENERATED_BODY()

public:
    virtual auto
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams) -> ECk_EntityScript_ConstructionFlow override;
};

// --------------------------------------------------------------------------------------------------------------------
