#include "CoreMinimal.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkUIDebugger/Window/SCkUIDebuggerWindow.h"

#include "CkDebuggerCommon/Widgets/SCkDebug_InspectorPanel.h"
#include "CkSlateLayout/CkFlexText.h"
#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/CkUiTreeCollection.h"
#include "CkSlateLayout/SCkUiRepeat.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkSlateLayout/SCkUiTree.h"
#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkUI/Layout/CkUI_LayoutConfigAsset.h"
#include "CkUI/Layout/CkUI_Layout_Subsystem.h"
#include "CkUI/Layout/CkUI_PrimaryGameLayout.h"
#include "CkUICore/Subsystem/CkUI_Input_Subsystem.h"

#include "CommonActivatableWidget.h"
#include "Engine/GameInstance.h"
#include "Engine/LocalPlayer.h"
#include "Framework/Application/SlateApplication.h"
#include "Framework/Application/SlateUser.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformProcess.h"
#include "ImageUtils.h"
#include "Interfaces/IPluginManager.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "Layout/Children.h"
#include "Layout/WidgetPath.h"
#include "Misc/AutomationTest.h"
#include "Misc/Paths.h"
#include "UObject/SoftObjectPath.h"
#include "UObject/UObjectIterator.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/Input/SSearchBox.h"
#include "Widgets/SNullWidget.h"
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"

namespace ck_tests_ui_debugger_history_authored_pie
{
    constexpr auto TestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;
    const TCHAR* LayoutPath = TEXT("/Script/AngelscriptAssets.CkTests_UIDebugger_HistoryPie_Layout");
    const TCHAR* WidgetClassPath = TEXT("/Script/Angelscript.CkTests_UIDebugger_HistoryPie_Widget");
    const FName WidgetClassName{TEXT("CkTests_UIDebugger_HistoryPie_Widget")};
    const FName LayerTagName{TEXT("CkTests.UI.Layer.CkUIDebugger.HistoryPie")};
    const FName SecondaryLayerTagName{TEXT("CkTests.UI.Layer.CkUIDebugger.HistoryPie.Secondary")};

    struct FState final
    {
        TObjectPtr<UCk_UI_LayoutConfigAsset_UE> LayoutConfig;
        TSubclassOf<UCommonActivatableWidget> WidgetClass;
        FGameplayTag LayerTag;
        FGameplayTag SecondaryLayerTag;
        TSharedPtr<SCkUIDebuggerWindow> Panel;
        TSharedPtr<SWindow> Window;
        TWeakPtr<SCkUIDebuggerWindow> WeakPanel;
        TWeakPtr<FCkUiView> WeakView;
        TWeakPtr<FCkUiView> WeakLayerView;
        TWeakPtr<FCkUiView> WeakSummaryView;
        TWeakPtr<FCkUiView> WeakCommandView;
        TWeakPtr<SCkUiRepeat> WeakRepeat;
        TWeakPtr<SCkUiTree> WeakLayerTree;
        TArray<TSharedPtr<SButton>> HeldCommandActions;
        TSharedPtr<SSearchBox> HeldCommandSearch;
        TSharedPtr<const FCkUiCollection> HeldHistoryCollection;
        TSharedPtr<const FCkUiTreeCollection> HeldLayerCollection;
        TSharedPtr<const FCkUiRecord> StableRecord;
        TSharedPtr<const FCkUiTreeNode> StableLayerRoot;
        TSharedPtr<const FCkUiTreeNode> StableLayerChild;
        uint64 ForcedLayerRefreshGenerationBefore = 0;
        TWeakPtr<SWidget> StableItem;
        FString StableKey;
        int32 ClearRecordsBefore = 0;
        int32 ClearRecordsAfter = 0;
        int32 ClearDescriptionCountBefore = 0;
        int32 ClearDescriptionCountAfter = 0;
        TWeakObjectPtr<UCk_UI_Input_Subsystem_UE> InputSubsystem;
        int32 InputSuspensionCountBeforeClearClick = INDEX_NONE;
        int32 HistoryRecordsBeforeRelease = 0;
        int32 LayerNodesBeforeRelease = 0;
        int64 LayerRevisionBeforeRelease = 0;
        bool bAssetsResolved = false;
        bool bMounted = false;
        bool bLayerMounted = false;
        bool bSummaryMounted = false;
        bool bCommandMounted = false;
        bool bSummaryNoLayoutBranch = false;
        bool bLayoutCreated = false;
        bool bSummaryLayoutBranches = false;
        bool bSummaryPrimaryState = false;
        bool bSummarySecondaryState = false;
        bool bSummaryPrimaryRestored = false;
        bool bPostCaptureHistoryRepeatTreeSettled = false;
        bool bLayerPublished = false;
        bool bLayerProjection = false;
        bool bActiveOnlyOnRouted = false;
        bool bActiveOnlyOffRouted = false;
        bool bLayerActions = false;
        bool bLayerReloadRetained = false;
        bool bCommandActions = false;
        bool bCommandReloadRetained = false;
        bool bForceRefreshRouted = false;
        bool bForceRefreshObserved = false;
        bool bPushPublished = false;
        bool bPopPublished = false;
        bool bRefreshRetained = false;
        bool bClearPublishedExactlyOnce = false;
        bool bClearButtonTargeted = false;
        bool bClearButtonEnabledBeforeDown = false;
        bool bClearButtonDownHandled = false;
        bool bClearButtonCapturedAfterDown = false;
        bool bClearButtonCaptorValidAfterDown = false;
        bool bClearButtonCaptorPathContainsTarget = false;
        bool bClearButtonTargetedBeforeUp = false;
        FString ClearButtonCaptorType;
        FName ClearButtonCaptorTag;
        int64 CommandViewRevisionBeforeClear = 0;
        bool bClearButtonUpHandled = false;
        bool bClearButtonRouted = false;
        bool bClearHistoryEmpty = false;
        bool bCapHeldAfter101Pushes = false;
        bool bSummaryPresentBeforeCaptures = false;
        bool bWideCapture = false;
        bool bNarrowCapture = false;
        bool bReleased = false;
        bool bLayoutDestroyed = false;
        bool bReleasedCallbacksInert = false;
    };

    auto Tick(FSlateApplication& InSlate) -> void
    {
        InSlate.PumpMessages();
        InSlate.Tick();
        InSlate.Tick();
    }

    auto FindInspector(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SCkDebug_InspectorPanel>
    {
        if (InRoot->GetTypeAsString() == TEXT("SCkDebug_InspectorPanel"))
        { return StaticCastSharedRef<SCkDebug_InspectorPanel>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SCkDebug_InspectorPanel> Found = FindInspector(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid())
            { return Found; }
        }
        return {};
    }

    auto FindTaggedWidget(const TSharedRef<SWidget>& InRoot, const FName InTag, const FString& InType) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTag() == InTag && InRoot->GetTypeAsString() == InType) { return InRoot; }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            const TSharedPtr<SWidget> Found = FindTaggedWidget(
                ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag, InType);
            if (Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto FindWidgetByTag(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTag() == InTag) { return InRoot; }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            const TSharedPtr<SWidget> Found = FindWidgetByTag(
                ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag);
            if (Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto ContainsPlainText(const TSharedRef<SWidget>& InRoot, const FString& InText) -> bool
    {
        if (InRoot->GetTypeAsString() == TEXT("SCkFlexText")
            && StaticCastSharedRef<SCkFlexText>(InRoot)->GetText().ToString() == InText) { return true; }
        if (InRoot->GetTypeAsString() == TEXT("STextBlock")
            && StaticCastSharedRef<STextBlock>(InRoot)->GetText().ToString() == InText) { return true; }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (ContainsPlainText(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InText)) { return true; }
        }
        return false;
    }

    auto ContainsSummaryText(const TSharedPtr<FCkUiView>& InView, const FString& InText) -> bool
    {
        return InView.IsValid() && ContainsPlainText(InView->GetRegion(TEXT("summary")), InText);
    }

    auto FindButtonByTag(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SButton>
    {
        TSharedPtr<SWidget> Widget = FindTaggedWidget(InRoot, InTag, TEXT("SCkUiStyledButton"));
        if (!Widget.IsValid()) { Widget = FindTaggedWidget(InRoot, InTag, TEXT("SButton")); }
        return Widget.IsValid()
            ? StaticCastSharedPtr<SButton>(Widget) : nullptr;
    }

    auto FindInputByTag(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SSearchBox>
    {
        const TSharedPtr<SWidget> Widget = FindTaggedWidget(InRoot, InTag, TEXT("SSearchBox"));
        return Widget.IsValid()
            ? StaticCastSharedPtr<SSearchBox>(Widget) : nullptr;
    }

    auto FocusPathContains(FSlateApplication& InSlate, const TSharedRef<SWidget>& InWidget) -> bool
    {
        const TSharedPtr<SWidget> Focused = InSlate.GetUserFocusedWidget(0);
        FWidgetPath Path;
        if (!Focused.IsValid() || !InSlate.GeneratePathToWidgetUnchecked(Focused.ToSharedRef(), Path)) { return false; }
        for (int32 Index = 0; Index < Path.Widgets.Num(); ++Index)
        {
            if (Path.Widgets[Index].Widget == InWidget) { return true; }
        }
        return false;
    }

    auto WidgetPathContains(const FWidgetPath& InPath, const TSharedRef<SWidget>& InWidget) -> bool
    {
        for (int32 Index = 0; Index < InPath.Widgets.Num(); ++Index)
        {
            if (InPath.Widgets[Index].Widget == InWidget) { return true; }
        }
        return false;
    }

    auto TickUntil(FSlateApplication& InSlate, TFunctionRef<bool()> InCondition, const double InTimeoutSeconds = 2.0) -> bool
    {
        const double Deadline = FPlatformTime::Seconds() + InTimeoutSeconds;
        while (!InCondition() && FPlatformTime::Seconds() < Deadline)
        {
            Tick(InSlate);
            FPlatformProcess::Sleep(0.01f);
        }
        return InCondition();
    }

    auto HistoryKeyValue(const FString& InKey) -> uint64
    {
        FString Prefix;
        FString Value;
        return InKey.Split(TEXT(":"), &Prefix, &Value) ? FCString::Strtoui64(*Value, nullptr, 10) : 0;
    }

    struct FPhysicalClickResult final
    {
        bool Targeted = false;
        bool EnabledBeforeDown = false;
        bool DownHandled = false;
        bool CapturedAfterDown = false;
        bool CaptorValidAfterDown = false;
        bool CaptorPathContainsTarget = false;
        bool TargetedBeforeUp = false;
        FString CaptorType;
        FName CaptorTag;
        bool UpHandled = false;

        auto Succeeded() const -> bool { return Targeted && DownHandled && UpHandled; }
    };

    auto ClickDetailed(FSlateApplication& InSlate, const TSharedRef<SWidget>& InWidget) -> FPhysicalClickResult
    {
        auto Result = FPhysicalClickResult{};
        const TSharedPtr<SWindow> Window = InSlate.FindWidgetWindow(InWidget);
        if (!Window.IsValid() || !Window->GetNativeWindow().IsValid()) { return Result; }
        Window->BringToFront(true);
        Tick(InSlate);
        InSlate.ReleaseAllPointerCapture(0);
        Result.EnabledBeforeDown = InWidget->IsEnabled();
        const FGeometry Geometry = InWidget->GetCachedGeometry();
        if (Geometry.GetLocalSize().X <= 0.0f || Geometry.GetLocalSize().Y <= 0.0f) { return Result; }
        const FVector2D Position = Geometry.LocalToAbsolute(Geometry.GetLocalSize() * 0.5f);
        const TSet<FKey> NoButtons;
        const TSet<FKey> LeftDown{EKeys::LeftMouseButton};
        const FPointerEvent MoveEvent(0, FSlateApplication::CursorPointerIndex, Position, Position,
            NoButtons, EKeys::Invalid, 0.0f, FModifierKeysState{});
        const FPointerEvent DownEvent(0, FSlateApplication::CursorPointerIndex, Position, Position,
            LeftDown, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        const FPointerEvent UpEvent(0, FSlateApplication::CursorPointerIndex, Position, Position,
            NoButtons, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        InSlate.SetCursorPos(Position);
        InSlate.ProcessMouseMoveEvent(MoveEvent, true);
        const FWidgetPath TargetPath = InSlate.LocateWindowUnderMouse(
            Position, InSlate.GetInteractiveTopLevelWindows(), false, 0);
        Result.Targeted = WidgetPathContains(TargetPath, InWidget);
        if (!Result.Targeted) { return Result; }
        Result.DownHandled = InSlate.ProcessMouseButtonDownEvent(Window->GetNativeWindow(), DownEvent);
        Result.CapturedAfterDown = InWidget->HasMouseCapture();
        const TSharedPtr<FSlateUser> CursorUser = InSlate.GetUser(0);
        const TSharedPtr<SWidget> Captor = CursorUser.IsValid()
            ? CursorUser->GetPointerCaptor(FSlateApplication::CursorPointerIndex) : nullptr;
        Result.CaptorValidAfterDown = Captor.IsValid();
        Result.CaptorType = Captor.IsValid() ? Captor->GetTypeAsString() : TEXT("<none>");
        Result.CaptorTag = Captor.IsValid() ? Captor->GetTag() : NAME_None;
        const FWidgetPath CaptorPath = CursorUser.IsValid()
            ? CursorUser->GetCaptorPath(FSlateApplication::CursorPointerIndex,
                FWeakWidgetPath::EInterruptedPathHandling::ReturnInvalid, &DownEvent)
            : FWidgetPath{};
        Result.CaptorPathContainsTarget = CaptorPath.IsValid() && WidgetPathContains(CaptorPath, InWidget);
        const FWidgetPath UpTargetPath = InSlate.LocateWindowUnderMouse(
            Position, InSlate.GetInteractiveTopLevelWindows(), false, 0);
        Result.TargetedBeforeUp = WidgetPathContains(UpTargetPath, InWidget);
        Result.UpHandled = InSlate.ProcessMouseButtonUpEvent(UpEvent);
        Tick(InSlate);
        return Result;
    }

    auto Click(FSlateApplication& InSlate, const TSharedRef<SWidget>& InWidget) -> bool
    {
        return ClickDetailed(InSlate, InWidget).Succeeded();
    }

    auto ReplaceText(FSlateApplication& InSlate, const TSharedRef<SSearchBox>& InInput, const FString& InText) -> bool
    {
        const TSharedPtr<SWindow> Window = InSlate.FindWidgetWindow(InInput);
        if (!Window.IsValid() || !Window->GetNativeWindow().IsValid()) { return false; }
        Window->BringToFront(true);
        Tick(InSlate);
        InSlate.ReleaseAllPointerCapture(0);
        if (!FocusPathContains(InSlate, InInput))
        {
            InSlate.SetUserFocus(0, InInput, EFocusCause::SetDirectly);
            Tick(InSlate);
            InSlate.ReleaseAllPointerCapture(0);
        }
        if (!FocusPathContains(InSlate, InInput)) { return false; }
        const FModifierKeysState Control{false, false, true, false, false, false, false, false, false};
        if (!InSlate.ProcessKeyDownEvent(FKeyEvent{EKeys::A, Control, 0, false, 0, 0})) { return false; }
        for (const TCHAR Character : InText)
        {
            if (!InSlate.ProcessKeyCharEvent(FCharacterEvent{Character, FModifierKeysState{}, 0, false})) { return false; }
        }
        return TickUntil(InSlate, [&InInput, &InText]() { return InInput->GetText().ToString() == InText; });
    }

    auto SaveCapture(FSlateApplication& InSlate, const TSharedRef<SWidget>& InRoot, const FString& InPath) -> bool
    {
        TArray<FColor> Pixels;
        FIntVector Size = FIntVector::ZeroValue;
        if (!InSlate.TakeScreenshot(InRoot, Pixels, Size) || Size.X <= 0 || Size.Y <= 0 || Pixels.Num() < Size.X * Size.Y) { return false; }
        IFileManager::Get().MakeDirectory(*FPaths::GetPath(InPath), true);
        return FImageUtils::SaveImageByExtension(*InPath, FImageView(Pixels.GetData(), Size.X, Size.Y, ERawImageFormat::BGRA8));
    }

    auto Description(const TSharedPtr<const FCkUiRecord>& InRecord) -> FString
    {
        const FCkUiFieldValue* Field = InRecord.IsValid() ? InRecord->FindField(TEXT("description")) : nullptr;
        return Field != nullptr ? Field->Text.ToString() : FString{};
    }

    auto CountDescriptions(const TSharedPtr<const FCkUiCollection>& InCollection, const FString& InNeedle) -> int32
    {
        if (!InCollection.IsValid()) { return 0; }
        int32 Count = 0;
        for (const TSharedPtr<const FCkUiRecord>& Record : InCollection->GetRecords())
        { Count += Description(Record).Contains(InNeedle); }
        return Count;
    }

    auto HasDescription(const TSharedPtr<const FCkUiCollection>& InCollection, const FString& InNeedle) -> bool
    {
        return CountDescriptions(InCollection, InNeedle) > 0;
    }

    auto TextField(const TSharedPtr<const FCkUiTreeNode>& InNode, const FString& InName) -> FString
    {
        const FCkUiFieldValue* Field = InNode.IsValid() ? InNode->FindField(InName) : nullptr;
        return Field != nullptr && Field->Kind == ECkUiFieldKind::Text ? Field->Text.ToString() : FString{};
    }

    auto ResolveLayoutLiteral() -> UCk_UI_LayoutConfigAsset_UE*
    {
        return Cast<UCk_UI_LayoutConfigAsset_UE>(StaticLoadObject(UCk_UI_LayoutConfigAsset_UE::StaticClass(), nullptr, LayoutPath));
    }

    auto ResolveWidgetClass() -> TSubclassOf<UCommonActivatableWidget>
    {
        if (UClass* Loaded = FSoftClassPath{WidgetClassPath}.TryLoadClass<UCommonActivatableWidget>())
        { return Loaded; }

        // AS class package names are generator-owned. Keep the literal path as the fast path but
        // retain a name-and-base fallback so a package-name normalization cannot silently turn this
        // production fixture into an invalid-widget no-op.
        for (TObjectIterator<UClass> It; It; ++It)
        {
            UClass* Candidate = *It;
            if (Candidate != nullptr && Candidate->GetFName() == WidgetClassName
                && Candidate->IsChildOf(UCommonActivatableWidget::StaticClass()))
            { return Candidate; }
        }
        return nullptr;
    }

    auto GetLayoutSubsystem(UWorld* InWorld) -> UCk_UI_Layout_Subsystem_UE*
    {
        if (InWorld == nullptr || InWorld->GetGameInstance() == nullptr) { return nullptr; }
        ULocalPlayer* LocalPlayer = InWorld->GetGameInstance()->GetFirstGamePlayer();
        return LocalPlayer != nullptr ? LocalPlayer->GetSubsystem<UCk_UI_Layout_Subsystem_UE>() : nullptr;
    }

    auto GetInputSubsystem(UWorld* InWorld) -> UCk_UI_Input_Subsystem_UE*
    {
        if (InWorld == nullptr || InWorld->GetGameInstance() == nullptr) { return nullptr; }
        ULocalPlayer* LocalPlayer = InWorld->GetGameInstance()->GetFirstGamePlayer();
        return LocalPlayer != nullptr ? LocalPlayer->GetSubsystem<UCk_UI_Input_Subsystem_UE>() : nullptr;
    }

    auto GetHistoryResources() -> FString
    {
        const TSharedPtr<IPlugin> Plugin = IPluginManager::Get().FindPlugin(TEXT("CkDebugger"));
        return Plugin.IsValid() ? FPaths::Combine(Plugin->GetBaseDir(), TEXT("Resources/UI")) : FString{};
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkUIDebugger_HistoryAuthoredPie,
    "Ck.UIDebugger.History.PIE",
    ck_tests_ui_debugger_history_authored_pie::TestFlags)

bool FCkUIDebugger_HistoryAuthoredPie::RunTest(const FString&)
{
    using namespace ck_tests_ui_debugger_history_authored_pie;

    const TSharedRef<FState> State = MakeShared<FState>();
    State->LayoutConfig = ResolveLayoutLiteral();
    State->WidgetClass = ResolveWidgetClass();
    State->LayerTag = FGameplayTag::RequestGameplayTag(LayerTagName, false);
    State->SecondaryLayerTag = FGameplayTag::RequestGameplayTag(SecondaryLayerTagName, false);
    State->bAssetsResolved = IsValid(State->LayoutConfig) && State->WidgetClass != nullptr
        && State->LayerTag.IsValid() && State->SecondaryLayerTag.IsValid();
    if (!State->bAssetsResolved || !FSlateApplication::IsInitialized())
    {
        AddError(FString::Printf(TEXT("UI debugger History PIE fixture preflight failed: layout=%s widget=%s tags=%s,%s slate=%d"),
            *GetNameSafe(State->LayoutConfig), *GetNameSafe(State->WidgetClass.Get()), *State->LayerTag.ToString(),
            *State->SecondaryLayerTag.ToString(), FSlateApplication::IsInitialized()));
        return false;
    }

    FSlateApplication& Slate = FSlateApplication::Get();
    State->Panel = SNew(SCkUIDebuggerWindow);
    State->WeakPanel = State->Panel;
    State->Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{1200.0f, 760.0f})
        .CreateTitleBar(false).HasCloseButton(false)[State->Panel.ToSharedRef()];
    Slate.AddWindow(State->Window.ToSharedRef(), true);
    Tick(Slate);
    const TSharedPtr<FCkUiView> View = State->Panel->Get_HistoryView();
    const TSharedPtr<const FCkUiCollection> Collection = State->Panel->Get_HistoryCollection();
    const TSharedRef<SWidget> HistoryRegion = View.IsValid()
        ? View->GetRegion(TEXT("main")) : SNullWidget::NullWidget;
    const TSharedPtr<SCkDebug_InspectorPanel> HistoryInspector = FindInspector(HistoryRegion);
    if (HistoryInspector.IsValid()) { HistoryInspector->Set_Expanded(true); }
    Tick(Slate);
    const TSharedPtr<SWidget> RepeatWidget = FindTaggedWidget(
        HistoryRegion, TEXT("history-records"), TEXT("SCkUiRepeat"));
    const TSharedPtr<SCkUiRepeat> Repeat = RepeatWidget.IsValid()
        ? StaticCastSharedPtr<SCkUiRepeat>(RepeatWidget) : nullptr;
    State->WeakRepeat = Repeat;
    const TSharedPtr<FCkUiView> LayerView = State->Panel->Get_LayerView();
    const TSharedPtr<const FCkUiTreeCollection> LayerCollection = State->Panel->Get_LayerCollection();
    const TSharedPtr<SCkUiTree> LayerTree = LayerView.IsValid()
        ? LayerView->GetTree(TEXT("ui-layer-tree")) : nullptr;
    State->WeakLayerView = LayerView;
    State->WeakLayerTree = LayerTree;
    const TSharedPtr<FCkUiView> SummaryView = State->Panel->Get_SummaryView();
    State->WeakSummaryView = SummaryView;
    const TSharedRef<SWidget> SummaryRegion = SummaryView.IsValid()
        ? SummaryView->GetRegion(TEXT("summary")) : SNullWidget::NullWidget;
    const TSharedPtr<SWidget> SummaryLive = FindWidgetByTag(SummaryRegion, TEXT("ui-summary-live"));
    const TSharedPtr<SWidget> SummaryNoLayout = FindWidgetByTag(SummaryRegion, TEXT("ui-summary-empty"));
    State->bLayerMounted = LayerView.IsValid() && LayerView->GetLastResult().Succeeded
        && LayerCollection.IsValid() && LayerCollection->GetNodes().IsEmpty()
        && LayerTree.IsValid() && LayerTree->GetVisibleNodeCount() == 0;
    State->bSummaryNoLayoutBranch = SummaryLive.IsValid() && SummaryNoLayout.IsValid()
        && !SummaryLive->GetVisibility().IsVisible() && SummaryNoLayout->GetVisibility().IsVisible()
        && ContainsSummaryText(SummaryView, TEXT("No active layout. Start PIE to see layer data."));
    State->bSummaryMounted = SummaryView.IsValid() && SummaryView->GetLastResult().Succeeded && State->bSummaryNoLayoutBranch;
    const TSharedPtr<FCkUiView> CommandView = State->Panel->Get_CommandView();
    State->WeakCommandView = CommandView;
    const TSharedRef<SWidget> CommandRegion = CommandView.IsValid()
        ? CommandView->GetRegion(TEXT("commands")) : SNullWidget::NullWidget;
    const TSharedPtr<SSearchBox> CommandSearch = FindInputByTag(CommandRegion, TEXT("ui-layer-filter"));
    for (const FName CommandId : {FName{TEXT("ui-layer-filter-clear")}, FName{TEXT("ui-active-layer-only")},
        FName{TEXT("ui-force-refresh")}, FName{TEXT("ui-expand-all")}, FName{TEXT("ui-collapse-all")},
        FName{TEXT("ui-clear-history")}, FName{TEXT("ui-name-depth-previous")}, FName{TEXT("ui-name-depth-next")}})
    { State->HeldCommandActions.Add(FindButtonByTag(CommandRegion, CommandId)); }
    State->bCommandMounted = CommandView.IsValid() && CommandView->GetLastResult().Succeeded
        && CommandSearch.IsValid() && FindWidgetByTag(CommandRegion, TEXT("ui-name-depth-value")).IsValid()
        && !State->HeldCommandActions.ContainsByPredicate([](const TSharedPtr<SButton>& InButton) { return !InButton.IsValid(); });
    State->bMounted = View.IsValid() && View->GetLastResult().Succeeded && Collection.IsValid()
        && Repeat.IsValid() && Repeat->GetItemCount() == 0
        && State->bLayerMounted && State->bSummaryMounted && State->bCommandMounted;
    if (!State->bMounted)
    {
        AddError(TEXT("UI debugger History did not mount its installed authored view before PIE."));
        Slate.DestroyWindowImmediately(State->Window.ToSharedRef());
        return false;
    }

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld* InWorld) -> void
    {
        if (UCk_UI_Layout_Subsystem_UE* Subsystem = GetLayoutSubsystem(InWorld))
        {
            Subsystem->CreateLayout(State->LayoutConfig);
            State->bLayoutCreated = Subsystem->Get_Layout() != nullptr
                && Subsystem->HasLayer(State->LayerTag) && Subsystem->HasLayer(State->SecondaryLayerTag);
        }
    })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    {
        const TSharedPtr<const FCkUiTreeCollection> Layers = State->Panel.IsValid()
            ? State->Panel->Get_LayerCollection() : nullptr;
        const TSharedPtr<SCkUiTree> Tree = State->WeakLayerTree.Pin();
        const TSharedPtr<FCkUiView> Summary = State->WeakSummaryView.Pin();
        const TSharedRef<SWidget> SummaryRegion = Summary.IsValid()
            ? Summary->GetRegion(TEXT("summary")) : SNullWidget::NullWidget;
        const TSharedPtr<SWidget> SummaryLive = FindWidgetByTag(SummaryRegion, TEXT("ui-summary-live"));
        const TSharedPtr<SWidget> SummaryNoLayout = FindWidgetByTag(SummaryRegion, TEXT("ui-summary-empty"));
        State->bSummaryLayoutBranches = SummaryLive.IsValid() && SummaryNoLayout.IsValid()
            && SummaryLive->GetVisibility().IsVisible() && !SummaryNoLayout->GetVisibility().IsVisible()
            && ContainsSummaryText(Summary, TEXT("2")) && !ContainsSummaryText(Summary, State->LayerTag.ToString());
        return State->bLayoutCreated && State->bSummaryLayoutBranches && Layers.IsValid() && Tree.IsValid()
            && Layers->GetRoots().Num() == 2 && Tree->GetVisibleNodeCount() == 2;
    }), 15.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld* InWorld) -> void
    {
        if (UCk_UI_Layout_Subsystem_UE* Subsystem = GetLayoutSubsystem(InWorld))
        { Subsystem->PushWidgetToLayer(State->LayerTag, State->WidgetClass); }
    })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    {
        const TSharedPtr<FCkUiView> Summary = State->WeakSummaryView.Pin();
        const TSharedPtr<const FCkUiCollection> Collection = State->Panel.IsValid() ? State->Panel->Get_HistoryCollection() : nullptr;
        const TSharedPtr<SCkUiRepeat> Repeat = State->WeakRepeat.Pin();
        State->bSummaryPrimaryState = ContainsSummaryText(Summary, State->LayerTag.ToString())
            && ContainsSummaryText(Summary, TEXT("GameAndUI")) && ContainsSummaryText(Summary, TEXT("2"));
        if (Collection.IsValid() && !Collection->GetRecords().IsEmpty())
        {
            State->StableRecord = Collection->GetRecords()[0];
            State->StableKey = State->StableRecord->GetKey();
            State->StableItem = Repeat.IsValid() ? Repeat->GetItemWidget(State->StableKey) : nullptr;
            State->bPushPublished = Description(State->StableRecord).Contains(TEXT("[Push]"))
                && !State->StableKey.IsEmpty() && State->StableItem.IsValid();
        }
        return State->bSummaryPrimaryState && State->bPushPublished;
    }), 15.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld* InWorld) -> void
    {
        if (UCk_UI_Layout_Subsystem_UE* Subsystem = GetLayoutSubsystem(InWorld))
        { Subsystem->PushWidgetToLayer(State->SecondaryLayerTag, State->WidgetClass); }
    })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    {
        const TSharedPtr<FCkUiView> Summary = State->WeakSummaryView.Pin();
        State->bSummarySecondaryState = ContainsSummaryText(Summary, State->SecondaryLayerTag.ToString())
            && ContainsSummaryText(Summary, TEXT("UIOnly")) && ContainsSummaryText(Summary, TEXT("2"));
        return State->bSummarySecondaryState;
    }), 15.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld* InWorld) -> void
    {
        if (UCk_UI_Layout_Subsystem_UE* Subsystem = GetLayoutSubsystem(InWorld))
        { Subsystem->PopWidgetFromLayer(State->SecondaryLayerTag); }
    })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    {
        const TSharedPtr<FCkUiView> Summary = State->WeakSummaryView.Pin();
        State->bSummaryPrimaryRestored = ContainsSummaryText(Summary, State->LayerTag.ToString())
            && ContainsSummaryText(Summary, TEXT("GameAndUI")) && ContainsSummaryText(Summary, TEXT("2"));
        return State->bSummaryPrimaryRestored;
    }), 15.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
    {
        if (!State->Panel.IsValid() || !State->Window.IsValid()) { return; }
        FSlateApplication& Slate = FSlateApplication::Get();
        const TSharedPtr<FCkUiView> Summary = State->WeakSummaryView.Pin();
        State->bSummaryPresentBeforeCaptures = ContainsSummaryText(Summary, State->LayerTag.ToString())
            && ContainsSummaryText(Summary, TEXT("GameAndUI")) && ContainsSummaryText(Summary, TEXT("2"));
        State->Window->Resize(FVector2D{1200.0f, 760.0f});
        Tick(Slate);
        State->bWideCapture = State->bSummaryPresentBeforeCaptures && SaveCapture(Slate, State->Window.ToSharedRef(),
            FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Automation/UIDebugger/HistoryPie-Wide.png")));
        State->Window->Resize(FVector2D{420.0f, 420.0f});
        Tick(Slate);
        State->bNarrowCapture = State->bSummaryPresentBeforeCaptures && SaveCapture(Slate, State->Window.ToSharedRef(),
            FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Automation/UIDebugger/HistoryPie-Narrow.png")));
        State->Window->Resize(FVector2D{1200.0f, 760.0f});
        Tick(Slate);
    })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    {
        const TSharedPtr<const FCkUiCollection> Collection = State->Panel.IsValid() ? State->Panel->Get_HistoryCollection() : nullptr;
        const TSharedPtr<const FCkUiTreeCollection> Layers = State->Panel.IsValid()
            ? State->Panel->Get_LayerCollection() : nullptr;
        const TSharedPtr<SCkUiRepeat> Repeat = State->WeakRepeat.Pin();
        const TSharedPtr<SCkUiTree> Tree = State->WeakLayerTree.Pin();
        State->bPostCaptureHistoryRepeatTreeSettled = HasDescription(Collection, TEXT("[Push]"))
            && Repeat.IsValid() && Layers.IsValid() && Tree.IsValid()
            && Layers->GetChildren(State->LayerTag.ToString()).Num() == 1 && Tree->GetVisibleNodeCount() == 3
            && Repeat->GetItemCount() == Collection->GetRecords().Num();
        return State->bPostCaptureHistoryRepeatTreeSettled;
    }), 15.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
    {
        if (!State->Panel.IsValid()) { return; }
        FSlateApplication& Slate = FSlateApplication::Get();
        const TSharedPtr<const FCkUiTreeCollection> Layers = State->Panel->Get_LayerCollection();
        const TSharedPtr<FCkUiView> LayerView = State->Panel->Get_LayerView();
        const TSharedPtr<SCkUiTree> Tree = State->WeakLayerTree.Pin();
        if (!Layers.IsValid() || !LayerView.IsValid() || !Tree.IsValid()) { return; }
        State->StableLayerRoot = Layers->FindNode(State->LayerTag.ToString());
        const TArray<TSharedPtr<const FCkUiTreeNode>> Children = Layers->GetChildren(State->LayerTag.ToString());
        State->StableLayerChild = Children.IsEmpty() ? nullptr : Children[0];
        const TSharedPtr<const FCkUiTreeNode> Secondary = Layers->FindNode(State->SecondaryLayerTag.ToString());
        State->bLayerPublished = State->StableLayerRoot.IsValid() && State->StableLayerChild.IsValid() && Secondary.IsValid()
            && TextField(State->StableLayerRoot, TEXT("layer-tag-tooltip")) == State->LayerTag.ToString()
            && TextField(State->StableLayerRoot, TEXT("priority")) == TEXT("[0]")
            && TextField(State->StableLayerRoot, TEXT("input-mode")) == TEXT("GameAndUI")
            && TextField(State->StableLayerRoot, TEXT("widget-count")) == TEXT("(1)")
            && TextField(State->StableLayerChild, TEXT("widget-name-tooltip")) == State->WidgetClass->GetName()
            && TextField(State->StableLayerChild, TEXT("widget-state")) == TEXT("Active")
            && TextField(Secondary, TEXT("priority")) == TEXT("[20]")
            && TextField(Secondary, TEXT("input-mode")) == TEXT("UIOnly")
            && Tree->GetExpandedKeys().Contains(State->LayerTag.ToString())
            && Tree->GetExpandedKeys().Contains(State->SecondaryLayerTag.ToString());

        const TSharedPtr<FCkUiView> CommandView = State->WeakCommandView.Pin();
        const TSharedRef<SWidget> CommandRegion = CommandView.IsValid()
            ? CommandView->GetRegion(TEXT("commands")) : SNullWidget::NullWidget;
        const TSharedPtr<SSearchBox> Search = FindInputByTag(CommandRegion, TEXT("ui-layer-filter"));
        const TSharedPtr<SButton> FilterClear = FindButtonByTag(CommandRegion, TEXT("ui-layer-filter-clear"));
        const TSharedPtr<SButton> ToggleActive = FindButtonByTag(CommandRegion, TEXT("ui-active-layer-only"));
        bool ProjectionWorks = Search.IsValid() && ReplaceText(Slate, Search.ToSharedRef(), TEXT("Scndry"))
            && TickUntil(Slate, [Tree]() { return Tree->GetVisibleNodeCount() == 1; })
            && ReplaceText(Slate, Search.ToSharedRef(), State->WidgetClass->GetName())
            && TickUntil(Slate, [Tree]() { return Tree->GetVisibleNodeCount() == 0; })
            && ReplaceText(Slate, Search.ToSharedRef(), TEXT("Scndry"))
            && TickUntil(Slate, [Tree]() { return Tree->GetVisibleNodeCount() == 1; })
            && FilterClear.IsValid() && Click(Slate, FilterClear.ToSharedRef())
            && TickUntil(Slate, [Search, Tree]() { return Search->GetText().IsEmpty() && Tree->GetVisibleNodeCount() == 3; });

        State->bActiveOnlyOnRouted = ToggleActive.IsValid() && Click(Slate, ToggleActive.ToSharedRef());
        State->bLayerProjection = ProjectionWorks
            && Layers->FindNode(State->LayerTag.ToString()) == State->StableLayerRoot
            && Layers->FindNode(State->StableLayerChild->GetKey()) == State->StableLayerChild;
    })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    {
        const TSharedPtr<SCkUiTree> Tree = State->WeakLayerTree.Pin();
        return State->bActiveOnlyOnRouted && Tree.IsValid() && Tree->GetVisibleNodeCount() == 2;
    }), 15.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
    {
        if (!State->Panel.IsValid()) { return; }
        const TSharedPtr<FCkUiView> CommandView = State->WeakCommandView.Pin();
        const TSharedRef<SWidget> CommandRegion = CommandView.IsValid()
            ? CommandView->GetRegion(TEXT("commands")) : SNullWidget::NullWidget;
        const TSharedPtr<SButton> ToggleActive = FindButtonByTag(CommandRegion, TEXT("ui-active-layer-only"));
        State->bActiveOnlyOffRouted = ToggleActive.IsValid()
            && Click(FSlateApplication::Get(), ToggleActive.ToSharedRef());
    })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    {
        const TSharedPtr<SCkUiTree> Tree = State->WeakLayerTree.Pin();
        return State->bActiveOnlyOffRouted && Tree.IsValid() && Tree->GetVisibleNodeCount() == 3;
    }), 15.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
    {
        if (!State->Panel.IsValid()) { return; }
        FSlateApplication& Slate = FSlateApplication::Get();
        const TSharedPtr<const FCkUiTreeCollection> Layers = State->Panel->Get_LayerCollection();
        const TSharedPtr<FCkUiView> LayerView = State->Panel->Get_LayerView();
        const TSharedPtr<SCkUiTree> Tree = State->WeakLayerTree.Pin();
        if (!Layers.IsValid() || !LayerView.IsValid() || !Tree.IsValid()) { return; }
        State->bLayerProjection = State->bLayerProjection && State->bActiveOnlyOnRouted
            && State->bActiveOnlyOffRouted && Tree->GetVisibleNodeCount() == 3
            && Layers->FindNode(State->LayerTag.ToString()) == State->StableLayerRoot
            && Layers->FindNode(State->StableLayerChild->GetKey()) == State->StableLayerChild;

        const TSharedPtr<FCkUiView> CommandView = State->WeakCommandView.Pin();
        const TSharedRef<SWidget> CommandRegion = CommandView.IsValid()
            ? CommandView->GetRegion(TEXT("commands")) : SNullWidget::NullWidget;
        const TSharedPtr<SButton> Collapse = FindButtonByTag(CommandRegion, TEXT("ui-collapse-all"));
        const TSharedPtr<SButton> Expand = FindButtonByTag(CommandRegion, TEXT("ui-expand-all"));
        const bool Collapsed = Collapse.IsValid() && Click(Slate, Collapse.ToSharedRef()) && Tree->GetExpandedKeys().IsEmpty();
        const bool Expanded = Expand.IsValid() && Click(Slate, Expand.ToSharedRef())
            && Tree->GetExpandedKeys().Contains(State->LayerTag.ToString())
            && Tree->GetExpandedKeys().Contains(State->SecondaryLayerTag.ToString());
        State->bLayerActions = Collapsed && Expanded;

        const TSharedPtr<SSearchBox> Search = FindInputByTag(CommandRegion, TEXT("ui-layer-filter"));
        const TSharedPtr<SButton> NameDepthPrevious = FindButtonByTag(CommandRegion, TEXT("ui-name-depth-previous"));
        const TSharedPtr<SButton> NameDepthNext = FindButtonByTag(CommandRegion, TEXT("ui-name-depth-next"));
        const TSharedPtr<SWidget> NameDepthValue = FindWidgetByTag(CommandRegion, TEXT("ui-name-depth-value"));
        const FString NameDepthBefore = NameDepthValue.IsValid() && NameDepthValue->GetTypeAsString() == TEXT("SCkFlexText")
            ? StaticCastSharedPtr<SCkFlexText>(NameDepthValue)->GetText().ToString() : FString{};
        const bool NameDepthCycles = NameDepthPrevious.IsValid() && NameDepthNext.IsValid() && !NameDepthBefore.IsEmpty()
            && Click(Slate, NameDepthNext.ToSharedRef())
            && StaticCastSharedPtr<SCkFlexText>(NameDepthValue)->GetText().ToString() != NameDepthBefore
            && Click(Slate, NameDepthPrevious.ToSharedRef())
            && StaticCastSharedPtr<SCkFlexText>(NameDepthValue)->GetText().ToString() == NameDepthBefore;

        const int64 CommandRevision = CommandView.IsValid() ? CommandView->GetRevision() : 0;
        const FString CommandSearchDraft = TEXT("Scndry");
        const bool EnteredReloadDraft = Search.IsValid() && ReplaceText(Slate, Search.ToSharedRef(), CommandSearchDraft)
            && TickUntil(Slate, [Tree]() { return Tree->GetVisibleNodeCount() == 1; });
        const FString CommandResources = GetHistoryResources();
        if (CommandView.IsValid())
        {
            const FCkUiLoadResult CommandReload = CommandView->ReloadFiles(
                FPaths::Combine(CommandResources, TEXT("UiDebuggerCommands.ui.html")),
                FPaths::Combine(CommandResources, TEXT("UiDebuggerCommands.ui.css")));
            const int64 AcceptedCommandRevision = CommandView->GetRevision();
            const FCkUiLoadResult RejectedCommandReload = CommandView->TryReload(TEXT("<ui>"), TEXT(""));
            Tick(Slate);
            const TSharedPtr<SSearchBox> ReloadedSearch = FindInputByTag(CommandRegion, TEXT("ui-layer-filter"));
            State->bCommandReloadRetained = EnteredReloadDraft && CommandReload.Succeeded && !RejectedCommandReload.Succeeded
                && State->Panel->Get_CommandView() == CommandView && CommandView->GetRevision() > CommandRevision
                && CommandView->GetRevision() == AcceptedCommandRevision && ReloadedSearch == Search
                && ReloadedSearch.IsValid() && ReloadedSearch->GetText().ToString() == CommandSearchDraft;
        }
        State->HeldCommandActions.Reset();
        for (const FName CommandId : {FName{TEXT("ui-layer-filter-clear")}, FName{TEXT("ui-active-layer-only")},
            FName{TEXT("ui-force-refresh")}, FName{TEXT("ui-expand-all")}, FName{TEXT("ui-collapse-all")},
            FName{TEXT("ui-clear-history")}, FName{TEXT("ui-name-depth-previous")}, FName{TEXT("ui-name-depth-next")}})
        { State->HeldCommandActions.Add(FindButtonByTag(CommandRegion, CommandId)); }
        const TSharedPtr<SButton> ForceRefresh = FindButtonByTag(CommandRegion, TEXT("ui-force-refresh"));
        State->ForcedLayerRefreshGenerationBefore = State->Panel->Get_ForcedLayerRefreshGeneration();
        State->bForceRefreshRouted = State->bCommandReloadRetained && NameDepthCycles && ForceRefresh.IsValid()
            && Click(Slate, ForceRefresh.ToSharedRef());
        State->bForceRefreshObserved = State->bForceRefreshRouted
            && State->Panel->Get_ForcedLayerRefreshGeneration() > State->ForcedLayerRefreshGenerationBefore
            && Layers->FindNode(State->LayerTag.ToString()) == State->StableLayerRoot
            && Layers->FindNode(State->StableLayerChild->GetKey()) == State->StableLayerChild
            && Tree->GetVisibleNodeCount() == 1;
        const TSharedPtr<SButton> FilterClearAfterReload = FindButtonByTag(CommandRegion, TEXT("ui-layer-filter-clear"));
        const bool ReloadDraftCleared = Search.IsValid() && FilterClearAfterReload.IsValid()
            && Click(Slate, FilterClearAfterReload.ToSharedRef())
            && TickUntil(Slate, [Search, Tree]() { return Search->GetText().IsEmpty() && Tree->GetVisibleNodeCount() == 3; });
        State->bCommandActions = State->bForceRefreshObserved && ReloadDraftCleared
            && !State->HeldCommandActions.ContainsByPredicate([](const TSharedPtr<SButton>& InButton) { return !InButton.IsValid(); });

        const int64 Revision = LayerView->GetRevision();
        const TSharedPtr<STreeView<SCkUiTree::FNode>> NativeTree = Tree->GetTree();
        const FString Resources = GetHistoryResources();
        const FCkUiLoadResult Reload = LayerView->ReloadFiles(FPaths::Combine(Resources, TEXT("UiDebuggerLayers.ui.html")),
            FPaths::Combine(Resources, TEXT("UiDebuggerLayers.ui.css")));
        const int64 AcceptedRevision = LayerView->GetRevision();
        const FCkUiLoadResult Rejected = LayerView->TryReload(TEXT("<ui>"), TEXT(""));
        Tick(Slate);
        State->bLayerReloadRetained = Reload.Succeeded && AcceptedRevision > Revision && !Rejected.Succeeded
            && LayerView->GetRevision() == AcceptedRevision && State->Panel->Get_LayerView() == LayerView
            && State->Panel->Get_LayerCollection() == Layers && State->WeakLayerTree.Pin() == Tree
            && Tree->GetTree() == NativeTree
            && Layers->FindNode(State->LayerTag.ToString()) == State->StableLayerRoot
            && Layers->FindNode(State->StableLayerChild->GetKey()) == State->StableLayerChild
            && Tree->GetExpandedKeys().Contains(State->LayerTag.ToString());
    })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld* InWorld) -> void
    {
        if (UCk_UI_Layout_Subsystem_UE* Subsystem = GetLayoutSubsystem(InWorld))
        { Subsystem->PopWidgetFromLayer(State->LayerTag); }
    })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    {
        const TSharedPtr<const FCkUiCollection> Collection = State->Panel.IsValid() ? State->Panel->Get_HistoryCollection() : nullptr;
        return HasDescription(Collection, TEXT("[Pop]"));
    }), 15.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld* InWorld) -> void
    {
        const TSharedPtr<FCkUiView> View = State->Panel.IsValid() ? State->Panel->Get_HistoryView() : nullptr;
        const TSharedPtr<const FCkUiCollection> Collection = State->Panel.IsValid() ? State->Panel->Get_HistoryCollection() : nullptr;
        State->bPopPublished = Collection.IsValid() && !Collection->GetRecords().IsEmpty()
            && Description(Collection->GetRecords()[0]).Contains(TEXT("[Pop]"));
        if (View.IsValid() && Collection.IsValid() && State->StableRecord.IsValid())
        {
            const int64 Revision = View->GetRevision();
            const FString Resources = GetHistoryResources();
            if (!Resources.IsEmpty())
            {
                const FCkUiLoadResult Reload = View->ReloadFiles(FPaths::Combine(Resources, TEXT("UiDebuggerHistory.ui.html")),
                    FPaths::Combine(Resources, TEXT("UiDebuggerHistory.ui.css")));
                State->bRefreshRetained = Reload.Succeeded && View->GetRevision() > Revision
                    && Collection->FindRecord(State->StableKey) == State->StableRecord
                    && State->WeakRepeat.IsValid()
                    && State->WeakRepeat.Pin()->GetItemWidget(State->StableKey) == State->StableItem.Pin();
            }
        }
        if (UCk_UI_Layout_Subsystem_UE* Subsystem = GetLayoutSubsystem(InWorld))
        {
            State->InputSubsystem = GetInputSubsystem(InWorld);
            Subsystem->PushWidgetToLayer(State->LayerTag, State->WidgetClass);
            State->ClearRecordsBefore = State->Panel->Get_HistoryCollection()->GetRecords().Num();
            State->ClearDescriptionCountBefore = CountDescriptions(State->Panel->Get_HistoryCollection(), TEXT("[Cleared]"));
            Subsystem->ClearLayer(State->LayerTag);
            if (State->Window.IsValid())
            {
                State->Window->BringToFront(true);
                Tick(FSlateApplication::Get());
            }
        }
    })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    {
        const TSharedPtr<const FCkUiCollection> Collection = State->Panel.IsValid() ? State->Panel->Get_HistoryCollection() : nullptr;
        return CountDescriptions(Collection, TEXT("[Cleared]")) >= State->ClearDescriptionCountBefore + 1;
    }), 15.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    {
        const UCk_UI_Input_Subsystem_UE* InputSubsystem = State->InputSubsystem.Get();
        return InputSubsystem != nullptr && !InputSubsystem->IsInputSuspended();
    }), 2.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
    {
        const TSharedPtr<const FCkUiCollection> Collection = State->Panel.IsValid() ? State->Panel->Get_HistoryCollection() : nullptr;
        State->ClearRecordsAfter = Collection.IsValid() ? Collection->GetRecords().Num() : 0;
        State->ClearDescriptionCountAfter = CountDescriptions(Collection, TEXT("[Cleared]"));
        State->bClearPublishedExactlyOnce = State->ClearDescriptionCountAfter == State->ClearDescriptionCountBefore + 1
            && State->ClearRecordsAfter > State->ClearRecordsBefore;

        if (!State->Panel.IsValid() || !State->Window.IsValid()) { return; }
        if (const TSharedPtr<SCkDebug_InspectorPanel> Inspector = FindInspector(State->Panel.ToSharedRef())) { Inspector->Set_Expanded(true); }
        Tick(FSlateApplication::Get());
        const TSharedPtr<FCkUiView> CommandView = State->WeakCommandView.Pin();
        const TSharedRef<SWidget> CommandRegion = CommandView.IsValid()
            ? CommandView->GetRegion(TEXT("commands")) : SNullWidget::NullWidget;
        const TSharedPtr<SButton> ClearButton = FindButtonByTag(CommandRegion, TEXT("ui-clear-history"));
        State->CommandViewRevisionBeforeClear = CommandView.IsValid() ? CommandView->GetRevision() : 0;
        State->InputSuspensionCountBeforeClearClick = State->InputSubsystem.IsValid()
            ? State->InputSubsystem->Get_ActiveSuspensionCount() : INDEX_NONE;
        const FPhysicalClickResult ClearClick = ClearButton.IsValid()
            ? ClickDetailed(FSlateApplication::Get(), ClearButton.ToSharedRef()) : FPhysicalClickResult{};
        State->bClearButtonTargeted = ClearClick.Targeted;
        State->bClearButtonEnabledBeforeDown = ClearClick.EnabledBeforeDown;
        State->bClearButtonDownHandled = ClearClick.DownHandled;
        State->bClearButtonCapturedAfterDown = ClearClick.CapturedAfterDown;
        State->bClearButtonCaptorValidAfterDown = ClearClick.CaptorValidAfterDown;
        State->bClearButtonCaptorPathContainsTarget = ClearClick.CaptorPathContainsTarget;
        State->bClearButtonTargetedBeforeUp = ClearClick.TargetedBeforeUp;
        State->ClearButtonCaptorType = ClearClick.CaptorType;
        State->ClearButtonCaptorTag = ClearClick.CaptorTag;
        State->bClearButtonUpHandled = ClearClick.UpHandled;
        State->bClearButtonRouted = ClearClick.Succeeded();
        State->bClearHistoryEmpty = State->bClearButtonRouted
            && TickUntil(FSlateApplication::Get(), [State]()
            {
                const TSharedPtr<const FCkUiCollection> Collection = State->Panel.IsValid()
                    ? State->Panel->Get_HistoryCollection() : nullptr;
                const TSharedPtr<SCkUiRepeat> Repeat = State->WeakRepeat.Pin();
                return Collection.IsValid() && Collection->GetRecords().IsEmpty()
                    && Repeat.IsValid() && Repeat->GetItemCount() == 0;
            });
    })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld* InWorld) -> void
    {
        if (UCk_UI_Layout_Subsystem_UE* Subsystem = GetLayoutSubsystem(InWorld))
        {
            for (int32 Index = 0; Index < 101; ++Index)
            { Subsystem->PushWidgetToLayer(State->LayerTag, State->WidgetClass); }
        }
    })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
    {
        if (!State->Panel.IsValid() || !State->Window.IsValid()) { return; }
        const TSharedPtr<const FCkUiCollection> Collection = State->Panel->Get_HistoryCollection();
        const TSharedPtr<const FCkUiTreeCollection> Layers = State->Panel->Get_LayerCollection();
        const TSharedPtr<SCkUiRepeat> Repeat = State->WeakRepeat.Pin();
        const bool Published = TickUntil(FSlateApplication::Get(), [Collection, Layers, Repeat, State]()
        {
            return Collection.IsValid() && Collection->GetRecords().Num() == 100
                && Repeat.IsValid() && Repeat->GetItemCount() == 100
                && Layers.IsValid() && Layers->GetChildren(State->LayerTag.ToString()).Num() == 16;
        });
        bool NewestFirst = Published;
        for (int32 Index = 0; NewestFirst && Index < Collection->GetRecords().Num(); ++Index)
        {
            NewestFirst = Description(Collection->GetRecords()[Index]).Contains(TEXT("[Push]"));
            if (Index > 0)
            {
                NewestFirst = HistoryKeyValue(Collection->GetRecords()[Index - 1]->GetKey())
                    == HistoryKeyValue(Collection->GetRecords()[Index]->GetKey()) + 1;
            }
        }
        State->bCapHeldAfter101Pushes = NewestFirst;
    })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld* InWorld) -> void
    {
        if (UCk_UI_Layout_Subsystem_UE* Subsystem = GetLayoutSubsystem(InWorld))
        {
            Subsystem->DestroyLayout();
            State->bLayoutDestroyed = !Subsystem->Has_Layout();
        }
        if (State->Panel.IsValid())
        {
            State->WeakView = State->Panel->Get_HistoryView();
            const TSharedPtr<FCkUiView> LayerView = State->Panel->Get_LayerView();
            State->WeakLayerView = LayerView;
            State->WeakLayerTree = LayerView.IsValid() ? LayerView->GetTree(TEXT("ui-layer-tree")) : nullptr;
            State->WeakSummaryView = State->Panel->Get_SummaryView();
            State->WeakCommandView = State->Panel->Get_CommandView();
            State->HeldCommandSearch = State->WeakCommandView.IsValid()
                ? FindInputByTag(State->WeakCommandView.Pin()->GetRegion(TEXT("commands")), TEXT("ui-layer-filter")) : nullptr;
            State->HeldHistoryCollection = State->Panel->Get_HistoryCollection();
            State->HeldLayerCollection = State->Panel->Get_LayerCollection();
            State->HistoryRecordsBeforeRelease = State->HeldHistoryCollection.IsValid()
                ? State->HeldHistoryCollection->GetRecords().Num() : 0;
            State->LayerNodesBeforeRelease = State->HeldLayerCollection.IsValid()
                ? State->HeldLayerCollection->GetNodes().Num() : 0;
            State->LayerRevisionBeforeRelease = State->HeldLayerCollection.IsValid()
                ? State->HeldLayerCollection->GetRevision() : 0;
        }
        if (State->Window.IsValid()) { FSlateApplication::Get().DestroyWindowImmediately(State->Window.ToSharedRef()); }
        State->Window.Reset();
        State->Panel.Reset();
        Tick(FSlateApplication::Get());
        State->bReleased = !State->WeakPanel.IsValid() && !State->WeakView.IsValid() && !State->WeakRepeat.IsValid()
            && !State->WeakLayerView.IsValid() && !State->WeakLayerTree.IsValid() && !State->WeakSummaryView.IsValid()
            && !State->WeakCommandView.IsValid();
        for (const TSharedPtr<SButton>& HeldCommandAction : State->HeldCommandActions)
        { if (HeldCommandAction.IsValid()) { HeldCommandAction->SimulateClick(); } }
        if (State->HeldCommandSearch.IsValid()) { State->HeldCommandSearch->SetText(FText::FromString(TEXT("released"))); }
        State->bReleasedCallbacksInert = State->bReleased && State->HeldHistoryCollection.IsValid()
            && State->HeldLayerCollection.IsValid() && State->HistoryRecordsBeforeRelease > 0
            && State->LayerNodesBeforeRelease > 0 && State->HeldCommandSearch.IsValid()
            && State->HeldHistoryCollection->GetRecords().Num() == State->HistoryRecordsBeforeRelease
            && State->HeldLayerCollection->GetNodes().Num() == State->LayerNodesBeforeRelease
            && State->HeldLayerCollection->GetRevision() == State->LayerRevisionBeforeRelease
            && State->HeldLayerCollection->FindNode(State->LayerTag.ToString()) == State->StableLayerRoot;
    })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this, FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
    {
        TestTrue(TEXT("AS-authored History layout literal and concrete AS widget class resolve"), State->bAssetsResolved);
        TestTrue(TEXT("Mounted production History view is ready before PIE"), State->bMounted);
        TestTrue(TEXT("Mounted production layer view is an empty retained tree before PIE"), State->bLayerMounted);
        TestTrue(TEXT("Mounted production summary view is an installed authored visible no-layout branch before PIE"),
            State->bSummaryMounted && State->bSummaryNoLayoutBranch);
        TestTrue(TEXT("Mounted production command view exposes every authored command by stable id"), State->bCommandMounted);
        TestTrue(TEXT("Production local-player subsystem creates the authored layout"), State->bLayoutCreated);
        TestTrue(TEXT("Created layout shows authored live summary with two layers and no active tag"), State->bSummaryLayoutBranches);
        TestTrue(TEXT("Public primary-layer push switches authored summary to primary GameAndUI"), State->bSummaryPrimaryState);
        TestTrue(TEXT("Public secondary-layer push switches authored summary active tag and effective input mode"), State->bSummarySecondaryState);
        TestTrue(TEXT("Public secondary-layer pop restores authored summary to primary GameAndUI"), State->bSummaryPrimaryRestored);
        TestTrue(TEXT("Post-capture production history, repeat, and layer tree reconcile together"), State->bPostCaptureHistoryRepeatTreeSettled);
        TestTrue(TEXT("Two production layers and a real widget publish complete authored tree fields"), State->bLayerPublished);
        TestTrue(TEXT("Physical authored search, filter clear, and active-only projection preserve stable layer and widget nodes"), State->bLayerProjection);
        TestTrue(TEXT("Authored Expand All and Collapse All route to the retained tree"), State->bLayerActions);
        TestTrue(TEXT("Authored command view reload retains its mounted search draft and rejects malformed reload"), State->bCommandReloadRetained);
        TestTrue(TEXT("Authored Force Refresh routes through the mounted command surface without replacing stable layer nodes"),
            State->bForceRefreshObserved);
        TestTrue(TEXT("Compatible and rejected layer reloads preserve view, tree, native tree, nodes, and expansion"), State->bLayerReloadRetained);
        TestTrue(TEXT("Public layout push publishes newest-first History record"), State->bPushPublished);
        TestTrue(TEXT("Public layout pop publishes a History record"), State->bPopPublished);
        TestTrue(TEXT("Compatible History refresh retains the published record identity"), State->bRefreshRetained);
        TestTrue(TEXT("One ClearLayer call publishes exactly one cleared History event"), State->bClearPublishedExactlyOnce);
        AddInfo(FString::Printf(TEXT("Clear History input state: enabled=%d revision=%lld input-suspensions=%d; pointer captor after down: valid=%d type=%s tag=%s path-contains-target=%d"),
            State->bClearButtonEnabledBeforeDown, static_cast<long long>(State->CommandViewRevisionBeforeClear), State->InputSuspensionCountBeforeClearClick,
            State->bClearButtonCaptorValidAfterDown, *State->ClearButtonCaptorType, *State->ClearButtonCaptorTag.ToString(),
            State->bClearButtonCaptorPathContainsTarget));
        TestTrue(TEXT("Mounted Clear History button is present in the physical hit-test path"), State->bClearButtonTargeted);
        TestTrue(TEXT("Mounted Clear History button remains enabled before pointer down"), State->bClearButtonEnabledBeforeDown);
        TestEqual(TEXT("Production layer transition releases its input suspension before Clear History pointer input"),
            State->InputSuspensionCountBeforeClearClick, 0);
        TestTrue(TEXT("Mounted Clear History button handles physical pointer down"), State->bClearButtonDownHandled);
        TestTrue(TEXT("Mounted Clear History button owns pointer capture after mouse down"), State->bClearButtonCapturedAfterDown);
        TestTrue(TEXT("Mounted Clear History button remains in the hit-test path before mouse up"), State->bClearButtonTargetedBeforeUp);
        TestTrue(TEXT("Mounted Clear History button handles physical pointer up"), State->bClearButtonUpHandled);
        TestTrue(TEXT("Mounted Clear History button handles physical pointer input"), State->bClearButtonRouted);
        TestTrue(TEXT("Clear History reconciles the production collection and mounted repeat to empty"), State->bClearHistoryEmpty);
        TestTrue(TEXT("101 production pushes retain newest 100 History records and cap the layer tree at 16 widgets"), State->bCapHeldAfter101Pushes);
        TestTrue(TEXT("Summary values are present before non-empty production wide and narrow captures"), State->bSummaryPresentBeforeCaptures);
        TestTrue(TEXT("Non-empty production History captures succeed at wide and narrow sizes"), State->bWideCapture && State->bNarrowCapture);
        TestTrue(TEXT("Layout and mounted debugger release before EndPIE"), State->bLayoutDestroyed && State->bReleased);
        TestTrue(TEXT("Held authored command callbacks and search cannot mutate after debugger owner release"), State->bReleasedCallbacksInert);
        return State->bAssetsResolved && State->bMounted && State->bLayerMounted && State->bSummaryMounted
            && State->bCommandMounted && State->bSummaryNoLayoutBranch && State->bLayoutCreated && State->bSummaryLayoutBranches
            && State->bSummaryPrimaryState && State->bSummarySecondaryState && State->bSummaryPrimaryRestored
            && State->bPostCaptureHistoryRepeatTreeSettled && State->bLayerPublished
            && State->bLayerProjection && State->bLayerActions && State->bCommandActions && State->bCommandReloadRetained
            && State->bForceRefreshObserved && State->bLayerReloadRetained
            && State->bPushPublished && State->bPopPublished
            && State->bRefreshRetained && State->bClearPublishedExactlyOnce && State->bClearButtonRouted && State->bClearHistoryEmpty
            && State->bCapHeldAfter101Pushes && State->bSummaryPresentBeforeCaptures && State->bWideCapture && State->bNarrowCapture && State->bLayoutDestroyed && State->bReleased
            && State->bReleasedCallbacksInert;
    }), TEXT("UI debugger History drives production local-player layout events through its mounted authored surface")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif
