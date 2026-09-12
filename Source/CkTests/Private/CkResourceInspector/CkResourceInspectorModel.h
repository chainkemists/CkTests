#pragma once

#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/CkUiTreeCollection.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "CoreMinimal.h"

/** Runtime-only data model for the authored Resource Inspector sample. */
class FCkResourceInspectorModel final : public TSharedFromThis<FCkResourceInspectorModel>
{
public:
    static auto TryCreate(FSimpleDelegate InClose, TSharedPtr<FCkResourceInspectorModel>& OutModel, FString& OutError, int32 InSlateUserIndex) -> bool;

    auto GetView() const -> TSharedRef<FCkUiView>;
    auto GetRoot() const -> TSharedRef<SWidget>;
    auto GetCollection() const -> TSharedPtr<FCkUiCollection>;
    auto GetActivity() const -> TSharedPtr<FCkUiCollection>;
    auto GetNavigation() const -> TSharedPtr<FCkUiTreeCollection>;
    auto GetPinnedSnapshots() const -> TSharedPtr<FCkUiCollection>;
    auto TrySetRowCount(int32 InRowCount, FString& OutError) -> bool;
    auto TrySetPresentationState(FString InKey) -> bool;
    auto TrySetCategory(FString InKey, FString& OutError) -> bool;
    auto TrySetSessionNote(FString InNote, FString& OutError) -> bool;
    auto TryPinSelected(FString& OutError) -> bool;
    auto TrySetDetailTab(const FString& InKey) -> bool;
    const FString& GetDetailTab() const { return _DetailTab; }
    const FString& GetPresentationState() const { return _PresentationState; }
    const FString& GetQuery() const { return _Query; }
    const FString& GetCategory() const { return _Category; }
    const FString& GetSessionNote() const { return _SessionNote; }
    const FString& GetSessionNoteError() const { return _SessionNoteError; }
    int32 GetRowCount() const { return _RowCount; }
    bool IsSessionNoteLocked() const { return _SessionNoteLocked; }
    auto SetSessionNoteLocked(bool InLocked) -> void { _SessionNoteLocked = InLocked; }
    bool HasSessionNoteError() const { return !_SessionNoteError.IsEmpty(); }
    bool IsClearPinsDialogOpen() const { return _ClearPinsDialogOpen; }
    bool IsLongLabels() const { return _bLongLabels; }
    auto GetSearchPlaceholder() const -> FText;
    auto GetNameColumnLabel() const -> FText;

private:
    explicit FCkResourceInspectorModel(FSimpleDelegate InClose) : _Close(MoveTemp(InClose)) {}

    auto MakeRecords(int32 InRowCount) const -> TArray<FCkUiRecordData>;
    auto MakeNavigationNodes() const -> TArray<FCkUiTreeNodeData>;
    auto IsKnownCategory(const FString& InKey) const -> bool;
    auto IsKnownPresentationState(const FString& InKey) const -> bool;
    auto CategoryLabel() const -> FString;
    auto HeaderCount() const -> FText;
    auto SelectedTitle() const -> FText;
    auto SelectedDetail() const -> FText;
    auto LayoutError() const -> FText;
    auto HasSelection() const -> bool;
    auto IsEmpty() const -> bool;
    auto HasLayoutError() const -> bool;
    auto FindSelectedRecord() const -> TSharedPtr<const FCkUiRecord>;
    auto TryTogglePinnedSnapshot(const FString& InKey, FString& OutError) -> bool;
    auto TryRemovePinnedSnapshot(const FString& InKey, FString& OutError) -> bool;
    auto PublishPinnedSnapshots(TArray<FCkUiRecordData> InRecords, FString& OutError) -> bool;
    auto AppendActivity(FString InMessage) -> void;
    auto OnSelectionChanged(TOptional<FString> InKey, ESelectInfo::Type InSelectionType) -> void;
    auto OnCategorySelectionChanged(TOptional<FString> InKey, ESelectInfo::Type InSelectionType) -> void;
    auto ClearSelection() -> void;
    auto InvokeClose() -> void;
    auto ConfirmClearPins() -> void;

    FSimpleDelegate _Close;
    TSharedPtr<FCkUiCollection> _Collection;
    TSharedPtr<FCkUiCollection> _Activity;
    TSharedPtr<FCkUiCollection> _PinnedSnapshots;
    TSharedPtr<FCkUiTreeCollection> _Navigation;
    TSharedPtr<FCkUiView> _View;
    FString _Query;
    FString _SessionNote;
    FString _SessionNoteError;
    bool _SessionNoteLocked = false;
    bool _ClearPinsDialogOpen = false;
    TOptional<FString> _SelectedKey;
    FString _Category = TEXT("all");
    FString _DetailTab = TEXT("overview");
    FString _PresentationState = TEXT("ready");
    int32 _RowCount = 12;
    bool _bLongLabels = false;
    uint64 _NextActivitySequence = 1;
    TArray<FCkUiRecordData> _ActivityRecords;
    TArray<FString> _QueuedActivityMessages;
    bool _bMutatingScenario = false;
    bool _bMutatingPinnedSnapshots = false;
    bool _bPublishingActivity = false;
};
