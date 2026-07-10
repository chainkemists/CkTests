// Language=angelscript

//============================================================================
// CK VAT — AUTOMATION TEST: TRANSIENT BAKE + END-TO-END PLAYBACK
//============================================================================
//
// The Gate-4 end-to-end test, unblocked by the transient bake (no committed
// baked content needed — the collection is built in memory per run):
//   1. CreateAndBake_TransientCollection (Bone mode, Mannequin + MM_Jump)
//      succeeds and returns a BAKED collection (textures + mesh + clip table
//      outered to the transient package; nothing saved to disk).
//   2. utils_vat_proxy::Add composes against it (Setup resolves the shared
//      MID from the committed VatBone master + the transient ISM renderer).
//   3. Request_PlayClip (Once, rate 4) plays and OnClipFinished fires exactly
//      once with the clip's name — the full CPU playback state machine:
//      request drain, 12-float packing, FireSignals completion math.
//
// Editor-scoped: the baker reads FSkeletalMeshModel source data, so the body
// is #if EDITOR (the harness only runs in-editor; cooked AS must not bind
// the editor-only baker subsystem type).
//
//============================================================================

class UCk_AutoTest_VatProxy_TransientBakePlayback : UCk_AutoTest_Base
{
    private FCk_Handle_VatProxy _Proxy;
    private int32 _FinishCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

#if EDITOR
        // ----- Build the transient collection -----

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

        Assert_True(ck::IsValid(Collection),
            "CreateAndBake_TransientCollection should return a valid collection");
        if (ck::Is_NOT_Valid(Collection))
        { FinishFailure("transient bake returned null"); return; }

        Assert_True(Collection.Get_IsBaked(),
            "the transient collection should be marked baked");
        Assert_True(Collection.Get_BakedClips().Num() == 1,
            "the transient collection should have exactly one baked clip");

        // ----- Compose + play -----

        auto Transform = utils_transform::Add(LocalHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        _Proxy = utils_vat_proxy::Add(Transform, FCk_Fragment_VatProxy_ParamsData(Collection));

        Assert_True(ck::IsValid(_Proxy),
            "utils_vat_proxy::Add should succeed against a transient-baked collection");
        if (ck::Is_NOT_Valid(_Proxy))
        { FinishFailure("Add returned an invalid handle"); return; }

        _Proxy.BindTo_OnClipFinished(FCk_Delegate_VatProxy_OnClipFinished(this, n"OnClipFinished"));

        auto Play = FCk_Request_VatProxy_PlayClip(n"Jump");
        Play.Set_LoopMode(ECk_VatProxy_LoopMode::Once);
        Play.Set_PlayRate(4.0f);
        utils_vat_proxy::Request_PlayClip(_Proxy, Play);
#else
        // The baker is editor-only; outside the editor there is nothing to exercise.
        FinishSuccess();
#endif
    }

    UFUNCTION()
    private void OnClipFinished(FCk_Handle_VatProxy InHandle, FName InClipName)
    {
        _FinishCount++;

        Assert_True(InClipName == n"Jump",
            "OnClipFinished should carry the finished clip's name");
        Assert_True(_FinishCount == 1,
            "OnClipFinished should fire exactly once for a Once clip");
        Assert_True(utils_vat_proxy::Get_ActiveClipName(InHandle) == n"Jump",
            "the finished clip should still be the active (frozen) clip");

        FinishSuccess();
    }
}

class ACk_AutoTest_VatProxy_TransientBakePlayback_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_VatProxy_TransientBakePlayback;
    default _TimeoutSeconds = 30.0f;
}
