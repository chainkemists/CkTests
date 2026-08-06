// Language=angelscript

//============================================================================
// CK CAMERA — AUTOMATION TEST: ONEONLY EVICTS ONLY ITS OWN PRIORITY SLOT
//============================================================================
//
// OneOnly stacking evicts existing layers at the SAME priority only — layers at a different priority coexist. This
// complements the OneOnlyEvicts test (which proves same-priority eviction) by proving the priority-slot boundary:
//
//   add A (OneOnly, p0)            -> { A }
//   add B (OneOnly, p1)            -> { A, B }   (B does NOT evict A — different slot)
//   add C (OneOnly, p0)            -> { B, C }   (C evicts A — same slot — but leaves B at p1 alone)
//============================================================================

class UCk_AutoTest_GameplayCamera_OneOnlyPrioritySlots : UCk_AutoTest_Base
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
        _Camera = utils_camera::Add(OwnedEntity, FCk_Camera_Spec(_Helper.CameraComponent));

        AddOneOnly(UCk_AutoTest_CameraLayer_A, 0);

        _Phase  = 0;
        _Frames = 0;
        WaitOneFrame(n"OnFrame");
    }

    UFUNCTION()
    private void OnFrame(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _Frames += 1;

        if (_Phase == 0)
        {
            if (_Camera.Get_LayerCount() == 1)
            {
                Assert_True(_Camera.Has_Layer(UCk_AutoTest_CameraLayer_A), "A (p0) present");

                AddOneOnly(UCk_AutoTest_CameraLayer_B, 1);
                Advance();
                return;
            }
            if (FailIfStuck("layer A never became live")) { return; }
        }
        else if (_Phase == 1)
        {
            if (_Camera.Get_LayerCount() == 2)
            {
                Assert_True(_Camera.Has_Layer(UCk_AutoTest_CameraLayer_A), "A (p0) still present — not evicted by B at a different priority");
                Assert_True(_Camera.Has_Layer(UCk_AutoTest_CameraLayer_B), "B (p1) coexists with A");

                AddOneOnly(UCk_AutoTest_CameraLayer_C, 0);
                Advance();
                return;
            }
            if (FailIfStuck("B (p1) did not coexist with A (p0) — expected 2 layers")) { return; }
        }
        else // _Phase == 2
        {
            // C (p0) evicts A (same slot); B (p1) survives. Wait for A's blend-out + prune.
            if (_Camera.Has_Layer(UCk_AutoTest_CameraLayer_A) == false)
            {
                Assert_Equals_Int(_Camera.Get_LayerCount(), 2, "two layers after same-slot eviction (B + C)");
                Assert_True(_Camera.Has_Layer(UCk_AutoTest_CameraLayer_B), "B (p1) untouched by the p0 eviction");
                Assert_True(_Camera.Has_Layer(UCk_AutoTest_CameraLayer_C), "C (p0) is the surviving p0 layer");
                FinishSuccess();
                return;
            }
            if (FailIfStuck("C (p0) never evicted A (p0)")) { return; }
        }

        WaitOneFrame(n"OnFrame");
    }

    private void AddOneOnly(TSubclassOf<UCk_CameraLayer_EntityScript> InClass, int32 InPriority)
    {
        auto Request = FCk_Request_Camera_AddLayer(InClass);
        Request.Set_Priority(InPriority);
        Request.Set_StackingBehavior(ECk_Camera_StackingBehavior::OneOnly);
        Request.Set_BlendInTime(FCk_Time(0.02));
        _Camera.Request_AddLayer(Request);
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
