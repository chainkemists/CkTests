#include "CkCapabilityGalleryModel.h"

#include "CkSlateLayout/CkUiCheckbox.h"
#include "CkSlateLayout/CkUiDialog.h"
#include "CkSlateLayout/CkUiNumberInput.h"
#include "CkSlateLayout/CkUiSelect.h"
#include "CkSlateLayout/CkUiSlider.h"
#include "CkSlateLayout/CkUiTextInput.h"
#include "CkSlateLayout/SCkUiTable.h"
#include "CkSlateLayout/SCkUiTree.h"
#include "Algo/Reverse.h"
#include "Interfaces/IPluginManager.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Styling/CoreStyle.h"
#include "Widgets/SBoxPanel.h"

namespace ck_capability_gallery
{
auto ErrorText(const FCkUiLoadResult& InResult) -> FString
{
    return InResult.Errors.IsEmpty() ? TEXT("Capability Gallery setup failed.") : FString::Join(InResult.Errors, TEXT("\n"));
}
auto Text(const FString& InText) -> FCkUiFieldValue { return {.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(InText)}; }
auto Bool(const bool InValue) -> FCkUiFieldValue { return {.Kind = ECkUiFieldKind::Bool, .Bool = InValue}; }
auto Number(const float InValue) -> FCkUiFieldValue { return {.Kind = ECkUiFieldKind::Number, .Number = InValue}; }
auto Color(const FLinearColor InValue) -> FCkUiFieldValue { return {.Kind = ECkUiFieldKind::Color, .Color = InValue}; }

auto MakeSelectOptions() -> TArray<FCkUiRecordData>
{
    TArray<FCkUiRecordData> Options;
    for (const TCHAR* Key : {TEXT("compact"), TEXT("comfortable"), TEXT("dense")})
    {
        FCkUiRecordData& Option = Options.AddDefaulted_GetRef();
        Option.Key = Key;
        Option.Fields.Add(TEXT("label"), Text(Key));
    }
    return Options;
}

auto TryLoadInstalledResources(FString& OutMarkup, FString& OutStylesheet, FString& OutFailure) -> bool
{
    const TSharedPtr<IPlugin> Plugin = IPluginManager::Get().FindPlugin(TEXT("CkTests"));
    if (!Plugin.IsValid())
    {
        OutFailure = TEXT("CkTests plugin is unavailable.");
        return false;
    }

    const FString Resources = FPaths::Combine(Plugin->GetBaseDir(), TEXT("Resources/CapabilityGallery"));
    if (!FFileHelper::LoadFileToString(OutMarkup, *FPaths::Combine(Resources, TEXT("CapabilityGallery.ui.html")))
        || !FFileHelper::LoadFileToString(OutStylesheet, *FPaths::Combine(Resources, TEXT("CapabilityGallery.ui.css"))))
    {
        OutFailure = TEXT("Installed Capability Gallery resources could not be read.");
        return false;
    }
    return true;
}

class FSlotProbePreparedUpdate final : public ICkUiPreparedWidgetUpdate
{
public:
    virtual void Commit() noexcept override {}
};

class FSlotProbe final : public ICkUiRetainedWidget
{
public:
    FSlotProbe(const TSharedRef<SWidget>& InContent, const TSharedRef<SWidget>& InDetails)
        : _Content(InContent), _Details(InDetails)
    {
        _Root = SNew(SVerticalBox)
            + SVerticalBox::Slot().AutoHeight()[_Content.ToSharedRef()]
            + SVerticalBox::Slot().AutoHeight()[_Details.ToSharedRef()];
    }

    virtual auto GetWidget() const -> TSharedRef<SWidget> override { return _Root.ToSharedRef(); }

    virtual auto PrepareReload(const FCkUiCustomWidgetArguments& InArguments, FString& OutFailure) const -> TUniquePtr<ICkUiPreparedWidgetUpdate> override
    {
        if (InArguments.Slots.FindRef(TEXT("content")) != _Content || InArguments.Slots.FindRef(TEXT("details")) != _Details)
        {
            OutFailure = TEXT("Slot probe mounts changed during retained reload.");
            return nullptr;
        }
        if (InArguments.TextProperties.FindRef(TEXT("mode")).ToString() == TEXT("reject"))
        {
            OutFailure = TEXT("Slot probe rejected by PrepareReload.");
            return nullptr;
        }
        return MakeUnique<FSlotProbePreparedUpdate>();
    }

private:
    TSharedPtr<SWidget> _Content;
    TSharedPtr<SWidget> _Details;
    TSharedPtr<SWidget> _Root;
};

auto RegisterSlotProbe(FCkUiWidgetRegistry& InRegistry) -> FCkUiLoadResult
{
    auto Registration = FCkUiCustomWidgetRegistration{};
    Registration.Schema.Tag = TEXT("gallery-slot-probe");
    Registration.Schema.Properties = {{TEXT("mode"), ECkUiCustomPropertyKind::Text, true}};
    Registration.Schema.Slots = {{TEXT("content"), true}, {TEXT("details"), false}};
    Registration.RetainedFactory = [](const FCkUiCustomWidgetArguments& InArguments, FString& OutFailure) -> TSharedPtr<ICkUiRetainedWidget>
    {
        const TSharedPtr<SWidget> Content = InArguments.Slots.FindRef(TEXT("content"));
        const TSharedPtr<SWidget> Details = InArguments.Slots.FindRef(TEXT("details"));
        if (!Content.IsValid() || !Details.IsValid())
        {
            OutFailure = TEXT("Slot probe requires persistent content and details mounts.");
            return nullptr;
        }
        return MakeShared<FSlotProbe>(Content.ToSharedRef(), Details.ToSharedRef());
    };
    return InRegistry.Register(MoveTemp(Registration));
}

auto BatchPreviewMarkup(const TCHAR* InText) -> FString
{
    return FString::Printf(TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"batch-preview-root\"><text id=\"batch-preview-text\">%s</text><button id=\"batch-preview-action\" action=\"batch-preview-action\">Run preview action</button></column></region></ui>"), InText);
}

auto BatchPreviewInvalidMarkup() -> FString
{
    return TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"batch-preview-root\"><text id=\"batch-preview-text\" bind=\"batch-preview-text-missing\"/><button id=\"batch-preview-action\" action=\"batch-preview-action\">Run preview action</button></column></region></ui>");
}

auto MakeTableRecord(const int32 InIndex, const TSet<FString>& InUpdatedKeys) -> FCkUiRecordData
{
    FCkUiRecordData Record;
    Record.Key = FString::Printf(TEXT("record-%05d"), InIndex);
    const bool bUpdated = InUpdatedKeys.Contains(Record.Key);
    const int32 PaletteIndex = InIndex % 5;
    Record.Fields.Add(TEXT("name"), Text(FString::Printf(TEXT("Record %05d"), InIndex)));
    Record.Fields.Add(TEXT("text"), Text(bUpdated ? TEXT("Updated selected record") : TEXT("Typed data row")));
    Record.Fields.Add(TEXT("value"), Number(static_cast<float>(InIndex + 1)));
    Record.Fields.Add(TEXT("color"), Color(FLinearColor(0.15f + 0.15f * PaletteIndex, 0.55f, 0.9f, 1.0f)));
    Record.Fields.Add(TEXT("tooltip"), Text(TEXT("Stable keyed table record")));
    Record.Fields.Add(TEXT("expanded"), Bool(false));
    return Record;
}

auto MakeRepeatRecord(const int32 InIndex, const TSet<FString>& InUpdatedKeys, const TSet<FString>& InExpandedKeys) -> FCkUiRecordData
{
    FCkUiRecordData Record;
    Record.Key = FString::Printf(TEXT("record-%d"), InIndex);
    Record.Fields.Add(TEXT("name"), Text(FString::Printf(TEXT("Record %d"), InIndex + 1)));
    Record.Fields.Add(TEXT("text"), Text(InUpdatedKeys.Contains(Record.Key) ? TEXT("Updated repeat card") : TEXT("Typed repeat card")));
    Record.Fields.Add(TEXT("value"), Number(static_cast<float>(InIndex + 1)));
    Record.Fields.Add(TEXT("color"), Color(FLinearColor(0.15f + 0.2f * InIndex, 0.55f, 0.9f, 1.0f)));
    Record.Fields.Add(TEXT("tooltip"), Text(TEXT("Stable keyed repeat card")));
    Record.Fields.Add(TEXT("expanded"), Bool(InExpandedKeys.Contains(Record.Key)));
    return Record;
}

auto AddPageNode(TArray<FCkUiTreeNodeData>& InOutNodes, const TCHAR* InKey, const TCHAR* InLabel) -> void
{
    FCkUiTreeNodeData& Node = InOutNodes.AddDefaulted_GetRef();
    Node.Key = InKey;
    Node.Fields.Add(TEXT("label"), Text(InLabel));
}

auto AddTreeLabNode(TArray<FCkUiTreeNodeData>& InOutNodes, const FString& InKey, const TOptional<FString>& InParentKey, const TCHAR* InLabel) -> void
{
    FCkUiTreeNodeData& Node = InOutNodes.AddDefaulted_GetRef();
    Node.Key = InKey;
    Node.ParentKey = InParentKey;
    Node.Fields.Add(TEXT("label"), Text(InLabel));
}

auto TreeLabLabel(const FString& InKey) -> const TCHAR*
{
    if (InKey == TEXT("tree-alpha")) { return TEXT("Alpha"); }
    if (InKey == TEXT("tree-beta")) { return TEXT("Beta"); }
    return TEXT("Gamma");
}
}

auto FCkCapabilityGalleryModel::TryCreate(FSimpleDelegate InClose, TSharedPtr<FCkCapabilityGalleryModel>& OutModel, FString& OutError, const int32 InSlateUserIndex) -> bool
{
    OutModel.Reset();
    OutError.Reset();
    if (InSlateUserIndex < 0)
    {
        OutError = TEXT("Capability Gallery requires an explicit nonnegative Slate user.");
        return false;
    }

    const TSharedPtr<FCkCapabilityGalleryModel> Candidate = MakeShareable(new FCkCapabilityGalleryModel(MoveTemp(InClose)));
    FCkUiWidgetRegistry Registry;
    for (const FCkUiLoadResult& Registration : {
        FCkUiTextInput::Register(Registry), FCkUiCheckbox::Register(Registry), FCkUiNumberInput::Register(Registry),
        FCkUiSlider::Register(Registry), FCkUiSelect::Register(Registry), FCkUiDialog::Register(Registry), ck_capability_gallery::RegisterSlotProbe(Registry)})
    {
        if (!Registration.Succeeded)
        {
            OutError = ck_capability_gallery::ErrorText(Registration);
            return false;
        }
    }

    const auto CreateCollection = [&OutError](TArray<FCkUiFieldSchema> InSchema, TSharedPtr<FCkUiCollection>& OutCollection) -> bool
    {
        const FCkUiLoadResult Result = FCkUiCollection::TryCreate(MoveTemp(InSchema), OutCollection);
        if (!Result.Succeeded) { OutError = ck_capability_gallery::ErrorText(Result); }
        return Result.Succeeded;
    };
    if (!CreateCollection({{TEXT("label"), ECkUiFieldKind::Text}}, Candidate->_Options)
        || !CreateCollection({
            {TEXT("name"), ECkUiFieldKind::Text}, {TEXT("text"), ECkUiFieldKind::Text},
            {TEXT("value"), ECkUiFieldKind::Number}, {TEXT("color"), ECkUiFieldKind::Color},
            {TEXT("tooltip"), ECkUiFieldKind::Text}, {TEXT("expanded"), ECkUiFieldKind::Bool}}, Candidate->_Records)
        || !CreateCollection({
            {TEXT("name"), ECkUiFieldKind::Text}, {TEXT("text"), ECkUiFieldKind::Text},
            {TEXT("value"), ECkUiFieldKind::Number}, {TEXT("color"), ECkUiFieldKind::Color},
            {TEXT("tooltip"), ECkUiFieldKind::Text}, {TEXT("expanded"), ECkUiFieldKind::Bool}}, Candidate->_RepeatItems))
    {
        return false;
    }

    const FCkUiLoadResult NavigationCreationResult = FCkUiTreeCollection::TryCreate({{TEXT("label"), ECkUiFieldKind::Text}}, Candidate->_Navigation);
    const FCkUiLoadResult TreeLabResult = FCkUiTreeCollection::TryCreate({{TEXT("label"), ECkUiFieldKind::Text}}, Candidate->_TreeLab);
    if (!NavigationCreationResult.Succeeded || !TreeLabResult.Succeeded)
    {
        OutError = !NavigationCreationResult.Succeeded ? ck_capability_gallery::ErrorText(NavigationCreationResult) : ck_capability_gallery::ErrorText(TreeLabResult);
        return false;
    }

    const FCkUiLoadResult OptionsResult = Candidate->_Options->TrySetRecords(ck_capability_gallery::MakeSelectOptions());
    if (!OptionsResult.Succeeded)
    {
        OutError = ck_capability_gallery::ErrorText(OptionsResult);
        return false;
    }

    TArray<FCkUiTreeNodeData> NavigationNodes;
    ck_capability_gallery::AddPageNode(NavigationNodes, TEXT("layout"), TEXT("Layout"));
    ck_capability_gallery::AddPageNode(NavigationNodes, TEXT("forms"), TEXT("Forms"));
    ck_capability_gallery::AddPageNode(NavigationNodes, TEXT("data"), TEXT("Data"));
    ck_capability_gallery::AddPageNode(NavigationNodes, TEXT("collections"), TEXT("Collections"));
    ck_capability_gallery::AddPageNode(NavigationNodes, TEXT("commands"), TEXT("Commands"));
    ck_capability_gallery::AddPageNode(NavigationNodes, TEXT("composition"), TEXT("Composition"));
    const FCkUiLoadResult NavigationPublicationResult = Candidate->_Navigation->TrySetNodes(MoveTemp(NavigationNodes));
    if (!NavigationPublicationResult.Succeeded)
    {
        OutError = ck_capability_gallery::ErrorText(NavigationPublicationResult);
        return false;
    }
    if (!Candidate->PublishTableRecords(Candidate->_TableRecordCount, Candidate->_TableRecordsReversed,
        Candidate->_RemovedTableRecordKeys, Candidate->_UpdatedTableRecordKeys))
    {
        OutError = TEXT("Capability Gallery initial table record publication failed.");
        return false;
    }
    if (!Candidate->PublishRepeatItems(Candidate->_RepeatItemOrder, Candidate->_RemovedRepeatItemKeys,
        Candidate->_UpdatedRepeatItemKeys, Candidate->_ExpandedRecordKeys))
    {
        OutError = TEXT("Capability Gallery initial repeat item publication failed.");
        return false;
    }
    if (!Candidate->PublishTreeLab(Candidate->_TreeLabChildOrder))
    {
        OutError = TEXT("Capability Gallery initial tree lab publication failed.");
        return false;
    }

    const TWeakPtr<FCkCapabilityGalleryModel> Weak = Candidate;
    FCkUiView::FDataBindings BatchPreviewData;
    BatchPreviewData.SlateUserIndex = InSlateUserIndex;
    BatchPreviewData.CanDispatchEvents = TAttribute<bool>::CreateLambda([Weak]()
    {
        return Weak.IsValid();
    });
    FCkUiView::FActions BatchPreviewActions;
    BatchPreviewActions.Add(TEXT("batch-preview-action"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> Model = Weak.Pin())
        {
            ++Model->_BatchActionCount;
            Model->_BatchStatus = TEXT("Batch preview action invoked");
        }
    }));
    Candidate->_BatchPreviewView = FCkUiView::Create({}, MoveTemp(BatchPreviewActions), {}, FCoreStyle::GetDefaultFontStyle("Regular", 12), MoveTemp(BatchPreviewData), Registry.CreateSnapshot());
    Candidate->_BatchPreviewView->GetRegion(TEXT("main"));
    const FCkUiLoadResult BatchPreviewInitialLoad = Candidate->_BatchPreviewView->TryReload(ck_capability_gallery::BatchPreviewMarkup(TEXT("Batch preview ready")), TEXT(""), TEXT("CapabilityGallery batch preview initial"));
    if (!BatchPreviewInitialLoad.Succeeded)
    {
        OutError = ck_capability_gallery::ErrorText(BatchPreviewInitialLoad);
        return false;
    }

    FCkUiView::FDataBindings Data;
    Data.SlateUserIndex = InSlateUserIndex;
    const auto AddText = [&Data, Weak](const TCHAR* InName, auto InGetter) -> void
    {
        Data.Text.Add(InName, TAttribute<FText>::CreateLambda([Weak, InGetter]() -> FText
        {
            const TSharedPtr<FCkCapabilityGalleryModel> Model = Weak.Pin();
            return Model.IsValid() ? FText::FromString(InGetter(*Model)) : FText::GetEmpty();
        }));
    };
    AddText(TEXT("gallery-title"), [](const FCkCapabilityGalleryModel& M) { return FString::Printf(TEXT("Capability Gallery - %s"), *M._Page); });
    AddText(TEXT("gallery-status"), [](const FCkCapabilityGalleryModel& M) { return M._Status; });
    AddText(TEXT("gallery-reload-failure-kind"), [](const FCkCapabilityGalleryModel& M) { return M._ReloadFailureKind; });
    AddText(TEXT("gallery-reload-diagnostic"), [](const FCkCapabilityGalleryModel& M) { return M._ReloadDiagnostic; });
    AddText(TEXT("gallery-reload-revision"), [](const FCkCapabilityGalleryModel& M) { return LexToString(M.GetReloadRevision()); });
    AddText(TEXT("gallery-batch-status"), [](const FCkCapabilityGalleryModel& M) { return M.GetBatchStatus(); });
    AddText(TEXT("gallery-batch-revisions"), [](const FCkCapabilityGalleryModel& M)
    {
        return FString::Printf(TEXT("Main: %lld, preview: %lld"), M._View.IsValid() ? M._View->GetRevision() : 0,
            M._BatchPreviewView.IsValid() ? M._BatchPreviewView->GetRevision() : 0);
    });
    AddText(TEXT("gallery-batch-action-count"), [](const FCkCapabilityGalleryModel& M) { return LexToString(M.GetBatchActionCount()); });
    AddText(TEXT("gallery-slot-probe-status"), [](const FCkCapabilityGalleryModel& M) { return M.GetSlotProbeStatus(); });
    AddText(TEXT("gallery-slot-probe-details-state"), [](const FCkCapabilityGalleryModel& M) { return M.GetSlotProbeDetailsState(); });
    AddText(TEXT("gallery-slot-probe-action-count"), [](const FCkCapabilityGalleryModel& M) { return LexToString(M.GetSlotProbeDetailsActionCount()); });
    AddText(TEXT("gallery-slot-probe-content-action-count"), [](const FCkCapabilityGalleryModel& M) { return LexToString(M.GetSlotProbeContentActionCount()); });
    AddText(TEXT("gallery-summary"), [](const FCkCapabilityGalleryModel&) { return FString(TEXT("Production parser, retained view, typed bindings and shared adapters.")); });
    AddText(TEXT("gallery-error"), [](const FCkCapabilityGalleryModel& M) { return M._ErrorVisible ? FString(TEXT("Rejected reload demo preserves the accepted gallery; inspect host diagnostics.")) : FString(); });
    AddText(TEXT("gallery-tooltip"), [](const FCkCapabilityGalleryModel&) { return FString(TEXT("Typed collection record tooltip")); });
    AddText(TEXT("gallery-text"), [](const FCkCapabilityGalleryModel& M) { return M._EditableText; });
    AddText(TEXT("gallery-text-length"), [](const FCkCapabilityGalleryModel& M) { return LexToString(M._EditableText.Len()); });
    AddText(TEXT("gallery-committed-text"), [](const FCkCapabilityGalleryModel& M) { return M._CommittedText; });
    AddText(TEXT("gallery-text-error"), [](const FCkCapabilityGalleryModel& M) { return M._TextError; });
    AddText(TEXT("gallery-number-accepted"), [](const FCkCapabilityGalleryModel& M) { return FString::Printf(TEXT("Accepted value: %g"), M._Number); });
    AddText(TEXT("gallery-number-proposal"), [](const FCkCapabilityGalleryModel& M) { return FString::Printf(TEXT("Live proposal: %g"), M._NumberProposal); });
    AddText(TEXT("gallery-select-placeholder"), [](const FCkCapabilityGalleryModel&) { return FString(TEXT("No options available")); });
    AddText(TEXT("gallery-select-options-count"), [](const FCkCapabilityGalleryModel& M) { return FString::Printf(TEXT("Options: %d"), M.GetSelectOptionCount()); });
    AddText(TEXT("gallery-select-selected-key"), [](const FCkCapabilityGalleryModel& M)
    {
        return M._Select.IsEmpty() ? FString(TEXT("Requested key: none")) : FString::Printf(TEXT("Requested key: %s"), *M._Select);
    });
    AddText(TEXT("gallery-select-options-status"), [](const FCkCapabilityGalleryModel& M) { return M.GetSelectOptionsStatus(); });
    AddText(TEXT("gallery-color-label"), [](const FCkCapabilityGalleryModel&) { return FString(TEXT("Live color binding")); });
    AddText(TEXT("gallery-image-label"), [](const FCkCapabilityGalleryModel&) { return FString(TEXT("Core-style image binding")); });
    AddText(TEXT("gallery-layout-preview-status"), [](const FCkCapabilityGalleryModel& M)
    {
        return M.IsLayoutPreviewPopulated() ? FString(TEXT("Layout preview: populated")) : FString(TEXT("Layout preview: empty"));
    });
    AddText(TEXT("gallery-selection"), [](const FCkCapabilityGalleryModel& M) { return M._Selection; });
    AddText(TEXT("gallery-nested-tabs-details-label"), [](const FCkCapabilityGalleryModel& M)
    {
        return M.GetNestedTabsDetailsLabel();
    });
    AddText(TEXT("gallery-record-count"), [](const FCkCapabilityGalleryModel& M) { return LexToString(M.GetRecordCount()); });
    AddText(TEXT("gallery-selected-key"), [](const FCkCapabilityGalleryModel& M)
    {
        return M._Selection.IsEmpty() ? FString(TEXT("No record selected")) : M._Selection;
    });
    AddText(TEXT("gallery-context-action-count"), [](const FCkCapabilityGalleryModel& M) { return FString::Printf(TEXT("Context actions: %d"), M.GetContextActionCount()); });
    AddText(TEXT("gallery-context-action-key"), [](const FCkCapabilityGalleryModel& M) { return FString::Printf(TEXT("Context key: %s"), *M.GetContextActionKey()); });
    AddText(TEXT("gallery-tree-status"), [](const FCkCapabilityGalleryModel& M) { return M.GetTreeLabStatus(); });
    AddText(TEXT("gallery-tree-count"), [](const FCkCapabilityGalleryModel& M)
    {
        const TSharedPtr<FCkUiTreeCollection> TreeLab = M.GetTreeLabCollection();
        return LexToString(TreeLab.IsValid() ? TreeLab->GetNodes().Num() : 0);
    });
    AddText(TEXT("gallery-tree-selection"), [](const FCkCapabilityGalleryModel& M)
    {
        return M.GetTreeLabSelection().IsEmpty() ? FString(TEXT("No tree node selected")) : M.GetTreeLabSelection();
    });
    AddText(TEXT("gallery-unsupported-summary"), [](const FCkCapabilityGalleryModel&) { return FString(TEXT("Missing capabilities are listed here; this gallery does not substitute bespoke Slate controls.")); });

    Data.String.Add(TEXT("gallery-page"), TAttribute<FString>::CreateLambda([Weak]() { const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin(); return M.IsValid() ? M->_Page : FString(); }));
    Data.String.Add(TEXT("gallery-select"), TAttribute<FString>::CreateLambda([Weak]() { const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin(); return M.IsValid() ? M->_Select : FString(); }));
    Data.String.Add(TEXT("gallery-nested-tabs-selection"), TAttribute<FString>::CreateLambda([Weak]() { const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin(); return M.IsValid() ? M->_NestedTabsSelection : FString(); }));
    Data.Text.Add(TEXT("gallery-query"), TAttribute<FText>::CreateLambda([Weak]() { const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin(); return M.IsValid() ? FText::FromString(M->_Query) : FText::GetEmpty(); }));
    Data.Text.Add(TEXT("gallery-edit-text"), TAttribute<FText>::CreateLambda([Weak]() { const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin(); return M.IsValid() ? FText::FromString(M->_EditableText) : FText::GetEmpty(); }));
    Data.Text.Add(TEXT("gallery-nested-tabs-draft"), TAttribute<FText>::CreateLambda([Weak]() { const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin(); return M.IsValid() ? FText::FromString(M->_NestedTabsDraft) : FText::GetEmpty(); }));
    Data.Number.Add(TEXT("gallery-number"), TAttribute<float>::CreateLambda([Weak]() { const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin(); return M.IsValid() ? M->_Number : 0.0f; }));
    Data.Number.Add(TEXT("gallery-slider"), TAttribute<float>::CreateLambda([Weak]() { const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin(); return M.IsValid() ? M->_Slider : 0.0f; }));
    Data.Color.Add(TEXT("gallery-color"), TAttribute<FLinearColor>::CreateLambda([Weak]() { return Weak.IsValid() ? FLinearColor(0.18f, 0.65f, 0.95f) : FLinearColor::Transparent; }));
    Data.Images.Add(TEXT("gallery-image"), TAttribute<const FSlateBrush*>::CreateLambda([]() { return FCoreStyle::Get().GetBrush(TEXT("Checkerboard")); }));
    const auto AddVisibility = [&Data, Weak](const TCHAR* InName, auto InGetter) -> void
    {
        Data.Visibility.Add(InName, TAttribute<bool>::CreateLambda([Weak, InGetter]()
        {
            const TSharedPtr<FCkCapabilityGalleryModel> Model = Weak.Pin();
            return Model.IsValid() && InGetter(*Model);
        }));
    };
    AddVisibility(TEXT("gallery-enabled"), [](const FCkCapabilityGalleryModel& M) { return M._Enabled; });
    AddVisibility(TEXT("gallery-read-only"), [](const FCkCapabilityGalleryModel& M) { return M._ReadOnly; });
    AddVisibility(TEXT("gallery-layout-preview-populated"), [](const FCkCapabilityGalleryModel& M) { return M.IsLayoutPreviewPopulated(); });
    AddVisibility(TEXT("gallery-layout-preview-disabled-overlay"), [](const FCkCapabilityGalleryModel& M)
    {
        return M.IsLayoutPreviewPopulated() && M._ReadOnly;
    });
    AddVisibility(TEXT("gallery-dialog-open"), [](const FCkCapabilityGalleryModel& M) { return M._DialogOpen; });
    AddVisibility(TEXT("gallery-empty"), [](const FCkCapabilityGalleryModel& M) { return M.GetRecordCount() == 0; });
    AddVisibility(TEXT("gallery-has-selection"), [](const FCkCapabilityGalleryModel& M) { return !M._Selection.IsEmpty(); });
    AddVisibility(TEXT("gallery-can-reinsert-selected"), [](const FCkCapabilityGalleryModel& M) { return !M._LastRemovedRecordKey.IsEmpty(); });
    AddVisibility(TEXT("gallery-error-visible"), [](const FCkCapabilityGalleryModel& M) { return M._ErrorVisible; });
    AddVisibility(TEXT("gallery-text-error-visible"), [](const FCkCapabilityGalleryModel& M) { return !M._TextError.IsEmpty(); });
    AddVisibility(TEXT("gallery-unsupported-visible"), [](const FCkCapabilityGalleryModel& M) { return M._Page == TEXT("composition"); });
    AddVisibility(TEXT("gallery-nested-tabs-details-enabled"), [](const FCkCapabilityGalleryModel& M) { return M._NestedTabsDetailsEnabled; });
    Data.Collections.Add(TEXT("gallery-options"), Candidate->_Options);
    Data.Collections.Add(TEXT("gallery-records"), Candidate->_Records);
    Data.Collections.Add(TEXT("gallery-repeat-items"), Candidate->_RepeatItems);
    Data.Trees.Add(TEXT("gallery-navigation"), Candidate->_Navigation);
    Data.Trees.Add(TEXT("gallery-tree-lab"), Candidate->_TreeLab);

    Data.StringChanged.Add(TEXT("select-gallery-page"), FCkUiOnStringChanged::CreateLambda([Weak](const FString& V) { if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->SetPage(V); } }));
    Data.StringChanged.Add(TEXT("gallery-select-changed"), FCkUiOnStringChanged::CreateLambda([Weak](const FString& V) { if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->_Select = V; ++M->_SelectChangedCount; M->_Status = TEXT("Select updated"); } }));
    Data.StringChanged.Add(TEXT("gallery-nested-tabs-selection-changed"), FCkUiOnStringChanged::CreateLambda([Weak](const FString& V) { if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->SetNestedTabsSelection(V); } }));
    Data.TextChanged.Add(TEXT("gallery-query"), FOnTextChanged::CreateLambda([Weak](const FText& V) { if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->_Query = V.ToString(); M->_Status = TEXT("Query updated"); } }));
    Data.TextChanged.Add(TEXT("gallery-edit-text-changed"), FOnTextChanged::CreateLambda([Weak](const FText& V) { if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->SetEditableText(V.ToString(), false); } }));
    Data.TextChanged.Add(TEXT("gallery-nested-tabs-draft-changed"), FOnTextChanged::CreateLambda([Weak](const FText& V) { if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->SetNestedTabsDraft(V.ToString()); } }));
    Data.TextCommitted.Add(TEXT("gallery-edit-text-committed"), FOnTextCommitted::CreateLambda([Weak](const FText& V, ETextCommit::Type) { if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->SetEditableText(V.ToString(), true); } }));
    Data.TextCommitted.Add(TEXT("gallery-nested-tabs-draft-committed"), FOnTextCommitted::CreateLambda([Weak](const FText& V, ETextCommit::Type) { if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->SetNestedTabsDraft(V.ToString()); } }));
    Data.BoolChanged.Add(TEXT("gallery-checkbox-changed"), FCkUiOnBoolChanged::CreateLambda([Weak](const bool V) { if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->_ReadOnly = V; M->_Status = TEXT("Read-only updated"); } }));
    Data.NumberChanged.Add(TEXT("gallery-number-changed"), FCkUiOnNumberChanged::CreateLambda([Weak](const float V) { if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->_NumberProposal = V; } }));
    Data.NumberCommitted.Add(TEXT("gallery-number-committed"), FCkUiOnNumberCommitted::CreateLambda([Weak](const float V, ETextCommit::Type) { if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->_Number = V; M->_NumberProposal = V; ++M->_NumberCommitCount; M->_Status = TEXT("Number committed"); } }));
    Data.NumberInteraction.Add(TEXT("gallery-slider-interaction"), FCkUiOnNumberInteraction::CreateLambda([Weak](const FCkUiNumberInteraction& E) { if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->_Slider = E.Value; if (E.Phase == ECkUiInteractionPhase::Commit) { M->_Status = TEXT("Slider committed"); } } }));
    Data.TreeSelectionChanged.Add(TEXT("gallery-select-navigation"), FOnCkUiTreeSelectionChanged::CreateLambda([Weak](const TOptional<FString> K, ESelectInfo::Type) { if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin(); M.IsValid() && K.IsSet()) { M->SetPage(K.GetValue()); } }));
    Data.TreeSelectionChanged.Add(TEXT("gallery-tree-selected"), FOnCkUiTreeSelectionChanged::CreateLambda([Weak](const TOptional<FString> K, ESelectInfo::Type)
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin())
        {
            M->_TreeLabSelection = K.IsSet() ? K.GetValue() : FString{};
        }
    }));
    Data.TableSelectionChanged.Add(TEXT("gallery-select-record"), FOnCkUiTableSelectionChanged::CreateLambda([Weak](const TOptional<FString> K, ESelectInfo::Type)
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin())
        {
            if (K.IsSet()) { M->_Selection = K.GetValue(); }
            else { M->_Selection.Reset(); }
        }
    }));
    Data.ContextActions.Add(TEXT("gallery-context-inspect"), FOnCkUiContextAction::CreateLambda([Weak](const FString& K)
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin())
        {
            M->_ContextActionKey = K;
            ++M->_ContextActionCount;
            M->_Status = FString::Printf(TEXT("Context inspected %s"), *K);
        }
    }));
    Data.ItemActions.Add(TEXT("gallery-repeat-toggle"), FCkUiOnItemAction::CreateLambda([Weak](const FString& K) { if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->ToggleRepeat(K); } }));

    FCkUiView::FActions Actions;
    Actions.Add(TEXT("gallery-close"), FSimpleDelegate::CreateLambda([Weak]() { if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->_Close.ExecuteIfBound(); } }));
    Actions.Add(TEXT("gallery-reset"), FSimpleDelegate::CreateLambda([Weak]() { if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->Reset(); } }));
    Actions.Add(TEXT("gallery-show-dialog"), FSimpleDelegate::CreateLambda([Weak]() { if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->_DialogOpen = true; } }));
    Actions.Add(TEXT("gallery-dismiss-dialog"), FSimpleDelegate::CreateLambda([Weak]() { if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->_DialogOpen = false; } }));
    Actions.Add(TEXT("gallery-confirm-dialog"), FSimpleDelegate::CreateLambda([Weak]() { if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->_DialogOpen = false; M->_Status = TEXT("Dialog confirmed"); } }));
    Actions.Add(TEXT("gallery-toggle-enabled"), FSimpleDelegate::CreateLambda([Weak]() { if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->_Enabled = !M->_Enabled; } }));
    Actions.Add(TEXT("gallery-toggle-read-only"), FSimpleDelegate::CreateLambda([Weak]() { if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->_ReadOnly = !M->_ReadOnly; } }));
    Actions.Add(TEXT("gallery-toggle-layout-preview"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->ToggleLayoutPreview(); }
    }));
    Actions.Add(TEXT("gallery-slot-probe-content-action"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { ++M->_SlotProbeContentActionCount; }
    }));
    Actions.Add(TEXT("gallery-slot-probe-details-action"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { ++M->_SlotProbeDetailsActionCount; }
    }));
    Actions.Add(TEXT("gallery-slot-probe-omit-details"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->ReloadSlotProbe(false, false); }
    }));
    Actions.Add(TEXT("gallery-slot-probe-reinsert-details"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->ReloadSlotProbe(true, false); }
    }));
    Actions.Add(TEXT("gallery-slot-probe-reject-reload"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->ReloadSlotProbe(true, true); }
    }));
    Actions.Add(TEXT("gallery-toggle-empty"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin())
        {
            M->SetTableCount(M->GetRecordCount() == 0 ? 3 : 0);
        }
    }));
    Actions.Add(TEXT("gallery-select-empty"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->EmptySelectOptions(); }
    }));
    Actions.Add(TEXT("gallery-select-restore"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->RestoreSelectOptions(); }
    }));
    Actions.Add(TEXT("gallery-nested-tabs-toggle-details"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->ToggleNestedTabsDetailsEnabled(); }
    }));
    Actions.Add(TEXT("gallery-nested-tabs-toggle-long-label"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->ToggleNestedTabsLongLabel(); }
    }));
    Actions.Add(TEXT("gallery-nested-tabs-reset"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->ResetNestedTabsLab(); }
    }));
    const auto AddTableCountAction = [&Actions, Weak](const TCHAR* InName, const int32 InCount) -> void
    {
        Actions.Add(InName, FSimpleDelegate::CreateLambda([Weak, InCount]()
        {
            if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->SetTableCount(InCount); }
        }));
    };
    AddTableCountAction(TEXT("gallery-data-count-0"), 0);
    AddTableCountAction(TEXT("gallery-data-count-1"), 1);
    AddTableCountAction(TEXT("gallery-data-count-12"), 12);
    AddTableCountAction(TEXT("gallery-data-count-1000"), 1000);
    AddTableCountAction(TEXT("gallery-data-count-10000"), 10000);
    Actions.Add(TEXT("gallery-data-reverse"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->ReverseTableRecords(); }
    }));
    Actions.Add(TEXT("gallery-data-update-selected"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->UpdateSelectedRecord(); }
    }));
    Actions.Add(TEXT("gallery-data-remove-selected"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->RemoveSelectedRecord(); }
    }));
    Actions.Add(TEXT("gallery-data-reinsert-selected"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->ReinsertSelectedRecord(); }
    }));
    Actions.Add(TEXT("gallery-repeat-reverse"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->ReverseRepeatItems(); }
    }));
    Actions.Add(TEXT("gallery-repeat-update"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->UpdateRepeatRecordZero(); }
    }));
    Actions.Add(TEXT("gallery-repeat-remove"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->RemoveRepeatRecordZero(); }
    }));
    Actions.Add(TEXT("gallery-repeat-reinsert"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->ReinsertRepeatRecord(); }
    }));
    Actions.Add(TEXT("gallery-repeat-reset"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->ResetRepeatItems(); }
    }));
    Actions.Add(TEXT("gallery-tree-insert"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->InsertTreeLabNode(); }
    }));
    Actions.Add(TEXT("gallery-tree-reverse"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->ReverseTreeLabNodes(); }
    }));
    Actions.Add(TEXT("gallery-tree-remove-selected"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->RemoveSelectedTreeLabNode(); }
    }));
    Actions.Add(TEXT("gallery-tree-reinsert"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->ReinsertTreeLabNode(); }
    }));
    Actions.Add(TEXT("gallery-tree-reset"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->ResetTreeLab(); }
    }));
    Actions.Add(TEXT("gallery-load-invalid-draft"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin())
        {
            M->SetEditableText(TEXT("01234567890123456789012345678901234567890123456789012345678901234"), false);
        }
    }));
    Actions.Add(TEXT("gallery-recover-valid-draft"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->SetEditableText(TEXT("Recovered valid draft"), false); }
    }));
    Actions.Add(TEXT("gallery-commit-edit-text"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->SetEditableText(M->_EditableText, true); }
    }));
    Actions.Add(TEXT("gallery-accepted-reload"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->RunAcceptedReload(); }
    }));
    Actions.Add(TEXT("gallery-batch-accept"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->RunBatchAccept(); }
    }));
    Actions.Add(TEXT("gallery-batch-reject-second"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->RunBatchRejectSecond(); }
    }));
    Actions.Add(TEXT("gallery-rejected-reload"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->RunRejectedReload(TEXT("Missing required action")); }
    }));
    Actions.Add(TEXT("gallery-rejected-reload-markup"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->RunRejectedReload(TEXT("Malformed markup")); }
    }));
    Actions.Add(TEXT("gallery-rejected-reload-binding"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->RunRejectedReload(TEXT("Missing text binding")); }
    }));
    Actions.Add(TEXT("gallery-rejected-reload-style"), FSimpleDelegate::CreateLambda([Weak]()
    {
        if (const TSharedPtr<FCkCapabilityGalleryModel> M = Weak.Pin()) { M->RunRejectedReload(TEXT("Unsupported style")); }
    }));

    FCkUiView::FNativeBindings Bindings;
    Bindings.Add(TEXT("gallery-batch-preview"), Candidate->_BatchPreviewView->GetRegion(TEXT("main")));
    Candidate->_View = FCkUiView::Create(MoveTemp(Bindings), MoveTemp(Actions), {}, FCoreStyle::GetDefaultFontStyle("Regular", 12), MoveTemp(Data), Registry.CreateSnapshot());
    Candidate->_View->GetRegion(TEXT("main"));
    OutModel = Candidate;
    return true;
}

auto FCkCapabilityGalleryModel::GetRoot() const -> TSharedRef<SWidget> { return GetView()->GetRegion(TEXT("main")); }

auto FCkCapabilityGalleryModel::IsSlotProbeDetailsPresent() const -> bool
{
    return _View.IsValid() && _View->GetScroll(TEXT("gallery-dialog/content/gallery-slot-probe/details/slot-probe-details")).IsValid();
}

auto FCkCapabilityGalleryModel::GetSlotProbeDetailsState() const -> FString
{
    return IsSlotProbeDetailsPresent() ? TEXT("Slot probe details: present") : TEXT("Slot probe details: omitted");
}

auto FCkCapabilityGalleryModel::GetSlotProbeStatus() const -> FString
{
    if (!_SlotProbeFailure.IsEmpty() && _View.IsValid() && _View->GetRevision() == _SlotProbeFailureRevision)
    {
        return _SlotProbeFailure;
    }
    return IsSlotProbeDetailsPresent() ? TEXT("Slot probe details present") : TEXT("Slot probe details omitted");
}


auto FCkCapabilityGalleryModel::ReloadSlotProbe(const bool bIncludeDetails, const bool bReject) -> void
{
    FString Markup;
    FString Stylesheet;
    FString SetupFailure;
    const FString ProbeMarker = TEXT("<gallery-slot-probe id=\"gallery-slot-probe\" mode=\"ready\" class=\"slot-probe\">");
    const FString DetailsSlot = TEXT("<slot name=\"details\"><scroll id=\"slot-probe-details\" direction=\"vertical\" class=\"slot-probe-details\"><column id=\"slot-probe-details-content\"><text id=\"slot-probe-details-copy\" class=\"description\">Optional authored details are mounted by the retained probe.</text><button id=\"slot-probe-details-action\" action=\"gallery-slot-probe-details-action\">Run details action</button></column></scroll></slot>");
    if (!_View.IsValid() || !ck_capability_gallery::TryLoadInstalledResources(Markup, Stylesheet, SetupFailure))
    {
        _SlotProbeFailure = SetupFailure.IsEmpty() ? TEXT("Slot probe setup failed; no reload was attempted.") : SetupFailure;
        _SlotProbeFailureRevision = _View.IsValid() ? _View->GetRevision() : INDEX_NONE;
        return;
    }
    bool bPreparedMarkup = Markup.Contains(ProbeMarker, ESearchCase::CaseSensitive);
    if (bPreparedMarkup && !bReject && !bIncludeDetails)
    {
        bPreparedMarkup = Markup.ReplaceInline(*DetailsSlot, TEXT(""), ESearchCase::CaseSensitive) == 1;
    }
    if (bPreparedMarkup && bReject)
    {
        bPreparedMarkup = Markup.ReplaceInline(*ProbeMarker,
            TEXT("<gallery-slot-probe id=\"gallery-slot-probe\" mode=\"reject\" class=\"slot-probe\">"), ESearchCase::CaseSensitive) == 1;
    }
    if (!bPreparedMarkup)
    {
        _SlotProbeFailure = TEXT("Slot probe setup marker is missing; no reload was attempted.");
        _SlotProbeFailureRevision = _View->GetRevision();
        return;
    }
    const FCkUiLoadResult Result = _View->TryReload(Markup, Stylesheet, TEXT("CapabilityGallery slot probe"));
    if (Result.Succeeded)
    {
        _SlotProbeFailure.Reset();
        _SlotProbeFailureRevision = INDEX_NONE;
        return;
    }
    _SlotProbeFailure = FString::Printf(TEXT("Slot probe reload rejected: %s"), *ck_capability_gallery::ErrorText(Result));
    _SlotProbeFailureRevision = _View->GetRevision();
}

auto FCkCapabilityGalleryModel::RunAcceptedReload() -> void
{
    FString Markup;
    FString Stylesheet;
    FString SetupFailure;
    if (!ck_capability_gallery::TryLoadInstalledResources(Markup, Stylesheet, SetupFailure))
    {
        _ErrorVisible = true;
        _ReloadFailureKind = TEXT("Setup failure");
        _ReloadDiagnostic = SetupFailure;
        _Status = TEXT("Reload lab setup failed; accepted gallery remains active");
        return;
    }

    const FString DescriptionMarker = TEXT("<text id=\"commands-description\" class=\"description\">Commands dispatch through named host actions. The menu uses native Slate menus, not browser emulation.</text>");
    const FString CompatibleDescription = TEXT("<text id=\"commands-description\" class=\"description\">Compatible reload applied.</text>");
    if (!Markup.Contains(DescriptionMarker, ESearchCase::CaseSensitive))
    {
        _ErrorVisible = true;
        _ReloadFailureKind = TEXT("Setup failure");
        _ReloadDiagnostic = TEXT("Installed Capability Gallery marker is missing; no reload was attempted.");
        _Status = TEXT("Reload lab setup failed; accepted gallery remains active");
        return;
    }

    Markup.ReplaceInline(*DescriptionMarker, *CompatibleDescription, ESearchCase::CaseSensitive);
    const FCkUiLoadResult Result = _View->TryReload(Markup, Stylesheet, TEXT("CapabilityGallery accepted reload lab"));
    const FCkUiLoadResult& LastResult = _View->GetLastResult();
    _ErrorVisible = !LastResult.Succeeded;
    _ReloadFailureKind = LastResult.Succeeded ? TEXT("Compatible reload") : TEXT("Compatible reload rejected");
    _ReloadDiagnostic = LastResult.Succeeded ? TEXT("Compatible reload applied.") : ck_capability_gallery::ErrorText(LastResult);
    _Status = Result.Succeeded ? TEXT("Compatible reload applied") : TEXT("Compatible reload was rejected; accepted gallery remains active");
}

auto FCkCapabilityGalleryModel::RunBatchAccept() -> void
{
    FString Markup;
    FString Stylesheet;
    FString SetupFailure;
    const FString ReadyMarker = TEXT("<text id=\"batch-main-state\" class=\"description\">Batch main ready</text>");
    const FString AcceptedMarker = TEXT("<text id=\"batch-main-state\" class=\"description\">Batch main accepted</text>");
    if (!_View.IsValid() || !_BatchPreviewView.IsValid() || !ck_capability_gallery::TryLoadInstalledResources(Markup, Stylesheet, SetupFailure))
    {
        _BatchStatus = SetupFailure.IsEmpty()
            ? TEXT("Batch setup failed; no batch was attempted")
            : FString::Printf(TEXT("Batch setup failed; no batch was attempted: %s"), *SetupFailure);
        return;
    }
    if (Markup.ReplaceInline(*ReadyMarker, *AcceptedMarker, ESearchCase::CaseSensitive) != 1)
    {
        _BatchStatus = TEXT("Batch setup failed; batch main ready marker is missing; no batch was attempted");
        return;
    }
    const FCkUiLoadResult Result = FCkUiView::TryReloadBatch({
        {_View, MoveTemp(Markup), MoveTemp(Stylesheet), TEXT("CapabilityGallery batch main accepted")},
        {_BatchPreviewView, ck_capability_gallery::BatchPreviewMarkup(TEXT("Batch preview accepted")), TEXT(""), TEXT("CapabilityGallery batch preview accepted")},
    });
    _BatchStatus = Result.Succeeded ? TEXT("Batch accepted") : FString::Printf(TEXT("Batch acceptance rejected: %s"), *ck_capability_gallery::ErrorText(Result));
}

auto FCkCapabilityGalleryModel::RunBatchRejectSecond() -> void
{
    FString Markup;
    FString Stylesheet;
    FString SetupFailure;
    const FString ReadyMarker = TEXT("<text id=\"batch-main-state\" class=\"description\">Batch main ready</text>");
    const FString RejectedMarker = TEXT("<text id=\"batch-main-state\" class=\"description\">Batch main must not publish</text>");
    if (!_View.IsValid() || !_BatchPreviewView.IsValid() || !ck_capability_gallery::TryLoadInstalledResources(Markup, Stylesheet, SetupFailure))
    {
        _BatchStatus = SetupFailure.IsEmpty()
            ? TEXT("Batch setup failed; no batch was attempted")
            : FString::Printf(TEXT("Batch setup failed; no batch was attempted: %s"), *SetupFailure);
        return;
    }
    if (Markup.ReplaceInline(*ReadyMarker, *RejectedMarker, ESearchCase::CaseSensitive) != 1)
    {
        _BatchStatus = TEXT("Batch setup failed; batch main ready marker is missing; no batch was attempted");
        return;
    }
    const FCkUiLoadResult Result = FCkUiView::TryReloadBatch({
        {_View, MoveTemp(Markup), MoveTemp(Stylesheet), TEXT("CapabilityGallery batch main rejected")},
        {_BatchPreviewView, ck_capability_gallery::BatchPreviewInvalidMarkup(), TEXT(""), TEXT("CapabilityGallery batch preview rejected")},
    });
    _BatchStatus = Result.Succeeded ? TEXT("Batch candidate unexpectedly accepted")
        : FString::Printf(TEXT("Batch rejected by second preview: %s"), *ck_capability_gallery::ErrorText(Result));
}

auto FCkCapabilityGalleryModel::RunRejectedReload(const FString& InFailureKind) -> void
{
    FString Markup;
    FString Stylesheet;
    FString SetupFailure;
    if (!ck_capability_gallery::TryLoadInstalledResources(Markup, Stylesheet, SetupFailure))
    {
        _ErrorVisible = true;
        _ReloadFailureKind = TEXT("Setup failure");
        _ReloadDiagnostic = SetupFailure;
        _Status = TEXT("Reload lab setup failed; accepted gallery remains active");
        return;
    }

    const FString TitleMarker = TEXT("<text id=\"gallery-title\" bind=\"gallery-title\" class=\"title\" />");
    const FString CloseMarker = TEXT("<button id=\"gallery-close\" action=\"gallery-close\">Close</button>");
    const FString StylesheetMarker = TEXT(".gallery-root {");
    bool CandidateReady = false;
    if (InFailureKind == TEXT("Malformed markup"))
    {
        CandidateReady = Markup.Contains(TitleMarker, ESearchCase::CaseSensitive);
        if (CandidateReady) { Markup.ReplaceInline(*TitleMarker, TEXT("<text id=\"gallery-title\" bind=\"gallery-title\" class=\"title\">"), ESearchCase::CaseSensitive); }
    }
    else if (InFailureKind == TEXT("Missing text binding"))
    {
        CandidateReady = Markup.Contains(TitleMarker, ESearchCase::CaseSensitive);
        if (CandidateReady) { Markup.ReplaceInline(*TitleMarker, TEXT("<text id=\"gallery-title\" bind=\"gallery-title-missing\" class=\"title\" />"), ESearchCase::CaseSensitive); }
    }
    else if (InFailureKind == TEXT("Missing required action"))
    {
        CandidateReady = Markup.Contains(CloseMarker, ESearchCase::CaseSensitive);
        if (CandidateReady) { Markup.ReplaceInline(*CloseMarker, TEXT("<button id=\"gallery-close\" action=\"gallery-close-missing\">Close</button>"), ESearchCase::CaseSensitive); }
    }
    else if (InFailureKind == TEXT("Unsupported style"))
    {
        CandidateReady = Stylesheet.Contains(StylesheetMarker, ESearchCase::CaseSensitive);
        if (CandidateReady) { Stylesheet += TEXT("\n.gallery-root { unsupported-reload-property: 1px; }\n"); }
    }

    if (!CandidateReady)
    {
        _ErrorVisible = true;
        _ReloadFailureKind = TEXT("Setup failure");
        _ReloadDiagnostic = TEXT("Installed Capability Gallery marker is missing; no reload was attempted.");
        _Status = TEXT("Reload lab setup failed; accepted gallery remains active");
        return;
    }

    const FCkUiLoadResult Result = _View->TryReload(Markup, Stylesheet, TEXT("CapabilityGallery rejected reload lab"));
    const FCkUiLoadResult& LastResult = _View->GetLastResult();
    _ErrorVisible = true;
    _ReloadFailureKind = InFailureKind;
    _ReloadDiagnostic = LastResult.Succeeded ? TEXT("Candidate unexpectedly loaded.") : ck_capability_gallery::ErrorText(LastResult);
    _Status = Result.Succeeded ? TEXT("Unexpected reload acceptance") : TEXT("Rejected reload preserved the accepted gallery");
}

auto FCkCapabilityGalleryModel::EmptySelectOptions() -> void
{
    if (!_Options.IsValid() || !_Options->TrySetRecords({}).Succeeded)
    {
        _SelectOptionsStatus = TEXT("Select options clear rejected");
        _Status = _SelectOptionsStatus;
        return;
    }

    _SelectOptionsStatus = FString::Printf(TEXT("Options cleared; requested key remains %s"), *_Select);
    _Status = TEXT("Select options cleared");
}

auto FCkCapabilityGalleryModel::RestoreSelectOptions() -> void
{
    if (!_Options.IsValid() || !_Options->TrySetRecords(ck_capability_gallery::MakeSelectOptions()).Succeeded)
    {
        _SelectOptionsStatus = TEXT("Select options restore rejected");
        _Status = _SelectOptionsStatus;
        return;
    }

    _SelectOptionsStatus = FString::Printf(TEXT("Options restored; requested key %s resolved"), *_Select);
    _Status = TEXT("Select options restored");
}

void FCkCapabilityGalleryModel::Reset()
{
    if (!_Options.IsValid() || !_Options->TrySetRecords(ck_capability_gallery::MakeSelectOptions()).Succeeded)
    {
        _SelectOptionsStatus = TEXT("Select options reset rejected");
        _Status = _SelectOptionsStatus;
        return;
    }

    _Page = TEXT("layout");
    _Query.Reset();
    _Select = TEXT("compact");
    _SelectOptionsStatus = TEXT("Options ready");
    _EditableText = TEXT("Editable text");
    _CommittedText = _EditableText;
    _TextError.Reset();
    _Status = TEXT("Reset");
    _Number = 24.0f;
    _NumberProposal = _Number;
    _SelectChangedCount = 0;
    _NumberCommitCount = 0;
    _ContextActionKey = TEXT("No context item inspected");
    _ContextActionCount = 0;
    _Slider = 0.5f;
    _Enabled = true;
    _ReadOnly = false;
    _LayoutPreviewPopulated = true;
    _DialogOpen = false;
    _ErrorVisible = false;
    const auto ResetRemovedKeys = TSet<FString>{};
    const auto ResetUpdatedKeys = TSet<FString>{};
    if (PublishTableRecords(3, false, ResetRemovedKeys, ResetUpdatedKeys))
    {
        _TableRecordCount = 3;
        _TableRecordsReversed = false;
        _RemovedTableRecordKeys = ResetRemovedKeys;
        _UpdatedTableRecordKeys = ResetUpdatedKeys;
        _LastRemovedRecordKey.Reset();
        const TSharedPtr<SCkUiTable> Table = GetRecordsTable();
        if (Table.IsValid() && !Table->TrySelectKey(TOptional<FString>{}, false))
        {
            _Status = TEXT("Table reset selection clear rejected");
        }
        SyncSelectionFromTable();
    }
    else
    {
        _Status = TEXT("Table reset rejected");
    }

    const FString StatusBeforeRepeatReset = _Status;
    ResetRepeatItems();
    if (_Status == TEXT("Repeat lab reset")) { _Status = StatusBeforeRepeatReset; }
}
auto FCkCapabilityGalleryModel::SetPage(const FString& InPage) -> bool
{
    static const TSet<FString> SupportedPages{TEXT("layout"), TEXT("forms"), TEXT("data"), TEXT("collections"), TEXT("commands"), TEXT("composition")};
    if (!SupportedPages.Contains(InPage)) { return false; }
    _Page = InPage; _Status = TEXT("Page selected"); return true;
}
void FCkCapabilityGalleryModel::ToggleLayoutPreview()
{
    _LayoutPreviewPopulated = !_LayoutPreviewPopulated;
    _Status = _LayoutPreviewPopulated ? TEXT("Layout preview populated") : TEXT("Layout preview emptied");
}

void FCkCapabilityGalleryModel::SetEditableText(const FString& InText, const bool bCommit)
{
    const bool bWasInvalid = !_TextError.IsEmpty();
    _EditableText = InText;
    if (InText.Len() > 64)
    {
        _TextError = TEXT("Text must be 64 characters or fewer.");
        _Status = TEXT("Text draft invalid");
        return;
    }
    _TextError.Reset();
    if (bCommit)
    {
        _CommittedText = InText;
        _Status = TEXT("Text committed");
        return;
    }
    _Status = bWasInvalid ? TEXT("Text draft recovered") : TEXT("Text draft updated");
}
void FCkCapabilityGalleryModel::SetNestedTabsSelection(const FString& InSelection)
{
    static const TSet<FString> SupportedSelections{TEXT("overview"), TEXT("details"), TEXT("history")};
    if (!SupportedSelections.Contains(InSelection) || (InSelection == TEXT("details") && !_NestedTabsDetailsEnabled))
    {
        return;
    }
    _NestedTabsSelection = InSelection;
    ++_NestedTabsSelectionChangedCount;
    _Status = TEXT("Nested tab selected");
}

void FCkCapabilityGalleryModel::SetNestedTabsDraft(const FString& InDraft)
{
    _NestedTabsDraft = InDraft;
    ++_NestedTabsDraftChangedCount;
    _Status = TEXT("Nested Details draft updated");
}

void FCkCapabilityGalleryModel::ToggleNestedTabsDetailsEnabled()
{
    if (_NestedTabsDetailsEnabled && _NestedTabsSelection == TEXT("details"))
    {
        _NestedTabsSelection = TEXT("overview");
    }
    _NestedTabsDetailsEnabled = !_NestedTabsDetailsEnabled;
    _Status = _NestedTabsDetailsEnabled ? TEXT("Nested Details enabled") : TEXT("Nested Details disabled");
}

void FCkCapabilityGalleryModel::ToggleNestedTabsLongLabel()
{
    _NestedTabsLongLabel = !_NestedTabsLongLabel;
    _Status = TEXT("Nested Details label updated");
}

void FCkCapabilityGalleryModel::ResetNestedTabsLab()
{
    _NestedTabsSelection = TEXT("overview");
    _NestedTabsDetailsEnabled = true;
    _NestedTabsLongLabel = false;
    _NestedTabsDraft = TEXT("Draft text stays with this Details panel.");
    _NestedTabsSelectionChangedCount = 0;
    _NestedTabsDraftChangedCount = 0;
    _Status = TEXT("Nested tabs reset");
}

void FCkCapabilityGalleryModel::SetTableCount(const int32 InCount)
{
    if (InCount < 0 || InCount > 10000)
    {
        _Status = TEXT("Table count update rejected");
        return;
    }

    const auto NextRemovedKeys = TSet<FString>{};
    const auto NextUpdatedKeys = TSet<FString>{};
    if (!PublishTableRecords(InCount, _TableRecordsReversed, NextRemovedKeys, NextUpdatedKeys))
    {
        _Status = TEXT("Table count update rejected");
        return;
    }

    _TableRecordCount = InCount;
    _RemovedTableRecordKeys = NextRemovedKeys;
    _UpdatedTableRecordKeys = NextUpdatedKeys;
    _LastRemovedRecordKey.Reset();
    SyncSelectionFromTable();
    _Status = FString::Printf(TEXT("Table count set to %d"), InCount);
}

void FCkCapabilityGalleryModel::ReverseTableRecords()
{
    const bool bNextReversed = !_TableRecordsReversed;
    if (!PublishTableRecords(_TableRecordCount, bNextReversed, _RemovedTableRecordKeys, _UpdatedTableRecordKeys))
    {
        _Status = TEXT("Table reverse rejected");
        return;
    }

    _TableRecordsReversed = bNextReversed;
    SyncSelectionFromTable();
    _Status = TEXT("Table order reversed");
}

void FCkCapabilityGalleryModel::UpdateSelectedRecord()
{
    if (_Selection.IsEmpty() || !HasRecord(_Selection))
    {
        _Status = TEXT("Selected record update rejected");
        return;
    }

    TSet<FString> NextUpdatedKeys = _UpdatedTableRecordKeys;
    NextUpdatedKeys.Add(_Selection);
    if (!PublishTableRecords(_TableRecordCount, _TableRecordsReversed, _RemovedTableRecordKeys, NextUpdatedKeys))
    {
        _Status = TEXT("Selected record update rejected");
        return;
    }

    _UpdatedTableRecordKeys = MoveTemp(NextUpdatedKeys);
    _Status = FString::Printf(TEXT("Updated %s"), *_Selection);
}

void FCkCapabilityGalleryModel::RemoveSelectedRecord()
{
    if (_Selection.IsEmpty() || !HasRecord(_Selection))
    {
        _Status = TEXT("Selected record removal rejected");
        return;
    }

    const FString SelectedKey = _Selection;
    TSet<FString> NextRemovedKeys = _RemovedTableRecordKeys;
    NextRemovedKeys.Add(SelectedKey);
    if (!PublishTableRecords(_TableRecordCount, _TableRecordsReversed, NextRemovedKeys, _UpdatedTableRecordKeys))
    {
        _Status = TEXT("Selected record removal rejected");
        return;
    }

    _RemovedTableRecordKeys = MoveTemp(NextRemovedKeys);
    _LastRemovedRecordKey = SelectedKey;
    _Selection.Reset();
    _Status = FString::Printf(TEXT("Removed %s"), *SelectedKey);
}

void FCkCapabilityGalleryModel::ReinsertSelectedRecord()
{
    if (_LastRemovedRecordKey.IsEmpty() || !_RemovedTableRecordKeys.Contains(_LastRemovedRecordKey))
    {
        _Status = TEXT("Selected record reinsertion rejected");
        return;
    }

    const FString ReinsertedKey = _LastRemovedRecordKey;
    TSet<FString> NextRemovedKeys = _RemovedTableRecordKeys;
    NextRemovedKeys.Remove(ReinsertedKey);
    if (!PublishTableRecords(_TableRecordCount, _TableRecordsReversed, NextRemovedKeys, _UpdatedTableRecordKeys))
    {
        _Status = TEXT("Selected record reinsertion rejected");
        return;
    }

    _RemovedTableRecordKeys = MoveTemp(NextRemovedKeys);
    _LastRemovedRecordKey.Reset();
    _Status = FString::Printf(TEXT("Reinserted %s"), *ReinsertedKey);
}

auto FCkCapabilityGalleryModel::PublishTableRecords(const int32 InCount, const bool bReverse,
    const TSet<FString>& InRemovedKeys, const TSet<FString>& InUpdatedKeys) -> bool
{
    if (!_Records.IsValid() || InCount < 0) { return false; }
    TArray<FCkUiRecordData> Records;
    Records.Reserve(InCount);
    for (int32 Index = 0; Index < InCount; ++Index)
    {
        if (!InRemovedKeys.Contains(FString::Printf(TEXT("record-%05d"), Index)))
        {
            Records.Add(ck_capability_gallery::MakeTableRecord(Index, InUpdatedKeys));
        }
    }
    if (bReverse) { Algo::Reverse(Records); }
    return _Records->TrySetRecords(MoveTemp(Records)).Succeeded;
}

auto FCkCapabilityGalleryModel::PublishRepeatItems(const TArray<FString>& InOrder, const TSet<FString>& InRemovedKeys,
    const TSet<FString>& InUpdatedKeys, const TSet<FString>& InExpandedKeys) -> bool
{
    if (!_RepeatItems.IsValid()) { return false; }
    TArray<FCkUiRecordData> Records;
    Records.Reserve(InOrder.Num());
    for (const FString& Key : InOrder)
    {
        int32 Index = INDEX_NONE;
        const FString Prefix = TEXT("record-");
        if (!Key.StartsWith(Prefix) || !LexTryParseString(Index, *Key.RightChop(Prefix.Len())) || Index < 0 || Index > 2) { return false; }
        const FString RecordKey = FString::Printf(TEXT("record-%d"), Index);
        if (!InRemovedKeys.Contains(RecordKey)) { Records.Add(ck_capability_gallery::MakeRepeatRecord(Index, InUpdatedKeys, InExpandedKeys)); }
    }
    return _RepeatItems->TrySetRecords(MoveTemp(Records)).Succeeded;
}

auto FCkCapabilityGalleryModel::PublishTreeLab(const TArray<FString>& InChildOrder) -> bool
{
    if (!_TreeLab.IsValid()) { return false; }
    TArray<FCkUiTreeNodeData> Nodes;
    Nodes.Reserve(InChildOrder.Num() + 1);
    ck_capability_gallery::AddTreeLabNode(Nodes, TEXT("tree-root"), {}, TEXT("Root"));
    for (const FString& Key : InChildOrder)
    {
        if (Key != TEXT("tree-alpha") && Key != TEXT("tree-beta") && Key != TEXT("tree-gamma")) { return false; }
        ck_capability_gallery::AddTreeLabNode(Nodes, Key, FString(TEXT("tree-root")), ck_capability_gallery::TreeLabLabel(Key));
    }
    return _TreeLab->TrySetNodes(MoveTemp(Nodes)).Succeeded;
}

auto FCkCapabilityGalleryModel::GetRecordsTable() const -> TSharedPtr<SCkUiTable>
{
    if (!_View.IsValid()) { return {}; }
    return _View->GetTable(TEXT("gallery-dialog/content/gallery-records"));
}

auto FCkCapabilityGalleryModel::GetTreeLab() const -> TSharedPtr<SCkUiTree>
{
    return _View.IsValid() ? _View->GetTree(TEXT("gallery-dialog/content/gallery-tree-lab")) : nullptr;
}

void FCkCapabilityGalleryModel::SyncSelectionFromTable()
{
    if (const TSharedPtr<SCkUiTable> Table = GetRecordsTable(); Table.IsValid())
    {
        const TOptional<FString> SelectedKey = Table->GetSelectedKey();
        if (SelectedKey.IsSet() && HasRecord(SelectedKey.GetValue()))
        {
            _Selection = SelectedKey.GetValue();
            return;
        }
        _Selection.Reset();
        return;
    }
    if (!_Selection.IsEmpty() && !HasRecord(_Selection)) { _Selection.Reset(); }
}

void FCkCapabilityGalleryModel::ToggleRepeat(const FString& InKey)
{
    if (!_RepeatItems.IsValid() || !_RepeatItems->FindRecord(InKey).IsValid()) { _Status = TEXT("Repeat item update rejected"); return; }
    TSet<FString> NextExpandedKeys = _ExpandedRecordKeys;
    if (NextExpandedKeys.Contains(InKey)) { NextExpandedKeys.Remove(InKey); } else { NextExpandedKeys.Add(InKey); }
    if (!PublishRepeatItems(_RepeatItemOrder, _RemovedRepeatItemKeys, _UpdatedRepeatItemKeys, NextExpandedKeys)) { _Status = TEXT("Repeat item update rejected"); return; }
    _ExpandedRecordKeys = MoveTemp(NextExpandedKeys);
    _Status = FString::Printf(TEXT("Repeat item %s toggled"), *InKey);
}

void FCkCapabilityGalleryModel::ReverseRepeatItems()
{
    TArray<FString> NextOrder = _RepeatItemOrder;
    Algo::Reverse(NextOrder);
    if (!PublishRepeatItems(NextOrder, _RemovedRepeatItemKeys, _UpdatedRepeatItemKeys, _ExpandedRecordKeys)) { _Status = TEXT("Repeat reverse rejected"); return; }
    _RepeatItemOrder = MoveTemp(NextOrder);
    _Status = TEXT("Repeat order reversed");
}

void FCkCapabilityGalleryModel::UpdateRepeatRecordZero()
{
    static const FString RecordZero = TEXT("record-0");
    if (!HasRepeatItem(RecordZero)) { _Status = TEXT("Repeat record-0 update rejected"); return; }
    TSet<FString> NextUpdatedKeys = _UpdatedRepeatItemKeys;
    NextUpdatedKeys.Add(RecordZero);
    if (!PublishRepeatItems(_RepeatItemOrder, _RemovedRepeatItemKeys, NextUpdatedKeys, _ExpandedRecordKeys)) { _Status = TEXT("Repeat record-0 update rejected"); return; }
    _UpdatedRepeatItemKeys = MoveTemp(NextUpdatedKeys);
    _Status = TEXT("Repeat record-0 updated");
}

void FCkCapabilityGalleryModel::RemoveRepeatRecordZero()
{
    static const FString RecordZero = TEXT("record-0");
    if (!HasRepeatItem(RecordZero)) { _Status = TEXT("Repeat record-0 removal rejected"); return; }
    TSet<FString> NextRemovedKeys = _RemovedRepeatItemKeys;
    NextRemovedKeys.Add(RecordZero);
    if (!PublishRepeatItems(_RepeatItemOrder, NextRemovedKeys, _UpdatedRepeatItemKeys, _ExpandedRecordKeys)) { _Status = TEXT("Repeat record-0 removal rejected"); return; }
    _RemovedRepeatItemKeys = MoveTemp(NextRemovedKeys);
    _LastRemovedRepeatItemKey = RecordZero;
    _Status = TEXT("Repeat record-0 removed");
}

void FCkCapabilityGalleryModel::ReinsertRepeatRecord()
{
    if (_LastRemovedRepeatItemKey.IsEmpty() || !_RemovedRepeatItemKeys.Contains(_LastRemovedRepeatItemKey)) { _Status = TEXT("Repeat reinsertion rejected"); return; }
    const FString ReinsertedKey = _LastRemovedRepeatItemKey;
    TSet<FString> NextRemovedKeys = _RemovedRepeatItemKeys;
    NextRemovedKeys.Remove(ReinsertedKey);
    if (!PublishRepeatItems(_RepeatItemOrder, NextRemovedKeys, _UpdatedRepeatItemKeys, _ExpandedRecordKeys)) { _Status = TEXT("Repeat reinsertion rejected"); return; }
    _RemovedRepeatItemKeys = MoveTemp(NextRemovedKeys);
    _LastRemovedRepeatItemKey.Reset();
    _Status = FString::Printf(TEXT("Repeat %s reinserted"), *ReinsertedKey);
}

void FCkCapabilityGalleryModel::ResetRepeatItems()
{
    const auto ResetOrder = TArray<FString>{TEXT("record-0"), TEXT("record-1"), TEXT("record-2")};
    const auto ResetKeys = TSet<FString>{};
    if (!PublishRepeatItems(ResetOrder, ResetKeys, ResetKeys, ResetKeys)) { _Status = TEXT("Repeat reset rejected"); return; }
    _RepeatItemOrder = ResetOrder;
    _RemovedRepeatItemKeys = ResetKeys;
    _UpdatedRepeatItemKeys = ResetKeys;
    _ExpandedRecordKeys = ResetKeys;
    _LastRemovedRepeatItemKey.Reset();
    _Status = TEXT("Repeat lab reset");
}

void FCkCapabilityGalleryModel::InsertTreeLabNode()
{
    if (_TreeLabChildOrder.Contains(TEXT("tree-gamma"))) { _TreeLabStatus = TEXT("Tree Gamma is already present"); return; }
    TArray<FString> NextOrder = _TreeLabChildOrder;
    NextOrder.Add(TEXT("tree-gamma"));
    if (!PublishTreeLab(NextOrder)) { _TreeLabStatus = TEXT("Tree insertion rejected"); return; }
    _TreeLabChildOrder = MoveTemp(NextOrder);
    _TreeLabStatus = TEXT("Tree Gamma inserted");
}

void FCkCapabilityGalleryModel::ReverseTreeLabNodes()
{
    TArray<FString> NextOrder = _TreeLabChildOrder;
    Algo::Reverse(NextOrder);
    if (!PublishTreeLab(NextOrder)) { _TreeLabStatus = TEXT("Tree reverse rejected"); return; }
    _TreeLabChildOrder = MoveTemp(NextOrder);
    _TreeLabStatus = TEXT("Tree children reversed");
}

void FCkCapabilityGalleryModel::RemoveSelectedTreeLabNode()
{
    if (_TreeLabSelection.IsEmpty() || _TreeLabSelection == TEXT("tree-root") || !_TreeLabChildOrder.Contains(_TreeLabSelection))
    {
        _TreeLabStatus = TEXT("Tree selected-node removal rejected");
        return;
    }

    const FString RemovedKey = _TreeLabSelection;
    TArray<FString> NextOrder = _TreeLabChildOrder;
    NextOrder.Remove(RemovedKey);
    if (!PublishTreeLab(NextOrder)) { _TreeLabStatus = TEXT("Tree selected-node removal rejected"); return; }
    _TreeLabChildOrder = MoveTemp(NextOrder);
    _LastRemovedTreeLabKey = RemovedKey;
    _TreeLabStatus = FString::Printf(TEXT("Tree %s removed"), *RemovedKey);
}

void FCkCapabilityGalleryModel::ReinsertTreeLabNode()
{
    if (_LastRemovedTreeLabKey.IsEmpty() || _TreeLabChildOrder.Contains(_LastRemovedTreeLabKey))
    {
        _TreeLabStatus = TEXT("Tree reinsertion rejected");
        return;
    }

    const FString ReinsertedKey = _LastRemovedTreeLabKey;
    TArray<FString> NextOrder = _TreeLabChildOrder;
    NextOrder.Add(ReinsertedKey);
    if (!PublishTreeLab(NextOrder)) { _TreeLabStatus = TEXT("Tree reinsertion rejected"); return; }
    _TreeLabChildOrder = MoveTemp(NextOrder);
    _LastRemovedTreeLabKey.Reset();
    _TreeLabStatus = FString::Printf(TEXT("Tree %s reinserted"), *ReinsertedKey);
}

void FCkCapabilityGalleryModel::ResetTreeLab()
{
    const auto ResetOrder = TArray<FString>{TEXT("tree-alpha"), TEXT("tree-beta")};
    if (!PublishTreeLab(ResetOrder)) { _TreeLabStatus = TEXT("Tree reset rejected"); return; }
    _TreeLabChildOrder = ResetOrder;
    _LastRemovedTreeLabKey.Reset();

    if (const TSharedPtr<SCkUiTree> Tree = GetTreeLab(); Tree.IsValid())
    {
        if (!Tree->TrySelectKey(TOptional<FString>{}, true) || !Tree->TrySetExpanded(TEXT("tree-root"), false))
        {
            _TreeLabStatus = TEXT("Tree reset native state clear rejected");
            return;
        }
    }
    _TreeLabSelection.Reset();
    _TreeLabStatus = TEXT("Tree lab reset");
}
