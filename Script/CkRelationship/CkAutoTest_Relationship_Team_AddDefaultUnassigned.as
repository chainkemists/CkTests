// Language=angelscript
//
// CK RELATIONSHIP — AUTOMATION TEST: Team_Add default param is Unassigned
// Calling Add without specifying a team ID assigns Unassigned (the BPFL
// default).

class UCk_AutoTest_Relationship_Team_AddDefaultUnassigned : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Entity = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto TeamHandle = utils_team::Add(Entity, ECk_Team_ID::Unassigned, ECk_Replication::DoesNotReplicate);

        Assert_True(utils_team::Get_ID(TeamHandle) == ECk_Team_ID::Unassigned,
            "Add with Unassigned should leave the entity in the Unassigned team");

        FinishSuccess();
    }
}
