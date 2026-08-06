// Language=angelscript

//============================================================================
// CK STATE MACHINE — AUTOMATION TEST: StateMachine CREATE MAKES A DISTINCT CHILD
//============================================================================
//
// Verifies the child-making Create verb (counterpart to the stamp-self Add):
// Create(owner, ...) spawns a NEW child entity carrying the feature — the
// returned handle is valid, Has(child) is true, and Has(owner) is FALSE
// (proving Create is child-making, not stamp-self like Add).
//============================================================================

class UCk_AutoTest_StateMachine_Create_MakesDistinctChild : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto Params = FCk_StateMachine_Spec(UCk_SmTest_State_Idle);

        auto Child = utils_state_machine::Create(Owner, Params);
        auto ChildEntity = FCk_Handle(Child);

        Assert_True(ck::IsValid(Child),
            "Create should return a valid FCk_Handle_StateMachine");
        Assert_True(utils_state_machine::Has(ChildEntity),
            "The created child entity should carry the StateMachine feature");
        Assert_True(!utils_state_machine::Has(Owner),
            "The owner must NOT carry the feature — Create is child-making, not stamp-self");

        FinishSuccess();
    }
}
