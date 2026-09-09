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
    // Both public entry points above are EXPLICIT requests (a user at the console, a
    // designer's Blueprint), so they force the full load-and-sync pass. The automatic
    // triggers -- subsystem Initialize and AngelScript post-compile -- call this with
    // bInForceFullSync = false, which lets Is_AlreadyInSync_FromAssetRegistry answer
    // "nothing to do" without loading any map.
    //
    // Keeping the forcing decision at the ENTRY POINT rather than inside the sync is
    // deliberate: it means "I asked for it, so do the real thing" is always available,
    // which is the bounded escape hatch for any case the cheap check gets wrong.
    auto
    Sync_AllConfigs_Internal(
        bool bInForceFullSync) -> void;

    auto
    Discover_AllConfigs() -> TArray<UCkAutoTestMapConfig*>;

    auto
    Sync_Config_Internal(
        UCkAutoTestMapConfig* InConfig,
        bool                  bInForceFullSync) -> FCkAutoTestSyncResult;

    // Cheap pre-check: can we conclude "this config's map is already correct" WITHOUT
    // loading it?
    //
    // Why this exists: loading the target map is the entire cost of a populator pass.
    // BusterBlock's two configs pull in 1,439 external-actor packages between them and
    // take 4.89 s of blocked game-thread time in editor frame 1, on every editor boot
    // (including every automation-test boot), only to report "0 spawned, 0 removed".
    //
    // Why it is not a staleness heuristic: for an OFPA level the set of placed actors IS
    // the set of external-actor packages on disk -- the level discovers them by asset
    // registry scan of __ExternalActors__/<MapName>/, not from a manifest in the .umap
    // (which is why the OFPA save path below never writes the .umap). The asset registry
    // already carries each package's actor class (AssetClassPath), its native base
    // (ActorMetaDataClass) and its Outliner label (ActorLabel) from disk. So the same
    // question the full pass answers by loading 1,439 packages is answerable from
    // registry metadata, exactly, and the answer is not an approximation of the full
    // pass -- it is the full pass's inputs, read from the cheaper source.
    //
    // Every uncertainty resolves toward doing the work: a non-OFPA map, an
    // as-yet-unpopulated map, a package the registry has no class metadata for, a count
    // mismatch, a label mismatch, an in-memory copy of the map that might differ from
    // disk -- all return false and the full load-and-sync runs.
    auto
    Is_AlreadyInSync_FromAssetRegistry(
        UCkAutoTestMapConfig* InConfig,
        const TArray<UClass*>& InWantedClasses,
        FString&               OutReasonToLoad) -> bool;

    // Builds the set of ACk_AutoTestRunner subclasses whose source matches
    // the config's ClassScanRoot filter.
    auto
    Discover_TestClasses(
        UCkAutoTestMapConfig* InConfig) const -> TArray<UClass*>;

    static auto
    Get_AssertedSourcePathForClass(
        UClass* InClass) -> FString;

    // The Outliner label the populator assigns a wrapper: the class name with the
    // conventional "_Actor" suffix stripped. Single source of truth -- the live-actor
    // relabel pass, the on-disk stale-wrapper detection and the asset-registry
    // pre-check all derive the expected label from here. A second copy of this rule
    // would let the pre-check skip a map the full pass would have relabeled.
    static auto
    Compute_ExpectedLabelForClassName(
        const FString& InClassName) -> FString;

    static auto
    Compute_ExpectedLabelForClass(
        const UClass* InClass) -> FString;

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

    // Resolves the UWorld to sync against for the given config. Two paths:
    //   1. If the config's TargetMap IS the currently-active editor world, returns
    //      that live world (OutWasLoadedFresh = false). Edits become user-visible
    //      immediately and the existing dirty-state guard applies.
    //   2. Otherwise, loads the target package via LoadPackage, locates the world
    //      inside (OutWasLoadedFresh = true). The package was clean before our load,
    //      so post-edit auto-save is unconditionally safe.
    // Returns nullptr (and a populated SkipReason via OutSkipReason) on any failure.
    auto
    Find_OrLoad_TargetWorld(
        UCkAutoTestMapConfig* InConfig,
        bool& OutWasLoadedFresh,
        FString& OutSkipReason) const -> UWorld*;

    auto
    OnAngelscriptPostCompile() -> void;

    auto
    OnAssetRegistryFilesLoaded() -> void;

    auto
    Defer_SyncToNextTick(
        bool bInForceFullSync) -> void;

private:
    FDelegateHandle _PostAngelscriptCompileHandle;
    FDelegateHandle _AssetRegistryFilesLoadedHandle;

    // Config display names whose unloadable-stale-wrapper preview has already been
    // emitted this editor session. The pre-check can run several times per boot (asset
    // registry files-loaded, then every AngelScript post-compile), and the condition it
    // reports is a property of what is on disk, not of this pass -- so repeating it per
    // pass is noise, not information.
    TSet<FString> _StaleWrapperPreviewReported;
};

// --------------------------------------------------------------------------------------------------------------------
