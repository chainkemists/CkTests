// Language=angelscript
//
// CK RELATIONSHIP — AUTOMATION TEST: Assign with the current ID is a no-op
// Assigning the team ID the entity already has must early-return without
// re-assigning, and the returned handle must still resolve to that team.
// (Regression guard for the Assign restructure that removed the double-cast:
// the same-ID early-return path now returns the cached typed handle.)

class UCk_AutoTest_Relationship_Team_AssignSameIdIsNoOp : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Entity = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto TeamHandle = utils_team::Add(Entity, ECk_Team_ID::Three, ECk_Replication::DoesNotReplicate);

        Assert_True(utils_team::Get_ID(TeamHandle) == ECk_Team_ID::Three,
            "Pre-Assign: team should be Three");

        auto Returned = utils_team::Assign(TeamHandle, ECk_Team_ID::Three);

        Assert_True(utils_team::Get_ID(TeamHandle) == ECk_Team_ID::Three,
            "Assigning the already-assigned ID must keep the team unchanged");
        Assert_True(utils_team::Get_ID(Returned) == ECk_Team_ID::Three,
            "Assign must return a usable team handle on the same-ID no-op path");

        FinishSuccess();
    }
}
