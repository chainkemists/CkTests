#pragma once

#include <CoreMinimal.h>
#include <Engine/DataAsset.h>
#include <Engine/World.h>

#include "CkAutoTestMapConfig.generated.h"

// --------------------------------------------------------------------------------------------------------------------

// Per-project configuration for the AutoTest map populator.
//
// One config per AutoTests map. CkTests authors a config pointing at the framework's
// AutoTests level; downstream projects (e.g. BusterBlock) author their own pointing
// at their AutoTests level. The populator iterates all configs found in the asset
// registry and syncs each independently.
UCLASS(BlueprintType, Category = "Ck|AutoTest")
class CKTESTSEDITOR_API UCkAutoTestMapConfig : public UDataAsset
{
    GENERATED_BODY()

public:
    // The level the populator will keep in sync with discovered ACk_AutoTestRunner
    // subclasses. Each test wrapper class becomes one placed actor in this level.
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "AutoTest Map",
              meta = (DisplayThumbnail = "false",
                      Tooltip = "Target AutoTests level. The populator places one wrapper actor per discovered test class into this map."))
    TSoftObjectPtr<UWorld> TargetMap;

    // Optional source-path filter for which test classes apply to this config.
    // Only ACk_AutoTestRunner subclasses whose authoring source file (the .as file
    // for AS-defined classes) contains this path will be synced into TargetMap.
    //
    // **Leave empty for the common case** — the populator auto-derives the scope from
    // where this config asset lives:
    //   - For an AS-defined `asset` declaration in `Plugins/Foo/Script/...`, the scope
    //     becomes `/Foo/` automatically.
    //   - For a .uasset config under `/Foo/Content/...`, the scope is also `/Foo/`.
    // So a config authored inside the CkTests plugin scopes to /CkTests/ with no
    // fields set. Override here only when you need a non-standard scope (e.g., `/Game/`
    // for project-level tests, or empty `+` an explicit override means "scan everything").
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "AutoTest Map",
              meta = (Tooltip = "Override the auto-derived owner-scope filter. Leave empty to use the plugin/project this config lives in."))
    FString ClassScanRoot;

    // When true, the populator saves the target map automatically after spawning or
    // removing wrappers — the user does not need to Ctrl+S. The save is gated by a
    // dirty-state check: if the map has unrelated dirty edits, the populator leaves
    // it dirty for the human to resolve and only logs a warning.
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "AutoTest Map",
              meta = (Tooltip = "Auto-save the map after a non-empty sync. Skips save if the map has unrelated dirty edits."))
    bool bAutoSaveOnSync = true;

public:
    auto
    Get_DisplayName() const -> FString;
};

// --------------------------------------------------------------------------------------------------------------------
