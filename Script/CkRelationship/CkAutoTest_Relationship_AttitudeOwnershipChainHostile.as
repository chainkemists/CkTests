// Language=angelscript
//
// CK RELATIONSHIP - AUTOMATION TEST: ownership-chain teams drive attitude
// Two team-less children whose parents are on opposing teams should resolve
// to Hostile through the ownership-chain team lookup.

class UCk_AutoTest_Relationship_AttitudeOwnershipChainHostile : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto ParentA = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_team::Add(ParentA, ECk_Team_ID::Two, ECk_Replication::DoesNotReplicate);
        auto ChildA = utils_entity_lifetime::Request_CreateEntity(ParentA);

        auto ParentB = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_team::Add(ParentB, ECk_Team_ID::Three, ECk_Replication::DoesNotReplicate);
        auto ChildB = utils_entity_lifetime::Request_CreateEntity(ParentB);

        auto Attitude = utils_relationship::Get_AttitudeTowards_Exec(ChildA, ChildB);
        Assert_True(Attitude == ECk_RelationshipAttitude::Hostile,
            "Children of parents on opposing teams should resolve to Hostile via ownership-chain team lookup");

        FinishSuccess();
    }
}
