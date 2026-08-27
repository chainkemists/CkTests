// Language=angelscript

//============================================================================
// CK PROBE - AUTOMATION TEST: ADD BOX CREATES PROBE ENTITY
//============================================================================
//
// First-coverage seed for CkProbe. Adding a box probe to a transform-bearing
// entity must return a valid FCk_Handle_Probe and Has(parentEntity) must
// report true on the same frame. Pins the most-fundamental contract: a
// probe entity exists after Add and the parent handle is queryable.
//============================================================================

class UCk_AutoTest_Probe_Add_Box_CreatesProbeEntity : UCk_AutoTest_Base
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
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Probe.Add_Box_Seed"));
        auto DebugInfo = FCk_Probe_DebugInfo();
        auto ProbeHandle = utils_probe::Add_Box(ParentTransform, FVector(50.0f, 50.0f, 50.0f), ProbeParams, DebugInfo);

        Assert_True(ck::IsValid(ProbeHandle),
            "utils_probe::Add_Box should return a valid FCk_Handle_Probe");
        Assert_True(utils_probe::Has(ParentEntity),
            "After Add_Box on a transform-bearing entity, Has(parent) should report true");

        FinishSuccess();
    }
}
