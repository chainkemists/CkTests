// Language=angelscript

//============================================================================
// CK PROBE - AUTOMATION TEST: GET_RESPONSE_POLICY ROUND-TRIPS
//============================================================================
//
// Pins the parameter round-trip for FCk_Fragment_Probe_ParamsData
// ._ResponsePolicy. A probe Added with Silent policy reports Silent;
// the default-constructed params (which set Notify) reports Notify on
// a second probe. Guards against a future refactor that drops the
// setter chain into the fragment.
//============================================================================

class UCk_AutoTest_Probe_Get_ResponsePolicy_ReturnsConfigured : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        // Probe A - explicit Silent.
        auto ParentA = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto TransformA = utils_transform::Add(ParentA, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        auto ParamsA = FCk_Fragment_Probe_ParamsData(utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Probe.ResponsePolicy.Silent"));
        ParamsA.Set_ResponsePolicy(ECk_ProbeResponse_Policy::Silent);
        auto ProbeA = utils_probe::Add_Box(TransformA, FVector(20.0f, 20.0f, 20.0f), ParamsA, FCk_Probe_DebugInfo());

        Assert_True(utils_probe::Get_ResponsePolicy(ProbeA) == ECk_ProbeResponse_Policy::Silent,
            "Probe configured with Set_ResponsePolicy(Silent) should report Silent");

        // Probe B - default (Notify per the params struct default).
        auto ParentB = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto TransformB = utils_transform::Add(ParentB, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        auto ParamsB = FCk_Fragment_Probe_ParamsData(utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Probe.ResponsePolicy.Notify"));
        auto ProbeB = utils_probe::Add_Box(TransformB, FVector(20.0f, 20.0f, 20.0f), ParamsB, FCk_Probe_DebugInfo());

        Assert_True(utils_probe::Get_ResponsePolicy(ProbeB) == ECk_ProbeResponse_Policy::Notify,
            "Probe with default params should report the struct default (Notify)");

        FinishSuccess();
    }
}
