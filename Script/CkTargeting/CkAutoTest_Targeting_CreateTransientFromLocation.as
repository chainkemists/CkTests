// Language=angelscript
//
// CK TARGETING — AUTOMATION TEST: Create_Transient_FromLocation round-trip

class UCk_AutoTest_Targeting_CreateTransientFromLocation : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private const FVector SeedLocation = FVector(-15.0f, 30.0f, 0.0f);
    private const float32 ToleranceCm = 0.1f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        // WorldContextObject is auto-supplied by the AS binding — do not pass `this`.
        auto TargetPoint = utils_target_point::Create_Transient_FromLocation(
            SeedLocation, ECk_Lifetime::UntilDestroyed);

        Assert_True(utils_handle::Get_IsValid(TargetPoint),
            "Create_Transient_FromLocation should return a valid TargetPoint handle");

        auto ActualLoc = utils_transform::Get_EntityCurrentLocation(TargetPoint);
        Assert_True(ActualLoc.Equals(SeedLocation, ToleranceCm),
            f"Location should round-trip; expected {SeedLocation}, got {ActualLoc}");

        FinishSuccess();
    }
}
