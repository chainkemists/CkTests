// Language=angelscript

//============================================================================
// CK LIVETUNE — AUTOMATION TEST: PROBE PILOT (ViaRequest)
//============================================================================
//
// The ViaRequest tier on a real setup-baked feature: a linked Probe's params
// edit routes through the Probe's own Request_Reconfigure — the live-read
// subset (here: ResponsePolicy) re-applies on the next request drain, with
// no destroy, no rebuild, and the probe's Jolt body untouched.
//============================================================================

class UCk_AutoTest_LiveTune_ProbeViaRequest : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private UCk_LiveTuneTest_TuningAsset _Asset;
    private FCk_Handle_Probe _Probe;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Self = InHandle;
        _Asset = UCk_LiveTuneTest_Utils::Create_TuningAsset(0, 0);

        auto ParentEntity = utils_entity_lifetime::Request_CreateEntity(Self);
        auto ParentTransform = utils_transform::Add(ParentEntity, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto ProbeTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Probe.GetName.SpecificValue");
        auto Params = FCk_Fragment_Probe_ParamsData(ProbeTag);
        auto DebugInfo = FCk_Probe_DebugInfo();
        _Probe = utils_probe::Add_Box(ParentTransform, FVector(25.0f, 25.0f, 25.0f), Params, DebugInfo);
        UCk_LiveTuneTest_Utils::Set_ProbeParams(_Asset, Params);

        auto ProbeBase = FCk_Handle(_Probe);
        utils_live_tune::Link(ProbeBase, _Asset, n"_ProbeParams");

        Assert_True(utils_probe::Get_ResponsePolicy(_Probe) == ECk_ProbeResponse_Policy::Notify,
            "a default-constructed probe should start with the Notify response policy");

        auto Retuned = FCk_Fragment_Probe_ParamsData(ProbeTag);
        Retuned.Set_ResponsePolicy(ECk_ProbeResponse_Policy::Silent);
        UCk_LiveTuneTest_Utils::Set_ProbeParams(_Asset, Retuned);
        UCk_LiveTuneTest_Utils::SimulatePropertyChange(Self, _Asset, n"_ProbeParams");

        Add_Step_WaitUntil("the retuned response policy lands through Request_Reconfigure", n"Check_PolicyRetuned");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_PolicyRetuned(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_probe::Get_ResponsePolicy(_Probe) == ECk_ProbeResponse_Policy::Silent);
    }
}
