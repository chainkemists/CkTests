// Language=angelscript
//
// CK RELATIONSHIP — AUTOMATION TEST: Different teams → Hostile
// Entity on team Two and entity on team Three resolve to Hostile.

class UCk_AutoTest_Relationship_AttitudeDifferentTeamsIsHostile : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto EntityA = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_team::Add(EntityA, ECk_Team_ID::Two, ECk_Replication::DoesNotReplicate);

        auto EntityB = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_team::Add(EntityB, ECk_Team_ID::Three, ECk_Replication::DoesNotReplicate);

        auto Attitude = utils_relationship::Get_AttitudeTowards_Exec(EntityA, EntityB);
        Assert_True(Attitude == ECk_RelationshipAttitude::Hostile,
            "Entities on different teams should resolve to Hostile");

        FinishSuccess();
    }
}
