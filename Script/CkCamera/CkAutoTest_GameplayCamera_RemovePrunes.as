// Language=angelscript

//============================================================================
// CK CAMERA — AUTOMATION TEST: GAMEPLAYCAMERA REMOVE PRUNES
//============================================================================
//
// RemoveLayer blends the modifier out and prunes it; the modifier count returns to zero.
//============================================================================

class UCk_AutoTest_GameplayCamera_RemovePrunes : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private ACkAutoTest_GameplayCamera_Helper _Helper;
    private FCk_Handle_Camera       _Camera;
    private int32                           _Frames = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
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

        auto Request = FCk_Request_Camera_AddLayer(UCk_AutoTest_CameraLayer_A);
        Request.Set_BlendInTime(FCk_Time(0.02));
        _Camera.Request_AddLayer(Request);

        WaitOneFrame(n"OnAfterAdd");
    }

    UFUNCTION()
    private void OnAfterAdd(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_Camera.Get_LayerCount(), 1, "one modifier present before removal");

        auto Request = FCk_Request_Camera_RemoveLayer(UCk_AutoTest_CameraLayer_A);
        Request.Set_BlendOutTime(FCk_Time(0.02));
        _Camera.Request_RemoveLayer(Request);

        _Frames = 0;
        WaitForPrune();
    }

    private void WaitForPrune()
    {
        if (_Frames < 5)
        {
            _Frames += 1;
            WaitOneFrame(n"OnPruneFrame");
        }
        else
        {
            DoAssert();
        }
    }

    UFUNCTION()
    private void OnPruneFrame(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        WaitForPrune();
    }

    private void DoAssert()
    {
        Assert_Equals_Int(_Camera.Get_LayerCount(), 0, "modifier pruned to zero after blend-out");
        FinishSuccess();
    }
}
