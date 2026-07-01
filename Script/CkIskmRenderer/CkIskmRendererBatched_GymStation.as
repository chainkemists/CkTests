// Language=angelscript

//============================================================================
// CK ISKM RENDERER — BATCHED GYM stations + tags
//============================================================================
//
// Stations for the dedicated batched-renderer gym. Uses iskm_assets::AnimCollection_Demo()
// (AS-authored, same as the IskmRenderer gym) and the batched-cluster utils.
//============================================================================

namespace Ck
{
    asset IskmRendererBatchedGym_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"Gym.IskmBatched.Crowd");
        GameplayTags.Add(n"Gym.IskmBatched.Flip");
    }
}

// ====================================================================================================================
// Station — Batched Crowd: one large GPU-skinned crowd through GPUScene cluster proxies.
// ====================================================================================================================

class UCk_EntityScript_IskmRendererBatched_Crowd : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        InHandle.Set_DebugName(n"BatchedCrowd");

        auto Collection = iskm_assets::AnimCollection_Demo();
        if (ck::Is_NOT_Valid(Collection))
        {
            Print("[IskmBatched Gym/Crowd] AnimCollection_Demo() invalid — registry may need regeneration.", 10.0f);
            return ECk_EntityScript_ConstructionFlow::Finished;
        }

        UCk_Utils_IskmAnimCollection_UE::Build_BakedPoseData(Collection);

        // 12x12 = 144 GPU-skinned instances, per-instance phase-offset looping, one GPUScene cluster.
        UCk_Utils_IskmBatched_UE::Debug_SpawnCluster(Collection, InitialTransform, 12, 150.0f, 0, 1.0f);

        return ECk_EntityScript_ConstructionFlow::Finished;
    }
}

// ====================================================================================================================
// Station — GPU <-> SKMC Flip: distance-LOD routing (Phase 5).
//
// STUB: currently spawns a batched crowd only. Once Phase 5 (distance-LOD routing + SKMC fallback)
// lands, this station will drive the manager so the instances nearest the player flip to per-SKMC
// proxies (Plan-1) for ragdoll/montage, then back to batched when they move away.
// ====================================================================================================================

class UCk_EntityScript_IskmRendererBatched_Flip : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        InHandle.Set_DebugName(n"BatchedFlip");

        auto Collection = iskm_assets::AnimCollection_Demo();
        if (ck::Is_NOT_Valid(Collection))
        {
            Print("[IskmBatched Gym/Flip] AnimCollection_Demo() invalid — registry may need regeneration.", 10.0f);
            return ECk_EntityScript_ConstructionFlow::Finished;
        }

        UCk_Utils_IskmAnimCollection_UE::Build_BakedPoseData(Collection);

        // Phase 5 will replace this with the distance-LOD crowd. For now a small batched grid stands in.
        UCk_Utils_IskmBatched_UE::Debug_SpawnCluster(Collection, InitialTransform, 6, 150.0f, 0, 1.0f);

        return ECk_EntityScript_ConstructionFlow::Finished;
    }
}
