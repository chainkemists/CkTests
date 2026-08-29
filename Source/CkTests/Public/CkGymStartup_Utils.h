#pragma once

#include "CoreMinimal.h"

#include "CkGym_StartupSettings.h"

#include <Kismet/BlueprintFunctionLibrary.h>

#include "CkGymStartup_Utils.generated.h"

// --------------------------------------------------------------------------------------------------------------------
//
// AngelScript / Blueprint bridge to UCkGym_StartupSettings.
//
// Named with the codebase's `UCk_Utils_X_UE` convention so the AngelScript
// plugin doesn't strip the suffix (the default strip list includes
// "FunctionLibrary"; using `_UE` keeps the namespace intact in AS).
//
// AS callsite spelling: `UCk_Utils_GymStartup_UE::Get_StartupMode()`.
//
// --------------------------------------------------------------------------------------------------------------------

UCLASS()
class CKTESTS_API UCk_Utils_GymStartup_UE : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()

public:
    UFUNCTION(BlueprintPure, Category = "Ck|Utils|GymStartup",
              DisplayName = "[Ck][GymStartup] Get StartupMode")
    static ECkGym_StartupMode
    Get_StartupMode();

    UFUNCTION(BlueprintCallable, Category = "Ck|Utils|GymStartup",
              DisplayName = "[Ck][GymStartup] Set StartupMode")
    static void
    Request_Set_StartupMode(
        ECkGym_StartupMode InMode);

    UFUNCTION(BlueprintPure, Category = "Ck|Utils|GymStartup",
              DisplayName = "[Ck][GymStartup] Get DefaultGymName")
    static FString
    Get_DefaultGymName();

    UFUNCTION(BlueprintCallable, Category = "Ck|Utils|GymStartup",
              DisplayName = "[Ck][GymStartup] Set DefaultGymName")
    static void
    Request_Set_DefaultGymName(
        const FString& InName);

    UFUNCTION(BlueprintPure, Category = "Ck|Utils|GymStartup",
              DisplayName = "[Ck][GymStartup] Get LastGymName")
    static FString
    Get_LastGymName();

    UFUNCTION(BlueprintCallable, Category = "Ck|Utils|GymStartup",
              DisplayName = "[Ck][GymStartup] Set LastGymName")
    static void
    Request_Set_LastGymName(
        const FString& InName);

    UFUNCTION(BlueprintPure, Category = "Ck|Utils|GymStartup",
              DisplayName = "[Ck][GymStartup] Get RecentGymNames")
    static TArray<FString>
    Get_RecentGymNames();

    // Records a visit: InName moves to (or enters at) the front, deduped, capped at RecentGymsCap.
    UFUNCTION(BlueprintCallable, Category = "Ck|Utils|GymStartup",
              DisplayName = "[Ck][GymStartup] Push RecentGym")
    static void
    Request_PushRecentGym(
        const FString& InName);
};
