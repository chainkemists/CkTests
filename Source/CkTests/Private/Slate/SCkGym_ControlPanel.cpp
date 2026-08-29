#include "SCkGym_ControlPanel.h"

#include "CkEditorTools/Style/CkStyle.h"

#include <Widgets/Layout/SBorder.h>
#include <Widgets/Layout/SBox.h>
#include <Widgets/SBoxPanel.h>
#include <Widgets/Text/STextBlock.h>

// --------------------------------------------------------------------------------------------------------------------

namespace ck_gym_control_panel_widget
{
    // Rows keep their declared order and stable indices, so a disabled row dims rather than
    // disappears — matching the Canvas panel's contract.
    constexpr float DisabledAlpha = 0.45f;

    auto Get_Dimmed(const FLinearColor& InColor, bool InEnabled) -> FLinearColor
    {
        if (InEnabled)
        { return InColor; }

        auto Dimmed = InColor;
        Dimmed.A *= DisabledAlpha;
        return Dimmed;
    }
}

// --------------------------------------------------------------------------------------------------------------------

auto
    SCkGym_ControlPanel::
    Construct(
        const FArguments& InArgs)
    -> void
{
    SetVisibility(EVisibility::HitTestInvisible);
}

auto
    SCkGym_ControlPanel::
    Refresh(
        const FString& InTitle,
        const TArray<FCkGym_ControlRow>& InRows,
        FVector2D InOffset,
        bool InPanelCollapsed)
    -> void
{
    if (InPanelCollapsed || InRows.Num() == 0)
    {
        // Just the reminder chips — either the user hid the panel (rows still fire) or the gym
        // declared no rows (only Tab matters).
        ChildSlot
        [
            SNew(SBox)
            .HAlign(HAlign_Left)
            .VAlign(VAlign_Top)
            .Padding(FMargin{InOffset.X, InOffset.Y, 0.0f, 0.0f})
            [
                SNew(SBorder)
                .BorderImage(CkStyle::GetRoundedBrush())
                .BorderBackgroundColor(CkStyle::OverlayOf(CkStyle::BgRoot(), 0.78f))
                .Padding(FMargin{CkStyle::SpaceS, 2.0f})
                [
                    DoBuild_HintLine(InPanelCollapsed)
                ]
            ]
        ];
        return;
    }

    auto Rows = SNew(SVerticalBox);

    Rows->AddSlot()
        .AutoHeight()
        .Padding(FMargin{0.0f, 0.0f, 0.0f, CkStyle::SpaceS})
        [
            SNew(SHorizontalBox)
            + SHorizontalBox::Slot()
            .FillWidth(1.0f)
            .VAlign(VAlign_Center)
            [
                SNew(STextBlock)
                .Text(FText::FromString(InTitle))
                .Font(CkStyle::BoldFont(CkStyle::FontSizeSmall()))
                .ColorAndOpacity(CkStyle::Text())
            ]
            + SHorizontalBox::Slot()
            .AutoWidth()
            .VAlign(VAlign_Center)
            .Padding(FMargin{CkStyle::SpaceM, 0.0f, 0.0f, 0.0f})
            [
                SNew(STextBlock)
                .Text(FText::FromString(TEXT("[H] hide")))
                .Font(CkStyle::MonoFont(CkStyle::FontSizeMicro()))
                .ColorAndOpacity(CkStyle::TextMute())
            ]
        ];

    for (const auto& Row : InRows)
    {
        Rows->AddSlot()
            .AutoHeight()
            .Padding(FMargin{0.0f, Row.Kind == ECkGym_ControlKind::Header ? CkStyle::SpaceS : 1.0f, 0.0f, 1.0f})
            [
                DoBuild_Row(Row)
            ];
    }

    Rows->AddSlot()
        .AutoHeight()
        .Padding(FMargin{0.0f, CkStyle::SpaceS, 0.0f, 0.0f})
        [
            DoBuild_HintLine(false)
        ];

    ChildSlot
    [
        SNew(SBox)
        .HAlign(HAlign_Left)
        .VAlign(VAlign_Top)
        .Padding(FMargin{InOffset.X, InOffset.Y, 0.0f, 0.0f})
        [
            SNew(SBorder)
            .BorderImage(CkStyle::GetRoundedBrush_Large())
            .BorderBackgroundColor(CkStyle::Border())
            .Padding(FMargin{1.0f})
            [
                SNew(SBorder)
                .BorderImage(CkStyle::GetRoundedBrush_Large())
                .BorderBackgroundColor(CkStyle::OverlayOf(CkStyle::BgRoot(), 0.82f))
                .Padding(FMargin{CkStyle::SpaceM, CkStyle::SpaceS})
                [
                    SNew(SBox)
                    .MinDesiredWidth(280.0f)
                    [
                        Rows
                    ]
                ]
            ]
        ]
    ];
}

// --------------------------------------------------------------------------------------------------------------------

auto
    SCkGym_ControlPanel::
    DoBuild_Row(
        const FCkGym_ControlRow& InRow)
    -> TSharedRef<SWidget>
{
    using namespace ck_gym_control_panel_widget;

    if (InRow.Kind == ECkGym_ControlKind::Header)
    {
        return SNew(STextBlock)
            .Text(FText::FromString(InRow.Label))
            .Font(CkStyle::BoldFont(CkStyle::FontSizeMicro()))
            .ColorAndOpacity(CkStyle::AccentDim());
    }

    auto Content = SNew(SHorizontalBox);

    // Key chip column — Status rows keep the column width so labels align.
    Content->AddSlot()
        .AutoWidth()
        .VAlign(VAlign_Center)
        .Padding(FMargin{0.0f, 0.0f, CkStyle::SpaceS, 0.0f})
        [
            SNew(SBox)
            .MinDesiredWidth(34.0f)
            .HAlign(HAlign_Left)
            [
                DoBuild_KeyChip(InRow)
            ]
        ];

    const auto IsActiveChoice = InRow.Kind == ECkGym_ControlKind::Choice && InRow.Active;

    Content->AddSlot()
        .FillWidth(1.0f)
        .VAlign(VAlign_Center)
        [
            SNew(STextBlock)
            .Text(FText::FromString(InRow.Label))
            .Font(IsActiveChoice ? CkStyle::BoldFont(CkStyle::FontSizeSmall()) : CkStyle::RegularFont(CkStyle::FontSizeSmall()))
            .ColorAndOpacity(Get_Dimmed(
                InRow.Kind == ECkGym_ControlKind::Status ? CkStyle::TextDim()
                    : IsActiveChoice ? CkStyle::TextStrong() : CkStyle::Text(),
                InRow.Enabled))
        ];

    if (NOT InRow.Value.IsEmpty())
    {
        const auto ValueColor =
            InRow.Warn ? CkStyle::Warn()
            : InRow.Kind == ECkGym_ControlKind::Toggle ? (InRow.Active ? CkStyle::Ok() : CkStyle::TextMute())
            : CkStyle::Accent();

        Content->AddSlot()
            .AutoWidth()
            .VAlign(VAlign_Center)
            .Padding(FMargin{CkStyle::SpaceM, 0.0f, 0.0f, 0.0f})
            [
                SNew(STextBlock)
                .Text(FText::FromString(InRow.Value))
                .Font(CkStyle::BoldFont(CkStyle::FontSizeMicro()))
                .ColorAndOpacity(Get_Dimmed(ValueColor, InRow.Enabled))
            ];
    }

    if (IsActiveChoice)
    {
        return SNew(SBorder)
            .BorderImage(CkStyle::GetRoundedBrush())
            .BorderBackgroundColor(CkStyle::OverlayOf(CkStyle::Selection(), 0.3f))
            .Padding(FMargin{2.0f, 1.0f})
            [
                Content
            ];
    }

    return SNew(SBox)
        .Padding(FMargin{2.0f, 1.0f})
        [
            Content
        ];
}

auto
    SCkGym_ControlPanel::
    DoBuild_KeyChip(
        const FCkGym_ControlRow& InRow)
    -> TSharedRef<SWidget>
{
    using namespace ck_gym_control_panel_widget;

    if (InRow.KeyLabel.IsEmpty())
    { return SNew(SBox); }

    return SNew(SBorder)
        .BorderImage(CkStyle::GetRoundedBrush_Small())
        .BorderBackgroundColor(Get_Dimmed(CkStyle::Bg3(), InRow.Enabled))
        .Padding(FMargin{CkStyle::SpaceS, 0.0f})
        [
            SNew(STextBlock)
            .Text(FText::FromString(InRow.KeyLabel))
            .Font(CkStyle::MonoFont(CkStyle::FontSizeMicro()))
            .ColorAndOpacity(Get_Dimmed(CkStyle::TextStrong(), InRow.Enabled))
        ];
}

auto
    SCkGym_ControlPanel::
    DoBuild_HintLine(
        bool InShowControlsHint)
    -> TSharedRef<SWidget>
{
    const auto Hint = InShowControlsHint
        ? FString{TEXT("[H] gym controls   ·   [Tab] gyms")}
        : FString{TEXT("[Tab] gyms")};

    return SNew(STextBlock)
        .Text(FText::FromString(Hint))
        .Font(CkStyle::MonoFont(CkStyle::FontSizeMicro()))
        .ColorAndOpacity(CkStyle::TextMute());
}
