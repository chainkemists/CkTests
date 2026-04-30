#pragma once

#include <CoreMinimal.h>
#include <EditorSubsystem.h>

#include "CkAutoTestMapPopulator.generated.h"

// --------------------------------------------------------------------------------------------------------------------

class UCkAutoTestMapConfig;
class UWorld;
class UPackage;
class AActor;

// --------------------------------------------------------------------------------------------------------------------

USTRUCT(BlueprintType)
struct CKTESTSEDITOR_API FCkAutoTestSyncResult
{
    GENERATED_BODY()

    UPROPERTY(BlueprintReadOnly, Category = "Ck|AutoTest")
    int32 Spawned = 0;

    UPROPERTY(BlueprintReadOnly, Category = "Ck|AutoTest")
    int32 Removed = 0;

    UPROPERTY(BlueprintReadOnly, Category = "Ck|AutoTest")
    int32 AlreadyPresent = 0;

    // Wrapper actors whose Outliner label was stale (e.g. placed manually
    // before the populator existed and still carrying the unstripped class
    // name) and got rewritten this pass. Counts toward Has_Delta() so the
    // auto-save path persists the fix.
    UPROPERTY(BlueprintReadOnly, Category = "Ck|AutoTest")
    int32 Relabeled = 0;

    UPROPERTY(BlueprintReadOnly, Category = "Ck|AutoTest")
    bool bSkipped = false;

    UPROPERTY(BlueprintReadOnly, Category = "Ck|AutoTest")
    bool bSaved = false;

    UPROPERTY(BlueprintReadOnly, Category = "Ck|AutoTest")
    FString SkipReason;

    auto
    Has_Delta() const -> bool { return Spawned > 0 || Removed > 0 || Relabeled > 0; }
};

// --------------------------------------------------------------------------------------------------------------------

// Editor subsystem that keeps each registered AutoTests map in sync with the set of
// discoverable ACk_AutoTestRunner subclasses. Triggered automatically on AngelScript
// post-compile and on subsystem Initialize. Can also be triggered manually via the
// BlueprintCallable functions or the Ck.SyncAutoTestMaps console command.
//
// Layer 2A scope: the populator only operates on a config whose TargetMap is the
// currently-loaded editor world. Configs whose map is not currently open are
// reported as skipped (with a clear reason). The "edit the map even when unloaded"
// path is Layer 2B.
UCLASS(BlueprintType)
class CKTESTSEDITOR_API UCkAutoTestMapPopulator : public UEditorSubsystem
{
    GENERATED_BODY()

public:
    virtual auto
    Initialize(
        FSubsystemCollectionBase& Collection) -> void override;

    virtual auto
    Deinitialize() -> void override;

public:
    // Discovers every UCkAutoTestMapConfig in the asset registry and runs SyncConfig
    // against each. Fires automatically after every AS recompile; can also be invoked
    // manually from BP/console.
    UFUNCTION(BlueprintCallable, Category = "Ck|AutoTest")
    void
    Sync_AllConfigs();

    UFUNCTION(BlueprintCallable, Category = "Ck|AutoTest")
    FCkAutoTestSyncResult
    Sync_Config(
        UCkAutoTestMapConfig* InConfig);

private:
    auto
    Discover_AllConfigs() -> TArray<UCkAutoTestMapConfig*>;

    auto
    Sync_Config_Internal(
        UCkAutoTestMapConfig* InConfig) -> FCkAutoTestSyncResult;

    // Builds the set of ACk_AutoTestRunner subclasses whose source matches
    // the config's ClassScanRoot filter.
    auto
    Discover_TestClasses(
        UCkAutoTestMapConfig* InConfig) const -> TArray<UClass*>;

    static auto
    Get_AssertedSourcePathForClass(
        UClass* InClass) -> FString;

    static auto
    Is_LiveTestRunnerSubclass(
        UClass* InClass,
        UClass* InAutoTestRunnerBase) -> bool;

    // Returns the implicit "owner scope" of a config: a path fragment used to filter
    // test classes when the config's ClassScanRoot field is left empty. Resolves
    // automatically from where the config was authored:
    //   - AS-defined assets — uses the ScriptAssetFilename metadata (set by AS-UE)
    //     to find the plugin whose Source dir contains the .as file.
    //   - On-disk .uasset configs — uses the package mount point (e.g., /CkTests/).
    // Returns an empty string if no owner can be determined; the caller treats that
    // as "scan everything".
    static auto
    Get_OwnerScopeForConfig(
        UCkAutoTestMapConfig* InConfig) -> FString;

    auto
    OnAngelscriptPostCompile() -> void;

    auto
    OnAssetRegistryFilesLoaded() -> void;

    auto
    Defer_SyncToNextTick() -> void;

private:
    FDelegateHandle _PostAngelscriptCompileHandle;
    FDelegateHandle _AssetRegistryFilesLoadedHandle;
};

// --------------------------------------------------------------------------------------------------------------------
