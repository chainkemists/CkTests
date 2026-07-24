#pragma once

#include "CkCore/Format/CkFormat.h"
#include "CkCore/Macros/CkMacros.h"

#include <Engine/DeveloperSettings.h>

#include "CkTestBridge_UserSettings.generated.h"

// --------------------------------------------------------------------------------------------------------------------
//
// Per-user opt-in for the live test bridge. Persisted to EditorPerProjectUserSettings.ini so the choice is
// per-machine and never committed to source. Governs whether THIS editor is allowed to claim server.json and
// run tests dropped by an external driver (the UnrealToolbox).
//
// --------------------------------------------------------------------------------------------------------------------

UENUM(BlueprintType)
enum class ECk_TestBridge_ServeMode : uint8
{
    // This editor NEVER claims the test bridge — the safest default for an interactive session that is not
    // expecting to donate itself to a test run.
    Off,

    // Serve, but only when the current editor world is the AutoTests map (or nothing that would be lost). The
    // default: an editor sitting on the AutoTests level is already a safe place to run a headless suite.
    AutoTestsMapOnly,

    // Serve from any editor state, borrowing the running editor for a run (still gated by the non-PIE /
    // non-dirty / AS-clean preconditions). For power users who explicitly opt in.
    CleanEditorBorrow
};

CK_DEFINE_CUSTOM_FORMATTER_ENUM(ECk_TestBridge_ServeMode);

// --------------------------------------------------------------------------------------------------------------------

UCLASS(Config = EditorPerProjectUserSettings, meta = (DisplayName = "Ck Test Bridge"))
class CKTESTSBRIDGE_API UCk_TestBridge_UserSettings : public UDeveloperSettings
{
    GENERATED_BODY()

public:
    CK_GENERATED_BODY(UCk_TestBridge_UserSettings);

public:
    auto GetCategoryName() const -> FName override { return TEXT("Ck"); }

private:
    UPROPERTY(Config, EditAnywhere, Category = "Test Bridge",
              meta = (AllowPrivateAccess = true,
                      ToolTip = "Controls whether this editor may donate itself to a headless test run triggered by an external driver (the UnrealToolbox). Off = never serve."))
    ECk_TestBridge_ServeMode _ServeMode = ECk_TestBridge_ServeMode::AutoTestsMapOnly;

public:
    CK_PROPERTY_GET(_ServeMode);
};

// --------------------------------------------------------------------------------------------------------------------
