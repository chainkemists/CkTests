// Language=angelscript
//
// CK RELATIONSHIP - AUTOMATION TEST: Get_IsAssignedTo discriminates teams
// An entity assigned to team Three reports IsAssignedTo(Three)==true and
// IsAssignedTo(Four)==false.

class UCk_AutoTest_Relationship_Team_GetIsAssignedTo : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Entity = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto TeamHandle = utils_team::Add(Entity, ECk_Team_ID::Three, ECk_Replication::DoesNotReplicate);

        Assert_True(utils_team::Get_IsAssignedTo(TeamHandle, ECk_Team_ID::Three),
            "Get_IsAssignedTo should return true for the assigned team");
        Assert_True(!utils_team::Get_IsAssignedTo(TeamHandle, ECk_Team_ID::Four),
            "Get_IsAssignedTo should return false for a different team");

        FinishSuccess();
    }
}
