// Language=angelscript

//============================================================================
// CK USF ENTITY OUTLINE — AUTOTEST: cascade to lifetime dependents
//============================================================================
//
// A parent entity with two child IsmProxy entities. Request_ApplyOutline with
// EntityAndDependents must outline both children (cascade-derived targets);
// Request_RemoveOutline on the parent must strip only the derived targets —
// a child outlined EXPLICITLY keeps its outline.
//
//============================================================================

class UCk_AutoTest_UsfOutline_CascadeDependents : UCk_AutoTest_Base
{
    private FCk_Handle _Parent;
    private FCk_Handle _Child1;
    private FCk_Handle _Child2;
    private FCk_Handle_IsmProxy _Proxy1;
    private FCk_Handle_IsmProxy _Proxy2;
    private int32 _Phase = 0;
    private int32 _TicksInPhase = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto RendererData = usf_outline_assets::EntityRenderer(InHandle);
        if (ck::Is_NOT_Valid(RendererData)) { FinishSuccess(); return; }

        auto LocalHandle = InHandle;
        _Parent = LocalHandle.Request_CreateEntity();
        _Child1 = _Parent.Request_CreateEntity();
        _Child2 = _Parent.Request_CreateEntity();

        auto Transform1 = utils_transform::Add(_Child1, FTransform(FVector(0.0, 0.0, 0.0)), ECk_Replication::DoesNotReplicate);
        auto Transform2 = utils_transform::Add(_Child2, FTransform(FVector(200.0, 0.0, 0.0)), ECk_Replication::DoesNotReplicate);

        _Proxy1 = utils_ism_proxy::Add(Transform1, FCk_Fragment_IsmProxy_ParamsData(RendererData));
        _Proxy2 = utils_ism_proxy::Add(Transform2, FCk_Fragment_IsmProxy_ParamsData(RendererData));

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _TicksInPhase++;

        if (_Phase == 0 && _TicksInPhase >= 2)
        {
            UCk_Utils_Usf_Outline_UE::Request_ApplyOutline(_Parent, CkUsf::DA_Outline_Interactable,
                ECk_Usf_OutlineScope::EntityAndDependents);
            _Phase = 1; _TicksInPhase = 0;
        }
        else if (_Phase == 1 && _TicksInPhase >= 2)
        {
            Assert_True(UCk_Utils_Usf_Outline_UE::Has_Outline(_Child1), "cascade stamped child 1");
            Assert_True(UCk_Utils_Usf_Outline_UE::Has_Outline(_Child2), "cascade stamped child 2");
            Assert_True(_Proxy1.Get_IsOutlineApplied(), "child 1 proxy outlined");
            Assert_True(_Proxy2.Get_IsOutlineApplied(), "child 2 proxy outlined");

            // Child 1 opts into an EXPLICIT outline — it must survive the parent's removal below.
            UCk_Utils_Usf_Outline_UE::Request_ApplyOutline(_Child1, CkUsf::DA_Outline_SeeThrough);
            UCk_Utils_Usf_Outline_UE::Request_RemoveOutline(_Parent);
            _Phase = 2; _TicksInPhase = 0;
        }
        else if (_Phase == 2 && _TicksInPhase >= 2)
        {
            Assert_True(!UCk_Utils_Usf_Outline_UE::Has_Outline(_Parent), "parent outline removed");
            Assert_True(UCk_Utils_Usf_Outline_UE::Has_Outline(_Child1), "explicitly-outlined child survives cascade removal");
            Assert_True(_Proxy1.Get_IsOutlineApplied(), "explicit child still applied");
            Assert_True(!UCk_Utils_Usf_Outline_UE::Has_Outline(_Child2), "derived-only child stripped");
            Assert_True(!_Proxy2.Get_IsOutlineApplied(), "derived-only child un-applied");

            UCk_Utils_Usf_Outline_UE::Request_RemoveOutline(_Child1);
            FinishSuccess();
        }
    }
}

class ACk_AutoTest_UsfOutline_CascadeDependents_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_UsfOutline_CascadeDependents;
    default _TimeoutSeconds = 5.0f;

    // See the matching note in CkAutoTest_UsfOutline_IsmShadowInstances.as — whichever ISM outline
    // test runs first eats the one-time 'bUsedWithInstancedStaticMeshes' content ensure; the
    // harness suppresses with Occurrences=-1 so a non-firing pattern is harmless.
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        Out.Add("bUsedWithInstancedStaticMeshes");
        Out.Add("material will recompile every editor launch");
        return Out;
    }
}
