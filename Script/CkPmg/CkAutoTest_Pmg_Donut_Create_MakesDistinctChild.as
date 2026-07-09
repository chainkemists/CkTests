// Language=angelscript

//============================================================================
// CK PMG — AUTOMATION TEST: Pmg_Donut CREATE MAKES A DISTINCT CHILD
//============================================================================
//
// Verifies the child-making Create verb (counterpart to the stamp-self Add):
// Create(owner, ...) spawns a NEW child entity carrying the feature — the
// returned handle is valid, Has(child) is true, and Has(owner) is FALSE
// (proving Create is child-making, not stamp-self like Add).
//============================================================================

class UCk_AutoTest_Pmg_Donut_Create_MakesDistinctChild : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto Params = FCk_Fragment_Pmg_Donut_ParamsData();

        auto Child = utils_pmg_donut::Create(Owner, Params);
        auto ChildEntity = FCk_Handle(Child);

        Assert_True(ck::IsValid(Child),
            "Create should return a valid FCk_Handle_Pmg_Donut");
        Assert_True(utils_pmg_donut::Has(ChildEntity),
            "The created child entity should carry the Pmg_Donut feature");
        Assert_True(!utils_pmg_donut::Has(Owner),
            "The owner must NOT carry the feature — Create is child-making, not stamp-self");

        utils_transform::Add(ChildEntity, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        FinishSuccess();
    }
}

//============================================================================
// HAND-AUTHORED WRAPPER ACTOR (skipped by the auto-generator when present)
//============================================================================

class ACk_AutoTest_Pmg_Donut_Create_MakesDistinctChild_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Pmg_Donut_Create_MakesDistinctChild;

    // Pmg Donut logs a benign warning when no material is supplied ("using default
    // material"). The Create still composes the feature correctly; whitelist the
    // warning so the harness doesn't auto-fail on the deliberately fixture-free
    // params. AS can't brace-init a TArray<FString> via default, so build it here.
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        Out.Add("No material specified for Pmg Donut");
        return Out;
    }
}
