// Language=angelscript
//
// CK RELATIONSHIP - AUTOMATION TEST: Unassign sets the team to Unassigned
// After Add(One) then Unassign, Get_ID returns Unassigned.

class UCk_AutoTest_Relationship_Team_UnassignSetsUnassigned : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Entity = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto TeamHandle = utils_team::Add(Entity, ECk_Team_ID::One, ECk_Replication::DoesNotReplicate);

        utils_team::Unassign(TeamHandle);

        Assert_True(utils_team::Get_ID(TeamHandle) == ECk_Team_ID::Unassigned,
            "Get_ID should return Unassigned after Unassign");

        FinishSuccess();
    }
}
