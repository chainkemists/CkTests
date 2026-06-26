// Language=angelscript

//============================================================================
// CK CAMERA — AUTOMATION TEST: OVERRIDE LAYER RETURNS TO BASE ON REMOVAL
//============================================================================
//
// Direct regression for the scooter "arm stuck at 300" bug, on the rig attribute it surfaced on. With the default
// profile the BoomArmLength base is 300. A single Override layer drives it to 600; removing the layer must blend the
// arm all the way back to the base 300 (not leave a residual). Override is realized additively as (target - base)*α,
// so on removal (α → 0) the contribution vanishes and the attribute rests on its base value.
//============================================================================

class UCk_AutoTest_GameplayCamera_OverrideReturnsToBase : UCk_AutoTest_Base
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
        _Camera = utils_camera::Add(OwnedEntity, FCk_Fragment_Camera_ParamsData(_Helper.CameraComponent));

        auto Request = FCk_Request_Camera_AddLayer(UCk_AutoTest_CameraLayer_ArmOverride600);
        Request.Set_BlendInTime(FCk_Time(0.02));
        _Camera.Request_AddLayer(Request);

        _Phase  = 0;
        _Frames = 0;
        WaitOneFrame(n"OnFrame");
    }

    UFUNCTION()
    private void OnFrame(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _Frames += 1;

        const float32 Arm = _Camera.Get_ComposedProfile().Get_Rig().Get_BoomArmLength();

        if (_Phase == 0)
        {
            if (Near(Arm, 600.0f))
            {
                Assert_Equals_Int(_Camera.Get_LayerCount(), 1, "override layer live");

                auto Request = FCk_Request_Camera_RemoveLayer(UCk_AutoTest_CameraLayer_ArmOverride600);
                Request.Set_BlendOutTime(FCk_Time(0.02));
                _Camera.Request_RemoveLayer(Request);
                Advance();
                return;
            }
            if (FailIfStuck(f"override never drove arm length to 600 (got {Arm})")) { return; }
        }
        else // _Phase == 1
        {
            // Gate on the prune so the base-value assertion isn't read mid-blend-out.
            if (_Camera.Has_Layer(UCk_AutoTest_CameraLayer_ArmOverride600) == false)
            {
                Assert_Equals_Int(_Camera.Get_LayerCount(), 0, "override layer pruned");
                Assert_True(Near(Arm, 300.0f), f"arm length returned to the base 300 after removing the override (got {Arm})");
                FinishSuccess();
                return;
            }
            if (FailIfStuck(f"override layer was never pruned after removal (arm {Arm})")) { return; }
        }

        WaitOneFrame(n"OnFrame");
    }

    private bool Near(float32 InValue, float32 InTarget) const
    {
        return Math::Abs(InValue - InTarget) < 1.0f;
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
