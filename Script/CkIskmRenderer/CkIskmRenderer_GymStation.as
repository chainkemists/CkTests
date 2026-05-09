// Language=angelscript

//============================================================================
// CK ISKM RENDERER GYM — stations
//============================================================================
//
// Five demo stations exercising the public CkIskmRenderer API surface:
//   - SpawnArmy:    5x5 grid of sub-entities, each with its own IskmProxy
//   - OutfitSwap:   single proxy, periodic submesh attach/detach
//   - MontageBurst: single proxy, periodic montage trigger
//   - RagdollDemo:  single proxy, alternating Begin/End ragdoll
//   - CustomData:   single proxy, sin-wave custom data slot
//
// Content discovery: each station tries to load the demo renderer data via
// `utils_i_o::LoadAssetByName("/CkTests/CkIskmRenderer/Demo/RendererData_Demo")`.
// If the asset isn't present (Plan-1 default until the engineer authors content),
// the station prints an on-screen warning naming the missing asset path and
// skips the proxy creation. With content authored, the demo runs.
//
// Required assets (see the Plan-1 wrap-up notes):
//   /CkTests/CkIskmRenderer/Demo/RendererData_Demo  (UCk_IskmRenderer_Data)
//     -> _AnimCollection: ref to a UCk_IskmAnimCollection_Data with skeleton
//                         + DefaultMesh + at least one looping sequence
//     -> _Submeshes:     entries with Name "Hat" (or rename in OutfitSwap below)
//     -> _NumCustomDataFloat: >= 1 for the CustomData station
//
//============================================================================

const FString IskmGym_RendererDataPath = "/CkTests/CkIskmRenderer/Demo/RendererData_Demo";

UCk_IskmRenderer_Data IskmGym_LoadRendererData()
{
    auto Result = utils_i_o::LoadAssetByName(
        IskmGym_RendererDataPath,
        ECk_AssetSearchScope::Plugins,
        ECk_AssetSearchStrategy::ExactOnly);
    return Cast<UCk_IskmRenderer_Data>(Result._Asset);
}

void IskmGym_PrintMissingContent(FString InStationName)
{
    Print(f"[IskmRenderer Gym/{InStationName}] Missing content — author UCk_IskmRenderer_Data at {IskmGym_RendererDataPath}", 10.0f);
}

USTRUCT()
struct FCkIskmRenderer_GymStationSpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;
}

// ====================================================================================================================
// Station 1 — SpawnArmy: 5x5 grid of sub-entities, each with its own IskmProxy.
// ====================================================================================================================

class UCk_EntityScript_IskmRendererGym_SpawnArmy : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    private TArray<FCk_Handle_IskmProxy> _Proxies;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

        auto RendererData = IskmGym_LoadRendererData();
        if (ck::Is_NOT_Valid(RendererData))
        {
            IskmGym_PrintMissingContent("SpawnArmy");
            return ECk_EntityScript_ConstructionFlow::Finished;
        }
        auto Renderer = utils_iskm_renderer::Add(InHandle, RendererData);

        const int32 Rows = 5;
        const int32 Cols = 5;
        const float32 Spacing = 150.0f;
        const float32 ColCenter = float32(Cols) * 0.5f;

        for (int32 Row = 0; Row < Rows; ++Row)
        {
            for (int32 Col = 0; Col < Cols; ++Col)
            {
                auto Offset = FVector(float32(Row) * -Spacing, (float32(Col) - ColCenter) * Spacing, 0.0f);
                auto SpawnXf = InitialTransform;
                SpawnXf.AddToTranslation(Offset);

                auto Entity = InHandle.Request_CreateEntity();
                utils_transform::Add(Entity, SpawnXf, ECk_Replication::DoesNotReplicate);
                auto Proxy = utils_iskm_proxy::Add(Entity, FCk_Fragment_IskmProxy_ParamsData(Renderer, SpawnXf));
                _Proxies.Add(Proxy);
            }
        }

        return ECk_EntityScript_ConstructionFlow::Finished;
    }
}

// ====================================================================================================================
// Station 2 — OutfitSwap: single proxy, periodic submesh attach/detach.
// ====================================================================================================================

class UCk_EntityScript_IskmRendererGym_OutfitSwap : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    private FCk_Handle_IskmProxy _Proxy;
    private bool _SubmeshAttached = false;
    private float _Elapsed = 0.0f;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

        auto RendererData = IskmGym_LoadRendererData();
        if (ck::Is_NOT_Valid(RendererData))
        {
            IskmGym_PrintMissingContent("OutfitSwap");
            return ECk_EntityScript_ConstructionFlow::Finished;
        }
        auto Renderer = utils_iskm_renderer::Add(InHandle, RendererData);

        auto AgentEntity = InHandle.Request_CreateEntity();
        utils_transform::Add(AgentEntity, InitialTransform, ECk_Replication::DoesNotReplicate);
        _Proxy = utils_iskm_proxy::Add(AgentEntity, FCk_Fragment_IskmProxy_ParamsData(Renderer, InitialTransform));

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnTick"));
        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (ck::Is_NOT_Valid(_Proxy)) { return; }

        _Elapsed += float(InDeltaT.Get_Seconds());
        if (_Elapsed < 1.5f) { return; }
        _Elapsed = 0.0f;

        if (_SubmeshAttached)
        {
            utils_iskm_proxy::Request_DetachSubmesh(_Proxy, n"Hat");
        }
        else
        {
            utils_iskm_proxy::Request_AttachSubmesh(_Proxy, n"Hat");
        }
        _SubmeshAttached = !_SubmeshAttached;
    }
}

// ====================================================================================================================
// Station 3 — MontageBurst: single proxy, periodic montage trigger.
// ====================================================================================================================

class UCk_EntityScript_IskmRendererGym_MontageBurst : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    private FCk_Handle_IskmProxy _Proxy;
    private UAnimMontage _Montage;
    private float _Elapsed = 0.0f;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

        auto RendererData = IskmGym_LoadRendererData();
        if (ck::Is_NOT_Valid(RendererData))
        {
            IskmGym_PrintMissingContent("MontageBurst");
            return ECk_EntityScript_ConstructionFlow::Finished;
        }
        auto Renderer = utils_iskm_renderer::Add(InHandle, RendererData);

        // Optional: load a montage asset for the demo. If missing, the timer still
        // fires but Request_PlayMontage is a no-op (handler bails on null _Montage).
        auto MontageResult = utils_i_o::LoadAssetByName(
            "/CkTests/CkIskmRenderer/Anim/AM_NotifyTest",
            ECk_AssetSearchScope::Plugins,
            ECk_AssetSearchStrategy::ExactOnly);
        _Montage = Cast<UAnimMontage>(MontageResult._Asset);

        auto AgentEntity = InHandle.Request_CreateEntity();
        utils_transform::Add(AgentEntity, InitialTransform, ECk_Replication::DoesNotReplicate);
        _Proxy = utils_iskm_proxy::Add(AgentEntity, FCk_Fragment_IskmProxy_ParamsData(Renderer, InitialTransform));

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnTick"));
        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (ck::Is_NOT_Valid(_Proxy)) { return; }

        _Elapsed += float(InDeltaT.Get_Seconds());
        if (_Elapsed < 3.0f) { return; }
        _Elapsed = 0.0f;

        auto Req = FCk_Request_IskmProxy_PlayMontage(_Montage);
        utils_iskm_proxy::Request_PlayMontage(_Proxy, Req);
    }
}

// ====================================================================================================================
// Station 4 — RagdollDemo: single proxy, alternating Begin/End ragdoll.
// ====================================================================================================================

class UCk_EntityScript_IskmRendererGym_RagdollDemo : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    private FCk_Handle_IskmProxy _Proxy;
    private bool _Ragdolling = false;
    private float _Elapsed = 0.0f;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

        auto RendererData = IskmGym_LoadRendererData();
        if (ck::Is_NOT_Valid(RendererData))
        {
            IskmGym_PrintMissingContent("RagdollDemo");
            return ECk_EntityScript_ConstructionFlow::Finished;
        }
        auto Renderer = utils_iskm_renderer::Add(InHandle, RendererData);

        auto AgentEntity = InHandle.Request_CreateEntity();
        utils_transform::Add(AgentEntity, InitialTransform, ECk_Replication::DoesNotReplicate);
        _Proxy = utils_iskm_proxy::Add(AgentEntity, FCk_Fragment_IskmProxy_ParamsData(Renderer, InitialTransform));

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnTick"));
        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (ck::Is_NOT_Valid(_Proxy)) { return; }

        _Elapsed += float(InDeltaT.Get_Seconds());
        const float Threshold = _Ragdolling ? 3.0f : 5.0f;
        if (_Elapsed < Threshold) { return; }
        _Elapsed = 0.0f;

        if (_Ragdolling)
        {
            utils_iskm_proxy::Request_EndRagdoll(_Proxy);
        }
        else
        {
            FCk_Request_IskmProxy_BeginRagdoll Req;
            utils_iskm_proxy::Request_BeginRagdoll(_Proxy, Req);
        }
        _Ragdolling = !_Ragdolling;
    }
}

// ====================================================================================================================
// Station 5 — CustomData: single proxy, sin-wave custom data slot.
// ====================================================================================================================

class UCk_EntityScript_IskmRendererGym_CustomData : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    private FCk_Handle_IskmProxy _Proxy;
    private float _Elapsed = 0.0f;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

        auto RendererData = IskmGym_LoadRendererData();
        if (ck::Is_NOT_Valid(RendererData))
        {
            IskmGym_PrintMissingContent("CustomData");
            return ECk_EntityScript_ConstructionFlow::Finished;
        }
        auto Renderer = utils_iskm_renderer::Add(InHandle, RendererData);

        auto AgentEntity = InHandle.Request_CreateEntity();
        utils_transform::Add(AgentEntity, InitialTransform, ECk_Replication::DoesNotReplicate);
        _Proxy = utils_iskm_proxy::Add(AgentEntity, FCk_Fragment_IskmProxy_ParamsData(Renderer, InitialTransform));

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnTick"));
        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (ck::Is_NOT_Valid(_Proxy)) { return; }

        _Elapsed += float(InDeltaT.Get_Seconds());

        // 0..1 sin-wave on slot 0. Engineer wires the material to read custom-data
        // slot 0 to see the visual effect.
        const float32 Value = float32(0.5 + 0.5 * Math::Sin(_Elapsed * 2.0));
        utils_iskm_proxy::Request_SetCustomDataFloat(_Proxy, int32(0), Value);
    }
}
