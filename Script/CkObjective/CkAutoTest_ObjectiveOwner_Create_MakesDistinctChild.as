// Language=angelscript

//============================================================================
// CK OBJECTIVE — AUTOMATION TEST: OBJECTIVE OWNER CREATE MAKES A DISTINCT CHILD
//============================================================================
//
// Covers the child-making Create verb (counterpart to the stamp-self Add).
// Create(owner, params) spawns a NEW child entity carrying the feature:
//   - the returned handle is valid,
//   - Has(child) is true,
//   - Has(owner) is FALSE — proving Create stamped the feature on a separate
//     child entity, not onto the owner (which is what Add does).
//============================================================================

class UCk_AutoTest_ObjectiveOwner_Create_MakesDistinctChild : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto Defaults = TArray<TSubclassOf<UCk_Objective_EntityScript>>();
        auto Params = FCk_ObjectiveOwner_Spec(Defaults);

        auto Child = utils_objective_owner::Create(Owner, Params);
        auto ChildEntity = FCk_Handle(Child);

        Assert_True(ck::IsValid(Child),
            "Create should return a valid FCk_Handle_ObjectiveOwner");
        Assert_True(utils_objective_owner::Has(ChildEntity),
            "The created child entity should carry the ObjectiveOwner feature");
        Assert_True(!utils_objective_owner::Has(Owner),
            "The owner must NOT carry the feature — Create is child-making, not stamp-self");

        FinishSuccess();
    }
}
