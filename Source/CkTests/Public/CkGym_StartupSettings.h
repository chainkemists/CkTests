#pragma once

#include "CoreMinimal.h"

#include <Engine/DeveloperSettings.h>

#include "CkGym_StartupSettings.generated.h"

// --------------------------------------------------------------------------------------------------------------------
//
// Per-user startup preferences for the gym cycler. Surfaces in:
//   Editor Preferences -> Ck Tests -> Gym Cycler
//
// Mirrors Unreal's "Editor Preferences -> Loading & Saving -> Startup -> Load
// Level at Startup" UX: a dev can pick a fixed default gym, opt to resume the
// last gym they were in, or keep the cycler menu (Tab) as the entry point.
//
// Persisted to EditorPerProjectUserSettings.ini (per-user, not source-controlled).
// LastGymName is written by the cycler on every successful travel.
//
// --------------------------------------------------------------------------------------------------------------------

UENUM(BlueprintType)
enum class ECkGym_StartupMode : uint8
{
    Cycler,   // Default: show the Tab cycler menu, no auto-travel.
    Default,  // Auto-travel to DefaultGymName on gym GameMode BeginPlay.
    Last      // Auto-travel to LastGymName (resume last visited gym).
};

UCLASS(Config = EditorPerProjectUserSettings, meta = (DisplayName = "Gym Cycler"))
class CKTESTS_API UCkGym_StartupSettings : public UDeveloperSettings
{
    GENERATED_BODY()

public:
    UCkGym_StartupSettings();

    // UDeveloperSettings ----------------------------------------------------------------------------------------------

    auto GetContainerName() const -> FName override;
    auto GetCategoryName()  const -> FName override;
    auto GetSectionName()   const -> FName override;
#if WITH_EDITOR
    auto GetSectionText()   const -> FText override;
    auto GetSectionDescription() const -> FText override;
#endif

    // Settings --------------------------------------------------------------------------------------------------------

    UPROPERTY(Config, EditAnywhere, Category = "Startup",
              meta = (DisplayName = "Startup Mode"))
    ECkGym_StartupMode StartupMode = ECkGym_StartupMode::Cycler;

    UPROPERTY(Config, EditAnywhere, Category = "Startup",
              meta = (DisplayName = "Default Gym Name",
                      EditCondition = "StartupMode == ECkGym_StartupMode::Default",
                      Tooltip = "DisplayName as registered with CkGym_Cycler::RegisterProjectGym (e.g. \"BB Economy\")."))
    FString DefaultGymName;

    UPROPERTY(Config, VisibleAnywhere, Category = "Startup",
              meta = (DisplayName = "Last Gym Name",
                      Tooltip = "Auto-updated by the cycler on every successful travel. Used when StartupMode = Last."))
    FString LastGymName;
};
