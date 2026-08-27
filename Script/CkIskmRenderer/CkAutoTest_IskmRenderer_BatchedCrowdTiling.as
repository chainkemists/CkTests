// Language=angelscript

//============================================================================
// CK ISKM RENDERER - AUTOMATION TEST: PLAN-2 PHASE 4b SPATIAL TILE CROWD
//============================================================================
//
// Spawns a scattered crowd and confirms it partitions into MORE THAN ONE tile
// cluster - i.e. the batched crowd is spatially partitioned (each tile is its own
// GPUScene proxy with tight bounds for per-tile frustum + per-instance occlusion
// culling), not one giant aggregate proxy.
//
// Verifies the manager bookkeeping (instance count + tile count) on the game thread.
// Under --no-nullrhi it also stands up the per-tile GPU proxies without crashing.
// NOT covered (needs a human with RHI): that the culled pixels are correct.
//============================================================================

class UCk_AutoTest_IskmRenderer_BatchedCrowdTiling : UCk_AutoTest_Base
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

        UCk_Utils_IskmAnimCollection_UE::Build_BakedPoseData(Collection);
        Assert_True(UCk_Utils_IskmAnimCollection_UE::Get_IsBaked(Collection),
            "Collection should bake before spawning a crowd");

        // 100 instances over a ~8000cm square (+/-4000), partitioned into 2000cm tiles -> multiple tiles.
        // WorldContext is auto-injected in AngelScript.
        auto BaseXf = FTransform();
        auto Crowd = UCk_Utils_IskmBatched_UE::Debug_SpawnScatteredCrowd(Collection, BaseXf, 100, 4000.0f, 2000.0f, 0, 1.0f);

        Assert_True(ck::IsValid(Crowd), "Debug_SpawnScatteredCrowd should return a valid crowd actor");
        Assert_Equals_Int(UCk_Utils_IskmBatched_UE::Get_CrowdInstanceCount(Crowd), 100,
            "The crowd should hold all 100 instances");
        Assert_True(UCk_Utils_IskmBatched_UE::Get_CrowdTileCount(Crowd) > 1,
            "A crowd scattered over ~8000cm with 2000cm tiles should occupy more than one tile");

        FinishSuccess();
    }
}

class ACk_AutoTest_IskmRenderer_BatchedCrowdTiling_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_IskmRenderer_BatchedCrowdTiling;
    default _TimeoutSeconds = 15.0f;
}
