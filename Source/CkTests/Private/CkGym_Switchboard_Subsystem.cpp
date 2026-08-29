#include "CkGym_Switchboard_Subsystem.h"

#include "CkGymRegistry_Utils.h"
#include "CkGym_Registry.h"
#include "CkTests/CkTests_Log.h"
#include "Slate/SCkGym_ControlPanel.h"
#include "Slate/SCkGym_Switchboard.h"

#include "CkCore/Algorithms/CkAlgorithms.h"
#include "CkCore/Validation/CkIsValid.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"

#include "CkInput/CkInputLayer_Utils.h"
#include "CkInput/Subsystem/CkInputSource_Subsystem.h"

#include <Engine/GameInstance.h>
#include <Engine/GameViewportClient.h>
#include <Engine/LocalPlayer.h>
#include <Engine/World.h>
#include <HAL/IConsoleManager.h>

// --------------------------------------------------------------------------------------------------------------------

namespace ck_gym_switchboard_subsystem
{
    // Below CkEntityDebugOverlay's 100 so the debug overlay keeps the foreground when both are up;
    // the control panel sits under the switchboard.
    constexpr int32 SwitchboardZOrder = 90;
    constexpr int32 ControlPanelZOrder = 85;

    constexpr auto FallbackCategory = TEXT("Misc");

    // Key-repeat feel, matching the retired Canvas menu.
    constexpr float RepeatDelaySeconds = 0.35f;
    constexpr float RepeatRateSeconds = 0.08f;

    auto Get_IsRepeatable(const FKey& InKey) -> bool
    {
        return InKey == EKeys::Up || InKey == EKeys::Down ||
               InKey == EKeys::Left || InKey == EKeys::Right ||
               InKey == EKeys::BackSpace;
    }

    // The filter corpus accepts single-character keys (letters/digits) plus space; everything else
    // is navigation or ignored. Unset = not a filter key.
    auto TryGet_FilterChar(const FKey& InKey) -> TOptional<TCHAR>
    {
        if (InKey == EKeys::SpaceBar)
        { return TEXT(' '); }

        const auto KeyName = InKey.GetFName().ToString();

        if (KeyName.Len() == 1)
        {
            const auto Char = KeyName[0];

            if (FChar::IsAlpha(Char))
            { return FChar::ToLower(Char); }

            if (FChar::IsDigit(Char))
            { return Char; }
        }

        static const TMap<FKey, TCHAR> DigitKeys = {
            {EKeys::Zero, TEXT('0')}, {EKeys::One, TEXT('1')}, {EKeys::Two, TEXT('2')},
            {EKeys::Three, TEXT('3')}, {EKeys::Four, TEXT('4')}, {EKeys::Five, TEXT('5')},
            {EKeys::Six, TEXT('6')}, {EKeys::Seven, TEXT('7')}, {EKeys::Eight, TEXT('8')},
            {EKeys::Nine, TEXT('9')},
            {EKeys::NumPadZero, TEXT('0')}, {EKeys::NumPadOne, TEXT('1')}, {EKeys::NumPadTwo, TEXT('2')},
            {EKeys::NumPadThree, TEXT('3')}, {EKeys::NumPadFour, TEXT('4')}, {EKeys::NumPadFive, TEXT('5')},
            {EKeys::NumPadSix, TEXT('6')}, {EKeys::NumPadSeven, TEXT('7')}, {EKeys::NumPadEight, TEXT('8')},
            {EKeys::NumPadNine, TEXT('9')}};

        if (const auto* Found = DigitKeys.Find(InKey))
        { return *Found; }

        return {};
    }
}

// --------------------------------------------------------------------------------------------------------------------

auto
    FCkGym_Switchboard_Model::
    Get_ActiveRows() const
    -> const TArray<FCkGym_Switchboard_Row>&
{
    if (Get_IsFiltered())
    { return FilteredRows; }

    static const TArray<FCkGym_Switchboard_Row> Empty;

    if (NOT Groups.IsValidIndex(SelectedGroupIndex))
    { return Empty; }

    return Groups[SelectedGroupIndex].Rows;
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCkGym_Switchboard_Subsystem::
    Initialize(
        FSubsystemCollectionBase& InCollection)
    -> void
{
    Super::Initialize(InCollection);

    // Function-local static: registered once per process, resolves the acting subsystem through the
    // command's own world each invocation — so PIE restarts and multi-client sessions need no
    // ownership handoff.
    static FAutoConsoleCommandWithWorld ToggleCommand(
        TEXT("Ck.Gym.Switchboard"),
        TEXT("Toggles the gym switchboard for the world's first local player."),
        FConsoleCommandWithWorldDelegate::CreateLambda([](UWorld* InWorld)
        {
            if (NOT IsValid(InWorld))
            { return; }

            const auto* GameInstance = InWorld->GetGameInstance();
            if (NOT IsValid(GameInstance))
            { return; }

            auto* LocalPlayer = GameInstance->GetLocalPlayerByIndex(0);
            if (NOT IsValid(LocalPlayer))
            { return; }

            if (auto* Subsystem = LocalPlayer->GetSubsystem<UCkGym_Switchboard_Subsystem>();
                IsValid(Subsystem))
            { Subsystem->Request_Toggle(); }
        }));
}

auto
    UCkGym_Switchboard_Subsystem::
    Deinitialize()
    -> void
{
    if (_RepeatTickerHandle.IsValid())
    {
        FTSTicker::GetCoreTicker().RemoveTicker(_RepeatTickerHandle);
        _RepeatTickerHandle.Reset();
    }

    DoRemoveViewportWidget();

    if (_PanelWidget.IsValid())
    {
        if (const auto* LocalPlayer = GetLocalPlayer();
            ck::IsValid(LocalPlayer))
        {
            if (auto* ViewportClient = LocalPlayer->ViewportClient.Get();
                IsValid(ViewportClient))
            { ViewportClient->RemoveViewportWidgetContent(_PanelWidget.ToSharedRef()); }
        }

        _PanelWidget.Reset();
    }

    // The menu layer's entity has a transient owner and dies with its world's registry; nothing to
    // destroy explicitly here, and the handle must not be poked mid-teardown.
    _MenuLayer = {};
    _IsOpen = false;
    _ArmedSource = {};

    Super::Deinitialize();
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCkGym_Switchboard_Subsystem::
    Request_ArmTabOpen()
    -> void
{
    auto* LocalPlayer = GetLocalPlayer();
    if (ck::Is_NOT_Valid(LocalPlayer))
    { return; }

    auto* SourceSubsystem = LocalPlayer->GetSubsystem<UCk_InputSource_Subsystem>();
    if (ck::Is_NOT_Valid(SourceSubsystem))
    { return; }

    auto Source = SourceSubsystem->Get_InputSource();
    if (ck::Is_NOT_Valid(Source))
    { return; }

    // The source entity is per-WORLD while this subsystem is per-LOCAL-PLAYER and survives
    // ServerTravel — so the arm has to follow the source, not happen once. A stale armed-source
    // handle (dead world) compares unequal to the fresh one and re-arms.
    if (_ArmedSource == Source)
    { return; }

    // Traveling while the menu was open leaves _IsOpen pointing at a dead layer; reset so the
    // fresh world starts closed and the next Tab opens cleanly.
    if (_IsOpen && ck::Is_NOT_Valid(_MenuLayer))
    {
        DoRemoveViewportWidget();
        _IsOpen = false;
    }

    UCk_Utils_InputLayer_UE::Request_AddGlobalAction(Source,
        FCk_Request_InputLayer_AddGlobalAction{EKeys::Tab}, {});

    // The reserved layer exists synchronously after the first registration.
    auto GlobalLayer = UCk_Utils_InputLayer_UE::TryGet_GlobalActionLayer(Source);
    if (ck::Is_NOT_Valid(GlobalLayer))
    { return; }

    // The layer is shared by every global action on this source, so the handler filters on Tab.
    auto Delegate = FCk_Delegate_InputLayer_CaptureTriggered{};
    Delegate.BindDynamic(this, &UCkGym_Switchboard_Subsystem::OnGlobalCaptureTriggered);

    UCk_Utils_InputLayer_UE::BindTo_OnCaptureTriggered(GlobalLayer, Delegate,
        ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
        ECk_Signal_PostFireBehavior::DoNothing);

    _ArmedSource = Source;
    ck::tests::Log(TEXT("[GymSwitchboard] Tab open armed (global action)"));
}

auto
    UCkGym_Switchboard_Subsystem::
    Get_IsOpen() const
    -> bool
{
    return _IsOpen;
}

auto
    UCkGym_Switchboard_Subsystem::
    Request_SetControlPanel(
        const FString& InTitle,
        const TArray<FCkGym_ControlRow>& InRows,
        FVector2D InOffset,
        bool InPanelCollapsed,
        bool InFullyHidden)
    -> void
{
    const auto Unchanged =
        _PanelWidget.IsValid() &&
        _PanelTitle == InTitle && _PanelRows == InRows && _PanelOffset == InOffset &&
        _PanelCollapsed == InPanelCollapsed && _PanelFullyHidden == InFullyHidden;

    if (Unchanged)
    { return; }

    _PanelTitle = InTitle;
    _PanelRows = InRows;
    _PanelOffset = InOffset;
    _PanelCollapsed = InPanelCollapsed;
    _PanelFullyHidden = InFullyHidden;

    if (NOT _PanelWidget.IsValid())
    {
        auto* LocalPlayer = GetLocalPlayer();
        auto* ViewportClient = ck::IsValid(LocalPlayer) ? LocalPlayer->ViewportClient.Get() : nullptr;

        if (NOT IsValid(ViewportClient))
        { return; }

        _PanelWidget = SNew(SCkGym_ControlPanel);
        ViewportClient->AddViewportWidgetContent(_PanelWidget.ToSharedRef(),
            ck_gym_switchboard_subsystem::ControlPanelZOrder);
    }

    DoRefreshPanelWidget();
}

auto
    UCkGym_Switchboard_Subsystem::
    DoRefreshPanelWidget()
    -> void
{
    if (NOT _PanelWidget.IsValid())
    { return; }

    // The panel vanishes outright during startup suppression and while the switchboard is open
    // (the menu draws over its corner and owns every key anyway).
    if (_PanelFullyHidden || _IsOpen)
    {
        _PanelWidget->SetVisibility(EVisibility::Collapsed);
        return;
    }

    _PanelWidget->SetVisibility(EVisibility::HitTestInvisible);
    _PanelWidget->Refresh(_PanelTitle, _PanelRows, _PanelOffset, _PanelCollapsed);
}

auto
    UCkGym_Switchboard_Subsystem::
    Request_Toggle()
    -> void
{
    if (_IsOpen)
    { Request_Close(); }
    else
    { Request_Open(); }
}

auto
    UCkGym_Switchboard_Subsystem::
    Request_Open()
    -> void
{
    if (_IsOpen)
    { return; }

    if (NOT DoEnsureMenuLayer())
    { return; }

    // While open the menu consumes EVERYTHING. Deferred by one routing pass by contract, so the
    // frame that opened the menu doesn't have its remaining input swallowed.
    UCk_Utils_InputLayer_UE::Request_AddCapture(_MenuLayer,
        FCk_Request_InputLayer_AddCapture{
            UCk_Utils_InputLayer_UE::Make_CatchAllCapture(ECk_InputLayer_CaptureBehavior::Consume)},
        {});

    DoBuildModel();

    auto* LocalPlayer = GetLocalPlayer();
    if (auto* ViewportClient = ck::IsValid(LocalPlayer) ? LocalPlayer->ViewportClient.Get() : nullptr;
        IsValid(ViewportClient))
    {
        _RootWidget = SNew(SCkGym_Switchboard);
        _RootWidget->Refresh(_Model);

        ViewportClient->AddViewportWidgetContent(_RootWidget.ToSharedRef(),
            ck_gym_switchboard_subsystem::SwitchboardZOrder);
    }

    _RepeatKey = FKey{};
    _RepeatTickerHandle = FTSTicker::GetCoreTicker().AddTicker(
        FTickerDelegate::CreateUObject(this, &UCkGym_Switchboard_Subsystem::DoTickRepeat), 0.0f);

    _IsOpen = true;
    DoRefreshPanelWidget();
    ck::tests::Log(TEXT("[GymSwitchboard] opened"));
}

auto
    UCkGym_Switchboard_Subsystem::
    Request_Close()
    -> void
{
    if (NOT _IsOpen)
    { return; }

    if (_RepeatTickerHandle.IsValid())
    {
        FTSTicker::GetCoreTicker().RemoveTicker(_RepeatTickerHandle);
        _RepeatTickerHandle.Reset();
    }
    _RepeatKey = FKey{};

    if (ck::IsValid(_MenuLayer))
    {
        UCk_Utils_InputLayer_UE::Request_RemoveCapture(_MenuLayer,
            FCk_Request_InputLayer_RemoveCapture{ECk_InputLayer_CaptureMatch::CatchAll, FKey{}},
            {});
    }

    DoRemoveViewportWidget();

    _IsOpen = false;
    DoRefreshPanelWidget();
    ck::tests::Log(TEXT("[GymSwitchboard] closed"));
}

// --------------------------------------------------------------------------------------------------------------------
// Model builders (static, unit-testable)
// --------------------------------------------------------------------------------------------------------------------

auto
    UCkGym_Switchboard_Subsystem::
    Build_Groups(
        const TArray<FCkGym_Entry>& InEntries)
    -> TArray<FCkGym_Switchboard_Group>
{
    using namespace ck_gym_switchboard_subsystem;

    auto Groups = TArray<FCkGym_Switchboard_Group>{};

    for (auto Index = 0; Index < InEntries.Num(); ++Index)
    {
        const auto& Entry = InEntries[Index];
        const auto Category = Entry.Category.IsEmpty() ? FString{FallbackCategory} : Entry.Category;

        auto* Group = Groups.FindByPredicate([&](const FCkGym_Switchboard_Group& InGroup)
        {
            return InGroup.Category == Category;
        });

        if (Group == nullptr)
        {
            auto& NewGroup = Groups.AddDefaulted_GetRef();
            NewGroup.Category = Category;
            NewGroup.Hue = Get_CategoryHue(Category);
            Group = &NewGroup;
        }

        auto& Row = Group->Rows.AddDefaulted_GetRef();
        Row.RegistryIndex = Index;
        Row.DisplayName = Entry.DisplayName;
        Row.Category = Category;
    }

    Groups.Sort([](const FCkGym_Switchboard_Group& InA, const FCkGym_Switchboard_Group& InB)
    {
        const auto AIsFallback = InA.Category == FallbackCategory;
        const auto BIsFallback = InB.Category == FallbackCategory;

        if (AIsFallback != BIsFallback)
        { return BIsFallback; }

        return InA.Category < InB.Category;
    });

    for (auto& Group : Groups)
    {
        Group.Rows.Sort([](const FCkGym_Switchboard_Row& InA, const FCkGym_Switchboard_Row& InB)
        {
            return InA.DisplayName < InB.DisplayName;
        });
    }

    return Groups;
}

auto
    UCkGym_Switchboard_Subsystem::
    Build_FilteredRows(
        const TArray<FCkGym_Switchboard_Group>& InGroups,
        const FString& InFilter)
    -> TArray<FCkGym_Switchboard_Row>
{
    auto Tokens = TArray<FString>{};
    InFilter.ParseIntoArray(Tokens, TEXT(" "), true);

    if (Tokens.Num() == 0)
    { return {}; }

    struct FRanked
    {
        FCkGym_Switchboard_Row Row;
        int32 Rank = 2;
    };

    auto Ranked = TArray<FRanked>{};

    for (const auto& Group : InGroups)
    {
        for (const auto& Row : Group.Rows)
        {
            const auto Corpus = FString::Printf(TEXT("%s %s"), *Row.DisplayName, *Row.Category);

            const auto AllTokensMatch = ck::algo::AllOf(Tokens, [&](const FString& InToken)
            {
                return Corpus.Contains(InToken, ESearchCase::IgnoreCase);
            });

            if (NOT AllTokensMatch)
            { continue; }

            // Rank 0: the display name starts with the first token. Rank 1: some word in the
            // corpus starts with it. Rank 2: substring-only.
            auto Rank = 2;

            if (Row.DisplayName.StartsWith(Tokens[0], ESearchCase::IgnoreCase))
            { Rank = 0; }
            else
            {
                auto Words = TArray<FString>{};
                Corpus.ParseIntoArray(Words, TEXT(" "), true);

                const auto AnyWordPrefix = ck::algo::AnyOf(Words, [&](const FString& InWord)
                {
                    return InWord.StartsWith(Tokens[0], ESearchCase::IgnoreCase);
                });

                if (AnyWordPrefix)
                { Rank = 1; }
            }

            Ranked.Add(FRanked{Row, Rank});
        }
    }

    Ranked.Sort([](const FRanked& InA, const FRanked& InB)
    {
        if (InA.Rank != InB.Rank)
        { return InA.Rank < InB.Rank; }

        return InA.Row.DisplayName < InB.Row.DisplayName;
    });

    auto Result = TArray<FCkGym_Switchboard_Row>{};
    Result.Reserve(Ranked.Num());

    for (const auto& Entry : Ranked)
    { Result.Add(Entry.Row); }

    return Result;
}

auto
    UCkGym_Switchboard_Subsystem::
    Get_CategoryHue(
        const FString& InCategory)
    -> FLinearColor
{
    // The debug overlay's provider-hue idiom: hash to a hue byte, fixed pastel saturation/value.
    const auto Hue = static_cast<uint8>(GetTypeHash(FName{*InCategory}) % 256);
    return FLinearColor::MakeFromHSV8(Hue, 150, 205);
}

// --------------------------------------------------------------------------------------------------------------------
// Key handling
// --------------------------------------------------------------------------------------------------------------------

auto
    UCkGym_Switchboard_Subsystem::
    OnMenuCaptureTriggered(
        FCk_Handle_InputLayer InLayer,
        FCk_InputSource_RawEvent InEvent,
        FCk_InputLayer_Capture InCapture)
    -> void
{
    using namespace ck_gym_switchboard_subsystem;

    if (NOT _IsOpen)
    { return; }

    const auto Key = InEvent.Get_Key();

    if (InEvent.Get_EventType() == ECk_InputSource_EventType::Released)
    {
        // A Release ALWAYS cancels repeat — including the synthetic Releases the focus-loss flush
        // writes, so a key held across an alt-tab never keeps repeating.
        if (Key == _RepeatKey)
        { _RepeatKey = FKey{}; }

        return;
    }

    if (InEvent.Get_EventType() != ECk_InputSource_EventType::Pressed)
    { return; }

    if (Get_IsRepeatable(Key))
    {
        _RepeatKey = Key;
        _RepeatCountdown = RepeatDelaySeconds;
    }

    DoHandlePressedKey(Key);
}

auto
    UCkGym_Switchboard_Subsystem::
    OnGlobalCaptureTriggered(
        FCk_Handle_InputLayer InLayer,
        FCk_InputSource_RawEvent InEvent,
        FCk_InputLayer_Capture InCapture)
    -> void
{
    // The global-action layer is shared; only Tab belongs to the switchboard. While the menu is
    // open its catch-all consumes Tab before the walk reaches the bottom, so this only ever opens.
    if (InEvent.Get_Key() != EKeys::Tab)
    { return; }

    if (InEvent.Get_EventType() != ECk_InputSource_EventType::Pressed)
    { return; }

    Request_Open();
}

auto
    UCkGym_Switchboard_Subsystem::
    DoHandlePressedKey(
        const FKey& InKey)
    -> void
{
    using namespace ck_gym_switchboard_subsystem;

    if (InKey == EKeys::Tab)
    {
        Request_Close();
        return;
    }

    if (InKey == EKeys::Escape)
    {
        if (_Model.Get_IsFiltered())
        {
            _Model.Filter.Empty();
            DoApplyFilterChange();
        }
        else
        {
            Request_Close();
        }
        return;
    }

    if (InKey == EKeys::Enter)
    {
        DoTravelToSelection();
        return;
    }

    if (InKey == EKeys::Up)    { DoMoveSelection(-1); return; }
    if (InKey == EKeys::Down)  { DoMoveSelection(+1); return; }
    if (InKey == EKeys::Left)  { DoMoveGroup(-1); return; }
    if (InKey == EKeys::Right) { DoMoveGroup(+1); return; }

    if (InKey == EKeys::BackSpace)
    {
        if (_Model.Get_IsFiltered())
        {
            _Model.Filter.LeftChopInline(1);
            DoApplyFilterChange();
        }
        return;
    }

    if (const auto FilterChar = TryGet_FilterChar(InKey);
        FilterChar.IsSet())
    {
        _Model.Filter.AppendChar(FilterChar.GetValue());
        DoApplyFilterChange();
    }
}

auto
    UCkGym_Switchboard_Subsystem::
    DoMoveSelection(
        int32 InDelta)
    -> void
{
    const auto& Rows = _Model.Get_ActiveRows();

    if (Rows.Num() == 0)
    { return; }

    _Model.SelectedRowIndex = FMath::Clamp(_Model.SelectedRowIndex + InDelta, 0, Rows.Num() - 1);
    DoRefreshWidget();
}

auto
    UCkGym_Switchboard_Subsystem::
    DoMoveGroup(
        int32 InDelta)
    -> void
{
    if (_Model.Get_IsFiltered() || _Model.Groups.Num() == 0)
    { return; }

    const auto Num = _Model.Groups.Num();
    _Model.SelectedGroupIndex = (_Model.SelectedGroupIndex + InDelta + Num) % Num;
    _Model.SelectedRowIndex = 0;
    DoRefreshWidget();
}

auto
    UCkGym_Switchboard_Subsystem::
    DoApplyFilterChange()
    -> void
{
    _Model.FilteredRows = Build_FilteredRows(_Model.Groups, _Model.Filter);
    _Model.SelectedRowIndex = 0;
    DoRefreshWidget();
}

auto
    UCkGym_Switchboard_Subsystem::
    DoTravelToSelection()
    -> void
{
    const auto& Rows = _Model.Get_ActiveRows();

    if (NOT Rows.IsValidIndex(_Model.SelectedRowIndex))
    { return; }

    const auto RegistryIndex = Rows[_Model.SelectedRowIndex].RegistryIndex;

    Request_Close();
    UCk_Utils_GymRegistry_UE::Request_TravelToGym(GetLocalPlayer(), RegistryIndex);
}

auto
    UCkGym_Switchboard_Subsystem::
    DoTickRepeat(
        float InDeltaTime)
    -> bool
{
    using namespace ck_gym_switchboard_subsystem;

    if (NOT _IsOpen || NOT _RepeatKey.IsValid())
    { return true; }

    _RepeatCountdown -= InDeltaTime;

    while (_RepeatCountdown <= 0.0f)
    {
        DoHandlePressedKey(_RepeatKey);
        _RepeatCountdown += RepeatRateSeconds;
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
// Internals
// --------------------------------------------------------------------------------------------------------------------

auto
    UCkGym_Switchboard_Subsystem::
    DoBuildModel()
    -> void
{
    _Model = FCkGym_Switchboard_Model{};

    auto* LocalPlayer = GetLocalPlayer();

    const auto Entries = UCk_Utils_GymRegistry_UE::Get_GymRegistry(LocalPlayer);
    _Model.Groups = Build_Groups(Entries);
    _Model.CurrentGymRegistryIndex = UCk_Utils_GymRegistry_UE::Get_CurrentGymIndex(LocalPlayer);

    // Land the selection on the running gym so reopening the menu shows where you are.
    if (_Model.CurrentGymRegistryIndex != INDEX_NONE)
    {
        for (auto GroupIndex = 0; GroupIndex < _Model.Groups.Num(); ++GroupIndex)
        {
            const auto RowIndex = _Model.Groups[GroupIndex].Rows.IndexOfByPredicate(
                [&](const FCkGym_Switchboard_Row& InRow)
                {
                    return InRow.RegistryIndex == _Model.CurrentGymRegistryIndex;
                });

            if (RowIndex != INDEX_NONE)
            {
                _Model.SelectedGroupIndex = GroupIndex;
                _Model.SelectedRowIndex = RowIndex;
                break;
            }
        }
    }
}

auto
    UCkGym_Switchboard_Subsystem::
    DoRefreshWidget()
    -> void
{
    if (_RootWidget.IsValid())
    { _RootWidget->Refresh(_Model); }
}

auto
    UCkGym_Switchboard_Subsystem::
    DoEnsureMenuLayer()
    -> bool
{
    if (ck::IsValid(_MenuLayer))
    { return true; }

    auto* LocalPlayer = GetLocalPlayer();
    if (ck::Is_NOT_Valid(LocalPlayer))
    {
        ck::tests::Warning(TEXT("[GymSwitchboard] no local player - cannot open"));
        return false;
    }

    auto* SourceSubsystem = LocalPlayer->GetSubsystem<UCk_InputSource_Subsystem>();
    if (ck::Is_NOT_Valid(SourceSubsystem))
    {
        ck::tests::Warning(TEXT("[GymSwitchboard] no input-source subsystem - cannot open"));
        return false;
    }

    auto Source = SourceSubsystem->Get_InputSource();
    if (ck::Is_NOT_Valid(Source))
    {
        ck::tests::Warning(TEXT("[GymSwitchboard] input source not ready (no PlayerController yet?) - try again"));
        return false;
    }

    if (const auto ExistingHolder = UCk_Utils_InputLayer_UE::TryGet_LayerWithPriority(Source, LayerPriority_Menu);
        ck::IsValid(ExistingHolder))
    {
        ck::tests::Warning(TEXT("[GymSwitchboard] menu priority [{}] already held by another layer - cannot open"),
            LayerPriority_Menu);
        return false;
    }

    auto LayerOwner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(LocalPlayer);
    _MenuLayer = UCk_Utils_InputLayer_UE::Create(LayerOwner,
        FCk_Fragment_InputLayer_ParamsData{Source, LayerPriority_Menu});

    if (ck::Is_NOT_Valid(_MenuLayer))
    {
        ck::tests::Warning(TEXT("[GymSwitchboard] menu layer creation failed"));
        return false;
    }

    auto Delegate = FCk_Delegate_InputLayer_CaptureTriggered{};
    Delegate.BindDynamic(this, &UCkGym_Switchboard_Subsystem::OnMenuCaptureTriggered);

    UCk_Utils_InputLayer_UE::BindTo_OnCaptureTriggered(_MenuLayer, Delegate,
        ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
        ECk_Signal_PostFireBehavior::DoNothing);

    return true;
}

auto
    UCkGym_Switchboard_Subsystem::
    DoRemoveViewportWidget()
    -> void
{
    if (NOT _RootWidget.IsValid())
    { return; }

    if (const auto* LocalPlayer = GetLocalPlayer();
        ck::IsValid(LocalPlayer))
    {
        if (auto* ViewportClient = LocalPlayer->ViewportClient.Get();
            IsValid(ViewportClient))
        { ViewportClient->RemoveViewportWidgetContent(_RootWidget.ToSharedRef()); }
    }

    _RootWidget.Reset();
}
