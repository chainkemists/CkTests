// Language=angelscript
//
// CK RELATIONSHIP — AUTOMATION TEST: Assign shifts the Get_IsAssignedTo tag
// IsAssignedTo is backed by a tag-per-team-id; after Assign the old tag
// must no longer match and the new one must.

class UCk_AutoTest_Relationship_Team_AssignShiftsIsAssignedTo : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Entity = utils_entity_lifetime::Request_CreateEntity(InHandle);
        auto TeamHandle = utils_team::Add(Entity, ECk_Team_ID::Zero, ECk_Replication::DoesNotReplicate);

        Assert_True(utils_team::Get_IsAssignedTo(TeamHandle, ECk_Team_ID::Zero),
            "Pre-Assign: IsAssignedTo(Zero) should be true");

        utils_team::Assign(TeamHandle, ECk_Team_ID::One);

        Assert_True(!utils_team::Get_IsAssignedTo(TeamHandle, ECk_Team_ID::Zero),
            "Post-Assign: IsAssignedTo(Zero) should be false (old tag cleared)");
        Assert_True(utils_team::Get_IsAssignedTo(TeamHandle, ECk_Team_ID::One),
            "Post-Assign: IsAssignedTo(One) should be true (new tag set)");

        FinishSuccess();
    }
}
