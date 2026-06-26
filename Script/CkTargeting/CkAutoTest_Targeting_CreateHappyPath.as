// Language=angelscript
//
// CK TARGETING — AUTOMATION TEST: Create happy path
// Create(owner, transform) returns a valid FCk_Handle_Transform whose
// current location matches the seed transform.

class UCk_AutoTest_Targeting_CreateHappyPath : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private const FVector SeedLocation = FVector(100.0f, 200.0f, 300.0f);
    private const float32 ToleranceCm = 0.1f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        auto TargetPoint = utils_target_point::Create(
            LocalHandle, FTransform(SeedLocation), ECk_Lifetime::UntilDestroyed);

        Assert_True(utils_handle::Get_IsValid(TargetPoint),
            "Create should return a valid FCk_Handle_Transform");

        auto ActualLoc = utils_transform::Get_EntityCurrentLocation(TargetPoint);
        Assert_True(ActualLoc.Equals(SeedLocation, ToleranceCm),
            f"TargetPoint location should match seed; expected {SeedLocation}, got {ActualLoc}");

        FinishSuccess();
    }
}
