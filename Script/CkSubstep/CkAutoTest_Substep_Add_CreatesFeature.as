// Language=angelscript

//============================================================================
// CK SUBSTEP — AUTOMATION TEST: ADD CREATES FEATURE
//============================================================================
//
// First-coverage seed for CkSubstep. Adding a Substep feature with a
// configured tick rate returns a valid handle and Has(parent) reports
// true. CkSubstep drives fixed-rate logic for entities that need
// deterministic stepping decoupled from frame rate.
//============================================================================

class UCk_AutoTest_Substep_Add_CreatesFeature : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        auto Entity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);

        auto Params = FCk_Substep_ParamsData(FCk_Time(0.05f));
        auto SubstepHandle = utils_substep::Add(Entity, Params);

        Assert_True(ck::IsValid(SubstepHandle),
            "utils_substep::Add should return a valid FCk_Handle_Substep");
        Assert_True(utils_substep::Has(Entity),
            "After Add, Has on the owning entity should report true");

        FinishSuccess();
    }
}
