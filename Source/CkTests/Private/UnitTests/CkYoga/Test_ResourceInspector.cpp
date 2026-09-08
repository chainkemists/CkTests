#include "CkResourceInspector/CkResourceInspectorModel.h"

#include "CkSlateLayout/CkFlexText.h"
#include "CkSlateLayout/SCkUiRepeat.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkSlateLayout/SCkUiSplitter.h"
#include "CkSlateLayout/SCkUiTable.h"
#include "CkSlateLayout/SCkUiTree.h"

#include "Framework/Application/SlateApplication.h"
#include "HAL/FileManager.h"
#include "ImageCore.h"
#include "ImageUtils.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "Interfaces/IPluginManager.h"
#include "Layout/WidgetPath.h"
#include "Misc/App.h"
#include "Misc/AutomationTest.h"
#include "Misc/FileHelper.h"
#include "Misc/Guid.h"
#include "Misc/Paths.h"
#include "Widgets/Input/SSearchBox.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/Layout/SScrollBox.h"
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"
#include "Widgets/Views/ITableRow.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_resource_inspector
{
    struct FWindowScope final
    {
        explicit FWindowScope(FSlateApplication& InSlate) : Slate(InSlate) {}
        ~FWindowScope() { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } }
        FSlateApplication& Slate;
        TSharedPtr<SWindow> Window;
    };

    struct FOwnedFile final
    {
        explicit FOwnedFile(FString InPath) : Path(MoveTemp(InPath)) {}
        ~FOwnedFile() { if (!Path.IsEmpty()) { IFileManager::Get().Delete(*Path, false, true); } }
        FString Path;
    };

    auto Tick(FSlateApplication& InSlate) -> void
    {
        InSlate.PumpMessages();
        InSlate.Tick();
        InSlate.Tick();
    }

    auto FindTagged(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTag() == InTag) { return InRoot; }
        const FChildren* Children = InRoot->GetChildren();
        if (Children == nullptr) { return nullptr; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SWidget> Found = FindTagged(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag); Found.IsValid()) { return Found; }
        }
        return nullptr;
    }

    auto FindSearchBox(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SSearchBox>
    {
        if (InRoot->GetTypeAsString() == TEXT("SSearchBox")) { return StaticCastSharedRef<SSearchBox>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        if (Children == nullptr) { return nullptr; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SSearchBox> Found = FindSearchBox(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid()) { return Found; }
        }
        return nullptr;
    }

    auto FindFlexText(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SCkFlexText>
    {
        if (InRoot->GetTypeAsString() == TEXT("SCkFlexText")) { return StaticCastSharedRef<SCkFlexText>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        if (Children == nullptr) { return nullptr; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SCkFlexText> Found = FindFlexText(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid()) { return Found; }
        }
        return nullptr;
    }

    auto ErrorText(const FCkUiLoadResult& InResult) -> FString
    {
        return InResult.Errors.IsEmpty() ? TEXT("No diagnostic was returned.") : FString::Join(InResult.Errors, TEXT("\n"));
    }

    auto ContainsText(const TSharedRef<SWidget>& InRoot, const FString& InText) -> bool
    {
        if (InRoot->GetTypeAsString() == TEXT("STextBlock") && StaticCastSharedRef<STextBlock>(InRoot)->GetText().ToString() == InText) { return true; }
        const FChildren* Children = InRoot->GetChildren();
        if (Children == nullptr) { return false; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        {
            if (ContainsText(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InText)) { return true; }
        }
        return false;
    }

    auto FindButton(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SButton>
    {
        if (InRoot->GetTypeAsString() == TEXT("SButton")) { return StaticCastSharedRef<SButton>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        if (Children == nullptr) { return nullptr; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SButton> Found = FindButton(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid()) { return Found; }
        }
        return nullptr;
    }

    auto FindHeaderButton(const TSharedRef<SWidget>& InRoot, const FString& InLabel) -> TSharedPtr<SButton>
    {
        if (InRoot->GetTypeAsString() == TEXT("STableColumnHeader") && ContainsText(InRoot, InLabel)) { return FindButton(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        if (Children == nullptr) { return nullptr; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SButton> Found = FindHeaderButton(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InLabel); Found.IsValid()) { return Found; }
        }
        return nullptr;
    }

    auto Click(const TSharedRef<SButton>& InButton) -> bool
    {
        const FGeometry Geometry = InButton->GetCachedGeometry();
        const FVector2D Position = Geometry.GetAbsolutePosition() + Geometry.GetAbsoluteSize() * 0.5f;
        const FPointerEvent Down{0, Position, Position, TSet<FKey>{EKeys::LeftMouseButton}, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{}};
        const FPointerEvent Up{0, Position, Position, TSet<FKey>{}, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{}};
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

    auto SaveCapture(FSlateApplication& InSlate, const TSharedRef<SWidget>& InRoot, const FString& InPath, FString& OutError) -> bool
    {
        OutError.Reset();
        if (!FApp::CanEverRender() || IsRunningDedicatedServer()) { OutError = TEXT("Capture requires a render-capable non-dedicated Slate runtime."); return false; }
        TArray<FColor> Pixels;
        FIntVector Size = FIntVector::ZeroValue;
        if (!InSlate.TakeScreenshot(InRoot, Pixels, Size) || Size.X <= 0 || Size.Y <= 0 || Pixels.Num() < Size.X * Size.Y)
        {
            OutError = TEXT("Slate did not return the expected screenshot pixels.");
            return false;
        }
        const FImageView Image{Pixels.GetData(), Size.X, Size.Y, ERawImageFormat::BGRA8};
        if (!FImageUtils::SaveImageByExtension(*InPath, Image)) { OutError = FString::Printf(TEXT("Could not write '%s'."), *InPath); return false; }
        return true;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkResourceInspector_ModelView,
    "Ck.ResourceInspector.ModelView.NativeResources",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkResourceInspector_ModelView::RunTest(const FString&) -> bool
{
    using namespace ck_tests_resource_inspector;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Resource Inspector model/view test requires initialized Slate.")); return false; }

    const TSharedPtr<IPlugin> Plugin = IPluginManager::Get().FindPlugin(TEXT("CkTests"));
    if (!TestTrue(TEXT("CkTests plugin resolves its installed Resource Inspector resources"), Plugin.IsValid())) { return false; }
    const FString ResourceDirectory = FPaths::Combine(Plugin->GetBaseDir(), TEXT("Resources/ResourceInspector"));
    const FString MarkupPath = FPaths::Combine(ResourceDirectory, TEXT("ResourceInspector.ui.html"));
    const FString StylesheetPath = FPaths::Combine(ResourceDirectory, TEXT("ResourceInspector.ui.css"));
    if (!TestTrue(TEXT("Installed Resource Inspector markup and stylesheet exist"), FPaths::FileExists(MarkupPath) && FPaths::FileExists(StylesheetPath))) { return false; }

    int32 CloseCalls = 0;
    TWeakPtr<FCkResourceInspectorModel> WeakModel;
    {
        TSharedPtr<FCkResourceInspectorModel> Model;
        FString CreateError;
        const bool bCreated = FCkResourceInspectorModel::TryCreate(FSimpleDelegate::CreateLambda([&CloseCalls]() { ++CloseCalls; }), Model, CreateError, 0);
        if (!TestTrue(*FString::Printf(TEXT("Resource Inspector model creates: %s"), *CreateError), bCreated) || !Model.IsValid()) { return false; }
        WeakModel = Model;
        TSharedPtr<FCkUiView> View = Model->GetView();
        TSharedPtr<FCkUiCollection> Collection = Model->GetCollection();
        if (!TestTrue(TEXT("Model exposes its retained production view and typed collection"), View.IsValid() && Collection.IsValid())) { return false; }
        TestEqual(TEXT("Model begins with the deterministic twelve-resource scenario"), Collection->GetRecords().Num(), 12);

        FSlateApplication& Slate = FSlateApplication::Get();
        TSharedPtr<SCkUiTable> Table;
        TSharedPtr<SCkUiTree> Navigation;
        TSharedPtr<SListView<SCkUiTable::FRecord>> List;
        TSharedPtr<SSearchBox> Search;
        {
            FWindowScope Scope{Slate};
            Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{960.0f, 640.0f}).CreateTitleBar(false).HasCloseButton(false)[Model->GetRoot()];
            Slate.AddWindow(Scope.Window.ToSharedRef(), true);
            const FString CaptureDirectory = FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Automation/ResourceInspector"));
            if (!TestTrue(TEXT("Resource Inspector capture directory exists"), IFileManager::Get().DirectoryExists(*CaptureDirectory) || IFileManager::Get().MakeDirectory(*CaptureDirectory, true))) { return false; }

            const FCkUiLoadResult InitialLoad = View->ReloadFiles(MarkupPath, StylesheetPath);
            if (!TestTrue(*FString::Printf(TEXT("Installed Resource Inspector document loads: %s"), *ErrorText(InitialLoad)), InitialLoad.Succeeded)) { return false; }
            Tick(Slate);
            FString CaptureError;
            const FString WideCapturePath = FPaths::Combine(CaptureDirectory, TEXT("Wide_960x640.png"));
            const bool bWideCapture = SaveCapture(Slate, Model->GetRoot(), WideCapturePath, CaptureError);
            TestTrue(*FString::Printf(TEXT("Wide Resource Inspector Slate capture writes: %s"), *CaptureError), bWideCapture);

            Table = View->GetTable(TEXT("inspector-dialog/content/resources"));
            Navigation = View->GetTree(TEXT("inspector-dialog/content/navigation"));
            const TSharedPtr<SCkUiSplitter> Splitter = View->GetSplitter(TEXT("inspector-dialog/content/resource-splitter"));
            const TSharedPtr<SWidget> TaggedSearch = FindTagged(Model->GetRoot(), TEXT("query"));
            Search = TaggedSearch.IsValid() ? FindSearchBox(TaggedSearch.ToSharedRef()) : nullptr;
            if (!TestTrue(TEXT("Installed document generates declared table, tree, splitter, and native search control"), Table.IsValid() && Navigation.IsValid() && Splitter.IsValid() && Search.IsValid())) { return false; }
            List = Table->GetList();
            const TSharedPtr<STreeView<SCkUiTree::FNode>> NativeNavigation = Navigation->GetTree();
            if (!TestTrue(TEXT("Generated table and navigation tree expose persistent native views"), List.IsValid() && NativeNavigation.IsValid())) { return false; }
            TestEqual(TEXT("Initial collection is visible through the authored table"), Table->GetVisibleRecordCount(), 12);
            TestTrue(TEXT("Declared production resource columns generate without a cell error"), Table->GetLastCellError().IsEmpty());

            const TSharedPtr<FCkUiTreeCollection> NavigationData = Model->GetNavigation();
            if (!TestTrue(TEXT("Model exposes the authored category navigation collection"), NavigationData.IsValid())) { return false; }
            TestTrue(TEXT("Native category tree expands its authored all-resources root"), Navigation->TrySetExpanded(TEXT("all"), true));
            Tick(Slate);
            TestTrue(TEXT("Category expansion persists as retained native tree state"), Navigation->GetExpandedKeys().Contains(TEXT("all")));

            int32 CategoryPublicationCalls = 0;
            bool bCategoryPublicationIsCoherent = false;
            bool bCategoryPublicationRejectsReentrancy = false;
            const FDelegateHandle CategoryPublicationHandle = Collection->OnChanged().AddLambda([&]()
            {
                ++CategoryPublicationCalls;
                const int64 RevisionBeforeReentrancy = Collection->GetRevision();
                const int32 RecordCountBeforeReentrancy = Collection->GetRecords().Num();
                bool bAllKindsMaterial = RecordCountBeforeReentrancy == 3;
                for (const TSharedPtr<const FCkUiRecord>& Record : Collection->GetRecords())
                {
                    const FCkUiFieldValue* Kind = Record.IsValid() ? Record->FindField(TEXT("kind")) : nullptr;
                    bAllKindsMaterial = bAllKindsMaterial && Kind != nullptr && Kind->Text.ToString() == TEXT("Material");
                }
                FString NestedCategoryError;
                FString NestedRowCountError;
                const bool bCategoryRejected = !Model->TrySetCategory(TEXT("texture"), NestedCategoryError);
                const bool bRowCountRejected = !Model->TrySetRowCount(0, NestedRowCountError);
                bCategoryPublicationIsCoherent = Model->GetCategory() == TEXT("material") && bAllKindsMaterial;
                bCategoryPublicationRejectsReentrancy = bCategoryRejected && bRowCountRejected &&
                    !NestedCategoryError.IsEmpty() && !NestedRowCountError.IsEmpty() && Model->GetCategory() == TEXT("material") &&
                    Collection->GetRevision() == RevisionBeforeReentrancy && Collection->GetRecords().Num() == RecordCountBeforeReentrancy;
            });
            TestTrue(TEXT("Native material tree selection invokes the model category callback"), Navigation->TrySelectKey(FString(TEXT("material")), true));
            Collection->OnChanged().Remove(CategoryPublicationHandle);
            Tick(Slate);
            TestEqual(TEXT("Native material category updates the model"), Model->GetCategory(), FString(TEXT("material")));
            TestEqual(TEXT("Material category filters the authored table to its exact deterministic records"), Table->GetVisibleRecordCount(), 3);
            TestTrue(TEXT("Category publication exposes coherent material records before observers run"), CategoryPublicationCalls == 1 && bCategoryPublicationIsCoherent);
            TestTrue(TEXT("Category publication rejects nested model mutations without changing its published snapshot"), bCategoryPublicationRejectsReentrancy);

            Search->SetText(FText::FromString(TEXT("Resource_00005")));
            Tick(Slate);
            TestEqual(TEXT("Material category combined with native search isolates Resource_00005"), Table->GetVisibleRecordCount(), 1);
            TestTrue(TEXT("Native texture tree selection is accepted"), Navigation->TrySelectKey(FString(TEXT("texture")), true));
            Tick(Slate);
            TestEqual(TEXT("Texture category excludes the material search result"), Table->GetVisibleRecordCount(), 0);
            TestTrue(TEXT("Native all-resources tree selection is accepted"), Navigation->TrySelectKey(FString(TEXT("all")), true));
            Tick(Slate);
            TestEqual(TEXT("All-resources category restores the native search result"), Table->GetVisibleRecordCount(), 1);
            Search->SetText(FText::GetEmpty());
            Tick(Slate);
            TestEqual(TEXT("All-resources category restores the initial table projection"), Table->GetVisibleRecordCount(), 12);

            const int64 NavigationRevisionBeforeUnknown = NavigationData->GetRevision();
            const int64 CollectionRevisionBeforeUnknown = Collection->GetRevision();
            const FString CategoryBeforeUnknown = Model->GetCategory();
            const TOptional<FString> SelectedCategoryBeforeUnknown = Navigation->GetSelectedKey();
            FString UnknownCategoryError;
            TestFalse(TEXT("Unknown category rejects"), Model->TrySetCategory(TEXT("unknown-category"), UnknownCategoryError));
            TestTrue(TEXT("Unknown category reports a diagnostic"), !UnknownCategoryError.IsEmpty());
            TestTrue(TEXT("Unknown category leaves model, tree data revision, and native selection unchanged"),
                Model->GetCategory() == CategoryBeforeUnknown && Collection->GetRevision() == CollectionRevisionBeforeUnknown &&
                NavigationData->GetRevision() == NavigationRevisionBeforeUnknown && Navigation->GetSelectedKey() == SelectedCategoryBeforeUnknown);

            FString CategoryScenarioError;
            if (!TestTrue(*FString::Printf(TEXT("Category one-thousand scenario publishes: %s"), *CategoryScenarioError), Model->TrySetRowCount(1000, CategoryScenarioError))) { return false; }
            Tick(Slate);
            TestTrue(TEXT("Native texture category selection accepts the one-thousand scenario"), Navigation->TrySelectKey(FString(TEXT("texture")), true));
            Tick(Slate);
            TestEqual(TEXT("Texture category has exactly one quarter of the one-thousand deterministic resources"), Table->GetVisibleRecordCount(), 250);
            TestTrue(TEXT("Native all-resources category selection restores one-thousand scenario"), Navigation->TrySelectKey(FString(TEXT("all")), true));
            Tick(Slate);
            TestEqual(TEXT("All-resources category restores the complete one-thousand projection"), Table->GetVisibleRecordCount(), 1000);
            if (!TestTrue(*FString::Printf(TEXT("Category scenario restores default twelve resources: %s"), *CategoryScenarioError), Model->TrySetRowCount(12, CategoryScenarioError))) { return false; }
            Tick(Slate);
            TestTrue(TEXT("Category scenario restores all category, empty query, and default resource count before existing coverage"),
                Model->GetCategory() == TEXT("all") && Model->GetQuery().IsEmpty() && Collection->GetRecords().Num() == 12 && Table->GetVisibleRecordCount() == 12);

            const TSharedPtr<const FCkUiRecord> Selected = Collection->FindRecord(TEXT("resource-00005"));
            if (!TestTrue(TEXT("Deterministic selected resource exists"), Selected.IsValid())) { return false; }
            if (!TestTrue(TEXT("Table selection invokes the model selection binding"), Table->TrySelectKey(Selected->GetKey(), true))) { return false; }
            Tick(Slate);
            const TSharedPtr<SWidget> DetailTitleTag = FindTagged(Model->GetRoot(), TEXT("selected-title"));
            const TSharedPtr<SCkFlexText> DetailTitle = DetailTitleTag.IsValid() ? FindFlexText(DetailTitleTag.ToSharedRef()) : nullptr;
            TestTrue(TEXT("Selection updates the authored details through the production callback"), DetailTitle.IsValid() && DetailTitle->GetText().ToString() == TEXT("Resource_00005"));

            Search->SetText(FText::FromString(TEXT("Resource_00005")));
            Tick(Slate);
            TestEqual(TEXT("Native search SetText writes through its authored text binding"), Model->GetQuery(), FString(TEXT("Resource_00005")));
            TestEqual(TEXT("Authored table filter observes the search binding"), Table->GetVisibleRecordCount(), 1);
            Search->SetText(FText::GetEmpty());
            Tick(Slate);
            TestEqual(TEXT("Clearing native search restores the deterministic table projection"), Table->GetVisibleRecordCount(), 12);

            FString ScenarioError;
            if (!TestTrue(*FString::Printf(TEXT("Zero-resource scenario publishes: %s"), *ScenarioError), Model->TrySetRowCount(0, ScenarioError))) { return false; }
            Tick(Slate);
            TestTrue(TEXT("Zero-resource scenario clears the real collection and table projection"), Collection->GetRecords().IsEmpty() && Table->GetVisibleRecordCount() == 0);
            if (!TestTrue(*FString::Printf(TEXT("One-resource scenario publishes: %s"), *ScenarioError), Model->TrySetRowCount(1, ScenarioError))) { return false; }
            Tick(Slate);
            TestTrue(TEXT("One-resource scenario publishes its stable first record"), Collection->FindRecord(TEXT("resource-00000")).IsValid() && Table->GetVisibleRecordCount() == 1);
            if (!TestTrue(*FString::Printf(TEXT("One-thousand resource scenario publishes: %s"), *ScenarioError), Model->TrySetRowCount(1000, ScenarioError))) { return false; }
            Tick(Slate);
            const TSharedPtr<const FCkUiRecord> Thousandth = Collection->FindRecord(TEXT("resource-00900"));
            if (!TestTrue(TEXT("Offscreen one-thousand scenario record exists"), Thousandth.IsValid())) { return false; }
            List->RequestScrollIntoView(Thousandth);
            Tick(Slate);
            TestTrue(TEXT("Offscreen one-thousand record realizes through the real native list"), List->WidgetFromItem(Thousandth).IsValid());
            TestTrue(TEXT("One-thousand scenario keeps generated table rows bounded"), Table->GetLiveRowCount() > 0 && Table->GetLiveRowCount() < 128);

            if (!TestTrue(*FString::Printf(TEXT("Ten-thousand resource scenario publishes: %s"), *ScenarioError), Model->TrySetRowCount(10000, ScenarioError))) { return false; }
            Tick(Slate);
            const TSharedPtr<const FCkUiRecord> TenThousandth = Collection->FindRecord(TEXT("resource-09900"));
            if (!TestTrue(TEXT("Offscreen ten-thousand scenario record exists"), TenThousandth.IsValid())) { return false; }
            List->RequestScrollIntoView(TenThousandth);
            Tick(Slate);
            TestTrue(TEXT("Offscreen ten-thousand record realizes through the real native list"), List->WidgetFromItem(TenThousandth).IsValid());
            TestTrue(TEXT("Ten-thousand scenario keeps generated table rows bounded"), Table->GetLiveRowCount() > 0 && Table->GetLiveRowCount() < 128);

            const TSharedPtr<SButton> SizeHeader = FindHeaderButton(Table.ToSharedRef(), TEXT("Size"));
            if (!TestTrue(TEXT("Numeric size column exposes its native sortable header"), SizeHeader.IsValid())) { return false; }
            if (!TestTrue(TEXT("Numeric size header handles its native click"), Click(SizeHeader.ToSharedRef()))) { return false; }
            Tick(Slate);
            TestTrue(TEXT("Native numeric size sort orders bytes rather than formatted size text"), !List->GetItems().IsEmpty() && List->GetItems()[0]->GetKey() == TEXT("resource-00000"));

            const TSharedPtr<const FCkUiRecord> RetainedSelection = Collection->FindRecord(TEXT("resource-00005"));
            if (!TestTrue(TEXT("Retained selection record survives scenario expansion"), RetainedSelection.IsValid() && Table->TrySelectKey(RetainedSelection->GetKey(), true))) { return false; }
            const int64 CollectionRevision = Collection->GetRevision();
            const int32 CollectionCount = Collection->GetRecords().Num();
            const TOptional<FString> SelectedKeyBeforeInvalidCount = Table->GetSelectedKey();
            for (const int32 InvalidCount : {-1, 10001})
            {
                FString InvalidCountError;
                TestFalse(*FString::Printf(TEXT("Invalid row count %d rejects"), InvalidCount), Model->TrySetRowCount(InvalidCount, InvalidCountError));
                TestTrue(*FString::Printf(TEXT("Invalid row count %d reports a diagnostic"), InvalidCount), !InvalidCountError.IsEmpty());
                TestTrue(*FString::Printf(TEXT("Invalid row count %d does not publish records or selection"), InvalidCount), Collection->GetRevision() == CollectionRevision && Collection->GetRecords().Num() == CollectionCount && Table->GetSelectedKey() == SelectedKeyBeforeInvalidCount);
            }
            if (!TestTrue(TEXT("Native material tree selection prepares retained category state for reload"), Navigation->TrySelectKey(FString(TEXT("material")), true))) { return false; }
            Tick(Slate);
            TestEqual(TEXT("Material category projects the deterministic ten-thousand scenario"), Table->GetVisibleRecordCount(), 2500);
            Search->SetText(FText::FromString(TEXT("Resource_00005")));
            Tick(Slate);
            const int64 AcceptedRevision = View->GetRevision();
            const FCkUiLoadResult AcceptedReload = View->ReloadFiles(MarkupPath, StylesheetPath);
            if (!TestTrue(*FString::Printf(TEXT("Installed valid reload succeeds: %s"), *ErrorText(AcceptedReload)), AcceptedReload.Succeeded)) { return false; }
            Tick(Slate);
            TestEqual(TEXT("Installed valid reload advances publication revision"), View->GetRevision(), AcceptedRevision + 1);
            TestTrue(TEXT("Installed valid reload retains table and list identity"), View->GetTable(TEXT("inspector-dialog/content/resources")) == Table && Table->GetList() == List);
            TestTrue(TEXT("Installed valid reload retains navigation tree identity, native tree, category selection, and expansion"),
                View->GetTree(TEXT("inspector-dialog/content/navigation")) == Navigation && Navigation->GetTree() == NativeNavigation &&
                Model->GetCategory() == TEXT("material") && Navigation->GetSelectedKey().IsSet() &&
                Navigation->GetSelectedKey().GetValue() == TEXT("material") && Navigation->GetExpandedKeys().Contains(TEXT("all")));
            const TSharedPtr<SWidget> ReloadedSearchTag = FindTagged(Model->GetRoot(), TEXT("query"));
            const TSharedPtr<SSearchBox> ReloadedSearch = ReloadedSearchTag.IsValid() ? FindSearchBox(ReloadedSearchTag.ToSharedRef()) : nullptr;
            TestTrue(TEXT("Installed valid reload retains search identity, model query, and selected key"), ReloadedSearch == Search && Model->GetQuery() == TEXT("Resource_00005") && Table->GetSelectedKey().IsSet() && Table->GetSelectedKey().GetValue() == TEXT("resource-00005"));

            TestTrue(TEXT("Native all-resources selection restores the default category after retained-reload coverage"), Navigation->TrySelectKey(FString(TEXT("all")), true));
            Tick(Slate);
            TestTrue(TEXT("Category reload coverage restores all category and retained native search result before existing assertions"),
                Model->GetCategory() == TEXT("all") && Model->GetQuery() == TEXT("Resource_00005") && Table->GetVisibleRecordCount() == 1);

            Search->SetText(FText::FromString(TEXT("No matching resource")));
            Tick(Slate);
            const TSharedPtr<SWidget> EmptyOverlay = FindTagged(Model->GetRoot(), TEXT("resource-empty"));
            const TSharedPtr<SWidget> EmptyMessageTag = FindTagged(Model->GetRoot(), TEXT("resource-empty-message"));
            const TSharedPtr<SCkFlexText> EmptyMessage = EmptyMessageTag.IsValid() ? FindFlexText(EmptyMessageTag.ToSharedRef()) : nullptr;
            const TSharedPtr<SWidget> HeaderCountTag = FindTagged(Model->GetRoot(), TEXT("header-count"));
            const TSharedPtr<SCkFlexText> HeaderCount = HeaderCountTag.IsValid() ? FindFlexText(HeaderCountTag.ToSharedRef()) : nullptr;
            TestTrue(TEXT("Non-matching filter shows the authored empty overlay and message"), Table->GetVisibleRecordCount() == 0 && EmptyOverlay.IsValid() && EmptyOverlay->GetVisibility() == EVisibility::Visible && EmptyMessage.IsValid() && EmptyMessage->GetText().ToString() == TEXT("No resources match the filter."));
            TestTrue(TEXT("Non-matching filter updates the authored visible/total header count"), HeaderCount.IsValid() && HeaderCount->GetText().ToString() == TEXT("0 / 10000 resources"));
            Search->SetText(FText::FromString(TEXT("Resource_00005")));
            Tick(Slate);

            if (!TestTrue(TEXT("Restored filter permits selecting the previously filtered-out resource"), Table->TrySelectKey(FString(TEXT("resource-00005")), true))) { return false; }
            Search->SetText(FText::GetEmpty());
            Tick(Slate);
            const auto PinTag = FindTagged(Model->GetRoot(), TEXT("pin-selected-resource"));
            const auto PinButton = PinTag.IsValid() ? FindButton(PinTag.ToSharedRef()) : nullptr;
            if (!TestTrue(TEXT("Snapshot capture exposes its authored pin button"), PinButton.IsValid())) { return false; }
            for (const FString Key : {FString(TEXT("resource-00000")), FString(TEXT("resource-00005"))})
            {
                if (!TestTrue(TEXT("Snapshot capture selects an existing resource"), Table->TrySelectKey(Key, true))) { return false; }
                PinButton->SimulateClick();
                Tick(Slate);
            }
            TestEqual(TEXT("Snapshot capture contains two comparison cards"), Model->GetPinnedSnapshots()->GetRecords().Num(), 2);
            Search->SetText(FText::FromString(TEXT("Resource_00005")));
            Tick(Slate);
            const FString PinnedWidePath = FPaths::Combine(CaptureDirectory, TEXT("Pinned_Wide_960x640.png"));
            CaptureError.Reset();
            TestTrue(*FString::Printf(TEXT("Pinned comparison capture writes: %s"), *CaptureError), SaveCapture(Slate, Model->GetRoot(), PinnedWidePath, CaptureError));
            Scope.Window->Resize(FVector2D{640.0f, 480.0f});
            Tick(Slate);
            TestTrue(TEXT("Narrow capture has exactly one native category highlight matching the model"),
                NativeNavigation->GetNumItemsSelected() == 1
                && NativeNavigation->IsItemSelected(NavigationData->FindNode(TEXT("all"))));
            TestTrue(TEXT("Narrow capture has exactly one native resource highlight matching the model"),
                List->GetNumItemsSelected() == 1
                && List->IsItemSelected(Collection->FindRecord(TEXT("resource-00005"))));
            const TSharedPtr<SWidget> ScenarioToolbar = FindTagged(Model->GetRoot(), TEXT("scenario-actions"));
            if (!TestTrue(TEXT("Narrow scenario toolbar exists"), ScenarioToolbar.IsValid())) { return false; }
            const FGeometry ToolbarGeometry = ScenarioToolbar->GetCachedGeometry();
            for (const TCHAR* ButtonId : {TEXT("rows-0"), TEXT("rows-1"), TEXT("rows-12"), TEXT("rows-1000"), TEXT("rows-10000")})
            {
                const TSharedPtr<SWidget> ButtonTag = FindTagged(Model->GetRoot(), FName(ButtonId));
                const TSharedPtr<SButton> ScenarioButton = ButtonTag.IsValid() ? FindButton(ButtonTag.ToSharedRef()) : nullptr;
                if (!TestTrue(*FString::Printf(TEXT("Narrow scenario button %s exists"), ButtonId), ScenarioButton.IsValid())) { return false; }
                const FGeometry ButtonGeometry = ScenarioButton->GetCachedGeometry();
                const FVector2D ButtonStart = ToolbarGeometry.AbsoluteToLocal(ButtonGeometry.GetAbsolutePosition());
                const FVector2D ButtonEnd = ToolbarGeometry.AbsoluteToLocal(ButtonGeometry.LocalToAbsolute(ButtonGeometry.GetLocalSize()));
                TestTrue(*FString::Printf(TEXT("Narrow scenario button %s fits its toolbar without clipping"), ButtonId),
                    ButtonGeometry.GetLocalSize().X > 0.0f && ButtonGeometry.GetLocalSize().Y > 0.0f
                    && ButtonStart.X >= -1.0f && ButtonStart.Y >= -1.0f
                    && ButtonEnd.X <= ToolbarGeometry.GetLocalSize().X + 1.0f
                    && ButtonEnd.Y <= ToolbarGeometry.GetLocalSize().Y + 1.0f);
            }
            const FString NarrowCapturePath = FPaths::Combine(CaptureDirectory, TEXT("Narrow_640x480.png"));
            CaptureError.Reset();
            const bool bNarrowCapture = SaveCapture(Slate, Model->GetRoot(), NarrowCapturePath, CaptureError);
            TestTrue(*FString::Printf(TEXT("Narrow Resource Inspector Slate capture writes: %s"), *CaptureError), bNarrowCapture);

            const TSharedPtr<SScrollBox> DetailScroll = View->GetScroll(TEXT("inspector-dialog/content/detail-scroll"));
            const TSharedPtr<SCkUiRepeat> PinnedSnapshots = View->GetRepeat(TEXT("inspector-dialog/content/pinned-snapshots"));
            if (!TestTrue(TEXT("Narrow capture exposes a scrollable detail pane with retained snapshot cards"),
                DetailScroll.IsValid() && PinnedSnapshots.IsValid() && PinnedSnapshots->GetItemCount() == 2 && DetailScroll->GetScrollOffsetOfEnd() > 0.0f)) { return false; }
            DetailScroll->SetScrollOffset(DetailScroll->GetScrollOffsetOfEnd());
            Tick(Slate);
            const TSharedPtr<SWidget> PinnedCard = PinnedSnapshots->GetItemWidget(TEXT("resource-00005"));
            const TSharedPtr<SWidget> PinnedHeadingTag = PinnedCard.IsValid() ? FindTagged(PinnedCard.ToSharedRef(), TEXT("toggle-pinned-snapshot")) : nullptr;
            const TSharedPtr<SWidget> PinnedRemoveTag = PinnedCard.IsValid() ? FindTagged(PinnedCard.ToSharedRef(), TEXT("remove-pinned-snapshot")) : nullptr;
            const TSharedPtr<SButton> PinnedHeading = PinnedHeadingTag.IsValid() ? FindButton(PinnedHeadingTag.ToSharedRef()) : nullptr;
            const TSharedPtr<SButton> PinnedRemove = PinnedRemoveTag.IsValid() ? FindButton(PinnedRemoveTag.ToSharedRef()) : nullptr;
            if (!TestTrue(TEXT("Scrolled narrow capture exposes the last snapshot heading and removal action"), PinnedHeading.IsValid() && PinnedRemove.IsValid())) { return false; }
            const FGeometry DetailGeometry = DetailScroll->GetCachedGeometry();
            const auto TestSnapshotActionGeometry = [this, &DetailGeometry](const TCHAR* InName, const TSharedRef<SButton>& InAction) -> void
            {
                const FGeometry ActionGeometry = InAction->GetCachedGeometry();
                const FVector2D ActionStart = DetailGeometry.AbsoluteToLocal(ActionGeometry.GetAbsolutePosition());
                const FVector2D ActionEnd = DetailGeometry.AbsoluteToLocal(ActionGeometry.LocalToAbsolute(ActionGeometry.GetLocalSize()));
                TestTrue(*FString::Printf(TEXT("Scrolled narrow snapshot %s action has visible nonclipped geometry"), InName),
                    ActionGeometry.GetLocalSize().X > 0.0f && ActionGeometry.GetLocalSize().Y > 0.0f
                    && ActionStart.X >= -1.0f && ActionStart.Y >= -1.0f
                    && ActionEnd.X <= DetailGeometry.GetLocalSize().X + 1.0f && ActionEnd.Y <= DetailGeometry.GetLocalSize().Y + 1.0f);
            };
            TestSnapshotActionGeometry(TEXT("heading"), PinnedHeading.ToSharedRef());
            TestSnapshotActionGeometry(TEXT("remove"), PinnedRemove.ToSharedRef());
            const FString PinnedNarrowPath = FPaths::Combine(CaptureDirectory, TEXT("Pinned_Narrow_640x480.png"));
            CaptureError.Reset();
            TestTrue(*FString::Printf(TEXT("Scrolled narrow pinned comparison capture writes: %s"), *CaptureError), SaveCapture(Slate, Model->GetRoot(), PinnedNarrowPath, CaptureError));

            const FString InvalidMarkupPath = FPaths::Combine(CaptureDirectory, FString::Printf(TEXT("%s.ui.html"), *FGuid::NewGuid().ToString(EGuidFormats::Digits)));
            const FOwnedFile InvalidMarkup{InvalidMarkupPath};
            if (!TestTrue(TEXT("Owned invalid Resource Inspector document writes for ReloadFiles rejection"), FFileHelper::SaveStringToFile(TEXT("<ui version=\"1\"><region name=\"main\"><table id=\"resources\""), *InvalidMarkupPath))) { return false; }
            const int64 RevisionBeforeInvalidFile = View->GetRevision();
            const FCkUiLoadResult InvalidFile = View->ReloadFiles(InvalidMarkupPath, StylesheetPath);
            TestFalse(TEXT("Invalid Resource Inspector file document rejects"), InvalidFile.Succeeded);
            TestTrue(TEXT("Invalid Resource Inspector file returns a diagnostic"), !InvalidFile.Errors.IsEmpty());
            TestEqual(TEXT("Invalid Resource Inspector file retains the published revision"), View->GetRevision(), RevisionBeforeInvalidFile);
            const TSharedPtr<SWidget> InvalidSearchTag = FindTagged(Model->GetRoot(), TEXT("query"));
            const TSharedPtr<SSearchBox> InvalidSearch = InvalidSearchTag.IsValid() ? FindSearchBox(InvalidSearchTag.ToSharedRef()) : nullptr;
            TestTrue(TEXT("Invalid Resource Inspector file retains table, list, search, query, and selection"), View->GetTable(TEXT("inspector-dialog/content/resources")) == Table && Table->GetList() == List && InvalidSearch == Search && Model->GetQuery() == TEXT("Resource_00005") && Table->GetSelectedKey().IsSet() && Table->GetSelectedKey().GetValue() == TEXT("resource-00005"));

            const FCkUiLoadResult Recovery = View->ReloadFiles(MarkupPath, StylesheetPath);
            if (!TestTrue(*FString::Printf(TEXT("Installed files recover after invalid file document: %s"), *ErrorText(Recovery)), Recovery.Succeeded)) { return false; }
            Tick(Slate);
        }

        Search.Reset();
        List.Reset();
        Table.Reset();
        Collection.Reset();
        View.Reset();
        Model.Reset();
    }
    TestFalse(TEXT("Window teardown and model release break view/data callback ownership cycles"), WeakModel.IsValid());
    TestEqual(TEXT("Model test does not invoke close action incidentally"), CloseCalls, 0);
    return true;
}

#endif
