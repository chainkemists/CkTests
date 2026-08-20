// Language=angelscript

//============================================================================
// CK CAMERA — AUTOMATION TEST: DEFAULT (BASE) LAYER RESTING INVARIANTS
//============================================================================
//
// utils_camera::Add creates a persistent internal "default layer" that holds the resting profile. This test pins
// down its invariants using only observable state (layer count + composed profile):
//
//   * It is NOT counted as a gameplay layer  → Get_LayerCount() == 0 right after Add (and again after every feature
//     layer is removed).
//   * The resting profile is live with no feature layers → composed FOV == base (90) at rest.
//   * Adding a feature layer changes the composed value; removing it blends straight back to the base — proving the
//     default layer is never evicted/pruned and is the fallback the stack rests on.
//============================================================================

class UCk_AutoTest_GameplayCamera_DefaultLayerResting : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private ACkAutoTest_GameplayCamera_Helper _Helper;
    private FCk_Handle_Camera                 _Camera;
    private int32                             _Phase  = 0;
    private int32                             _Frames = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Helper = Cast<ACkAutoTest_GameplayCamera_Helper>(SpawnActor(
            ACkAutoTest_GameplayCamera_Helper, FVector::ZeroVector, FRotator::ZeroRotator));
        if (ck::Is_NOT_Valid(_Helper))
        { FinishFailure("Failed to spawn GameplayCamera helper"); return; }

        utils_pending_entity_script::Promise_OnConstructed(
            _Helper.PendingEntity,
            FCk_Delegate_EntityScript_Constructed(this, n"OnEntityReady"));
    }

    UFUNCTION()
    private void OnEntityReady(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        if (IsFinished()) { return; }

        auto OwnedEntity = FCk_Handle(InEntityScriptHandle);
        auto OwnedTransform = OwnedEntity.As_Transform();
        _Camera = utils_camera::Add(OwnedTransform, FCk_Fragment_Camera_ParamsData(_Helper.CameraComponent));

        _Phase  = 0;
        _Frames = 0;
        WaitOneFrame(n"OnFrame");
    }

    UFUNCTION()
    private void OnFrame(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _Frames += 1;

        const float32 Fov = _Camera.Get_ComposedProfile().Get_Sensor().Get_FOV();

        if (_Phase == 0)
        {
            // At rest (no gameplay layers): default layer is present but not counted, and the base FOV is live.
            if (Near(Fov, 90.0f))
            {
                Assert_Equals_Int(_Camera.Get_LayerCount(), 0, "default layer is not counted as a gameplay layer at rest");

                auto Request = FCk_Request_Camera_AddLayer(UCk_AutoTest_CameraLayer_FovAdd30);
                Request.Set_BlendInTime(FCk_Time(0.02));
                _Camera.Request_AddLayer(Request);
                Advance();
                return;
            }
            if (FailIfStuck(f"resting FOV was not the base 90 (got {Fov})")) { return; }
        }
        else if (_Phase == 1)
        {
            // Feature layer blended in over the base.
            if (Near(Fov, 120.0f))
            {
                Assert_Equals_Int(_Camera.Get_LayerCount(), 1, "one gameplay layer over the default base");

                auto Request = FCk_Request_Camera_RemoveLayer(UCk_AutoTest_CameraLayer_FovAdd30);
                Request.Set_BlendOutTime(FCk_Time(0.02));
                _Camera.Request_RemoveLayer(Request);
                Advance();
                return;
            }
            if (FailIfStuck(f"feature layer never blended FOV to 120 (got {Fov})")) { return; }
        }
        else // _Phase == 2
        {
            // Feature layer gone → composed profile rests back on the (never-pruned) default layer's base.
            if (Near(Fov, 90.0f))
            {
                Assert_Equals_Int(_Camera.Get_LayerCount(), 0, "back to zero gameplay layers; default layer persists");
                FinishSuccess();
                return;
            }
            if (FailIfStuck(f"FOV never returned to the base 90 after removing the only feature layer (got {Fov})")) { return; }
        }

        WaitOneFrame(n"OnFrame");
    }

    private bool Near(float32 InValue, float32 InTarget) const
    {
        return Math::Abs(InValue - InTarget) < 0.5f;
    }

    private void Advance()
    {
        _Phase  += 1;
        _Frames  = 0;
        WaitOneFrame(n"OnFrame");
    }

    private bool FailIfStuck(const FString& InMessage)
    {
        if (_Frames > 40)
        {
            FinishFailure(InMessage);
            return true;
        }
        return false;
    }
}
