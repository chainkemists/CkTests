// Language=angelscript
//
// CK RELATIONSHIP - AUTOMATION TEST: Get_AttitudeTowards(self, self) is Friendly
// Self-attitude short-circuits to Friendly regardless of team assignment.

class UCk_AutoTest_Relationship_AttitudeSelfIsFriendly : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Entity = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto Attitude = utils_relationship::Get_AttitudeTowards_Exec(Entity, Entity);
        Assert_True(Attitude == ECk_RelationshipAttitude::Friendly,
            "Self-attitude (same handle on both sides) should resolve to Friendly");

        FinishSuccess();
    }
}
