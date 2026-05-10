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
// Station 6 — TransitionCycle: single proxy, alternates loop ↔ non-loop sequences.
// Demonstrates the Replaced (interrupting a loop) + Completed (non-looping ends naturally)
// paths in OnAnimationFinished.
// ====================================================================================================================

class UCk_EntityScript_IskmRendererGym_TransitionCycle : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    private FCk_Handle_IskmProxy _Proxy;
    private UAnimSequenceBase _SeqLoop;
    private UAnimSequenceBase _SeqNonLoop;
    private bool _PlayingNonLoop = false;
    private float _Elapsed = 0.0f;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

        auto RendererData = IskmGym_LoadRendererData();
        if (ck::Is_NOT_Valid(RendererData))
        {
            IskmGym_PrintMissingContent("TransitionCycle");
            return ECk_EntityScript_ConstructionFlow::Finished;
        }
        auto Renderer = utils_iskm_renderer::Add(InHandle, RendererData);

        auto LoopResult = utils_i_o::LoadAssetByName(
            "/CkTests/CkIskmRenderer/Anim/MM_Idle",
            ECk_AssetSearchScope::Plugins,
            ECk_AssetSearchStrategy::ExactOnly);
        _SeqLoop = Cast<UAnimSequenceBase>(LoopResult._Asset);

        auto NonLoopResult = utils_i_o::LoadAssetByName(
            "/CkTests/CkIskmRenderer/Anim/MM_Jump",
            ECk_AssetSearchScope::Plugins,
            ECk_AssetSearchStrategy::ExactOnly);
        _SeqNonLoop = Cast<UAnimSequenceBase>(NonLoopResult._Asset);

        auto AgentEntity = InHandle.Request_CreateEntity();
        utils_transform::Add(AgentEntity, InitialTransform, ECk_Replication::DoesNotReplicate);
        _Proxy = utils_iskm_proxy::Add(AgentEntity, FCk_Fragment_IskmProxy_ParamsData(Renderer, InitialTransform));

        // Kick off with the looping sequence. If unauthored, the timer still
        // runs but Request_PlayAnimation is a no-op (handler bails on null sequence).
        if (ck::IsValid(_SeqLoop))
        {
            auto Req = FCk_Request_IskmProxy_PlayAnimation(_SeqLoop);
            Req.Set_bLoop(true);
            utils_iskm_proxy::Request_PlayAnimation(_Proxy, Req);
        }

        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnTick"));
        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (ck::Is_NOT_Valid(_Proxy)) { return; }
        if (ck::Is_NOT_Valid(_SeqLoop) || ck::Is_NOT_Valid(_SeqNonLoop)) { return; }

        _Elapsed += float(InDeltaT.Get_Seconds());
        if (_Elapsed < 2.5f) { return; }
        _Elapsed = 0.0f;

        auto NextSeq = (_PlayingNonLoop == false) ? _SeqNonLoop : _SeqLoop;
        // Currently non-loop → switch to loop next; currently loop → switch to non-loop.
        const bool NextLoop = _PlayingNonLoop;

        auto Req = FCk_Request_IskmProxy_PlayAnimation(NextSeq);
        Req.Set_bLoop(NextLoop);
        utils_iskm_proxy::Request_PlayAnimation(_Proxy, Req);

        _PlayingNonLoop = (_PlayingNonLoop == false);
    }
}

// ====================================================================================================================
// Station 7 — AnimBPDemo: side-by-side AnimBP-driven vs Sequence-driven proxies.
//
// Left proxy: lets Setup apply the Renderer PDA's _DefaultAnimInstanceClass, which
//             the engineer wires to ABP_Unarmed (or any UAnimInstance subclass) on
//             /CkTests/CkIskmRenderer/Demo/RendererData_Demo. With nothing set, the
//             proxy stays in the fallback UCk_IskmNotify_AnimInstance (sequence mode
//             by default) — looks like the right proxy.
// Right proxy: explicitly forced to Sequence mode via Request_SetAnimInstanceClass(null)
//              + a looping MM_Idle so it doesn't sit in T-pose.
// ====================================================================================================================

class UCk_EntityScript_IskmRendererGym_AnimBPDemo : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    private FCk_Handle_IskmProxy _ProxyAnimBP;
    private FCk_Handle_IskmProxy _ProxySequence;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);

        auto RendererData = IskmGym_LoadRendererData();
        if (ck::Is_NOT_Valid(RendererData))
        {
            IskmGym_PrintMissingContent("AnimBPDemo");
            return ECk_EntityScript_ConstructionFlow::Finished;
        }
        auto Renderer = utils_iskm_renderer::Add(InHandle, RendererData);

        // Left (Y -100): AnimBP mode. Setup applies _DefaultAnimInstanceClass automatically.
        auto LeftXf = InitialTransform;
        LeftXf.AddToTranslation(FVector(0.0f, -100.0f, 0.0f));
        auto LeftEntity = InHandle.Request_CreateEntity();
        utils_transform::Add(LeftEntity, LeftXf, ECk_Replication::DoesNotReplicate);
        _ProxyAnimBP = utils_iskm_proxy::Add(LeftEntity, FCk_Fragment_IskmProxy_ParamsData(Renderer, LeftXf));

        // Right (Y +100): forced to Sequence mode + plays MM_Idle.
        auto RightXf = InitialTransform;
        RightXf.AddToTranslation(FVector(0.0f, 100.0f, 0.0f));
        auto RightEntity = InHandle.Request_CreateEntity();
        utils_transform::Add(RightEntity, RightXf, ECk_Replication::DoesNotReplicate);
        _ProxySequence = utils_iskm_proxy::Add(RightEntity, FCk_Fragment_IskmProxy_ParamsData(Renderer, RightXf));

        TSubclassOf<UAnimInstance> NullClass;
        utils_iskm_proxy::Request_SetAnimInstanceClass(_ProxySequence, NullClass);

        // Optional: drive the sequence-mode proxy with a looping idle so it's not T-posed.
        auto IdleResult = utils_i_o::LoadAssetByName(
            "/CkTests/CkIskmRenderer/Anim/MM_Idle",
            ECk_AssetSearchScope::Plugins,
            ECk_AssetSearchStrategy::ExactOnly);
        auto IdleSeq = Cast<UAnimSequenceBase>(IdleResult._Asset);
        if (ck::IsValid(IdleSeq))
        {
            auto PlayReq = FCk_Request_IskmProxy_PlayAnimation(IdleSeq);
            PlayReq.Set_bLoop(true);
            utils_iskm_proxy::Request_PlayAnimation(_ProxySequence, PlayReq);
        }

        return ECk_EntityScript_ConstructionFlow::Finished;
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
