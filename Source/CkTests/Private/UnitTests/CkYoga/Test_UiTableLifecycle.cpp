#include "CkSlateLayout/CkFlexText.h"
#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkSlateLayout/SCkUiTable.h"

#include "Framework/Application/SlateApplication.h"
#include "Misc/AutomationTest.h"
#include "Styling/SlateBrush.h"
#include "Widgets/Images/SImage.h"
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"
#include "Widgets/Views/ITableRow.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_table_lifecycle
{
    auto MakeSchema() -> TArray<FCkUiFieldSchema>
    {
        return {{TEXT("label"), ECkUiFieldKind::Text}, {TEXT("thumbnail"), ECkUiFieldKind::Image}};
    }

    auto MakeRecord(const TSharedPtr<const FSlateBrush>& InBrush) -> FCkUiRecordData
    {
        auto Record = FCkUiRecordData{};
        Record.Key = TEXT("life-row");
        Record.Fields.Add(TEXT("label"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(TEXT("Live resource"))});
        Record.Fields.Add(TEXT("thumbnail"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Image, .Image = InBrush});
        return Record;
    }

    auto InitialMarkup() -> FString
    {
        return TEXT("<ui version=\"1\"><region name=\"main\"><table id=\"resources\" bind=\"resources\" row-height=\"24\"><table-column id=\"name\" label=\"Initial name\" sort-field=\"label\"><column id=\"cell-root\"><text id=\"cell-label\" bind-field=\"label\"/><image id=\"cell-image\" bind-field=\"thumbnail\"/></column></table-column></table></region></ui>");
    }

    auto StructuralMarkup() -> FString
    {
        return TEXT("<ui version=\"1\"><region name=\"main\"><table id=\"resources\" bind=\"resources\" row-height=\"24\"><table-column id=\"display\" label=\"Reloaded name\" sort-field=\"label\"><text id=\"cell-reloaded\">Reloaded label</text></table-column><table-column id=\"preview\" label=\"Reloaded preview\"><image id=\"cell-image-reloaded\" bind-field=\"thumbnail\"/></table-column></table></region></ui>");
    }

    auto InvalidMarkup() -> FString
    {
        return TEXT("<ui version=\"1\"><region name=\"main\"><table id=\"resources\" bind=\"resources\"><table-column id=\"display\" label=\"Broken\" sort-field=\"missing\"><text id=\"broken-cell\">broken</text></table-column></table></region></ui>");
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

    auto FindFlexText(const TSharedRef<SWidget>& InRoot, const FString& InText = FString{}) -> TSharedPtr<SCkFlexText>
    {
        if (InRoot->GetTypeAsString() == TEXT("SCkFlexText"))
        {
            const TSharedPtr<SCkFlexText> Text = StaticCastSharedRef<SCkFlexText>(InRoot);
            if (InText.IsEmpty() || Text->GetText().ToString() == InText) { return Text; }
        }
        const FChildren* Children = InRoot->GetChildren();
        if (Children == nullptr) { return nullptr; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SCkFlexText> Found = FindFlexText(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InText); Found.IsValid()) { return Found; }
        }
        return nullptr;
    }

    auto FindImage(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SImage>
    {
        if (InRoot->GetTypeAsString() == TEXT("SImage")) { return StaticCastSharedRef<SImage>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        if (Children == nullptr) { return nullptr; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SImage> Found = FindImage(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid()) { return Found; }
        }
        return nullptr;
    }

    auto HasText(const TSharedRef<SWidget>& InRoot, const FString& InText) -> bool
    {
        if (InRoot->GetTypeAsString() == TEXT("STextBlock") && StaticCastSharedRef<STextBlock>(InRoot)->GetText().ToString() == InText) { return true; }
        const FChildren* Children = InRoot->GetChildren();
        if (Children == nullptr) { return false; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        { if (HasText(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InText)) { return true; } }
        return false;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiTableLifecycle_Runtime,
    "Ck.UiAuthoring.Table.LifecycleAndStructuralReload",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiTableLifecycle_Runtime::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_table_lifecycle;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Table lifecycle test requires an initialized Slate application.")); return false; }

    TSharedPtr<FCkUiCollection> Collection;
    if (!TestTrue(TEXT("Lifecycle collection creates"), FCkUiCollection::TryCreate(MakeSchema(), Collection).Succeeded) || !Collection.IsValid()) { return false; }

    TSharedPtr<FSlateBrush> Brush = MakeShared<FSlateBrush>();
    Brush->ImageSize = FVector2D{12.0f, 12.0f};
    const TWeakPtr<const FSlateBrush> WeakBrush = Brush;
    if (!TestTrue(TEXT("Lifecycle record publishes"), Collection->TrySetRecords({MakeRecord(Brush)}).Succeeded)) { return false; }

    FSlateApplication& Slate = FSlateApplication::Get();
    auto Data = FCkUiView::FDataBindings{};
    Data.Collections.Add(TEXT("resources"), Collection);
    auto View = TSharedPtr<FCkUiView>{FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, MoveTemp(Data))};
    TSharedPtr<SWidget> Region = View->GetRegion(TEXT("main"));
    TSharedPtr<SCkUiTable> Table;
    TSharedPtr<SListView<SCkUiTable::FRecord>> List;
    TSharedPtr<const FCkUiRecord> Record;
    TSharedPtr<ITableRow> Row;
    TSharedPtr<SImage> Image;

    {
        FWindowScope Scope{Slate};
        Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{360.0f, 180.0f})
            .CreateTitleBar(false).HasCloseButton(false)[Region.ToSharedRef()];
        Slate.AddWindow(Scope.Window.ToSharedRef(), true);
        if (!TestTrue(TEXT("Lifecycle authored table loads"), View->TryReload(InitialMarkup(), TEXT(""), TEXT("UiTableLifecycle")).Succeeded)) { return false; }
        Scope.Window->Resize(FVector2D{360.0f, 180.0f});
        TickSlate(Slate);

        Table = View->GetTable(TEXT("resources"));
        List = Table.IsValid() ? Table->GetList() : nullptr;
        Record = Collection->FindRecord(TEXT("life-row"));
        if (!TestTrue(TEXT("Initial production table and record exist"), Table.IsValid() && List.IsValid() && Record.IsValid())) { return false; }
        List->RequestScrollIntoView(Record);
        TickSlate(Slate);
        Row = List->WidgetFromItem(Record);
        if (!TestTrue(TEXT("Lifecycle record realizes a production row"), Row.IsValid())) { return false; }
        Image = FindImage(Row->AsWidget());
        if (!TestTrue(TEXT("Lifecycle row mounts the image field"), Image.IsValid())) { return false; }
        TestTrue(TEXT("Record-owned brush remains alive while row is mounted"), WeakBrush.IsValid());

        const int64 RevisionBeforeStructural = View->GetRevision();
        const FCkUiLoadResult StructuralResult = View->TryReload(StructuralMarkup(), TEXT(""), TEXT("UiTableLifecycleStructural"));
        if (!TestTrue(TEXT("Accepted structural column reload succeeds"), StructuralResult.Succeeded))
        {
            for (const FString& Error : StructuralResult.Errors) { AddError(Error); }
            return false;
        }
        TickSlate(Slate);
        TestTrue(TEXT("Accepted structural reload retains table identity"), View->GetTable(TEXT("resources")) == Table);
        TestTrue(TEXT("Accepted structural reload retains list identity"), Table->GetList() == List);
        TestEqual(TEXT("Accepted structural reload advances revision"), View->GetRevision(), RevisionBeforeStructural + 1);
        const TSharedPtr<ITableRow> StructuralRow = List->WidgetFromItem(Record);
        const TSharedPtr<SCkFlexText> StructuralText = StructuralRow.IsValid() ? FindFlexText(StructuralRow->AsWidget(), TEXT("Reloaded label")) : nullptr;
        TestTrue(TEXT("Structural reload replaces generated cell text"), StructuralText.IsValid() && StructuralText->GetText().ToString() == TEXT("Reloaded label"));
        TestTrue(TEXT("Structural reload replaces rendered header label"), HasText(Table.ToSharedRef(), TEXT("Reloaded name")));

        const int64 AcceptedRevision = View->GetRevision();
        const TSharedPtr<ITableRow> AcceptedRow = StructuralRow;
        const TSharedPtr<SCkFlexText> AcceptedText = StructuralText;
        const FCkUiLoadResult Rejected = View->TryReload(InvalidMarkup(), TEXT(""), TEXT("UiTableLifecycleRejected"));
        TestFalse(TEXT("Invalid structural reload rejects"), Rejected.Succeeded);
        TestEqual(TEXT("Rejected structural reload retains revision"), View->GetRevision(), AcceptedRevision);
        TestTrue(TEXT("Rejected structural reload retains table and list"), View->GetTable(TEXT("resources")) == Table && Table->GetList() == List);
        const TSharedPtr<ITableRow> RejectedRow = List->WidgetFromItem(Record);
        TestTrue(TEXT("Rejected structural reload retains the live row tree"), RejectedRow.IsValid() && RejectedRow == AcceptedRow);
        TestTrue(TEXT("Rejected structural reload retains rendered cell text"), AcceptedText.IsValid() && AcceptedText->GetText().ToString() == TEXT("Reloaded label"));

        Image = StructuralRow.IsValid() ? FindImage(StructuralRow->AsWidget()) : nullptr;
        if (!TestTrue(TEXT("Structural image cell remains mounted before removal"), Image.IsValid())) { return false; }
        Brush.Reset();
        TestTrue(TEXT("Brush survives external release while its record is retained"), WeakBrush.IsValid());
        if (!TestTrue(TEXT("Removing lifecycle record succeeds"), Collection->TrySetRecords({}).Succeeded)) { return false; }
        TickSlate(Slate);
    }

    const TWeakPtr<SWidget> WeakImage = Image;
    const TWeakPtr<ITableRow> WeakRow = Row;
    const TWeakPtr<const FCkUiRecord> WeakRecord = Record;
    Image.Reset();
    Row.Reset();
    Record.Reset();
    TickSlate(Slate);
    TestFalse(TEXT("Removed generated image widget releases"), WeakImage.IsValid());
    TestFalse(TEXT("Removed generated row releases"), WeakRow.IsValid());
    TestFalse(TEXT("Removed record releases"), WeakRecord.IsValid());
    TestFalse(TEXT("Removed record image brush releases"), WeakBrush.IsValid());

    const TWeakPtr<SCkUiTable> WeakTable = Table;
    const TWeakPtr<FCkUiView> WeakView = View;
    List.Reset();
    Table.Reset();
    Region.Reset();
    View.Reset();
    TickSlate(Slate);
    TestFalse(TEXT("View teardown releases retained table without a collection cycle"), WeakTable.IsValid());
    TestFalse(TEXT("View teardown releases table owner"), WeakView.IsValid());
    TestTrue(TEXT("Collection remains independently usable after table teardown"), Collection->TrySetRecords({}).Succeeded);
    return true;
}

#endif
