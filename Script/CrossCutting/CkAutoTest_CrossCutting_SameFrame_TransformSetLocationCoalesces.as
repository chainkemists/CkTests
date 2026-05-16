// Language=angelscript

//============================================================================
// CK CROSS-CUTTING — AUTOMATION TEST: SAME-FRAME SetLocation COALESCES
//============================================================================
//
// Pins the documented same-frame coalescing contract for Transform:
//   Two Request_SetLocation calls issued in one tick must yield ONE OnUpdate
//   broadcast carrying the FINAL location.
//
// The refactor is expected to simplify processor logic. This test catches a
// regression where simplification produces two broadcasts (signals fan-out
// per-request instead of per-coalesced-result) or zero broadcasts (loses
// the second write).
//
// Setup:
//   - Add a Transform.
//   - Bind OnUpdate, counting fires.
//   - Issue Request_SetLocation(A) then Request_SetLocation(B) before any
//     processor tick.
//   - Wait several ticks.
//
// Pass: OnUpdate fired exactly once; observed location ~= B.
// Fail: count != 1 (two fires, or none) or final location != B.
//============================================================================

class UCk_AutoTest_CrossCutting_SameFrame_TransformSetLocationCoalesces : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private const FVector LocationA = FVector(100.0f, 0.0f, 0.0f);
    private const FVector LocationB = FVector(500.0f, 0.0f, 0.0f);
    private const float32 ToleranceCm = 1.0f;

    private FCk_Handle_Transform _Transform;
    private int32 _UpdateCount = 0;
    private int32 _TickCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        _Transform = utils_transform::Add(LocalHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        utils_transform::BindTo_OnUpdate(_Transform,
            FCk_Delegate_Transform_OnUpdate(this, n"OnTransformUpdate"));

        // Two writes in one frame — the processor's coalesce contract says
        // exactly one OnUpdate fires, carrying LocationB.
        utils_transform::Request_SetLocation(_Transform, LocationA, ECk_LocalWorld::World);
        utils_transform::Request_SetLocation(_Transform, LocationB, ECk_LocalWorld::World);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTransformUpdate(FCk_Handle_Transform InHandle, FTransform InTransform)
    {
        _UpdateCount++;
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _TickCount++;
        if (_TickCount < 5) { return; }

        Assert_Equals_Int(_UpdateCount, 1,
            "Two same-frame Request_SetLocation calls should coalesce into ONE OnUpdate broadcast");

        auto ActualLoc = utils_transform::Get_EntityCurrentLocation(_Transform);
        Assert_True(ActualLoc.Equals(LocationB, ToleranceCm),
            f"Final transform location should equal LocationB (the second write); expected {LocationB}, got {ActualLoc}");

        FinishSuccess();
    }
}
