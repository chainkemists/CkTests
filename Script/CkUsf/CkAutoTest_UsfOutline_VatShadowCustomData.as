// Language=angelscript

//============================================================================
// CK USF ENTITY OUTLINE - AUTOTEST: VAT shadow material + custom-data parity
//============================================================================
//
// A VatProxy renders through an IsmProxy composed on the SAME entity, and VAT deforms the mesh
// entirely inside its material's World Position Offset - sampling a baked pose texture with the 12
// per-instance custom-data floats. So the custom-depth "shadow ISM" only silhouettes the ANIMATED
// pose if it carries the source ISM's material AND the same custom data. If it doesn't, the outline
// traces the bind pose while the mesh animates.
//
// This pins that contract CPU-side (headless-safe - no rendering asserted):
//   1. the shadow instance's custom data matches the proxy's authoritative cache at apply time
//      (the seed in FProcessor_IsmProxy_Outline_Sync),
//   2. the shadow carries the collection's VAT MID, not the static mesh's default material
//      (the material inheritance in FindOrCreate_OutlineIsmComponent),
//   3. a later playback state change is MIRRORED onto the shadow
//      (FProcessor_IsmProxy_HandleRequests) - write-on-change, never per frame.
//   4. a late custom-data write while the movable proxy is disabled is accepted into the CPU
//      cache, then restored to the main and newly recreated shadow instances on re-enable.
//
// Contracts 1-3 pin the original VAT-shadow fix; contract 4 is the red/green discriminator for
// accepting late custom-data writes while the movable proxy has no live instance.
//
// Editor-scoped: the transient VAT bake reads FSkeletalMeshModel source data.
//
//============================================================================

class UCk_AutoTest_UsfOutline_VatShadowCustomData : UCk_AutoTest_Base
{
    private FCk_Handle _Entity;
    private FCk_Handle_VatProxy _VatProxy;
    private FCk_Handle_IsmProxy _IsmProxy;
    private int32 _Phase = 0;
    private int32 _TicksInPhase = 0;
    private int64 _LateSubmissionFrame = 0;
    private int32 _LateCompletionFireCount = 0;
    private float32 _LateValue = 0.0f;
    private bool _DisableCompleted = false;
    private int32 _DisableCompletionFireCount = 0;
    private ECk_Request_OperationResult _DisableResult = ECk_Request_OperationResult::Failed;
    private bool _DisabledLateWriteCompleted = false;
    private int32 _DisabledLateWriteCompletionFireCount = 0;
    private ECk_Request_OperationResult _DisabledLateWriteResult = ECk_Request_OperationResult::Failed;
    private float32 _DisabledLateValue = 0.0f;
    private bool _EnableCompleted = false;
    private int32 _EnableCompletionFireCount = 0;
    private ECk_Request_OperationResult _EnableResult = ECk_Request_OperationResult::Failed;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

#if EDITOR
        auto Skeleton = assets::load::SK_Mannequin();
        auto Mesh = assets::load::SKM_Manny_Simple();
        auto Jump = assets::load::MM_Jump();
        if (ck::Is_NOT_Valid(Skeleton) || ck::Is_NOT_Valid(Mesh) || ck::Is_NOT_Valid(Jump))
        {
            FinishFailure("Mannequin content (SK_Mannequin / SKM_Manny_Simple / MM_Jump) failed to load");
            return;
        }

        auto Baker = Cast<UCkVat_BakerSubsystem>(EditorSubsystem::GetEditorSubsystem(UCkVat_BakerSubsystem));
        if (ck::Is_NOT_Valid(Baker))
        {
            FinishFailure("UCkVat_BakerSubsystem unavailable");
            return;
        }

        auto Clips = TArray<FCk_VatCollection_ClipDef>();
        Clips.Add(FCk_VatCollection_ClipDef(Jump, n"Jump"));

        auto Collection = Baker.CreateAndBake_TransientCollection(Skeleton, Mesh, Clips,
            30, ECk_Vat_BakeMode::Bone, ECk_Vat_Precision::High);

        if (ck::Is_NOT_Valid(Collection) || Collection.Get_BakedData().Get_IsBaked() == false)
        {
            FinishFailure("transient VAT bake did not produce a baked collection");
            return;
        }

        _Entity = LocalHandle.Request_CreateEntity();
        auto Transform = utils_transform::Add(_Entity, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto Params = FCk_Fragment_VatProxy_ParamsData(Collection);
        Params.Set_InitialClipName(n"Jump");
        _VatProxy = utils_vat_proxy::Add(Transform, Params);

        if (ck::Is_NOT_Valid(_VatProxy))
        {
            FinishFailure("utils_vat_proxy::Add returned an invalid handle");
            return;
        }

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
#else
        // The VAT baker is editor-only; outside the editor there is nothing to exercise.
        FinishSuccess();
#endif
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _TicksInPhase++;

        if (_Phase == 0 && _TicksInPhase >= 4)
        {
            // VatProxy Setup composes the IsmProxy on this same entity, which then needs its own
            // Setup + AddInstance to clear before an outline can mirror it.
            if (!utils_ism_proxy::Has(_Entity))
            {
                FinishFailure("VatProxy Setup should have composed an IsmProxy on the same entity");
                return;
            }

            _IsmProxy = utils_ism_proxy::DoCastChecked(_Entity);

            UCk_Utils_Usf_Outline_UE::Request_ApplyOutline(_Entity, CkUsf::DA_Outline_Interactable, ECk_Usf_OutlineScope::EntityOnly);
            _Phase = 1; _TicksInPhase = 0;
        }
        else if (_Phase == 1 && _TicksInPhase >= 3)
        {
            Assert_True(_IsmProxy.Get_IsOutlineApplied(),
                "the VAT entity's IsmProxy should be outlined (VAT rides the generic ISM outline path)");
            Assert_True(_IsmProxy.Get_Mobility() == ECk_Mobility::Movable,
                "the disabled late-write regression requires a movable ISM proxy");

            auto SourceData = _IsmProxy.Get_CustomInstanceData();
            Assert_Equals_Int(SourceData.Num(), 12,
                "a VAT proxy drives 12 per-instance custom-data floats");

            if (SourceData.Num() == 0)
            {
                FinishFailure("VAT source custom data was empty before the late-write assertion");
                return;
            }

            Assert_True(Cast<UMaterialInstanceDynamic>(_IsmProxy.Get_OutlineShadowMaterial(0)) != nullptr,
                "the shadow ISM must carry the collection's VAT MID, not the static mesh's default material");

            Assert_ShadowMatchesSource("at apply time");

            // Exercise the opt-in DeferredApply lane used by late PostTransform visual producers.
            // Completion must observe both authoritative source data and the outline shadow updated.
            _LateValue = SourceData[0] + 0.125f;
            _LateSubmissionFrame = utils_time::Get_FrameCounter();
            utils_ism_proxy::Request_SetCustomInstanceDataValue_Late(_IsmProxy,
                FCk_Request_IsmProxy_SetCustomInstanceDataValue(0, _LateValue),
                FCk_Delegate_Request_OnCompleted(this, n"OnLateWriteCompleted"));

            _Phase = 2; _TicksInPhase = 0;
        }
        else if (_Phase == 2 && _TicksInPhase >= 2)
        {
            Assert_Equals_Int(_LateCompletionFireCount, 1,
                "late ISM custom-data completion must fire exactly once");
            Assert_ShadowMatchesSource("after a late custom-data write");

            utils_ism_proxy::Request_EnableDisable(_IsmProxy,
                FCk_Request_IsmProxy_EnableDisable(ECk_EnableDisable::Disable),
                FCk_Delegate_Request_OnCompleted(this, n"OnDisableCompleted"));

            _Phase = 3; _TicksInPhase = 0;
            WaitUntil(n"Check_DisabledAndOutlineSuspended", n"OnDisabledAndOutlineSuspended");
        }
        else if (_Phase == 4 && _TicksInPhase >= 3)
        {
            Assert_ShadowMatchesSource("after a play-rate/clip change");
            FinishSuccess();
        }
    }

    UFUNCTION()
    private void Check_DisabledAndOutlineSuspended(
        FCk_Handle InHandle,
        FCk_SharedBool OutResult,
        FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_DisableCompleted && _IsmProxy.Get_IsOutlineApplied() == false);
    }

    UFUNCTION()
    private void OnDisabledAndOutlineSuspended(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_DisableCompletionFireCount, 1,
            "disable completion must fire exactly once");
        Assert_True(_DisableResult == ECk_Request_OperationResult::Succeeded,
            "disabling the movable ISM proxy must succeed");
        Assert_False(_IsmProxy.Get_IsOutlineApplied(),
            "the outline shadow must be suspended while the ISM proxy is disabled");

        auto SourceData = _IsmProxy.Get_CustomInstanceData();
        if (SourceData.Num() == 0)
        {
            FinishFailure("VAT source custom data was empty before the disabled late-write assertion");
            return;
        }

        // Disable completion is post-handler: the movable proxy's main instance is already removed.
        // Waiting for outline suspension also proves there is no live shadow instance to receive this
        // write. The late lane must still accept the value into the authoritative CPU cache.
        _DisabledLateValue = SourceData[0] + 0.25f;
        utils_ism_proxy::Request_SetCustomInstanceDataValue_Late(_IsmProxy,
            FCk_Request_IsmProxy_SetCustomInstanceDataValue(0, _DisabledLateValue),
            FCk_Delegate_Request_OnCompleted(this, n"OnDisabledLateWriteCompleted"));

        WaitUntil(n"Check_DisabledLateWriteCompleted", n"OnDisabledLateWriteSettled");
    }

    UFUNCTION()
    private void Check_DisabledLateWriteCompleted(
        FCk_Handle InHandle,
        FCk_SharedBool OutResult,
        FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_DisabledLateWriteCompleted);
    }

    UFUNCTION()
    private void OnDisabledLateWriteSettled(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_DisabledLateWriteCompletionFireCount, 1,
            "disabled late-write completion must fire exactly once");
        Assert_True(_DisabledLateWriteResult == ECk_Request_OperationResult::Succeeded,
            "a late custom-data write without a live instance must be accepted");

        auto SourceData = _IsmProxy.Get_CustomInstanceData();
        Assert_True(SourceData.Num() > 0 && Math::IsNearlyEqual(SourceData[0], _DisabledLateValue, 0.0001f),
            "disabled late-write completion must observe the authoritative cache updated");
        Assert_False(_IsmProxy.Get_IsOutlineApplied(),
            "the late write must not implicitly recreate a disabled proxy's outline shadow");

        utils_ism_proxy::Request_EnableDisable(_IsmProxy,
            FCk_Request_IsmProxy_EnableDisable(ECk_EnableDisable::Enable),
            FCk_Delegate_Request_OnCompleted(this, n"OnEnableCompleted"));

        WaitUntil(n"Check_ReEnabledWithOutline", n"OnReEnabledFromCache");
    }

    UFUNCTION()
    private void Check_ReEnabledWithOutline(
        FCk_Handle InHandle,
        FCk_SharedBool OutResult,
        FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_EnableCompleted && _IsmProxy.Get_IsOutlineApplied());
    }

    UFUNCTION()
    private void OnReEnabledFromCache(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_EnableCompletionFireCount, 1,
            "enable completion must fire exactly once");
        Assert_True(_EnableResult == ECk_Request_OperationResult::Succeeded,
            "re-enabling the movable ISM proxy must succeed");

        // Outline sync excludes NeedsInstanceAdded and runs after AddInstance, so a newly applied
        // outline proves the main instance was recreated from the same authoritative cache.
        auto SourceData = _IsmProxy.Get_CustomInstanceData();
        auto ShadowData = _IsmProxy.Get_OutlineShadowCustomData();
        Assert_True(SourceData.Num() > 0 && Math::IsNearlyEqual(SourceData[0], _DisabledLateValue, 0.0001f),
            "re-enabled main instance must restore the disabled late-write value from the cache");
        Assert_True(ShadowData.Num() > 0 && Math::IsNearlyEqual(ShadowData[0], _DisabledLateValue, 0.0001f),
            "re-enabled outline shadow must mirror the disabled late-write value");
        Assert_ShadowMatchesSource("after re-enabling from a disabled late write");

        // A playback change repacks the custom data - the shadow must follow, or the silhouette
        // freezes on the pose it was outlined in.
        auto Play = FCk_Request_VatProxy_PlayClip(n"Jump");
        Play.Set_PlayRate(2.0f);
        Play.Set_LoopMode(ECk_VatProxy_LoopMode::Loop);
        utils_vat_proxy::Request_PlayClip(_VatProxy, Play);

        _Phase = 4; _TicksInPhase = 0;
    }

    UFUNCTION()
    private void OnLateWriteCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        if (IsFinished()) { return; }

        _LateCompletionFireCount++;
        Assert_True(InRequestOwner == _IsmProxy,
            "late ISM custom-data completion must report the IsmProxy request owner");
        Assert_True(InResult == ECk_Request_OperationResult::Succeeded,
            "late ISM custom-data completion must report Succeeded after application");
        Assert_True(utils_time::Get_FrameCounter() == _LateSubmissionFrame,
            "DeferredApply must consume a late ISM custom-data request in its submission frame");

        const auto SourceData = _IsmProxy.Get_CustomInstanceData();
        const auto ShadowData = _IsmProxy.Get_OutlineShadowCustomData();
        Assert_True(SourceData.Num() > 0 && Math::IsNearlyEqual(SourceData[0], _LateValue, 0.0001f),
            "late completion must observe the source custom-data cache updated");
        Assert_True(ShadowData.Num() > 0 && Math::IsNearlyEqual(ShadowData[0], _LateValue, 0.0001f),
            "late completion must observe the outline shadow custom data updated");
    }

    UFUNCTION()
    private void OnDisableCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        if (IsFinished()) { return; }

        _DisableCompletionFireCount++;
        _DisableResult = InResult;
        _DisableCompleted = true;
        Assert_True(InRequestOwner == _IsmProxy,
            "disable completion must report the IsmProxy request owner");
    }

    UFUNCTION()
    private void OnDisabledLateWriteCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        if (IsFinished()) { return; }

        _DisabledLateWriteCompletionFireCount++;
        _DisabledLateWriteResult = InResult;
        _DisabledLateWriteCompleted = true;
        Assert_True(InRequestOwner == _IsmProxy,
            "disabled late-write completion must report the IsmProxy request owner");
    }

    UFUNCTION()
    private void OnEnableCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        if (IsFinished()) { return; }

        _EnableCompletionFireCount++;
        _EnableResult = InResult;
        _EnableCompleted = true;
        Assert_True(InRequestOwner == _IsmProxy,
            "enable completion must report the IsmProxy request owner");
    }

    private void Assert_ShadowMatchesSource(FString InWhen)
    {
        auto SourceData = _IsmProxy.Get_CustomInstanceData();
        auto ShadowData = _IsmProxy.Get_OutlineShadowCustomData();

        Assert_Equals_Int(ShadowData.Num(), SourceData.Num(),
            f"shadow custom-data width must match the source {InWhen}");

        if (ShadowData.Num() != SourceData.Num())
        { return; }

        for (int32 i = 0; i < SourceData.Num(); ++i)
        {
            Assert_True(Math::IsNearlyEqual(ShadowData[i], SourceData[i], 0.0001f),
                f"shadow custom-data float [{i}] must match the source {InWhen}");
        }
    }
}

class ACk_AutoTest_UsfOutline_VatShadowCustomData_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_UsfOutline_VatShadowCustomData;
    default _TimeoutSeconds = 30.0f;

    // Shares the ISM-outline content ensure whitelist: the renderer DA's material lacks
    // 'bUsedWithInstancedStaticMeshes' in uncooked/headless runs. Occurrences=-1 (pure suppression),
    // so a non-firing pattern is harmless.
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        Out.Add("bUsedWithInstancedStaticMeshes");
        Out.Add("material will recompile every editor launch");
        return Out;
    }
}
