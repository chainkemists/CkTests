// Language=angelscript

//============================================================================
// CK CAMERA — AUTOMATION TEST: GAMEPLAYCAMERA ADD LAYER
//============================================================================
//
// Pushing a layer onto the camera creates exactly one live layer entity, discoverable by class.
// Uses the actor-backed entity helper because the GameplayCamera director's Add ensures an OwningActor.
//============================================================================

class UCk_AutoTest_GameplayCamera_AddLayer : UCk_AutoTest_Base
{
    private ACkAutoTest_GameplayCamera_Helper _Helper;
    private FCk_Handle_Camera       _Camera;

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

        auto Request = FCk_Request_Camera_AddLayer(UCk_AutoTest_CameraLayer_A);
        Request.Set_BlendInTime(FCk_Time(0.02));
        _Camera.Request_AddLayer(Request);

        // One frame for HandleRequests to spawn + connect the modifier entity.
        WaitOneFrame(n"OnSettled");
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_Camera.Get_LayerCount(), 1, "one modifier present after AddLayer");
        Assert_True(_Camera.Has_Layer(UCk_AutoTest_CameraLayer_A), "Has_Layer(A) is true after add");

        FinishSuccess();
    }
}
