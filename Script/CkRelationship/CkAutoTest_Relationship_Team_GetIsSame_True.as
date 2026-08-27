// Language=angelscript
//
// CK RELATIONSHIP - AUTOMATION TEST: Get_IsSame returns true for same team
// Two entities both assigned to team Two -> Get_IsSame is true.

class UCk_AutoTest_Relationship_Team_GetIsSame_True : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto EntityA = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto TeamA = utils_team::Add(EntityA, ECk_Team_ID::Two, ECk_Replication::DoesNotReplicate);

        auto EntityB = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto TeamB = utils_team::Add(EntityB, ECk_Team_ID::Two, ECk_Replication::DoesNotReplicate);

        Assert_True(utils_team::Get_IsSame(TeamA, TeamB),
            "Two entities on team Two should Get_IsSame == true");

        FinishSuccess();
    }
}
