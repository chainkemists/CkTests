#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/CkUiTreeCollection.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Framework/Application/SlateApplication.h"
#include "HAL/PlatformProcess.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "Layout/Children.h"
#include "Layout/WidgetPath.h"
#include "Misc/AutomationTest.h"
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"
#include "Widgets/Views/ITableRow.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_context_menu_runtime
{
    auto Tick(FSlateApplication& InSlate) -> void
    {
        InSlate.PumpMessages();
        InSlate.Tick();
        InSlate.Tick();
    }

    auto Record(const FString& InKey, const FString& InName) -> FCkUiRecordData
    {
        FCkUiRecordData Result;
        Result.Key = InKey;
        Result.Fields.Add(TEXT("name"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(InName)});
        return Result;
    }

    auto Node(const FString& InKey, const FString& InName) -> FCkUiTreeNodeData
    {
        FCkUiTreeNodeData Result;
        Result.Key = InKey;
        Result.Fields.Add(TEXT("name"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(InName)});
        return Result;
    }

    auto Markup(const FString& InAction = TEXT("inspect"), const bool bTree = false) -> FString
    {
        const FString Collection = bTree
            ? TEXT("<tree id=\"tree\" bind=\"nodes\" context-menu=\"actions\" class=\"fill\"><row id=\"row\"><text id=\"name-cell\" bind-field=\"name\"/></row></tree>")
            : TEXT("<table id=\"table\" bind=\"records\" selection-action=\"redirect\" context-menu=\"actions\" class=\"fill\"><table-column id=\"name\" label=\"Name\"><text id=\"name-cell\" bind-field=\"name\"/></table-column></table>");
        return FString::Printf(TEXT("<ui version=\"1\"><menu id=\"actions\"><submenu key=\"more\" label=\"More\" menu=\"details\"/></menu><menu id=\"details\"><menu-item key=\"inspect\" label=\"Inspect\" action=\"%s\"/></menu><region name=\"main\"><column id=\"root\">%s</column></region></ui>"), *InAction, *Collection);
    }

    auto FindText(const TSharedRef<SWidget>& InRoot, const FString& InText) -> TSharedPtr<STextBlock>
    {
        if (InRoot->GetTypeAsString() == TEXT("STextBlock"))
        {
            const TSharedRef<STextBlock> Text = StaticCastSharedRef<STextBlock>(InRoot);
            if (Text->GetText().ToString() == InText) { return Text; }
        }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<STextBlock> Found = FindText(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InText); Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto FindMenuEntry(const TSharedRef<SWidget>& InRoot, const FString& InLabel) -> TSharedPtr<SWidget>
    {
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SWidget> Found = FindMenuEntry(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InLabel); Found.IsValid()) { return Found; }
        }
        if (InRoot->GetTypeAsString() == TEXT("SMenuEntryBlock") && FindText(InRoot, InLabel).IsValid()) { return InRoot; }
        return {};
    }

    auto FindVisibleMenuWindow(FSlateApplication& InSlate, const FString& InLabel) -> TSharedPtr<SWindow>
    {
        TArray<TSharedRef<SWindow>> Windows;
        InSlate.GetAllVisibleWindowsOrdered(Windows);
        for (const TSharedRef<SWindow>& Window : Windows)
        {
            if (FindMenuEntry(Window, InLabel).IsValid()) { return Window; }
        }
        return {};
    }

    auto WaitForMenu(FSlateApplication& InSlate, const FString& InLabel) -> TSharedPtr<SWindow>
    {
        for (int32 Attempt = 0; Attempt < 100; ++Attempt)
        {
            if (const TSharedPtr<SWindow> Window = FindVisibleMenuWindow(InSlate, InLabel); Window.IsValid())
            {
                const TSharedPtr<STextBlock> Text = FindText(Window.ToSharedRef(), InLabel);
                FWidgetPath Path;
                if (Text.IsValid() && Text->GetCachedGeometry().GetLocalSize().X > 0.0f
                    && Text->GetCachedGeometry().GetLocalSize().Y > 0.0f && InSlate.GeneratePathToWidgetUnchecked(Text.ToSharedRef(), Path)) { return Window; }
            }
            FPlatformProcess::Sleep(0.01f);
            Tick(InSlate);
        }
        return {};
    }

    auto MoveToText(FSlateApplication& InSlate, const TSharedRef<STextBlock>& InText) -> void
    {
        const FGeometry Geometry = InText->GetCachedGeometry();
        const FVector2D Position = Geometry.LocalToAbsolute(Geometry.GetLocalSize() * 0.5f);
        InSlate.SetCursorPos(Position);
        InSlate.ProcessMouseMoveEvent(FPointerEvent(0, FSlateApplication::CursorPointerIndex, Position, Position, TSet<FKey>{}, EKeys::Invalid, 0.0f, FModifierKeysState{}));
        Tick(InSlate);
    }

    auto ClickText(FSlateApplication& InSlate, const TSharedRef<SWindow>& InWindow, const TSharedRef<STextBlock>& InText) -> bool
    {
        if (!InWindow->GetNativeWindow().IsValid()) { return false; }
        const FGeometry Geometry = InText->GetCachedGeometry();
        const FVector2D Position = Geometry.LocalToAbsolute(Geometry.GetLocalSize() * 0.5f);
        InSlate.SetCursorPos(Position);
        InSlate.ProcessMouseMoveEvent(FPointerEvent(0, FSlateApplication::CursorPointerIndex, Position, Position, TSet<FKey>{}, EKeys::Invalid, 0.0f, FModifierKeysState{}));
        const bool Down = InSlate.ProcessMouseButtonDownEvent(InWindow->GetNativeWindow(), FPointerEvent(0, FSlateApplication::CursorPointerIndex, Position, Position, TSet<FKey>{EKeys::LeftMouseButton}, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{}));
        const bool Up = InSlate.ProcessMouseButtonUpEvent(FPointerEvent(0, FSlateApplication::CursorPointerIndex, Position, Position, TSet<FKey>{}, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{}));
        Tick(InSlate);
        return Down && Up;
    }

    struct FWindowScope final
    {
        explicit FWindowScope(FSlateApplication& InSlate) : Slate(InSlate), PreviousCursor(InSlate.GetCursorPos()) {}
        ~FWindowScope() { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } Slate.SetCursorPos(PreviousCursor); }
        FSlateApplication& Slate;
        FVector2D PreviousCursor;
        TSharedPtr<SWindow> Window;
    };

    struct FTableFixture final
    {
        explicit FTableFixture(FSlateApplication& InSlate) : Slate(InSlate), Scope(Slate) {}

        auto Load() -> bool
        {
            if (!FCkUiCollection::TryCreate({{TEXT("name"), ECkUiFieldKind::Text}}, Collection).Succeeded
                || !Collection->TrySetRecords({Record(TEXT("a"), TEXT("A")), Record(TEXT("b"), TEXT("B"))}).Succeeded) { return false; }
            FCkUiView::FDataBindings Data;
            Data.Collections.Add(TEXT("records"), Collection);
            Data.ContextActions.Add(TEXT("inspect"), FOnCkUiContextAction::CreateLambda([this](const FString& Key) { Dispatched.Add(Key); }));
            Data.TableSelectionChanged.Add(TEXT("redirect"), FOnCkUiTableSelectionChanged::CreateLambda([this](TOptional<FString> Key, ESelectInfo::Type)
            {
                if (Key.IsSet() && Key.GetValue() == TEXT("b")) { ++Redirects; if (Table.IsValid()) { Table->GetList()->SetSelection(Collection->FindRecord(TEXT("a")), ESelectInfo::OnKeyPress); } }
            }));
            View = FCkUiView::Create({}, {}, {}, {}, MoveTemp(Data));
            Region = View->GetRegion(TEXT("main"));
            Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D(420.0f, 240.0f)).CreateTitleBar(false).HasCloseButton(false)[Region.ToSharedRef()];
            Slate.AddWindow(Scope.Window.ToSharedRef(), true);
            if (!View->TryReload(Markup(), TEXT(".fill { flex-grow: 1; }"), TEXT("UiContextMenuTable")).Succeeded) { return false; }
            Tick(Slate);
            Table = View->GetTable(TEXT("table"));
            return Table.IsValid() && Table->GetList().IsValid();
        }

        auto OpenNestedForB(FString& OutDiagnostic) -> bool
        {
            OutDiagnostic.Reset();
            const TSharedPtr<const FCkUiRecord> B = Collection->FindRecord(TEXT("b"));
            const TSharedPtr<SListView<SCkUiTable::FRecord>> List = Table->GetList();
            if (!B.IsValid() || !List.IsValid())
            {
                OutDiagnostic = FString::Printf(TEXT("record-b=%s; list=%s; row=not-attempted; path=not-attempted; native-window=not-attempted"),
                    B.IsValid() ? TEXT("valid") : TEXT("missing"), List.IsValid() ? TEXT("valid") : TEXT("missing"));
                return false;
            }
            List->RequestScrollIntoView(B); Tick(Slate);
            const TSharedPtr<ITableRow> Row = List->WidgetFromItem(B);
            if (!Row.IsValid())
            {
                OutDiagnostic = TEXT("record-b=valid; list=valid; row=missing; path=not-attempted; native-window=not-attempted");
                return false;
            }
            const FGeometry Geometry = Row->AsWidget()->GetCachedGeometry();
            const FVector2D Position = Geometry.LocalToAbsolute(Geometry.GetLocalSize() * 0.5f);
            FWidgetPath Path;
            const bool bGeometryValid = Geometry.GetLocalSize().X > 0.0f && Geometry.GetLocalSize().Y > 0.0f && Geometry.IsUnderLocation(Position);
            if (!bGeometryValid)
            {
                OutDiagnostic = FString::Printf(TEXT("record-b=valid; list=valid; row=valid; geometry=%s; path=not-attempted; native-window=not-attempted"),
                    *Geometry.GetLocalSize().ToString());
                return false;
            }
            if (!Slate.GeneratePathToWidgetUnchecked(Row->AsWidget(), Path))
            {
                OutDiagnostic = TEXT("record-b=valid; list=valid; row=valid; path=missing; native-window=not-attempted");
                return false;
            }
            const TSharedPtr<SWindow> RowWindow = Path.GetWindow();
            if (!RowWindow.IsValid() || !RowWindow->GetNativeWindow().IsValid())
            {
                OutDiagnostic = FString::Printf(TEXT("record-b=valid; list=valid; row=valid; path=valid; window=%s; native-window=%s"),
                    RowWindow.IsValid() ? TEXT("valid") : TEXT("missing"),
                    RowWindow.IsValid() && RowWindow->GetNativeWindow().IsValid() ? TEXT("valid") : TEXT("missing"));
                return false;
            }
            Slate.SetCursorPos(Position);
            Slate.ProcessMouseMoveEvent(FPointerEvent(0, FSlateApplication::CursorPointerIndex, Position, Position, TSet<FKey>{}, EKeys::Invalid, 0.0f, FModifierKeysState{}));
            const bool Down = Slate.ProcessMouseButtonDownEvent(RowWindow->GetNativeWindow(), FPointerEvent(0, FSlateApplication::CursorPointerIndex, Position, Position, TSet<FKey>{EKeys::RightMouseButton}, EKeys::RightMouseButton, 0.0f, FModifierKeysState{}));
            const bool Up = Slate.ProcessMouseButtonUpEvent(FPointerEvent(0, FSlateApplication::CursorPointerIndex, Position, Position, TSet<FKey>{}, EKeys::RightMouseButton, 0.0f, FModifierKeysState{}));
            Tick(Slate);
            RootMenu = WaitForMenu(Slate, TEXT("More"));
            if (!Down || !Up || !RootMenu.IsValid())
            {
                OutDiagnostic = FString::Printf(TEXT("record-b=valid; list=valid; row=valid; path=valid; window=valid; native-window=valid; right-down=%s; right-up=%s; root-more-wait=%s"),
                    Down ? TEXT("handled") : TEXT("unhandled"), Up ? TEXT("handled") : TEXT("unhandled"), RootMenu.IsValid() ? TEXT("ready") : TEXT("timed-out"));
                return false;
            }
            const TSharedPtr<STextBlock> More = FindText(RootMenu.ToSharedRef(), TEXT("More"));
            if (!More.IsValid())
            {
                OutDiagnostic = FString::Printf(TEXT("record-b=valid; list=valid; row=valid; path=valid; window=valid; native-window=valid; right-down=%s; right-up=%s; root-more-wait=ready; root-more-entry=missing"),
                    Down ? TEXT("handled") : TEXT("unhandled"), Up ? TEXT("handled") : TEXT("unhandled"));
                return false;
            }
            MoveToText(Slate, More.ToSharedRef());
            NestedMenu = WaitForMenu(Slate, TEXT("Inspect"));
            const bool bNestedEntryValid = NestedMenu.IsValid() && FindMenuEntry(NestedMenu.ToSharedRef(), TEXT("Inspect")).IsValid();
            OutDiagnostic = FString::Printf(TEXT("record-b=valid; list=valid; row=valid; path=valid; window=valid; native-window=valid; right-down=%s; right-up=%s; root-more-wait=ready; root-more-entry=valid; nested-inspect-wait=%s; nested-inspect-entry=%s"),
                Down ? TEXT("handled") : TEXT("unhandled"), Up ? TEXT("handled") : TEXT("unhandled"),
                NestedMenu.IsValid() ? TEXT("ready") : TEXT("timed-out"), bNestedEntryValid ? TEXT("valid") : TEXT("missing"));
            return bNestedEntryValid;
        }

        FSlateApplication& Slate;
        TSharedPtr<FCkUiCollection> Collection;
        TSharedPtr<FCkUiView> View;
        TSharedPtr<SWidget> Region;
        TSharedPtr<SCkUiTable> Table;
        TSharedPtr<SWindow> RootMenu;
        TSharedPtr<SWindow> NestedMenu;
        TArray<FString> Dispatched;
        int32 Redirects = 0;
        FWindowScope Scope;
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiContextMenu_Runtime,
    "Ck.UiAuthoring.ContextMenus.NativeRuntime",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiContextMenu_Runtime::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_context_menu_runtime;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Context menu runtime test requires Slate.")); return false; }
    FSlateApplication& Slate = FSlateApplication::Get();
    FTableFixture Fixture(Slate);
    const auto OpenNestedForB = [this, &Fixture](const FString& InTestName) -> bool
    {
        FString Diagnostic;
        const bool bOpened = Fixture.OpenNestedForB(Diagnostic);
        AddInfo(FString::Printf(TEXT("%s: %s"), *InTestName, *Diagnostic));
        return TestTrue(*InTestName, bOpened);
    };
    if (!TestTrue(TEXT("Context menu table fixture loads"), Fixture.Load())
        || !OpenNestedForB(TEXT("Real right-click reaches B's live table row and opens nested context menu"))) { return false; }
    const TOptional<FString> RedirectedSelection = Fixture.Table->GetSelectedKey();
    TestTrue(TEXT("Selection callback redirected native selection to A"), Fixture.Redirects > 0 && RedirectedSelection.IsSet()
        && RedirectedSelection.GetValue() == TEXT("a"));
    const TSharedPtr<STextBlock> Inspect = FindText(Fixture.NestedMenu.ToSharedRef(), TEXT("Inspect"));
    if (!TestTrue(TEXT("Deepest nested context menu entry is mounted"), Inspect.IsValid())) { return false; }
    TestTrue(TEXT("Nested Inspect receives real Slate input"), ClickText(Slate, Fixture.NestedMenu.ToSharedRef(), Inspect.ToSharedRef()));
    TestTrue(TEXT("Context action receives right-clicked B, not redirected selection A"), Fixture.Dispatched.Num() == 1
        && Fixture.Dispatched[0] == TEXT("b"));

    if (!OpenNestedForB(TEXT("Context menu reopens before removed-record test"))) { return false; }
    const TSharedPtr<SWindow> RemovedWindow = Fixture.NestedMenu;
    const TSharedPtr<STextBlock> RemovedInspect = FindText(RemovedWindow.ToSharedRef(), TEXT("Inspect"));
    TestTrue(TEXT("Removing target record succeeds"), Fixture.Collection->TrySetRecords({Record(TEXT("a"), TEXT("A"))}).Succeeded);
    Tick(Slate);
    TestFalse(TEXT("Removing the context target closes only its popup"), FindVisibleMenuWindow(Slate, TEXT("Inspect")).IsValid());
    if (RemovedInspect.IsValid()) { ClickText(Slate, RemovedWindow.ToSharedRef(), RemovedInspect.ToSharedRef()); }
    TestEqual(TEXT("Removed context target cannot dispatch stale action"), Fixture.Dispatched.Num(), 1);

    TestTrue(TEXT("Restoring B succeeds"), Fixture.Collection->TrySetRecords({Record(TEXT("a"), TEXT("A")), Record(TEXT("b"), TEXT("B"))}).Succeeded);
    Tick(Slate);
    if (!OpenNestedForB(TEXT("Context menu reopens before replacement test"))) { return false; }
    const TSharedPtr<SWindow> ReplacedWindow = Fixture.NestedMenu;
    const TSharedPtr<STextBlock> ReplacedInspect = FindText(ReplacedWindow.ToSharedRef(), TEXT("Inspect"));
    const auto OriginalB = Fixture.Collection->FindRecord(TEXT("b"));
    TestTrue(TEXT("Removing B before same-key reinsertion succeeds"), Fixture.Collection->TrySetRecords({Record(TEXT("a"), TEXT("A"))}).Succeeded);
    TestTrue(TEXT("Same-key replacement publishes a new record"), Fixture.Collection->TrySetRecords({Record(TEXT("a"), TEXT("A")), Record(TEXT("b"), TEXT("Replacement"))}).Succeeded);
    TestTrue(TEXT("Same-key reinsertion has a distinct record identity"), Fixture.Collection->FindRecord(TEXT("b")) != OriginalB);
    Tick(Slate);
    if (ReplacedInspect.IsValid()) { ClickText(Slate, ReplacedWindow.ToSharedRef(), ReplacedInspect.ToSharedRef()); }
    TestEqual(TEXT("Same-key replacement cannot dispatch stale context action"), Fixture.Dispatched.Num(), 1);

    if (!OpenNestedForB(TEXT("Context menu reopens before rejected reload"))) { return false; }
    const int64 RejectedRevision = Fixture.View->GetRevision();
    const FCkUiLoadResult Rejected = Fixture.View->TryReload(Markup(TEXT("missing")), TEXT(""), TEXT("UiContextMenuRejected"));
    TestTrue(TEXT("Missing typed context action rejects before publication"), !Rejected.Succeeded && Fixture.View->GetRevision() == RejectedRevision
        && FindVisibleMenuWindow(Slate, TEXT("Inspect")).IsValid());
    const TSharedPtr<STextBlock> RejectedInspect = FindText(Fixture.NestedMenu.ToSharedRef(), TEXT("Inspect"));
    if (RejectedInspect.IsValid()) { ClickText(Slate, Fixture.NestedMenu.ToSharedRef(), RejectedInspect.ToSharedRef()); }
    TestTrue(TEXT("Rejected reload preserves committed context action"), Fixture.Dispatched.Num() == 2
        && Fixture.Dispatched[0] == TEXT("b") && Fixture.Dispatched[1] == TEXT("b"));

    if (!OpenNestedForB(TEXT("Context menu reopens before accepted reload"))) { return false; }
    const TSharedPtr<SWindow> AcceptedWindow = Fixture.NestedMenu;
    const TSharedPtr<STextBlock> AcceptedInspect = FindText(AcceptedWindow.ToSharedRef(), TEXT("Inspect"));
    TestTrue(TEXT("Accepted reload succeeds"), Fixture.View->TryReload(Markup(), TEXT(".fill { flex-grow: 1; } .root { padding: 1px; }"), TEXT("UiContextMenuAccepted")).Succeeded);
    Tick(Slate);
    TestFalse(TEXT("Accepted reload closes its owned context popup"), FindVisibleMenuWindow(Slate, TEXT("Inspect")).IsValid());
    if (AcceptedInspect.IsValid()) { ClickText(Slate, AcceptedWindow.ToSharedRef(), AcceptedInspect.ToSharedRef()); }
    TestEqual(TEXT("Accepted reload makes held popup input inert"), Fixture.Dispatched.Num(), 2);

    if (!OpenNestedForB(TEXT("Context menu reopens before owner release"))) { return false; }
    const TSharedPtr<SWindow> HeldWindow = Fixture.NestedMenu;
    const TSharedPtr<STextBlock> HeldInspect = FindText(HeldWindow.ToSharedRef(), TEXT("Inspect"));
    const TSharedPtr<SCkUiTable> HeldTable = Fixture.Table;
    Fixture.View.Reset();
    Tick(Slate);
    TestFalse(TEXT("Owner release closes held context popup"), FindVisibleMenuWindow(Slate, TEXT("Inspect")).IsValid());
    if (HeldInspect.IsValid()) { ClickText(Slate, HeldWindow.ToSharedRef(), HeldInspect.ToSharedRef()); }
    TestTrue(TEXT("Held table remains valid while released popup action is inert"), HeldTable.IsValid() && Fixture.Dispatched.Num() == 2);

    TSharedPtr<FCkUiTreeCollection> TreeCollection;
    if (!TestTrue(TEXT("Tree context model creates"), FCkUiTreeCollection::TryCreate({{TEXT("name"), ECkUiFieldKind::Text}}, TreeCollection).Succeeded)
        || !TestTrue(TEXT("Tree context node publishes"), TreeCollection->TrySetNodes({Node(TEXT("tree-key"), TEXT("Tree"))}).Succeeded)) { return false; }
    int32 TreeCalls = 0;
    FString TreeKey;
    auto TreeData = FCkUiView::FDataBindings{};
    TreeData.Trees.Add(TEXT("nodes"), TreeCollection);
    TreeData.ContextActions.Add(TEXT("inspect"), FOnCkUiContextAction::CreateLambda([&TreeCalls, &TreeKey](const FString& Key) { ++TreeCalls; TreeKey = Key; }));
    const TSharedRef<FCkUiView> TreeView = FCkUiView::Create({}, {}, {}, {}, MoveTemp(TreeData));
    const TSharedRef<SWidget> TreeRegion = TreeView->GetRegion(TEXT("main"));
    FWindowScope TreeScope(Slate);
    TreeScope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D(420.0f, 240.0f)).CreateTitleBar(false).HasCloseButton(false)[TreeRegion];
    Slate.AddWindow(TreeScope.Window.ToSharedRef(), true);
    if (!TestTrue(TEXT("Tree context menu document loads"), TreeView->TryReload(Markup(TEXT("inspect"), true), TEXT(".fill { flex-grow: 1; }"), TEXT("UiContextMenuTree")).Succeeded)) { return false; }
    Tick(Slate);
    const TSharedPtr<SCkUiTree> Tree = TreeView->GetTree(TEXT("tree"));
    const TSharedPtr<STreeView<SCkUiTree::FNode>> NativeTree = Tree.IsValid() ? Tree->GetTree() : nullptr;
    const TSharedPtr<const FCkUiTreeNode> TreeNode = TreeCollection->FindNode(TEXT("tree-key"));
    if (!TestTrue(TEXT("Tree exposes its native selection host"), NativeTree.IsValid() && TreeNode.IsValid())) { return false; }
    NativeTree->SetSelection(TreeNode, ESelectInfo::OnKeyPress);
    Slate.SetUserFocus(0, NativeTree.ToSharedRef(), EFocusCause::SetDirectly);
    const FModifierKeysState Shift{true, false, false, false, false, false, false, false, false};
    if (!TestTrue(TEXT("Native Shift+F10 opens tree menu"), Slate.ProcessKeyDownEvent(FKeyEvent{EKeys::F10, Shift, 0, false, 0, 0}))) { return false; }
    Tick(Slate);
    const TSharedPtr<SWindow> TreeRootMenu = WaitForMenu(Slate, TEXT("More"));
    const TSharedPtr<STextBlock> TreeMore = TreeRootMenu.IsValid() ? FindText(TreeRootMenu.ToSharedRef(), TEXT("More")) : nullptr;
    if (!TestTrue(TEXT("Tree context menu root is mounted after keyboard input"), TreeMore.IsValid())) { return false; }
    MoveToText(Slate, TreeMore.ToSharedRef());
    const TSharedPtr<SWindow> TreeNestedMenu = WaitForMenu(Slate, TEXT("Inspect"));
    const TSharedPtr<STextBlock> TreeInspect = TreeNestedMenu.IsValid() ? FindText(TreeNestedMenu.ToSharedRef(), TEXT("Inspect")) : nullptr;
    if (!TestTrue(TEXT("Tree context menu nested action is mounted"), TreeInspect.IsValid())) { return false; }
    TestTrue(TEXT("Native tree context-menu key dispatches typed record key"), ClickText(Slate, TreeNestedMenu.ToSharedRef(), TreeInspect.ToSharedRef())
        && TreeCalls == 1 && TreeKey == TEXT("tree-key"));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiContextMenu_Prevalidation,
    "Ck.UiAuthoring.ContextMenus.Prevalidation",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiContextMenu_Prevalidation::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_context_menu_runtime;
    TSharedPtr<FCkUiCollection> Collection;
    if (!TestTrue(TEXT("Prevalidation collection creates"), FCkUiCollection::TryCreate({{TEXT("name"), ECkUiFieldKind::Text}}, Collection).Succeeded)) { return false; }
    auto Data = FCkUiView::FDataBindings{};
    Data.Collections.Add(TEXT("records"), Collection);
    Data.TableSelectionChanged.Add(TEXT("redirect"), FOnCkUiTableSelectionChanged::CreateLambda([](TOptional<FString>, ESelectInfo::Type) {}));
    FCkUiView::FActions PlainActions;
    PlainActions.Add(TEXT("inspect"), FSimpleDelegate::CreateLambda([] {}));
    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, MoveTemp(PlainActions), {}, {}, MoveTemp(Data));
    View->GetRegion(TEXT("main"));
    const FCkUiLoadResult Missing = View->TryReload(Markup(), TEXT(""), TEXT("UiContextMenuMissingAction"));
    TestFalse(TEXT("Missing context action rejects before native table staging"), Missing.Succeeded);
    TestFalse(TEXT("Missing context action creates no table"), View->GetTable(TEXT("table")).IsValid());
    return true;
}

#endif
