// Language=angelscript

//============================================================================
// CK ISKM RENDERER STRESS GYM - one-station EntityScript
//============================================================================
//
// Shared by `IskmRenderer Stress (Static 500)` and `IskmRenderer Stress
// (Moving 500)`. The two stress gyms differ only in the `Moving` spawn-param
// they pass - Static skips the OnTick entirely, Moving drives each proxy on
// a small per-proxy circular orbit via entity-transform updates.
//
// Animation: all proxies are in Sequence mode (no ABP_Unarmed opt-in). Each
// proxy plays a random looping sequence drawn from the AnimCollection,
// jittered +/-15% on PlayRate so the herd never visually syncs.
//
// Moving variant: per-proxy { Center, Radius, Period, Phase } is sampled at
// construction and never mutated. OnTick computes one full FTransform per
// proxy and issues ONE Request_SetTransform (single-call rule per
// feedback_scenenode_helpers.md).
//
//============================================================================

// AS top-level free functions aren't visible cross-file (only namespaced
// symbols are), so duplicate the two small helpers from
// CkIskmRenderer_GymStation.as locally with distinct names.
UCk_IskmRenderer_Data IskmGymStress_LoadRendererData()
{
    return iskm_assets::RendererData_Demo();
}

void IskmGymStress_PrintMissingContent(FString InStationName)
{
    Print(f"[IskmRenderer Gym/{InStationName}] iskm_assets::RendererData_Demo() invalid - registry may need regeneration.", 10.0f);
}

USTRUCT()
struct FCk_IskmStress_Orbit
{
    UPROPERTY()
    FVector Center = FVector::ZeroVector;

    UPROPERTY()
    float Radius = 0.0f;

    UPROPERTY()
    float Period = 0.0f;

    UPROPERTY()
    float Phase = 0.0f;
}

class UCk_EntityScript_IskmRendererGym_StressArmy : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    UPROPERTY(ExposeOnSpawn)
    int32 Count = 500;

    UPROPERTY(ExposeOnSpawn)
    bool Moving = false;

    private TArray<FCk_Handle_Transform> _ProxyTransforms;
    private TArray<FCk_IskmStress_Orbit> _Orbits;
    private float _Elapsed = 0.0f;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        InHandle.Set_DebugName(n"StressArmy");
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

        auto RendererData = IskmGymStress_LoadRendererData();
        if (ck::Is_NOT_Valid(RendererData))
        {
            IskmGymStress_PrintMissingContent("StressArmy");
            return ECk_EntityScript_ConstructionFlow::Finished;
        }
        auto Renderer = utils_iskm_renderer::Add(InHandle, RendererData);

        // Sequence pool. Cached once; reused per proxy.
        UAnimSequenceBase Seq_Idle = assets::load::MM_Idle();
        UAnimSequenceBase Seq_Walk = assets::load::MF_Unarmed_Walk_Fwd();
        UAnimSequenceBase Seq_Jog  = assets::load::MF_Unarmed_Jog_Fwd();

        // Grid layout: roughly square, biased to fit the existing 4000x4000 floor.
        // X grows in -X only (away from the station's back wall, toward the player
        // camera) so the grid never intersects the station. Y stays centered.
        const int32 Cols = 23;
        const int32 Rows = 22;
        const float32 Spacing = 80.0f;
        const float32 ColCenter = float32(Cols) * 0.5f;
        const int32 Total = (Count < Rows * Cols) ? Count : (Rows * Cols);

        int32 Spawned = 0;
        for (int32 Row = 0; Row < Rows; ++Row)
        {
            if (Spawned >= Total) { break; }
            for (int32 Col = 0; Col < Cols; ++Col)
            {
                if (Spawned >= Total) { break; }

                const auto Offset = FVector(
                    float32(Row) * -Spacing,
                    (float32(Col) - ColCenter) * Spacing,
                    0.0f);
                auto SpawnXf = InitialTransform;
                SpawnXf.AddToTranslation(Offset);

                auto Entity = InHandle.Request_CreateEntity();
                auto SoldierName = FName(f"Soldier_{Spawned}");
                Entity.Set_DebugName(SoldierName);
                auto EntityTransform = utils_transform::Add(Entity, SpawnXf, ECk_Replication::DoesNotReplicate);
                auto Proxy = utils_iskm_proxy::Add(EntityTransform, FCk_Fragment_IskmProxy_ParamsData(Renderer, SpawnXf));

                // Random sequence pick. Moving variant drops idle (sliding-foot artifact).
                UAnimSequenceBase ChosenSeq;
                if (Moving)
                {
                    const int32 Pick = Math::RandRange(0, 1);
                    ChosenSeq = (Pick == 0) ? Seq_Walk : Seq_Jog;
                }
                else
                {
                    const int32 Pick = Math::RandRange(0, 2);
                    if      (Pick == 0) { ChosenSeq = Seq_Idle; }
                    else if (Pick == 1) { ChosenSeq = Seq_Walk; }
                    else                { ChosenSeq = Seq_Jog;  }
                }

                if (ck::IsValid(ChosenSeq))
                {
                    auto PlayReq = FCk_Request_IskmProxy_PlayAnimation(ChosenSeq);
                    PlayReq.Set_Loop(true);
                    PlayReq.Set_PlayRate(Math::RandRange(0.85f, 1.15f));
                    utils_iskm_proxy::Request_PlayAnimation(Proxy, PlayReq);
                }

                _ProxyTransforms.Add(EntityTransform);

                if (Moving)
                {
                    FCk_IskmStress_Orbit Orbit;
                    Orbit.Center = SpawnXf.GetTranslation();
                    Orbit.Radius = Math::RandRange(50.0f, 120.0f);
                    Orbit.Period = Math::RandRange(4.0f, 8.0f);
                    Orbit.Phase  = Math::RandRange(0.0f, float(2.0 * Math::PI));
                    _Orbits.Add(Orbit);
                }

                ++Spawned;
            }
        }

        if (Moving)
        {
            utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnTick"));
        }

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        _Elapsed += float(InDeltaT.Get_Seconds());

        const int32 Num = _ProxyTransforms.Num();
        for (int32 i = 0; i < Num; ++i)
        {
            auto TransformHandle = _ProxyTransforms[i];
            if (ck::Is_NOT_Valid(TransformHandle)) { continue; }

            const auto Orbit = _Orbits[i];
            const float Theta = (float(2.0 * Math::PI) * _Elapsed / Orbit.Period) + Orbit.Phase;
            const float CosT = float(Math::Cos(Theta));
            const float SinT = float(Math::Sin(Theta));

            const auto Pos = Orbit.Center + FVector(CosT * Orbit.Radius, SinT * Orbit.Radius, 0.0f);

            // Tangent direction: derivative of (cos, sin) is (-sin, cos). Yaw faces along motion.
            // Math::Atan2 may return radians; convert via Math::RadiansToDegrees if available, else
            // fall back to a fixed yaw (no facing rotation) - purely cosmetic per the design spec.
            FRotator Rot = FRotator::ZeroRotator;
            const float YawRad = float(Math::Atan2(CosT, -SinT));
            Rot.Yaw = YawRad * (180.0f / float(Math::PI));

            FTransform NewXf;
            NewXf.SetLocation(Pos);
            NewXf.SetRotation(FQuat(Rot));
            NewXf.SetScale3D(FVector::OneVector);

            auto Req = FCk_Request_Transform_SetTransform(NewXf);
            utils_transform::Request_SetTransform(TransformHandle, Req);
        }
    }
}
