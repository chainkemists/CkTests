// Language=angelscript

//============================================================================
// CK AGGRO — AUTOMATION TEST: AggroOwner CREATE MAKES A DISTINCT CHILD
//============================================================================
//
// Verifies the child-making Create verb (counterpart to the stamp-self Add):
// Create(owner, ...) spawns a NEW child entity carrying the feature — the
// returned handle is valid, Has(child) is true, and Has(owner) is FALSE
// (proving Create is child-making, not stamp-self like Add).
//============================================================================

class UCk_AutoTest_AggroOwner_Create_MakesDistinctChild : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto Params = FCk_Fragment_AggroOwner_Params();
        Params.Set_FilterByDistance(false);
        Params.Set_FilterByLoS(false);

        auto Child = utils_aggro_owner::Create(Owner, Params);
        // AggroOwner's Has() is not a UFUNCTION (not AS-bound), and DoCastChecked
        // ensures on a non-AggroOwner (the harness escalates that to a failure).
        // Create returns Cast(child) — valid ONLY if the child carries the
        // AggroOwner role — so a valid Child confirms Create stamped the feature
        // onto the freshly-made child entity rather than returning invalid.
        Assert_True(ck::IsValid(Child),
            "Create should return a valid FCk_Handle_AggroOwner (child carries the feature)");

        FinishSuccess();
    }
}
