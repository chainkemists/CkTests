// Language=angelscript

//============================================================================
// CK USF ENTITY OUTLINE — AUTOTEST: VAT shadow material + custom-data parity
//============================================================================
//
// A VatProxy renders through an IsmProxy composed on the SAME entity, and VAT deforms the mesh
// entirely inside its material's World Position Offset — sampling a baked pose texture with the 12
// per-instance custom-data floats. So the custom-depth "shadow ISM" only silhouettes the ANIMATED
// pose if it carries the source ISM's material AND the same custom data. If it doesn't, the outline
// traces the bind pose while the mesh animates.
//
// This pins that contract CPU-side (headless-safe — no rendering asserted):
//   1. the shadow instance's custom data matches the proxy's authoritative cache at apply time
//      (the seed in FProcessor_IsmProxy_Outline_Sync),
//   2. the shadow carries the collection's VAT MID, not the static mesh's default material
//      (the material inheritance in FindOrCreate_OutlineIsmComponent),
//   3. a later playback state change is MIRRORED onto the shadow
//      (FProcessor_IsmProxy_HandleRequests) — write-on-change, never per frame.
//
// Before those three landed the shadow had NumCustomDataFloats = 0 and the mesh's default material,
// so assertions 1-3 are the red/green discriminator for the whole fix.
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

        auto Params = FCk_VatProxy_Spec(Collection);
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

            auto SourceData = _IsmProxy.Get_CustomInstanceData();
            Assert_Equals_Int(SourceData.Num(), 12,
                "a VAT proxy drives 12 per-instance custom-data floats");

            Assert_True(Cast<UMaterialInstanceDynamic>(_IsmProxy.Get_OutlineShadowMaterial(0)) != nullptr,
                "the shadow ISM must carry the collection's VAT MID, not the static mesh's default material");

            Assert_ShadowMatchesSource("at apply time");

            // A playback change repacks the custom data — the shadow must follow, or the silhouette
            // freezes on the pose it was outlined in.
            auto Play = FCk_Request_VatProxy_PlayClip(n"Jump");
            Play.Set_PlayRate(2.0f);
            Play.Set_LoopMode(ECk_VatProxy_LoopMode::Loop);
            utils_vat_proxy::Request_PlayClip(_VatProxy, Play);

            _Phase = 2; _TicksInPhase = 0;
        }
        else if (_Phase == 2 && _TicksInPhase >= 3)
        {
            Assert_ShadowMatchesSource("after a play-rate/clip change");
            FinishSuccess();
        }
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
