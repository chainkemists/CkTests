#pragma once

#include "CoreMinimal.h"

#include "CkAutoTest_Bridge.h"

#include "CkEcs/Handle/CkHandle.h"
#include "CkGoap/Planner/CkGoap_Planner_Utils.h"

#include "CkAutoTest_Utils.generated.h"

// Read-only measurement of the published rig, independent of the candidate selector's scoring implementation.
USTRUCT(BlueprintType)
struct CKTESTS_API FCk_AutoTest_ProceduralRigMetrics
{
    GENERATED_BODY()
    CK_GENERATED_BODY(FCk_AutoTest_ProceduralRigMetrics);

private:
    UPROPERTY(BlueprintReadOnly, meta = (AllowPrivateAccess = true))
    bool _Ready = false;

    UPROPERTY(BlueprintReadOnly, meta = (AllowPrivateAccess = true))
    double _TotalPenetrationSquared = 0.0;

    UPROPERTY(BlueprintReadOnly, meta = (AllowPrivateAccess = true))
    double _MaximumPenetration = 0.0;

    UPROPERTY(BlueprintReadOnly, meta = (AllowPrivateAccess = true))
    int32 _OverlappingPairs = 0;

    UPROPERTY(BlueprintReadOnly, meta = (AllowPrivateAccess = true))
    double _MaximumJointGap = 0.0;

    UPROPERTY(BlueprintReadOnly, meta = (AllowPrivateAccess = true))
    double _MaximumFootGap = 0.0;

    UPROPERTY(BlueprintReadOnly, meta = (AllowPrivateAccess = true))
    int64 _SampleSequence = 0;

public:
    CK_PROPERTY(_Ready);
    CK_PROPERTY(_TotalPenetrationSquared);
    CK_PROPERTY(_MaximumPenetration);
    CK_PROPERTY(_OverlappingPairs);
    CK_PROPERTY(_MaximumJointGap);
    CK_PROPERTY(_MaximumFootGap);
    CK_PROPERTY(_SampleSequence);
};

UCLASS()
class CKTESTS_API UCk_Utils_AutoTest_UE : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()

public:
    UFUNCTION(BlueprintCallable, Category = "Ck|Utils|AutoTest",
              DisplayName = "[Ck][AutoTest] Set Result")
    static void
    Set_Result(
        UPARAM(ref) FCk_Handle& InHandle,
        ECk_AutoTest_Status InStatus,
        const FString& InFailureMessage,
        int32 InAssertionsRun,
        int32 InAssertionsFailed);

    UFUNCTION(BlueprintPure, Category = "Ck|Utils|AutoTest",
              DisplayName = "[Ck][AutoTest] Has Result")
    static bool
    Has_Result(
        const FCk_Handle& InHandle);

    UFUNCTION(BlueprintPure, Category = "Ck|Utils|AutoTest",
              DisplayName = "[Ck][AutoTest] Get Result")
    static FCk_AutoTest_Result
    Get_Result(
        const FCk_Handle& InHandle);

    // ----- Console variables: scoped push/pop, for the AS base's Set_CVarForTest -----
    //
    // Restoring a CVar means restoring its VALUE **and its SetBy priority**. Writing the old value
    // back at ECVF_SetByConsole leaves the variable pinned at console priority, so the next thing
    // that legitimately sets it at a lower priority (scalability, device profile, project setting)
    // is silently ignored for the rest of the process. The prior value/priority pair is therefore
    // captured here in C++, where IConsoleVariable exposes both, rather than in AngelScript.
    //
    // Capture is once-per-name and first-writer-wins; a second push while an override is live does
    // not re-capture (it would record the overridden value as the "prior"). Pop is idempotent.

    UFUNCTION(BlueprintPure, Category = "Ck|Utils|AutoTest",
              DisplayName = "[Ck][AutoTest] Get CVar Exists")
    static bool
    Get_CVarExists(
        FName InName);

    // Capture the current value+priority, then set InValue at ECVF_SetByConsole.
    UFUNCTION(BlueprintCallable, Category = "Ck|Utils|AutoTest",
              DisplayName = "[Ck][AutoTest] Request Push CVar Override")
    static void
    Request_PushCVarOverride(
        FName InName,
        const FString& InValue);

    // Capture the current value+priority WITHOUT changing it — for a variable that some engine
    // path (a HighResShot, a screenshot request) is about to move on the test's behalf.
    UFUNCTION(BlueprintCallable, Category = "Ck|Utils|AutoTest",
              DisplayName = "[Ck][AutoTest] Request Push CVar Snapshot")
    static void
    Request_PushCVarSnapshot(
        FName InName);

    // Put back what was captured, priority included, and forget it. No-op if nothing was captured.
    UFUNCTION(BlueprintCallable, Category = "Ck|Utils|AutoTest",
              DisplayName = "[Ck][AutoTest] Request Pop CVar Override")
    static void
    Request_PopCVarOverride(
        FName InName);

    // Deliberately creates one active-planner invariant failure only for focused negative coverage, then restores
    // the removed fragment on the same stack before returning.
    UFUNCTION(BlueprintCallable, Category = "Ck|Utils|AutoTest", meta = (DevelopmentOnly))
    static bool
    TryGet_GoapLastSearchDebugWithoutWorldStateSource_ForTesting(
        const FCk_Handle_Goap_Planner& InPlanner,
        UPARAM(ref) TArray<FCk_Goap_SearchDebugRow>& OutRows);

    // Test-only, read-only summary of one leg's last accepted procedural-animation solve.
    UFUNCTION(BlueprintPure, Category = "Ck|Utils|AutoTest", meta = (DevelopmentOnly))
    static FString
    Get_ProceduralAnimationLegSnapshot(
        const FCk_Handle& InBody,
        FName InLegId,
        FVector InOrigin);

    // Radii are flattened in captured leg/segment order, so a legacy rig can be measured with the same geometry.
    // Ready is false until the accepted gait and fully published rig poses agree and every requested part is live.
    UFUNCTION(BlueprintPure, Category = "Ck|Utils|AutoTest", meta = (DevelopmentOnly))
    static FCk_AutoTest_ProceduralRigMetrics
    Get_ProceduralAnimationRigMetrics(
        const FCk_Handle& InBody,
        const TArray<float>& InSegmentRadii);
};
