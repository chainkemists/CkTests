// Language=angelscript
//
// CK RELATIONSHIP - AUTOMATION TEST: Team_Has is false before Add
// A freshly created entity reports Has == false until Add is called.

class UCk_AutoTest_Relationship_Team_HasFalseBeforeAdd : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Entity = utils_entity_lifetime::Request_CreateEntity(InHandle);

        Assert_True(!utils_team::Has(Entity),
            "Pre-Add: Team_Has should be false on a freshly created entity");

        utils_team::Add(Entity, ECk_Team_ID::Zero, ECk_Replication::DoesNotReplicate);

        Assert_True(utils_team::Has(Entity),
            "Post-Add: Team_Has should be true");

        FinishSuccess();
    }
}
