#pragma once

#include "CoreMinimal.h"

#include "CkGym_ControlPanelTypes.h"

#include <Widgets/SCompoundWidget.h>

// --------------------------------------------------------------------------------------------------------------------
//
// The gym control panel's Slate face — the CkStyle-language replacement for the old Canvas
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

    // InPanelCollapsed = the user's H toggle: rows keep firing, only the drawing collapses to the
    // reminder chip.
    void Refresh(
        const FString& InTitle,
        const TArray<FCkGym_ControlRow>& InRows,
        FVector2D InOffset,
        bool InPanelCollapsed);

private:
    auto
    DoBuild_Row(
        const FCkGym_ControlRow& InRow) -> TSharedRef<SWidget>;

    auto
    DoBuild_KeyChip(
        const FCkGym_ControlRow& InRow) -> TSharedRef<SWidget>;

    auto
    DoBuild_HintLine(
        bool InShowControlsHint) -> TSharedRef<SWidget>;
};
