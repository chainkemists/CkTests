#pragma once

#include <Kismet/BlueprintFunctionLibrary.h>

#include "CkGroundNavStreamingAcceptance_EditorUtils.generated.h"

class ACk_EntitySpawner_UE;
class ACk_PathNetwork_UE;

// --------------------------------------------------------------------------------------------------------------------

/**
 * Narrow editor bridge for the Python-authored GroundNav streaming acceptance fixture.
 *
 * Unreal's stock Python surface can create maps but cannot safely create or attach an ordinary
 * streaming sublevel. Keeping that operation here prevents a Python tool from saving loose maps
 * that look like a streaming fixture but never enter the persistent world's streaming list.
 */
UCLASS()
class CKTESTSEDITOR_API UCk_GroundNavStreamingAcceptance_EditorUtils : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()

public:
    /** Places a fully configured manifest-driven GroundNav volume in the persistent fixture level. */
    UFUNCTION(BlueprintCallable, Category = "Ck|Tests|GroundNav Acceptance")
    static ACk_EntitySpawner_UE* CreateVolumeSpawner();

    /** Places a PathNetwork with labeled candidate points for flat, ramp, upper-floor, and no-surface snaps. */
    UFUNCTION(BlueprintCallable, Category = "Ck|Tests|GroundNav Acceptance")
    static ACk_PathNetwork_UE* CreatePathNetworkActor();

    /** Adds an existing level or creates it as a ULevelStreamingDynamic child of the current editor world. */
    UFUNCTION(BlueprintCallable, Category = "Ck|Tests|GroundNav Acceptance")
    static bool CreateOrAddStreamingLevel(const FString& InLevelPackageName);

    /** Makes the loaded level with this package name current, so editor scripting spawns into it. */
    UFUNCTION(BlueprintCallable, Category = "Ck|Tests|GroundNav Acceptance")
    static bool MakeNamedLevelCurrent(const FString& InLevelPackageName);

    /** Restores the current editor world to its persistent level. */
    UFUNCTION(BlueprintCallable, Category = "Ck|Tests|GroundNav Acceptance")
    static bool RestorePersistentCurrentLevel();

    /** Removes tagged generator-owned actors from only the current fixture level. */
    UFUNCTION(BlueprintCallable, Category = "Ck|Tests|GroundNav Acceptance")
    static int32 DeleteOwnedActorsInCurrentLevel(FName InOwnershipTag);

    /** Saves only dirty map packages under /CkTests/GroundNavAcceptance. */
    UFUNCTION(BlueprintCallable, Category = "Ck|Tests|GroundNav Acceptance")
    static bool SaveDirtyFixtureLevels();
};

// --------------------------------------------------------------------------------------------------------------------
