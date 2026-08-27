// Language=angelscript

//============================================================================
// CK OBJECTIVE - AUTOMATION TEST: OBJECTIVE OWNER ADD CREATES FEATURE
//============================================================================
//
// First-coverage seed for CkObjective. Adding an ObjectiveOwner feature
// with an empty default-objectives array returns a valid handle and
// Has(parent) reports true on the same frame.
//
// The Request_AddObjective / Request_RemoveObjective flow is deferred
// for a future slice that authors test Objective subclasses.
//============================================================================

class UCk_AutoTest_ObjectiveOwner_Add_CreatesFeature : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        auto Entity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);

        auto Defaults = TArray<TSubclassOf<UCk_Objective_EntityScript>>();
        auto Params = FCk_ObjectiveOwner_ParamsData(Defaults);
        auto Owner = utils_objective_owner::Add(Entity, Params);

        Assert_True(ck::IsValid(Owner),
            "utils_objective_owner::Add should return a valid FCk_Handle_ObjectiveOwner");
        Assert_True(utils_objective_owner::Has(Entity),
            "After Add, Has on the owning entity should report true");

        FinishSuccess();
    }
}
