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
// Each station takes RendererData via ExposeOnSpawn on the spawn-params struct.
// Plan-1 leaves it null (the AS-declared empty-body asset stamps in
// CkIskmRenderer_Shared.as need an engineer to populate skeleton/mesh/sequences
// in the editor before they're useful). With null RendererData each station
// is a no-op — proxies are not added, timers don't fire any visible work.
// Wire RendererData in a Blueprint subclass of the gym GameMode/PlayerController
// once content is authored.
//
//============================================================================

USTRUCT()
struct FCkIskmRenderer_GymStationSpawnParams
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    UPROPERTY()
    UCk_IskmRenderer_Data RendererData;
}

// ====================================================================================================================
// Station 1 — SpawnArmy: 5x5 grid of sub-entities, each with its own IskmProxy.
// ====================================================================================================================

class UCk_EntityScript_IskmRendererGym_SpawnArmy : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    UPROPERTY(ExposeOnSpawn)
    UCk_IskmRenderer_Data RendererData;

    private TArray<FCk_Handle_IskmProxy> _Proxies;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

        if (ck::Is_NOT_Valid(RendererData)) { return ECk_EntityScript_ConstructionFlow::Finished; }
        auto Renderer = utils_iskm_renderer::Add(InHandle, RendererData);

        const int32 Rows = 5;
        const int32 Cols = 5;
        const float32 Spacing = 150.0f;
        const float32 ColCenter = float32(Cols) * 0.5f;

        for (int32 Row = 0; Row < Rows; ++Row)
        {
            for (int32 Col = 0; Col < Cols; ++Col)
            {
                // Stations face -X (per the gym convention) — lay agents out behind the panel.
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

    UPROPERTY(ExposeOnSpawn)
    UCk_IskmRenderer_Data RendererData;

    private FCk_Handle_IskmProxy _Proxy;
    private bool _SubmeshAttached = false;
    private float _Elapsed = 0.0f;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

        if (ck::Is_NOT_Valid(RendererData)) { return ECk_EntityScript_ConstructionFlow::Finished; }
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

    UPROPERTY(ExposeOnSpawn)
    UCk_IskmRenderer_Data RendererData;

    private FCk_Handle_IskmProxy _Proxy;
    private float _Elapsed = 0.0f;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

        if (ck::Is_NOT_Valid(RendererData)) { return ECk_EntityScript_ConstructionFlow::Finished; }
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
        if (_Elapsed < 3.0f) { return; }
        _Elapsed = 0.0f;

        // Default-constructed request: _Montage is null. Engineer fills in a real
        // UAnimMontage at content-authoring time; until then the handler short-circuits
        // on the null-montage guard.
        FCk_Request_IskmProxy_PlayMontage Req;
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

    UPROPERTY(ExposeOnSpawn)
    UCk_IskmRenderer_Data RendererData;

    private FCk_Handle_IskmProxy _Proxy;
    private bool _Ragdolling = false;
    private float _Elapsed = 0.0f;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

        if (ck::Is_NOT_Valid(RendererData)) { return ECk_EntityScript_ConstructionFlow::Finished; }
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

    UPROPERTY(ExposeOnSpawn)
    UCk_IskmRenderer_Data RendererData;

    private FCk_Handle_IskmProxy _Proxy;
    private float _Elapsed = 0.0f;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

        if (ck::Is_NOT_Valid(RendererData)) { return ECk_EntityScript_ConstructionFlow::Finished; }
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
