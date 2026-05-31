// Language=angelscript

//============================================================================
// CK CAMERA — AUTOMATION TEST: GAMEPLAYCAMERA ONEONLY EVICTS
//============================================================================
//
// A OneOnly modifier evicts (blends out + prunes) an existing modifier in the same ordering group.
// A and B both use the default (empty) ordering group, so they share a group.
//============================================================================

class UCk_AutoTest_GameplayCamera_OneOnlyEvicts : UCk_AutoTest_Base
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
        Request.Set_StackingBehavior(ECk_Camera_StackingBehavior::OneOnly);
        Request.Set_BlendInTime(FCk_Time(0.02));
        _Camera.Request_AddLayer(Request);

        WaitOneFrame(n"OnAfterFirst");
    }

    UFUNCTION()
    private void OnAfterFirst(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(_Camera.Has_Layer(UCk_AutoTest_CameraLayer_A), "A present before eviction");

        auto Request = FCk_Request_Camera_AddLayer(UCk_AutoTest_CameraLayer_B);
        Request.Set_StackingBehavior(ECk_Camera_StackingBehavior::OneOnly);
        Request.Set_BlendInTime(FCk_Time(0.02));
        _Camera.Request_AddLayer(Request);

        _Frames = 0;
        WaitForBlend();
    }

    private void WaitForBlend()
    {
        // Let A blend out + the destruction pipeline prune it.
        if (_Frames < 5)
        {
            _Frames += 1;
            WaitOneFrame(n"OnBlendFrame");
        }
        else
        {
            DoAssert();
        }
    }

    UFUNCTION()
    private void OnBlendFrame(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        WaitForBlend();
    }

    private void DoAssert()
    {
        Assert_Equals_Int(_Camera.Get_LayerCount(), 1, "exactly one modifier remains after OneOnly eviction");
        Assert_True(_Camera.Has_Layer(UCk_AutoTest_CameraLayer_B), "B (the new OneOnly modifier) remains");
        Assert_True(_Camera.Has_Layer(UCk_AutoTest_CameraLayer_A) == false, "A was evicted by the OneOnly push");

        FinishSuccess();
    }
}
