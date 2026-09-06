#pragma once

#include "CoreMinimal.h"

#include "CkGym_ControlPanelTypes.h"

#include <Brushes/SlateRoundedBoxBrush.h>
#include <Widgets/SCompoundWidget.h>

// --------------------------------------------------------------------------------------------------------------------
//
// The gym control panel's Slate face - the CkStyle-language replacement for the old Canvas
// DrawRect/DrawText panel. Visual-only (HitTestInvisible, never focused); dispatch stays with the
// gym HUD's input layer, so this widget draws state and nothing else. The subsystem calls
// Refresh() only when the pushed state actually changed.
//
// --------------------------------------------------------------------------------------------------------------------

class SCkGym_ControlPanel : public SCompoundWidget
{
public:
    SLATE_BEGIN_ARGS(SCkGym_ControlPanel) {}
    SLATE_END_ARGS()

    void Construct(const FArguments& InArgs);

    // InMode = the user's H cycle: rows keep firing in every mode, only the drawing changes.
    // InMaxWidth bounds the card, so a long value wraps or clips instead of growing the panel
    // across the viewport. InRows arrives already filtered for the mode.
    void Refresh(
        const FString& InTitle,
        const TArray<FCkGym_ControlRow>& InRows,
        FVector2D InOffset,
        float InMaxWidth,
        ECkGym_ControlPanel_Mode InMode);

private:
    // The text widths one Refresh derives from the bounded card, handed down so every row wraps
    // against the same geometry instead of each one re-deriving it.
    struct FRowWidths
    {
        float Content = 0.0f;
        float Label = 0.0f;
        float Value = 0.0f;
    };

    // Refresh rebuilds the panel tree, so the outlined brush must outlive the SBorder that paints
    // it. It separates the translucent fill from the opaque outline without a second solid border.
    TOptional<FSlateRoundedBoxBrush> _PanelBackgroundBrush;

    auto
    DoBuild_Row(
        const FCkGym_ControlRow& InRow,
        bool InCompact,
        const FRowWidths& InWidths) -> TSharedRef<SWidget>;

    auto
    DoBuild_KeyChip(
        const FCkGym_ControlRow& InRow) -> TSharedRef<SWidget>;

    auto
    DoBuild_HintLine(
        bool InShowControlsHint) -> TSharedRef<SWidget>;
};
