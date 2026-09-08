#include "CkSlateLayout/CkFlexText.h"
#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkSlateLayout/SCkUiTable.h"

#include "Framework/Application/SlateApplication.h"
#include "Misc/AutomationTest.h"
#include "Widgets/SWindow.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/IToolTip.h"
#include "Widgets/Text/STextBlock.h"
#include "Widgets/Views/ITableRow.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_text_metadata
{
    auto Record(const FString& InLabel, const FLinearColor InTint, const FString& InDetail) -> FCkUiRecordData
    {
        auto Value = FCkUiRecordData{}; Value.Key = TEXT("one");
        Value.Fields.Add(TEXT("label"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(InLabel)});
        Value.Fields.Add(TEXT("tint"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Color, .Color = InTint});
        Value.Fields.Add(TEXT("detail"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(InDetail)});
        return Value;
    }
    auto Schema() -> TArray<FCkUiFieldSchema> { return {{TEXT("label"), ECkUiFieldKind::Text}, {TEXT("tint"), ECkUiFieldKind::Color}, {TEXT("detail"), ECkUiFieldKind::Text}}; }
    auto TableMarkup() -> FString { return TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"><table id=\"table\" class=\"fill\" bind=\"records\"><table-column id=\"name\" label=\"Name\"><text id=\"cell\" bind-field=\"label\" color-field=\"tint\" tooltip-field=\"detail\"/></table-column></table></column></region></ui>"); }
    auto FindFlexText(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SCkFlexText>
    {
        if (InRoot->GetTypeAsString() == TEXT("SCkFlexText")) { return StaticCastSharedRef<SCkFlexText>(InRoot); }
        const FChildren* Children = InRoot->GetChildren(); if (Children == nullptr) { return nullptr; }
        for (int32 Index = 0; Index < Children->Num(); ++Index) { if (const TSharedPtr<SCkFlexText> Found = FindFlexText(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid()) { return Found; } }
        return nullptr;
    }
    auto FindPlainText(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<STextBlock>
    {
        if (InRoot->GetTypeAsString() == TEXT("STextBlock")) { return StaticCastSharedRef<STextBlock>(InRoot); }
        const FChildren* Children = InRoot->GetChildren(); if (Children == nullptr) { return nullptr; }
        for (int32 Index = 0; Index < Children->Num(); ++Index) { if (const TSharedPtr<STextBlock> Found = FindPlainText(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid()) { return Found; } }
        return nullptr;
    }
    auto RegionContent(const TSharedRef<FCkUiView>& InView) -> TSharedRef<SWidget> { return StaticCastSharedRef<SBox>(InView->GetRegion(TEXT("main")))->GetChildren()->GetChildAt(0); }
    struct FWindowScope final { explicit FWindowScope(FSlateApplication& InSlate) : Slate(InSlate) {} ~FWindowScope() { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } } FSlateApplication& Slate; TSharedPtr<SWindow> Window; };
    auto Tick(FSlateApplication& InSlate) -> void { InSlate.PumpMessages(); InSlate.Tick(); InSlate.Tick(); }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiTextMetadata_Runtime,
    "Ck.UiAuthoring.TextMetadata.GlobalAndTableBindings",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiTextMetadata_Runtime::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_text_metadata;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Text metadata test requires initialized Slate.")); return false; }
    FLinearColor GlobalColor = FLinearColor::Red; FString GlobalTip = TEXT("Initial global tooltip");
    auto GlobalData = FCkUiView::FDataBindings{};
    GlobalData.Color.Add(TEXT("color"), TAttribute<FLinearColor>::CreateLambda([&GlobalColor]() { return GlobalColor; }));
    GlobalData.Text.Add(TEXT("tip"), TAttribute<FText>::CreateLambda([&GlobalTip]() { return FText::FromString(GlobalTip); }));
    const TSharedRef<FCkUiView> GlobalView = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, MoveTemp(GlobalData));
    GlobalView->GetRegion(TEXT("main"));
    const FString GlobalMarkup = TEXT("<ui version=\"1\"><region name=\"main\"><text id=\"global\" color-bind=\"color\" tooltip-bind=\"tip\">Global</text></region></ui>");
    if (!TestTrue(TEXT("Standalone color and tooltip bindings load"), GlobalView->TryReload(GlobalMarkup, TEXT(".unused { color: #ffffff; }"), TEXT("UiTextGlobal")).Succeeded)) { return false; }
    const TSharedPtr<SCkFlexText> GlobalText = FindFlexText(RegionContent(GlobalView));
    if (!TestTrue(TEXT("Standalone metadata produces real flex text"), GlobalText.IsValid())) { return false; }
    TestTrue(TEXT("Standalone global color binding is live"), GlobalText->GetColorAndOpacity().GetSpecifiedColor().Equals(FLinearColor::Red));
    GlobalColor = FLinearColor::Blue; GlobalTip = TEXT("Updated global tooltip");
    TestTrue(TEXT("Standalone global color updates live"), GlobalText->GetColorAndOpacity().GetSpecifiedColor().Equals(FLinearColor::Blue));
    const TSharedPtr<IToolTip> GlobalToolTip = GlobalText->GetToolTip();
    const TSharedPtr<SWidget> GlobalToolTipContent = GlobalToolTip.IsValid() ? TSharedPtr<SWidget>(GlobalToolTip->GetContentWidget()) : nullptr;
    const TSharedPtr<STextBlock> GlobalToolTipText = GlobalToolTipContent.IsValid() ? FindPlainText(GlobalToolTipContent.ToSharedRef()) : nullptr;
    TestTrue(TEXT("Standalone global tooltip updates live"), GlobalToolTipText.IsValid() && GlobalToolTipText->GetText().ToString() == TEXT("Updated global tooltip"));

    TSharedPtr<FCkUiCollection> Collection;
    if (!TestTrue(TEXT("Text metadata collection creates"), FCkUiCollection::TryCreate(Schema(), Collection).Succeeded) || !Collection.IsValid()) { return false; }
    auto Data = FCkUiView::FDataBindings{}; Data.Collections.Add(TEXT("records"), Collection);
    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, MoveTemp(Data));
    const TSharedRef<SWidget> Region = View->GetRegion(TEXT("main"));
    FSlateApplication& Slate = FSlateApplication::Get(); FWindowScope Scope{Slate};
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{320, 180}).CreateTitleBar(false).HasCloseButton(false)[Region]; Slate.AddWindow(Scope.Window.ToSharedRef(), true);
    if (!TestTrue(TEXT("Table metadata markup loads"), View->TryReload(TableMarkup(), TEXT(".fill { flex-grow: 1; }"), TEXT("UiTextTable")).Succeeded)) { return false; }
    if (!TestTrue(TEXT("Initial metadata records commit"), Collection->TrySetRecords({Record(TEXT("First"), FLinearColor::Red, TEXT("First detail"))}).Succeeded)) { return false; } Tick(Slate);
    const TSharedPtr<SCkUiTable> Table = View->GetTable(TEXT("table")); const TSharedPtr<SListView<SCkUiTable::FRecord>> List = Table.IsValid() ? Table->GetList() : nullptr;
    const TSharedPtr<const FCkUiRecord> Row = Collection->FindRecord(TEXT("one")); if (!TestTrue(TEXT("Table row realizes"), List.IsValid() && Row.IsValid())) { return false; }
    List->RequestScrollIntoView(Row); Tick(Slate);
    const TSharedPtr<ITableRow> NativeRow = List->WidgetFromItem(Row); const TSharedPtr<SCkFlexText> Text = NativeRow.IsValid() ? FindFlexText(NativeRow->AsWidget()) : nullptr;
    if (!TestTrue(TEXT("Generated cell has flex text metadata"), Text.IsValid())) { return false; }
    TestTrue(TEXT("Generated cell reads typed color"), Text->GetColorAndOpacity().GetSpecifiedColor().Equals(FLinearColor::Red));
    const TSharedPtr<IToolTip> InitialToolTip = Text->GetToolTip();
    const TSharedPtr<SWidget> InitialToolTipContent = InitialToolTip.IsValid() ? TSharedPtr<SWidget>(InitialToolTip->GetContentWidget()) : nullptr;
    const TSharedPtr<STextBlock> InitialToolTipText = InitialToolTipContent.IsValid() ? FindPlainText(InitialToolTipContent.ToSharedRef()) : nullptr;
    TestTrue(TEXT("Generated cell exposes typed tooltip through Slate tooltip widget"), InitialToolTipText.IsValid() && InitialToolTipText->GetText().ToString() == TEXT("First detail"));
    const TSharedPtr<ITableRow> OriginalRow = NativeRow;
    if (!TestTrue(TEXT("Updated metadata records commit"), Collection->TrySetRecords({Record(TEXT("Updated"), FLinearColor::Green, TEXT("Updated detail"))}).Succeeded)) { return false; } Tick(Slate);
    const TSharedPtr<ITableRow> UpdatedRow = List->WidgetFromItem(Collection->FindRecord(TEXT("one"))); const TSharedPtr<SCkFlexText> UpdatedText = UpdatedRow.IsValid() ? FindFlexText(UpdatedRow->AsWidget()) : nullptr;
    TestTrue(TEXT("Metadata update preserves native row"), UpdatedRow.IsValid() && UpdatedRow == OriginalRow);
    TestTrue(TEXT("Generated cell text and color update live"), UpdatedText.IsValid() && UpdatedText->GetText().ToString() == TEXT("Updated") && UpdatedText->GetColorAndOpacity().GetSpecifiedColor().Equals(FLinearColor::Green));
    const TSharedPtr<IToolTip> UpdatedToolTip = UpdatedText.IsValid() ? UpdatedText->GetToolTip() : nullptr;
    const TSharedPtr<SWidget> UpdatedToolTipContent = UpdatedToolTip.IsValid() ? TSharedPtr<SWidget>(UpdatedToolTip->GetContentWidget()) : nullptr;
    const TSharedPtr<STextBlock> UpdatedToolTipText = UpdatedToolTipContent.IsValid() ? FindPlainText(UpdatedToolTipContent.ToSharedRef()) : nullptr;
    TestTrue(TEXT("Generated cell tooltip updates live"), UpdatedToolTipText.IsValid() && UpdatedToolTipText->GetText().ToString() == TEXT("Updated detail"));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiTextMetadata_Validation,
    "Ck.UiAuthoring.TextMetadata.Validation",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiTextMetadata_Validation::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_text_metadata;
    auto Document = FCkUiDocument{};
    const FString Baseline = TEXT("<ui version=\"1\"><region name=\"main\"><text id=\"ok\" tooltip=\"literal\">Ok</text></region></ui>");
    if (!TestTrue(TEXT("Metadata validation baseline loads"), FCkUiDocumentParser::TryParse(Baseline, TEXT(".x { color: #ffffff; }"), {}, Document, TEXT("UiTextMetadata")).Succeeded)) { return false; }
    const auto Reject = [this, &Document](const FString& InName, const FString& InMarkup)
    { const FCkUiLoadResult Result = FCkUiDocumentParser::TryParse(InMarkup, TEXT(".x { color: #ffffff; }"), {}, Document, TEXT("UiTextMetadata")); TestFalse(*InName, Result.Succeeded); TestTrue(*(InName + TEXT(" reports error")), !Result.Errors.IsEmpty()); TestTrue(*(InName + TEXT(" preserves baseline")), Document.Regions.Contains(TEXT("main")) && Document.Regions.FindRef(TEXT("main")).Id == TEXT("ok")); };
    Reject(TEXT("Literal color syntax rejects as unsupported"), TEXT("<ui version=\"1\"><region name=\"main\"><text id=\"x\" color=\"#ffffff\">X</text></region></ui>"));
    const auto TableReject = [this](const FString& InName, const FString& InCell)
    {
        auto Out = FCkUiDocument{};
        const FString Markup = TableMarkup().Replace(TEXT("<text id=\"cell\" bind-field=\"label\" color-field=\"tint\" tooltip-field=\"detail\"/>"), *InCell);
        const FCkUiLoadResult Result = FCkUiDocumentParser::TryParse(Markup, TEXT(".fill { flex-grow: 1; }"), {}, Out, TEXT("UiTextMetadata"));
        TestFalse(*InName, Result.Succeeded); TestTrue(*(InName + TEXT(" reports error")), !Result.Errors.IsEmpty());
    };
    TableReject(TEXT("Color bind and field conflict rejects"), TEXT("<text id=\"cell\" bind-field=\"label\" color-bind=\"tone\" color-field=\"tint\"/>"));
    TableReject(TEXT("Color field and bind conflict rejects"), TEXT("<text id=\"cell\" bind-field=\"label\" color-field=\"tint\" color-bind=\"tone\"/>"));
    TableReject(TEXT("Tooltip literal bind field conflict rejects"), TEXT("<text id=\"cell\" bind-field=\"label\" tooltip=\"x\" tooltip-bind=\"tip\" tooltip-field=\"detail\"/>"));
    TableReject(TEXT("Tooltip field bind literal conflict rejects"), TEXT("<text id=\"cell\" bind-field=\"label\" tooltip-field=\"detail\" tooltip-bind=\"tip\" tooltip=\"x\"/>"));
    TSharedPtr<FCkUiCollection> Collection;
    if (!TestTrue(TEXT("Production validation collection creates"), FCkUiCollection::TryCreate(Schema(), Collection).Succeeded) || !Collection.IsValid()) { return false; }
    auto Data = FCkUiView::FDataBindings{}; Data.Collections.Add(TEXT("records"), Collection);
    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, MoveTemp(Data)); View->GetRegion(TEXT("main"));
    if (!TestTrue(TEXT("Production table validation baseline loads"), View->TryReload(TableMarkup(), TEXT(".fill { flex-grow: 1; }"), TEXT("UiTextMetadataProduction")).Succeeded)) { return false; }
    const int64 Revision = View->GetRevision();
    const auto RejectView = [this, &View, Revision](const FString& InName, const FString& InMarkup)
    { const FCkUiLoadResult Result = View->TryReload(InMarkup, TEXT(".fill { flex-grow: 1; }"), TEXT("UiTextMetadataProduction")); TestFalse(*InName, Result.Succeeded); TestTrue(*(InName + TEXT(" reports error")), !Result.Errors.IsEmpty()); TestEqual(*(InName + TEXT(" preserves view revision")), View->GetRevision(), Revision); };
    RejectView(TEXT("Wrong color field type rejects in production view"), TableMarkup().Replace(TEXT("color-field=\"tint\""), TEXT("color-field=\"label\"")));
    RejectView(TEXT("Wrong tooltip field type rejects in production view"), TableMarkup().Replace(TEXT("tooltip-field=\"detail\""), TEXT("tooltip-field=\"tint\"")));
    RejectView(TEXT("Missing color field rejects in production view"), TableMarkup().Replace(TEXT("color-field=\"tint\""), TEXT("color-field=\"missing\"")));
    auto MissingData = FCkUiView::FDataBindings{}; const TSharedRef<FCkUiView> MissingView = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, MoveTemp(MissingData)); MissingView->GetRegion(TEXT("main"));
    const FCkUiLoadResult MissingGlobal = MissingView->TryReload(TEXT("<ui version=\"1\"><region name=\"main\"><text id=\"global\" color-bind=\"color\" tooltip-bind=\"tip\">Global</text></region></ui>"), TEXT(".x { color: #ffffff; }"), TEXT("UiTextMissingGlobal"));
    TestFalse(TEXT("Missing global color and tooltip bindings reject"), MissingGlobal.Succeeded);
    TestTrue(TEXT("Missing global bindings report failure"), !MissingGlobal.Errors.IsEmpty());
    return true;
}

#endif
