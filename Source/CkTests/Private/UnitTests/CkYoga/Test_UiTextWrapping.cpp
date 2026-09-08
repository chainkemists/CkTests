#include "CkSlateLayout/CkFlexText.h"
#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkSlateLayout/SCkUiTable.h"

#include "Framework/Application/SlateApplication.h"
#include "Misc/AutomationTest.h"
#include "Styling/CoreStyle.h"
#include "Widgets/SWindow.h"
#include "Widgets/Views/ITableRow.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_text_wrapping
{
    auto FindText(const TSharedRef<SWidget>& InWidget) -> TSharedPtr<SCkFlexText>
    {
        if (InWidget->GetTypeAsString() == TEXT("SCkFlexText")) { return StaticCastSharedRef<SCkFlexText>(InWidget); }
        const FChildren* Children = InWidget->GetChildren();
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        {
            if (const auto Found = FindText(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid()) { return Found; }
        }
        return nullptr;
    }

    auto Tick(FSlateApplication& InSlate) -> void { InSlate.PumpMessages(); InSlate.Tick(); InSlate.Tick(); }

    struct FWindowScope
    {
        FSlateApplication& Slate;
        TSharedPtr<SWindow> Window;
        ~FWindowScope() { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } }
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiTextWrapping_Runtime,
    "Ck.UiAuthoring.TextWrapping.RuntimeAndTableReload",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiTextWrapping_Runtime::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_text_wrapping;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Text wrapping requires Slate.")); return false; }
    FString Label = TEXT("A long resource name with enough words to wrap across several narrow lines");
    TSharedPtr<FCkUiCollection> Collection;
    if (!TestTrue(TEXT("Collection creates"), FCkUiCollection::TryCreate({{TEXT("label"), ECkUiFieldKind::Text}}, Collection).Succeeded)) { return false; }
    auto Data = FCkUiView::FDataBindings{};
    Data.Text.Add(TEXT("label"), TAttribute<FText>::CreateLambda([&Label]() { return FText::FromString(Label); }));
    Data.Collections.Add(TEXT("rows"), Collection);
    const auto View = FCkUiView::Create({}, {}, {}, FCoreStyle::GetDefaultFontStyle("Regular", 12), MoveTemp(Data));
    const auto Region = View->GetRegion(TEXT("main"));
    const FString Markup = TEXT("<ui version=\"1\"><region name=\"main\"><text id=\"label\" class=\"label\" bind=\"label\"/></region></ui>");
    const FString Wrapped = TEXT(".label { text-wrap: wrap; text-overflow: clip; }");
    const FString Ellipsis = TEXT(".label { text-overflow: ellipsis; text-wrap: nowrap; }");
    if (!TestTrue(TEXT("Wrapping document loads"), View->TryReload(Markup, Wrapped).Succeeded)) { return false; }
    FSlateApplication& Slate = FSlateApplication::Get();
    FWindowScope Scope{Slate};
    Scope.Window = SNew(SWindow).ClientSize(FVector2D{240, 180}).CreateTitleBar(false)[Region];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);
    Tick(Slate);
    const auto WrappedText = FindText(Region);
    if (!TestTrue(TEXT("Authored wrapped text is realized"), WrappedText.IsValid())) { return false; }
    const auto WrappedSize = WrappedText->Measure(90, YGMeasureModeExactly, YGUndefined, YGMeasureModeUndefined, 1);
    if (!TestTrue(TEXT("Nowrap ellipsis reload applies regardless of property order"), View->TryReload(Markup, Ellipsis).Succeeded)) { return false; }
    Tick(Slate);
    const auto Text = FindText(Region);
    if (!TestTrue(TEXT("Reload realizes authored text"), Text.IsValid())) { return false; }
    const auto Narrow = Text->Measure(90, YGMeasureModeExactly, YGUndefined, YGMeasureModeUndefined, 1);
    const auto Wide = Text->Measure(600, YGMeasureModeExactly, YGUndefined, YGMeasureModeUndefined, 1);
    TestTrue(TEXT("Nowrap eliminates soft line breaks"), WrappedSize.Y > Narrow.Y * 2);
    TestEqual(TEXT("Nowrap still honors Yoga's width"), Narrow.X, 90.0);
    TestEqual(TEXT("Nowrap line height is independent of allotted width"), Narrow.Y, Wide.Y);
    const auto Natural = Text->Measure(YGUndefined, YGMeasureModeUndefined, YGUndefined, YGMeasureModeUndefined, 1);
    TestTrue(TEXT("Ellipsis does not truncate the intrinsic text measurement"), Natural.X > 90);
    Label = TEXT("First line\nSecond line");
    const auto ExplicitLines = Text->Measure(90, YGMeasureModeExactly, YGUndefined, YGMeasureModeUndefined, 1);
    TestTrue(TEXT("Nowrap preserves explicit line breaks"), ExplicitLines.Y > Narrow.Y * 1.5);
    const auto Revision = View->GetRevision();
    TestFalse(TEXT("Wrapped ellipsis rejects atomically"), View->TryReload(Markup, TEXT(".label { text-wrap: wrap; text-overflow: ellipsis; }")).Succeeded);
    TestEqual(TEXT("Rejected style preserves revision"), View->GetRevision(), Revision);
    TestTrue(TEXT("Rejected style preserves text widget"), FindText(Region) == Text);

    auto Row = FCkUiRecordData{};
    Row.Key = TEXT("one");
    Row.Fields.Add(TEXT("label"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(TEXT("A long table record label with many words for narrow columns"))});
    if (!TestTrue(TEXT("Table record publishes"), Collection->TrySetRecords({Row}).Succeeded)) { return false; }
    const FString TableMarkup = TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"><table id=\"table\" bind=\"rows\" class=\"fill\"><table-column id=\"name\" label=\"Name\"><text id=\"cell\" class=\"label\" bind-field=\"label\"/></table-column></table></column></region></ui>");
    if (!TestTrue(TEXT("Table with nowrap cells loads"), View->TryReload(TableMarkup, Ellipsis + TEXT(".fill { flex-grow: 1; }")).Succeeded)) { return false; }
    Tick(Slate);
    const auto Table = View->GetTable(TEXT("table"));
    if (!TestTrue(TEXT("Authored table exists"), Table.IsValid())) { return false; }
    const auto List = Table->GetList();
    const auto Record = Collection->FindRecord(TEXT("one"));
    const auto NativeRow = List->WidgetFromItem(Record);
    const auto Cell = NativeRow.IsValid() ? FindText(NativeRow->AsWidget()) : nullptr;
    if (!TestTrue(TEXT("Native generated row contains authored cell"), Cell.IsValid())) { return false; }
    const auto CellHeight = Cell->Measure(90, YGMeasureModeExactly, YGUndefined, YGMeasureModeUndefined, 1).Y;
    TestTrue(TEXT("Selection succeeds"), Table->TrySelectKey(FString(TEXT("one"))));
    if (!TestTrue(TEXT("Cell wrapping reload applies"), View->TryReload(TableMarkup, Wrapped + TEXT(".fill { flex-grow: 1; }")).Succeeded)) { return false; }
    Tick(Slate);
    const auto ReloadedRow = List->WidgetFromItem(Record);
    const auto ReloadedCell = ReloadedRow.IsValid() ? FindText(ReloadedRow->AsWidget()) : nullptr;
    TestTrue(TEXT("Style reload retains list and selection"), View->GetTable(TEXT("table"))->GetList() == List && List->GetSelectedItems().Contains(Record));
    TestTrue(TEXT("Reloaded cell uses wrapping measurement"), ReloadedCell.IsValid()
        && ReloadedCell->Measure(90, YGMeasureModeExactly, YGUndefined, YGMeasureModeUndefined, 1).Y > CellHeight * 2);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiTextWrapping_Validation,
    "Ck.UiAuthoring.TextWrapping.Validation",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiTextWrapping_Validation::RunTest(const FString&) -> bool
{
    FCkUiDocument Document;
    const FString Markup = TEXT("<ui version=\"1\"><region name=\"main\"><text id=\"label\" class=\"label\">Label</text></region></ui>");
    const TMap<FString, FString> Tokens{{TEXT("--wrap"), TEXT("nowrap")}, {TEXT("--overflow"), TEXT("ellipsis")}};
    if (!TestTrue(TEXT("Tokenized wrapping styles parse"), FCkUiDocumentParser::TryParse(Markup,
        TEXT(".label { text-wrap: var(--wrap); text-overflow: var(--overflow); }"), Tokens, Document).Succeeded)) { return false; }
    const auto Reject = [this, &Document](const FString& InMarkup, const FString& InCss)
    {
        const auto Result = FCkUiDocumentParser::TryParse(InMarkup, InCss, {}, Document);
        TestFalse(TEXT("Invalid text style rejects"), Result.Succeeded);
        TestTrue(TEXT("Rejection explains the error"), !Result.Errors.IsEmpty());
        TestTrue(TEXT("Rejection preserves accepted document"), Document.Regions.Contains(TEXT("main")) && Document.Regions.FindRef(TEXT("main")).Id == TEXT("label"));
    };
    Reject(Markup, TEXT(".label { text-wrap: balanced; }"));
    Reject(Markup, TEXT(".label { text-overflow: fade; }"));
    Reject(Markup, TEXT(".label { text-overflow: ellipsis; }"));
    Reject(TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\" class=\"label\"/></region></ui>"), TEXT(".label { text-wrap: nowrap; }"));
    Reject(TEXT("<ui version=\"1\"><template name=\"unused\"><text id=\"body\" class=\"label\">Body</text></template><region name=\"main\"><text id=\"ok\">Okay</text></region></ui>"), TEXT(".label { text-overflow: ellipsis; }"));
    return true;
}

#endif
