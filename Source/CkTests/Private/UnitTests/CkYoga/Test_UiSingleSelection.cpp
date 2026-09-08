#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/CkUiTreeCollection.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkSlateLayout/SCkUiTable.h"
#include "CkSlateLayout/SCkUiTree.h"

#include "Framework/Application/SlateApplication.h"
#include "Misc/AutomationTest.h"
#include "Styling/CoreStyle.h"
#include "Widgets/SWindow.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_single_selection
{
    auto Schema() -> TArray<FCkUiFieldSchema>
    {
        return {{TEXT("label"), ECkUiFieldKind::Text}};
    }

    auto Record(const TCHAR* InKey, const FString& InLabel) -> FCkUiRecordData
    {
        auto Result = FCkUiRecordData{};
        Result.Key = InKey;
        Result.Fields.Add(TEXT("label"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(InLabel)});
        return Result;
    }

    auto Node(const TCHAR* InKey, TOptional<FString> InParent, const FString& InLabel) -> FCkUiTreeNodeData
    {
        auto Result = FCkUiTreeNodeData{};
        Result.Key = InKey;
        Result.ParentKey = MoveTemp(InParent);
        Result.Fields.Add(TEXT("label"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(InLabel)});
        return Result;
    }

    auto Records(const TCHAR* InSuffix = TEXT("")) -> TArray<FCkUiRecordData>
    {
        return {Record(TEXT("root"), FString::Printf(TEXT("Root%s"), InSuffix)), Record(TEXT("child"), FString::Printf(TEXT("Child%s"), InSuffix)), Record(TEXT("other"), FString::Printf(TEXT("Other%s"), InSuffix))};
    }

    auto Nodes(const TCHAR* InSuffix = TEXT("")) -> TArray<FCkUiTreeNodeData>
    {
        return {Node(TEXT("root"), {}, FString::Printf(TEXT("Root%s"), InSuffix)), Node(TEXT("child"), FString(TEXT("root")), FString::Printf(TEXT("Child%s"), InSuffix)), Node(TEXT("other"), {}, FString::Printf(TEXT("Other%s"), InSuffix))};
    }

    auto Markup() -> FString
    {
        return TEXT("<ui version=\"1\"><region name=\"main\"><row id=\"root\"><table id=\"table\" class=\"fill\" bind=\"records\" row-height=\"20\"><table-column id=\"column\" label=\"Label\"><text id=\"table-label\" bind-field=\"label\"/></table-column></table><tree id=\"tree\" class=\"fill\" bind=\"nodes\" row-height=\"20\"><row id=\"tree-row\"><text id=\"tree-label\" bind-field=\"label\"/></row></tree></row></region></ui>");
    }

    auto Styles() -> FString { return TEXT(".fill { flex-grow: 1; }"); }

    auto Tick(FSlateApplication& InSlate) -> void
    {
        InSlate.PumpMessages();
        InSlate.Tick();
        InSlate.Tick();
    }

    struct FWindowScope final
    {
        explicit FWindowScope(FSlateApplication& InSlate) : Slate(InSlate) {}
        ~FWindowScope() { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } }

        FSlateApplication& Slate;
        TSharedPtr<SWindow> Window;
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiSingleSelection_Runtime,
    "Ck.UiAuthoring.Selection.NativeSingleSelection",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiSingleSelection_Runtime::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_single_selection;

    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Native single-selection test requires Slate.")); return false; }

    TSharedPtr<FCkUiCollection> Collection;
    TSharedPtr<FCkUiTreeCollection> Model;
    if (!TestTrue(TEXT("Table collection creates"), FCkUiCollection::TryCreate(Schema(), Collection).Succeeded)
        || !TestTrue(TEXT("Tree model creates"), FCkUiTreeCollection::TryCreate(Schema(), Model).Succeeded)
        || !TestTrue(TEXT("Table records publish"), Collection->TrySetRecords(Records()).Succeeded)
        || !TestTrue(TEXT("Tree nodes publish"), Model->TrySetNodes(Nodes()).Succeeded)) { return false; }

    auto Data = FCkUiView::FDataBindings{};
    Data.Collections.Add(TEXT("records"), Collection);
    Data.Trees.Add(TEXT("nodes"), Model);
    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, {}, {}, FCoreStyle::GetDefaultFontStyle(TEXT("Regular"), 12), MoveTemp(Data));
    const TSharedRef<SWidget> Region = View->GetRegion(TEXT("main"));
    FSlateApplication& Slate = FSlateApplication::Get();
    FWindowScope Scope{Slate};
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{640.0f, 260.0f}).CreateTitleBar(false).HasCloseButton(false)[Region];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);
    const FCkUiLoadResult Loaded = View->TryReload(Markup(), Styles(), TEXT("UiSingleSelection"));
    if (!TestTrue(TEXT("Production table and tree document loads"), Loaded.Succeeded))
    {
        for (const FString& Error : Loaded.Errors) { AddError(Error); }
        return false;
    }
    Tick(Slate);

    const TSharedPtr<SCkUiTable> Table = View->GetTable(TEXT("table"));
    const TSharedPtr<SCkUiTree> Tree = View->GetTree(TEXT("tree"));
    const TSharedPtr<SListView<SCkUiTable::FRecord>> NativeTable = Table.IsValid() ? Table->GetList() : nullptr;
    const TSharedPtr<STreeView<SCkUiTree::FNode>> NativeTree = Tree.IsValid() ? Tree->GetTree() : nullptr;
    if (!TestTrue(TEXT("Authored views expose native single-selection controls"), Table.IsValid() && Tree.IsValid() && NativeTable.IsValid() && NativeTree.IsValid())) { return false; }

    const SCkUiTree::FNode CollapsedChild = Model->FindNode(TEXT("child"));
    if (!TestTrue(TEXT("Collapsed descendant exists"), CollapsedChild.IsValid())
        || !TestTrue(TEXT("Programmatic selection accepts collapsed descendant"), Tree->TrySelectKey(FString(TEXT("child")), true))) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Collapsed descendant has exactly one native tree selection"), NativeTree->GetSelectedItems().Num() == 1 && NativeTree->GetSelectedItems()[0] == CollapsedChild);

    if (!TestTrue(TEXT("Expanding selected parent succeeds"), Tree->TrySetExpanded(TEXT("root"), true))) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Expansion retains exactly the selected child natively"), NativeTree->GetSelectedItems().Num() == 1 && NativeTree->GetSelectedItems()[0] == Model->FindNode(TEXT("child")));

    if (!TestTrue(TEXT("Tree successive selection changes to other"), Tree->TrySelectKey(FString(TEXT("other")), true))
        || !TestTrue(TEXT("Tree successive selection changes to root"), Tree->TrySelectKey(FString(TEXT("root")), true))) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Tree successive selections replace the native item"), NativeTree->GetSelectedItems().Num() == 1 && NativeTree->GetSelectedItems()[0] == Model->FindNode(TEXT("root")));
    TestTrue(TEXT("Same-key tree selection keeps one native item"), Tree->TrySelectKey(FString(TEXT("root")), true));
    TestTrue(TEXT("Same-key tree selection remains native-single"), NativeTree->GetSelectedItems().Num() == 1 && NativeTree->GetSelectedItems()[0] == Model->FindNode(TEXT("root")));

    if (!TestTrue(TEXT("Table selection chooses child"), Table->TrySelectKey(FString(TEXT("child")), true))
        || !TestTrue(TEXT("Table selection replaces child with other"), Table->TrySelectKey(FString(TEXT("other")), true))) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Table successive selections replace the native item"), NativeTable->GetSelectedItems().Num() == 1 && NativeTable->GetSelectedItems()[0] == Collection->FindRecord(TEXT("other")));
    TestTrue(TEXT("Same-key table selection keeps one native item"), Table->TrySelectKey(FString(TEXT("other")), true));
    TestTrue(TEXT("Same-key table selection remains native-single"), NativeTable->GetSelectedItems().Num() == 1 && NativeTable->GetSelectedItems()[0] == Collection->FindRecord(TEXT("other")));

    if (!TestTrue(TEXT("Table projection refresh succeeds"), Table->TryRefresh())) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Table refresh retains one selected current item"), NativeTable->GetSelectedItems().Num() == 1 && NativeTable->GetSelectedItems()[0] == Collection->FindRecord(TEXT("other")));

    const int64 ReloadRevision = View->GetRevision();
    if (!TestTrue(TEXT("Reload after expanded selection succeeds"), View->TryReload(Markup(), Styles() + TEXT(" .fill { padding: 1px; }"), TEXT("UiSingleSelectionReload")).Succeeded)) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Reload retains tree and table native single selections"), View->GetRevision() == ReloadRevision + 1
        && NativeTree->GetSelectedItems().Num() == 1 && NativeTree->GetSelectedItems()[0] == Model->FindNode(TEXT("root"))
        && NativeTable->GetSelectedItems().Num() == 1 && NativeTable->GetSelectedItems()[0] == Collection->FindRecord(TEXT("other")));

    if (!TestTrue(TEXT("Same-key table model refresh succeeds"), Collection->TrySetRecords(Records(TEXT(" refreshed"))).Succeeded)
        || !TestTrue(TEXT("Same-key tree model refresh succeeds"), Model->TrySetNodes(Nodes(TEXT(" refreshed"))).Succeeded)) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Model refresh retains one current selected table item"), NativeTable->GetSelectedItems().Num() == 1 && NativeTable->GetSelectedItems()[0] == Collection->FindRecord(TEXT("other")));
    TestTrue(TEXT("Model refresh retains one current selected tree item"), NativeTree->GetSelectedItems().Num() == 1 && NativeTree->GetSelectedItems()[0] == Model->FindNode(TEXT("root")));

    if (!TestTrue(TEXT("Table clear selection succeeds"), Table->TrySelectKey({}, true))
        || !TestTrue(TEXT("Tree clear selection succeeds"), Tree->TrySelectKey({}, true))) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Table clear leaves no native selected items"), NativeTable->GetSelectedItems().Num() == 0);
    TestTrue(TEXT("Tree clear leaves no native selected items"), NativeTree->GetSelectedItems().Num() == 0);
    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
