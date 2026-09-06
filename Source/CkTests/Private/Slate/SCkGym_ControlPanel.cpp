#include "SCkGym_ControlPanel.h"

#include "CkEditorTools/Style/CkStyle.h"

#include <Framework/Text/TextLayout.h>
#include <Widgets/Layout/SBorder.h>
#include <Widgets/Layout/SBox.h>
#include <Widgets/SBoxPanel.h>
#include <Widgets/Text/STextBlock.h>

// --------------------------------------------------------------------------------------------------------------------

namespace ck_gym_control_panel_widget
{
    // Rows keep their declared order and stable indices, so a disabled row dims rather than
    // disappears - matching the Canvas panel's contract.
    constexpr float DisabledAlpha = 0.45f;

    // The card's own padding, named once so the wrap widths and the SBorder that produces them
    // cannot drift apart.
    constexpr float OuterPaddingH = CkStyle::SpaceM + 1.0f;
    constexpr float OuterPaddingV = CkStyle::SpaceS + 1.0f;

    // A row's fixed furniture, subtracted from the content width to leave the two text columns
    // their share: the key-chip column, its gutter, the value gutter, and the row's own padding.
    constexpr float KeyChipWidth = 34.0f;
    constexpr float RowPaddingH = 2.0f;

    // Compact clips rather than wraps, so its value column needs a ceiling of its own - a wrap
    // width would let the row grow tall again, which is the thing the mode exists to avoid.
    constexpr float CompactValueWidth = 420.0f;

    // Floors, so a narrow viewport degrades to a cramped panel instead of a zero-width column.
    constexpr float MinValueWrapWidth = 140.0f;
    constexpr float MinLabelWrapWidth = 80.0f;

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
        float InMaxWidth,
        ECkGym_ControlPanel_Mode InMode)
    -> void
{
    using namespace ck_gym_control_panel_widget;

    const auto IsHidden = InMode == ECkGym_ControlPanel_Mode::Hidden;

    if (IsHidden || InRows.Num() == 0)
    {
        // Just the reminder chips - either the user hid the panel (rows still fire) or the gym
        // declared no rows (only Tab matters).
        //
        // [H] is offered whenever the mode is not Full, which covers the third way to land here:
        // Compact filtering every row out. Without it the chip would say only [Tab] gyms, and the
        // way back to a panel the gym does have rows for would be unreachable from the screen.
        const auto ShowControlsHint = InMode != ECkGym_ControlPanel_Mode::Full;

        ChildSlot
        [
            SNew(SBox)
            .HAlign(HAlign_Left)
            .VAlign(VAlign_Top)
            .Padding(FMargin{InOffset.X, InOffset.Y, 0.0f, 0.0f})
            [
                SNew(SBorder)
                .BorderImage(CkStyle::GetRoundedBrush())
                .BorderBackgroundColor(CkStyle::OverlayOf(CkStyle::BgRoot(), 0.85f))
                .Padding(FMargin{CkStyle::SpaceS, 2.0f})
                [
                    DoBuild_HintLine(ShowControlsHint)
                ]
            ]
        ];
        return;
    }

    const auto IsCompact = InMode == ECkGym_ControlPanel_Mode::Compact;

    // Every text column wraps at an EXPLICIT width. AutoWrapText is wrong here: the value sits in
    // an AutoWidth slot under a MaxDesiredWidth box, which has no bounded geometry on the first
    // layout pass, and auto-wrap oscillates between passes as a result.
    auto Widths = FRowWidths{};
    Widths.Content = InMaxWidth - 2.0f * OuterPaddingH;
    Widths.Value = FMath::Max(MinValueWrapWidth, Widths.Content * 0.45f);
    Widths.Label = FMath::Max(MinLabelWrapWidth,
        Widths.Content - KeyChipWidth - CkStyle::SpaceS - CkStyle::SpaceM - Widths.Value - 2.0f * RowPaddingH);

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
                .WrapTextAt(Widths.Content)
                .Font(CkStyle::BoldFont(CkStyle::FontSizeSmall()))
                .ColorAndOpacity(CkStyle::Text())
            ]
            + SHorizontalBox::Slot()
            .AutoWidth()
            .VAlign(VAlign_Center)
            .Padding(FMargin{CkStyle::SpaceM, 0.0f, 0.0f, 0.0f})
            [
                SNew(STextBlock)
                .Text(FText::FromString(IsCompact ? TEXT("[H] hide") : TEXT("[H] compact")))
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
                DoBuild_Row(Row, IsCompact, Widths)
            ];
    }

    Rows->AddSlot()
        .AutoHeight()
        .Padding(FMargin{0.0f, CkStyle::SpaceS, 0.0f, 0.0f})
        [
            DoBuild_HintLine(false)
        ];

    _PanelBackgroundBrush.Emplace(
        CkStyle::OverlayOf(CkStyle::BgRoot(), 0.85f),
        8.0f,
        CkStyle::Border(),
        1.0f);

    ChildSlot
    [
        SNew(SBox)
        .HAlign(HAlign_Left)
        .VAlign(VAlign_Top)
        .Padding(FMargin{InOffset.X, InOffset.Y, 0.0f, 0.0f})
        [
            SNew(SBorder)
            .BorderImage(&(_PanelBackgroundBrush.GetValue()))
            .Padding(FMargin{OuterPaddingH, OuterPaddingV})
            [
                // The content width, not InMaxWidth: this box sits INSIDE the border's padding, so
                // ceiling it at InMaxWidth would let the card reach InMaxWidth + 2 * OuterPaddingH -
                // and it is the same number the text columns wrap at, which is why they agree.
                SNew(SBox)
                .MinDesiredWidth(280.0f)
                .MaxDesiredWidth(Widths.Content)
                [
                    Rows
                ]
            ]
        ]
    ];
}

// --------------------------------------------------------------------------------------------------------------------

auto
    SCkGym_ControlPanel::
    DoBuild_Row(
        const FCkGym_ControlRow& InRow,
        bool InCompact,
        const FRowWidths& InWidths)
    -> TSharedRef<SWidget>
{
    using namespace ck_gym_control_panel_widget;

    if (InRow.Kind == ECkGym_ControlKind::Header)
    {
        return SNew(STextBlock)
            .Text(FText::FromString(InRow.Label))
            .WrapTextAt(InWidths.Content)
            .Font(CkStyle::BoldFont(CkStyle::FontSizeMicro()))
            .ColorAndOpacity(CkStyle::AccentDim());
    }

    auto Content = SNew(SHorizontalBox);

    // Key chip column - Status rows keep the column width so labels align.
    Content->AddSlot()
        .AutoWidth()
        .VAlign(VAlign_Center)
        .Padding(FMargin{0.0f, 0.0f, CkStyle::SpaceS, 0.0f})
        [
            SNew(SBox)
            .MinDesiredWidth(KeyChipWidth)
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
            .WrapTextAt(InWidths.Label)
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

        auto ValueWidget = TSharedPtr<SWidget>{};

        if (InCompact)
        {
            // Compact is one line per row - the clipping is what makes the mode scannable - so the
            // value ellipsizes inside a hard ceiling rather than wrapping and growing the row tall.
            // The ceiling is the SMALLER of the mode's own cap and the column the card actually has:
            // the cap is absolute, so on any card narrower than it the value would push the row past
            // the panel's edge.
            ValueWidget = SNew(SBox)
                .MaxDesiredWidth(FMath::Min(CompactValueWidth, InWidths.Value))
                [
                    SNew(STextBlock)
                    .Text(FText::FromString(InRow.Value))
                    .OverflowPolicy(ETextOverflowPolicy::Ellipsis)
                    .Font(CkStyle::BoldFont(CkStyle::FontSizeMicro()))
                    .ColorAndOpacity(Get_Dimmed(ValueColor, InRow.Enabled))
                ];
        }
        else
        {
            ValueWidget = SNew(STextBlock)
                .Text(FText::FromString(InRow.Value))
                .WrapTextAt(InWidths.Value)
                .Font(CkStyle::BoldFont(CkStyle::FontSizeMicro()))
                .ColorAndOpacity(Get_Dimmed(ValueColor, InRow.Enabled));
        }

        Content->AddSlot()
            .AutoWidth()
            .VAlign(VAlign_Center)
            .Padding(FMargin{CkStyle::SpaceM, 0.0f, 0.0f, 0.0f})
            [
                ValueWidget.ToSharedRef()
            ];
    }

    if (IsActiveChoice)
    {
        return SNew(SBorder)
            .BorderImage(CkStyle::GetRoundedBrush())
            .BorderBackgroundColor(CkStyle::OverlayOf(CkStyle::Selection(), 0.3f))
            .Padding(FMargin{RowPaddingH, 1.0f})
            [
                Content
            ];
    }

    return SNew(SBox)
        .Padding(FMargin{RowPaddingH, 1.0f})
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
