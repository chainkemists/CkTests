// Language=angelscript

//============================================================================
// CK TRANSFORM — AUTOMATION TEST: REQUEST SET LOCATION
//============================================================================
//
// Verifies Request_SetLocation deferred update:
//   1. Add transform at origin.
//   2. Issue Request_SetLocation to (500, 0, 0) in world space.
//   3. Poll Get_EntityCurrentLocation each tick until it matches.
//   4. Harness timeout catches the regression where the request never lands.
//============================================================================

class UCk_AutoTest_Transform_SetLocation : UCk_AutoTest_Base
{
    private FCk_Handle_Transform _Transform;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        _Transform = utils_transform::Add(
            LocalHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        utils_transform::Request_SetLocation(
            _Transform, FVector(500.0f, 0.0f, 0.0f), ECk_LocalWorld::World);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Location = utils_transform::Get_EntityCurrentLocation(_Transform);
        if (Location.X == 500.0f && Location.Y == 0.0f && Location.Z == 0.0f)
        {
            Assert_True(true, "Request_SetLocation should land within harness timeout");
            FinishSuccess();
        }
    }
}
