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
    // DEFAULT. This editor NEVER claims the test bridge. Test runs go to a headless warm server (which the driver
    // launches on demand) or to a fresh boot — neither of which touches this session.
    Off,

    // Opt in to donating THIS editor to test runs. Still gated by the non-PIE / non-dirty / AS-clean preconditions,
    // but understand what it costs: automation LOADS the map each test needs, so your open level is replaced (and
    // NOT restored), and PIE runs in your window while the suite executes.
    //
    // Only advantage over the warm server is that it costs no extra multi-GB editor process. If you are not
    // RAM-constrained, leave this Off.
    Allow
};

// NOTE on upgrading: the previous enum had `AutoTestsMapOnly` (the old default) and `CleanEditorBorrow`. Config
// enums persist BY NAME, so an ini carrying either of those names no longer resolves and falls back to the CDO
// default — which is now `Off`. That is the intended, conservative outcome: nobody keeps serving by accident.
//
// Why the map-scoped mode was removed: it promised the "provably free" case (already on the AutoTests map ⇒ no map
// operation at all), but a project can have SEVERAL maps whose names contain "AutoTests" (here: CkTests' and
// BusterBlock's). Sitting on one of them says nothing about which map an incoming run needs — measured 2026-07-25,
// a single `--test-pattern Timer` spanned both — so the guarantee silently did not hold, and the mode's real
// behaviour was indistinguishable from an unrestricted borrow.

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
    // NOTE: a UHT metadata value must be ONE string literal — adjacent-literal concatenation is a parse error here.
    UPROPERTY(Config, EditAnywhere, Category = "Test Bridge",
              meta = (AllowPrivateAccess = true,
                      ToolTip = "Whether THIS editor may be borrowed for test runs triggered by an external driver (the UnrealToolbox). Off (default): never serve - runs go to a headless warm server or a fresh boot and leave this session alone. Allow: donate this editor - automation loads a map per test and nothing restores yours, so when the run ends you are LEFT SITTING ON THE LAST TEST MAP and must reopen your own level yourself; PIE also runs in your window while the suite executes. Your unsaved work is never at risk (a dirty world makes the run refuse outright) - what you lose is your place. Only worth it if you cannot spare the RAM for a second editor process."))
    ECk_TestBridge_ServeMode _ServeMode = ECk_TestBridge_ServeMode::Off;

public:
    CK_PROPERTY_GET(_ServeMode);
};

// --------------------------------------------------------------------------------------------------------------------
