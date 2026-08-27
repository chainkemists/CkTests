// Language=angelscript

//============================================================================
// CK RELATIONSHIP - AUTOMATION TEST: Player CREATE MAKES A DISTINCT CHILD
//============================================================================
//
// Verifies the child-making Create verb (counterpart to the stamp-self Add):
// Create(owner, ...) spawns a NEW child entity carrying the feature - the
// returned handle is valid, Has(child) is true, and Has(owner) is FALSE
// (proving Create is child-making, not stamp-self like Add).
//============================================================================

class UCk_AutoTest_Player_Create_MakesDistinctChild : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto Child = utils_player::Create(Owner, ECk_Player_ID::Zero, ECk_Replication::DoesNotReplicate);
        auto ChildEntity = FCk_Handle(Child);

        Assert_True(ck::IsValid(Child),
            "Create should return a valid FCk_Handle_Player");
        Assert_True(utils_player::Has(ChildEntity),
            "The created child entity should carry the Player feature");
        Assert_True(!utils_player::Has(Owner),
            "The owner must NOT carry the feature - Create is child-making, not stamp-self");

        FinishSuccess();
    }
}
