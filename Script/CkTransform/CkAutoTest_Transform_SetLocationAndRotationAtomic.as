// Language=angelscript

//============================================================================
// CK TRANSFORM — AUTOMATION TEST: ATOMIC SetLocationAndRotation
//============================================================================
//
// Pins the atomic-write contract for the combined SetLocationAndRotation
// request: a single request setting BOTH location and rotation must fire
// ONE OnUpdate broadcast carrying the final transform, not two (one per
// component).
//
// The refactor's processor simplification could regress this in either
// direction — splitting the combined request into two separate writes
// (two broadcasts), or losing one component (incomplete transform).
//
// Setup:
//   - Add a Transform at Identity.
//   - Bind OnUpdate with a counter.
//   - Issue Request_SetLocationAndRotation(NewLoc, NewRot).
//   - WaitOneFrame.
//
// Pass: OnUpdate fires exactly once; both location and rotation reflect
//   the requested values.
//============================================================================

class UCk_AutoTest_Transform_SetLocationAndRotationAtomic : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private const FVector NewLocation = FVector(150.0f, -75.0f, 200.0f);
    private const FRotator NewRotation = FRotator(0.0f, 90.0f, 0.0f);
    private const float32 PositionToleranceCm = 1.0f;
    private const float32 RotationToleranceDeg = 1.0f;

    private FCk_Handle_Transform _Transform;
    private int32 _UpdateCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        _Transform = utils_transform::Add(LocalHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        utils_transform::BindTo_OnUpdate(_Transform,
            FCk_Delegate_Transform_OnUpdate(this, n"OnTransformUpdate"));

        auto Req = FCk_Request_Transform_SetLocationAndRotation(NewLocation, NewRotation);
        Req.Set_LocalWorld(ECk_LocalWorld::World);
        utils_transform::Request_SetLocationAndRotation(_Transform, Req);

        WaitUntil(n"Check_TransformUpdated", n"OnSettled");
    }

    UFUNCTION()
    private void Check_TransformUpdated(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_UpdateCount >= 1);
    }

    UFUNCTION()
    private void OnTransformUpdate(FCk_Handle_Transform InHandle, FTransform InTransform)
    {
        _UpdateCount++;
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        Assert_Equals_Int(_UpdateCount, 1,
            "Combined SetLocationAndRotation should fire exactly one OnUpdate broadcast");

        auto ActualLoc = utils_transform::Get_EntityCurrentLocation(_Transform);
        auto ActualRot = utils_transform::Get_EntityCurrentRotation(_Transform);

        Assert_True(ActualLoc.Equals(NewLocation, PositionToleranceCm),
            f"Atomic write: location should equal NewLocation; expected {NewLocation}, got {ActualLoc}");
        Assert_True(ActualRot.Equals(NewRotation, RotationToleranceDeg),
            f"Atomic write: rotation should equal NewRotation; expected {NewRotation}, got {ActualRot}");

        FinishSuccess();
    }
}
