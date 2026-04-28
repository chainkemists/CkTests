#pragma once

#include "CoreMinimal.h"

#include "CkAutoTest_Bridge.generated.h"

UENUM(BlueprintType)
enum class ECk_AutoTest_Status : uint8
{
    Pending,
    Running,
    Passed,
    Failed,
    TimedOut
};

USTRUCT(BlueprintType)
struct CKTESTS_API FCk_AutoTest_Result
{
    GENERATED_BODY()

public:
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Ck|AutoTest")
    ECk_AutoTest_Status Status = ECk_AutoTest_Status::Pending;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Ck|AutoTest")
    FString FailureMessage;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Ck|AutoTest")
    int32 AssertionsRun = 0;

    UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Ck|AutoTest")
    int32 AssertionsFailed = 0;
};
