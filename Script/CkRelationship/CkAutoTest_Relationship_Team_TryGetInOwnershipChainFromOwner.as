// Language=angelscript
//
// CK RELATIONSHIP — AUTOMATION TEST: TryGet_Entity_Team_InOwnershipChain finds owner's team
// A child entity (no team of its own) inherits its owner's team via the
// ownership-chain lookup — feeds CkAggro/CkTargeting/CkResolver attitude
// queries that span entity hierarchies.

class UCk_AutoTest_Relationship_Team_TryGetInOwnershipChainFromOwner : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Parent = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto ParentTeam = utils_team::Add(Parent, ECk_Team_ID::Two, ECk_Replication::DoesNotReplicate);

        auto Child = utils_entity_lifetime::Request_CreateEntity(Parent);

        auto FoundTeam = utils_team::TryGet_Entity_Team_InOwnershipChain(Child);

        Assert_True(utils_handle::Get_IsValid(FoundTeam),
            "Child should resolve its owner's team via TryGet_Entity_Team_InOwnershipChain");
        Assert_True(utils_team::Get_ID(FoundTeam) == ECk_Team_ID::Two,
            "Resolved team ID should match the parent's team");

        FinishSuccess();
    }
}
