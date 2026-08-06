// Language=angelscript

//============================================================================
// CK PROBE — AUTOMATION TEST: GET_NAME ROUND-TRIPS THE CONFIGURED TAG
//============================================================================
//
// Pins the parameter round-trip for FCk_Probe_Spec._ProbeName:
// the name tag passed to the Probe params constructor is the same tag
// Get_Name(probe) returns immediately after Add — no settle frame, no
// processor pass needed, because _ProbeName is a constant-after-construction
// fragment field.
//============================================================================

class UCk_AutoTest_Probe_GetName_ReturnsConfiguredTag : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        auto ParentEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto ParentTransform = utils_transform::Add(ParentEntity, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto ConfiguredTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Probe.GetName.SpecificValue");
        auto ProbeParams = FCk_Probe_Spec(ConfiguredTag);
        auto DebugInfo = FCk_Probe_DebugInfo();
        auto ProbeHandle = utils_probe::Add_Box(ParentTransform, FVector(25.0f, 25.0f, 25.0f), ProbeParams, DebugInfo);

        auto ReturnedTag = utils_probe::Get_Name(ProbeHandle);
        Assert_True(ReturnedTag == ConfiguredTag,
            f"Get_Name should return the tag passed to the FCk_Probe_Spec constructor (configured: AutoTest.Probe.GetName.SpecificValue)");

        FinishSuccess();
    }
}
