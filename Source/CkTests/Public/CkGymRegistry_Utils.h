#pragma once

#include "CoreMinimal.h"

#include "CkGym_Registry.h"

#include <Kismet/BlueprintFunctionLibrary.h>

#include "CkGymRegistry_Utils.generated.h"

// --------------------------------------------------------------------------------------------------------------------
//
// AngelScript / Blueprint bridge to UCkGym_Registry_Subsystem (see CkGymStartup_Utils.h for the
// naming rationale). Every function resolves the per-GameInstance subsystem through the world
// context, which AngelScript supplies implicitly (WorldContext params are stripped AS-side).
//
// AS callsite spelling: `UCk_Utils_GymRegistry_UE::Get_GymRegistry()`.
//
// --------------------------------------------------------------------------------------------------------------------

UCLASS()
class CKTESTS_API UCk_Utils_GymRegistry_UE : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()

public:
    UFUNCTION(BlueprintCallable, Category = "Ck|Utils|GymRegistry",
              DisplayName = "[Ck][GymRegistry] Register Gym",
              meta = (WorldContext = "InWorldContextObject"))
    static void
    Request_RegisterGym(
        const UObject* InWorldContextObject,
        const FString& InDisplayName,
        TSubclassOf<AGameModeBase> InGameModeClass,
        const FString& InLevelName,
        const FString& InCategory);

    UFUNCTION(BlueprintPure, Category = "Ck|Utils|GymRegistry",
              DisplayName = "[Ck][GymRegistry] Get GymRegistry",
              meta = (WorldContext = "InWorldContextObject"))
    static TArray<FCkGym_Entry>
    Get_GymRegistry(
        const UObject* InWorldContextObject);

    UFUNCTION(BlueprintPure, Category = "Ck|Utils|GymRegistry",
              DisplayName = "[Ck][GymRegistry] Get CurrentGymIndex",
              meta = (WorldContext = "InWorldContextObject"))
    static int32
    Get_CurrentGymIndex(
        const UObject* InWorldContextObject);

    UFUNCTION(BlueprintPure, Category = "Ck|Utils|GymRegistry",
              DisplayName = "[Ck][GymRegistry] Get SuppressHUDDuringStartup",
              meta = (WorldContext = "InWorldContextObject"))
    static bool
    Get_SuppressHUDDuringStartup(
        const UObject* InWorldContextObject);

    UFUNCTION(BlueprintCallable, Category = "Ck|Utils|GymRegistry",
              DisplayName = "[Ck][GymRegistry] Set SuppressHUDDuringStartup",
              meta = (WorldContext = "InWorldContextObject"))
    static void
    Request_Set_SuppressHUDDuringStartup(
        const UObject* InWorldContextObject,
        bool InSuppress);

    UFUNCTION(BlueprintPure, Category = "Ck|Utils|GymRegistry",
              DisplayName = "[Ck][GymRegistry] Find GymIndexByName",
              meta = (WorldContext = "InWorldContextObject"))
    static int32
    Find_GymIndexByName(
        const UObject* InWorldContextObject,
        const FString& InName);

    // Returns the registry index the gym GameMode should auto-travel to on BeginPlay, based on the
    // user's startup preference. -1 when the cycler menu should handle entry (mode = Cycler, or the
    // saved name no longer resolves to a registered gym).
    UFUNCTION(BlueprintPure, Category = "Ck|Utils|GymRegistry",
              DisplayName = "[Ck][GymRegistry] Resolve StartupGymIndex",
              meta = (WorldContext = "InWorldContextObject"))
    static int32
    Resolve_StartupGymIndex(
        const UObject* InWorldContextObject);

    UFUNCTION(BlueprintCallable, Category = "Ck|Utils|GymRegistry",
              DisplayName = "[Ck][GymRegistry] Travel To Gym",
              meta = (WorldContext = "InWorldContextObject"))
    static void
    Request_TravelToGym(
        const UObject* InWorldContextObject,
        int32 InIndex);

    UFUNCTION(BlueprintCallable, Category = "Ck|Utils|GymRegistry",
              DisplayName = "[Ck][GymRegistry] Travel To Gym By Name",
              meta = (WorldContext = "InWorldContextObject"))
    static void
    Request_TravelToGymByName(
        const UObject* InWorldContextObject,
        const FString& InName);

    UFUNCTION(BlueprintCallable, Category = "Ck|Utils|GymRegistry",
              DisplayName = "[Ck][GymRegistry] Travel To Next Gym",
              meta = (WorldContext = "InWorldContextObject"))
    static void
    Request_NextGym(
        const UObject* InWorldContextObject);

    UFUNCTION(BlueprintCallable, Category = "Ck|Utils|GymRegistry",
              DisplayName = "[Ck][GymRegistry] Travel To Previous Gym",
              meta = (WorldContext = "InWorldContextObject"))
    static void
    Request_PrevGym(
        const UObject* InWorldContextObject);

private:
    static auto
    DoGet_Subsystem(
        const UObject* InWorldContextObject) -> UCkGym_Registry_Subsystem*;
};
