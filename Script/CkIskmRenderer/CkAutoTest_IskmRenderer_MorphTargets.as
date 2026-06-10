// Language=angelscript

//============================================================================
// CK ISKM RENDERER — AUTOMATION TEST: PER-PROXY MORPH TARGETS
//============================================================================
//
// Verifies the per-proxy morph-target capability (Phase 1b of the
// character-customizer port):
//   1. Request_SetMorphTarget(name, 1.0) -> Get_MorphTarget (recorded value)
//      and Get_MorphTargetWeight (live SKMC curve) both read back 1.0.
//   2. Request_ClearMorphTargets -> both read back 0.
//   3. POOL HYGIENE (load-bearing): with a morph still set, destroying the
//      proxy entity returns its SKMC to the renderer pool (LIFO). A second
//      proxy created against the same renderer borrows the SAME SKMC and must
//      see a zero morph curve — no leak across borrowers.
//
// Morph name: queried from the test mesh at runtime (GetAllMorphTargetNames).
// If the mesh has no morph targets, a synthetic name is used — the engine
// stores morph curves by name without validating against the mesh
// (MorphTargetCurves map), so the request/state/pool path is fully exercised
// either way; only the visual deformation needs a real morph.
//
// Skip condition (mirrors CustomDataSuccess): missing wrapper/demo assets ->
// FinishSuccess without asserting.
//
//============================================================================

class UCk_AutoTest_IskmRenderer_MorphTargets : UCk_AutoTest_Base
{
    private FCk_Handle _TestEntity;
    private FCk_Handle _ChildA;
    private FCk_Handle _ChildB;
    private FCk_Handle_IskmRenderer _Renderer;
    private FCk_Handle_IskmProxy _ProxyA;
    private FCk_Handle_IskmProxy _ProxyB;
    private FName _MorphName;
    private int32 _Phase = 0;
    private int32 _TicksInPhase = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        UCk_IskmRenderer_Data RendererData = iskm_assets::RendererData_Demo();
        if (ck::Is_NOT_Valid(RendererData)) { FinishSuccess(); return; }

        _MorphName = n"Ck_TestMorph";
        USkeletalMesh TestMesh = assets::load::SKM_Manny_Simple();
        if (ck::IsValid(TestMesh))
        {
            TArray<FString> MorphNames = TestMesh.GetAllMorphTargetNames();
            if (MorphNames.Num() > 0)
            {
                _MorphName = FName(MorphNames[0]);
            }
        }

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
            // Poll until ProxyA's Setup has landed (SKMC acquired + mesh set).
            if (utils_iskm_proxy::Get_Material(_ProxyA, int32(0)) == nullptr) { return; }

            Assert_True(utils_iskm_proxy::Get_MorphTarget(_ProxyA, _MorphName) == 0.0f,
                "A fresh proxy must report 0 for an unset morph target");

            utils_iskm_proxy::Request_SetMorphTarget(_ProxyA, _MorphName, 1.0f);
            _Phase = 1;
            _TicksInPhase = 0;
        }
        else if (_Phase == 1 && _TicksInPhase >= 2)
        {
            Assert_True(utils_iskm_proxy::Get_MorphTarget(_ProxyA, _MorphName) == 1.0f,
                "Get_MorphTarget should return the value set via Request_SetMorphTarget");
            Assert_True(utils_iskm_proxy::Get_MorphTargetWeight(_ProxyA, _MorphName) == 1.0f,
                "Get_MorphTargetWeight should reflect the applied curve on the base SKMC");

            utils_iskm_proxy::Request_ClearMorphTargets(_ProxyA);
            _Phase = 2;
            _TicksInPhase = 0;
        }
        else if (_Phase == 2 && _TicksInPhase >= 2)
        {
            Assert_True(utils_iskm_proxy::Get_MorphTarget(_ProxyA, _MorphName) == 0.0f,
                "Get_MorphTarget should return 0 after Request_ClearMorphTargets");
            Assert_True(utils_iskm_proxy::Get_MorphTargetWeight(_ProxyA, _MorphName) == 0.0f,
                "Get_MorphTargetWeight should return 0 after Request_ClearMorphTargets");

            // Re-set so a live curve exists when the proxy is destroyed — the
            // pool round-trip below must NOT carry it to the next borrower.
            utils_iskm_proxy::Request_SetMorphTarget(_ProxyA, _MorphName, 1.0f);
            _Phase = 3;
            _TicksInPhase = 0;
        }
        else if (_Phase == 3 && _TicksInPhase >= 2)
        {
            Assert_True(utils_iskm_proxy::Get_MorphTargetWeight(_ProxyA, _MorphName) == 1.0f,
                "Morph curve should be live again before the pool round-trip");

            // Return ProxyA's SKMC to the renderer pool by destroying its entity.
            auto ChildA = _ChildA;
            utils_entity_lifetime::Request_DestroyEntity(ChildA);
            _Phase = 4;
            _TicksInPhase = 0;
        }
        else if (_Phase == 4 && _TicksInPhase >= 2)
        {
            // The pool is LIFO and ProxyA's SKMC is the only released component,
            // so ProxyB borrows the SAME SKMC.
            auto LocalHandle = _TestEntity;
            auto ChildB = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
            auto Params = FCk_Fragment_IskmProxy_ParamsData(_Renderer, FTransform::Identity);
            _ProxyB = utils_iskm_proxy::Add(ChildB, Params);
            _ChildB = ChildB;
            _Phase = 5;
            _TicksInPhase = 0;
        }
        else if (_Phase == 5)
        {
            // Poll until ProxyB's Setup has landed.
            if (utils_iskm_proxy::Get_Material(_ProxyB, int32(0)) == nullptr) { return; }

            Assert_True(utils_iskm_proxy::Get_MorphTarget(_ProxyB, _MorphName) == 0.0f,
                "A fresh proxy on the recycled SKMC must report no recorded morph target");
            Assert_True(utils_iskm_proxy::Get_MorphTargetWeight(_ProxyB, _MorphName) == 0.0f,
                "POOL LEAK: the recycled SKMC must come back with no morph curve set");
            FinishSuccess();
        }
    }
}

class ACk_AutoTest_IskmRenderer_MorphTargets_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_IskmRenderer_MorphTargets;
    default _TimeoutSeconds = 10.0f;
}
