// Language=angelscript

//============================================================================
// CK SUBSTEP — AUTOMATION TEST: SUBSTEP CREATE MAKES A DISTINCT CHILD
//============================================================================
//
// Covers the child-making Create verb (counterpart to the stamp-self Add).
// Create(owner, params) spawns a NEW child entity carrying the Substep
// feature: the returned handle is valid, Has(child) is true, and Has(owner)
// is FALSE — proving Create is child-making, not stamp-self like Add.
//============================================================================

class UCk_AutoTest_Substep_Create_MakesDistinctChild : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto Params = FCk_Substep_ParamsData(FCk_Time(0.05f));

        auto Child = utils_substep::Create(Owner, Params);
        auto ChildEntity = FCk_Handle(Child);

        Assert_True(ck::IsValid(Child),
            "Create should return a valid FCk_Handle_Substep");
        Assert_True(utils_substep::Has(ChildEntity),
            "The created child entity should carry the Substep feature");
        Assert_True(!utils_substep::Has(Owner),
            "The owner must NOT carry the feature — Create is child-making, not stamp-self");

        FinishSuccess();
    }
}
