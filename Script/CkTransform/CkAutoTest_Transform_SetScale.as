// Language=angelscript

//============================================================================
// CK TRANSFORM — AUTOMATION TEST: REQUEST SET SCALE
//============================================================================
//
// Verifies Request_SetScale deferred update:
//   1. Add transform with identity scale (1,1,1).
//   2. Issue Request_SetScale to (2, 4, 8) in world space.
//   3. Poll Get_EntityCurrentScale each tick until it matches.
//============================================================================

class UCk_AutoTest_Transform_SetScale : UCk_AutoTest_Base
{
    private FCk_Handle_Transform _Transform;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        _Transform = utils_transform::Add(
            LocalHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        utils_transform::Request_SetScale(
            _Transform, FVector(2.0f, 4.0f, 8.0f), ECk_LocalWorld::World);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Scale = utils_transform::Get_EntityCurrentScale(_Transform);
        if (Scale.X == 2.0f && Scale.Y == 4.0f && Scale.Z == 8.0f)
        {
            Assert_True(true, "Request_SetScale should land within harness timeout");
            FinishSuccess();
        }
    }
}
