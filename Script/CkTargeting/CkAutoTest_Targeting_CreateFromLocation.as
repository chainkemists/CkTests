// Language=angelscript
//
// CK TARGETING — AUTOMATION TEST: Create_FromLocation round-trip
// Create_FromLocation(loc) yields a TargetPoint whose current location
// matches the seed FVector.

class UCk_AutoTest_Targeting_CreateFromLocation : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private const FVector SeedLocation = FVector(50.0f, -50.0f, 75.0f);
    private const float32 ToleranceCm = 0.1f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        auto TargetPoint = utils_target_point::Create_FromLocation(
            LocalHandle, SeedLocation, ECk_Lifetime::UntilDestroyed);

        Assert_True(utils_handle::Get_IsValid(TargetPoint),
            "Create_FromLocation should return a valid TargetPoint handle");

        auto ActualLoc = utils_transform::Get_EntityCurrentLocation(TargetPoint);
        Assert_True(ActualLoc.Equals(SeedLocation, ToleranceCm),
            f"Location should round-trip; expected {SeedLocation}, got {ActualLoc}");

        FinishSuccess();
    }
}
