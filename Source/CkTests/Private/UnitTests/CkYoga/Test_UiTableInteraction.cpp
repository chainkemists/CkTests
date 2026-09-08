#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/CkFlexText.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkSlateLayout/SCkUiTable.h"

#include "Framework/Application/SlateApplication.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "Misc/AutomationTest.h"
#include "Widgets/SWindow.h"
#include "Widgets/Views/ITableRow.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_table_interaction
{
    auto MakeSchema() -> TArray<FCkUiFieldSchema>
    {
        return {{TEXT("label"), ECkUiFieldKind::Text}, {TEXT("visible"), ECkUiFieldKind::Bool}};
    }

    auto MakeRecord(const int32 InIndex, const FString& InSuffix = TEXT("")) -> FCkUiRecordData
    {
        auto Record = FCkUiRecordData{};
        Record.Key = FString::Printf(TEXT("row-%d"), InIndex);
        Record.Fields.Add(TEXT("label"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(FString::Printf(TEXT("Row %d%s"), InIndex, *InSuffix))});
        Record.Fields.Add(TEXT("visible"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Bool, .Bool = true});
        return Record;
    }

    auto MakeRecords(const int32 InCount, const FString& InSuffix = TEXT("")) -> TArray<FCkUiRecordData>
    {
        auto Records = TArray<FCkUiRecordData>{};
        Records.Reserve(InCount);
        for (int32 Index = 0; Index < InCount; ++Index) { Records.Add(MakeRecord(Index, InSuffix)); }
        return Records;
    }

    auto Markup() -> FString
    {
        return TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"><table id=\"records\" class=\"fill\" bind=\"records\" filter-bind=\"filter\" selection-action=\"selected\" row-height=\"20\"><table-column id=\"name\" label=\"Name\" sort-field=\"label\"><text id=\"cell\" bind-field=\"label\" visible-field=\"visible\"/></table-column></table></column></region></ui>");
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

    auto FindCellText(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SCkFlexText>
    {
        if (InRoot->GetTypeAsString() == TEXT("SCkFlexText")) { return StaticCastSharedRef<SCkFlexText>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        if (Children == nullptr) { return nullptr; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SCkFlexText> Found = FindCellText(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid()) { return Found; }
        }
        return nullptr;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiTableInteraction_Runtime,
    "Ck.UiAuthoring.Table.InteractionVirtualizedRows",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiTableInteraction_Runtime::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_table_interaction;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Table interaction requires an initialized Slate application.")); return false; }
    TSharedPtr<FCkUiCollection> Collection;
    if (!TestTrue(TEXT("Table collection creates"), FCkUiCollection::TryCreate(MakeSchema(), Collection).Succeeded) || !Collection.IsValid()) { return false; }
    FString Filter;
    int32 SelectionNotifications = 0;
    auto Data = FCkUiView::FDataBindings{};
    Data.Collections.Add(TEXT("records"), Collection);
    Data.Text.Add(TEXT("filter"), TAttribute<FText>::CreateLambda([&Filter]() { return FText::FromString(Filter); }));
    Data.TableSelectionChanged.Add(TEXT("selected"), FOnCkUiTableSelectionChanged::CreateLambda([&SelectionNotifications](TOptional<FString>, ESelectInfo::Type) { ++SelectionNotifications; }));
    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, {}, {}, FSlateFontInfo{}, MoveTemp(Data));
    const TSharedRef<SWidget> Region = View->GetRegion(TEXT("main"));
    FSlateApplication& Slate = FSlateApplication::Get();
    FWindowScope Scope{Slate};
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{320.0f, 180.0f}).CreateTitleBar(false).HasCloseButton(false)[Region];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);
    if (!TestTrue(TEXT("Authored table loads"), View->TryReload(Markup(), TEXT(".fill { flex-grow: 1; }"), TEXT("UiTableInteraction")).Succeeded)) { return false; }
    Scope.Window->Resize(FVector2D{320.0f, 180.0f});

    for (const int32 Count : {0, 1, 12, 1000, 10000})
    {
        if (!TestTrue(*FString::Printf(TEXT("Collection accepts %d authored table rows"), Count), Collection->TrySetRecords(MakeRecords(Count)).Succeeded)) { return false; }
        TickSlate(Slate);
        const TSharedPtr<SCkUiTable> Table = View->GetTable(TEXT("records"));
        if (!TestTrue(TEXT("View exposes retained authored table"), Table.IsValid())) { return false; }
        TestEqual(*FString::Printf(TEXT("Authored table exposes %d visible rows"), Count), Table->GetVisibleRecordCount(), Count);
        if (Count > 0)
        {
            TestTrue(*FString::Printf(TEXT("%d-row table produces no cell error"), Count), Table->GetLastCellError().IsEmpty());
            TestTrue(*FString::Printf(TEXT("%d-row table generates visible rows"), Count), Table->GetLiveRowCount() > 0);
        }
        if (Count >= 1000)
        {
            const int32 Live = Table->GetLiveRowCount();
            TestTrue(*FString::Printf(TEXT("%d-row table generates a bounded live row set"), Count), Live > 0 && Live < 128);
        }
    }

    const TSharedPtr<SCkUiTable> Table = View->GetTable(TEXT("records"));
    const TSharedPtr<SListView<SCkUiTable::FRecord>> List = Table.IsValid() ? Table->GetList() : nullptr;
    const TSharedPtr<const FCkUiRecord> First = Collection->FindRecord(TEXT("row-0"));
    const TSharedPtr<const FCkUiRecord> Last = Collection->FindRecord(TEXT("row-9999"));
    if (!TestTrue(TEXT("List and on/offscreen records are available"), List.IsValid() && First.IsValid() && Last.IsValid())) { return false; }
    List->RequestScrollIntoView(Last);
    TickSlate(Slate);
    TestTrue(TEXT("Offscreen record is realized after native list scroll request"), List->WidgetFromItem(Last).IsValid());
    TestTrue(TEXT("Offscreen scroll remains virtualized"), Table->GetLiveRowCount() < 128);

    List->RequestScrollIntoView(First);
    TickSlate(Slate);
    const FGeometry ListGeometry = FGeometry::MakeRoot(FVector2D{320.0f, 180.0f}, FSlateLayoutTransform{});
    const TSet<FKey> PressedButtons{EKeys::LeftMouseButton};
    const FPointerEvent MouseDown{0, FVector2D{10.0f, 10.0f}, FVector2D{10.0f, 10.0f}, PressedButtons,
        EKeys::LeftMouseButton, 0.0f, FModifierKeysState{}};
    for (const int32 Index : {1, 2})
    {
        const TSharedPtr<const FCkUiRecord> Clicked = Collection->FindRecord(FString::Printf(TEXT("row-%d"), Index));
        const TSharedPtr<ITableRow> Generated = Clicked.IsValid() ? List->WidgetFromItem(Clicked) : nullptr;
        if (!TestTrue(*FString::Printf(TEXT("Distinct visible row %d has a generated native row"), Index), Generated.IsValid())) { return false; }
        const int32 EventsBefore = SelectionNotifications;
        Generated->AsWidget()->OnMouseButtonDown(ListGeometry, MouseDown);
        if (!TestTrue(TEXT("Held mouse-down selects generated row"), Table->GetSelectedKey().IsSet())) { return false; }
        TestEqual(TEXT("Held mouse-down selects correct stable key"), Table->GetSelectedKey().GetValue(), Clicked->GetKey());
        TestTrue(TEXT("Native list has exactly the held selected item"), List->GetSelectedItems().Num() == 1 && List->GetSelectedItems()[0] == Clicked);
        if (!TestTrue(TEXT("Same-key held selection refresh commits"), Collection->TrySetRecords(MakeRecords(10000, FString::Printf(TEXT(" held-%d"), Index))).Succeeded)) { return false; }
        TickSlate(Slate);
        TestTrue(TEXT("Held native selection remains after collection refresh"), Table->GetSelectedKey().IsSet() && Table->GetSelectedKey().GetValue() == Clicked->GetKey());
        const TSharedPtr<const FCkUiRecord> Refreshed = Collection->FindRecord(Clicked->GetKey());
        TestTrue(TEXT("Native selected item follows the stable selected key"), Refreshed.IsValid() && List->GetSelectedItems().Num() == 1 && List->GetSelectedItems()[0] == Refreshed);
        TestEqual(TEXT("Held refresh does not duplicate selection event"), SelectionNotifications, EventsBefore + 1);
        const TSharedPtr<ITableRow> RefreshedRow = Refreshed.IsValid() ? List->WidgetFromItem(Refreshed) : nullptr;
        const TSharedPtr<SCkFlexText> Cell = RefreshedRow.IsValid() ? FindCellText(RefreshedRow->AsWidget()) : nullptr;
        TestTrue(TEXT("Generated cell shows updated bound text after same-key refresh"), Cell.IsValid() && Cell->GetText().ToString() == FString::Printf(TEXT("Row %d held-%d"), Index, Index));
    }

    if (!TestTrue(TEXT("Selection API selects stable row"), Table->TrySelectKey(FString(TEXT("row-9999")), true))) { return false; }
    TickSlate(Slate);
    const int32 NotificationsAfterSelect = SelectionNotifications;
    Filter = TEXT("Row 0");
    TickSlate(Slate);
    TestFalse(TEXT("Filtering selected row clears selection"), Table->GetSelectedKey().IsSet());
    TestEqual(TEXT("Filtering selection emits exactly one clear notification"), SelectionNotifications, NotificationsAfterSelect + 1);

    Filter.Reset();
    List->RequestScrollIntoView(First);
    TickSlate(Slate);
    const TSharedPtr<ITableRow> FirstRow = List->WidgetFromItem(First);
    if (!TestTrue(TEXT("Stable-key row is realized before data update"), FirstRow.IsValid())) { return false; }
    if (!TestTrue(TEXT("Updated same-key records commit"), Collection->TrySetRecords(MakeRecords(10000, TEXT(" updated"))).Succeeded)) { return false; }
    TickSlate(Slate);
    const TSharedPtr<ITableRow> UpdatedFirstRow = List->WidgetFromItem(Collection->FindRecord(TEXT("row-0")));
    TestTrue(TEXT("Same-key data update preserves realized row widget"), UpdatedFirstRow.IsValid() && UpdatedFirstRow == FirstRow);
    return true;
}

#endif
