#pragma once

#include "CoreMinimal.h"

#include "CkAutoTest_Bridge.h"

#include "CkEcs/Handle/CkHandle.h"

#include "CkAutoTest_Utils.generated.h"

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
};
