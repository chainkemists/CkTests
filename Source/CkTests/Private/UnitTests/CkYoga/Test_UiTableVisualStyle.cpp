#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/CkUiDocument.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkSlateLayout/SCkUiTable.h"

#include "Framework/Application/SlateApplication.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "Layout/WidgetPath.h"
#include "Misc/AutomationTest.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"
#include "Widgets/Views/ITableRow.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_table_visual_style
{
    auto MakeRecord(const FString& InKey, const FString& InLabel) -> FCkUiRecordData
    {
        auto Result = FCkUiRecordData{};
        Result.Key = InKey;
        Result.Fields.Add(TEXT("label"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(InLabel)});
        return Result;
    }

    auto Markup(const bool bWithStyleClass = true) -> FString
    {
        const TCHAR* StyleClass = bWithStyleClass ? TEXT(" class=\"table-style\"") : TEXT("");
        return FString{TEXT("<ui version=\"1\"><region name=\"main\"><table id=\"records\" bind=\"records\" selection-action=\"selected\" row-height=\"24\"")}
            + StyleClass + TEXT("><table-column id=\"label\" label=\"Label\" sort-field=\"label\"><text id=\"value\" bind-field=\"label\"/></table-column></table></region></ui>");
    }

    auto ValidStyles(const FString& InSelectedBackground = TEXT("#244d6d"), const bool bWithSortIndicator = true) -> FString
    {
        return FString{TEXT(".table-style ")
            TEXT("{ ")
            TEXT("-ck-table-header-background: #142c3d; ")
            }
            + (bWithSortIndicator ? TEXT("-ck-table-sort-indicator-color: #61d9e8; ") : TEXT(""))
            + TEXT("-ck-table-header-padding-x: 9px; ")
            TEXT("-ck-table-header-padding-y: 6px; ")
            TEXT("-ck-table-row-background: #102131; ")
            TEXT("-ck-table-row-hover-background: #183d56; ")
            + FString::Printf(TEXT("-ck-table-row-selected-background: %s; "), *InSelectedBackground)
            + TEXT("-ck-table-row-separator-color: #315268; -ck-table-row-separator-width: 1px; }");
    }

    auto WrongNodeMarkup(const FString& InNode) -> FString
    {
        return TEXT("<ui version=\"1\"><region name=\"main\">") + InNode + TEXT("</region></ui>");
    }

    struct FWindowScope final
    {
        explicit FWindowScope(FSlateApplication& InSlate) : Slate(InSlate) {}
        ~FWindowScope() { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } }

        FSlateApplication& Slate;
        TSharedPtr<SWindow> Window;
    };

    auto TickSlate(FSlateApplication& InSlate) -> void
    {
        InSlate.PumpMessages();
        InSlate.Tick();
        InSlate.Tick();
    }

    auto FindHeaderButton(const TSharedRef<SWidget>& InRoot, bool bInHeader = false) -> TSharedPtr<SButton>
    {
        bInHeader |= InRoot->GetTypeAsString() == TEXT("STableColumnHeader");
        if (bInHeader && InRoot->GetTypeAsString() == TEXT("SButton")) { return StaticCastSharedRef<SButton>(InRoot); }
        FChildren* Children = InRoot->GetChildren();
        if (Children == nullptr) { return {}; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        {
            const TSharedPtr<SButton> Found = FindHeaderButton(Children->GetChildAt(Index), bInHeader);
            if (Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto FindText(const TSharedRef<SWidget>& InRoot, const FText& InText) -> TSharedPtr<STextBlock>
    {
        if (InRoot->GetTypeAsString() == TEXT("STextBlock"))
        {
            const TSharedRef<STextBlock> Text = StaticCastSharedRef<STextBlock>(InRoot);
            if (Text->GetText().EqualTo(InText)) { return Text; }
        }
        FChildren* Children = InRoot->GetChildren();
        if (Children == nullptr) { return {}; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        {
            const TSharedPtr<STextBlock> Found = FindText(Children->GetChildAt(Index), InText);
            if (Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto Click(const TSharedRef<SButton>& InButton) -> bool
    {
        const FGeometry Geometry = InButton->GetCachedGeometry();
        const FVector2D Position = Geometry.GetAbsolutePosition() + Geometry.GetAbsoluteSize() * 0.5f;
        const TSet<FKey> DownButtons{EKeys::LeftMouseButton};
        const FPointerEvent Down{0, Position, Position, DownButtons, EKeys::LeftMouseButton, 0, FModifierKeysState{}};
        const TSet<FKey> UpButtons;
        const FPointerEvent Up{0, Position, Position, UpButtons, EKeys::LeftMouseButton, 0, FModifierKeysState{}};
        FWidgetPath Path;
        FSlateApplication& Slate = FSlateApplication::Get();
        if (!Slate.GeneratePathToWidgetUnchecked(InButton, Path)) { return false; }
        InButton->OnMouseEnter(Geometry, Down);
        const FReply Pressed = InButton->OnMouseButtonDown(Geometry, Down);
        Slate.ProcessReply(Path, Pressed, &Path, &Down);
        const FReply Released = InButton->OnMouseButtonUp(Geometry, Up);
        Slate.ProcessReply(Path, Released, &Path, &Up);
        InButton->OnMouseLeave(Up);
        return Pressed.IsEventHandled() && Released.IsEventHandled();
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkUiTable_VisualStyle,
    "Ck.UiAuthoring.Table.VisualStyle",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiTable_VisualStyle::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_table_visual_style;

    FCkUiDocument Parsed;
    const FCkUiLoadResult AcceptedParse = FCkUiDocumentParser::TryParse(Markup(), ValidStyles(), {}, Parsed, TEXT("UiTableVisualStyleAccepted"));
    if (!TestTrue(TEXT("Table visual style contract parses on table"), AcceptedParse.Succeeded))
    {
        for (const FString& Error : AcceptedParse.Errors) { AddError(Error); }
        return false;
    }

    const TArray<FString> Properties = {
        TEXT("-ck-table-header-background: #142c3d;"),
        TEXT("-ck-table-sort-indicator-color: #61d9e8;"),
        TEXT("-ck-table-header-padding-x: 9px;"),
        TEXT("-ck-table-header-padding-y: 6px;"),
        TEXT("-ck-table-row-background: #102131;"),
        TEXT("-ck-table-row-hover-background: #183d56;"),
        TEXT("-ck-table-row-selected-background: #244d6d;"),
        TEXT("-ck-table-row-separator-color: #315268;"),
        TEXT("-ck-table-row-separator-width: 1px;")};
    for (const FString& Property : Properties)
    {
        FCkUiDocument WrongNode;
        const FString Styles = TEXT(".wrong { ") + Property + TEXT(" }");
        const FCkUiLoadResult Rejected = FCkUiDocumentParser::TryParse(
            WrongNodeMarkup(TEXT("<column id=\"wrong\" class=\"wrong\"/>")), Styles, {}, WrongNode, TEXT("UiTableVisualStyleWrongNode"));
        TestFalse(*FString::Printf(TEXT("Table-only style rejects column applicability: %s"), *Property), Rejected.Succeeded);
    }

    if (!FSlateApplication::IsInitialized())
    {
        AddError(TEXT("Table visual style test requires an initialized Slate application."));
        return false;
    }

    TSharedPtr<FCkUiCollection> Collection;
    if (!TestTrue(TEXT("Visual style collection creates"), FCkUiCollection::TryCreate({{TEXT("label"), ECkUiFieldKind::Text}}, Collection).Succeeded)
        || !TestTrue(TEXT("Visual style records publish"), Collection->TrySetRecords({MakeRecord(TEXT("alpha"), TEXT("Alpha")), MakeRecord(TEXT("beta"), TEXT("Beta"))}).Succeeded))
    {
        return false;
    }

    int32 SelectionNotifications = 0;
    auto Data = FCkUiView::FDataBindings{};
    Data.Collections.Add(TEXT("records"), Collection);
    Data.TableSelectionChanged.Add(TEXT("selected"), FOnCkUiTableSelectionChanged::CreateLambda(
        [&SelectionNotifications](TOptional<FString>, ESelectInfo::Type) { ++SelectionNotifications; }));
    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, MoveTemp(Data));
    const TSharedRef<SWidget> Region = View->GetRegion(TEXT("main"));
    FSlateApplication& Slate = FSlateApplication::Get();
    FWindowScope Scope{Slate};
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{360.0f, 160.0f})
        .CreateTitleBar(false).HasCloseButton(false)[Region];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);

    const FCkUiLoadResult Initial = View->TryReload(Markup(), ValidStyles(), TEXT("UiTableVisualStyleInitial"));
    if (!TestTrue(TEXT("Styled production table loads"), Initial.Succeeded))
    {
        for (const FString& Error : Initial.Errors) { AddError(Error); }
        return false;
    }
    TickSlate(Slate);

    const TSharedPtr<SCkUiTable> Table = View->GetTable(TEXT("records"));
    const TSharedPtr<SListView<SCkUiTable::FRecord>> List = Table.IsValid() ? Table->GetList() : nullptr;
    const TSharedPtr<const FCkUiRecord> Alpha = Collection->FindRecord(TEXT("alpha"));
    if (!TestTrue(TEXT("Styled document mounts the production table and native list"), Table.IsValid() && List.IsValid() && Alpha.IsValid())) { return false; }
    List->RequestScrollIntoView(Alpha);
    TickSlate(Slate);
    const TSharedPtr<ITableRow> InitialRow = List->WidgetFromItem(Alpha);
    if (!TestTrue(TEXT("Styled production table realizes its row"), InitialRow.IsValid())) { return false; }

    const TSharedPtr<SButton> HeaderButton = FindHeaderButton(Table.ToSharedRef());
    const TSharedPtr<STextBlock> InactiveIndicator = FindText(Table.ToSharedRef(), FText::FromString(TEXT("↕")));
    if (!TestTrue(TEXT("Styled sortable header mounts a production header button and inactive indicator"), HeaderButton.IsValid() && InactiveIndicator.IsValid())) { return false; }
    TestTrue(TEXT("Inactive indicator uses its authored color"), InactiveIndicator->GetColorAndOpacity().GetSpecifiedColor().Equals(FLinearColor::FromSRGBColor(FColor(0x61, 0xd9, 0xe8))));

    TestTrue(TEXT("Styled table preserves native programmatic selection"), Table->TrySelectKey(FString{TEXT("alpha")}, true));
    TestTrue(TEXT("Styled table exposes the selected stable key"), Table->GetSelectedKey() == TOptional<FString>{TEXT("alpha")});
    TestEqual(TEXT("Styled table selection invokes its documented callback once"), SelectionNotifications, 1);

    TestTrue(TEXT("Routed header activation sorts ascending"), Click(HeaderButton.ToSharedRef()));
    TickSlate(Slate);
    TestTrue(TEXT("Ascending indicator replaces inactive indicator"), FindText(Table.ToSharedRef(), FText::FromString(TEXT("↑"))).IsValid()
        && !FindText(Table.ToSharedRef(), FText::FromString(TEXT("↕"))).IsValid());
    TestTrue(TEXT("Second routed header activation sorts descending"), Click(HeaderButton.ToSharedRef()));
    TickSlate(Slate);
    TestTrue(TEXT("Descending indicator replaces ascending indicator"), FindText(Table.ToSharedRef(), FText::FromString(TEXT("↓"))).IsValid()
        && !FindText(Table.ToSharedRef(), FText::FromString(TEXT("↑"))).IsValid());
    const TSharedPtr<ITableRow> RowBeforeReload = List->WidgetFromItem(Alpha);
    if (!TestTrue(TEXT("Sorted table retains a realized selected row before reload"), RowBeforeReload.IsValid())) { return false; }

    const int64 AcceptedRevision = View->GetRevision();
    const FCkUiLoadResult CompatibleReload = View->TryReload(Markup(), ValidStyles(TEXT("#2f6288")), TEXT("UiTableVisualStyleCompatibleReload"));
    if (!TestTrue(TEXT("Compatible table visual style reload succeeds"), CompatibleReload.Succeeded))
    {
        for (const FString& Error : CompatibleReload.Errors) { AddError(Error); }
        return false;
    }
    TickSlate(Slate);
    TestEqual(TEXT("Compatible table visual style reload advances revision"), View->GetRevision(), AcceptedRevision + 1);
    TestTrue(TEXT("Compatible visual style reload retains table and native list identity"), View->GetTable(TEXT("records")) == Table && Table->GetList() == List);
    TestTrue(TEXT("Compatible visual style reload retains selected stable key"), Table->GetSelectedKey() == TOptional<FString>{TEXT("alpha")});
    TestTrue(TEXT("Compatible visual style reload retains realized row identity"), List->WidgetFromItem(Alpha) == RowBeforeReload);
    TestEqual(TEXT("Compatible visual style reload sends no synthetic selection callback"), SelectionNotifications, 1);
    TestTrue(TEXT("Compatible visual style reload retains descending indicator state"), FindText(Table.ToSharedRef(), FText::FromString(TEXT("↓"))).IsValid());

    const auto RejectAtomically = [this, &View, &Table, &List, &Alpha, &RowBeforeReload, AcceptedRevision, &SelectionNotifications](const FString& InName, const FString& InStyles)
    {
        const FCkUiLoadResult Rejected = View->TryReload(Markup(), InStyles, InName);
        TestFalse(*FString::Printf(TEXT("%s rejects"), *InName), Rejected.Succeeded);
        TestEqual(*FString::Printf(TEXT("%s retains accepted revision"), *InName), View->GetRevision(), AcceptedRevision + 1);
        TestTrue(*FString::Printf(TEXT("%s retains production table list and row"), *InName), View->GetTable(TEXT("records")) == Table && Table->GetList() == List && List->WidgetFromItem(Alpha) == RowBeforeReload);
        TestTrue(*FString::Printf(TEXT("%s retains selection"), *InName), Table->GetSelectedKey() == TOptional<FString>{TEXT("alpha")});
        TestEqual(*FString::Printf(TEXT("%s sends no callback"), *InName), SelectionNotifications, 1);
        TestTrue(*FString::Printf(TEXT("%s retains the rendered descending indicator"), *InName), FindText(Table.ToSharedRef(), FText::FromString(TEXT("↓"))).IsValid());
    };
    RejectAtomically(TEXT("Invalid table visual color"), TEXT(".table-style { -ck-table-row-hover-background: not-a-color; }"));
    RejectAtomically(TEXT("Invalid sort indicator color"), TEXT(".table-style { -ck-table-sort-indicator-color: not-a-color; }"));
    RejectAtomically(TEXT("Negative table visual length"), TEXT(".table-style { -ck-table-row-separator-width: -1px; }"));

    const FCkUiLoadResult RemoveIndicator = View->TryReload(Markup(), ValidStyles(TEXT("#2f6288"), false), TEXT("UiTableVisualStyleRemoveIndicator"));
    if (!TestTrue(TEXT("Compatible indicator-only style removal succeeds"), RemoveIndicator.Succeeded))
    {
        for (const FString& Error : RemoveIndicator.Errors) { AddError(Error); }
        return false;
    }
    TickSlate(Slate);
    TestTrue(TEXT("Indicator-only style removal retains table list and row identity"), View->GetTable(TEXT("records")) == Table && Table->GetList() == List && List->WidgetFromItem(Alpha) == RowBeforeReload);
    TestTrue(TEXT("Indicator-only style removal retains selection and descending sort"), Table->GetSelectedKey() == TOptional<FString>{TEXT("alpha")}
        && List->GetItems().Num() > 0 && List->GetItems()[0]->GetKey() == TEXT("beta"));
    TestTrue(TEXT("Indicator-only style removal removes Ck-owned glyphs"), !FindText(Table.ToSharedRef(), FText::FromString(TEXT("↕"))).IsValid()
        && !FindText(Table.ToSharedRef(), FText::FromString(TEXT("↑"))).IsValid()
        && !FindText(Table.ToSharedRef(), FText::FromString(TEXT("↓"))).IsValid());

    const FCkUiLoadResult ClearStyle = View->TryReload(Markup(false), TEXT(""), TEXT("UiTableVisualStyleClear"));
    if (!TestTrue(TEXT("Compatible table style clear succeeds"), ClearStyle.Succeeded))
    {
        for (const FString& Error : ClearStyle.Errors) { AddError(Error); }
        return false;
    }
    TickSlate(Slate);
    TestTrue(TEXT("Style clear retains table list and row identity"), View->GetTable(TEXT("records")) == Table && Table->GetList() == List && List->WidgetFromItem(Alpha) == RowBeforeReload);
    TestTrue(TEXT("Style clear retains selected stable key"), Table->GetSelectedKey() == TOptional<FString>{TEXT("alpha")});
    TestTrue(TEXT("Style clear removes Ck-owned sort glyph"), !FindText(Table.ToSharedRef(), FText::FromString(TEXT("↕"))).IsValid()
        && !FindText(Table.ToSharedRef(), FText::FromString(TEXT("↑"))).IsValid()
        && !FindText(Table.ToSharedRef(), FText::FromString(TEXT("↓"))).IsValid());
    return true;
}

#endif
