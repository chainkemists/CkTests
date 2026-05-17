// Language=angelscript
//
// CK RELATIONSHIP — AUTOMATION TEST: Asymmetric team membership → Neutral
// If only one entity has a Team fragment, the attitude lookup falls back to
// Neutral — the framework does not treat "team vs no team" as Hostile.

class UCk_AutoTest_Relationship_AttitudeOneHasNoTeamIsNeutral : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto EntityA = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_team::Add(EntityA, ECk_Team_ID::Two, ECk_Replication::DoesNotReplicate);

        auto EntityB = utils_entity_lifetime::Request_CreateEntity(InHandle);
        // No team on EntityB.

        auto AttitudeAtoB = utils_relationship::Get_AttitudeTowards_Exec(EntityA, EntityB);
        Assert_True(AttitudeAtoB == ECk_RelationshipAttitude::Neutral,
            "Team -> no-team attitude should be Neutral");

        auto AttitudeBtoA = utils_relationship::Get_AttitudeTowards_Exec(EntityB, EntityA);
        Assert_True(AttitudeBtoA == ECk_RelationshipAttitude::Neutral,
            "No-team -> team attitude should also be Neutral");

        FinishSuccess();
    }
}
