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

        // 144 GPU-skinned instances scattered over a ~6000cm square in front of the panel (player camera is -X),
        // spatially partitioned into 2000cm tile clusters — each tile is its own GPUScene proxy with tight bounds
        // (per-tile frustum + per-instance occlusion culling). SequenceIndex -1 = cycle idle/walk/jog per instance
        // so the crowd is visibly alive and the per-instance (out-of-phase, independent) animation is obvious — idle
        // alone is too subtle to read. WorldContext is auto-injected in AS.
        auto SpawnBase = InitialTransform;
        SpawnBase.AddToTranslation(FVector(-3000.0f, 0.0f, 0.0f));
        UCk_Utils_IskmBatched_UE::Debug_SpawnScatteredCrowd(Collection, SpawnBase, 144, 3000.0f, 2000.0f, -1, 1.0f);

        return ECk_EntityScript_ConstructionFlow::Finished;
    }
}

// ====================================================================================================================
// Station — GPU <-> SKMC Flip: distance-LOD routing (Phase 5).
//
// A small batched crowd. Each tick, the members within PromoteDist of the player flip OUT of the batched tile
// (Set_CrowdMemberVisible false) and are replaced by a real per-SKMC proxy (Plan-1) at the same transform — so
// they can ragdoll and play montages. When a promoted member moves beyond DemoteDist, its SKMC proxy is destroyed
// (SKMC returns to the Plan-1 pool automatically on EndPlay) and it returns to batched rendering. Hysteresis
// (700/1100) prevents thrash; MaxPromoted caps concurrent SKMCs so the pool stays small.
// ====================================================================================================================

class UCk_EntityScript_IskmRendererBatched_Flip : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    private ACk_Iskm_BatchedCrowd_Actor _Crowd;
    private FCk_Handle _SelfHandle;
    private FCk_Handle_IskmRenderer _Renderer;
    private bool _RendererValid = false;

    // Per-member flip state (parallel to crowd member indices).
    private TArray<bool>       _Promoted;
    private TArray<FCk_Handle> _ProxyEntities;

    const float PromoteDist = 700.0f;
    const float DemoteDist  = 1100.0f;
    const int32 MaxPromoted = 6;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        InHandle.Set_DebugName(n"BatchedFlip");
        _SelfHandle = InHandle;

        auto Collection = iskm_assets::AnimCollection_Demo();
        if (ck::Is_NOT_Valid(Collection))
        {
            Print("[IskmBatched Gym/Flip] AnimCollection_Demo() invalid — registry may need regeneration.", 10.0f);
            return ECk_EntityScript_ConstructionFlow::Finished;
        }
        UCk_Utils_IskmAnimCollection_UE::Build_BakedPoseData(Collection);

        // Plan-1 renderer for the per-SKMC stand-ins. If unset, the crowd still renders batched; promotion is skipped.
        auto RendererData = iskm_assets::RendererData_Demo();
        if (ck::IsValid(RendererData))
        {
            _Renderer = utils_iskm_renderer::Add(InHandle, RendererData);
            _RendererValid = true;
        }

        // Small walkable crowd in front of the panel (player camera is -X).
        auto SpawnBase = InitialTransform;
        SpawnBase.AddToTranslation(FVector(-2000.0f, 0.0f, 0.0f));
        _Crowd = UCk_Utils_IskmBatched_UE::Debug_SpawnScatteredCrowd(Collection, SpawnBase, 36, 1200.0f, 1500.0f, 0, 1.0f);

        if (ck::IsValid(_Crowd))
        {
            const int32 Count = UCk_Utils_IskmBatched_UE::Get_CrowdMemberCount(_Crowd);
            _Promoted.SetNum(Count);
            _ProxyEntities.SetNum(Count);
            for (int32 i = 0; i < Count; ++i)
            {
                _Promoted[i] = false;
            }
        }

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnTick"));
        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (ck::Is_NOT_Valid(_Crowd) || !_RendererValid) { return; }

        auto Pawn = Gameplay::GetPlayerPawn(0);
        if (!IsValid(Pawn)) { return; }
        const FVector PlayerLoc = Pawn.GetActorLocation();

        const int32 Count = UCk_Utils_IskmBatched_UE::Get_CrowdMemberCount(_Crowd);

        int32 PromotedCount = 0;
        for (int32 i = 0; i < Count; ++i)
        {
            if (_Promoted[i]) { PromotedCount++; }
        }

        for (int32 i = 0; i < Count; ++i)
        {
            const FTransform MemberXf = UCk_Utils_IskmBatched_UE::Get_CrowdMemberTransform(_Crowd, i);
            const float Dist = (MemberXf.GetLocation() - PlayerLoc).Size();

            if (!_Promoted[i] && Dist < PromoteDist && PromotedCount < MaxPromoted)
            {
                Promote(i, MemberXf);
                PromotedCount++;
            }
            else if (_Promoted[i] && Dist > DemoteDist)
            {
                Demote(i);
                PromotedCount--;
            }
        }
    }

    // Hide the batched member; stand up a per-SKMC proxy at its transform and RAGDOLL it. Against the idle batched
    // backdrop the flip is unmistakable — the nearest instances become real per-SKMC proxies and collapse — and it
    // directly demonstrates the SKMC-only capability (ragdoll) the batched path can't do.
    private void Promote(int32 InIndex, FTransform InMemberXf)
    {
        UCk_Utils_IskmBatched_UE::Set_CrowdMemberVisible(_Crowd, InIndex, false);

        auto Entity = _SelfHandle.Request_CreateEntity();
        auto Transform = utils_transform::Add(Entity, InMemberXf, ECk_Replication::DoesNotReplicate);
        auto Proxy = utils_iskm_proxy::Add(Transform, FCk_Fragment_IskmProxy_ParamsData(_Renderer, InMemberXf));

        FCk_Request_IskmProxy_BeginRagdoll RagdollReq;
        utils_iskm_proxy::Request_BeginRagdoll(Proxy, RagdollReq);

        _ProxyEntities[InIndex] = Entity;
        _Promoted[InIndex] = true;
    }

    // Destroy the per-SKMC proxy (SKMC returns to the Plan-1 pool on EndPlay); return the member to batched.
    private void Demote(int32 InIndex)
    {
        if (ck::IsValid(_ProxyEntities[InIndex]))
        {
            utils_entity_lifetime::Request_DestroyEntity(_ProxyEntities[InIndex]);
        }
        UCk_Utils_IskmBatched_UE::Set_CrowdMemberVisible(_Crowd, InIndex, true);
        _Promoted[InIndex] = false;
    }
}
