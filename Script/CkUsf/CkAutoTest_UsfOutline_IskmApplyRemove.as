// Language=angelscript

//============================================================================
// CK USF ENTITY OUTLINE - AUTOTEST: ISKM Plan-1 apply/remove
//============================================================================
//
// One Plan-1 skeletal proxy. Request_ApplyOutline on its entity must mark the
// proxy outlined (custom depth + stencil on the pooled SKMC); Request_RemoveOutline
// must clear it. (Pool hygiene - released SKMCs carrying no outline state - is
// double-guarded in Release_BaseSKMC itself.)
//
//============================================================================

class UCk_AutoTest_UsfOutline_IskmApplyRemove : UCk_AutoTest_Base
{
    private FCk_Handle _SelfEntity;
    private FCk_Handle_IskmProxy _Proxy;
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
            UCk_Utils_Usf_Outline_UE::Request_ApplyOutline(_SelfEntity, CkUsf::DA_Outline_Interactable, ECk_Usf_OutlineScope::EntityOnly);
            _Phase = 1; _TicksInPhase = 0;
        }
        else if (_Phase == 1 && _TicksInPhase >= 2)
        {
            Assert_True(UCk_Utils_Usf_Outline_UE::Has_Outline(_SelfEntity), "entity has an outline target");
            Assert_True(_Proxy.Get_IsOutlineApplied(),
                "outline applied to the ISKM proxy (custom depth on its SKMC)");

            UCk_Utils_Usf_Outline_UE::Request_RemoveOutline(_SelfEntity);
            _Phase = 2; _TicksInPhase = 0;
        }
        else if (_Phase == 2 && _TicksInPhase >= 2)
        {
            Assert_True(!UCk_Utils_Usf_Outline_UE::Has_Outline(_SelfEntity), "outline target removed");
            Assert_True(!_Proxy.Get_IsOutlineApplied(),
                "outline cleared from the ISKM proxy");
            FinishSuccess();
        }
    }
}
