#include "CkSlateLayout/SCkUiSurface.h"
#include "CkSlateLayout/SCkUiTable.h"
#include "Framework/Application/SlateApplication.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "Layout/WidgetPath.h"
#include "Misc/AutomationTest.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/SWindow.h"

#if WITH_DEV_AUTOMATION_TESTS
namespace ck_tests_ui_table_sort
{
    struct FWindowScope
    {
        FSlateApplication& Slate;
        TSharedPtr<SWindow> Window;
        ~FWindowScope() { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } }
    };

    auto Tick(FSlateApplication& Slate) -> void { Slate.PumpMessages(); Slate.Tick(); Slate.Tick(); }

    auto FindHeaderButton(const TSharedRef<SWidget>& Root, bool InHeader = false) -> TSharedPtr<SButton>
    {
        InHeader |= Root->GetTypeAsString() == TEXT("STableColumnHeader");
        if (InHeader && Root->GetTypeAsString() == TEXT("SButton")) { return StaticCastSharedRef<SButton>(Root); }
        FChildren* Children = Root->GetChildren();
        if (Children == nullptr) { return {}; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        {
            const TSharedPtr<SButton> Found = FindHeaderButton(Children->GetChildAt(Index), InHeader);
            if (Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto Record(const TCHAR* Key, float Rank) -> FCkUiRecordData
    {
        FCkUiRecordData Result;
        Result.Key = Key;
        Result.Fields.Add(TEXT("name"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(Key)});
        Result.Fields.Add(TEXT("rank"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Number, .Number = Rank});
        return Result;
    }

    auto Keys(const TSharedPtr<SListView<SCkUiTable::FRecord>>& List) -> FString
    {
        FString Result;
        for (const auto& Item : List->GetItems()) { Result += Item->GetKey() + TEXT(","); }
        return Result;
    }

    auto Click(const TSharedRef<SButton>& Button) -> bool
    {
        const FGeometry Geometry = Button->GetCachedGeometry();
        const FVector2D Position = Geometry.GetAbsolutePosition() + Geometry.GetAbsoluteSize() * 0.5f;
        const FPointerEvent Down{0, Position, Position, TSet<FKey>{EKeys::LeftMouseButton}, EKeys::LeftMouseButton, 0, FModifierKeysState{}};
        const FPointerEvent Up{0, Position, Position, TSet<FKey>{}, EKeys::LeftMouseButton, 0, FModifierKeysState{}};
        FWidgetPath Path;
        auto& Slate = FSlateApplication::Get();
        if (!Slate.GeneratePathToWidgetUnchecked(Button, Path)) { return false; }
        Button->OnMouseEnter(Geometry, Down);
        const FReply Pressed = Button->OnMouseButtonDown(Geometry, Down);
        Slate.ProcessReply(Path, Pressed, &Path, &Down);
        const FReply Released = Button->OnMouseButtonUp(Geometry, Up);
        Slate.ProcessReply(Path, Released, &Path, &Up);
        Button->OnMouseLeave(Up);
        return Pressed.IsEventHandled() && Released.IsEventHandled();
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiTableSort_Runtime, "Ck.UiAuthoring.Table.HeaderSort",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiTableSort_Runtime::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_table_sort;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Slate is required.")); return false; }
    TSharedPtr<FCkUiCollection> Collection;
    if (!TestTrue(TEXT("Collection creates"), FCkUiCollection::TryCreate({
        {TEXT("name"), ECkUiFieldKind::Text}, {TEXT("rank"), ECkUiFieldKind::Number}}, Collection).Succeeded)) { return false; }
    FCkUiView::FDataBindings Data;
    Data.Collections.Add(TEXT("rows"), Collection);
    const auto View = FCkUiView::Create({}, {}, {}, {}, MoveTemp(Data));
    const auto Region = View->GetRegion(TEXT("main"));
    auto& Slate = FSlateApplication::Get();
    FWindowScope Scope{Slate};
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{640, 240})[Region];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);
    const FString Markup = TEXT("<ui version=\"1\"><region name=\"main\"><row id=\"root\"><table id=\"table\" class=\"fill\" bind=\"rows\"><table-column id=\"rank\" label=\"Rank\" sort-field=\"rank\"><text id=\"cell\" bind-field=\"name\"/></table-column></table><table id=\"other\" class=\"fill\" bind=\"rows\"><table-column id=\"otherRank\" label=\"Rank\" sort-field=\"rank\"><text id=\"otherCell\" bind-field=\"name\"/></table-column></table></row></region></ui>");
    if (!TestTrue(TEXT("Production tables load"), View->TryReload(Markup, TEXT(".fill { flex-grow: 1; }")).Succeeded)) { return false; }
    if (!TestTrue(TEXT("Rows commit"), Collection->TrySetRecords({Record(TEXT("a"), 2), Record(TEXT("b"), 1), Record(TEXT("c"), 1)}).Succeeded)) { return false; }
    Tick(Slate);
    const auto Table = View->GetTable(TEXT("table"));
    const auto Other = View->GetTable(TEXT("other"));
    if (!TestTrue(TEXT("Both tables exist"), Table.IsValid() && Other.IsValid())) { return false; }
    const auto List = Table->GetList();
    const auto OtherList = Other->GetList();
    if (!TestTrue(TEXT("Both native lists exist"), List.IsValid() && OtherList.IsValid())) { return false; }
    TestEqual(TEXT("Input order is default"), Keys(List), FString(TEXT("a,b,c,")));
    const auto OriginalA = Collection->FindRecord(TEXT("a"));
    const auto Button = FindHeaderButton(Table.ToSharedRef());
    if (!TestTrue(TEXT("Generated column contains a header button"), Button.IsValid())) { return false; }
    TestTrue(TEXT("Header handles first mouse click"), Click(Button.ToSharedRef()));
    Tick(Slate);
    TestEqual(TEXT("Ascending sort uses stable ties"), Keys(List), FString(TEXT("b,c,a,")));
    TestEqual(TEXT("Other view keeps input order"), Keys(OtherList), FString(TEXT("a,b,c,")));
    TestTrue(TEXT("Header handles second mouse click"), Click(Button.ToSharedRef()));
    Tick(Slate);
    TestEqual(TEXT("Second click sorts descending"), Keys(List), FString(TEXT("a,b,c,")));
    if (!TestTrue(TEXT("Changed values publish"), Collection->TrySetRecords({Record(TEXT("a"), 0), Record(TEXT("b"), 3), Record(TEXT("c"), 2)}).Succeeded)) { return false; }
    Tick(Slate);
    TestEqual(TEXT("Refresh reranks the sorted view"), Keys(List), FString(TEXT("b,c,a,")));
    TestEqual(TEXT("Refresh leaves other view in input order"), Keys(OtherList), FString(TEXT("a,b,c,")));
    TestTrue(TEXT("Sorting and refresh preserve shared record identity"), Collection->FindRecord(TEXT("a")) == OriginalA);
    return true;
}
#endif
