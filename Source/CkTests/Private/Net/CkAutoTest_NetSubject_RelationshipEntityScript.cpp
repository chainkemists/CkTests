#include "CkTests/Net/CkAutoTest_NetSubject_RelationshipEntityScript.h"

#include "CkRelationship/Player/CkPlayer_Utils.h"
#include "CkRelationship/Team/CkTeam_Utils.h"

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_NetSubject_RelationshipEntityScript_UE::
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams)
    -> ECk_EntityScript_ConstructionFlow
{
    const auto Flow = Super::Construct(InHandle, InSpawnParams);

    // Player ID + Team ID both start at Unassigned. The tests mutate them server-side via
    // Request_SetPlayerID / Request_SetTeamID and assert the new value lands on the client
    // via the FCk_RepData_Player / FCk_RepData_Team rep handlers.
    UCk_Utils_Player_UE::Add(InHandle);
    UCk_Utils_Team_UE::Add(InHandle);

    return Flow;
}

// --------------------------------------------------------------------------------------------------------------------
