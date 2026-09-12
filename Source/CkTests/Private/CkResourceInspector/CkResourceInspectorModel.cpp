#include "CkResourceInspector/CkResourceInspectorModel.h"

#include "CkCore/Ensure/CkEnsure.h"
#include "CkSlateLayout/CkUiTextInput.h"
#include "CkSlateLayout/CkUiCheckbox.h"
#include "CkSlateLayout/CkUiNumberInput.h"
#include "CkSlateLayout/CkUiSlider.h"
#include "CkSlateLayout/CkUiSelect.h"
#include "CkSlateLayout/CkUiDialog.h"
#include "CkSlateLayout/CkUiStatusPill.h"
#include "CkSlateLayout/SCkUiTree.h"
#include "Styling/CoreStyle.h"

namespace ck_resource_inspector
{
    constexpr int32 DefaultRowCount = 12;
    constexpr int32 MaximumRowCount = 10000;
    constexpr int32 MaximumSessionNoteLength = 80;
    constexpr int32 MaximumActivityRecords = 100;

    auto ErrorText(const FCkUiLoadResult& InResult) -> FString
    {
        return InResult.Errors.IsEmpty() ? TEXT("Resource Inspector collection creation failed.") : FString::Join(InResult.Errors, TEXT("\n"));
    }

    auto TextField(const FString& InValue) -> FCkUiFieldValue
    {
        return FCkUiFieldValue{.Kind = ECkUiFieldKind::Text, .Text = FText::FromString(InValue)};
    }

    auto ColorField(const FLinearColor InValue) -> FCkUiFieldValue
    {
        return FCkUiFieldValue{.Kind = ECkUiFieldKind::Color, .Color = InValue};
    }

    auto StateForeground(const FString& InState) -> FLinearColor
    {
        if (InState == TEXT("Ready")) { return FLinearColor(FColor::FromHex(TEXT("A2E6BD"))); }
        if (InState == TEXT("Streaming")) { return FLinearColor(FColor::FromHex(TEXT("92CCFF"))); }
        if (InState == TEXT("Cached")) { return FLinearColor(FColor::FromHex(TEXT("B8C5D1"))); }
        return FLinearColor(FColor::FromHex(TEXT("FFCA87")));
    }

    auto StateOutline(const FString& InState) -> FLinearColor
    {
        if (InState == TEXT("Ready")) { return FLinearColor(FColor::FromHex(TEXT("38715D"))); }
        if (InState == TEXT("Streaming")) { return FLinearColor(FColor::FromHex(TEXT("3D6990"))); }
        if (InState == TEXT("Cached")) { return FLinearColor(FColor::FromHex(TEXT("526473"))); }
        return FLinearColor(FColor::FromHex(TEXT("8C6134")));
    }

    auto CategoryKind(const FString& InKey) -> const TCHAR*
    {
        if (InKey == TEXT("texture")) { return TEXT("Texture"); }
        if (InKey == TEXT("material")) { return TEXT("Material"); }
        if (InKey == TEXT("static-mesh")) { return TEXT("Static Mesh"); }
        if (InKey == TEXT("shader")) { return TEXT("Shader"); }
        return nullptr;
    }

    auto SearchPlaceholder(const bool bLongLabels) -> FText
    {
        return bLongLabels
            ? NSLOCTEXT("CkResourceInspector", "ResourceSearchPlaceholderLong", "Filter deterministic resources by display name, kind, state, or retained inspection details…")
            : NSLOCTEXT("CkResourceInspector", "ResourceSearchPlaceholder", "Filter resources…");
    }

    auto NameColumnLabel(const bool bLongLabels) -> FText
    {
        return bLongLabels
            ? NSLOCTEXT("CkResourceInspector", "ResourceNameColumnLabelLong", "Resource display name and retained inspection identity")
            : NSLOCTEXT("CkResourceInspector", "ResourceNameColumnLabel", "Name");
    }
}

auto FCkResourceInspectorModel::TryCreate(FSimpleDelegate InClose, TSharedPtr<FCkResourceInspectorModel>& OutModel, FString& OutError, const int32 InSlateUserIndex) -> bool
{
    OutError.Reset();
    if (InSlateUserIndex < 0)
    {
        OutError = TEXT("Resource Inspector requires an explicit nonnegative Slate user.");
        return false;
    }
    const TSharedPtr<FCkResourceInspectorModel> Candidate = MakeShareable(new FCkResourceInspectorModel(MoveTemp(InClose)));
    auto Registry = FCkUiWidgetRegistry{};
    const FCkUiLoadResult TextInputRegistration = FCkUiTextInput::Register(Registry);
    if (!TextInputRegistration.Succeeded)
    {
        OutError = ck_resource_inspector::ErrorText(TextInputRegistration);
        return false;
    }
    const FCkUiLoadResult CheckboxRegistration = FCkUiCheckbox::Register(Registry);
    if (!CheckboxRegistration.Succeeded)
    {
        OutError = ck_resource_inspector::ErrorText(CheckboxRegistration);
        return false;
    }
    const FCkUiLoadResult NumberInputRegistration = FCkUiNumberInput::Register(Registry);
    if (!NumberInputRegistration.Succeeded)
    {
        OutError = ck_resource_inspector::ErrorText(NumberInputRegistration);
        return false;
    }
    const FCkUiLoadResult SliderRegistration = FCkUiSlider::Register(Registry);
    if (!SliderRegistration.Succeeded)
    {
        OutError = ck_resource_inspector::ErrorText(SliderRegistration);
        return false;
    }
    const FCkUiLoadResult SelectRegistration = FCkUiSelect::Register(Registry);
    if (!SelectRegistration.Succeeded)
    {
        OutError = ck_resource_inspector::ErrorText(SelectRegistration);
        return false;
    }
    const FCkUiLoadResult DialogRegistration = FCkUiDialog::Register(Registry);
    if (!DialogRegistration.Succeeded)
    {
        OutError = ck_resource_inspector::ErrorText(DialogRegistration);
        return false;
    }
    const FCkUiLoadResult StatusPillRegistration = FCkUiStatusPill::Register(Registry);
    if (!StatusPillRegistration.Succeeded)
    {
        OutError = ck_resource_inspector::ErrorText(StatusPillRegistration);
        return false;
    }
    TSharedPtr<FCkUiCollection> CategoryOptions;
    const FCkUiLoadResult OptionsCreated = FCkUiCollection::TryCreate({{TEXT("label"), ECkUiFieldKind::Text}}, CategoryOptions);
    if (!OptionsCreated.Succeeded)
    {
        OutError = ck_resource_inspector::ErrorText(OptionsCreated);
        return false;
    }
    TArray<FCkUiRecordData> OptionRecords;
    for (const FString& Key : {FString(TEXT("all")), FString(TEXT("texture")), FString(TEXT("material")), FString(TEXT("static-mesh")), FString(TEXT("shader"))})
    {
        const TCHAR* Label = ck_resource_inspector::CategoryKind(Key);
        FCkUiRecordData Record;
        Record.Key = Key;
        Record.Fields.Add(TEXT("label"), ck_resource_inspector::TextField(Label != nullptr ? Label : TEXT("All resources")));
        OptionRecords.Add(MoveTemp(Record));
    }
    const FCkUiLoadResult OptionsPopulated = CategoryOptions->TrySetRecords(MoveTemp(OptionRecords));
    if (!OptionsPopulated.Succeeded)
    {
        OutError = ck_resource_inspector::ErrorText(OptionsPopulated);
        return false;
    }
    const TSharedRef<const FCkUiWidgetRegistrySnapshot> RegistrySnapshot = Registry.CreateSnapshot();

    const FCkUiLoadResult CollectionResult = FCkUiCollection::TryCreate({
        {TEXT("name"), ECkUiFieldKind::Text},
        {TEXT("kind"), ECkUiFieldKind::Text},
        {TEXT("size"), ECkUiFieldKind::Text},
        {TEXT("size-bytes"), ECkUiFieldKind::Number},
        {TEXT("state"), ECkUiFieldKind::Text},
        {TEXT("state-foreground"), ECkUiFieldKind::Color},
        {TEXT("state-outline"), ECkUiFieldKind::Color},
    }, Candidate->_Collection);
    if (!CollectionResult.Succeeded || !Candidate->_Collection.IsValid())
    {
        OutError = ck_resource_inspector::ErrorText(CollectionResult);
        return false;
    }

    const FCkUiLoadResult ActivityResult = FCkUiCollection::TryCreate({
        {TEXT("sequence"), ECkUiFieldKind::Number},
        {TEXT("message"), ECkUiFieldKind::Text},
    }, Candidate->_Activity);
    if (!ActivityResult.Succeeded || !Candidate->_Activity.IsValid())
    {
        OutError = ck_resource_inspector::ErrorText(ActivityResult);
        return false;
    }

    const FCkUiLoadResult PinnedSnapshotsResult = FCkUiCollection::TryCreate({
        {TEXT("name"), ECkUiFieldKind::Text},
        {TEXT("kind"), ECkUiFieldKind::Text},
        {TEXT("size"), ECkUiFieldKind::Text},
        {TEXT("state"), ECkUiFieldKind::Text},
        {TEXT("heading"), ECkUiFieldKind::Text},
        {TEXT("details"), ECkUiFieldKind::Text},
        {TEXT("expanded"), ECkUiFieldKind::Bool},
    }, Candidate->_PinnedSnapshots);
    if (!PinnedSnapshotsResult.Succeeded || !Candidate->_PinnedSnapshots.IsValid())
    {
        OutError = ck_resource_inspector::ErrorText(PinnedSnapshotsResult);
        return false;
    }

    const FCkUiLoadResult NavigationResult = FCkUiTreeCollection::TryCreate({{TEXT("label"), ECkUiFieldKind::Text}}, Candidate->_Navigation);
    if (!NavigationResult.Succeeded || !Candidate->_Navigation.IsValid())
    {
        OutError = ck_resource_inspector::ErrorText(NavigationResult);
        return false;
    }
    const FCkUiLoadResult NavigationNodes = Candidate->_Navigation->TrySetNodes(Candidate->MakeNavigationNodes());
    if (!NavigationNodes.Succeeded)
    {
        OutError = ck_resource_inspector::ErrorText(NavigationNodes);
        return false;
    }

    const FCkUiLoadResult InitialRows = Candidate->_Collection->TrySetRecords(Candidate->MakeRecords(ck_resource_inspector::DefaultRowCount));
    if (!InitialRows.Succeeded)
    {
        OutError = ck_resource_inspector::ErrorText(InitialRows);
        return false;
    }

    const TWeakPtr<FCkResourceInspectorModel> WeakModel = Candidate;
    auto Data = FCkUiView::FDataBindings{};
    Data.SlateUserIndex = InSlateUserIndex;
    Data.Collections.Add(TEXT("category-options"), CategoryOptions);
    Data.String.Add(TEXT("detail-tab"), TAttribute<FString>::CreateLambda([WeakModel]()
    {
        const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin();
        return Model.IsValid() ? Model->GetDetailTab() : FString{};
    }));
    Data.StringChanged.Add(TEXT("select-detail-tab"), FCkUiOnStringChanged::CreateLambda([WeakModel](const FString& Key)
    {
        if (const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin()) { Model->TrySetDetailTab(Key); }
    }));
    Data.String.Add(TEXT("category"), TAttribute<FString>::CreateLambda([WeakModel]()
    {
        const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin();
        return Model.IsValid() ? Model->_Category : FString{};
    }));
    Data.StringChanged.Add(TEXT("select-category-key"), FCkUiOnStringChanged::CreateLambda([WeakModel](const FString& InKey)
    {
        if (const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin())
        {
            FString Failure;
            Model->TrySetCategory(InKey, Failure);
        }
    }));
    Data.Text.Add(TEXT("query"), TAttribute<FText>::CreateLambda([WeakModel]()
    {
        const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin();
        return Model.IsValid() ? FText::FromString(Model->_Query) : FText::GetEmpty();
    }));
    Data.TextChanged.Add(TEXT("query"), FOnTextChanged::CreateLambda([WeakModel](const FText& InText)
    {
        if (const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin()) { Model->_Query = InText.ToString(); }
    }));
    Data.Text.Add(TEXT("resource-search-placeholder"), TAttribute<FText>::CreateLambda([WeakModel]()
    {
        const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin();
        return Model.IsValid() ? Model->GetSearchPlaceholder() : FText::GetEmpty();
    }));
    Data.Text.Add(TEXT("resource-name-column-label"), TAttribute<FText>::CreateLambda([WeakModel]()
    {
        const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin();
        return Model.IsValid() ? Model->GetNameColumnLabel() : FText::GetEmpty();
    }));
    Data.Text.Add(TEXT("header-count"), TAttribute<FText>::CreateLambda([WeakModel]()
    {
        const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin();
        return Model.IsValid() ? Model->HeaderCount() : FText::GetEmpty();
    }));
    Data.Text.Add(TEXT("selected-title"), TAttribute<FText>::CreateLambda([WeakModel]()
    {
        const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin();
        return Model.IsValid() ? Model->SelectedTitle() : FText::GetEmpty();
    }));
    Data.Text.Add(TEXT("selected-detail"), TAttribute<FText>::CreateLambda([WeakModel]()
    {
        const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin();
        return Model.IsValid() ? Model->SelectedDetail() : FText::GetEmpty();
    }));
    Data.Text.Add(TEXT("resource-empty-message"), TAttribute<FText>::CreateLambda([WeakModel]()
    {
        const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin();
        if (!Model.IsValid() || !Model->IsEmpty()) { return FText::GetEmpty(); }
        if (Model->_RowCount == 0) { return FText::FromString(TEXT("No resources in this scenario.")); }
        return FText::FromString(Model->_Category == TEXT("all") ? TEXT("No resources match the filter.")
            : FString::Printf(TEXT("No %s resources in this scenario."), *Model->CategoryLabel()));
    }));
    Data.Text.Add(TEXT("layout-error"), TAttribute<FText>::CreateLambda([WeakModel]()
    {
        const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin();
        return Model.IsValid() ? Model->LayoutError() : FText::GetEmpty();
    }));
    Data.Number.Add(TEXT("row-count"), TAttribute<float>::CreateLambda([WeakModel]()
    {
        const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin();
        return Model.IsValid() ? static_cast<float>(Model->GetRowCount()) : 0.0f;
    }));
    Data.NumberCommitted.Add(TEXT("set-row-count"), FCkUiOnNumberCommitted::CreateLambda([WeakModel](const float InValue, const ETextCommit::Type InReason)
    {
        if (InReason != ETextCommit::OnEnter && InReason != ETextCommit::OnUserMovedFocus) { return; }
        if (const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin())
        {
            if (!FMath::IsFinite(InValue) || InValue < 0.0f || InValue > static_cast<float>(ck_resource_inspector::MaximumRowCount)) { return; }
            FString Error;
            Model->TrySetRowCount(FMath::RoundToInt(InValue), Error);
        }
    }));
    Data.NumberInteraction.Add(TEXT("set-row-count-slider"), FCkUiOnNumberInteraction::CreateLambda([WeakModel](const FCkUiNumberInteraction& InEvent)
    {
        if (InEvent.Phase != ECkUiInteractionPhase::Commit || !FMath::IsFinite(InEvent.Value)) { return; }
        if (const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin())
        {
            const float ClampedValue = FMath::Clamp(InEvent.Value, 0.0f, static_cast<float>(ck_resource_inspector::MaximumRowCount));
            FString Error;
            Model->TrySetRowCount(FMath::RoundToInt(ClampedValue), Error);
        }
    }));
    Data.Text.Add(TEXT("lock-note-label"), FText::FromString(TEXT("Lock note")));
    Data.Visibility.Add(TEXT("session-note-locked"), TAttribute<bool>::CreateLambda([WeakModel]()
    {
        const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin();
        return Model.IsValid() && Model->IsSessionNoteLocked();
    }));
    Data.BoolChanged.Add(TEXT("lock-session-note"), FCkUiOnBoolChanged::CreateLambda([WeakModel](const bool InLocked)
    {
        if (const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin()) { Model->SetSessionNoteLocked(InLocked); }
    }));
    Data.Text.Add(TEXT("session-note"), TAttribute<FText>::CreateLambda([WeakModel]()
    {
        const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin();
        return Model.IsValid() ? FText::FromString(Model->GetSessionNote()) : FText::GetEmpty();
    }));
    Data.Text.Add(TEXT("session-note-error"), TAttribute<FText>::CreateLambda([WeakModel]()
    {
        const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin();
        return Model.IsValid() ? FText::FromString(Model->GetSessionNoteError()) : FText::GetEmpty();
    }));
    Data.Visibility.Add(TEXT("has-selection"), TAttribute<bool>::CreateLambda([WeakModel]()
    {
        const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin();
        return Model.IsValid() && Model->HasSelection();
    }));
    Data.Visibility.Add(TEXT("resource-empty"), TAttribute<bool>::CreateLambda([WeakModel]()
    {
        const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin();
        return Model.IsValid() && Model->GetPresentationState() == TEXT("ready") && Model->IsEmpty();
    }));
    Data.Visibility.Add(TEXT("resource-ready"), TAttribute<bool>::CreateLambda([WeakModel]()
    {
        const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin();
        return Model.IsValid() && Model->GetPresentationState() == TEXT("ready");
    }));
    Data.Visibility.Add(TEXT("resource-loading"), TAttribute<bool>::CreateLambda([WeakModel]()
    {
        const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin();
        return Model.IsValid() && Model->GetPresentationState() == TEXT("loading");
    }));
    Data.Visibility.Add(TEXT("resource-error"), TAttribute<bool>::CreateLambda([WeakModel]()
    {
        const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin();
        return Model.IsValid() && Model->GetPresentationState() == TEXT("error");
    }));
    Data.Visibility.Add(TEXT("has-layout-error"), TAttribute<bool>::CreateLambda([WeakModel]()
    {
        const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin();
        return Model.IsValid() && Model->HasLayoutError();
    }));
    Data.Visibility.Add(TEXT("has-session-note-error"), TAttribute<bool>::CreateLambda([WeakModel]()
    {
        const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin();
        return Model.IsValid() && Model->HasSessionNoteError();
    }));
    Data.Collections.Add(TEXT("resources"), Candidate->_Collection);
    Data.Collections.Add(TEXT("activity"), Candidate->_Activity);
    Data.Collections.Add(TEXT("pinned-snapshots"), Candidate->_PinnedSnapshots);
    Data.Visibility.Add(TEXT("activity-empty"), TAttribute<bool>::CreateLambda([WeakModel]()
    {
        const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin();
        return !Model.IsValid() || !Model->_Activity.IsValid() || Model->_Activity->GetRecords().IsEmpty();
    }));
    Data.Trees.Add(TEXT("navigation"), Candidate->_Navigation);
    Data.ContextActions.Add(TEXT("show-properties"), FOnCkUiContextAction::CreateLambda([WeakModel](const FString& InKey)
    {
        const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin();
        if (!Model.IsValid() || !Model->_Collection.IsValid() || !Model->_Collection->FindRecord(InKey).IsValid() || !Model->_View.IsValid()) { return; }
        const TSharedPtr<SCkUiTable> Table = Model->_View->GetTable(TEXT("inspector-dialog/content/resources"));
        if (Table.IsValid() && Table->TrySelectKey(InKey, true)) { Model->TrySetDetailTab(TEXT("properties")); }
    }));
    Data.ContextActions.Add(TEXT("show-category"), FOnCkUiContextAction::CreateLambda([WeakModel](const FString& InKey)
    {
        const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin();
        if (!Model.IsValid() || !Model->_Navigation.IsValid() || !Model->_Navigation->FindNode(InKey).IsValid()) { return; }
        Model->OnCategorySelectionChanged(InKey, ESelectInfo::OnMouseClick);
    }));
    Data.TableSelectionChanged.Add(TEXT("select-resource"), FOnCkUiTableSelectionChanged::CreateLambda(
        [WeakModel](TOptional<FString> InKey, const ESelectInfo::Type InSelectionType)
        {
            if (const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin()) { Model->OnSelectionChanged(MoveTemp(InKey), InSelectionType); }
        }));
    Data.TreeSelectionChanged.Add(TEXT("select-category"), FOnCkUiTreeSelectionChanged::CreateLambda(
        [WeakModel](TOptional<FString> InKey, const ESelectInfo::Type InSelectionType)
        {
            if (const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin()) { Model->OnCategorySelectionChanged(MoveTemp(InKey), InSelectionType); }
        }));
    Data.TextCommitted.Add(TEXT("commit-session-note"), FOnTextCommitted::CreateLambda(
        [WeakModel](const FText& InText, const ETextCommit::Type InCommitType)
        {
            if (InCommitType == ETextCommit::Default || InCommitType == ETextCommit::OnCleared) { return; }
            if (const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin())
            {
                FString IgnoredFailure;
                Model->TrySetSessionNote(InText.ToString(), IgnoredFailure);
            }
        }));
    Data.ItemActions.Add(TEXT("toggle-pinned-snapshot"), FCkUiOnItemAction::CreateLambda([WeakModel](const FString InKey)
    {
        if (const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin())
        {
            FString IgnoredFailure;
            Model->TryTogglePinnedSnapshot(InKey, IgnoredFailure);
        }
    }));
    Data.ItemActions.Add(TEXT("remove-pinned-snapshot"), FCkUiOnItemAction::CreateLambda([WeakModel](const FString InKey)
    {
        if (const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin())
        {
            FString IgnoredFailure;
            Model->TryRemovePinnedSnapshot(InKey, IgnoredFailure);
        }
    }));

    Data.Visibility.Add(TEXT("clear-pins-dialog-open"), TAttribute<bool>::CreateLambda([WeakModel]()
    {
        const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin();
        return Model.IsValid() && Model->_ClearPinsDialogOpen;
    }));
    Data.Visibility.Add(TEXT("has-pins"), TAttribute<bool>::CreateLambda([WeakModel]()
    {
        const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin();
        return Model.IsValid() && Model->_PinnedSnapshots.IsValid() && !Model->_PinnedSnapshots->GetRecords().IsEmpty();
    }));
    auto Actions = FCkUiView::FActions{};
    Actions.Add(TEXT("request-clear-pins"), FSimpleDelegate::CreateLambda([WeakModel]()
    {
        if (const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin(); Model.IsValid()
            && Model->_PinnedSnapshots.IsValid() && !Model->_PinnedSnapshots->GetRecords().IsEmpty())
        { Model->_ClearPinsDialogOpen = true; }
    }));
    Actions.Add(TEXT("cancel-clear-pins"), FSimpleDelegate::CreateLambda([WeakModel]()
    {
        if (const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin()) { Model->_ClearPinsDialogOpen = false; }
    }));
    Actions.Add(TEXT("confirm-clear-pins"), FSimpleDelegate::CreateLambda([WeakModel]()
    {
        if (const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin()) { Model->ConfirmClearPins(); }
    }));
    const auto AddScenario = [&Actions, WeakModel](const TCHAR* InAction, const int32 InCount) -> void
    {
        Actions.Add(InAction, FSimpleDelegate::CreateLambda([WeakModel, InCount]()
        {
            if (const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin())
            {
                FString IgnoredFailure;
                Model->TrySetRowCount(InCount, IgnoredFailure);
            }
        }));
    };
    AddScenario(TEXT("rows-0"), 0);
    AddScenario(TEXT("rows-1"), 1);
    AddScenario(TEXT("rows-12"), 12);
    AddScenario(TEXT("rows-1000"), 1000);
    AddScenario(TEXT("rows-10000"), 10000);
    const auto AddPresentationScenario = [&Actions, WeakModel](const TCHAR* InAction, const TCHAR* InState) -> void
    {
        Actions.Add(InAction, FSimpleDelegate::CreateLambda([WeakModel, InState]()
        {
            if (const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin()) { Model->TrySetPresentationState(InState); }
        }));
    };
    AddPresentationScenario(TEXT("preview-loading"), TEXT("loading"));
    AddPresentationScenario(TEXT("preview-error"), TEXT("error"));
    AddPresentationScenario(TEXT("show-resources"), TEXT("ready"));
    Actions.Add(TEXT("collapse-navigation"), FSimpleDelegate::CreateLambda([WeakModel]()
    {
        const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin();
        if (!Model.IsValid() || !Model->_View.IsValid() || !Model->_Navigation.IsValid()) { return; }
        const TSharedPtr<SCkUiTree> Navigation = Model->_View->GetTree(TEXT("inspector-dialog/content/navigation"));
        if (!Navigation.IsValid()) { return; }
        for (const TSharedPtr<const FCkUiTreeNode>& Node : Model->_Navigation->GetNodes())
        {
            if (Node.IsValid()) { Navigation->TrySetExpanded(Node->GetKey(), false); }
        }
    }));
    Actions.Add(TEXT("toggle-long-labels"), FSimpleDelegate::CreateLambda([WeakModel]()
    {
        if (const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin()) { Model->_bLongLabels = !Model->_bLongLabels; }
    }));
    Actions.Add(TEXT("clear-selection"), FSimpleDelegate::CreateLambda([WeakModel]()
    {
        if (const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin()) { Model->ClearSelection(); }
    }));
    Actions.Add(TEXT("pin-selected-resource"), FSimpleDelegate::CreateLambda([WeakModel]()
    {
        if (const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin())
        {
            FString IgnoredFailure;
            Model->TryPinSelected(IgnoredFailure);
        }
    }));
    Actions.Add(TEXT("close"), FSimpleDelegate::CreateLambda([WeakModel]()
    {
        if (const TSharedPtr<FCkResourceInspectorModel> Model = WeakModel.Pin()) { Model->InvokeClose(); }
    }));

    Candidate->_View = FCkUiView::Create({}, MoveTemp(Actions), {}, FCoreStyle::GetDefaultFontStyle("Regular", 12), MoveTemp(Data), RegistrySnapshot);
    Candidate->_View->GetRegion(TEXT("main"));
    OutModel = Candidate;
    return true;
}

auto FCkResourceInspectorModel::ConfirmClearPins() -> void
{
    if (!_ClearPinsDialogOpen || _bMutatingPinnedSnapshots) { return; }
    if (!_PinnedSnapshots.IsValid() || _PinnedSnapshots->GetRecords().IsEmpty()) { _ClearPinsDialogOpen = false; return; }
    FString Failure;
    _ClearPinsDialogOpen = false;
    if (!PublishPinnedSnapshots({}, Failure)) { _ClearPinsDialogOpen = true; return; }
    AppendActivity(TEXT("Cleared pinned snapshots."));
}

auto FCkResourceInspectorModel::GetView() const -> TSharedRef<FCkUiView>
{
    return _View.ToSharedRef();
}

auto FCkResourceInspectorModel::GetRoot() const -> TSharedRef<SWidget>
{
    return GetView()->GetRegion(TEXT("main"));
}

auto FCkResourceInspectorModel::GetCollection() const -> TSharedPtr<FCkUiCollection>
{
    return _Collection;
}

auto FCkResourceInspectorModel::GetActivity() const -> TSharedPtr<FCkUiCollection>
{
    return _Activity;
}

auto FCkResourceInspectorModel::GetNavigation() const -> TSharedPtr<FCkUiTreeCollection>
{
    return _Navigation;
}

auto FCkResourceInspectorModel::GetPinnedSnapshots() const -> TSharedPtr<FCkUiCollection>
{
    return _PinnedSnapshots;
}

auto FCkResourceInspectorModel::TrySetRowCount(const int32 InRowCount, FString& OutError) -> bool
{
    OutError.Reset();
    if (InRowCount < 0 || InRowCount > ck_resource_inspector::MaximumRowCount)
    {
        OutError = FString::Printf(TEXT("Resource Inspector row count must be between 0 and %d."), ck_resource_inspector::MaximumRowCount);
        return false;
    }
    if (!_Collection.IsValid())
    {
        OutError = TEXT("Resource Inspector collection is unavailable.");
        return false;
    }
    if (_bMutatingScenario)
    {
        OutError = TEXT("Resource Inspector scenario mutation during publication is rejected.");
        return false;
    }
    if (_RowCount == InRowCount) { return true; }

    const int32 PreviousRowCount = _RowCount;
    TGuardValue<bool> Guard(_bMutatingScenario, true);
    _RowCount = InRowCount;
    const FCkUiLoadResult Result = _Collection->TrySetRecords(MakeRecords(InRowCount));
    if (!Result.Succeeded)
    {
        _RowCount = PreviousRowCount;
        OutError = ck_resource_inspector::ErrorText(Result);
        return false;
    }
    AppendActivity(FString::Printf(TEXT("Resource count set to %d."), InRowCount));
    return true;
}

auto FCkResourceInspectorModel::TrySetPresentationState(FString InKey) -> bool
{
    InKey = InKey.TrimStartAndEnd().ToLower();
    if (!IsKnownPresentationState(InKey)) { return false; }
    _PresentationState = MoveTemp(InKey);
    return true;
}

auto FCkResourceInspectorModel::TrySetCategory(FString InKey, FString& OutError) -> bool
{
    OutError.Reset();
    InKey = InKey.TrimStartAndEnd().ToLower();
    if (!IsKnownCategory(InKey))
    {
        OutError = FString::Printf(TEXT("Unknown Resource Inspector category '%s'."), *InKey);
        return false;
    }
    if (!_Collection.IsValid())
    {
        OutError = TEXT("Resource Inspector collection is unavailable.");
        return false;
    }
    if (_bMutatingScenario)
    {
        OutError = TEXT("Resource Inspector scenario mutation during publication is rejected.");
        return false;
    }
    if (_Category == InKey) { return true; }

    const FString PreviousCategory = _Category;
    TGuardValue<bool> Guard(_bMutatingScenario, true);
    _Category = MoveTemp(InKey);
    const FCkUiLoadResult Result = _Collection->TrySetRecords(MakeRecords(_RowCount));
    if (!Result.Succeeded)
    {
        _Category = PreviousCategory;
        OutError = ck_resource_inspector::ErrorText(Result);
        return false;
    }
    AppendActivity(FString::Printf(TEXT("Category set to %s."), *CategoryLabel()));
    return true;
}

auto FCkResourceInspectorModel::TrySetSessionNote(FString InNote, FString& OutError) -> bool
{
    OutError.Reset();
    InNote = InNote.TrimStartAndEnd();
    if (InNote.Len() > ck_resource_inspector::MaximumSessionNoteLength)
    {
        _SessionNoteError = FString::Printf(TEXT("Session note must be %d characters or fewer."), ck_resource_inspector::MaximumSessionNoteLength);
        OutError = _SessionNoteError;
        return false;
    }

    const bool bChanged = _SessionNote != InNote;
    _SessionNote = MoveTemp(InNote);
    _SessionNoteError.Reset();
    if (bChanged) { AppendActivity(TEXT("Session note saved.")); }
    return true;
}

auto FCkResourceInspectorModel::TryPinSelected(FString& OutError) -> bool
{
    OutError.Reset();
    const TSharedPtr<const FCkUiRecord> Selected = FindSelectedRecord();
    if (!Selected.IsValid())
    {
        OutError = TEXT("Select a valid Resource Inspector resource before pinning a snapshot.");
        return false;
    }
    if (!_PinnedSnapshots.IsValid())
    {
        OutError = TEXT("Resource Inspector pinned snapshot collection is unavailable.");
        return false;
    }

    auto Snapshot = FCkUiRecordData{};
    Snapshot.Key = Selected->GetKey();
    const FCkUiFieldValue* Name = Selected->FindField(TEXT("name"));
    const FCkUiFieldValue* Kind = Selected->FindField(TEXT("kind"));
    const FCkUiFieldValue* Size = Selected->FindField(TEXT("size"));
    const FCkUiFieldValue* State = Selected->FindField(TEXT("state"));
    Snapshot.Fields.Add(TEXT("name"), Name != nullptr ? *Name : ck_resource_inspector::TextField(TEXT("Unknown")));
    Snapshot.Fields.Add(TEXT("kind"), Kind != nullptr ? *Kind : ck_resource_inspector::TextField(TEXT("Unknown")));
    Snapshot.Fields.Add(TEXT("size"), Size != nullptr ? *Size : ck_resource_inspector::TextField(TEXT("Unknown")));
    Snapshot.Fields.Add(TEXT("state"), State != nullptr ? *State : ck_resource_inspector::TextField(TEXT("Unknown")));
    Snapshot.Fields.Add(TEXT("heading"), ck_resource_inspector::TextField(Name != nullptr ? Name->Text.ToString() : Selected->GetKey()));
    Snapshot.Fields.Add(TEXT("details"), ck_resource_inspector::TextField(FString::Printf(TEXT("Kind: %s\nSize: %s\nState: %s\nStable key: %s"),
        Kind != nullptr ? *Kind->Text.ToString() : TEXT("Unknown"), Size != nullptr ? *Size->Text.ToString() : TEXT("Unknown"),
        State != nullptr ? *State->Text.ToString() : TEXT("Unknown"), *Selected->GetKey())));
    Snapshot.Fields.Add(TEXT("expanded"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Bool, .Bool = true});

    TArray<FCkUiRecordData> Updated;
    Updated.Reserve(_PinnedSnapshots->GetRecords().Num() + 1);
    bool bUpdatedExisting = false;
    for (const TSharedPtr<const FCkUiRecord>& Existing : _PinnedSnapshots->GetRecords())
    {
        if (!Existing.IsValid()) { continue; }
        if (Existing->GetKey() == Snapshot.Key)
        {
            if (const FCkUiFieldValue* Expanded = Existing->FindField(TEXT("expanded"))) { Snapshot.Fields[TEXT("expanded")] = *Expanded; }
            Updated.Add(MoveTemp(Snapshot));
            bUpdatedExisting = true;
            continue;
        }
        auto Preserved = FCkUiRecordData{};
        Preserved.Key = Existing->GetKey();
        for (const TCHAR* Field : {TEXT("name"), TEXT("kind"), TEXT("size"), TEXT("state"), TEXT("heading"), TEXT("details"), TEXT("expanded")})
        {
            if (const FCkUiFieldValue* Value = Existing->FindField(Field)) { Preserved.Fields.Add(Field, *Value); }
        }
        Updated.Add(MoveTemp(Preserved));
    }
    if (!bUpdatedExisting) { Updated.Add(MoveTemp(Snapshot)); }
    const int64 PreviousRevision = _PinnedSnapshots->GetRevision();
    if (!PublishPinnedSnapshots(MoveTemp(Updated), OutError)) { return false; }
    if (_PinnedSnapshots->GetRevision() != PreviousRevision)
    {
        AppendActivity(FString::Printf(TEXT("Pinned %s."), Name != nullptr ? *Name->Text.ToString() : *Selected->GetKey()));
    }
    return true;
}

auto FCkResourceInspectorModel::TryTogglePinnedSnapshot(const FString& InKey, FString& OutError) -> bool
{
    OutError.Reset();
    if (!_PinnedSnapshots.IsValid() || !_PinnedSnapshots->FindRecord(InKey).IsValid())
    {
        OutError = FString::Printf(TEXT("Pinned Resource Inspector snapshot '%s' is unavailable."), *InKey);
        return false;
    }

    TArray<FCkUiRecordData> Updated;
    Updated.Reserve(_PinnedSnapshots->GetRecords().Num());
    for (const TSharedPtr<const FCkUiRecord>& Existing : _PinnedSnapshots->GetRecords())
    {
        if (!Existing.IsValid()) { continue; }
        auto Snapshot = FCkUiRecordData{};
        Snapshot.Key = Existing->GetKey();
        for (const TCHAR* Field : {TEXT("name"), TEXT("kind"), TEXT("size"), TEXT("state"), TEXT("heading"), TEXT("details"), TEXT("expanded")})
        {
            if (const FCkUiFieldValue* Value = Existing->FindField(Field)) { Snapshot.Fields.Add(Field, *Value); }
        }
        if (Snapshot.Key == InKey)
        {
            FCkUiFieldValue* Expanded = Snapshot.Fields.Find(TEXT("expanded"));
            if (Expanded == nullptr || Expanded->Kind != ECkUiFieldKind::Bool)
            {
                OutError = FString::Printf(TEXT("Pinned Resource Inspector snapshot '%s' has invalid expanded state."), *InKey);
                return false;
            }
            Expanded->Bool = !Expanded->Bool;
        }
        Updated.Add(MoveTemp(Snapshot));
    }
    return PublishPinnedSnapshots(MoveTemp(Updated), OutError);
}

auto FCkResourceInspectorModel::TryRemovePinnedSnapshot(const FString& InKey, FString& OutError) -> bool
{
    OutError.Reset();
    if (!_PinnedSnapshots.IsValid() || !_PinnedSnapshots->FindRecord(InKey).IsValid())
    {
        OutError = FString::Printf(TEXT("Pinned Resource Inspector snapshot '%s' is unavailable."), *InKey);
        return false;
    }

    const TSharedPtr<const FCkUiRecord> Removed = _PinnedSnapshots->FindRecord(InKey);
    const FCkUiFieldValue* RemovedName = Removed.IsValid() ? Removed->FindField(TEXT("name")) : nullptr;
    TArray<FCkUiRecordData> Updated;
    Updated.Reserve(_PinnedSnapshots->GetRecords().Num() - 1);
    for (const TSharedPtr<const FCkUiRecord>& Existing : _PinnedSnapshots->GetRecords())
    {
        if (!Existing.IsValid() || Existing->GetKey() == InKey) { continue; }
        auto Snapshot = FCkUiRecordData{};
        Snapshot.Key = Existing->GetKey();
        for (const TCHAR* Field : {TEXT("name"), TEXT("kind"), TEXT("size"), TEXT("state"), TEXT("heading"), TEXT("details"), TEXT("expanded")})
        {
            if (const FCkUiFieldValue* Value = Existing->FindField(Field)) { Snapshot.Fields.Add(Field, *Value); }
        }
        Updated.Add(MoveTemp(Snapshot));
    }
    if (!PublishPinnedSnapshots(MoveTemp(Updated), OutError)) { return false; }
    AppendActivity(FString::Printf(TEXT("Unpinned %s."), RemovedName != nullptr ? *RemovedName->Text.ToString() : *InKey));
    return true;
}

auto FCkResourceInspectorModel::PublishPinnedSnapshots(TArray<FCkUiRecordData> InRecords, FString& OutError) -> bool
{
    OutError.Reset();
    if (!_PinnedSnapshots.IsValid())
    {
        OutError = TEXT("Resource Inspector pinned snapshot collection is unavailable.");
        return false;
    }
    if (_bMutatingPinnedSnapshots)
    {
        OutError = TEXT("Resource Inspector pinned snapshot mutation during publication is rejected.");
        return false;
    }

    TGuardValue<bool> Guard(_bMutatingPinnedSnapshots, true);
    const FCkUiLoadResult Result = _PinnedSnapshots->TrySetRecords(MoveTemp(InRecords));
    if (!Result.Succeeded)
    {
        OutError = ck_resource_inspector::ErrorText(Result);
        return false;
    }
    return true;
}

auto FCkResourceInspectorModel::AppendActivity(FString InMessage) -> void
{
    const bool bActivityAvailable = _Activity.IsValid();
    CK_ENSURE_IF_NOT(bActivityAvailable, TEXT("Resource Inspector activity collection is unavailable after a successful state change.")) {}
    if (!bActivityAvailable) { return; }
    _QueuedActivityMessages.Add(MoveTemp(InMessage));
    if (_bPublishingActivity)
    {
        return;
    }

    constexpr int32 MaximumActivityDrain = 256;
    for (int32 PublicationCount = 0; !_QueuedActivityMessages.IsEmpty() && PublicationCount < MaximumActivityDrain; ++PublicationCount)
    {
        FString Message = MoveTemp(_QueuedActivityMessages[0]);
        _QueuedActivityMessages.RemoveAt(0, 1, EAllowShrinking::No);
        auto Updated = _ActivityRecords;
        FCkUiRecordData Entry;
        Entry.Key = FString::Printf(TEXT("activity-%020llu"), static_cast<unsigned long long>(_NextActivitySequence));
        Entry.Fields.Add(TEXT("sequence"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Number, .Number = static_cast<float>(_NextActivitySequence)});
        Entry.Fields.Add(TEXT("message"), ck_resource_inspector::TextField(Message));
        Updated.Insert(MoveTemp(Entry), 0);
        if (Updated.Num() > ck_resource_inspector::MaximumActivityRecords) { Updated.SetNum(ck_resource_inspector::MaximumActivityRecords); }

        FCkUiLoadResult Result;
        {
            TGuardValue<bool> Guard(_bPublishingActivity, true);
            Result = _Activity->TrySetRecords(Updated);
        }
        const bool bPublished = Result.Succeeded;
        CK_ENSURE_IF_NOT(bPublished, TEXT("Resource Inspector activity publication failed after a successful state change: {}"), ck_resource_inspector::ErrorText(Result)) {}
        if (!bPublished)
        {
            _QueuedActivityMessages.Insert(MoveTemp(Message), 0);
            return;
        }
        _ActivityRecords = MoveTemp(Updated);
        ++_NextActivitySequence;
    }
    const bool bFullyDrained = _QueuedActivityMessages.IsEmpty();
    CK_ENSURE_IF_NOT(bFullyDrained, TEXT("Resource Inspector activity queue exceeded the {} publication drain limit."), MaximumActivityDrain) {}
    if (!bFullyDrained) { return; }
}

auto FCkResourceInspectorModel::MakeRecords(const int32 InRowCount) const -> TArray<FCkUiRecordData>
{
    static const TCHAR* Kinds[] = {TEXT("Texture"), TEXT("Material"), TEXT("Static Mesh"), TEXT("Shader")};
    static const TCHAR* States[] = {TEXT("Ready"), TEXT("Streaming"), TEXT("Cached"), TEXT("Pending")};

    auto Records = TArray<FCkUiRecordData>{};
    Records.Reserve(InRowCount);
    const TCHAR* RequiredKind = ck_resource_inspector::CategoryKind(_Category);
    for (int32 Index = 0; Index < InRowCount; ++Index)
    {
        const TCHAR* Kind = Kinds[Index % UE_ARRAY_COUNT(Kinds)];
        if (RequiredKind != nullptr && FCString::Strcmp(Kind, RequiredKind) != 0) { continue; }
        FCkUiRecordData Record;
        Record.Key = FString::Printf(TEXT("resource-%05d"), Index);
        Record.Fields.Add(TEXT("name"), ck_resource_inspector::TextField(FString::Printf(TEXT("Resource_%05d"), Index)));
        Record.Fields.Add(TEXT("kind"), ck_resource_inspector::TextField(Kind));
        const int32 SizeKiB = 64 + (Index % 97) * 16;
        Record.Fields.Add(TEXT("size"), ck_resource_inspector::TextField(FString::Printf(TEXT("%d KiB"), SizeKiB)));
        Record.Fields.Add(TEXT("size-bytes"), FCkUiFieldValue{.Kind = ECkUiFieldKind::Number, .Number = static_cast<float>(SizeKiB * 1024)});
        const FString State = States[Index % UE_ARRAY_COUNT(States)];
        Record.Fields.Add(TEXT("state"), ck_resource_inspector::TextField(State));
        Record.Fields.Add(TEXT("state-foreground"), ck_resource_inspector::ColorField(ck_resource_inspector::StateForeground(State)));
        Record.Fields.Add(TEXT("state-outline"), ck_resource_inspector::ColorField(ck_resource_inspector::StateOutline(State)));
        Records.Add(MoveTemp(Record));
    }
    return Records;
}

auto FCkResourceInspectorModel::MakeNavigationNodes() const -> TArray<FCkUiTreeNodeData>
{
    auto Nodes = TArray<FCkUiTreeNodeData>{};
    auto Root = FCkUiTreeNodeData{};
    Root.Key = TEXT("all");
    Root.Fields.Add(TEXT("label"), ck_resource_inspector::TextField(TEXT("All resources")));
    Nodes.Add(MoveTemp(Root));
    for (const TCHAR* Key : {TEXT("texture"), TEXT("material"), TEXT("static-mesh"), TEXT("shader")})
    {
        auto Child = FCkUiTreeNodeData{};
        Child.Key = Key;
        Child.ParentKey = TEXT("all");
        Child.Fields.Add(TEXT("label"), ck_resource_inspector::TextField(ck_resource_inspector::CategoryKind(Key)));
        Nodes.Add(MoveTemp(Child));
    }
    return Nodes;
}

auto FCkResourceInspectorModel::IsKnownCategory(const FString& InKey) const -> bool
{
    return InKey == TEXT("all") || ck_resource_inspector::CategoryKind(InKey) != nullptr;
}

auto FCkResourceInspectorModel::IsKnownPresentationState(const FString& InKey) const -> bool
{
    return InKey == TEXT("ready") || InKey == TEXT("loading") || InKey == TEXT("error");
}

auto FCkResourceInspectorModel::CategoryLabel() const -> FString
{
    if (_Category == TEXT("all")) { return TEXT("all"); }
    if (const TCHAR* Label = ck_resource_inspector::CategoryKind(_Category)) { return Label; }
    return TEXT("all");
}

auto FCkResourceInspectorModel::HeaderCount() const -> FText
{
    const int32 TotalCount = _Collection.IsValid() ? _Collection->GetRecords().Num() : 0;
    if (_View.IsValid())
    {
        if (const TSharedPtr<SCkUiTable> Table = _View->GetTable(TEXT("inspector-dialog/content/resources")); Table.IsValid())
        {
            return _Category == TEXT("all")
                ? FText::FromString(FString::Printf(TEXT("%d / %d resources"), Table->GetVisibleRecordCount(), TotalCount))
                : FText::FromString(FString::Printf(TEXT("%d / %d %s resources"), Table->GetVisibleRecordCount(), TotalCount, *CategoryLabel()));
        }
    }
    return _Category == TEXT("all")
        ? FText::FromString(FString::Printf(TEXT("%d resources"), TotalCount))
        : FText::FromString(FString::Printf(TEXT("%d %s resources"), TotalCount, *CategoryLabel()));
}

auto FCkResourceInspectorModel::GetSearchPlaceholder() const -> FText
{
    return ck_resource_inspector::SearchPlaceholder(_bLongLabels);
}

auto FCkResourceInspectorModel::GetNameColumnLabel() const -> FText
{
    return ck_resource_inspector::NameColumnLabel(_bLongLabels);
}

auto FCkResourceInspectorModel::SelectedTitle() const -> FText
{
    if (const TSharedPtr<const FCkUiRecord> Record = FindSelectedRecord())
    {
        if (const FCkUiFieldValue* Name = Record->FindField(TEXT("name"))) { return Name->Text; }
    }
    return FText::FromString(TEXT("Select a resource"));
}

auto FCkResourceInspectorModel::SelectedDetail() const -> FText
{
    const TSharedPtr<const FCkUiRecord> Record = FindSelectedRecord();
    if (!Record.IsValid()) { return FText::FromString(TEXT("Choose a resource to inspect its current typed collection data.")); }

    const FCkUiFieldValue* Name = Record->FindField(TEXT("name"));
    const FCkUiFieldValue* Kind = Record->FindField(TEXT("kind"));
    const FCkUiFieldValue* Size = Record->FindField(TEXT("size"));
    const FCkUiFieldValue* State = Record->FindField(TEXT("state"));
    return FText::FromString(FString::Printf(TEXT("%s\n\nKind: %s\nSize: %s\nState: %s\nStable key: %s"),
        Name != nullptr ? *Name->Text.ToString() : TEXT("Unknown"), Kind != nullptr ? *Kind->Text.ToString() : TEXT("Unknown"),
        Size != nullptr ? *Size->Text.ToString() : TEXT("Unknown"), State != nullptr ? *State->Text.ToString() : TEXT("Unknown"), *Record->GetKey()));
}

auto FCkResourceInspectorModel::LayoutError() const -> FText
{
    if (!_View.IsValid() || _View->GetLastResult().Succeeded) { return FText::GetEmpty(); }
    return FText::FromString(FString::Join(_View->GetLastResult().Errors, TEXT("\n")));
}

auto FCkResourceInspectorModel::HasSelection() const -> bool
{
    return FindSelectedRecord().IsValid();
}

auto FCkResourceInspectorModel::IsEmpty() const -> bool
{
    if (!_Collection.IsValid() || _Collection->GetRecords().IsEmpty()) { return true; }
    if (_View.IsValid())
    {
        if (const TSharedPtr<SCkUiTable> Table = _View->GetTable(TEXT("inspector-dialog/content/resources")); Table.IsValid())
        {
            return Table->GetVisibleRecordCount() == 0;
        }
    }
    return false;
}

auto FCkResourceInspectorModel::HasLayoutError() const -> bool
{
    return _View.IsValid() && !_View->GetLastResult().Succeeded;
}

auto FCkResourceInspectorModel::FindSelectedRecord() const -> TSharedPtr<const FCkUiRecord>
{
    return _Collection.IsValid() && _SelectedKey.IsSet() ? _Collection->FindRecord(_SelectedKey.GetValue()) : nullptr;
}

auto FCkResourceInspectorModel::OnSelectionChanged(TOptional<FString> InKey, const ESelectInfo::Type) -> void
{
    if (!InKey.IsSet())
    {
        if (!_SelectedKey.IsSet()) { return; }
        _SelectedKey.Reset();
        AppendActivity(TEXT("Cleared selection."));
        return;
    }
    if (!_Collection.IsValid()) { return; }
    const TSharedPtr<const FCkUiRecord> Selected = _Collection->FindRecord(InKey.GetValue());
    if (!Selected.IsValid() || (_SelectedKey.IsSet() && _SelectedKey.GetValue() == InKey.GetValue())) { return; }
    _SelectedKey = MoveTemp(InKey);
    const FCkUiFieldValue* Name = Selected->FindField(TEXT("name"));
    AppendActivity(FString::Printf(TEXT("Selected %s."), Name != nullptr ? *Name->Text.ToString() : *Selected->GetKey()));
}

auto FCkResourceInspectorModel::OnCategorySelectionChanged(TOptional<FString> InKey, const ESelectInfo::Type) -> void
{
    if (!InKey.IsSet()) { return; }
    FString IgnoredFailure;
    TrySetCategory(InKey.GetValue(), IgnoredFailure);
}

auto FCkResourceInspectorModel::ClearSelection() -> void
{
    if (_View.IsValid())
    {
        if (const TSharedPtr<SCkUiTable> Table = _View->GetTable(TEXT("inspector-dialog/content/resources")); Table.IsValid())
        {
            Table->TrySelectKey({}, true);
        }
    }
    if (_SelectedKey.IsSet())
    {
        _SelectedKey.Reset();
        AppendActivity(TEXT("Cleared selection."));
    }
}

auto FCkResourceInspectorModel::InvokeClose() -> void
{
    _Close.ExecuteIfBound();
}

auto FCkResourceInspectorModel::TrySetDetailTab(const FString& InKey) -> bool
{
    if (!InKey.Equals(TEXT("overview"), ESearchCase::CaseSensitive)
        && !InKey.Equals(TEXT("properties"), ESearchCase::CaseSensitive)
        && !InKey.Equals(TEXT("activity"), ESearchCase::CaseSensitive)) { return false; }
    _DetailTab = InKey;
    return true;
}
