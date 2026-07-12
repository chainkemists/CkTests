// Language=angelscript

//============================================================================
// CK USF ENTITY OUTLINE — AUTOTEST: ISM shadow-instance bookkeeping
//============================================================================
//
// Three IsmProxy cube entities share one ISM component. Outlining two of them
// must mirror exactly two instances into the custom-depth-only shadow ISM;
// removal and entity destruction must pull them back out.
// Headless-safe: instance add/remove is CPU-side (no rendering asserted).
//
//============================================================================

class UCk_AutoTest_UsfOutline_IsmShadowInstances : UCk_AutoTest_Base
{
    private FCk_Handle _EntityA;
    private FCk_Handle _EntityB;
    private FCk_Handle _EntityC;
    private FCk_Handle_IsmProxy _ProxyA;
    private FCk_Handle_IsmProxy _ProxyB;
    private FCk_Handle_IsmProxy _ProxyC;
    private int32 _Phase = 0;
    private int32 _TicksInPhase = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto RendererData = usf_outline_assets::EntityRenderer(InHandle);
        if (ck::Is_NOT_Valid(RendererData)) { FinishSuccess(); return; }

        auto LocalHandle = InHandle;

        _EntityA = LocalHandle.Request_CreateEntity();
        _EntityB = LocalHandle.Request_CreateEntity();
        _EntityC = LocalHandle.Request_CreateEntity();

        auto TransformA = utils_transform::Add(_EntityA, FTransform(FVector(0.0, 0.0, 0.0)), ECk_Replication::DoesNotReplicate);
        auto TransformB = utils_transform::Add(_EntityB, FTransform(FVector(200.0, 0.0, 0.0)), ECk_Replication::DoesNotReplicate);
        auto TransformC = utils_transform::Add(_EntityC, FTransform(FVector(400.0, 0.0, 0.0)), ECk_Replication::DoesNotReplicate);

        _ProxyA = utils_ism_proxy::Add(TransformA, FCk_Fragment_IsmProxy_ParamsData(RendererData));
        _ProxyB = utils_ism_proxy::Add(TransformB, FCk_Fragment_IsmProxy_ParamsData(RendererData));
        _ProxyC = utils_ism_proxy::Add(TransformC, FCk_Fragment_IsmProxy_ParamsData(RendererData));

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _TicksInPhase++;

        if (_Phase == 0 && _TicksInPhase >= 2)
        {
            // Proxies set up + instances added — outline A and B.
            UCk_Utils_Usf_Outline_UE::Request_ApplyOutline(_EntityA, CkUsf::DA_Outline_Interactable);
            UCk_Utils_Usf_Outline_UE::Request_ApplyOutline(_EntityB, CkUsf::DA_Outline_Interactable);
            _Phase = 1; _TicksInPhase = 0;
        }
        else if (_Phase == 1 && _TicksInPhase >= 2)
        {
            Assert_True(_ProxyA.Get_IsOutlineApplied(), "A outlined after apply");
            Assert_True(_ProxyB.Get_IsOutlineApplied(), "B outlined after apply");
            Assert_True(!_ProxyC.Get_IsOutlineApplied(), "C not outlined");
            Assert_Equals_Int(_ProxyA.Get_OutlineShadowInstanceCount(), 2,
                "shadow ISM holds exactly the two outlined instances");

            UCk_Utils_Usf_Outline_UE::Request_RemoveOutline(_EntityA);
            _Phase = 2; _TicksInPhase = 0;
        }
        else if (_Phase == 2 && _TicksInPhase >= 2)
        {
            Assert_True(!_ProxyA.Get_IsOutlineApplied(), "A no longer outlined after remove");
            Assert_Equals_Int(_ProxyB.Get_OutlineShadowInstanceCount(), 1,
                "shadow ISM shrank to one instance after remove");

            // Destroying an outlined entity must pull its shadow instance too.
            utils_entity_lifetime::Request_DestroyEntity(_EntityB);
            UCk_Utils_Usf_Outline_UE::Request_ApplyOutline(_EntityC, CkUsf::DA_Outline_Interactable);
            _Phase = 3; _TicksInPhase = 0;
        }
        else if (_Phase == 3 && _TicksInPhase >= 3)
        {
            Assert_True(_ProxyC.Get_IsOutlineApplied(), "C outlined after apply");
            Assert_Equals_Int(_ProxyC.Get_OutlineShadowInstanceCount(), 1,
                "destroyed entity's shadow instance was removed (only C remains)");
            FinishSuccess();
        }
    }
}

class ACk_AutoTest_UsfOutline_IsmShadowInstances_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_UsfOutline_IsmShadowInstances;
    default _TimeoutSeconds = 5.0f;

    // The FIRST test in the map to stand up the shared ISM renderer eats a one-time content ensure:
    // the renderer DA's material lacks 'bUsedWithInstancedStaticMeshes' in uncooked/headless runs
    // (editor sessions auto-set the flag on save). Whitelist it on BOTH ISM outline tests — the
    // harness registers these with Occurrences=-1 (pure suppression), so a non-firing pattern is fine.
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        Out.Add("bUsedWithInstancedStaticMeshes");
        Out.Add("material will recompile every editor launch");
        return Out;
    }
}
