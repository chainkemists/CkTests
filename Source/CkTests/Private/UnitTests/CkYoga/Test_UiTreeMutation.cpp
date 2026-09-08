#include "CkSlateLayout/CkUiTreeCollection.h"
#include "CkSlateLayout/CkUiWidgetRegistry.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkSlateLayout/SCkUiTree.h"

#include "Framework/Application/SlateApplication.h"
#include "Layout/Children.h"
#include "Misc/AutomationTest.h"
#include "Styling/CoreStyle.h"
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"
#include "Widgets/Views/ITableRow.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_tree_mutation
{
    struct FWindowScope final
    {
        explicit FWindowScope(FSlateApplication& InSlate) : Slate(InSlate) {}
        ~FWindowScope() { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } }

        FSlateApplication& Slate;
        TSharedPtr<SWindow> Window;
    };

    struct FMutationProbe final
    {
        TSharedPtr<FCkUiTreeCollection> Model;
        TArray<FCkUiTreeNodeData> Replacement;
        TWeakPtr<SWidget> CandidateDuringMutation;
        FString LabelAtMutation;
        FString TargetLabel;
        int32 Mutations = 0;
        bool bArmed = false;
    };

    auto Tick(FSlateApplication& InSlate) -> void { InSlate.PumpMessages(); InSlate.Tick(); InSlate.Tick(); }

    auto Schema() -> TArray<FCkUiFieldSchema> { return {{TEXT("name"), ECkUiFieldKind::Text}}; }

    auto Nodes(const FString& InPrefix, const int32 InCount = 192) -> TArray<FCkUiTreeNodeData>
    {
        auto Result = TArray<FCkUiTreeNodeData>{};
        Result.Reserve(InCount);
        for (int32 Index = 0; Index < InCount; ++Index)
        {
            auto Node = FCkUiTreeNodeData{};
            Node.Key = FString::Printf(TEXT("node-%03d"), Index);
            Node.ParentKey = TOptional<FString>{};
            Node.Fields.Add(TEXT("name"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Text,
                .Text = FText::FromString(FString::Printf(TEXT("%s node %03d"), *InPrefix, Index))});
            Result.Add(MoveTemp(Node));
        }
        return Result;
    }

    auto Markup() -> FString
    {
        return TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"><tree id=\"tree\" class=\"fill\" bind=\"tree\" row-height=\"24\"><row id=\"cell\"><mutation-cell id=\"mutation\" label-field=\"name\"/></row></tree></column></region></ui>");
    }

    auto Styles() -> FString { return TEXT(".fill { flex-grow: 1; }"); }

    auto ContainsWidget(const TSharedRef<SWidget>& InRoot, const SWidget* const InTarget) -> bool
    {
        if (&InRoot.Get() == InTarget) { return true; }
        const FChildren* const Children = InRoot->GetChildren();
        if (Children == nullptr) { return false; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        {
            if (ContainsWidget(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTarget)) { return true; }
        }
        return false;
    }

    auto FindText(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<STextBlock>
    {
        if (InRoot->GetTypeAsString() == TEXT("STextBlock")) { return StaticCastSharedRef<STextBlock>(InRoot); }
        const FChildren* const Children = InRoot->GetChildren();
        if (Children == nullptr) { return nullptr; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<STextBlock> Found = FindText(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid()) { return Found; }
        }
        return nullptr;
    }

    auto RegisterMutationCell(const TSharedRef<FMutationProbe>& InProbe, FCkUiWidgetRegistry& InRegistry) -> bool
    {
        auto Registration = FCkUiCustomWidgetRegistration{};
        Registration.Schema.Tag = TEXT("mutation-cell");
        Registration.Schema.Properties = {{TEXT("label"), ECkUiCustomPropertyKind::TextBinding}};
        Registration.Factory = [InProbe](const FCkUiCustomWidgetArguments& Args, FString& Failure) -> TSharedPtr<SWidget>
        {
            const TAttribute<FText>* const Label = Args.TextBindings.Find(TEXT("label"));
            if (Label == nullptr) { Failure = TEXT("Mutation cell did not receive its row label binding."); return nullptr; }

            const TSharedRef<STextBlock> Result = SNew(STextBlock).Text(*Label);
            const FString CurrentLabel = Label->Get(FText::GetEmpty()).ToString();
            if (!InProbe->bArmed || (!InProbe->TargetLabel.IsEmpty() && InProbe->TargetLabel != CurrentLabel)) { return Result; }

            InProbe->bArmed = false;
            InProbe->CandidateDuringMutation = Result;
            InProbe->LabelAtMutation = CurrentLabel;
            ++InProbe->Mutations;
            if (!InProbe->Model.IsValid() || !InProbe->Model->TrySetNodes(MoveTemp(InProbe->Replacement)).Succeeded)
            { Failure = TEXT("Mutation cell could not publish its replacement tree model."); return nullptr; }
            return Result;
        };
        return InRegistry.Register(MoveTemp(Registration)).Succeeded;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiTreeMutation_Runtime,
    "Ck.UiAuthoring.Tree.MutationGuards",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiTreeMutation_Runtime::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_tree_mutation;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Tree mutation test requires initialized Slate.")); return false; }

    TSharedPtr<FCkUiTreeCollection> Model;
    if (!TestTrue(TEXT("Mutation tree model creates"), FCkUiTreeCollection::TryCreate(Schema(), Model).Succeeded) || !Model.IsValid()) { return false; }
    if (!TestTrue(TEXT("Initial shallow stable-key tree publishes"), Model->TrySetNodes(Nodes(TEXT("Initial"))).Succeeded)) { return false; }

    const TSharedRef<FMutationProbe> Probe = MakeShared<FMutationProbe>();
    Probe->Model = Model;
    auto Registry = FCkUiWidgetRegistry{};
    if (!TestTrue(TEXT("Stateless mutation row factory registers"), RegisterMutationCell(Probe, Registry))) { return false; }

    auto Data = FCkUiView::FDataBindings{};
    Data.Trees.Add(TEXT("tree"), Model);
    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, {}, {}, FCoreStyle::GetDefaultFontStyle(TEXT("Regular"), 12), MoveTemp(Data), Registry.CreateSnapshot());
    const TSharedRef<SWidget> Region = View->GetRegion(TEXT("main"));
    FSlateApplication& Slate = FSlateApplication::Get();
    FWindowScope Scope{Slate};
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{480.0f, 240.0f}).CreateTitleBar(false).HasCloseButton(false)[Region];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);
    if (!TestTrue(TEXT("Production mutation tree document loads"), View->TryReload(Markup(), Styles(), TEXT("UiTreeMutation")).Succeeded)) { return false; }
    Tick(Slate);

    const TSharedPtr<SCkUiTree> Tree = View->GetTree(TEXT("tree"));
    const TSharedPtr<STreeView<SCkUiTree::FNode>> NativeTree = Tree.IsValid() ? Tree->GetTree() : nullptr;
    const SCkUiTree::FNode First = Model->FindNode(TEXT("node-000"));
    if (!TestTrue(TEXT("Initial valid render realizes the production native tree"), Tree.IsValid() && NativeTree.IsValid() && Tree->GetLiveRowCount() > 0 && Tree->GetLastCellError().IsEmpty())
        || !TestTrue(TEXT("Initial stable row exists"), First.IsValid())) { return false; }
    NativeTree->RequestScrollIntoView(First);
    Tick(Slate);

    const int64 ViewRevisionBeforeReload = View->GetRevision();
    const int64 ModelRevisionBeforeReload = Model->GetRevision();
    Probe->Replacement = Nodes(TEXT("Reloaded"));
    Probe->TargetLabel.Reset();
    Probe->bArmed = true;
    const FCkUiLoadResult ReloadRejected = View->TryReload(Markup(), Styles() + TEXT(" .fill { padding: 1px; }"), TEXT("UiTreeMutationReload"));
    TestFalse(TEXT("Reload rejects when a realized row factory mutates the tree during Prepare"), ReloadRejected.Succeeded);
    TestTrue(TEXT("Reload mutation reports the tree preparation diagnostic"), !ReloadRejected.Errors.IsEmpty() && ReloadRejected.Errors[0].Contains(TEXT("tree collection changed while preparing cells")));
    TestTrue(TEXT("Rejected reload leaves the native tree and view revision intact"), View->GetRevision() == ViewRevisionBeforeReload && View->GetTree(TEXT("tree")) == Tree && Tree->GetTree() == NativeTree);
    TestTrue(TEXT("Reload factory arms only after initial valid render and mutates once"), !Probe->bArmed && Probe->Mutations == 1 && Model->GetRevision() == ModelRevisionBeforeReload + 1);
    Tick(Slate);

    const FString OffscreenKey = TEXT("node-180");
    const SCkUiTree::FNode StaleOffscreen = Model->FindNode(OffscreenKey);
    if (!TestTrue(TEXT("Current offscreen stable-key node exists"), StaleOffscreen.IsValid())) { return false; }
    Probe->Replacement = Nodes(TEXT("Current"));
    Probe->CandidateDuringMutation.Reset();
    Probe->LabelAtMutation.Reset();
    Probe->TargetLabel = TEXT("Reloaded node 180");
    Probe->bArmed = true;
    NativeTree->RequestScrollIntoView(StaleOffscreen);
    Tick(Slate);
    const TSharedPtr<ITableRow> StaleRow = NativeTree->WidgetFromItem(StaleOffscreen);
    const TSharedPtr<SWidget> StaleCandidate = Probe->CandidateDuringMutation.Pin();
    const bool bStaleCandidateAttached = StaleRow.IsValid() && StaleCandidate.IsValid() && ContainsWidget(StaleRow->AsWidget(), StaleCandidate.Get());
    TestTrue(TEXT("Native offscreen realization invokes the armed factory for the requested stale row"), !Probe->bArmed && Probe->Mutations == 2 && Probe->LabelAtMutation == TEXT("Reloaded node 180"));
    TestTrue(TEXT("Lazy row guard records a stale-model diagnostic and never attaches its candidate"), Tree->GetLastCellError().Contains(TEXT("tree collection changed while generating row")) && !bStaleCandidateAttached);

    const SCkUiTree::FNode CurrentOffscreen = Model->FindNode(OffscreenKey);
    if (!TestTrue(TEXT("Replacement preserves the offscreen stable node identity while updating its fields"), CurrentOffscreen.IsValid() && CurrentOffscreen == StaleOffscreen)) { return false; }
    const int64 RecoveryRevision = View->GetRevision();
    if (!TestTrue(TEXT("Valid reload replaces the rejected lazy cell with the current stable-key row"), View->TryReload(Markup(), Styles() + TEXT(" .fill { padding: 2px; }"), TEXT("UiTreeMutationRecovery")).Succeeded)) { return false; }
    TestEqual(TEXT("Recovery reload publishes exactly one view revision"), View->GetRevision(), RecoveryRevision + 1);
    NativeTree->RequestScrollIntoView(CurrentOffscreen);
    Tick(Slate);
    const TSharedPtr<ITableRow> CurrentRow = NativeTree->WidgetFromItem(CurrentOffscreen);
    const TSharedPtr<STextBlock> CurrentText = CurrentRow.IsValid() ? FindText(CurrentRow->AsWidget()) : nullptr;
    TestTrue(TEXT("Later valid reload restores the current stable-key row after lazy rejection"), CurrentText.IsValid() && CurrentText->GetText().ToString() == TEXT("Current node 180"));
    return true;
}

#endif
