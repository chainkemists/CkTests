// Language=angelscript
//
// CK TARGETING — AUTOMATION TEST: Create_Transient happy path
// Create_Transient(transform, worldCtx) spawns a TargetPoint on the world's
// transient owner — independent of any specific entity owner.

class UCk_AutoTest_Targeting_CreateTransientHappyPath : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private const FVector SeedLocation = FVector(10.0f, 20.0f, 30.0f);
    private const float32 ToleranceCm = 0.1f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        // WorldContextObject is auto-supplied by the AS binding — do not pass `this`.
        auto TargetPoint = utils_target_point::Create_Transient(
            FTransform(SeedLocation), ECk_Lifetime::UntilDestroyed);

        Assert_True(utils_handle::Get_IsValid(TargetPoint),
            "Create_Transient should return a valid TargetPoint handle");

        auto ActualLoc = utils_transform::Get_EntityCurrentLocation(TargetPoint);
        Assert_True(ActualLoc.Equals(SeedLocation, ToleranceCm),
            f"Transient TargetPoint location should match seed; expected {SeedLocation}, got {ActualLoc}");

        FinishSuccess();
    }
}
