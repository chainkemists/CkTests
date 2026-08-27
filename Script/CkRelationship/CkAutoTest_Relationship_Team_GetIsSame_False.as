// Language=angelscript
//
// CK RELATIONSHIP - AUTOMATION TEST: Get_IsSame returns false for different teams

class UCk_AutoTest_Relationship_Team_GetIsSame_False : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto EntityA = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto TeamA = utils_team::Add(EntityA, ECk_Team_ID::Two, ECk_Replication::DoesNotReplicate);

        auto EntityB = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto TeamB = utils_team::Add(EntityB, ECk_Team_ID::Three, ECk_Replication::DoesNotReplicate);

        Assert_True(!utils_team::Get_IsSame(TeamA, TeamB),
            "Entities on different teams should Get_IsSame == false");

        FinishSuccess();
    }
}
