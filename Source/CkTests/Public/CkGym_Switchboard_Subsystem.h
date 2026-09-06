#pragma once

#include "CoreMinimal.h"

#include "CkCore/Macros/CkMacros.h"

#include "CkGym_ControlPanelTypes.h"
#include "CkGym_StartupSettings.h"

#include "CkInput/CkInputLayer_Fragment_Data.h"
#include "CkInput/CkInputSource_Fragment_Data.h"

#include <Containers/Ticker.h>
#include <Subsystems/LocalPlayerSubsystem.h>

#include "CkGym_Switchboard_Subsystem.generated.h"

class SCkGym_ControlPanel;
class SCkGym_Switchboard;

// --------------------------------------------------------------------------------------------------------------------
//
// The gym switchboard: a Slate widget on the game viewport whose interaction runs entirely through
// CkInput's raw-input layer stack. While open, the menu's layer holds a catch-all Consume capture,
// so everything below it — control panel, pawn movement, global debug actions — goes structurally
// silent; there is no suspension flag to forget to clear.
//
// The widget itself is HitTestInvisible and never takes keyboard focus (a focused Slate widget
// would pause CkInput's Slate writer — the direct-viewport-focus gate). Keys reach the menu only
// via OnCaptureTriggered on its layer.
//
// Tab opens it as a GLOBAL ACTION on the local player's source, armed by the gym HUD
// (Request_ArmTabOpen) so only gym worlds ever register it; while open, the catch-all consumes Tab
// before the global action can see it, and the menu treats it as close. Console fallback:
// `Ck.Gym.Switchboard`.
//
// --------------------------------------------------------------------------------------------------------------------

// One selectable gym row. RegistryIndex is the entry's position in the registry — the travel
// currency — carried through grouping and filtering so neither ever breaks the travel target.
struct FCkGym_Switchboard_Row
{
    int32 RegistryIndex = INDEX_NONE;
    FString DisplayName;
    FString Category;
};

struct FCkGym_Switchboard_Group
{
    FString Category;
    FLinearColor Hue = FLinearColor::White;
    TArray<FCkGym_Switchboard_Row> Rows;
};

// The switchboard's whole display state: rebuilt from the registry on every open, mutated by key
// handling, rendered by SCkGym_Switchboard::Refresh. Selection is by index into Groups /
// the active row list; the widget windows the row list itself (MaxVisibleRows).
struct FCkGym_Switchboard_Model
{
    TArray<FCkGym_Switchboard_Group> Groups;

    int32 SelectedGroupIndex = 0;
    int32 SelectedRowIndex = 0;

    FString Filter;
    TArray<FCkGym_Switchboard_Row> FilteredRows;

    int32 CurrentGymRegistryIndex = INDEX_NONE;

    // Snapshot of the per-user startup settings, so the menu surfaces (and edits) them without
    // reaching into the CDO from widget code. [1] cycles the mode, [2] pins the selected gym
    // (digits, not F-keys — Unreal owns those for rendering debug modes; digits left the filter
    // corpus to become the menu's command keys).
    ECkGym_StartupMode StartupMode = ECkGym_StartupMode::Cycler;
    FString DefaultGymName;
    FString LastGymName;

    static constexpr int32 MaxVisibleRows = 18;

    auto Get_IsFiltered() const -> bool { return NOT Filter.IsEmpty(); }

    // The list Up/Down navigates: the selected group's rows, or the filtered flattening.
    auto Get_ActiveRows() const -> const TArray<FCkGym_Switchboard_Row>&;
};

// --------------------------------------------------------------------------------------------------------------------

UCLASS(NotBlueprintable)
class CKTESTS_API UCkGym_Switchboard_Subsystem : public ULocalPlayerSubsystem
{
    GENERATED_BODY()

public:
    // The gym input stack, top to bottom. Global actions occupy the reserved bottom.
    // MUST match CkGym_InputStack in Script/Common/CkGym_InputStack.as.
    static constexpr int32 LayerPriority_Menu = 1000;
    static constexpr int32 LayerPriority_ControlPanel = 500;
    static constexpr int32 LayerPriority_Pawn = 100;

public:
    virtual void Initialize(FSubsystemCollectionBase& InCollection) override;
    virtual void Deinitialize() override;

public:
    // Registers the Tab global action that opens the switchboard. Called by the gym HUD (gym
    // worlds only, by HUDClass construction); idempotent, retried until the input source exists.
    UFUNCTION(BlueprintCallable, Category = "Ck|Gym|Switchboard",
              DisplayName = "[Ck][GymSwitchboard] Arm Tab Open")
    void
    Request_ArmTabOpen();

    UFUNCTION(BlueprintPure, Category = "Ck|Gym|Switchboard",
              DisplayName = "[Ck][GymSwitchboard] Get IsOpen")
    bool
    Get_IsOpen() const;

    // The gym HUD pushes the control panel's state here every frame; the Slate panel re-renders
    // only when something changed. InMaxWidth bounds the card (the HUD clamps it against the
    // viewport); InMode is the H cycle (rows keep firing in every mode, only the drawing changes);
    // InFullyHidden is the startup-suppression window, which is NOT a mode - nothing draws at all
    // and the user's choice must survive it.
    UFUNCTION(BlueprintCallable, Category = "Ck|Gym|Switchboard",
              DisplayName = "[Ck][GymSwitchboard] Set ControlPanel")
    void
    Request_SetControlPanel(
        const FString& InTitle,
        const TArray<FCkGym_ControlRow>& InRows,
        FVector2D InOffset,
        float InMaxWidth,
        ECkGym_ControlPanel_Mode InMode,
        bool InFullyHidden);

    auto
    Request_Toggle() -> void;

    UFUNCTION(BlueprintCallable, Category = "Ck|Gym|Switchboard",
              DisplayName = "[Ck][GymSwitchboard] Open")
    void
    Request_Open();

    UFUNCTION(BlueprintCallable, Category = "Ck|Gym|Switchboard",
              DisplayName = "[Ck][GymSwitchboard] Close")
    void
    Request_Close();

public:
    // Pure model builders/steppers, static for unit-testability.

    // Groups + sorts the registry rows: categories alphabetical with the empty-category fallback
    // bucket ("Misc") last; rows alphabetical inside each group.
    static auto
    Build_Groups(
        const TArray<struct FCkGym_Entry>& InEntries) -> TArray<FCkGym_Switchboard_Group>;

    // Ranked filter over all rows: every space-separated token must match DisplayName or Category
    // (case-insensitive substring); rows whose DisplayName starts with the first token rank first,
    // then word-boundary prefix matches, then the rest; ties alphabetical.
    static auto
    Build_FilteredRows(
        const TArray<FCkGym_Switchboard_Group>& InGroups,
        const FString& InFilter) -> TArray<FCkGym_Switchboard_Row>;

    // The control panel's Compact mode, as a pure row filter: every Header, every row that carries
    // a key, and the Status rows that carry a verdict or a warning survive, in declaration order.
    // What is dropped is the running commentary - a Compact panel answers "what can I press" and
    // "is anything wrong", nothing else.
    static auto
    Build_CompactRows(
        const TArray<FCkGym_ControlRow>& InRows) -> TArray<FCkGym_ControlRow>;

    static auto
    Get_CategoryHue(
        const FString& InCategory) -> FLinearColor;

private:
    UFUNCTION()
    void
    OnMenuCaptureTriggered(
        FCk_Handle_InputLayer InLayer,
        FCk_InputSource_RawEvent InEvent,
        FCk_InputLayer_Capture InCapture);

    UFUNCTION()
    void
    OnGlobalCaptureTriggered(
        FCk_Handle_InputLayer InLayer,
        FCk_InputSource_RawEvent InEvent,
        FCk_InputLayer_Capture InCapture);

private:
    auto
    DoEnsureMenuLayer() -> bool;

    auto
    DoRemoveViewportWidget() -> void;

    auto
    DoBuildModel() -> void;

    auto
    DoHandlePressedKey(
        const FKey& InKey) -> void;

    auto
    DoMoveSelection(
        int32 InDelta) -> void;

    auto
    DoMoveGroup(
        int32 InDelta) -> void;

    auto
    DoApplyFilterChange() -> void;

    auto
    DoTravelToSelection() -> void;

    auto
    DoRefreshWidget() -> void;

    auto
    DoTickRepeat(
        float InDeltaTime) -> bool;

private:
    auto
    DoRefreshPanelWidget() -> void;

    auto
    DoRefreshSettingsInModel() -> void;

private:
    TSharedPtr<SCkGym_Switchboard> _RootWidget;

    TSharedPtr<SCkGym_ControlPanel> _PanelWidget;
    FString _PanelTitle;
    TArray<FCkGym_ControlRow> _PanelRows;
    FVector2D _PanelOffset = FVector2D::ZeroVector;
    float _PanelMaxWidth = 0.0f;
    ECkGym_ControlPanel_Mode _PanelMode = ECkGym_ControlPanel_Mode::Full;
    bool _PanelFullyHidden = true;

    FCk_Handle_InputLayer _MenuLayer;

    FCkGym_Switchboard_Model _Model;

    bool _IsOpen = false;

    // The world-scoped source the Tab global action is currently registered on; a travel makes
    // this stale (dead entity) and Request_ArmTabOpen re-arms on the new world's source.
    FCk_Handle_InputSource _ArmedSource;

    FTSTicker::FDelegateHandle _RepeatTickerHandle;
    FKey _RepeatKey;
    float _RepeatCountdown = 0.0f;
};
