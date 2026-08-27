// Language=angelscript

//============================================================================
// CK ISKM RENDERER - AUTOMATION TEST: PLAN-2 PHASE 1 BATCHED CLUSTER LIFECYCLE
//============================================================================
//
// Plan-2 Phase 1 gate (CPU-verifiable slice). Spawns a batched cluster of
// baked-pose instances and confirms the game-thread lifecycle stands up
// without crashing: spawn -> Setup -> Set_Instances -> proxy creation path.
//
// Under -nullrhi (the default suite) the GPU proxy is not created (the app
// can't render), so this verifies the component/instance bookkeeping only.
// Run with --no-nullrhi to additionally exercise the render path: the baked
// SRV/uniform-buffer/vertex-factory upload, proxy creation, and - because the
// mannequin material's shader map then includes the batched vertex factory
// compilation of CkIskm_BatchedVertexFactory.ush. A shader-compile error or a
// render-thread crash there fails this test.
//
// NOT covered (requires a human with RHI): that the skinned pixels are correct.
//============================================================================

class UCk_AutoTest_IskmRenderer_BatchedClusterLifecycle : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Collection = iskm_assets::AnimCollection_Demo();
        if (ck::Is_NOT_Valid(Collection))
        {
            FinishFailure("iskm_assets::AnimCollection_Demo() invalid - registry may need regeneration.");
            return;
        }

        // Bake (CPU) so the chosen frame index is a real baked frame even under -nullrhi.
        UCk_Utils_IskmAnimCollection_UE::Build_BakedPoseData(Collection);
        Assert_True(UCk_Utils_IskmAnimCollection_UE::Get_IsBaked(Collection),
            "Collection should bake before spawning a batched cluster");

        // NOTE: the WorldContext param is stripped in AngelScript (meta=(WorldContext=...)); it is auto-injected.
        // 2x2 grid, all playing sequence 0 with independent phase; Rate defaults to 1 (animating). Under --no-nullrhi
        // this drives the per-frame instance update (proxy UpdateInstanceBuffer + FScene::PrimitiveUpdates).
        auto BaseXf = FTransform();
        auto Cluster = UCk_Utils_IskmBatched_UE::Debug_SpawnCluster(Collection, BaseXf, 2, 150.0f, 0);

        Assert_True(ck::IsValid(Cluster),
            "Debug_SpawnCluster should return a valid batched cluster component");
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_InstanceCount(Cluster), 4,
            "A 2x2 grid should create 4 batched instances");

        FinishSuccess();
    }
}

class ACk_AutoTest_IskmRenderer_BatchedClusterLifecycle_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_IskmRenderer_BatchedClusterLifecycle;
    default _TimeoutSeconds = 15.0f;
}
