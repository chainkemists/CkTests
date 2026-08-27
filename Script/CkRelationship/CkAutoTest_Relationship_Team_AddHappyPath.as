// Language=angelscript
//
// CK RELATIONSHIP - AUTOMATION TEST: Team_Add happy path
// Add(handle, Zero) -> Has reports true; Get_ID returns Zero.

class UCk_AutoTest_Relationship_Team_AddHappyPath : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Entity = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto TeamHandle = utils_team::Add(Entity, ECk_Team_ID::Zero, ECk_Replication::DoesNotReplicate);

        Assert_True(utils_handle::Get_IsValid(TeamHandle),
            "Add should return a valid FCk_Handle_Team");
        Assert_True(utils_team::Has(Entity),
            "Has should return true after Add");
        Assert_True(utils_team::Get_ID(TeamHandle) == ECk_Team_ID::Zero,
            "Get_ID should match the assigned team");

        FinishSuccess();
    }
}
