// Language=angelscript

//============================================================================
// CK PROBE — AUTOMATION TEST: Probe CREATE MAKES A DISTINCT CHILD
//============================================================================
//
// Verifies the child-making Create verb (counterpart to the stamp-self Add):
// Create(owner, ...) spawns a NEW child entity carrying the feature — the
// returned handle is valid, Has(child) is true, and Has(owner) is FALSE
// (proving Create is child-making, not stamp-self like Add).
//
// Note: utils_probe::Create already provisions the child's Transform from
// InInitialTransform (CkProbe_Utils.cpp:65) before adding the shape + probe,
// so no extra utils_transform::Add is needed here (a second Add would be
// redundant on an already-transform-bearing child).
//============================================================================

class UCk_AutoTest_Probe_Create_MakesDistinctChild : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);

        auto BoxShape = utils_shapes::Make_Box(FCk_ShapeBox_Dimensions(FVector(50.0f, 50.0f, 50.0f)));
        auto ProbeParams = FCk_Fragment_Probe_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Probe.Create_Seed"));
        auto DebugInfo = FCk_Probe_DebugInfo();

        auto Child = utils_probe::Create(Owner, FTransform::Identity, BoxShape, ProbeParams, DebugInfo);
        auto ChildEntity = FCk_Handle(Child);

        Assert_True(ck::IsValid(Child),
            "Create should return a valid FCk_Handle_Probe");
        Assert_True(utils_probe::Has(ChildEntity),
            "The created child entity should carry the Probe feature");
        Assert_True(!utils_probe::Has(Owner),
            "The owner must NOT carry the feature — Create is child-making, not stamp-self");

        FinishSuccess();
    }
}
