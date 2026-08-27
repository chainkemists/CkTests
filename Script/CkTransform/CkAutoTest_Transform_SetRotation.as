// Language=angelscript

//============================================================================
// CK TRANSFORM - AUTOMATION TEST: REQUEST SET ROTATION
//============================================================================
//
// Verifies Request_SetRotation deferred update:
//   1. Add transform with identity rotation.
//   2. Issue Request_SetRotation to (45, 90, 135) in world space.
//   3. Poll Get_EntityCurrentRotation each tick until it matches.
//============================================================================

class UCk_AutoTest_Transform_SetRotation : UCk_AutoTest_Base
{
    private FCk_Handle_Transform _Transform;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        _Transform = utils_transform::Add(
            LocalHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        utils_transform::Request_SetRotation(
            _Transform, FRotator(45.0f, 90.0f, 135.0f), ECk_LocalWorld::World);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // FRotator round-trips through FQuat lose precision - compare with tolerance.
        auto Tol = 0.01f;
        auto Rotation = utils_transform::Get_EntityCurrentRotation(_Transform);
        if (Math::Abs(Rotation.Pitch - 45.0f)  < Tol &&
            Math::Abs(Rotation.Yaw   - 90.0f)  < Tol &&
            Math::Abs(Rotation.Roll  - 135.0f) < Tol)
        {
            Assert_True(true, "Request_SetRotation should land within harness timeout");
            FinishSuccess();
        }
    }
}
