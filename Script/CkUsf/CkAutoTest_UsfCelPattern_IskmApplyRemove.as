// Language=angelscript

//============================================================================
// CK USF ENTITY CEL PATTERN — AUTOTEST: ISKM Plan-1 apply/remove
//============================================================================
//
// The cel-pattern twin of CkAutoTest_UsfOutline_IskmApplyRemove. One Plan-1
// skeletal proxy. Request_SetCelPattern on its entity must mark the proxy
// patterned (custom depth + the pattern's stencil on the pooled SKMC);
// Request_ClearCelPattern must clear it. (Pool hygiene — released SKMCs
// carrying no stencil state — is double-guarded in Release_BaseSKMC itself.)
//
// Then the mutual-exclusion half: an outline applied over a pattern drops the
// cel applied-state without clearing the flags, because both features write
// the SAME SKMCs and the outline's own Sync owns the byte from then on.
//
//============================================================================

class UCk_AutoTest_UsfCelPattern_IskmApplyRemove : UCk_AutoTest_Base
{
    private FCk_Handle _SelfEntity;
    private FCk_Handle_IskmProxy _Proxy;
    private int32 _StencilWhenApplied = 0;
    private int32 _Phase = 0;
    private int32 _TicksInPhase = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto RendererData = iskm_assets::RendererData_Demo();
        if (ck::Is_NOT_Valid(RendererData)) { FinishSuccess(); return; }

        auto LocalHandle = InHandle;
        _SelfEntity = InHandle;

        auto TransformHandle = utils_transform::Add(LocalHandle, FTransform::Identity);
        auto Renderer = utils_iskm_renderer::Add(LocalHandle, RendererData);
        _Proxy = utils_iskm_proxy::Add(TransformHandle, FCk_Fragment_IskmProxy_ParamsData(Renderer, FTransform::Identity));

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _TicksInPhase++;

        if (_Phase == 0 && _TicksInPhase >= 2)
        {
            UCk_Utils_Usf_CelPattern_UE::Request_SetCelPattern(_SelfEntity, ECk_Usf_CelPattern::Crosshatch, ECk_Usf_OutlineScope::EntityOnly);
            _Phase = 1; _TicksInPhase = 0;
        }
        else if (_Phase == 1 && _TicksInPhase >= 2)
        {
            Assert_True(UCk_Utils_Usf_CelPattern_UE::Has_CelPattern(_SelfEntity), "entity has a cel pattern target");
            Assert_True(_Proxy.Get_IsCelPatternApplied(),
                "cel pattern applied to the ISKM proxy (custom depth on its SKMC)");

            _StencilWhenApplied = _Proxy.Get_CelPatternStencilValue();
            Assert_True(_StencilWhenApplied != 0,
                "a real stencil value was written (0 is the engine's 'nothing here')");

            UCk_Utils_Usf_CelPattern_UE::Request_ClearCelPattern(_SelfEntity);
            _Phase = 2; _TicksInPhase = 0;
        }
        else if (_Phase == 2 && _TicksInPhase >= 2)
        {
            Assert_True(!UCk_Utils_Usf_CelPattern_UE::Has_CelPattern(_SelfEntity), "cel pattern target removed");
            Assert_True(!_Proxy.Get_IsCelPatternApplied(),
                "cel pattern cleared from the ISKM proxy");

            // Re-apply, then outline over it: the outline must win and the cel applied-state must drop,
            // or the pattern's cache survives and Sync never restores it after the outline goes away.
            UCk_Utils_Usf_CelPattern_UE::Request_SetCelPattern(_SelfEntity, ECk_Usf_CelPattern::Crosshatch, ECk_Usf_OutlineScope::EntityOnly);
            _Phase = 3; _TicksInPhase = 0;
        }
        else if (_Phase == 3 && _TicksInPhase >= 2)
        {
            Assert_True(_Proxy.Get_IsCelPatternApplied(), "cel pattern re-applied");

            UCk_Utils_Usf_Outline_UE::Request_ApplyOutline(_SelfEntity, CkUsf::DA_Outline_Interactable, ECk_Usf_OutlineScope::EntityOnly);
            _Phase = 4; _TicksInPhase = 0;
        }
        else if (_Phase == 4 && _TicksInPhase >= 3)
        {
            Assert_True(!_Proxy.Get_IsCelPatternApplied(),
                "cel applied-state dropped once the entity carries an outline");
            Assert_True(_Proxy.Get_IsOutlineApplied(), "the outline took the SKMC's stencil over");
            FinishSuccess();
        }
    }
}

class ACk_AutoTest_UsfCelPattern_IskmApplyRemove_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_UsfCelPattern_IskmApplyRemove;
    default _TimeoutSeconds = 5.0f;
}
