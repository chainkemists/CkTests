// Language=angelscript

//============================================================================
// CK USF OUTLINE GYM - ENTITY-OUTLINE stations (ISM / ISKM Plan-1 / Batched / Cascade)
//============================================================================
//
// Demonstrates "outline this ENTITY" across every renderer (CkUsf/the entity-outlines design note):
//   - ISM:     a row of IsmProxy cube entities sharing ONE ISM component; only the outlined
//              entities' instances silhouette (shadow-ISM mechanism - per-instance outlines).
//   - ISKM:    three Plan-1 skeletal proxies; the middle one is outlined (custom depth on its
//              pooled SKMC).
//   - Batched: a small Plan-2 GPU-skinned crowd; a few members outlined by index (highlight
//              cluster tracks the skinned pose). THE visual verification for the batched
//              custom-depth path - flagged as unverified-until-PIE in the design doc.
//   - Cascade: a parent entity whose visuals live on child IsmProxy entities; one entity-level
//              Request_ApplyOutline(EntityAndDependents) outlines them all.
//============================================================================

// ====================================================================================================================
// Station - ISM: 5 cube proxies in one ISM; entities 1 and 3 outlined (different presets).
// ====================================================================================================================

class UCk_EntityScript_UsfOutlineGym_Ism : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        InHandle.Set_DebugName(n"UsfOutlineIsm");

        auto RendererData = usf_outline_assets::EntityRenderer(InHandle);
        if (ck::Is_NOT_Valid(RendererData))
        {
            Print("[UsfOutline Gym/Ism] entity renderer asset invalid", 10.0f);
            return ECk_EntityScript_ConstructionFlow::Finished;
        }

        // Row of 5 cubes toward the player (world -X), raised off the floor.
        for (int32 i = 0; i < 5; ++i)
        {
            auto Xf = FTransform(FRotator::ZeroRotator,
                InitialTransform.GetLocation() + FVector(-250.0f, (i - 2) * 200.0f, 100.0f),
                FVector(0.5f, 0.5f, 0.5f));

            auto Entity = InHandle.Request_CreateEntity();
            auto Transform = utils_transform::Add(Entity, Xf, ECk_Replication::DoesNotReplicate);
            utils_ism_proxy::Add(Transform, FCk_Fragment_IsmProxy_ParamsData(RendererData));

            if (i == 1)
            { UCk_Utils_Usf_Outline_UE::Request_ApplyOutline(Entity, CkUsf::DA_Outline_Interactable, ECk_Usf_OutlineScope::EntityOnly); }
            else if (i == 3)
            { UCk_Utils_Usf_Outline_UE::Request_ApplyOutline(Entity, CkUsf::DA_Outline_SeeThrough, ECk_Usf_OutlineScope::EntityOnly); }
        }

        return ECk_EntityScript_ConstructionFlow::Finished;
    }
}

// ====================================================================================================================
// Station - ISKM Plan-1: 3 skeletal proxies; the middle one outlined.
// ====================================================================================================================

class UCk_EntityScript_UsfOutlineGym_Iskm : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        InHandle.Set_DebugName(n"UsfOutlineIskm");

        auto RendererData = iskm_assets::RendererData_Demo();
        if (ck::Is_NOT_Valid(RendererData))
        {
            Print("[UsfOutline Gym/Iskm] RendererData_Demo() invalid - registry may need regeneration.", 10.0f);
            return ECk_EntityScript_ConstructionFlow::Finished;
        }

        auto Renderer = utils_iskm_renderer::Add(InHandle, RendererData);

        for (int32 i = 0; i < 3; ++i)
        {
            auto Xf = FTransform(FRotator(0.0f, 180.0f, 0.0f),
                InitialTransform.GetLocation() + FVector(-300.0f, (i - 1) * 200.0f, 0.0f),
                FVector::OneVector);

            auto Entity = InHandle.Request_CreateEntity();
            auto Transform = utils_transform::Add(Entity, Xf, ECk_Replication::DoesNotReplicate);
            utils_iskm_proxy::Add(Transform, FCk_Fragment_IskmProxy_ParamsData(Renderer, Xf));

            if (i == 1)
            { UCk_Utils_Usf_Outline_UE::Request_ApplyOutline(Entity, CkUsf::DA_Outline_MaskedObjective, ECk_Usf_OutlineScope::EntityOnly); }
        }

        return ECk_EntityScript_ConstructionFlow::Finished;
    }
}

// ====================================================================================================================
// Station - Batched (Plan-2): small GPU-skinned crowd; members 0..2 outlined by index.
// ====================================================================================================================

class UCk_EntityScript_UsfOutlineGym_Batched : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        InHandle.Set_DebugName(n"UsfOutlineBatched");

        auto Collection = iskm_assets::AnimCollection_Demo();
        if (ck::Is_NOT_Valid(Collection))
        {
            Print("[UsfOutline Gym/Batched] AnimCollection_Demo() invalid - registry may need regeneration.", 10.0f);
            return ECk_EntityScript_ConstructionFlow::Finished;
        }
        UCk_Utils_IskmAnimCollection_UE::Build_BakedPoseData(Collection);

        // Tight scatter (+/-250uu) close to the panel so the crowd visibly belongs to THIS station.
        auto SpawnBase = InitialTransform;
        SpawnBase.AddToTranslation(FVector(-500.0f, 0.0f, 0.0f));
        auto Crowd = UCk_Utils_IskmBatched_UE::Debug_SpawnScatteredCrowd(Collection, SpawnBase, 16, 250.0f, 2000.0f, 0, 1.0f);
        if (ck::Is_NOT_Valid(Crowd))
        { return ECk_EntityScript_ConstructionFlow::Finished; }

        // Outline three members with two different presets - silhouettes must track the skinned pose.
        UCk_Utils_IskmBatched_UE::Set_CrowdMemberOutline(Crowd, 0, CkUsf::DA_Outline_Interactable);
        UCk_Utils_IskmBatched_UE::Set_CrowdMemberOutline(Crowd, 1, CkUsf::DA_Outline_Interactable);
        UCk_Utils_IskmBatched_UE::Set_CrowdMemberOutline(Crowd, 2, CkUsf::DA_Outline_SeeThrough);

        return ECk_EntityScript_ConstructionFlow::Finished;
    }
}

// ====================================================================================================================
// Station - Cascade: parent entity with 3 child cube proxies; one EntityAndDependents request.
// ====================================================================================================================

class UCk_EntityScript_UsfOutlineGym_Cascade : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        InHandle.Set_DebugName(n"UsfOutlineCascade");

        auto RendererData = usf_outline_assets::EntityRenderer(InHandle);
        if (ck::Is_NOT_Valid(RendererData))
        {
            Print("[UsfOutline Gym/Cascade] entity renderer asset invalid", 10.0f);
            return ECk_EntityScript_ConstructionFlow::Finished;
        }

        // Little "snowman" arrangement of child proxies under one parent entity.
        auto Parent = InHandle.Request_CreateEntity();

        for (int32 i = 0; i < 3; ++i)
        {
            const float Scale = 0.6f - 0.15f * i;
            auto Xf = FTransform(FRotator::ZeroRotator,
                InitialTransform.GetLocation() + FVector(-250.0f, 0.0f, 60.0f + i * 130.0f),
                FVector(Scale, Scale, Scale));

            auto Entity = Parent.Request_CreateEntity();
            auto Transform = utils_transform::Add(Entity, Xf, ECk_Replication::DoesNotReplicate);
            utils_ism_proxy::Add(Transform, FCk_Fragment_IsmProxy_ParamsData(RendererData));
        }

        // ONE request on the parent outlines every dependent's renderable.
        UCk_Utils_Usf_Outline_UE::Request_ApplyOutline(Parent, CkUsf::DA_Outline_Interactable,
            ECk_Usf_OutlineScope::EntityAndDependents);

        return ECk_EntityScript_ConstructionFlow::Finished;
    }
}

// ====================================================================================================================
// Station - VAT: 3 vertex-animated proxies sharing ONE ISM; the outer two outlined, middle one the control.
// ====================================================================================================================
//
// The ANIMATED-silhouette check. A VatProxy renders through an IsmProxy composed on the same entity, and VAT
// deforms the mesh entirely inside the material's World Position Offset - it samples a baked pose texture using
// the 12 per-instance custom-data floats. So the silhouette is only correct if the custom-depth shadow ISM carries
// the SAME material AND the same custom data as the visible instance. If it doesn't, the outlined figures
// silhouette their bind pose while the mesh walks. The un-outlined middle figure is the comparison control:
// all three must be in identical poses at all times, outline or not.
//
// Uses the VAT gym's collection contract (CkVatGym_Shared.as): "AUTO" self-bakes a Bone-mode Mannequin
// collection in memory at PIE start. Editor-only - a cooked run resolves nothing and the station early-outs.

class UCk_EntityScript_UsfOutlineGym_Vat : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        InHandle.Set_DebugName(n"UsfOutlineVat");

        auto Collection = vat_gym::ResolveCollection(vat_gym::DefaultCollectionPath);
        if (ck::Is_NOT_Valid(Collection) || Collection.Get_BakedData().Get_IsBaked() == false)
        {
            Print("[UsfOutline Gym/Vat] no baked VAT collection (self-bake failed?)", 10.0f);
            return ECk_EntityScript_ConstructionFlow::Finished;
        }

        auto BakedClips = Collection.Get_BakedData().Get_BakedClips();
        if (BakedClips.Num() == 0)
        {
            Print("[UsfOutline Gym/Vat] VAT collection has no baked clips", 10.0f);
            return ECk_EntityScript_ConstructionFlow::Finished;
        }

        // The last baked clip is the most locomotive one (Idle, Walk, Jog): a silhouette stuck on the bind
        // pose only reads as wrong when the limbs actually travel.
        auto ClipName = BakedClips[BakedClips.Num() - 1].Get_Name();

        for (int32 i = 0; i < 3; ++i)
        {
            auto Xf = FTransform(FRotator(0.0f, 180.0f, 0.0f),
                InitialTransform.GetLocation() + FVector(-300.0f, (i - 1) * 200.0f, 0.0f),
                FVector::OneVector);

            auto Entity = InHandle.Request_CreateEntity();
            auto Transform = utils_transform::Add(Entity, Xf, ECk_Replication::DoesNotReplicate);

            auto Params = FCk_Fragment_VatProxy_ParamsData(Collection);
            Params.Set_InitialClipName(ClipName);
            utils_vat_proxy::Add(Transform, Params);

            if (i == 0)
            { UCk_Utils_Usf_Outline_UE::Request_ApplyOutline(Entity, CkUsf::DA_Outline_Interactable, ECk_Usf_OutlineScope::EntityOnly); }
            else if (i == 2)
            { UCk_Utils_Usf_Outline_UE::Request_ApplyOutline(Entity, CkUsf::DA_Outline_SeeThrough, ECk_Usf_OutlineScope::EntityOnly); }
        }

        return ECk_EntityScript_ConstructionFlow::Finished;
    }
}
