#pragma once

#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/CkUiTreeCollection.h"
#include "CkSlateLayout/SCkUiSurface.h"

class SCkUiTree;

class FCkCapabilityGalleryModel final : public TSharedFromThis<FCkCapabilityGalleryModel>
{
public:
    static auto TryCreate(FSimpleDelegate InClose, TSharedPtr<FCkCapabilityGalleryModel>& OutModel, FString& OutError, int32 InSlateUserIndex) -> bool;

    auto GetView() const -> TSharedRef<FCkUiView> { return _View.ToSharedRef(); }
    auto GetBatchPreviewView() const -> TSharedPtr<FCkUiView> { return _BatchPreviewView; }
    auto GetRoot() const -> TSharedRef<SWidget>;
    auto RunAcceptedReload() -> void;
    const FString& GetPage() const { return _Page; }
    const FString& GetEditableText() const { return _EditableText; }
    const FString& GetCommittedText() const { return _CommittedText; }
    const FString& GetTextError() const { return _TextError; }
    const FString& GetSelect() const { return _Select; }
    auto GetSelectOptionCount() const -> int32 { return _Options.IsValid() ? _Options->GetRecords().Num() : 0; }
    const FString& GetSelectOptionsStatus() const { return _SelectOptionsStatus; }
    auto GetSelectChangedCount() const -> int32 { return _SelectChangedCount; }
    const FString& GetQuery() const { return _Query; }
    const FString& GetSelection() const { return _Selection; }
    const FString& GetContextActionKey() const { return _ContextActionKey; }
    auto GetContextActionCount() const -> int32 { return _ContextActionCount; }
    const FString& GetNestedTabsSelection() const { return _NestedTabsSelection; }
    auto IsNestedTabsDetailsEnabled() const -> bool { return _NestedTabsDetailsEnabled; }
    auto IsNestedTabsLongLabel() const -> bool { return _NestedTabsLongLabel; }
    auto GetNestedTabsDetailsLabel() const -> FString { return _NestedTabsLongLabel ? TEXT("Details with a deliberately long native tab label") : TEXT("Details"); }
    const FString& GetNestedTabsDraft() const { return _NestedTabsDraft; }
    auto GetNestedTabsSelectionChangedCount() const -> int32 { return _NestedTabsSelectionChangedCount; }
    auto GetNestedTabsDraftChangedCount() const -> int32 { return _NestedTabsDraftChangedCount; }
    const FString& GetStatus() const { return _Status; }
    const FString& GetReloadFailureKind() const { return _ReloadFailureKind; }
    const FString& GetReloadDiagnostic() const { return _ReloadDiagnostic; }
    auto GetReloadRevision() const -> int64 { return _View.IsValid() ? _View->GetRevision() : 0; }
    const FString& GetBatchStatus() const { return _BatchStatus; }
    auto GetBatchActionCount() const -> int32 { return _BatchActionCount; }
    auto IsSlotProbeDetailsPresent() const -> bool;
    auto GetSlotProbeStatus() const -> FString;
    auto GetSlotProbeDetailsState() const -> FString;
    auto GetSlotProbeDetailsActionCount() const -> int32 { return _SlotProbeDetailsActionCount; }
    auto GetSlotProbeContentActionCount() const -> int32 { return _SlotProbeContentActionCount; }
    auto GetNumber() const -> float { return _Number; }
    auto GetNumberProposal() const -> float { return _NumberProposal; }
    auto GetNumberCommitCount() const -> int32 { return _NumberCommitCount; }
    auto IsEnabled() const -> bool { return _Enabled; }
    auto IsReadOnly() const -> bool { return _ReadOnly; }
    auto IsLayoutPreviewPopulated() const -> bool { return _LayoutPreviewPopulated; }
    auto IsDialogOpen() const -> bool { return _DialogOpen; }
    auto GetRecordCount() const -> int32 { return _Records.IsValid() ? _Records->GetRecords().Num() : 0; }
    auto GetTreeLabCollection() const -> TSharedPtr<FCkUiTreeCollection> { return _TreeLab; }
    const FString& GetTreeLabSelection() const { return _TreeLabSelection; }
    const FString& GetTreeLabStatus() const { return _TreeLabStatus; }
    auto GetRepeatItemCount() const -> int32 { return _RepeatItems.IsValid() ? _RepeatItems->GetRecords().Num() : 0; }
    auto HasRepeatItem(const FString& InKey) const -> bool { return _RepeatItems.IsValid() && _RepeatItems->FindRecord(InKey).IsValid(); }
    auto GetFirstRepeatItemKey() const -> FString
    {
        return _RepeatItems.IsValid() && !_RepeatItems->GetRecords().IsEmpty() ? _RepeatItems->GetRecords()[0]->GetKey() : FString{};
    }
    auto GetRepeatItemText(const FString& InKey) const -> FString
    {
        const TSharedPtr<const FCkUiRecord> Record = _RepeatItems.IsValid() ? _RepeatItems->FindRecord(InKey) : nullptr;
        const FCkUiFieldValue* Value = Record.IsValid() ? Record->FindField(TEXT("text")) : nullptr;
        return Value != nullptr && Value->Kind == ECkUiFieldKind::Text ? Value->Text.ToString() : FString{};
    }
    auto HasRecord(const FString& InKey) const -> bool { return _Records.IsValid() && _Records->FindRecord(InKey).IsValid(); }
    auto GetFirstRecordKey() const -> FString
    {
        return _Records.IsValid() && !_Records->GetRecords().IsEmpty() ? _Records->GetRecords()[0]->GetKey() : FString{};
    }
    auto GetRecordText(const FString& InKey) const -> FString
    {
        const TSharedPtr<const FCkUiRecord> Record = _Records.IsValid() ? _Records->FindRecord(InKey) : nullptr;
        const FCkUiFieldValue* Value = Record.IsValid() ? Record->FindField(TEXT("text")) : nullptr;
        return Value != nullptr && Value->Kind == ECkUiFieldKind::Text ? Value->Text.ToString() : FString{};
    }
    auto IsRecordExpanded(const FString& InKey) const -> bool { return _ExpandedRecordKeys.Contains(InKey); }
    auto IsRepeatItemExpanded(const FString& InKey) const -> bool { return IsRecordExpanded(InKey); }

private:
    explicit FCkCapabilityGalleryModel(FSimpleDelegate InClose) : _Close(MoveTemp(InClose)) {}

    auto Reset() -> void;
    auto SetPage(const FString& InPage) -> bool;
    auto SetEditableText(const FString& InText, bool bCommit) -> void;
    auto SetNestedTabsSelection(const FString& InSelection) -> void;
    auto ToggleLayoutPreview() -> void;
    auto SetNestedTabsDraft(const FString& InDraft) -> void;
    auto ToggleNestedTabsDetailsEnabled() -> void;
    auto ToggleNestedTabsLongLabel() -> void;
    auto ResetNestedTabsLab() -> void;
    auto SetTableCount(int32 InCount) -> void;
    auto ReverseTableRecords() -> void;
    auto UpdateSelectedRecord() -> void;
    auto RemoveSelectedRecord() -> void;
    auto ReinsertSelectedRecord() -> void;
    auto PublishTableRecords(int32 InCount, bool bReverse, const TSet<FString>& InRemovedKeys,
        const TSet<FString>& InUpdatedKeys) -> bool;
    auto PublishRepeatItems(const TArray<FString>& InOrder, const TSet<FString>& InRemovedKeys,
        const TSet<FString>& InUpdatedKeys, const TSet<FString>& InExpandedKeys) -> bool;
    auto PublishTreeLab(const TArray<FString>& InChildOrder) -> bool;
    auto GetRecordsTable() const -> TSharedPtr<SCkUiTable>;
    auto GetTreeLab() const -> TSharedPtr<SCkUiTree>;
    auto SyncSelectionFromTable() -> void;
    auto ToggleRepeat(const FString& InKey) -> void;
    auto ReverseRepeatItems() -> void;
    auto UpdateRepeatRecordZero() -> void;
    auto RemoveRepeatRecordZero() -> void;
    auto ReinsertRepeatRecord() -> void;
    auto ResetRepeatItems() -> void;
    auto InsertTreeLabNode() -> void;
    auto ReverseTreeLabNodes() -> void;
    auto RemoveSelectedTreeLabNode() -> void;
    auto ReinsertTreeLabNode() -> void;
    auto ResetTreeLab() -> void;
    auto EmptySelectOptions() -> void;
    auto RestoreSelectOptions() -> void;
    auto RunBatchAccept() -> void;
    auto RunBatchRejectSecond() -> void;
    auto ReloadSlotProbe(bool bIncludeDetails, bool bReject) -> void;
    auto RunRejectedReload(const FString& InFailureKind) -> void;

    FSimpleDelegate _Close;
    TSharedPtr<FCkUiView> _View;
    TSharedPtr<FCkUiView> _BatchPreviewView;
    TSharedPtr<FCkUiCollection> _Options;
    TSharedPtr<FCkUiCollection> _Records;
    TSharedPtr<FCkUiCollection> _RepeatItems;
    TSharedPtr<FCkUiTreeCollection> _Navigation;
    TSharedPtr<FCkUiTreeCollection> _TreeLab;
    FString _Page = TEXT("layout");
    FString _Query;
    FString _Select = TEXT("compact");
    FString _SelectOptionsStatus = TEXT("Options ready");
    FString _EditableText = TEXT("Editable text");
    FString _CommittedText = TEXT("Editable text");
    FString _TextError;
    FString _Status = TEXT("Ready");
    FString _ReloadFailureKind = TEXT("No reload attempted");
    FString _ReloadDiagnostic = TEXT("No reload attempt has been made.");
    FString _BatchStatus = TEXT("Batch preview ready");
    FString _SlotProbeFailure;
    FString _Selection;
    FString _ContextActionKey = TEXT("No context item inspected");
    FString _TreeLabSelection;
    FString _TreeLabStatus = TEXT("Tree lab ready");
    FString _NestedTabsSelection = TEXT("overview");
    FString _NestedTabsDraft = TEXT("Draft text stays with this Details panel.");
    FString _LastRemovedRecordKey;
    float _Number = 24.0f;
    float _NumberProposal = 24.0f;
    float _Slider = 0.5f;
    bool _Enabled = true;
    bool _ReadOnly = false;
    bool _LayoutPreviewPopulated = true;
    bool _DialogOpen = false;
    bool _ErrorVisible = false;
    bool _NestedTabsDetailsEnabled = true;
    bool _NestedTabsLongLabel = false;
    int32 _NestedTabsSelectionChangedCount = 0;
    int32 _NestedTabsDraftChangedCount = 0;
    int32 _SelectChangedCount = 0;
    int32 _ContextActionCount = 0;
    int32 _NumberCommitCount = 0;
    int32 _BatchActionCount = 0;
    int32 _SlotProbeDetailsActionCount = 0;
    int32 _SlotProbeContentActionCount = 0;
    int64 _SlotProbeFailureRevision = INDEX_NONE;
    int32 _TableRecordCount = 3;
    bool _TableRecordsReversed = false;
    TSet<FString> _RemovedTableRecordKeys;
    TSet<FString> _UpdatedTableRecordKeys;
    TSet<FString> _ExpandedRecordKeys;
    TArray<FString> _TreeLabChildOrder{TEXT("tree-alpha"), TEXT("tree-beta")};
    FString _LastRemovedTreeLabKey;
    TArray<FString> _RepeatItemOrder{TEXT("record-0"), TEXT("record-1"), TEXT("record-2")};
    TSet<FString> _RemovedRepeatItemKeys;
    TSet<FString> _UpdatedRepeatItemKeys;
    FString _LastRemovedRepeatItemKey;
};
