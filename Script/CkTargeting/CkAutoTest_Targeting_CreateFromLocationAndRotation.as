// Language=angelscript
//
// CK TARGETING - AUTOMATION TEST: Create_FromLocationAndRotation round-trip
// Both the location and the rotation should be preserved on the spawned
// TargetPoint entity.

class UCk_AutoTest_Targeting_CreateFromLocationAndRotation : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private const FVector SeedLocation = FVector(25.0f, -10.0f, 5.0f);
    private const FRotator SeedRotation = FRotator(0.0f, 45.0f, 0.0f);
    private const float32 ToleranceCm = 0.1f;
    private const float32 ToleranceDeg = 0.1f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        auto TargetPoint = utils_target_point::Create_FromLocationAndRotation(
            LocalHandle, SeedLocation, SeedRotation, ECk_Lifetime::UntilDestroyed);

        Assert_True(utils_handle::Get_IsValid(TargetPoint),
            "Create_FromLocationAndRotation should return a valid TargetPoint handle");

        auto ActualLoc = utils_transform::Get_EntityCurrentLocation(TargetPoint);
        Assert_True(ActualLoc.Equals(SeedLocation, ToleranceCm),
            f"Location should round-trip; expected {SeedLocation}, got {ActualLoc}");

        auto ActualRot = utils_transform::Get_EntityCurrentRotation(TargetPoint);
        Assert_True(ActualRot.Equals(SeedRotation, ToleranceDeg),
            f"Rotation should round-trip; expected {SeedRotation}, got {ActualRot}");

        FinishSuccess();
    }
}
