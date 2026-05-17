// Language=angelscript
//
// CK TARGETING — AUTOMATION TEST: Create_Transient_FromLocationAndRotation round-trip

class UCk_AutoTest_Targeting_CreateTransientFromLocationAndRotation : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private const FVector SeedLocation = FVector(0.0f, 100.0f, -50.0f);
    private const FRotator SeedRotation = FRotator(0.0f, -90.0f, 0.0f);
    private const float32 ToleranceCm = 0.1f;
    private const float32 ToleranceDeg = 0.1f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        // WorldContextObject is auto-supplied by the AS binding — do not pass `this`.
        auto TargetPoint = utils_target_point::Create_Transient_FromLocationAndRotation(
            SeedLocation, SeedRotation, ECk_Lifetime::UntilDestroyed);

        Assert_True(utils_handle::Get_IsValid(TargetPoint),
            "Create_Transient_FromLocationAndRotation should return a valid TargetPoint handle");

        auto ActualLoc = utils_transform::Get_EntityCurrentLocation(TargetPoint);
        Assert_True(ActualLoc.Equals(SeedLocation, ToleranceCm),
            f"Location should round-trip; expected {SeedLocation}, got {ActualLoc}");

        auto ActualRot = utils_transform::Get_EntityCurrentRotation(TargetPoint);
        Assert_True(ActualRot.Equals(SeedRotation, ToleranceDeg),
            f"Rotation should round-trip; expected {SeedRotation}, got {ActualRot}");

        FinishSuccess();
    }
}
