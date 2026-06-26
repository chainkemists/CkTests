// Language=angelscript
//
// CK RELATIONSHIP — AUTOMATION TEST: TryGet_Entity_Team_InOwnershipChain with no team
// When no entity in the ownership chain has a Team fragment, the lookup
// returns an invalid handle.

class UCk_AutoTest_Relationship_Team_TryGetInOwnershipChainNoTeam : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Parent = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto Child = utils_entity_lifetime::Request_CreateEntity(Parent);

        auto FoundTeam = utils_team::TryGet_Entity_Team_InOwnershipChain(Child);

        Assert_True(!utils_handle::Get_IsValid(FoundTeam),
            "TryGet_Entity_Team_InOwnershipChain should return an invalid handle when no team exists in the chain");

        FinishSuccess();
    }
}
