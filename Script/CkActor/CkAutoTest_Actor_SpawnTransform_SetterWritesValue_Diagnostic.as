// Language=angelscript

//============================================================================
// CK ACTOR - DIAGNOSTIC: Set_SpawnTransform writes value into AS-built params
//============================================================================
//
// Isolates whether the SpawnTransform write itself fails in AS. The full
// SpawnActor functional test saw spawned actors at the origin even after
// setting SpawnTransform; this test takes the actor spawn out of the
// picture and asks whether the AS-side setter even mutates the struct.
//
// If Get_SpawnTransform returns the just-set value:
//   -> AS setter works; the propagation loss is downstream (request copy
//     / processor read / deferred spawn).
// If Get_SpawnTransform returns Identity:
//   -> AS setter is the problem (either binding isn't generated for
//     FTransform-valued CK_PROPERTY setters, or AS's by-value-struct
//     semantics drop the local mutation).
//============================================================================

class UCk_AutoTest_Actor_SpawnTransform_SetterWritesValue_Diagnostic : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 2.0f;

    private const FVector ExpectedLocation = FVector(450.0f, 250.0f, 75.0f);
    private const FRotator ExpectedRotation = FRotator(0.0f, 45.0f, 0.0f);
    private const float32 PositionToleranceCm = 0.01f;
    private const float32 RotationToleranceDeg = 0.01f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto SpawnParams = FCk_Utils_Actor_SpawnActor_Params();

        auto BeforeXform = SpawnParams.Get_SpawnTransform();
        Assert_True(BeforeXform.GetLocation().Equals(FVector::ZeroVector, PositionToleranceCm),
            f"Default SpawnTransform should be Identity (got loc {BeforeXform.GetLocation()})");

        auto NewXform = FTransform(ExpectedRotation, ExpectedLocation, FVector::OneVector);
        SpawnParams.Set_SpawnTransform(NewXform);

        auto AfterXform = SpawnParams.Get_SpawnTransform();
        Assert_True(AfterXform.GetLocation().Equals(ExpectedLocation, PositionToleranceCm),
            f"After Set_SpawnTransform, Get_SpawnTransform location | expected {ExpectedLocation}, got {AfterXform.GetLocation()}");
        Assert_True(AfterXform.GetRotation().Rotator().Equals(ExpectedRotation, RotationToleranceDeg),
            f"After Set_SpawnTransform, Get_SpawnTransform rotation | expected {ExpectedRotation}, got {AfterXform.GetRotation().Rotator()}");

        // Also test propagation through the Request struct constructor
        // if SpawnParams holds the value but the request's _SpawnParams
        // copy drops it, the failure is in the request-side struct copy
        // (CK_DEFINE_CONSTRUCTOR / std::move chain).
        auto Req = FCk_Request_ActorModifier_SpawnActor(SpawnParams);
        auto ReqStoredXform = Req.Get_SpawnParams().Get_SpawnTransform();
        Assert_True(ReqStoredXform.GetLocation().Equals(ExpectedLocation, PositionToleranceCm),
            f"Request stored SpawnTransform location | expected {ExpectedLocation}, got {ReqStoredXform.GetLocation()}");

        FinishSuccess();
    }
}
