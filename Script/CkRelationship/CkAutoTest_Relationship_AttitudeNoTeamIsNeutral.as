// Language=angelscript
//
// CK RELATIONSHIP — AUTOMATION TEST: No team on either side → Neutral
// Two entities with no Team in their ownership chain resolve to Neutral.

class UCk_AutoTest_Relationship_AttitudeNoTeamIsNeutral : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto EntityA = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto EntityB = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto Attitude = utils_relationship::Get_AttitudeTowards_Exec(EntityA, EntityB);
        Assert_True(Attitude == ECk_RelationshipAttitude::Neutral,
            "Two team-less entities should resolve to Neutral");

        FinishSuccess();
    }
}
