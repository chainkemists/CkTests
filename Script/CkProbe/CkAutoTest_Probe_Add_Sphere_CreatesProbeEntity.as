// Language=angelscript

//============================================================================
// CK PROBE - AUTOMATION TEST: ADD SPHERE CREATES PROBE ENTITY
//============================================================================
//
// Sphere-shape variant of the Add box-shape seed. utils_probe::Add_Sphere
// attaches a sphere collision shape via utils_shape_sphere::Add and then
// hands off to utils_probe::Add. Asserts the resulting probe handle is
// valid and Has reports true on the parent.
//============================================================================

class UCk_AutoTest_Probe_Add_Sphere_CreatesProbeEntity : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        auto ParentEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto ParentTransform = utils_transform::Add(ParentEntity, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        if (ck::Is_NOT_Valid(ParentTransform))
        {
            FinishFailure("Failed to add Transform feature to parent entity");
            return;
        }

        auto ProbeParams = FCk_Fragment_Probe_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Probe.Add_Sphere_Seed"));
        auto DebugInfo = FCk_Probe_DebugInfo();
        auto ProbeHandle = utils_probe::Add_Sphere(ParentTransform, 75.0f, ProbeParams, DebugInfo);

        Assert_True(ck::IsValid(ProbeHandle),
            "utils_probe::Add_Sphere should return a valid FCk_Handle_Probe");
        Assert_True(utils_probe::Has(ParentEntity),
            "After Add_Sphere on a transform-bearing entity, Has(parent) should report true");

        FinishSuccess();
    }
}
