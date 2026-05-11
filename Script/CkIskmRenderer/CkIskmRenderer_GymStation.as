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
// Content discovery: each station references the AS-authored
// `Asset_RendererData_Demo` (defined in CkIskmRenderer_Assets.as) directly —
// no path-based LoadAssetByName, no editor-only `.uasset` to keep in sync.
// The wrapper itself pulls migrated UE Mannequin content via the generated
// `assets::` namespace at script-load time. If the asset somehow resolves
// invalid at runtime (e.g. the registry hasn't regenerated since the
// content was migrated), the station prints an on-screen warning and skips.
//
//============================================================================

UCk_IskmRenderer_Data IskmGym_LoadRendererData()
{
    return iskm_assets::RendererData_Demo();
}

void IskmGym_PrintMissingContent(FString InStationName)
{
    Print(f"[IskmRenderer Gym/{InStationName}] iskm_assets::RendererData_Demo() invalid — registry may need regeneration.", 10.0f);
}

// Opts a proxy into ABP_Unarmed so the mesh idles via the BlendSpace
// (visual gym demo). The wrapper Renderer PDA leaves _DefaultAnimInstanceClass
// unset because ABP_Unarmed isn't a UCk_IskmNotify_AnimInstance subclass and
// the AutoTest harness escalates the framework warning to a test failure.
// In gym PIE the warning is harmless — montages play through DefaultSlot,
// just OnAnimationNotify won't fire (acceptable for a visual demo).
void IskmGym_OptIn_AnimBP(FCk_Handle_IskmProxy InProxy)
{
    auto Local = InProxy;
    utils_iskm_proxy::Request_SetAnimInstanceClass(Local, assets::load::ABP_Unarmed_Class());
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
                IskmGym_OptIn_AnimBP(Proxy);
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
        IskmGym_OptIn_AnimBP(_Proxy);

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

        // Optional: pull the AS-authored montage for the demo. If unset (e.g.
        // the registry hasn't regenerated since the montage was authored), the
        // timer still fires but Request_PlayMontage is a no-op (handler bails
        // on null _Montage).
        _Montage = assets::load::AM_NotifyTest();

        auto AgentEntity = InHandle.Request_CreateEntity();
        utils_transform::Add(AgentEntity, InitialTransform, ECk_Replication::DoesNotReplicate);
        _Proxy = utils_iskm_proxy::Add(AgentEntity, FCk_Fragment_IskmProxy_ParamsData(Renderer, InitialTransform));
        IskmGym_OptIn_AnimBP(_Proxy);

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
        IskmGym_OptIn_AnimBP(_Proxy);

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

    // STEP A: re-add the member fields. NOT referenced from OnTick yet
    // (no OnTick at all in this step) — only assigned in DoConstruct after
    // the kickoff PlayAnimation. If this still animates, fields-and-assignment
    // aren't the cause and we proceed to Step B (timer + empty OnTick).
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

        auto AgentEntity = InHandle.Request_CreateEntity();
        utils_transform::Add(AgentEntity, InitialTransform, ECk_Replication::DoesNotReplicate);
        _Proxy = utils_iskm_proxy::Add(AgentEntity, FCk_Fragment_IskmProxy_ParamsData(Renderer, InitialTransform));

        TSubclassOf<UAnimInstance> NullClass;
        utils_iskm_proxy::Request_SetAnimInstanceClass(_Proxy, NullClass);

        UAnimSequenceBase IdleSeq = assets::load::MM_Idle();
        if (ck::IsValid(IdleSeq))
        {
            auto PlayReq = FCk_Request_IskmProxy_PlayAnimation(IdleSeq);
            PlayReq.Set_Loop(true);
            utils_iskm_proxy::Request_PlayAnimation(_Proxy, PlayReq);
        }

        // STEP A: cache for later steps. Assign AFTER the kickoff so the
        // kickoff path is unchanged from the known-good version.
        _SeqLoop = IdleSeq;
        _SeqNonLoop = assets::load::MM_Jump();

        // STEP B: add the timer + empty OnTick. If this breaks animation,
        // the timer fragment on InHandle (which already has renderer fragments)
        // is interfering with rendering. If still animating, Step C re-adds
        // the elapsed-time gating.
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
        const bool NextLoop = _PlayingNonLoop;

        auto Req = FCk_Request_IskmProxy_PlayAnimation(NextSeq);
        Req.Set_Loop(NextLoop);
        utils_iskm_proxy::Request_PlayAnimation(_Proxy, Req);

        _PlayingNonLoop = (_PlayingNonLoop == false);
    }
}

// ====================================================================================================================
// Station 7 — AnimBPDemo: side-by-side AnimBP-driven vs Sequence-driven proxies.
//
// Left proxy: lets Setup apply the Renderer PDA's _DefaultAnimInstanceClass,
//             which Asset_RendererData_Demo wires to ABP_Unarmed via
//             assets::ABP_Unarmed_Class(). With nothing set, the proxy
//             stays in the fallback UCk_IskmNotify_AnimInstance (sequence
//             mode by default) — looks like the right proxy.
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

        // Left (Y -100): AnimBP mode. Wrapper PDA leaves
        // _DefaultAnimInstanceClass unset (so the non-IskmNotify ABP_Unarmed
        // doesn't trip AutoTest harness on tests sharing this PDA), so we
        // opt in here.
        auto LeftXf = InitialTransform;
        LeftXf.AddToTranslation(FVector(0.0f, -100.0f, 0.0f));
        auto LeftEntity = InHandle.Request_CreateEntity();
        utils_transform::Add(LeftEntity, LeftXf, ECk_Replication::DoesNotReplicate);
        _ProxyAnimBP = utils_iskm_proxy::Add(LeftEntity, FCk_Fragment_IskmProxy_ParamsData(Renderer, LeftXf));
        IskmGym_OptIn_AnimBP(_ProxyAnimBP);

        // Right (Y +100): forced to Sequence mode + plays MM_Idle.
        auto RightXf = InitialTransform;
        RightXf.AddToTranslation(FVector(0.0f, 100.0f, 0.0f));
        auto RightEntity = InHandle.Request_CreateEntity();
        utils_transform::Add(RightEntity, RightXf, ECk_Replication::DoesNotReplicate);
        _ProxySequence = utils_iskm_proxy::Add(RightEntity, FCk_Fragment_IskmProxy_ParamsData(Renderer, RightXf));

        TSubclassOf<UAnimInstance> NullClass;
        utils_iskm_proxy::Request_SetAnimInstanceClass(_ProxySequence, NullClass);

        // Optional: drive the sequence-mode proxy with a looping idle so it's not T-posed.
        UAnimSequenceBase IdleSeq = assets::load::MM_Idle();
        if (ck::IsValid(IdleSeq))
        {
            auto PlayReq = FCk_Request_IskmProxy_PlayAnimation(IdleSeq);
            PlayReq.Set_Loop(true);
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
        IskmGym_OptIn_AnimBP(_Proxy);

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
