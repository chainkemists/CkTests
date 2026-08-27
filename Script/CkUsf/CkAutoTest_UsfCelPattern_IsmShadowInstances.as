// Language=angelscript

//============================================================================
// CK USF ENTITY CEL PATTERN - AUTOTEST: ISM shadow-instance bookkeeping
//============================================================================
//
// The cel-pattern twin of CkAutoTest_UsfOutline_IsmShadowInstances. Four
// IsmProxy cube entities share one ISM component; two take one pattern and two
// take another. Each pattern must get its OWN custom-depth-only shadow ISM
// (the shadow is keyed on the stencil VALUE, not on a preset), and every way a
// pattern can end must pull the instance back out:
//
//   - an outline arriving over it  -> the cel shadow instance is TORN DOWN,
//     not merely forgotten, or two custom-depth writers land on the same pixels
//   - the entity being destroyed
//   - Request_ClearCelPattern
//
// Headless-safe: instance add/remove is CPU-side (no rendering asserted).
//
//============================================================================

class UCk_AutoTest_UsfCelPattern_IsmShadowInstances : UCk_AutoTest_Base
{
    private FCk_Handle _EntityA;
    private FCk_Handle _EntityB;
    private FCk_Handle _EntityC;
    private FCk_Handle _EntityD;
    private FCk_Handle_IsmProxy _ProxyA;
    private FCk_Handle_IsmProxy _ProxyB;
    private FCk_Handle_IsmProxy _ProxyC;
    private FCk_Handle_IsmProxy _ProxyD;
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
        _EntityD = LocalHandle.Request_CreateEntity();

        auto TransformA = utils_transform::Add(_EntityA, FTransform(FVector(0.0, 0.0, 0.0)), ECk_Replication::DoesNotReplicate);
        auto TransformB = utils_transform::Add(_EntityB, FTransform(FVector(200.0, 0.0, 0.0)), ECk_Replication::DoesNotReplicate);
        auto TransformC = utils_transform::Add(_EntityC, FTransform(FVector(400.0, 0.0, 0.0)), ECk_Replication::DoesNotReplicate);
        auto TransformD = utils_transform::Add(_EntityD, FTransform(FVector(600.0, 0.0, 0.0)), ECk_Replication::DoesNotReplicate);

        _ProxyA = utils_ism_proxy::Add(TransformA, FCk_Fragment_IsmProxy_ParamsData(RendererData));
        _ProxyB = utils_ism_proxy::Add(TransformB, FCk_Fragment_IsmProxy_ParamsData(RendererData));
        _ProxyC = utils_ism_proxy::Add(TransformC, FCk_Fragment_IsmProxy_ParamsData(RendererData));
        _ProxyD = utils_ism_proxy::Add(TransformD, FCk_Fragment_IsmProxy_ParamsData(RendererData));

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _TicksInPhase++;

        if (_Phase == 0 && _TicksInPhase >= 2)
        {
            // Proxies set up + instances added - two entities per pattern.
            UCk_Utils_Usf_CelPattern_UE::Request_SetCelPattern(_EntityA, ECk_Usf_CelPattern::Bayer, ECk_Usf_OutlineScope::EntityOnly);
            UCk_Utils_Usf_CelPattern_UE::Request_SetCelPattern(_EntityB, ECk_Usf_CelPattern::Bayer, ECk_Usf_OutlineScope::EntityOnly);
            UCk_Utils_Usf_CelPattern_UE::Request_SetCelPattern(_EntityC, ECk_Usf_CelPattern::Lines, ECk_Usf_OutlineScope::EntityOnly);
            UCk_Utils_Usf_CelPattern_UE::Request_SetCelPattern(_EntityD, ECk_Usf_CelPattern::Lines, ECk_Usf_OutlineScope::EntityOnly);
            _Phase = 1; _TicksInPhase = 0;
        }
        else if (_Phase == 1 && _TicksInPhase >= 2)
        {
            Assert_True(_ProxyA.Get_IsCelPatternApplied(), "A patterned after request");
            Assert_True(_ProxyB.Get_IsCelPatternApplied(), "B patterned after request");
            Assert_True(_ProxyC.Get_IsCelPatternApplied(), "C patterned after request");
            Assert_True(_ProxyD.Get_IsCelPatternApplied(), "D patterned after request");

            Assert_True(_ProxyA.Get_CelPatternStencilValue() != 0,
                "a real stencil value was written (0 is the engine's 'nothing here')");
            Assert_True(_ProxyC.Get_CelPatternStencilValue() != _ProxyA.Get_CelPatternStencilValue(),
                "a different pattern resolves to a different stencil value");

            Assert_Equals_Int(_ProxyA.Get_CelPatternShadowInstanceCount(), 2,
                "the first pattern's shadow ISM holds exactly A and B");
            Assert_Equals_Int(_ProxyC.Get_CelPatternShadowInstanceCount(), 2,
                "the second pattern got its OWN shadow ISM, holding exactly C and D");

            // An outline on a patterned proxy must remove the cel shadow instance, not just forget it:
            // two custom-depth writers on the same pixels is exactly what this guards.
            UCk_Utils_Usf_Outline_UE::Request_ApplyOutline(_EntityB, CkUsf::DA_Outline_Interactable, ECk_Usf_OutlineScope::EntityOnly);
            _Phase = 2; _TicksInPhase = 0;
        }
        else if (_Phase == 2 && _TicksInPhase >= 3)
        {
            Assert_True(!_ProxyB.Get_IsCelPatternApplied(),
                "cel applied-state dropped once B carries an outline");
            Assert_True(_ProxyB.Get_IsOutlineApplied(), "the outline took B over");
            Assert_Equals_Int(_ProxyA.Get_CelPatternShadowInstanceCount(), 1,
                "B's cel shadow instance was torn down, not left beside the outline's");

            // Destroying a patterned entity must pull its shadow instance too.
            utils_entity_lifetime::Request_DestroyEntity(_EntityD);
            _Phase = 3; _TicksInPhase = 0;
        }
        else if (_Phase == 3 && _TicksInPhase >= 3)
        {
            Assert_Equals_Int(_ProxyC.Get_CelPatternShadowInstanceCount(), 1,
                "destroyed entity's shadow instance was removed (only C remains)");

            UCk_Utils_Usf_CelPattern_UE::Request_ClearCelPattern(_EntityC);
            _Phase = 4; _TicksInPhase = 0;
        }
        else if (_Phase == 4 && _TicksInPhase >= 2)
        {
            Assert_True(!_ProxyC.Get_IsCelPatternApplied(), "C no longer patterned after clear");
            Assert_True(_ProxyA.Get_IsCelPatternApplied(), "A's pattern survived every other entity's exit");
            FinishSuccess();
        }
    }
}

class ACk_AutoTest_UsfCelPattern_IsmShadowInstances_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_UsfCelPattern_IsmShadowInstances;
    default _TimeoutSeconds = 5.0f;

    // Shares the ISM outline tests' one-time content ensure: the renderer DA's material lacks
    // 'bUsedWithInstancedStaticMeshes' in uncooked/headless runs, and whichever test stands the shared
    // renderer up first eats it. Registered with Occurrences=-1 (pure suppression), so a non-firing
    // pattern is fine.
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        Out.Add("bUsedWithInstancedStaticMeshes");
        Out.Add("material will recompile every editor launch");
        return Out;
    }
}
