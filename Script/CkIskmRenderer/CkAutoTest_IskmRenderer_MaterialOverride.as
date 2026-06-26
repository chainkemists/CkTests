// Language=angelscript

//============================================================================
// CK ISKM RENDERER — AUTOMATION TEST: PER-PROXY MATERIAL OVERRIDE
//============================================================================
//
// Verifies the per-proxy material-override capability (Phase 1a of the
// character-customizer port):
//   1. A fresh proxy reports no override (Get_MaterialOverride == nullptr)
//      and Get_Material(0) returns the mesh-default material.
//   2. Request_SetMaterialOverride(slot 0, M_Glow) -> Get_MaterialOverride
//      and Get_Material both read back the override after a tick.
//   3. POOL HYGIENE (load-bearing): destroying the proxy entity returns its
//      SKMC to the renderer pool (LIFO). A second proxy created against the
//      same renderer borrows the SAME SKMC and must come back with the
//      mesh-default material — no override leak across borrowers.
//
// Skip condition (mirrors CustomDataSuccess): missing wrapper/demo assets ->
// FinishSuccess without asserting.
//
//============================================================================

class UCk_AutoTest_IskmRenderer_MaterialOverride : UCk_AutoTest_Base
{
    private FCk_Handle _TestEntity;
    private FCk_Handle _ChildA;
    private FCk_Handle _ChildB;
    private FCk_Handle_IskmRenderer _Renderer;
    private FCk_Handle_IskmProxy _ProxyA;
    private FCk_Handle_IskmProxy _ProxyB;
    private UMaterialInterface _DefaultMat;
    private UMaterialInterface _OverrideMat;
    private int32 _Phase = 0;
    private int32 _TicksInPhase = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        UCk_IskmRenderer_Data RendererData = iskm_assets::RendererData_Demo();
        if (ck::Is_NOT_Valid(RendererData)) { FinishSuccess(); return; }

        _OverrideMat = assets::load::M_Glow();
        if (ck::Is_NOT_Valid(_OverrideMat)) { FinishSuccess(); return; }

        auto LocalHandle = InHandle;
        _TestEntity = InHandle;
        _Renderer = utils_iskm_renderer::Add(LocalHandle, RendererData);

        auto ChildA = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto Params = FCk_Fragment_IskmProxy_ParamsData(_Renderer, FTransform::Identity);
        _ProxyA = utils_iskm_proxy::Add(ChildA, Params);
        _ChildA = ChildA;

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _TicksInPhase++;

        if (_Phase == 0)
        {
            // Poll until ProxyA's Setup has landed (SKMC acquired + mesh set);
            // Get_Material returns nullptr until then.
            _DefaultMat = utils_iskm_proxy::Get_Material(_ProxyA, int32(0));
            if (_DefaultMat == nullptr) { return; }

            Assert_True(utils_iskm_proxy::Get_MaterialOverride(_ProxyA, int32(0)) == nullptr,
                "A fresh proxy must report no material override on slot 0");
            Assert_True(_DefaultMat != _OverrideMat,
                "Test precondition: the mesh-default material must differ from the override material");

            auto Request = FCk_Request_IskmProxy_SetMaterialOverride(int32(0), _OverrideMat);
            utils_iskm_proxy::Request_SetMaterialOverride(_ProxyA, Request);
            _Phase = 1;
            _TicksInPhase = 0;
        }
        else if (_Phase == 1 && _TicksInPhase >= 2)
        {
            Assert_True(utils_iskm_proxy::Get_MaterialOverride(_ProxyA, int32(0)) == _OverrideMat,
                "Get_MaterialOverride(0) should return the material set via Request_SetMaterialOverride");
            Assert_True(utils_iskm_proxy::Get_Material(_ProxyA, int32(0)) == _OverrideMat,
                "Get_Material(0) should reflect the applied override on the base SKMC");

            // Return ProxyA's SKMC to the renderer pool by destroying its entity.
            auto ChildA = _ChildA;
            utils_entity_lifetime::Request_DestroyEntity(ChildA);
            _Phase = 2;
            _TicksInPhase = 0;
        }
        else if (_Phase == 2 && _TicksInPhase >= 2)
        {
            // The pool is LIFO and ProxyA's SKMC is the only released component,
            // so ProxyB borrows the SAME SKMC.
            auto LocalHandle = _TestEntity;
            auto ChildB = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
            auto Params = FCk_Fragment_IskmProxy_ParamsData(_Renderer, FTransform::Identity);
            _ProxyB = utils_iskm_proxy::Add(ChildB, Params);
            _ChildB = ChildB;
            _Phase = 3;
            _TicksInPhase = 0;
        }
        else if (_Phase == 3)
        {
            // Poll until ProxyB's Setup has landed.
            auto FreshMat = utils_iskm_proxy::Get_Material(_ProxyB, int32(0));
            if (FreshMat == nullptr) { return; }

            Assert_True(utils_iskm_proxy::Get_MaterialOverride(_ProxyB, int32(0)) == nullptr,
                "A fresh proxy on the recycled SKMC must report no material override");
            Assert_True(FreshMat == _DefaultMat,
                "POOL LEAK: the recycled SKMC must come back with the mesh-default material on slot 0");
            FinishSuccess();
        }
    }
}

class ACk_AutoTest_IskmRenderer_MaterialOverride_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_IskmRenderer_MaterialOverride;
    default _TimeoutSeconds = 10.0f;
}
