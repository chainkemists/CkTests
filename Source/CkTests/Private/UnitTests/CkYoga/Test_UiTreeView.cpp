#include "CkSlateLayout/CkUiTreeCollection.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkSlateLayout/SCkUiTree.h"

#include "Framework/Application/SlateApplication.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "Misc/AutomationTest.h"
#include "Styling/CoreStyle.h"
#include "Widgets/SWindow.h"
#include "Widgets/Views/ITableRow.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_tree_view
{
    struct FWindowScope final { explicit FWindowScope(FSlateApplication& InSlate) : Slate(InSlate) {} ~FWindowScope() { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } } FSlateApplication& Slate; TSharedPtr<SWindow> Window; };
    struct FHostKeyProbe final : TSharedFromThis<FHostKeyProbe>
    {
        explicit FHostKeyProbe(TSharedRef<int32> InCalls) : Calls(MoveTemp(InCalls)) {}
        auto OnKeyDown(const FGeometry&, const FKeyEvent&) -> FReply { ++*Calls; return FReply::Handled(); }
        TSharedRef<int32> Calls;
    };
    auto Tick(FSlateApplication& InSlate) -> void { InSlate.PumpMessages(); InSlate.Tick(); InSlate.Tick(); }
    auto Schema() -> TArray<FCkUiFieldSchema> { return {{TEXT("name"), ECkUiFieldKind::Text}, {TEXT("rank"), ECkUiFieldKind::Number}, {TEXT("visible"), ECkUiFieldKind::Bool}}; }
    auto Node(const FString& InKey, TOptional<FString> InParent = {}, const FString& InName = TEXT("node"), float InRank = 0.0f, const bool bVisible = true) -> FCkUiTreeNodeData
    { FCkUiTreeNodeData Result; Result.Key = InKey; Result.ParentKey = MoveTemp(InParent); Result.Fields.Add(TEXT("name"), FCkUiFieldValue{.Kind=ECkUiFieldKind::Text,.Text=FText::FromString(InName)}); Result.Fields.Add(TEXT("rank"), FCkUiFieldValue{.Kind=ECkUiFieldKind::Number,.Number=InRank}); Result.Fields.Add(TEXT("visible"), FCkUiFieldValue{.Kind=ECkUiFieldKind::Bool,.Bool=bVisible}); return Result; }
    auto Markup() -> FString { return TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"><tree id=\"tree\" class=\"fill\" bind=\"tree\" filter-bind=\"query\" selection-action=\"selected\" row-height=\"24\"><row id=\"cell\"><text id=\"name\" bind-field=\"name\"/></row></tree></column></region></ui>"); }
    auto ContextMarkup() -> FString { return TEXT("<ui version=\"1\"><menu id=\"tree-menu\"><menu-item key=\"inspect\" label=\"Inspect\" action=\"inspect\"/></menu><region name=\"main\"><column id=\"root\"><tree id=\"tree\" class=\"fill\" bind=\"tree\" filter-bind=\"query\" selection-action=\"selected\" context-menu=\"tree-menu\" row-height=\"24\"><row id=\"cell\"><text id=\"name\" bind-field=\"name\"/></row></tree></column></region></ui>"); }
    auto ProjectionMarkup() -> FString { return TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"><tree id=\"tree\" class=\"fill\" bind=\"tree\" projection-field=\"visible\" selectable=\"false\" expand-on-row-click=\"true\" row-height=\"24\"><row id=\"cell\"><text id=\"name\" bind-field=\"name\"/></row></tree></column></region></ui>"); }
    auto Styles() -> FString { return TEXT(".fill { flex-grow: 1; }"); }
    auto Key(const FKey InKey) -> FKeyEvent { return FKeyEvent(InKey, FModifierKeysState{}, 0, false, 0, 0); }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiTreeView_Runtime, "Ck.UiAuthoring.Tree.ViewRuntime", EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)
auto FCkUiTreeView_Runtime::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_tree_view;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Tree view runtime test requires Slate.")); return false; }
    TSharedPtr<FCkUiTreeCollection> Model;
    if (!TestTrue(TEXT("Tree model creates"), FCkUiTreeCollection::TryCreate(Schema(), Model).Succeeded) || !Model.IsValid()) { return false; }
    if (!TestTrue(TEXT("Initial hierarchy publishes"), Model->TrySetNodes({Node(TEXT("root"), {}, TEXT("Root")), Node(TEXT("child"), FString(TEXT("root")), TEXT("Child")), Node(TEXT("other"), {}, TEXT("Other"))}).Succeeded)) { return false; }
    FString Query;
    int32 SelectionEvents = 0;
    auto Data = FCkUiView::FDataBindings{};
    Data.Trees.Add(TEXT("tree"), Model);
    Data.Text.Add(TEXT("query"), TAttribute<FText>::CreateLambda([&Query]() { return FText::FromString(Query); }));
    Data.TreeSelectionChanged.Add(TEXT("selected"), FOnCkUiTreeSelectionChanged::CreateLambda([&SelectionEvents](TOptional<FString>, ESelectInfo::Type) { ++SelectionEvents; }));
    Data.ContextActions.Add(TEXT("inspect"), FOnCkUiContextAction::CreateLambda([](const FString&) {}));
    TSharedPtr<FCkUiView> View = FCkUiView::Create({}, {}, {}, FCoreStyle::GetDefaultFontStyle("Regular", 12), MoveTemp(Data));
    TSharedPtr<SWidget> Region = View->GetRegion(TEXT("main"));
    FSlateApplication& Slate = FSlateApplication::Get(); FWindowScope Scope{Slate};
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{640, 360}).CreateTitleBar(false).HasCloseButton(false)[Region.ToSharedRef()]; Slate.AddWindow(Scope.Window.ToSharedRef(), true);
    const FCkUiLoadResult Loaded = View->TryReload(Markup(), Styles(), TEXT("UiTreeView"));
    if (!TestTrue(TEXT("Production tree document loads"), Loaded.Succeeded)) { for (const FString& Error : Loaded.Errors) { AddError(Error); } return false; }
    Tick(Slate);
    TSharedPtr<SCkUiTree> Tree = View->GetTree(TEXT("tree"));
    TSharedPtr<STreeView<SCkUiTree::FNode>> NativeTree = Tree.IsValid() ? Tree->GetTree() : nullptr;
    if (!TestTrue(TEXT("Authored tree exposes retained native tree"), Tree.IsValid() && NativeTree.IsValid())) { return false; }
    TestTrue(TEXT("Initial tree cells generate without error"), Tree->GetLastCellError().IsEmpty());
    const SCkUiTree::FNode Root = Model->FindNode(TEXT("root"));
    if (!TestTrue(TEXT("Root node exists"), Root.IsValid())) { return false; }
    int32 HostKeyCalls = 0;
    Tree->SetHostKeyDownHandler(FOnKeyDown::CreateLambda([&HostKeyCalls](const FGeometry&, const FKeyEvent&) { ++HostKeyCalls; return FReply::Handled(); }));
    const FReply HostHandledReply = NativeTree->OnKeyDown(NativeTree->GetCachedGeometry(), Key(EKeys::F));
    TestTrue(TEXT("Native host key hook handles an otherwise unhandled tree key"), HostHandledReply.IsEventHandled() && HostKeyCalls == 1);
    Tree->SetHostKeyDownHandler(FOnKeyDown::CreateLambda([&HostKeyCalls](const FGeometry&, const FKeyEvent&) { ++HostKeyCalls; return FReply::Unhandled(); }));
    const FReply HostUnhandledReply = NativeTree->OnKeyDown(NativeTree->GetCachedGeometry(), Key(EKeys::F));
    TestTrue(TEXT("Unhandled native host key hook falls through to ordinary tree handling"), !HostUnhandledReply.IsEventHandled() && HostKeyCalls == 2);
    const TSharedRef<int32> ExpiredHostCalls = MakeShared<int32>(0);
    TSharedPtr<FHostKeyProbe> ExpiredHost = MakeShared<FHostKeyProbe>(ExpiredHostCalls);
    Tree->SetHostKeyDownHandler(FOnKeyDown::CreateSP(ExpiredHost.ToSharedRef(), &FHostKeyProbe::OnKeyDown));
    ExpiredHost.Reset();
    const FReply ExpiredHostReply = NativeTree->OnKeyDown(NativeTree->GetCachedGeometry(), Key(EKeys::F));
    TestTrue(TEXT("Expired native host owner leaves ordinary tree handling inert"), !ExpiredHostReply.IsEventHandled() && *ExpiredHostCalls == 0);
    Tree->SetHostKeyDownHandler({});
    TestFalse(TEXT("Unbound native host key hook leaves ordinary tree behavior intact"), NativeTree->OnKeyDown(NativeTree->GetCachedGeometry(), Key(EKeys::F)).IsEventHandled());
    Tree->SetHostKeyDownHandler(FOnKeyDown::CreateLambda([&HostKeyCalls](const FGeometry&, const FKeyEvent&) { ++HostKeyCalls; return FReply::Handled(); }));
    NativeTree->SetSelection(Root, ESelectInfo::OnKeyPress);
    Slate.SetKeyboardFocus(NativeTree.ToSharedRef(), EFocusCause::SetDirectly);
    const int32 HostCallsBeforeContextKey = HostKeyCalls;
    if (!TestTrue(TEXT("Context-menu reload succeeds before key precedence"), View->TryReload(ContextMarkup(), Styles(), TEXT("UiTreeViewContextKey")).Succeeded)) { return false; }
    Tick(Slate);
    const FModifierKeysState Shift{true, false, false, false, false, false, false, false, false};
    const FReply ContextReply = NativeTree->OnKeyDown(NativeTree->GetCachedGeometry(), FKeyEvent(EKeys::F10, Shift, 0, false, 0, 0));
    TestTrue(TEXT("Authored Shift+F10 context menu precedes the native host key hook"), ContextReply.IsEventHandled() && HostKeyCalls == HostCallsBeforeContextKey);
    Tree->ReleaseContextMenu();
    Tree->SetHostKeyDownHandler({});
    const FReply ExpandReply = NativeTree->OnKeyDown(NativeTree->GetCachedGeometry(), Key(EKeys::Right)); Tick(Slate);
    TestTrue(TEXT("Native keyboard right expands the selected authored root"), ExpandReply.IsEventHandled() && Tree->GetExpandedKeys().Contains(TEXT("root")) && Tree->GetSelectedKey().IsSet() && Tree->GetSelectedKey().GetValue() == TEXT("root"));
    const FReply CollapseReply = NativeTree->OnKeyDown(NativeTree->GetCachedGeometry(), Key(EKeys::Left)); Tick(Slate);
    TestTrue(TEXT("Native keyboard left collapses the selected authored root"), CollapseReply.IsEventHandled() && !Tree->GetExpandedKeys().Contains(TEXT("root")));
    Tree->SetHostKeyDownHandler(FOnKeyDown::CreateLambda([&HostKeyCalls](const FGeometry&, const FKeyEvent&) { ++HostKeyCalls; return FReply::Handled(); }));
    if (!TestTrue(TEXT("Public tree expansion restores root"), Tree->TrySetExpanded(TEXT("root"), true))) { return false; }
    Tick(Slate);
    if (!TestTrue(TEXT("Select unrelated root before hidden-selection filter"), Tree->TrySelectKey(FString(TEXT("other")), true))) { return false; }
    const int32 EventsBeforeFilter = SelectionEvents;
    Query = TEXT("Child"); Tick(Slate);
    TestTrue(TEXT("Filter retains matching child ancestors and clears unrelated selected root"), Tree->GetVisibleNodeCount() == 2 && !Tree->GetSelectedKey().IsSet() && SelectionEvents == EventsBeforeFilter + 1);
    Query.Reset(); Tick(Slate);
    TestTrue(TEXT("Clearing filter preserves user expansion"), Tree->GetExpandedKeys().Contains(TEXT("root")) && Tree->GetVisibleNodeCount() == 3);
    NativeTree->RequestScrollIntoView(Root); Tick(Slate);
    TSharedPtr<ITableRow> HeightRow = NativeTree->WidgetFromItem(Root);
    if (!TestTrue(TEXT("Root has a live native row before row-height reload"), HeightRow.IsValid())) { return false; }
    const int64 HeightRevision = View->GetRevision();
    if (!TestTrue(TEXT("Accepted row-height reload succeeds"), View->TryReload(Markup().Replace(TEXT("row-height=\"24\""), TEXT("row-height=\"36\"")), Styles(), TEXT("UiTreeViewRowHeight")).Succeeded)) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Accepted row-height reload updates the live native row geometry"), View->GetRevision() == HeightRevision + 1 && HeightRow->AsWidget()->GetCachedGeometry().GetLocalSize().Y >= 35.0f);

    auto Large = TArray<FCkUiTreeNodeData>{}; Large.Reserve(10000);
    for (int32 Index=1; Index<10000; ++Index) { Large.Add(Node(FString::Printf(TEXT("node-%05d"),Index), FString(TEXT("scale-root")), TEXT("Scale node"), static_cast<float>(Index))); }
    Large.Add(Node(TEXT("scale-root"), {}, TEXT("Scale root")));
    if (!TestTrue(TEXT("Ten-thousand shallow tree publishes"), Model->TrySetNodes(MoveTemp(Large)).Succeeded)) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Ten-thousand tree remains virtualized"), Tree->GetVisibleNodeCount() == 10000 && Tree->GetLiveRowCount() > 0 && Tree->GetLiveRowCount() < 128);
    const SCkUiTree::FNode ScaleRoot = Model->FindNode(TEXT("scale-root"));
    NativeTree->SetItemExpansion(ScaleRoot, true); Tick(Slate);
    const SCkUiTree::FNode Offscreen = Model->FindNode(TEXT("node-09000")); NativeTree->RequestScrollIntoView(Offscreen); Tick(Slate);
    TestTrue(TEXT("Offscreen tree node realizes through native tree scrolling"), NativeTree->WidgetFromItem(Offscreen).IsValid());

    if (!TestTrue(TEXT("Tree selects stable child before retained reload"), Tree->TrySelectKey(FString(TEXT("node-00001")), true))) { return false; }
    const TSet<FString> ExpandedBeforeReload = Tree->GetExpandedKeys(); const int64 Revision = View->GetRevision();
    TSharedPtr<SWidget> FocusedBeforeReload = Slate.GetUserFocusedWidget(0);
    if (!TestTrue(TEXT("Accepted tree reload succeeds"), View->TryReload(Markup(), Styles() + TEXT(" .fill { padding: 1px; }"), TEXT("UiTreeViewReload")).Succeeded)) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Accepted reload retains tree/native identity selection focus and expansion"), View->GetRevision() == Revision + 1 && View->GetTree(TEXT("tree")) == Tree && Tree->GetTree() == NativeTree && Slate.GetUserFocusedWidget(0) == FocusedBeforeReload && Tree->GetSelectedKey().IsSet() && Tree->GetSelectedKey().GetValue() == TEXT("node-00001") && Tree->GetExpandedKeys().Difference(ExpandedBeforeReload).Num() == 0 && ExpandedBeforeReload.Difference(Tree->GetExpandedKeys()).Num() == 0);
    const int32 HostCallsBeforeRetainedReload = HostKeyCalls;
    TestTrue(TEXT("Compatible reload retains the native host key hook"), NativeTree->OnKeyDown(NativeTree->GetCachedGeometry(), Key(EKeys::F)).IsEventHandled() && HostKeyCalls == HostCallsBeforeRetainedReload + 1);
    const int64 AcceptedRevision = View->GetRevision();
    const FString Invalid = Markup().Replace(TEXT("bind-field=\"name\""), TEXT("bind-field=\"rank\""));
    const FCkUiLoadResult Rejected = View->TryReload(Invalid, Styles(), TEXT("UiTreeViewInvalid"));
    TestFalse(TEXT("Wrong tree text field rejects before publication"), Rejected.Succeeded); TestTrue(TEXT("Rejected tree reload reports diagnostic"), !Rejected.Errors.IsEmpty());
    TestTrue(TEXT("Rejected tree reload retains tree identity and revision"), View->GetRevision() == AcceptedRevision && View->GetTree(TEXT("tree")) == Tree && Tree->GetTree() == NativeTree);
    const int32 HostCallsBeforeRejectedReload = HostKeyCalls;
    TestTrue(TEXT("Rejected reload retains the native host key hook"), NativeTree->OnKeyDown(NativeTree->GetCachedGeometry(), Key(EKeys::F)).IsEventHandled() && HostKeyCalls == HostCallsBeforeRejectedReload + 1);

    if (!TestTrue(TEXT("Projection hierarchy publishes"), Model->TrySetNodes({Node(TEXT("root"), {}, TEXT("Root")), Node(TEXT("child"), FString(TEXT("root")), TEXT("Child")), Node(TEXT("other"), {}, TEXT("Other"))}).Succeeded)) { return false; }
    Tick(Slate);
    const SCkUiTree::FNode ProjectionRoot = Model->FindNode(TEXT("root"));
    if (!TestTrue(TEXT("Projection root realizes before opt-in reload"), ProjectionRoot.IsValid() && Tree->TrySetExpanded(TEXT("root"), true))) { return false; }
    Tick(Slate);
    if (!TestTrue(TEXT("Projection root has a row"), NativeTree->WidgetFromItem(ProjectionRoot).IsValid())) { return false; }
    const int32 EventsBeforeProjection = SelectionEvents;
    if (!TestTrue(TEXT("Projection opt-in reload succeeds"), View->TryReload(ProjectionMarkup(), Styles(), TEXT("UiTreeViewProjection")).Succeeded)) { return false; }
    Tick(Slate);
    const TSharedPtr<ITableRow> ProjectionRow = NativeTree->WidgetFromItem(ProjectionRoot);
    if (!TestTrue(TEXT("Projection reload retains the realized root row"), ProjectionRow.IsValid())) { return false; }
    NativeTree->SetSelection(ProjectionRoot, ESelectInfo::OnMouseClick);
    Tick(Slate);
    TestTrue(TEXT("Non-selectable projection tree exposes no selection state or callback"), !Tree->GetSelectedKey().IsSet() && !Tree->TrySelectKey(FString(TEXT("root"))) && NativeTree->GetSelectedItems().Num() == 0 && SelectionEvents == EventsBeforeProjection);
    if (!TestTrue(TEXT("Projection hides false root while retaining visible root expansion"), Model->TrySetNodes({Node(TEXT("root"), {}, TEXT("Root")), Node(TEXT("child"), FString(TEXT("root")), TEXT("Child")), Node(TEXT("other"), {}, TEXT("Other"), 0.0f, false)}).Succeeded)) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Projection retains collection identity, realized row, and expansion without auto-expanding"), Model->FindNode(TEXT("root")) == ProjectionRoot && NativeTree->WidgetFromItem(ProjectionRoot) == ProjectionRow && Tree->GetVisibleNodeCount() == 2 && Tree->GetExpandedKeys().Contains(TEXT("root")) && Tree->GetTree() == NativeTree);
    const int64 ProjectionRevision = View->GetRevision();
    const TSet<FString> ProjectionExpansion = Tree->GetExpandedKeys();
    const FCkUiLoadResult RejectedProjection = View->TryReload(ProjectionMarkup().Replace(TEXT("bind-field=\"name\""), TEXT("bind-field=\"rank\"")), Styles(), TEXT("UiTreeViewProjectionInvalid"));
    TestFalse(TEXT("Invalid active projection reload rejects before publication"), RejectedProjection.Succeeded);
    TestTrue(TEXT("Rejected active projection retains revision identity projection selection and expansion"),
        View->GetRevision() == ProjectionRevision && View->GetTree(TEXT("tree")) == Tree && Tree->GetTree() == NativeTree
        && Tree->GetVisibleNodeCount() == 2 && !Tree->GetSelectedKey().IsSet() && NativeTree->GetSelectedItems().Num() == 0
        && Tree->GetExpandedKeys().Difference(ProjectionExpansion).Num() == 0 && ProjectionExpansion.Difference(Tree->GetExpandedKeys()).Num() == 0);
    const TSharedPtr<SWidget> ProjectionRowWidget = ProjectionRow->AsWidget();
    const FGeometry ProjectionGeometry = ProjectionRowWidget->GetCachedGeometry();
    const FVector2D ProjectionPosition = ProjectionGeometry.LocalToAbsolute(ProjectionGeometry.GetLocalSize() * 0.5f);
    const FPointerEvent LeftClick(0, FSlateApplication::CursorPointerIndex, ProjectionPosition, ProjectionPosition, TSet<FKey>{EKeys::LeftMouseButton}, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
    Tree->TrySetExpanded(TEXT("root"), false);
    const FReply ParentClick = ProjectionRowWidget->OnMouseButtonDown(ProjectionGeometry, LeftClick);
    Tick(Slate);
    TestTrue(TEXT("One unmodified parent row click toggles expansion exactly once"), ParentClick.IsEventHandled() && Tree->GetExpandedKeys().Contains(TEXT("root")));
    const SCkUiTree::FNode ChildNode = Model->FindNode(TEXT("child"));
    const TSharedPtr<ITableRow> ChildRow = NativeTree->WidgetFromItem(ChildNode);
    if (!TestTrue(TEXT("Projection child row realizes"), ChildRow.IsValid())) { return false; }
    const FGeometry ChildGeometry = ChildRow->AsWidget()->GetCachedGeometry();
    const FVector2D ChildPosition = ChildGeometry.LocalToAbsolute(ChildGeometry.GetLocalSize() * 0.5f);
    const FPointerEvent RightClick(0, FSlateApplication::CursorPointerIndex, ChildPosition, ChildPosition, TSet<FKey>{EKeys::RightMouseButton}, EKeys::RightMouseButton, 0.0f, FModifierKeysState{});
    ChildRow->AsWidget()->OnMouseButtonDown(ChildGeometry, RightClick);
    Tick(Slate);
    TestTrue(TEXT("Child and right clicks do not change parent expansion"), Tree->GetExpandedKeys().Contains(TEXT("root")));
    if (!TestTrue(TEXT("Projection excludes children of a false parent"), Model->TrySetNodes({Node(TEXT("root"), {}, TEXT("Root"), 0.0f, false), Node(TEXT("child"), FString(TEXT("root")), TEXT("Child")), Node(TEXT("other"), {}, TEXT("Other"))}).Succeeded)) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Projection hides true descendants beneath false ancestors without pruning expansion"), Tree->GetVisibleNodeCount() == 1 && Tree->GetExpandedKeys().Contains(TEXT("root")));
    if (!TestTrue(TEXT("Clearing projection reload succeeds"), View->TryReload(Markup(), Styles(), TEXT("UiTreeViewProjectionClear")).Succeeded)) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Clearing projection restores full hierarchy and prior user expansion"), Tree->GetVisibleNodeCount() == 3 && Tree->GetExpandedKeys().Contains(TEXT("root")) && Tree->GetTree() == NativeTree);
    const FString OrdinaryIdCollision = TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"tree\"><text id=\"ordinary\">ordinary</text></column></region></ui>");
    const FCkUiLoadResult KindChange = View->TryReload(OrdinaryIdCollision, TEXT(""), TEXT("UiTreeViewKindChange"));
    TestFalse(TEXT("Retained tree id cannot become an ordinary node"), KindChange.Succeeded);
    TestTrue(TEXT("Retained tree kind change preserves pointer and revision"), View->GetRevision() == AcceptedRevision + 2 && View->GetTree(TEXT("tree")) == Tree);
    TWeakPtr<FCkUiView> WeakView = View;
    TWeakPtr<FCkUiTreeCollection> WeakModel = Model;
    Slate.DestroyWindowImmediately(Scope.Window.ToSharedRef()); Scope.Window.Reset();
    HeightRow.Reset(); FocusedBeforeReload.Reset(); NativeTree.Reset(); Tree.Reset(); Region.Reset(); View.Reset(); Model.Reset();
    TestFalse(TEXT("Tree view and model release after native window teardown"), WeakView.IsValid() || WeakModel.IsValid());
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiTreeView_Validation, "Ck.UiAuthoring.Tree.ViewValidation", EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)
auto FCkUiTreeView_Validation::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_tree_view;
    TSharedPtr<FCkUiTreeCollection> Model; if (!TestTrue(TEXT("Validation tree model creates"), FCkUiTreeCollection::TryCreate(Schema(), Model).Succeeded)) { return false; }
    FString Query;
    const auto AddTreeAuxiliaryBindings = [&Query](FCkUiView::FDataBindings& InOutData)
    {
        InOutData.Text.Add(TEXT("query"), TAttribute<FText>::CreateLambda([&Query]() { return FText::FromString(Query); }));
        InOutData.TreeSelectionChanged.Add(TEXT("selected"), FOnCkUiTreeSelectionChanged::CreateLambda([](TOptional<FString>, ESelectInfo::Type) {}));
    };
    auto MissingData = FCkUiView::FDataBindings{}; AddTreeAuxiliaryBindings(MissingData);
    const TSharedRef<FCkUiView> Missing = FCkUiView::Create({}, {}, {}, {}, MoveTemp(MissingData)); Missing->GetRegion(TEXT("main"));
    const FCkUiLoadResult MissingBinding = Missing->TryReload(Markup(), Styles(), TEXT("UiTreeMissing"));
    TestFalse(TEXT("Missing tree binding rejects before factory"), MissingBinding.Succeeded); TestTrue(TEXT("Missing tree binding reports diagnostic"), !MissingBinding.Errors.IsEmpty());
    auto MissingFilterData = FCkUiView::FDataBindings{}; MissingFilterData.Trees.Add(TEXT("tree"), Model); MissingFilterData.TreeSelectionChanged.Add(TEXT("selected"), FOnCkUiTreeSelectionChanged::CreateLambda([](TOptional<FString>, ESelectInfo::Type) {}));
    const TSharedRef<FCkUiView> MissingFilter = FCkUiView::Create({}, {}, {}, {}, MoveTemp(MissingFilterData)); MissingFilter->GetRegion(TEXT("main"));
    const FCkUiLoadResult MissingFilterResult = MissingFilter->TryReload(Markup(), Styles(), TEXT("UiTreeMissingFilter"));
    TestFalse(TEXT("Missing tree filter binding rejects before factory"), MissingFilterResult.Succeeded); TestTrue(TEXT("Missing tree filter binding reports diagnostic"), !MissingFilterResult.Errors.IsEmpty());
    const auto OptionalProjectionSchema = TArray<FCkUiFieldSchema>{{TEXT("name"), ECkUiFieldKind::Text}, {TEXT("visible"), ECkUiFieldKind::Bool, false}};
    TSharedPtr<FCkUiTreeCollection> OptionalProjectionModel;
    if (!TestTrue(TEXT("Optional projection tree model creates"), FCkUiTreeCollection::TryCreate(OptionalProjectionSchema, OptionalProjectionModel).Succeeded)) { return false; }
    auto OptionalProjectionData = FCkUiView::FDataBindings{};
    OptionalProjectionData.Trees.Add(TEXT("tree"), OptionalProjectionModel);
    const TSharedRef<FCkUiView> OptionalProjectionView = FCkUiView::Create({}, {}, {}, {}, MoveTemp(OptionalProjectionData));
    OptionalProjectionView->GetRegion(TEXT("main"));
    const FCkUiLoadResult OptionalProjection = OptionalProjectionView->TryReload(ProjectionMarkup(), Styles(), TEXT("UiTreeOptionalProjection"));
    TestFalse(TEXT("Optional Bool projection field rejects before factory"), OptionalProjection.Succeeded);
    TestTrue(TEXT("Optional Bool projection field reports diagnostic"), !OptionalProjection.Errors.IsEmpty());
    auto Data = FCkUiView::FDataBindings{}; Data.Trees.Add(TEXT("tree"), Model); AddTreeAuxiliaryBindings(Data);
    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, {}, {}, {}, MoveTemp(Data)); View->GetRegion(TEXT("main"));
    for (const FString& Invalid : {Markup().Replace(TEXT("selection-action=\"selected\""), TEXT("selection-action=\"missing\"")), Markup().Replace(TEXT("<row id=\"cell\">"), TEXT("<row id=\"a\"><text id=\"x\" bind-field=\"name\"/></row><row id=\"b\">")), ProjectionMarkup().Replace(TEXT("projection-field=\"visible\""), TEXT("projection-field=\"name\"")), ProjectionMarkup().Replace(TEXT("projection-field=\"visible\""), TEXT("projection-field=\"visible\" filter-bind=\"query\"")), ProjectionMarkup().Replace(TEXT("selectable=\"false\""), TEXT("selectable=\"false\" selection-action=\"selected\""))})
    { const FCkUiLoadResult Result=View->TryReload(Invalid,Styles(),TEXT("UiTreeInvalid")); TestFalse(TEXT("Malformed tree declaration rejects"),Result.Succeeded); TestTrue(TEXT("Malformed tree declaration reports diagnostic"),!Result.Errors.IsEmpty()); }
    return true;
}

#endif
