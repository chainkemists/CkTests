// Language=angelscript

//============================================================================
// CK VISUAL LOD GYM — arbitration station + tags
//============================================================================
//
// One station: a 40-member orbiting crowd managed by a CkVisualLod arbiter with a
// deliberately small near budget (5). Walk toward the crowd and the nearest in-view
// members crossfade from batched rendering to real SKMC proxies; walk away and they
// dissolve back. Strafe along the crowd's edge to watch ranked preemption: a
// better-placed member takes the slot of the worst incumbent (rate-limited, with a
// distance margin so near-equals don't churn).
//
// NEW-BINDING RULE: CkVisualLod calls go through UCk_Utils_* classes directly — the
// generated utils_* alias layer regenerates AFTER script compile, so a fresh
// feature's aliases don't resolve on the first boot (same rule the BB flip
// processors followed).
//============================================================================

namespace Ck
{
    asset VisualLodGym_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"Gym.VisualLod.Arbitration");
        GameplayTags.Add(n"Gym.VisualLod.Domain");
    }
}

class UCk_EntityScript_VisualLodGym_Arbitration : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_VisualLodArbiter _Arbiter;

    // Per-member orbit drive (the members' transforms are the arbiter's rank input).
    private TArray<FCk_Handle> _Members;
    private TArray<FVector> _OrbitCenters;
    private TArray<float>   _OrbitRadii;
    private TArray<float>   _OrbitPeriods;
    private TArray<float>   _OrbitPhases;
    private float _Elapsed = 0.0f;

    const int32 MemberCount = 40;
    const float AreaExtent  = 1600.0f;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        InHandle.Set_DebugName(n"VisualLodArbitration");
        _SelfHandle = InHandle;

        auto Config = visual_lod_gym_assets::ArbiterConfig();
        if (ck::Is_NOT_Valid(Config))
        {
            Print("[VisualLod Gym] ArbiterConfig() invalid — registry may need regeneration.", 10.0f);
            return ECk_EntityScript_ConstructionFlow::Finished;
        }

        // The arbiter entity. No observer is wired on purpose: the gym exercises the
        // local-view discovery fallback (TryGet_LocalViewInfo -> the PIE player's camera).
        auto ArbiterEntity = _SelfHandle.Request_CreateEntity();
        _Arbiter = UCk_Utils_VisualLodArbiter_UE::Add(ArbiterEntity,
            FCk_Fragment_VisualLodArbiter_ParamsData(Config));

        const auto DomainTag = utils_gameplay_tag::ResolveGameplayTag(n"Gym.VisualLod.Domain");
        auto RendererData = iskm_assets::RendererData_Demo();

        // Members scattered in front of the panel (player camera is -X), each on a small orbit
        // so far-member transform pushes and the walk far-anim are always live.
        auto SpawnBase = InitialTransform;
        SpawnBase.AddToTranslation(FVector(-AreaExtent - 800.0f, 0.0f, 0.0f));

        for (int32 i = 0; i < MemberCount; ++i)
        {
            auto MemberXf = SpawnBase;
            MemberXf.AddToTranslation(FVector(
                Math::RandRange(-AreaExtent, AreaExtent),
                Math::RandRange(-AreaExtent, AreaExtent),
                0.0f));

            auto Member = _SelfHandle.Request_CreateEntity();
            auto Transform = utils_transform::Add(Member, MemberXf, ECk_Replication::DoesNotReplicate);

            auto MemberParams = FCk_Fragment_VisualLod_ParamsData(DomainTag);
            MemberParams.Set_Renderer(RendererData);

            // Fixed walk far-anim: the batched members visibly animate while orbiting
            // (SpeedDriven would read zero — the orbit drives transforms, not a velocity feature).
            auto FarAnim = FCk_VisualLod_FarAnim(ECk_VisualLod_FarAnimMode::Fixed);
            FarAnim.Set_FixedSequenceIndex(2);
            MemberParams.Set_InitialFarAnim(FarAnim);

            UCk_Utils_VisualLod_UE::Add(Member, MemberParams);

            _Members.Add(Member);
            _OrbitCenters.Add(MemberXf.GetTranslation());
            _OrbitRadii.Add(Math::RandRange(120.0f, 300.0f));
            _OrbitPeriods.Add(Math::RandRange(10.0f, 20.0f));
            _OrbitPhases.Add(Math::RandRange(0.0f, float(2.0 * Math::PI)));
        }

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnTick"));
        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        _Elapsed += float(InDeltaT.Get_Seconds());

        for (int32 i = 0; i < _Members.Num(); ++i)
        {
            if (ck::Is_NOT_Valid(_Members[i]))
            { continue; }

            auto Xf = _Members[i].As_Transform();
            if (ck::Is_NOT_Valid(Xf))
            { continue; }

            const float Theta = (float(2.0 * Math::PI) * _Elapsed / _OrbitPeriods[i]) + _OrbitPhases[i];
            const float CosT = float(Math::Cos(Theta));
            const float SinT = float(Math::Sin(Theta));

            const auto Pos = _OrbitCenters[i] + FVector(CosT * _OrbitRadii[i], SinT * _OrbitRadii[i], 0.0f);

            FRotator Rot = FRotator::ZeroRotator;
            Rot.Yaw = float(Math::Atan2(CosT, -SinT)) * (180.0f / float(Math::PI));

            FTransform NewXf;
            NewXf.SetLocation(Pos);
            NewXf.SetRotation(FQuat(Rot));
            NewXf.SetScale3D(FVector::OneVector);

            utils_transform::Request_SetTransform(Xf, NewXf);
        }
    }
}
