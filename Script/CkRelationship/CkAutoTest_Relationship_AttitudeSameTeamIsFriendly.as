// Language=angelscript
//
// CK RELATIONSHIP — AUTOMATION TEST: Same team → Friendly
// Two entities both on team Two resolve to Friendly.

class UCk_AutoTest_Relationship_AttitudeSameTeamIsFriendly : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto EntityA = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_team::Add(EntityA, ECk_Team_ID::Two, ECk_Replication::DoesNotReplicate);

        auto EntityB = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_team::Add(EntityB, ECk_Team_ID::Two, ECk_Replication::DoesNotReplicate);

        auto Attitude = utils_relationship::Get_AttitudeTowards_Exec(EntityA, EntityB);
        Assert_True(Attitude == ECk_RelationshipAttitude::Friendly,
            "Two entities on the same team should resolve to Friendly");

        FinishSuccess();
    }
}
