// Language=angelscript

//============================================================================
// CK CAMERA — AUTOMATION TEST: MULTI-LAYER STACK, MIXED OPS, MIDDLE ADD/REMOVE
//============================================================================
//
// The headline modifier-stack test. Three coexisting (Additive-stacking) layers at distinct priorities contribute
// to ONE attribute (FOV), mixing Additive and Override ops:
//
//   base FOV ............................. 90
//   p0  FovAdd30      (Additive +30) ..... +30
//   p1  FovOverride70 (Override -> 70) ... +(70-90) = -20   <-- the "middle" layer
//   p2  FovAdd5       (Additive +5) ...... +5
//   ---------------------------------------------------
//   composed (all three) ................. 90 +30 -20 +5 = 105
//
// It then REMOVES the middle layer (the Override) and asserts the other two contributions are untouched
// (90 +30 +5 = 125), then RE-ADDS a middle layer and asserts the stack returns to 105. This proves: (a) Override and
// Additive modifiers compose as independent summed deltas, (b) removing/adding a layer in the middle of the stack
// only adds/removes that layer's contribution, and (c) the live layer count tracks add/remove precisely.
//============================================================================

class UCk_AutoTest_GameplayCamera_MultiLayerMixedOps : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private ACkAutoTest_GameplayCamera_Helper _Helper;
    private FCk_Handle_Camera                 _Camera;
    private int32                             _Phase  = 0;
    private int32                             _Frames = 0;

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

        // Build the initial three-layer stack (distinct priorities, all Additive-stacking so they coexist).
        AddLayer(UCk_AutoTest_CameraLayer_FovAdd30,      0);
        AddLayer(UCk_AutoTest_CameraLayer_FovOverride70, 1);
        AddLayer(UCk_AutoTest_CameraLayer_FovAdd5,       2);

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
            // Wait for the three layers to blend fully in: 90 +30 -20 +5 = 105.
            if (Near(Fov, 105.0f))
            {
                Assert_Equals_Int(_Camera.Get_LayerCount(), 3, "three layers live with the full stack");
                Assert_True(_Camera.Has_Layer(UCk_AutoTest_CameraLayer_FovAdd30),      "FovAdd30 present");
                Assert_True(_Camera.Has_Layer(UCk_AutoTest_CameraLayer_FovOverride70), "FovOverride70 (middle) present");
                Assert_True(_Camera.Has_Layer(UCk_AutoTest_CameraLayer_FovAdd5),       "FovAdd5 present");

                // Remove the MIDDLE layer (the Override). Only its -20 should drop out.
                RemoveLayer(UCk_AutoTest_CameraLayer_FovOverride70);
                Advance();
                return;
            }
            if (FailIfStuck(f"stack never composed to 105 (got {Fov})")) { return; }
        }
        else if (_Phase == 1)
        {
            // Middle Override fully removed (blended out + pruned) → its -20 is gone and the two additive
            // contributions are untouched: 90 +30 +5 = 125. Gate on the prune (not just the value) so we don't read
            // a transient frame where the weight has nearly settled but the entity isn't pruned yet.
            if (_Camera.Has_Layer(UCk_AutoTest_CameraLayer_FovOverride70) == false)
            {
                Assert_Equals_Int(_Camera.Get_LayerCount(), 2, "two layers remain after removing the middle layer");
                Assert_True(Near(Fov, 125.0f), "removing the middle Override left the additive contributions intact (FOV 125)");
                Assert_True(_Camera.Has_Layer(UCk_AutoTest_CameraLayer_FovAdd30), "FovAdd30 contribution untouched by middle removal");
                Assert_True(_Camera.Has_Layer(UCk_AutoTest_CameraLayer_FovAdd5),  "FovAdd5 contribution untouched by middle removal");

                // Add a layer back into the middle of the stack.
                AddLayer(UCk_AutoTest_CameraLayer_FovOverride70, 1);
                Advance();
                return;
            }
            if (FailIfStuck(f"middle Override was never pruned after removal (FOV {Fov})")) { return; }
        }
        else // _Phase == 2
        {
            // Re-added middle Override → back to 90 +30 -20 +5 = 105, three layers live again.
            if (Near(Fov, 105.0f))
            {
                Assert_Equals_Int(_Camera.Get_LayerCount(), 3, "three layers live again after re-adding the middle layer");
                Assert_True(_Camera.Has_Layer(UCk_AutoTest_CameraLayer_FovOverride70), "re-added middle Override present");
                FinishSuccess();
                return;
            }
            if (FailIfStuck(f"stack never returned to 105 after re-adding the middle layer (got {Fov})")) { return; }
        }

        WaitOneFrame(n"OnFrame");
    }

    //------------------------------------------------------------------------
    // Helpers
    //------------------------------------------------------------------------

    private bool Near(float32 InValue, float32 InTarget) const
    {
        return Math::Abs(InValue - InTarget) < 0.5f;
    }

    private void AddLayer(TSubclassOf<UCk_CameraLayer_EntityScript> InClass, int32 InPriority)
    {
        auto Request = FCk_Request_Camera_AddLayer(InClass);
        Request.Set_Priority(InPriority);
        Request.Set_StackingBehavior(ECk_Camera_StackingBehavior::Additive);
        Request.Set_BlendInTime(FCk_Time(0.02));
        _Camera.Request_AddLayer(Request);
    }

    private void RemoveLayer(TSubclassOf<UCk_CameraLayer_EntityScript> InClass)
    {
        auto Request = FCk_Request_Camera_RemoveLayer(InClass);
        Request.Set_BlendOutTime(FCk_Time(0.02));
        _Camera.Request_RemoveLayer(Request);
    }

    private void Advance()
    {
        _Phase  += 1;
        _Frames  = 0;
        WaitOneFrame(n"OnFrame");
    }

    // Returns true (and finishes the test) when a phase has waited too long for its target.
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
