#pragma once

#include "CoreMinimal.h"

#include <InputCoreTypes.h>

#include "CkGym_ControlPanelTypes.generated.h"

// --------------------------------------------------------------------------------------------------------------------
//
// The gym control panel's data shapes. Declared in C++ (fields public, BlueprintReadWrite) because
// the panel renders as a Slate widget owned by UCkGym_Switchboard_Subsystem; AngelScript keeps the
// row BUILDERS (Script/Common/CkGym_ControlPanel.as) and the dispatch, and hands the rows across
// per frame.
//
// --------------------------------------------------------------------------------------------------------------------

// What a row IS, which decides how it draws and whether it takes a key.
UENUM(BlueprintType)
enum class ECkGym_ControlKind : uint8
{
    // A section label. No key, no value - it groups the rows under it.
    Header,

    // Fires once and does something. No value column.
    Action,

    // Fires once and flips a two-state value, reported as ON / off.
    Toggle,

    // One of a mutually exclusive set. Exactly one is Active, and that one is highlighted.
    Choice,

    // No key at all - a readout the gym wants on screen beside its controls.
    Status
};

// --------------------------------------------------------------------------------------------------------------------

UENUM(BlueprintType)
enum class ECkGym_ControlShift : uint8
{
    Any,
    Released,
    Pressed
};

// --------------------------------------------------------------------------------------------------------------------

// How much of the panel draws. H cycles it; UCkGym_StartupSettings persists the choice per user.
// Rows keep firing in every mode - this is a drawing concern only.
UENUM(BlueprintType)
enum class ECkGym_ControlPanel_Mode : uint8
{
    // Nothing but the reminder chip.
    Hidden,

    // Headers, keyed rows, and the Status rows that carry a verdict or a warning. Values are
    // clipped to one line, so the panel stays a strip beside the image it annotates.
    Compact,

    // Every row, values wrapped inside the bounded width.
    Full
};

// One row of the panel. Build these through the AS CkGym_Control builders rather than by hand: the
// builders are what keep Kind, HasAltKey and the value column consistent with how the panel draws.
USTRUCT(BlueprintType)
struct CKTESTS_API FCkGym_ControlRow
{
    GENERATED_BODY()

    UPROPERTY(EditAnywhere, BlueprintReadWrite)
    FString Label;

    // The right-hand column. Empty draws nothing, which is what an Action wants.
    UPROPERTY(EditAnywhere, BlueprintReadWrite)
    FString Value;

    UPROPERTY(EditAnywhere, BlueprintReadWrite)
    FKey Key;

    // A second key that fires the same row - the numpad twin of a number key.
    UPROPERTY(EditAnywhere, BlueprintReadWrite)
    FKey AltKey;

    // Whether AltKey is set. Checked instead of asking the FKey, so a default-constructed key is
    // never dispatched against.
    UPROPERTY(EditAnywhere, BlueprintReadWrite)
    bool HasAltKey = false;

    // Spelled out rather than derived from the FKey: the panel wants "PgDn", not "PageDown".
    UPROPERTY(EditAnywhere, BlueprintReadWrite)
    FString KeyLabel;

    UPROPERTY(EditAnywhere, BlueprintReadWrite)
    ECkGym_ControlKind Kind = ECkGym_ControlKind::Action;

    // Choice: this is the live one. Toggle: it is on.
    UPROPERTY(EditAnywhere, BlueprintReadWrite)
    bool Active = false;

    // Draw hot. For the state that INVALIDATES what the viewer is looking at, not mere emphasis.
    UPROPERTY(EditAnywhere, BlueprintReadWrite)
    bool Warn = false;

    // Disabled rows remain visible as an explanation of the unavailable action, but never dispatch.
    UPROPERTY(EditAnywhere, BlueprintReadWrite)
    bool Enabled = true;

    // Existing action rows accept either Shift state; numbered shortcuts opt into exact matching.
    UPROPERTY(EditAnywhere, BlueprintReadWrite)
    ECkGym_ControlShift ShiftRequirement = ECkGym_ControlShift::Any;

    auto operator==(
        const FCkGym_ControlRow& InOther) const -> bool
    {
        return Label == InOther.Label && Value == InOther.Value && Key == InOther.Key &&
               AltKey == InOther.AltKey && HasAltKey == InOther.HasAltKey &&
               KeyLabel == InOther.KeyLabel && Kind == InOther.Kind &&
               Active == InOther.Active && Warn == InOther.Warn && Enabled == InOther.Enabled &&
               ShiftRequirement == InOther.ShiftRequirement;
    }
};

// --------------------------------------------------------------------------------------------------------------------

// Where the panel anchors, in Slate units from the viewport's top-left, and how wide it may get.
// The Slate card sizes itself inside MaxWidth; the old Canvas geometry fields (row height,
// columns) are gone with the Canvas.
USTRUCT(BlueprintType)
struct CKTESTS_API FCkGym_ControlPanel_Style
{
    GENERATED_BODY()

    UPROPERTY(EditAnywhere, BlueprintReadWrite)
    float X = 24.0f;

    // Below any gym readout drawn along the top edge.
    UPROPERTY(EditAnywhere, BlueprintReadWrite)
    float Y = 90.0f;

    // The card's ceiling: the value column wraps (Full) or clips (Compact) rather than pushing the
    // panel across the viewport. The HUD clamps this against the live viewport before pushing it.
    UPROPERTY(EditAnywhere, BlueprintReadWrite)
    float MaxWidth = 720.0f;
};
