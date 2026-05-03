// Language=angelscript

//============================================================================
// CK TRANSFORM — AUTOMATION TEST: ADD LOCATION OFFSET
//============================================================================
//
// Verifies Request_AddLocationOffset accumulates onto the current location:
//   1. Add transform at (100, 0, 0).
//   2. Apply offset (+50, 0, 0).
//   3. Poll until Get_EntityCurrentLocation reports (150, 0, 0) — proving
//      the offset was added rather than replacing the location.
//============================================================================

class UCk_AutoTest_Transform_AddLocationOffset : UCk_AutoTest_Base
{
    private FCk_Handle_Transform _Transform;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto Initial = FTransform(FRotator::ZeroRotator, FVector(100.0f, 0.0f, 0.0f), FVector::OneVector);
        _Transform = utils_transform::Add(
            LocalHandle, Initial, ECk_Replication::DoesNotReplicate);

        utils_transform::Request_AddLocationOffset(
            _Transform, FVector(50.0f, 0.0f, 0.0f), ECk_LocalWorld::World);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Location = utils_transform::Get_EntityCurrentLocation(_Transform);
        if (Location.X == 150.0f && Location.Y == 0.0f && Location.Z == 0.0f)
        {
            Assert_True(true, "Request_AddLocationOffset should accumulate onto initial location");
            FinishSuccess();
        }
    }
}
