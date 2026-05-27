#pragma once

#include "CkActorRelay/CkActorRelay_GroupSubsystem.h"

#include "CkActorRelay_TestProbeGroup_Subsystem.generated.h"

// --------------------------------------------------------------------------------------------------------------------

// Group subsystem for ACk_ActorRelay_TestProbe_UE. PlayerOwned - one channel per player, plus
// a server-side counterpart. One subsystem covers both test directions (server multicast through
// a player-owned channel, plus client->server Server_* RPCs on the owning client's channel).
UCLASS()
class CKTESTS_API UCk_ActorRelay_TestProbeGroup_Subsystem_UE : public UCk_ActorRelay_Group_Subsystem_Base_UE
{
    GENERATED_BODY()

public:
    CK_GENERATED_BODY(UCk_ActorRelay_TestProbeGroup_Subsystem_UE);

public:
    auto
    Get_GroupTag() const -> FGameplayTag override;

    auto
    Get_ActorClass() const -> TSubclassOf<ACk_ActorRelay_UE> override;

    auto
    Get_OwnershipPolicy() const -> ECk_ActorRelay_OwnershipPolicy override;

    auto
    Get_ChannelCount() const -> int32 override;

    auto
    Get_SelectionAlgorithm() const -> ECk_ActorRelay_SelectionAlgorithm override;
};

// --------------------------------------------------------------------------------------------------------------------
