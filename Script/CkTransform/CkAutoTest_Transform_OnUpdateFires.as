// Language=angelscript

//============================================================================
// CK TRANSFORM — AUTOMATION TEST: ON-UPDATE SIGNAL FIRES
//============================================================================
//
// Verifies BindTo_OnUpdate fires when the transform actually changes:
//   1. Add transform at origin and bind OnUpdate.
//   2. Issue Request_SetLocation to (250, 0, 0).
//   3. OnUpdate callback fires; finish on first observation.
//
// Catches the regression where transform mutations don't broadcast their
// update signal — gameplay code that listens via OnUpdate (e.g. cached
// world-space queries) would silently miss updates.
//============================================================================

class UCk_AutoTest_Transform_OnUpdateFires : UCk_AutoTest_Base
{
    private FCk_Handle_Transform _Transform;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        _Transform = utils_transform::Add(
            LocalHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        utils_transform::BindTo_OnUpdate(
            _Transform,
            FCk_Delegate_Transform_OnUpdate(this, n"OnTransformUpdate"));

        utils_transform::Request_SetLocation(
            _Transform, FVector(250.0f, 0.0f, 0.0f), ECk_LocalWorld::World);
    }

    UFUNCTION()
    private void OnTransformUpdate(
        FCk_Handle_Transform InHandle,
        FTransform InTransform)
    {
        if (IsFinished()) { return; }

        Assert_True(true,
            "OnUpdate should fire after Request_SetLocation lands");
        FinishSuccess();
    }
}
