#include "CkTests/Net/Probes/CkActorRelay_TestProbeGroup_Subsystem.h"

#include "CkTests/Net/Probes/CkActorRelay_TestProbe.h"

#include "NativeGameplayTags.h"

// --------------------------------------------------------------------------------------------------------------------

UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_CkTests_ActorRelay_TestProbeGroup, "CkTests.ActorRelay.TestProbeGroup");

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_ActorRelay_TestProbeGroup_Subsystem_UE::
    Get_GroupTag() const
    -> FGameplayTag
{
    return TAG_CkTests_ActorRelay_TestProbeGroup;
}

auto
    UCk_ActorRelay_TestProbeGroup_Subsystem_UE::
    Get_ActorClass() const
    -> TSubclassOf<ACk_ActorRelay_UE>
{
    return ACk_ActorRelay_TestProbe_UE::StaticClass();
}

auto
    UCk_ActorRelay_TestProbeGroup_Subsystem_UE::
    Get_OwnershipPolicy() const
    -> ECk_ActorRelay_OwnershipPolicy
{
    return ECk_ActorRelay_OwnershipPolicy::PlayerOwned;
}

auto
    UCk_ActorRelay_TestProbeGroup_Subsystem_UE::
    Get_ChannelCount() const
    -> int32
{
    return 1;
}

auto
    UCk_ActorRelay_TestProbeGroup_Subsystem_UE::
    Get_SelectionAlgorithm() const
    -> ECk_ActorRelay_SelectionAlgorithm
{
    return ECk_ActorRelay_SelectionAlgorithm::RoundRobin;
}

// --------------------------------------------------------------------------------------------------------------------
