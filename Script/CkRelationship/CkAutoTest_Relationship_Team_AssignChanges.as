// Language=angelscript
//
// CK RELATIONSHIP - AUTOMATION TEST: Assign reassigns the team
// Starting on One, Assign(Two) flips the entity's reported team to Two.

class UCk_AutoTest_Relationship_Team_AssignChanges : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Entity = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto TeamHandle = utils_team::Add(Entity, ECk_Team_ID::One, ECk_Replication::DoesNotReplicate);

        Assert_True(utils_team::Get_ID(TeamHandle) == ECk_Team_ID::One,
            "Pre-Assign: team should be One");

        utils_team::Assign(TeamHandle, ECk_Team_ID::Two);

        Assert_True(utils_team::Get_ID(TeamHandle) == ECk_Team_ID::Two,
            "Post-Assign: team should be Two");

        FinishSuccess();
    }
}
