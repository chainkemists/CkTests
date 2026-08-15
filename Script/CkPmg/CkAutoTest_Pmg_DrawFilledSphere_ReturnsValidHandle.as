// Language=angelscript

//============================================================================
// CK PMG — AUTOMATION TEST: DRAW FILLED SPHERE RETURNS VALID HANDLE
//============================================================================
//
// Pmg drawing primitives spawn debug-shape entities tracked by a returned
// FCk_Handle_Pmg_DebugShape. This test verifies both the immediate handle
// contract and that a filled shape can be set up again after the first shape,
// its mesh, and its material references have been torn down across a full GC.
//============================================================================

class UCk_AutoTest_Pmg_DrawFilledSphere_ReturnsValidHandle : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle_Pmg_DebugShape _FirstShape;
    private FCk_Handle_Pmg_DebugShape _SecondShape;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _FirstShape = utils_pmg_basic_shapes::DrawFilledSphere(
            FVector(0.0f, 0.0f, 0.0f),
            25.0f, 12, 12,
            FLinearColor::White,
            true, 2.0f, ECk_Plane_Axis::XY, -1.0f);

        Assert_True(ck::IsValid(_FirstShape),
            "DrawFilledSphere should return a valid FCk_Handle_Pmg_DebugShape");
        if (IsFinished()) { return; }

        // Request handling is excluded from NeedsSetup, so completion proves
        // that the first mesh-setup processor pass has completed.
        utils_pmg_debug_shape::Request_SetColor(
            _FirstShape,
            FCk_Request_Pmg_DebugShape_SetColor(FLinearColor::Red),
            FCk_Delegate_Request_OnCompleted(this, n"OnFirstShapeReady"));
    }

    UFUNCTION()
    private void OnFirstShapeReady(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        if (IsFinished()) { return; }

        Assert_True(InRequestOwner == FCk_Handle(_FirstShape),
            "the first setup completion should report the first shape as its request owner");
        Assert_True(InResult == ECk_Request_OperationResult::Succeeded,
            f"the first shape setup fence should complete successfully (got {InResult})");
        if (IsFinished()) { return; }

        utils_entity_lifetime::Request_DestroyEntity(FCk_Handle(_FirstShape));
        WaitUntil(n"Check_FirstShapeDestroyed", n"OnFirstShapeDestroyed");
    }

    UFUNCTION()
    private void Check_FirstShapeDestroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(ck::Is_NOT_Valid(_FirstShape));
    }

    UFUNCTION()
    private void OnFirstShapeDestroyed(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _FirstShape = utils_pmg_debug_shape::Get_InvalidHandle();
        System::CollectGarbage();
        WaitOneFrame(n"OnGarbageCollectionSettled");
    }

    UFUNCTION()
    private void OnGarbageCollectionSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _SecondShape = utils_pmg_basic_shapes::DrawFilledSphere(
            FVector(100.0f, 0.0f, 0.0f),
            25.0f, 12, 12,
            FLinearColor::White,
            true, 2.0f, ECk_Plane_Axis::XY, -1.0f);

        Assert_True(ck::IsValid(_SecondShape),
            "DrawFilledSphere should return a valid handle after teardown and full GC");
        if (IsFinished()) { return; }

        utils_pmg_debug_shape::Request_SetColor(
            _SecondShape,
            FCk_Request_Pmg_DebugShape_SetColor(FLinearColor::Green),
            FCk_Delegate_Request_OnCompleted(this, n"OnSecondShapeReady"));
    }

    UFUNCTION()
    private void OnSecondShapeReady(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        if (IsFinished()) { return; }

        Assert_True(InRequestOwner == FCk_Handle(_SecondShape),
            "the post-GC setup completion should report the second shape as its request owner");
        Assert_True(InResult == ECk_Request_OperationResult::Succeeded,
            f"the post-GC shape setup fence should complete successfully (got {InResult})");
        if (IsFinished()) { return; }

        utils_entity_lifetime::Request_DestroyEntity(FCk_Handle(_SecondShape));
        WaitUntil(n"Check_SecondShapeDestroyed", n"OnSecondShapeDestroyed");
    }

    UFUNCTION()
    private void Check_SecondShapeDestroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(ck::Is_NOT_Valid(_SecondShape));
    }

    UFUNCTION()
    private void OnSecondShapeDestroyed(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _SecondShape = utils_pmg_debug_shape::Get_InvalidHandle();
        FinishSuccess();
    }
}
