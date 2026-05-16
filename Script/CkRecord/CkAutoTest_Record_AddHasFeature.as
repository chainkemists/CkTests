// Language=angelscript

//============================================================================
// CK RECORD — AUTOMATION TEST: ADD FEATURE + HAS QUERY
//============================================================================
//
// Smoke test for the Record-of-Entities public BP/AS surface. Adding the
// generic Record feature to an entity should make `Has` return true.
//
// Catches regressions where the BP `Add` overload diverges from the
// templated C++ AddIfMissing — most likely if the refactor consolidates
// the Default-policy overload.
//============================================================================

class UCk_AutoTest_Record_AddHasFeature : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto RecordOwner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        Assert_True(!utils_record_of_entities::Has(RecordOwner),
            "Fresh entity should NOT have the generic Record feature before Add");

        utils_record_of_entities::Add(RecordOwner);

        Assert_True(utils_record_of_entities::Has(RecordOwner),
            "After Add, the entity should have the generic Record feature");

        // Adding again should be idempotent (Default policy, no ensure).
        utils_record_of_entities::Add(RecordOwner);
        Assert_True(utils_record_of_entities::Has(RecordOwner),
            "After redundant Add (same policy), Record feature still present");

        FinishSuccess();
    }
}
