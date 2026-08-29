#include "SCkGym_Switchboard.h"

#include "CkGym_Switchboard_Subsystem.h"

#include "CkEditorTools/Style/CkStyle.h"

#include <Widgets/Layout/SBorder.h>
#include <Widgets/Layout/SBox.h>
#include <Widgets/Layout/SSpacer.h>
#include <Widgets/SBoxPanel.h>
#include <Widgets/Text/STextBlock.h>

// --------------------------------------------------------------------------------------------------------------------

namespace ck_gym_switchboard_widget
{
    // Ink dark enough to sit on a saturated category pill — the focus card's chip-ink constant.
    constexpr auto ChipInk = FLinearColor{0.04f, 0.07f, 0.10f, 1.0f};

    constexpr float RailWidth = 190.0f;
    constexpr float ListWidth = 360.0f;

    auto Make_CategoryPill(const FString& InText, const FLinearColor& InHue, float InFillAlpha) -> TSharedRef<SWidget>
    {
        return SNew(SBorder)
            .BorderImage(CkStyle::GetRoundedBrush())
            .BorderBackgroundColor(CkStyle::OverlayOf(InHue, InFillAlpha))
            .Padding(FMargin{CkStyle::SpaceS, 1.0f})
            [
                SNew(STextBlock)
                .Text(FText::FromString(InText))
                .Font(CkStyle::BoldFont(CkStyle::FontSizeMicro()))
                .ColorAndOpacity(InFillAlpha > 0.5f ? ChipInk : CkStyle::OverlayOf(InHue, 0.95f))
            ];
    }
}

// --------------------------------------------------------------------------------------------------------------------

auto
    SCkGym_Switchboard::
    Construct(
        const FArguments& InArgs)
    -> void
{
    SetVisibility(EVisibility::HitTestInvisible);
}

auto
    SCkGym_Switchboard::
    Refresh(
        const FCkGym_Switchboard_Model& InModel)
    -> void
{
    using namespace ck_gym_switchboard_widget;

    auto Body = SNew(SHorizontalBox);

    if (NOT InModel.Get_IsFiltered())
    {
        Body->AddSlot()
            .AutoWidth()
            .Padding(FMargin{0.0f, 0.0f, CkStyle::SpaceM, 0.0f})
            [
                SNew(SBox)
                .WidthOverride(RailWidth)
                [
                    DoBuild_Rail(InModel)
                ]
            ];
    }

    Body->AddSlot()
        .AutoWidth()
        [
            SNew(SBox)
            .WidthOverride(ListWidth)
            [
                DoBuild_RowList(InModel)
            ]
        ];

    ChildSlot
    [
        SNew(SBox)
        .HAlign(HAlign_Center)
        .VAlign(VAlign_Center)
        [
            SNew(SBorder)
            .BorderImage(CkStyle::GetRoundedBrush_Large())
            .BorderBackgroundColor(CkStyle::Border())
            .Padding(FMargin{2.0f})
            [
                SNew(SBorder)
                .BorderImage(CkStyle::GetRoundedBrush_Large())
                .BorderBackgroundColor(CkStyle::OverlayOf(CkStyle::BgRoot(), 0.92f))
                .Padding(FMargin{CkStyle::SpaceL})
                [
                    SNew(SVerticalBox)
                    + SVerticalBox::Slot()
                    .AutoHeight()
                    .Padding(FMargin{0.0f, 0.0f, 0.0f, CkStyle::SpaceM})
                    [
                        DoBuild_Header(InModel)
                    ]
                    + SVerticalBox::Slot()
                    .AutoHeight()
                    [
                        Body
                    ]
                    + SVerticalBox::Slot()
                    .AutoHeight()
                    .Padding(FMargin{0.0f, CkStyle::SpaceM, 0.0f, 0.0f})
                    [
                        DoBuild_SettingsLine(InModel)
                    ]
                    + SVerticalBox::Slot()
                    .AutoHeight()
                    .Padding(FMargin{0.0f, CkStyle::SpaceS, 0.0f, 0.0f})
                    [
                        DoBuild_Footer(InModel)
                    ]
                ]
            ]
        ]
    ];
}

// --------------------------------------------------------------------------------------------------------------------

auto
    SCkGym_Switchboard::
    DoBuild_Header(
        const FCkGym_Switchboard_Model& InModel)
    -> TSharedRef<SWidget>
{
    auto Header = SNew(SHorizontalBox);

    Header->AddSlot()
        .AutoWidth()
        .VAlign(VAlign_Center)
        [
            SNew(STextBlock)
            .Text(FText::FromString(TEXT("GYM SWITCHBOARD")))
            .Font(CkStyle::BoldFont(CkStyle::FontSizeH3()))
            .ColorAndOpacity(CkStyle::Text())
        ];

    const auto FilterText = InModel.Get_IsFiltered()
        ? FString::Printf(TEXT("filter: %s_  (%d)"), *InModel.Filter, InModel.FilteredRows.Num())
        : FString{TEXT("type to filter")};

    Header->AddSlot()
        .FillWidth(1.0f)
        .HAlign(HAlign_Right)
        .VAlign(VAlign_Center)
        [
            SNew(STextBlock)
            .Text(FText::FromString(FilterText))
            .Font(CkStyle::MonoFont(CkStyle::FontSizeSmall()))
            .ColorAndOpacity(InModel.Get_IsFiltered() ? CkStyle::Accent() : CkStyle::TextMute())
        ];

    return Header;
}

auto
    SCkGym_Switchboard::
    DoBuild_Rail(
        const FCkGym_Switchboard_Model& InModel)
    -> TSharedRef<SWidget>
{
    using namespace ck_gym_switchboard_widget;

    auto Rail = SNew(SVerticalBox);

    for (auto GroupIndex = 0; GroupIndex < InModel.Groups.Num(); ++GroupIndex)
    {
        const auto& Group = InModel.Groups[GroupIndex];
        const auto IsSelected = GroupIndex == InModel.SelectedGroupIndex;

        auto RowContent = SNew(SHorizontalBox);

        RowContent->AddSlot()
            .AutoWidth()
            .VAlign(VAlign_Center)
            .Padding(FMargin{0.0f, 0.0f, CkStyle::SpaceS, 0.0f})
            [
                Make_CategoryPill(Group.Category, Group.Hue, IsSelected ? 1.0f : 0.75f)
            ];

        RowContent->AddSlot()
            .FillWidth(1.0f)
            [
                SNew(SSpacer)
            ];

        RowContent->AddSlot()
            .AutoWidth()
            .VAlign(VAlign_Center)
            [
                SNew(STextBlock)
                .Text(FText::FromString(FString::FromInt(Group.Rows.Num())))
                .Font(CkStyle::MonoFont(CkStyle::FontSizeMicro()))
                .ColorAndOpacity(IsSelected ? CkStyle::Text() : CkStyle::TextMute())
            ];

        Rail->AddSlot()
            .AutoHeight()
            .Padding(FMargin{0.0f, 0.0f, 0.0f, CkStyle::SpaceXS})
            [
                SNew(SBorder)
                .BorderImage(CkStyle::GetRoundedBrush())
                .BorderBackgroundColor(IsSelected
                    ? CkStyle::OverlayOf(CkStyle::Selection(), 0.35f)
                    : CkStyle::OverlayOf(CkStyle::Bg2(), 0.6f))
                .Padding(FMargin{CkStyle::SpaceS, 3.0f})
                [
                    RowContent
                ]
            ];
    }

    return Rail;
}

auto
    SCkGym_Switchboard::
    DoBuild_RowList(
        const FCkGym_Switchboard_Model& InModel)
    -> TSharedRef<SWidget>
{
    using namespace ck_gym_switchboard_widget;

    const auto& Rows = InModel.Get_ActiveRows();

    auto List = SNew(SVerticalBox);

    if (Rows.Num() == 0)
    {
        List->AddSlot()
            .AutoHeight()
            [
                SNew(STextBlock)
                .Text(FText::FromString(TEXT("no matches")))
                .Font(CkStyle::RegularFont(CkStyle::FontSizeBody()))
                .ColorAndOpacity(CkStyle::TextMute())
            ];

        return List;
    }

    // Window the list around the selection — a HitTestInvisible tree can never scroll, so content
    // past the budget is clipped by choice of window, not by a scrollbar.
    const auto MaxVisible = FCkGym_Switchboard_Model::MaxVisibleRows;
    auto WindowStart = FMath::Clamp(InModel.SelectedRowIndex - MaxVisible / 2, 0,
        FMath::Max(0, Rows.Num() - MaxVisible));
    const auto WindowEnd = FMath::Min(Rows.Num(), WindowStart + MaxVisible);

    if (WindowStart > 0)
    {
        List->AddSlot()
            .AutoHeight()
            [
                SNew(STextBlock)
                .Text(FText::FromString(FString::Printf(TEXT("… %d above"), WindowStart)))
                .Font(CkStyle::MonoFont(CkStyle::FontSizeMicro()))
                .ColorAndOpacity(CkStyle::TextMute())
            ];
    }

    for (auto RowIndex = WindowStart; RowIndex < WindowEnd; ++RowIndex)
    {
        const auto& Row = Rows[RowIndex];
        const auto IsSelected = RowIndex == InModel.SelectedRowIndex;
        const auto IsCurrent = Row.RegistryIndex == InModel.CurrentGymRegistryIndex;

        auto RowContent = SNew(SHorizontalBox);

        if (InModel.Get_IsFiltered())
        {
            const auto Hue = UCkGym_Switchboard_Subsystem::Get_CategoryHue(Row.Category);

            RowContent->AddSlot()
                .AutoWidth()
                .VAlign(VAlign_Center)
                .Padding(FMargin{0.0f, 0.0f, CkStyle::SpaceS, 0.0f})
                [
                    Make_CategoryPill(Row.Category, Hue, 0.75f)
                ];
        }

        RowContent->AddSlot()
            .FillWidth(1.0f)
            .VAlign(VAlign_Center)
            [
                SNew(STextBlock)
                .Text(FText::FromString(Row.DisplayName))
                .Font(IsSelected ? CkStyle::BoldFont(CkStyle::FontSizeBody()) : CkStyle::RegularFont(CkStyle::FontSizeBody()))
                .ColorAndOpacity(IsSelected ? CkStyle::TextStrong() : CkStyle::Text())
            ];

        if (IsCurrent)
        {
            RowContent->AddSlot()
                .AutoWidth()
                .VAlign(VAlign_Center)
                [
                    SNew(STextBlock)
                    .Text(FText::FromString(TEXT("● running")))
                    .Font(CkStyle::BoldFont(CkStyle::FontSizeMicro()))
                    .ColorAndOpacity(CkStyle::Ok())
                ];
        }

        List->AddSlot()
            .AutoHeight()
            .Padding(FMargin{0.0f, 0.0f, 0.0f, 1.0f})
            [
                SNew(SBorder)
                .BorderImage(CkStyle::GetRoundedBrush())
                .BorderBackgroundColor(IsSelected
                    ? CkStyle::OverlayOf(CkStyle::Selection(), 0.45f)
                    : FLinearColor::Transparent)
                .Padding(FMargin{CkStyle::SpaceS, 2.0f})
                [
                    RowContent
                ]
            ];
    }

    if (WindowEnd < Rows.Num())
    {
        List->AddSlot()
            .AutoHeight()
            [
                SNew(STextBlock)
                .Text(FText::FromString(FString::Printf(TEXT("… %d below"), Rows.Num() - WindowEnd)))
                .Font(CkStyle::MonoFont(CkStyle::FontSizeMicro()))
                .ColorAndOpacity(CkStyle::TextMute())
            ];
    }

    return List;
}

auto
    SCkGym_Switchboard::
    DoBuild_SettingsLine(
        const FCkGym_Switchboard_Model& InModel)
    -> TSharedRef<SWidget>
{
    // The per-user startup preference (Editor Preferences -> Ck Tests -> Gym Cycler), editable
    // without leaving the menu: F1 cycles the mode, F2 pins the selected gym as the default.
    auto ModeText = FString{};
    switch (InModel.StartupMode)
    {
        case ECkGym_StartupMode::Default:
            ModeText = FString::Printf(TEXT("Default → %s"),
                InModel.DefaultGymName.IsEmpty() ? TEXT("(unset)") : *InModel.DefaultGymName);
            break;
        case ECkGym_StartupMode::Last:
            ModeText = FString::Printf(TEXT("Last (→ %s)"),
                InModel.LastGymName.IsEmpty() ? TEXT("none yet") : *InModel.LastGymName);
            break;
        case ECkGym_StartupMode::Cycler:
        default:
            ModeText = TEXT("Cycler (this menu)");
            break;
    }

    return SNew(SHorizontalBox)
        + SHorizontalBox::Slot()
        .AutoWidth()
        .VAlign(VAlign_Center)
        [
            SNew(STextBlock)
            .Text(FText::FromString(FString::Printf(TEXT("[F1] startup: %s"), *ModeText)))
            .Font(CkStyle::MonoFont(CkStyle::FontSizeMicro()))
            .ColorAndOpacity(InModel.StartupMode == ECkGym_StartupMode::Cycler
                ? CkStyle::TextMute() : CkStyle::AccentDim())
        ]
        + SHorizontalBox::Slot()
        .AutoWidth()
        .VAlign(VAlign_Center)
        .Padding(FMargin{CkStyle::SpaceL, 0.0f, 0.0f, 0.0f})
        [
            SNew(STextBlock)
            .Text(FText::FromString(TEXT("[F2] start on selected")))
            .Font(CkStyle::MonoFont(CkStyle::FontSizeMicro()))
            .ColorAndOpacity(CkStyle::TextMute())
        ];
}

auto
    SCkGym_Switchboard::
    DoBuild_Footer(
        const FCkGym_Switchboard_Model& InModel)
    -> TSharedRef<SWidget>
{
    // Esc is deliberately unadvertised: in PIE the editor owns it (stop session) at a level the
    // input layers cannot mask, so Tab is the one close key that works everywhere.
    const auto Hints = InModel.Get_IsFiltered()
        ? TEXT("↑↓ select   ·   Enter travel   ·   Backspace edit   ·   Tab close")
        : TEXT("←→ groups   ·   ↑↓ select   ·   Enter travel   ·   type to filter   ·   Tab close");

    return SNew(STextBlock)
        .Text(FText::FromString(Hints))
        .Font(CkStyle::RegularFont(CkStyle::FontSizeMicro()))
        .ColorAndOpacity(CkStyle::TextMute());
}
