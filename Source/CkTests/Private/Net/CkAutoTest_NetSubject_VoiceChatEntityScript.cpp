#include "CkTests/Net/CkAutoTest_NetSubject_VoiceChatEntityScript.h"

#include "CkTests/Net/CkAutoTest_NetSubject_VoiceChat.h"

#include "CkEcs/OwningActor/CkOwningActor_Utils.h"

#include "CkVoiceChat/VoiceChannel/CkVoiceChannel_Utils.h"
#include "CkVoiceChat/VoiceTalker/CkVoiceTalker_Utils.h"

#include <NativeGameplayTags.h>

// --------------------------------------------------------------------------------------------------------------------

// Test-only child of the C++-registered "VoiceChat.Channel" category root.
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_VoiceChat_Channel_AutoTest_Net, TEXT("VoiceChat.Channel.AutoTest.Net"));

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_NetSubject_VoiceChatEntityScript_UE::
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams)
    -> ECk_EntityScript_ConstructionFlow
{
    // Super::Construct sets up the WithActor bridge (OwningActor + Transform + Label) and must
    // run first — the control-plane container needs an OwningActor in the chain to bind its
    // replication driver to.
    const auto Flow = Super::Construct(InHandle, InSpawnParams);

    auto Channel = UCk_Utils_VoiceChannel_UE::Add(InHandle,
        FCk_VoiceChannel_Spec{TAG_VoiceChat_Channel_AutoTest_Net});
    auto Talker = UCk_Utils_VoiceTalker_UE::Add(InHandle, FCk_VoiceTalker_Spec{});

    if (auto* Subject = Cast<ACk_AutoTest_NetSubject_VoiceChat_UE>(
            UCk_Utils_OwningActor_UE::Get_EntityOwningActor(InHandle)))
    {
        Subject->_TestChannel = Channel;
        Subject->_TestTalker = Talker;
    }

    return Flow;
}

// --------------------------------------------------------------------------------------------------------------------
