// Language=angelscript

//============================================================================
// CK ISKM RENDERER GYM — Plan-2 batched station
//============================================================================
//
// BatchedArmy: a 10x10 crowd of batched GPU-skinned instances rendered through a
// SINGLE GPUScene cluster proxy (one FPrimitiveSceneProxy, GPU linear-blend
// skinning, per-instance independent looping animation), vs the per-SKMC
// SpawnArmy station's 5x5 = 25 real USkeletalMeshComponents.
//
// A/B: stand between the two stations and compare `stat rhi` / `stat scenerendering`
// (draw calls) and `stat unit` (frame time). 100 batched instances draw as a
// handful of instanced calls; the 25 per-SKMC proxies each cost a full skeletal
// draw + CPU pose eval.
//
// Uses UCk_Utils_IskmBatched_UE::Debug_SpawnCluster (the direct driver). The
// production entry point (UCk_Utils_IskmProxy_UE::Add + PoseSource routing) is a
// later phase — see CkIskmRenderer/CONTINUATION_PROMPT_Plan2.md.
//============================================================================

class UCk_EntityScript_IskmRendererGym_BatchedArmy : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        InHandle.Set_DebugName(n"BatchedArmy");

        auto Collection = iskm_assets::AnimCollection_Demo();
        if (ck::Is_NOT_Valid(Collection))
        {
            Print("[IskmRenderer Gym/BatchedArmy] AnimCollection_Demo() invalid — registry may need regeneration.", 10.0f);
            return ECk_EntityScript_ConstructionFlow::Finished;
        }

        // Bake (CPU) so the per-instance frame advance has real baked frames.
        UCk_Utils_IskmAnimCollection_UE::Build_BakedPoseData(Collection);

        // 10x10 batched crowd, all playing sequence 0 (idle) at rate 1 with a per-instance
        // phase offset so they animate out of sync. WorldContext is auto-injected in AS.
        UCk_Utils_IskmBatched_UE::Debug_SpawnCluster(Collection, InitialTransform, 10, 150.0f, 0, 1.0f);

        return ECk_EntityScript_ConstructionFlow::Finished;
    }
}
