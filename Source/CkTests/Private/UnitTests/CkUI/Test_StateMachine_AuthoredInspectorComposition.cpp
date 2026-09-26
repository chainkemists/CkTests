#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkCore/Validation/CkIsValid.h"
#include "CkDebuggerCommon/Settings/CkDebuggerStyleSettings.h"
#include "CkDebuggerCommon/Navigation/CkDebug_SelectionSync.h"
#include "CkDebuggerCommon/Widgets/SCkDebug_EntityRef.h"
#include "CkDebuggerCommon/Widgets/SCkDebug_EventTimeline.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Fragment.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcsDebugger/Inspectors/CkInspectorWidgetBuilder.h"
#include "CkEcsDebugger/Inspectors/CkInspector_StateMachine.h"
#include "CkEditorTools/Style/CkStyle.h"
#include "CkSlateLayout/CkFlexText.h"
#include "CkSlateLayout/SCkUiRepeat.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkStateMachine/Debug/CkStateMachine_Debug_Fragment.h"
#include "CkStateMachine/Debug/CkStateMachine_Debug_Utils.h"
#include "CkStateMachine/State/CkSmState_Fragment.h"
#include "CkStateMachine/StateMachine/CkStateMachine_Fragment.h"
#include "CkStateMachine/StateMachine/CkStateMachine_Utils.h"
#include "CkStateMachine/Condition/CkSmCondition_Fragment.h"
#include "CkStateMachine/Task/CkSmTask_Fragment.h"
#include "CkStateMachine/Transition/CkSmTransition_Fragment.h"
#include "CkTests/Net/CkAutoTest_Sm_Recorder.h"
#include "CkTests/Net/CkAutoTest_Sm_RecordingState.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include "Engine/World.h"
#include "Framework/Application/SlateApplication.h"
#include "Framework/Docking/TabManager.h"
#include "Input/Events.h"
#include "Input/HittestGrid.h"
#include "InputCoreTypes.h"
#include "Interfaces/IPluginManager.h"
#include "Layout/WidgetPath.h"
#include "Misc/App.h"
#include "Misc/AutomationTest.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "UObject/SoftObjectPath.h"
#include "Widgets/Docking/SDockTab.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/SNullWidget.h"
#include "Widgets/SWindow.h"
#include "Widgets/SToolTip.h"
#include "Widgets/Text/STextBlock.h"

namespace ck_tests_state_machine_authored
{
    constexpr auto kFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;
    constexpr auto kHistoryTransitionCount = int32{9};

    auto FindButton(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SButton>
    {
        if (InRoot->GetTypeAsString() == TEXT("SButton") && InRoot->GetTag() == InTag)
        { return StaticCastSharedRef<SButton>(InRoot); }
        FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const auto Found = FindButton(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag);
                Found.IsValid())
            { return Found; }
        }
        return nullptr;
    }

    auto TickSlate(FSlateApplication& InSlate) -> void
    { InSlate.PumpMessages(); InSlate.Tick(); InSlate.Tick(); }

    auto FindType(const TSharedRef<SWidget>& InRoot, const FString& InType) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTypeAsString() == InType) { return InRoot; }
        const auto Children = InRoot->GetChildren();
        for (auto Index = int32{0}; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const auto Found = FindType(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InType);
                Found.IsValid()) { return Found; }
        }
        return nullptr;
    }

    auto CollectText(const TSharedRef<SWidget>& InRoot, TArray<FString>& OutText) -> void
    {
        if (InRoot->GetTypeAsString() == TEXT("STextBlock"))
        { OutText.Add(StaticCastSharedRef<STextBlock>(InRoot)->GetText().ToString()); }
        else if (InRoot->GetTypeAsString() == TEXT("SCkFlexText"))
        { OutText.Add(StaticCastSharedRef<SCkFlexText>(InRoot)->GetText().ToString()); }
        const auto Children = InRoot->GetChildren();
        for (auto Index = int32{0}; Children != nullptr && Index < Children->Num(); ++Index)
        { CollectText(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), OutText); }
    }

    // Probe the actual native leaf's public hover/tooltip channel, not a copied event array.
    // Narrow windows isolate each production timestamp without depending on font-measured gutters
    // or frame spacing. This is content proof; physical action routing is covered separately below.
    auto CaptureTimelineTooltips(const TSharedRef<SWidget>& InWidget,
        const TArray<ck::FCk_SmDebug_HistoryEntry>& InHistory) -> TArray<FString>
    {
        auto Result = TArray<FString>{};
        if (InHistory.Num() < 2 || InWidget->GetTypeAsString() != TEXT("SCkDebug_EventTimeline")) { return Result; }
        auto MinGap = InHistory[1].RealTimeSeconds - InHistory[0].RealTimeSeconds;
        for (auto Index = int32{1}; Index < InHistory.Num(); ++Index)
        { MinGap = FMath::Min(MinGap, InHistory[Index].RealTimeSeconds - InHistory[Index - 1].RealTimeSeconds); }
        if (MinGap <= 0.0) { return Result; }
        const auto Timeline = StaticCastSharedRef<SCkDebug_EventTimeline>(InWidget);
        const auto PreviousStart = Timeline->Get_ViewStart();
        const auto PreviousDuration = Timeline->Get_ViewDuration();
        const auto PreviousFollow = Timeline->Get_IsFollowingLive();
        const auto Geometry = FGeometry::MakeRoot(FVector2D{512.0f, 60.0f}, FSlateLayoutTransform{});
        const TSet<FKey> NoButtons;
        for (auto EntryIndex = int32{0}; EntryIndex < InHistory.Num(); ++EntryIndex)
        {
            const auto& Entry = InHistory[EntryIndex];
            const auto IsFinalEntry = EntryIndex == InHistory.Num() - 1;
            Timeline->Set_View(IsFinalEntry ? 0.0 : Entry.RealTimeSeconds - MinGap * 0.25,
                IsFinalEntry ? 0.0 : MinGap * 0.5);
            auto Hovered = TArray<FString>{};
            for (auto X = int32{0}; X <= 512; X += 4)
            {
                const auto Position = FVector2D{static_cast<double>(X), 30.0};
                const FPointerEvent Move{0, FSlateApplication::CursorPointerIndex, Position, Position,
                    NoButtons, EKeys::Invalid, 0.0f, FModifierKeysState{}};
                InWidget->OnMouseMove(Geometry, Move);
                if (const auto Tooltip = InWidget->GetToolTip(); Tooltip.IsValid()
                    && Tooltip->AsWidget()->GetTypeAsString() == TEXT("SToolTip"))
                {
                    const auto Text = StaticCastSharedRef<SToolTip>(Tooltip->AsWidget())->GetTextTooltip().ToString();
                    if (NOT Text.IsEmpty() && (NOT IsFinalEntry
                        || Text.StartsWith(FString::Printf(TEXT("[%d] "), EntryIndex))))
                    { Hovered.AddUnique(Text); }
                }
            }
            // The final event is probed in the full view because a micro-window clamps it to the right edge,
            // where floating cancellation can cull it. Its index prefix isolates that marker from earlier ones.
            // More than one marker in every other isolated window is also a content mismatch.
            Result.Add(FString::Join(Hovered, TEXT(" | ")));
        }
        Timeline->Set_View(PreviousStart, PreviousDuration);
        Timeline->Set_FollowLive(PreviousFollow);
        InWidget->OnMouseLeave(FPointerEvent{});
        return Result;
    }

    auto ContainsWidget(const FWidgetPath& InPath, const TSharedRef<SWidget>& InWidget) -> bool
    {
        for (int32 Index = 0; Index < InPath.Widgets.Num(); ++Index)
        {
            if (InPath.Widgets[Index].Widget == InWidget) { return true; }
        }
        return false;
    }

    struct FPhysicalClickResult final
    {
        bool NativeWindow = false;
        bool Enabled = false;
        bool Arranged = false;
        bool Visible = false;
        bool Targeted = false;
        bool SameWindowTargeted = false;
        bool DownHandled = false;
        bool Captured = false;
        bool TargetedBeforeUp = false;
        bool UpHandled = false;
        int32 HitPathSize = 0;
        FString HitRootType;
        FString HitLeafType;

        auto Succeeded() const -> bool
        { return NativeWindow && Enabled && Arranged && Targeted && DownHandled && Captured && TargetedBeforeUp && UpHandled; }

        auto Describe() const -> FString
        {
            return FString::Printf(TEXT("native=%d enabled=%d arranged=%d visible=%d hit=%d same-window=%d "
                "path=%d root='%s' leaf='%s' down=%d capture=%d up-hit=%d up=%d"),
                NativeWindow, Enabled, Arranged, Visible, Targeted, SameWindowTargeted,
                HitPathSize, *HitRootType, *HitLeafType,
                DownHandled, Captured, TargetedBeforeUp, UpHandled);
        }
    };

    // The same native-window routing used by Inventories: arranged path geometry, real hit testing,
    // and Slate mouse down/capture/up. Never invoke the button's handler or action binding directly.
    auto ClickDetailed(FSlateApplication& InSlate, const TSharedRef<SButton>& InButton) -> FPhysicalClickResult
    {
        auto Result = FPhysicalClickResult{};
        const auto Window = InSlate.FindWidgetWindow(InButton);
        Result.NativeWindow = Window.IsValid() && Window->GetNativeWindow().IsValid();
        if (NOT Result.NativeWindow) { return Result; }
        Window->BringToFront(true);
        TickSlate(InSlate);
        // A settling tick can open a deferred tooltip over the synthetic cursor. Close it after the final tick,
        // then redraw without ticking again so the physical move/click sees the production fixture window.
        InSlate.CloseToolTip();
        InSlate.ReleaseAllPointerCapture(0);
        Result.Enabled = InButton->IsEnabled();
        FWidgetPath WidgetPath;
        if (NOT InSlate.GeneratePathToWidgetUnchecked(InButton, WidgetPath, EVisibility::All))
        { return Result; }
        TOptional<FGeometry> Geometry;
        for (int32 Index = 0; Index < WidgetPath.Widgets.Num(); ++Index)
        {
            if (WidgetPath.Widgets[Index].Widget == InButton)
            { Geometry = WidgetPath.Widgets[Index].Geometry; }
        }
        if (NOT Geometry.IsSet()) { return Result; }
        const auto& ArrangedGeometry = Geometry.GetValue();
        Result.Arranged = ArrangedGeometry.GetLocalSize().X > 0.0f && ArrangedGeometry.GetLocalSize().Y > 0.0f;
        if (NOT Result.Arranged) { return Result; }
        const auto Position = ArrangedGeometry.LocalToAbsolute(ArrangedGeometry.GetLocalSize() * 0.5f);
        const TSet<FKey> NoButtons;
        const TSet<FKey> LeftDown{EKeys::LeftMouseButton};
        const FPointerEvent MoveEvent(0, FSlateApplication::CursorPointerIndex,
            Position, Position, NoButtons, EKeys::Invalid, 0.0f, FModifierKeysState{});
        const FPointerEvent DownEvent(0, FSlateApplication::CursorPointerIndex,
            Position, Position, LeftDown, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        const FPointerEvent UpEvent(0, FSlateApplication::CursorPointerIndex,
            Position, Position, NoButtons, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        InSlate.SetCursorPos(Position);
        InSlate.ProcessMouseMoveEvent(MoveEvent, true);
        InSlate.ForceRedrawWindow(Window.ToSharedRef());
        Result.Visible = InButton->GetVisibility() == EVisibility::Visible;
        const auto HitPath = InSlate.LocateWindowUnderMouse(
            Position, InSlate.GetInteractiveTopLevelWindows(), false, 0);
        Result.HitPathSize = HitPath.Widgets.Num();
        if (Result.HitPathSize > 0)
        {
            Result.HitRootType = HitPath.Widgets[0].Widget->GetTypeAsString();
            Result.HitLeafType = HitPath.Widgets.Last().Widget->GetTypeAsString();
        }
        Result.Targeted = ContainsWidget(HitPath, InButton);
        Result.SameWindowTargeted = ContainsWidget(FWidgetPath(Window->GetHittestGrid().GetBubblePath(
            Position, InSlate.GetCursorRadius(), false, 0)), InButton);
        if (NOT Result.Targeted) { return Result; }
        Result.DownHandled = InSlate.ProcessMouseButtonDownEvent(Window->GetNativeWindow(), DownEvent);
        Result.Captured = InButton->HasMouseCapture();
        Result.TargetedBeforeUp = ContainsWidget(InSlate.LocateWindowUnderMouse(
            Position, InSlate.GetInteractiveTopLevelWindows(), false, 0), InButton);
        Result.UpHandled = InSlate.ProcessMouseButtonUpEvent(UpEvent);
        TickSlate(InSlate);
        return Result;
    }

    struct FPhysicalPressResult final
    {
        bool NativeWindow = false;
        bool Arranged = false;
        bool Targeted = false;
        bool DownHandled = false;

        auto Succeeded() const -> bool
        { return NativeWindow && Arranged && Targeted && DownHandled; }

        auto Describe() const -> FString
        {
            return FString::Printf(TEXT("native=%d arranged=%d hit=%d down=%d"),
                NativeWindow, Arranged, Targeted, DownHandled);
        }
    };

    // Entity references activate on mouse-down rather than the SButton capture/up route.
    // Keep this on the real native window and hit-test path so the custom-widget adapter,
    // SCkDebug_EntityRef, navigation slot, and ECS selection model all participate.
    auto PressDetailed(FSlateApplication& InSlate, const TSharedRef<SWidget>& InWidget) -> FPhysicalPressResult
    {
        auto Result = FPhysicalPressResult{};
        const auto Window = InSlate.FindWidgetWindow(InWidget);
        Result.NativeWindow = Window.IsValid() && Window->GetNativeWindow().IsValid();
        if (NOT Result.NativeWindow) { return Result; }
        Window->BringToFront(true);
        TickSlate(InSlate);
        InSlate.CloseToolTip();
        InSlate.ReleaseAllPointerCapture(0);
        FWidgetPath WidgetPath;
        if (NOT InSlate.GeneratePathToWidgetUnchecked(InWidget, WidgetPath, EVisibility::All))
        { return Result; }
        TOptional<FGeometry> Geometry;
        for (int32 Index = 0; Index < WidgetPath.Widgets.Num(); ++Index)
        {
            if (WidgetPath.Widgets[Index].Widget == InWidget)
            { Geometry = WidgetPath.Widgets[Index].Geometry; }
        }
        if (NOT Geometry.IsSet()) { return Result; }
        const auto& ArrangedGeometry = Geometry.GetValue();
        Result.Arranged = ArrangedGeometry.GetLocalSize().X > 0.0f && ArrangedGeometry.GetLocalSize().Y > 0.0f;
        if (NOT Result.Arranged) { return Result; }
        const auto Position = ArrangedGeometry.LocalToAbsolute(ArrangedGeometry.GetLocalSize() * 0.5f);
        const TSet<FKey> NoButtons;
        const TSet<FKey> LeftDown{EKeys::LeftMouseButton};
        const FPointerEvent MoveEvent(0, FSlateApplication::CursorPointerIndex,
            Position, Position, NoButtons, EKeys::Invalid, 0.0f, FModifierKeysState{});
        const FPointerEvent DownEvent(0, FSlateApplication::CursorPointerIndex,
            Position, Position, LeftDown, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        const FPointerEvent UpEvent(0, FSlateApplication::CursorPointerIndex,
            Position, Position, NoButtons, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        InSlate.SetCursorPos(Position);
        InSlate.ProcessMouseMoveEvent(MoveEvent, true);
        InSlate.ForceRedrawWindow(Window.ToSharedRef());
        Result.Targeted = ContainsWidget(InSlate.LocateWindowUnderMouse(
            Position, InSlate.GetInteractiveTopLevelWindows(), false, 0), InWidget);
        if (Result.Targeted)
        { Result.DownHandled = InSlate.ProcessMouseButtonDownEvent(Window->GetNativeWindow(), DownEvent); }
        InSlate.ProcessMouseButtonUpEvent(UpEvent);
        TickSlate(InSlate);
        return Result;
    }

    auto HoverInspectorAction(FSlateApplication& InSlate, const TSharedRef<SButton>& InButton) -> bool
    {
        const auto Window = InSlate.FindWidgetWindow(InButton);
        if (NOT Window.IsValid() || NOT Window->GetNativeWindow().IsValid()) { return false; }
        Window->BringToFront(true);
        TickSlate(InSlate);
        InSlate.CloseToolTip();
        InSlate.ReleaseAllPointerCapture(0);

        auto HoverHost = InButton->GetParentWidget();
        for (auto Depth = int32{0}; HoverHost.IsValid() && HoverHost->GetTypeAsString() != TEXT("SBox")
            && Depth < 4; ++Depth)
        { HoverHost = HoverHost->GetParentWidget(); }
        if (NOT HoverHost.IsValid() || HoverHost->GetTypeAsString() != TEXT("SBox")) { return false; }

        FWidgetPath WidgetPath;
        if (NOT InSlate.GeneratePathToWidgetUnchecked(HoverHost.ToSharedRef(), WidgetPath, EVisibility::All))
        { return false; }
        TOptional<FGeometry> Geometry;
        for (int32 Index = 0; Index < WidgetPath.Widgets.Num(); ++Index)
        {
            if (&WidgetPath.Widgets[Index].Widget.Get() == HoverHost.Get())
            { Geometry = WidgetPath.Widgets[Index].Geometry; }
        }
        if (NOT Geometry.IsSet()) { return false; }
        const auto& ArrangedGeometry = Geometry.GetValue();
        if (ArrangedGeometry.GetLocalSize().X <= 0.0f || ArrangedGeometry.GetLocalSize().Y <= 0.0f)
        { return false; }
        const auto Position = ArrangedGeometry.LocalToAbsolute(ArrangedGeometry.GetLocalSize() * 0.5f);
        const TSet<FKey> NoButtons;
        const FPointerEvent MoveEvent(0, FSlateApplication::CursorPointerIndex,
            Position, Position, NoButtons, EKeys::Invalid, 0.0f, FModifierKeysState{});
        InSlate.SetCursorPos(Position);
        InSlate.ProcessMouseMoveEvent(MoveEvent, true);
        InSlate.ForceRedrawWindow(Window.ToSharedRef());
        return ContainsWidget(InSlate.LocateWindowUnderMouse(
            Position, InSlate.GetInteractiveTopLevelWindows(), false, 0), HoverHost.ToSharedRef())
            && InButton->GetVisibility() == EVisibility::Visible;
    }

    auto RequestCount(const FCk_Handle& InEntity) -> int32
    {
        return ck::IsValid(InEntity) && InEntity.Has<ck::FFragment_Sm_Requests>()
            ? InEntity.Get<ck::FFragment_Sm_Requests>().Get_Requests().Num() : 0;
    }

    auto HasStatus(const FCk_Handle_StateMachine& InSm, ECk_SmRunStatus InStatus) -> bool
    {
        return ck::IsValid(InSm) && InSm.Has<ck::FFragment_Sm_Current>()
            && UCk_Utils_StateMachine_UE::Get_RunStatus(InSm) == InStatus;
    }

    auto HasActionOutcome(const FCk_Handle_StateMachine& InSm, ECk_SmRunStatus InStatus,
        int32 InInitialRecordedEvents) -> bool
    {
        if (NOT HasStatus(InSm, InStatus) || RequestCount(InSm) != 0) { return false; }
        const auto CurrentClass = UCk_Utils_StateMachine_UE::Get_CurrentStateClass(InSm);
        const auto CurrentState = UCk_Utils_StateMachine_UE::Get_CurrentStateHandle(InSm);
        const auto Stopped = InStatus == ECk_SmRunStatus::Stopped;
        const auto StateMatches = Stopped ? CurrentClass == nullptr && ck::Is_NOT_Valid(CurrentState)
            : CurrentClass == UCk_AutoTest_Sm_RecordingState_D::StaticClass() && ck::IsValid(CurrentState);
        const auto World = ck::auto_test::net::Get_ServerWorld();
        const auto Recorder = World != nullptr ? World->GetSubsystem<UCk_AutoTest_Sm_RecorderSubsystem>() : nullptr;
        // A cleared/current handle alone does not prove the deferred state Enter/Exit callback ran.
        return StateMatches && Recorder != nullptr
            && Recorder->Get_EventsForState(UCk_AutoTest_Sm_RecordingState_D::StaticClass()).Num()
                >= InInitialRecordedEvents + (Stopped ? 2 : 1);
    }

    auto CaptureRows(FCkInspector_StateMachine& InInspector, const FCk_Handle& InEntity) -> TMap<FString, FString>
    {
        const FCkInspector_RowCaptureScope Capture{};
        InInspector.Build_Inspector(InEntity);
        return Capture.Get_Rows();
    }

    auto HistoryStateClass(const int32 InIndex) -> UClass*
    {
        return InIndex % 2 == 0 ? UCk_AutoTest_Sm_RecordingState_B::StaticClass()
            : UCk_AutoTest_Sm_RecordingState_C::StaticClass();
    }

    auto HasHistoryOutcome(const FCk_Handle_StateMachine& InSm, UClass* InClass, const int32 InCount) -> bool
    {
        if (NOT HasStatus(InSm, ECk_SmRunStatus::Running) || RequestCount(InSm) != 0
            || InSm.Has<ck::FFragment_Sm_PendingTransition>()
            || NOT UCk_Utils_StateMachineDebug_UE::Get_IsDebuggerCaptureActive(InSm)) { return false; }
        const auto State = UCk_Utils_StateMachine_UE::Get_CurrentStateHandle(InSm);
        return UCk_Utils_StateMachine_UE::Get_CurrentStateClass(InSm) == InClass && ck::IsValid(State)
            && State.Has<ck::FTag_SmState_Active>()
            && InSm.Get<ck::FFragment_Sm_Debug>().Get_History().Num() == InCount
            && (NOT InSm.Has<ck::FFragment_SmDebug_Requests>()
                || InSm.Get<ck::FFragment_SmDebug_Requests>().Get_Requests().IsEmpty());
    }

    auto LoadAsStateClass(const TCHAR* InPath) -> TSubclassOf<UCk_SmState_EntityScript>
    { return FSoftClassPath{InPath}.TryLoadClass<UCk_SmState_EntityScript>(); }

    auto EventCount(UWorld* InWorld, TSubclassOf<UCk_SmState_EntityScript> InClass,
        ECk_AutoTest_Sm_EventKind InKind) -> int32
    {
        const auto Recorder = InWorld != nullptr
            ? InWorld->GetSubsystem<UCk_AutoTest_Sm_RecorderSubsystem>() : nullptr;
        if (Recorder == nullptr) { return 0; }
        auto Count = int32{0};
        for (const auto& Event : Recorder->Get_EventsForState(InClass))
        { Count += Event.Kind == InKind ? 1 : 0; }
        return Count;
    }

    auto BuildAuthored(FAutomationTestBase& InTest, FCkInspector_StateMachine& InInspector,
        const FCk_Handle& InEntity) -> TSharedPtr<SCkInspector_StateMachineAuthored>
    {
        const auto Built = InInspector.Build_Inspector(InEntity);
        if (NOT InTest.TestTrue(*FString::Printf(TEXT("production authored StateMachine type=%s error='%s'"),
            *Built->GetTypeAsString(), *InInspector.Get_LastAuthoredLoadError()),
            Built->GetTypeAsString() == TEXT("SCkInspector_StateMachineAuthored")))
        { return nullptr; }
        const auto Authored = StaticCastSharedRef<SCkInspector_StateMachineAuthored>(Built);
        if (NOT InTest.TestTrue(TEXT("authored StateMachine mounted a live view"),
            Authored->Is_Mounted() && Authored->Get_View().IsValid() && NOT Authored->Is_Inert()))
        { return nullptr; }
        return Authored;
    }

    struct FScenario final
    {
        FCk_Handle Owner;
        FCk_Handle_StateMachine Sm;
        FCk_Handle_SmState EnteredState;
        TUniquePtr<FCkInspector_StateMachine> Inspector;
        TSharedPtr<SCkInspector_StateMachineAuthored> Authored;
        TSharedPtr<SCkInspector_StateMachineAuthored> SecondAuthored;
        TSharedPtr<SWindow> Window;
        ECkDebugAxis_EditControlStyle PreviousStyle = ECkDebugAxis_EditControlStyle::Inline;
        bool StyleOverridden = false;
        bool FixtureCreated = false;
        bool UiReady = false;
        bool ReleasedBeforeEndPIE = false;
        int32 ActionsCompleted = 0;
        int32 InitialRecordedEvents = 0;
        bool HadDebugSnapshot = false;
        FString HistoryTitle;
        FString HistoryRun;
        FString HistoryEnteredAt;
        bool PreviousCaptureVisible = false;
        bool CaptureOverridden = false;
        bool HistoryReady = false;
        int32 HistoryInitialRun = 0;
        int32 HistoryTransitionsCompleted = 0;

        auto RestoreStyle() -> void
        {
            if (StyleOverridden)
            {
                UCkDebuggerStyleSettings::Get_Mutable()->Selection.EditControlStyle = PreviousStyle;
                StyleOverridden = false;
            }
        }

        auto RestoreCapture() -> void
        {
            if (CaptureOverridden)
            {
                UCk_Utils_StateMachineDebug_UE::Set_IsDebuggerCaptureVisible(PreviousCaptureVisible);
                CaptureOverridden = false;
            }
        }

        ~FScenario() { RestoreCapture(); RestoreStyle(); }
    };

    struct FActionCase final
    {
        FName Id;
        ECk_SmRunStatus Before;
        ECk_SmRunStatus After;
        ECk_Tone Tone;
    };

    struct FVariantScenario final
    {
        TSubclassOf<UCk_SmState_EntityScript> HierarchyClass;
        TSubclassOf<UCk_SmState_EntityScript> CascadeClass;
        TSubclassOf<UCk_SmState_EntityScript> OverrideBaseClass;
        TSubclassOf<UCk_SmState_EntityScript> OverrideReplacementClass;
        FCk_Handle Owner;
        FCk_Handle_StateMachine Sm;
        FCk_Handle_SmState State;
        FCk_Handle_SmTask Task;
        FCk_Handle_SmTransition Transition;
        FCk_Handle_SmCondition Condition;
        FCk_Handle_StateMachine SubSm;
        FCk_Handle_SmState SubState;
        FCk_Handle OverrideOwner;
        FCk_Handle_StateMachine OverrideSm;
        FCk_Handle ClientOwner;
        FCk_Handle_StateMachine ClientSm;
        FCk_Handle CascadeOwner;
        FCk_Handle_StateMachine CascadeSm;
        FCk_Handle_StateMachine StaleSm;
        TUniquePtr<FCkInspector_StateMachine> Inspector;
        TSharedPtr<SCkInspector_StateMachineAuthored> Authored;
        TSharedPtr<SWindow> Window;
        FVector2D PreviousCursor = FVector2D::ZeroVector;
        ECkDebugAxis_EditControlStyle PreviousStyle = ECkDebugAxis_EditControlStyle::Inline;
        bool CursorCaptured = false;
        bool StyleOverridden = false;
        bool ServerReady = false;
        bool TopologyReady = false;
        bool VariantsAccepted = false;
        bool OverrideAccepted = false;
        bool ClientRefusalAccepted = false;
        bool StopAccepted = false;
        bool CascadeCreated = false;
        bool CascadeAccepted = false;
        bool StaleAccepted = false;
        bool ReleasedBeforeEndPIE = false;
        bool EcsDebuggerWasOpen = false;
        int32 InitialDoExitCount = 0;
        int32 CascadeInitialDoExitCount = 0;

        auto RestoreStyle() -> void
        {
            if (StyleOverridden)
            {
                UCkDebuggerStyleSettings::Get_Mutable()->Selection.EditControlStyle = PreviousStyle;
                StyleOverridden = false;
            }
        }

        auto RestoreCursor() -> void
        {
            if (CursorCaptured && FSlateApplication::IsInitialized())
            {
                FSlateApplication::Get().SetCursorPos(PreviousCursor);
                CursorCaptured = false;
            }
        }

        ~FVariantScenario() { RestoreCursor(); RestoreStyle(); }
    };

    auto ResolveVariantTopology(FVariantScenario& InScenario) -> bool
    {
        if (NOT HasStatus(InScenario.Sm, ECk_SmRunStatus::Running)
            && NOT HasStatus(InScenario.Sm, ECk_SmRunStatus::Paused))
        { return false; }
        InScenario.State = UCk_Utils_StateMachine_UE::Get_CurrentStateHandle(InScenario.Sm);
        if (ck::Is_NOT_Valid(InScenario.State)) { return false; }
        const auto Tasks = UCk_Utils_StateMachine_UE::RecordOfSmTasks_Utils::Get_ValidEntries(InScenario.State);
        const auto Transitions = UCk_Utils_StateMachine_UE::RecordOfSmTransitions_Utils::Get_ValidEntries(InScenario.State);
        if (Tasks.Num() != 1 || Transitions.Num() != 1) { return false; }
        InScenario.Task = Tasks[0];
        InScenario.Transition = Transitions[0];
        const auto Conditions = UCk_Utils_StateMachine_UE::RecordOfSmConditions_Utils::Get_ValidEntries(InScenario.Transition);
        if (Conditions.Num() != 1 || NOT InScenario.Task.Has<ck::FFragment_SmTask_SubStateMachine>())
        { return false; }
        InScenario.Condition = Conditions[0];
        InScenario.SubSm = InScenario.Task.Get<ck::FFragment_SmTask_SubStateMachine>().Get_SubStateMachineHandle();
        if (ck::Is_NOT_Valid(InScenario.SubSm)
            || (NOT HasStatus(InScenario.SubSm, ECk_SmRunStatus::Running)
                && NOT HasStatus(InScenario.SubSm, ECk_SmRunStatus::Paused)))
        { return false; }
        InScenario.SubState = UCk_Utils_StateMachine_UE::Get_CurrentStateHandle(InScenario.SubSm);
        return ck::IsValid(InScenario.SubState);
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_StateMachine_AuthoredInspectorComposition,
    "Ck.UiAuthoring.EcsDebugger.StateMachineInspector.AuthoredComposition", ck_tests_state_machine_authored::kFlags | EAutomationTestFlags::NonNullRHI)

bool FCkTest_StateMachine_AuthoredInspectorComposition::RunTest(const FString& Parameters)
{
    using namespace ck_tests_state_machine_authored;
    if (NOT FSlateApplication::IsInitialized() || NOT FApp::CanEverRender())
    {
        AddError(TEXT("StateMachine authored routed-click proof requires initialized Slate and real RHI (--no-nullrhi)."));
        return false;
    }

    const auto Scenario = MakeShared<FScenario>();
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, Scenario](UWorld* InWorld)
        {
            Scenario->PreviousStyle = UCkDebuggerStyleSettings::Get_Selection().EditControlStyle;
            Scenario->StyleOverridden = true;
            UCkDebuggerStyleSettings::Get_Mutable()->Selection.EditControlStyle = ECkDebugAxis_EditControlStyle::Inline;
            Scenario->Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InWorld, {});
            if (NOT TestTrue(TEXT("real PIE transient owner created"), ck::IsValid(Scenario->Owner))) { return; }
            auto Params = FCk_Fragment_StateMachine_ParamsData{UCk_AutoTest_Sm_RecordingState_D::StaticClass()};
            Params.Set_AutoStart(ECk_SmAutoStart::Disabled);
            Scenario->Sm = UCk_Utils_StateMachine_UE::Add(Scenario->Owner, Params);
            Scenario->FixtureCreated = TestTrue(TEXT("production AutoStart-disabled StateMachine composed"),
                ck::IsValid(Scenario->Sm));
            if (const auto Recorder = InWorld->GetSubsystem<UCk_AutoTest_Sm_RecorderSubsystem>();
                TestNotNull(TEXT("real state lifecycle recorder is available"), Recorder))
            { Scenario->InitialRecordedEvents = Recorder->Get_EventsForState(UCk_AutoTest_Sm_RecordingState_D::StaticClass()).Num(); }
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this, FCk_NetAutoTest_Condition::CreateLambda([Scenario]()
        {
            return NOT Scenario->FixtureCreated || (HasStatus(Scenario->Sm, ECk_SmRunStatus::Stopped)
                && NOT Scenario->Sm.Has<ck::FTag_Sm_RequiresSetup>() && RequestCount(Scenario->Sm) == 0);
        }), 10.0, TEXT("AutoStart-disabled StateMachine setup completed without a request")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, Scenario](UWorld*)
        {
            if (NOT Scenario->FixtureCreated) { return; }
            if (NOT TestTrue(TEXT("SM begins stopped after the setup processor"),
                HasStatus(Scenario->Sm, ECk_SmRunStatus::Stopped)
                    && NOT Scenario->Sm.Has<ck::FTag_Sm_RequiresSetup>() && RequestCount(Scenario->Sm) == 0)) { return; }
            Scenario->Inspector = MakeUnique<FCkInspector_StateMachine>();
            Scenario->Authored = BuildAuthored(*this, *Scenario->Inspector, Scenario->Sm);
            Scenario->SecondAuthored = BuildAuthored(*this, *Scenario->Inspector, Scenario->Sm);
            if (NOT Scenario->Authored.IsValid() || NOT Scenario->SecondAuthored.IsValid()) { return; }
            TestTrue(TEXT("each production build retains an independent view"),
                Scenario->Authored->Get_View() != Scenario->SecondAuthored->Get_View());
            const auto Rows = CaptureRows(*Scenario->Inspector, Scenario->Sm);
            TestTrue(TEXT("exact native root capture and live authored projection agree"),
                Rows.Contains(TEXT("Status:")) && Rows.Contains(TEXT("Current State:"))
                    && Rows.FindRef(TEXT("Control:")) == TEXT("Start Stop Pause Resume")
                    && Scenario->Authored->Get_Text(TEXT("status")) == Rows.FindRef(TEXT("Status:"))
                    && Scenario->Authored->Get_Text(TEXT("current-state")) == TEXT("(None)")
                    && Scenario->Authored->Get_Text(TEXT("current-state")) == Rows.FindRef(TEXT("Current State:"))
                    && Scenario->Authored->Get_Bool(TEXT("root")) && NOT Scenario->Authored->Get_Bool(TEXT("state"))
                    && NOT Scenario->Authored->Get_Bool(TEXT("pending")) && Scenario->Authored->Get_CanRequest()
                    && Scenario->Authored->Get_Tone(TEXT("status")) == ECk_Tone::Neutral);
            auto Differing = TSet<FString>{TEXT("Status:"), TEXT("Control:")};
            {
                const FCkInspector_DiffMarkScope Scope{&Differing};
                const auto Diff = BuildAuthored(*this, *Scenario->Inspector, Scenario->Sm);
                if (Diff.IsValid())
                {
                    TestTrue(TEXT("diff routes retain exact native label colors"),
                        Diff->Get_DiffColor(TEXT("Status:")) == CkStyle::Accent()
                            && Diff->Get_DiffColor(TEXT("Control:")) == CkStyle::Accent()
                            && Diff->Get_DiffColor(TEXT("Current State:")) == CkStyle::TextDim());
                    Diff->Release();
                }
            }
            Scenario->HadDebugSnapshot = Scenario->Authored->Get_Bool(TEXT("debug"));
            TestEqual(TEXT("debug visibility is based on actual build-time debug composition"),
                Scenario->HadDebugSnapshot, Scenario->Sm.Has<ck::FFragment_Sm_Debug>());
            Scenario->HistoryTitle = Scenario->Authored->Get_Text(TEXT("history-title"));
            Scenario->HistoryRun = Scenario->Authored->Get_Text(TEXT("run"));
            Scenario->HistoryEnteredAt = Scenario->Authored->Get_Text(TEXT("entered-at"));

            auto& Slate = FSlateApplication::Get();
            Scenario->Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{760.0f, 640.0f})
                .CreateTitleBar(false).HasCloseButton(false)[Scenario->Authored.ToSharedRef()];
            Slate.AddWindow(Scenario->Window.ToSharedRef(), true);
            TickSlate(Slate);
            Scenario->Authored->SlatePrepass(1.0f);
            const auto View = Scenario->Authored->Get_View();
            const auto Root = View->GetRegion(TEXT("main"));
            const auto Start = FindButton(Root, TEXT("sm-start"));
            if (NOT TestTrue(TEXT("production authored document exposes all four real action buttons"),
                Start.IsValid() && FindButton(Root, TEXT("sm-stop")).IsValid()
                    && FindButton(Root, TEXT("sm-pause")).IsValid() && FindButton(Root, TEXT("sm-resume")).IsValid())) { return; }
            const auto Plugin = IPluginManager::Get().FindPlugin(TEXT("CkDebugger"));
            if (NOT TestTrue(TEXT("CkDebugger resource owner resolves"), Plugin.IsValid())) { return; }
            FString Markup;
            FString Css;
            const auto ResourceRoot = FPaths::Combine(Plugin->GetBaseDir(), TEXT("Resources/UI"));
            if (NOT TestTrue(TEXT("production StateMachine HTML and CSS resources load"),
                FFileHelper::LoadFileToString(Markup, *FPaths::Combine(ResourceRoot, TEXT("EcsInspectorStateMachine.ui.html")))
                    && FFileHelper::LoadFileToString(Css, *FPaths::Combine(ResourceRoot, TEXT("EcsInspectorStateMachine.ui.css"))))) { return; }
            TestTrue(TEXT("production document retains the specialized timeline port and authored Sub SM reference"),
                Markup.Contains(TEXT("<native id=\"sm-timeline\" bind=\"sm-timeline-port\""))
                    && Markup.Contains(TEXT("<debug-entity-ref id=\"sm-sub-sm\"")));
            const auto Revision = View->GetRevision();
            const auto Reloaded = View->TryReload(Markup, Css, TEXT("StateMachine compatible reload"));
            if (NOT TestTrue(TEXT("compatible reload preserves the main region and fixed action identity"),
                Reloaded.Succeeded && View->GetRevision() > Revision
                    && &View->GetRegion(TEXT("main")).Get() == &Root.Get()
                    && FindButton(View->GetRegion(TEXT("main")), TEXT("sm-start")) == Start)) { return; }
            const auto RejectedRevision = View->GetRevision();
            const auto InvalidMarkup = Markup.Replace(TEXT("action=\"sm-start\""), TEXT("action=\"sm-missing-action\""));
            const auto Rejected = View->TryReload(InvalidMarkup, Css, TEXT("StateMachine missing action"));
            Scenario->UiReady = TestTrue(TEXT("missing required action rejects atomically without replacing the last-good route"),
                InvalidMarkup != Markup && NOT Rejected.Succeeded && View->GetRevision() == RejectedRevision
                    && &View->GetRegion(TEXT("main")).Get() == &Root.Get()
                    && FindButton(View->GetRegion(TEXT("main")), TEXT("sm-start")) == Start);
        })));

    // Every positive outcome waits for the real request processor, not a guessed number of frames.
    const TArray<FActionCase> Actions{
        {TEXT("sm-start"), ECk_SmRunStatus::Stopped, ECk_SmRunStatus::Running, ECk_Tone::Accent},
        {TEXT("sm-pause"), ECk_SmRunStatus::Running, ECk_SmRunStatus::Paused, ECk_Tone::Warn},
        {TEXT("sm-resume"), ECk_SmRunStatus::Paused, ECk_SmRunStatus::Running, ECk_Tone::Accent},
        {TEXT("sm-stop"), ECk_SmRunStatus::Running, ECk_SmRunStatus::Stopped, ECk_Tone::Neutral}};
    for (const auto Action : Actions)
    {
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
            [this, Scenario, Action](UWorld*)
            {
                if (NOT Scenario->UiReady) { return; }
                if (NOT TestTrue(*FString::Printf(TEXT("%s begins from its valid processor state"), *Action.Id.ToString()),
                    HasStatus(Scenario->Sm, Action.Before) && RequestCount(Scenario->Sm) == 0))
                { Scenario->UiReady = false; return; }
                // Reacquire from the current materialized view immediately before routing input.
                const auto Button = FindButton(Scenario->Authored->Get_View()->GetRegion(TEXT("main")), Action.Id);
                if (NOT TestTrue(TEXT("current action resolves"), Button.IsValid()))
                { Scenario->UiReady = false; return; }
                const auto Result = ClickDetailed(FSlateApplication::Get(), Button.ToSharedRef());
                Scenario->UiReady = TestTrue(*FString::Printf(TEXT("%s physical routed click: %s"),
                    *Action.Id.ToString(), *Result.Describe()), Result.Succeeded());
                Scenario->UiReady = TestEqual(*FString::Printf(TEXT("%s enqueued exactly one production request"),
                    *Action.Id.ToString()), RequestCount(Scenario->Sm), 1) && Scenario->UiReady;
            })));
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this, FCk_NetAutoTest_Condition::CreateLambda(
            [Scenario, Action]()
            {
                return NOT Scenario->UiReady || HasActionOutcome(Scenario->Sm, Action.After, Scenario->InitialRecordedEvents);
            }), 10.0, FString::Printf(TEXT("%s processor outcome and drained request queue"), *Action.Id.ToString())));
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
            [this, Scenario, Action](UWorld* InWorld)
            {
                if (NOT Scenario->UiReady) { return; }
                if (NOT TestTrue(*FString::Printf(TEXT("%s reached the expected processor outcome"), *Action.Id.ToString()),
                    HasActionOutcome(Scenario->Sm, Action.After, Scenario->InitialRecordedEvents)))
                { Scenario->UiReady = false; return; }
                ++Scenario->ActionsCompleted;
                const auto Rows = CaptureRows(*Scenario->Inspector, Scenario->Sm);
                TestTrue(TEXT("live run status/current state remain equal to exact native row capture"),
                    Scenario->Authored->Get_Text(TEXT("status")) == Rows.FindRef(TEXT("Status:"))
                        && Scenario->Authored->Get_Text(TEXT("current-state")) == Rows.FindRef(TEXT("Current State:"))
                        && Scenario->Authored->Get_Tone(TEXT("status")) == Action.Tone);
                if (Scenario->HadDebugSnapshot)
                {
                    TestTrue(TEXT("existing history remains one build-time snapshot while root status is live"),
                        Scenario->Authored->Get_Text(TEXT("history-title")) == Scenario->HistoryTitle
                            && Scenario->Authored->Get_Text(TEXT("run")) == Scenario->HistoryRun
                            && Scenario->Authored->Get_Text(TEXT("entered-at")) == Scenario->HistoryEnteredAt);
                }
                if (Action.Id == FName{TEXT("sm-start")})
                {
                    Scenario->EnteredState = UCk_Utils_StateMachine_UE::Get_CurrentStateHandle(Scenario->Sm);
                    const auto StateView = BuildAuthored(*this, *Scenario->Inspector, Scenario->EnteredState);
                    if (StateView.IsValid())
                    {
                        const auto StateRows = CaptureRows(*Scenario->Inspector, Scenario->EnteredState);
                        TestTrue(TEXT("actual entered state has authored state projection and native class capture parity"),
                            StateView->Get_Bool(TEXT("state")) && NOT StateView->Get_Bool(TEXT("root"))
                                && NOT StateView->Get_CanRequest() && StateRows.Contains(TEXT("Class:"))
                                && StateView->Get_Text(TEXT("state-class")) == StateRows.FindRef(TEXT("Class:")));
                        StateView->Release();
                    }
                }
                else if (Action.After != ECk_SmRunStatus::Stopped)
                {
                    TestTrue(TEXT("Pause and Resume preserve the entered state identity"),
                        UCk_Utils_StateMachine_UE::Get_CurrentStateHandle(Scenario->Sm) == Scenario->EnteredState);
                }
                else
                {
                    TestTrue(TEXT("Stop clears the current state class and handle"),
                        UCk_Utils_StateMachine_UE::Get_CurrentStateClass(Scenario->Sm) == nullptr
                            && ck::Is_NOT_Valid(UCk_Utils_StateMachine_UE::Get_CurrentStateHandle(Scenario->Sm)));
                    Scenario->EnteredState = {};
                    if (const auto Recorder = InWorld->GetSubsystem<UCk_AutoTest_Sm_RecorderSubsystem>();
                        TestNotNull(TEXT("lifecycle recorder survives the action sequence"), Recorder))
                    {
                        const auto Events = Recorder->Get_EventsForState(UCk_AutoTest_Sm_RecordingState_D::StaticClass());
                        const auto Offset = Scenario->InitialRecordedEvents;
                        auto OnlyDeduplicatedExitAttemptsFollow = Events.Num() - Offset >= 2;
                        for (auto Index = Offset + 2; Index < Events.Num(); ++Index)
                        {
                            OnlyDeduplicatedExitAttemptsFollow = OnlyDeduplicatedExitAttemptsFollow
                                && Events[Index].Kind == ECk_AutoTest_Sm_EventKind::ExitState;
                        }
                        if (TestTrue(TEXT("one Enter is followed by Exit; only EndPlay dedup exit attempts may trail"),
                            OnlyDeduplicatedExitAttemptsFollow))
                        {
                            TestTrue(TEXT("real state lifecycle callbacks preserve Enter then Exit ordering"),
                                Events[Offset].Kind == ECk_AutoTest_Sm_EventKind::EnterState
                                    && Events[Offset + 1].Kind == ECk_AutoTest_Sm_EventKind::ExitState);
                        }
                    }
                }
            })));
    }

    // Start a separate run only after the original routed-action/lifecycle assertions completed.
    // The debugger's public capture contract owns history; never manufacture debug fragment entries.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, Scenario](UWorld*)
        {
            if (NOT Scenario->UiReady || Scenario->ActionsCompleted != 4) { return; }
            Scenario->PreviousCaptureVisible = UCk_Utils_StateMachineDebug_UE::Get_IsDebuggerCaptureVisible();
            Scenario->CaptureOverridden = true;
            UCk_Utils_StateMachineDebug_UE::Set_IsDebuggerCaptureVisible(true);
            UCk_Utils_StateMachineDebug_UE::BeginDebuggerCapture(Scenario->Sm);
            UCk_Utils_StateMachineDebug_UE::NotifyDebugDataConsumed();
            Scenario->HistoryReady = TestTrue(TEXT("public capture contract admits the fixture machine"),
                UCk_Utils_StateMachineDebug_UE::Get_IsDebuggerCaptureActive(Scenario->Sm));
            if (NOT Scenario->HistoryReady) { return; }
            Scenario->HistoryInitialRun = Scenario->Sm.Get<ck::FFragment_Sm_Debug>().Get_RunCounter();
            UCk_Utils_StateMachine_UE::Request_Start(Scenario->Sm, {});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this, FCk_NetAutoTest_Condition::CreateLambda([Scenario]()
        {
            UCk_Utils_StateMachineDebug_UE::NotifyDebugDataConsumed();
            return NOT Scenario->HistoryReady
                || (HasHistoryOutcome(Scenario->Sm, UCk_AutoTest_Sm_RecordingState_D::StaticClass(), 0)
                    && Scenario->Sm.Get<ck::FFragment_Sm_Debug>().Get_RunCounter() == Scenario->HistoryInitialRun + 1);
        }), 10.0, TEXT("history run entered D and the debug poll observed its new run before transitions")));

    for (auto Index = int32{0}; Index < kHistoryTransitionCount; ++Index)
    {
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
            [this, Scenario, Index](UWorld*)
            {
                if (NOT Scenario->HistoryReady) { return; }
                UCk_Utils_StateMachineDebug_UE::NotifyDebugDataConsumed();
                const auto PreviousClass = Index == 0 ? UCk_AutoTest_Sm_RecordingState_D::StaticClass()
                    : HistoryStateClass(Index - 1);
                Scenario->HistoryReady = TestTrue(TEXT("each history transition starts from the prior committed capture"),
                    HasHistoryOutcome(Scenario->Sm, PreviousClass, Index)
                        && Scenario->Sm.Get<ck::FFragment_Sm_Debug>().Get_RunCounter() == Scenario->HistoryInitialRun + 1);
                if (Scenario->HistoryReady)
                { UCk_Utils_StateMachine_UE::Request_Transition(Scenario->Sm, HistoryStateClass(Index), {}); }
            })));
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this, FCk_NetAutoTest_Condition::CreateLambda(
            [Scenario, Index]()
            {
                UCk_Utils_StateMachineDebug_UE::NotifyDebugDataConsumed();
                return NOT Scenario->HistoryReady || HasHistoryOutcome(Scenario->Sm, HistoryStateClass(Index), Index + 1);
            }), 10.0, FString::Printf(TEXT("history transition %d entered its target and drained the debug capture request"), Index)));
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
            [this, Scenario, Index](UWorld*)
            {
                if (NOT Scenario->HistoryReady) { return; }
                Scenario->HistoryReady = TestTrue(TEXT("production transition and debug capture both completed"),
                    HasHistoryOutcome(Scenario->Sm, HistoryStateClass(Index), Index + 1));
                if (Scenario->HistoryReady) { ++Scenario->HistoryTransitionsCompleted; }
            })));
    }
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, Scenario](UWorld*)
        {
            TestEqual(TEXT("nine real transitions populate history beyond the eight-row presentation limit"),
                Scenario->HistoryTransitionsCompleted, kHistoryTransitionCount);
            if (NOT Scenario->HistoryReady) { return; }
            const auto& Debug = Scenario->Sm.Get<ck::FFragment_Sm_Debug>();
            const auto History = Debug.Get_History();
            if (NOT TestEqual(TEXT("production debug history contains exactly nine committed transitions"),
                History.Num(), kHistoryTransitionCount)) { return; }
            for (auto Index = int32{0}; Index < History.Num(); ++Index)
            {
                const auto& Entry = History[Index];
                const auto PreviousClass = Index == 0 ? UCk_AutoTest_Sm_RecordingState_D::StaticClass()
                    : HistoryStateClass(Index - 1);
                TestEqual(*FString::Printf(TEXT("history [%d] source is the previous committed state"), Index),
                    Entry.FromStateClass.Get(), PreviousClass);
                TestEqual(*FString::Printf(TEXT("history [%d] target is the requested state"), Index),
                    Entry.ToStateClass.Get(), HistoryStateClass(Index));
                TestTrue(*FString::Printf(TEXT("history [%d] direct-request metadata has a timestamp and no conditions"), Index),
                    Entry.RealTimeSeconds > 0.0 && Entry.TransitionConditionNames.IsEmpty());
                if (Index > 0)
                {
                    const auto& Previous = History[Index - 1];
                    // Capture stores GFrameNumber (scene rendering), not GFrameCounter (engine ticks).
                    // Completed production transitions may share a render frame; their array order is authoritative.
                    TestTrue(*FString::Printf(TEXT("history [%d] render frame is nondecreasing: previous=%llu current=%llu"),
                        Index, Previous.FrameNumber, Entry.FrameNumber), Entry.FrameNumber >= Previous.FrameNumber);
                    // This fixture issues separate requests and its tooltip probe requires distinct sampled times.
                    TestTrue(*FString::Printf(TEXT("history [%d] sampled time increases: previous=%.9f current=%.9f"),
                        Index, Previous.RealTimeSeconds, Entry.RealTimeSeconds), Entry.RealTimeSeconds > Previous.RealTimeSeconds);
                }
            }
            auto HistoryInspector = MakeUnique<FCkInspector_StateMachine>();
            const auto HistoryAuthored = BuildAuthored(*this, *HistoryInspector, Scenario->Sm);
            if (NOT HistoryAuthored.IsValid()) { return; }
            const TWeakPtr<FCkUiView> WeakView = HistoryAuthored->Get_View();
            TWeakPtr<SWidget> WeakTimeline;
            {
                const auto Rows = CaptureRows(*HistoryInspector, Scenario->Sm);
                const auto View = HistoryAuthored->Get_View();
                const auto Root = View->GetRegion(TEXT("main"));
                Root->SlatePrepass(1.0f);
                const auto Repeat = View->GetRepeat(TEXT("sm-history"));
                const auto Timeline = FindType(Root, TEXT("SCkDebug_EventTimeline"));
                WeakTimeline = Timeline;
                TestTrue(TEXT("populated native history fields match the authored snapshot"),
                    Rows.Contains(TEXT("Run #:")) && Rows.Contains(TEXT("State Entered At:"))
                        && Rows.Contains(TEXT("Timeline:")) && HistoryAuthored->Get_Bool(TEXT("debug"))
                        && HistoryAuthored->Get_Bool(TEXT("history-populated"))
                        && NOT HistoryAuthored->Get_Bool(TEXT("history-empty"))
                        && HistoryAuthored->Get_Text(TEXT("run")) == Rows.FindRef(TEXT("Run #:"))
                        && HistoryAuthored->Get_Text(TEXT("entered-at")) == Rows.FindRef(TEXT("State Entered At:"))
                        && HistoryAuthored->Get_Text(TEXT("history-title")) == TEXT("History (9)"));
                if (TestTrue(TEXT("populated authored snapshot materializes repeat and native timeline"),
                    Repeat.IsValid() && Timeline.IsValid()))
                {
                    TestEqual(TEXT("authored repeat contains only the last eight history records"), Repeat->GetItemCount(), 8);
                    const auto& Entity = Scenario->Sm.Get_Entity();
                    const auto KeyPrefix = FString::Printf(TEXT("%u:%u:history:%d:"),
                        static_cast<uint32>(Entity.Get_ID()), static_cast<uint32>(Entity.Get_VersionNumber()), Debug.Get_RunCounter());
                    TestFalse(TEXT("oldest history key is excluded while its timeline event remains"),
                        Repeat->GetItemWidget(KeyPrefix + TEXT("0")).IsValid());
                    auto ExpectedText = TArray<FString>{};
                    auto Items = TArray<TSharedPtr<SWidget>>{};
                    for (auto Index = int32{1}; Index < History.Num(); ++Index)
                    {
                        const auto Label = FString::Printf(TEXT("[%d]"), Index);
                        const auto Item = Repeat->GetItemWidget(KeyPrefix + FString::FromInt(Index));
                        Items.Add(Item);
                        ExpectedText.Add(Label);
                        ExpectedText.Add(Rows.FindRef(Label));
                        if (TestTrue(*FString::Printf(TEXT("stable entity/version/run/index key resolves history %d"), Index),
                            Item.IsValid() && Rows.Contains(Label)))
                        {
                            auto ItemText = TArray<FString>{};
                            CollectText(Item.ToSharedRef(), ItemText);
                            TestTrue(TEXT("keyed history label and value equal exact native capture"),
                                ItemText == TArray<FString>{Label, Rows.FindRef(Label)});
                        }
                    }
                    auto ActualText = TArray<FString>{};
                    CollectText(Repeat.ToSharedRef(), ActualText);
                    TestTrue(TEXT("last-eight materialized rows preserve chronological order"), ActualText == ExpectedText);
                    const auto Tooltips = CaptureTimelineTooltips(Timeline.ToSharedRef(), History);
                    TestEqual(TEXT("all nine timeline tooltip payloads equal exact native timeline capture"),
                        TEXT("Transitions ") + FString::Join(Tooltips, TEXT(" ")), Rows.FindRef(TEXT("Timeline:")));

                    const auto Plugin = IPluginManager::Get().FindPlugin(TEXT("CkDebugger"));
                    FString Markup;
                    FString Css;
                    if (TestTrue(TEXT("populated reload resolves production resources"), Plugin.IsValid()))
                    {
                        const auto ResourceRoot = FPaths::Combine(Plugin->GetBaseDir(), TEXT("Resources/UI"));
                        if (TestTrue(TEXT("populated reload reads production HTML and CSS"),
                            FFileHelper::LoadFileToString(Markup, *FPaths::Combine(ResourceRoot, TEXT("EcsInspectorStateMachine.ui.html")))
                                && FFileHelper::LoadFileToString(Css, *FPaths::Combine(ResourceRoot, TEXT("EcsInspectorStateMachine.ui.css")))))
                        {
                            const auto Revision = View->GetRevision();
                            const auto Reloaded = View->TryReload(Markup, Css, TEXT("StateMachine populated history compatible reload"));
                            TestTrue(TEXT("compatible populated reload retains region, repeat, and native timeline identity"),
                                Reloaded.Succeeded && View->GetRevision() > Revision
                                    && &View->GetRegion(TEXT("main")).Get() == &Root.Get()
                                    && View->GetRepeat(TEXT("sm-history")) == Repeat
                                    && FindType(Root, TEXT("SCkDebug_EventTimeline")) == Timeline);
                            Root->SlatePrepass(1.0f);
                            for (auto Index = int32{1}; Index < History.Num(); ++Index)
                            {
                                TestTrue(TEXT("compatible reload preserves every keyed history item identity"),
                                    Repeat->GetItemWidget(KeyPrefix + FString::FromInt(Index)) == Items[Index - 1]);
                            }
                            ActualText.Reset();
                            CollectText(Repeat.ToSharedRef(), ActualText);
                            TestTrue(TEXT("compatible reload preserves last-eight text and order"), ActualText == ExpectedText);
                            TestTrue(TEXT("compatible reload preserves all timeline tooltip content"),
                                CaptureTimelineTooltips(Timeline.ToSharedRef(), History) == Tooltips);
                        }
                    }
                }
            }
            // No test-owned strong view/timeline reference survives this scope boundary.
            HistoryInspector->OnDeactivated();
            TestTrue(TEXT("populated inspector deactivation makes authored snapshot inert"), HistoryAuthored->Is_Inert());
            TestFalse(TEXT("populated inspector deactivation releases its view"), WeakView.IsValid());
            TestFalse(TEXT("populated inspector deactivation releases its native timeline"), WeakTimeline.IsValid());
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [Scenario](UWorld*)
        {
            if (Scenario->CaptureOverridden && HasStatus(Scenario->Sm, ECk_SmRunStatus::Running))
            { UCk_Utils_StateMachine_UE::Request_Stop(Scenario->Sm, {}); }
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this, FCk_NetAutoTest_Condition::CreateLambda([Scenario]()
        {
            UCk_Utils_StateMachineDebug_UE::NotifyDebugDataConsumed();
            return NOT Scenario->CaptureOverridden
                || (HasStatus(Scenario->Sm, ECk_SmRunStatus::Stopped) && RequestCount(Scenario->Sm) == 0
                    && UCk_Utils_StateMachine_UE::Get_CurrentStateClass(Scenario->Sm) == nullptr
                    && ck::Is_NOT_Valid(UCk_Utils_StateMachine_UE::Get_CurrentStateHandle(Scenario->Sm)));
        }), 10.0, TEXT("history run stopped before existing fail-closed and lifetime checks")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, Scenario](UWorld*)
        {
            Scenario->RestoreCapture();
            TestEqual(TEXT("all four production routed actions completed"), Scenario->ActionsCompleted, 4);
            if (NOT Scenario->UiReady || NOT ck::IsValid(Scenario->Sm)) { return; }
            auto& Slate = FSlateApplication::Get();
            const auto Start = FindButton(Scenario->Authored->Get_View()->GetRegion(TEXT("main")), TEXT("sm-start"));
            if (NOT TestTrue(TEXT("current Start route is retained for fail-closed checks"), Start.IsValid())) { return; }
            const auto Before = RequestCount(Scenario->Sm);

            // Remove only a request prerequisite, restore it in this callback before any world tick.
            // Current remains inspectable, so this tests live admission rather than widget destruction.
            const auto SavedParams = Scenario->Sm.Get<ck::FFragment_Sm_Params>();
            Scenario->Sm.Try_Remove<ck::FFragment_Sm_Params>();
            TestTrue(TEXT("composition loss closes action admission with an explicit reason"),
                Scenario->Authored->Get_IsAvailable() && NOT Scenario->Authored->Get_CanRequest()
                    && NOT Scenario->Authored->Get_RequestDisabledReason().IsEmpty());
            const auto MissingParamsClick = ClickDetailed(Slate, Start.ToSharedRef());
            TestTrue(TEXT("held production action cannot enqueue against missing composition"),
                NOT MissingParamsClick.Succeeded() && RequestCount(Scenario->Sm) == Before);
            Scenario->Sm.Add<ck::FFragment_Sm_Params>(SavedParams);
            TestTrue(TEXT("restored composition reopens the same route without mutating run status"),
                Scenario->Authored->Get_CanRequest() && HasStatus(Scenario->Sm, ECk_SmRunStatus::Stopped));

            auto DestructorInspector = MakeUnique<FCkInspector_StateMachine>();
            const auto DestructorView = BuildAuthored(*this, *DestructorInspector, Scenario->Sm);
            if (DestructorView.IsValid())
            {
                const TWeakPtr<FCkUiView> WeakView = DestructorView->Get_View();
                const auto Held = FindButton(DestructorView->Get_View()->GetRegion(TEXT("main")), TEXT("sm-start"));
                DestructorInspector.Reset();
                TickSlate(Slate);
                TestTrue(TEXT("destructor makes authored widget inert"), DestructorView->Is_Inert());
                TestFalse(TEXT("destructor clears authored widget view"), DestructorView->Get_View().IsValid());
                TestFalse(TEXT("destructor releases weak view ownership"), WeakView.IsValid());
                TestTrue(TEXT("destructor diagnostic retains detached button pointer"), Held.IsValid());
                TestEqual(TEXT("destructor does not enqueue a request"), RequestCount(Scenario->Sm), Before);
            }

            const TWeakPtr<FCkUiView> MainView = Scenario->Authored->Get_View();
            const TWeakPtr<FCkUiView> SecondView = Scenario->SecondAuthored->Get_View();
            Scenario->Inspector->OnDeactivated();
            const auto DeactivatedClick = ClickDetailed(Slate, Start.ToSharedRef());
            TestTrue(TEXT("deactivation makes primary authored widget inert"), Scenario->Authored->Is_Inert());
            TestTrue(TEXT("deactivation makes independent authored widget inert"), Scenario->SecondAuthored->Is_Inert());
            TestFalse(TEXT("deactivation releases primary view ownership"), MainView.IsValid());
            TestFalse(TEXT("deactivation releases independent view ownership"), SecondView.IsValid());
            TestFalse(TEXT("deactivated held action is no longer physically routable"), DeactivatedClick.Succeeded());
            TestEqual(TEXT("deactivated held action cannot enqueue"), RequestCount(Scenario->Sm), Before);

            Scenario->Authored = BuildAuthored(*this, *Scenario->Inspector, Scenario->Sm);
            if (NOT Scenario->Authored.IsValid()) { return; }
            Scenario->Window->SetContent(Scenario->Authored.ToSharedRef());
            TickSlate(Slate);
            const auto PendingStart = FindButton(Scenario->Authored->Get_View()->GetRegion(TEXT("main")), TEXT("sm-start"));
            if (NOT TestTrue(TEXT("fresh live route exists before lifetime rejection"), PendingStart.IsValid())) { return; }
            const TWeakPtr<FCkUiView> PendingView = Scenario->Authored->Get_View();
            UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(Scenario->Owner);
            TestTrue(TEXT("pending destruction closes inspection and request admission immediately"),
                Scenario->Owner.Has<ck::FTag_DestroyEntity_Initiate>() && NOT Scenario->Inspector->CanInspect(Scenario->Sm)
                    && NOT Scenario->Authored->Get_IsAvailable() && NOT Scenario->Authored->Get_CanRequest());
            const auto PendingClick = ClickDetailed(Slate, PendingStart.ToSharedRef());
            Scenario->Inspector->Tick(Scenario->Sm, 0.0f);
            TestTrue(TEXT("pending-destruction held route cannot enqueue and releases all authored state"),
                NOT PendingClick.Succeeded() && RequestCount(Scenario->Sm) == Before
                    && Scenario->Authored->Is_Inert() && NOT PendingView.IsValid());
        })));

    // Unconditional fixture cleanup also runs after an earlier assertion/route failure. Release all
    // registry-backed handles and mounted views before the PIE world's registry is torn down.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, Scenario](UWorld*)
        {
            if (Scenario->Inspector.IsValid()) { Scenario->Inspector->OnDeactivated(); }
            if (Scenario->Window.IsValid())
            {
                Scenario->Window->SetContent(SNullWidget::NullWidget);
                FSlateApplication::Get().DestroyWindowImmediately(Scenario->Window.ToSharedRef());
            }
            Scenario->Window.Reset();
            Scenario->Authored.Reset();
            Scenario->SecondAuthored.Reset();
            Scenario->Inspector.Reset();
            if (ck::IsValid(Scenario->Owner) && NOT Scenario->Owner.Has<ck::FTag_DestroyEntity_Initiate>())
            { UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(Scenario->Owner); }
            Scenario->EnteredState = {};
            Scenario->Sm = {};
            Scenario->Owner = {};
            Scenario->RestoreCapture();
            Scenario->RestoreStyle();
            Scenario->ReleasedBeforeEndPIE = TestTrue(TEXT("fixture released all views, window, and entity handles before EndPIE"),
                NOT Scenario->Window.IsValid() && NOT Scenario->Authored.IsValid() && NOT Scenario->SecondAuthored.IsValid()
                    && ck::Is_NOT_Valid(Scenario->Owner) && ck::Is_NOT_Valid(Scenario->Sm)
                    && NOT Scenario->StyleOverridden && NOT Scenario->CaptureOverridden);
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this, FCk_NetAutoTest_Assertion::CreateLambda([Scenario]()
        {
            return Scenario->ReleasedBeforeEndPIE && ck::auto_test::net::Get_AllPIEWorlds().IsEmpty()
                && NOT Scenario->StyleOverridden && NOT Scenario->CaptureOverridden && NOT Scenario->Window.IsValid();
        }), TEXT("EndPIE completed after StateMachine fixture-owned UI and handle cleanup")));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_StateMachine_AuthoredInspectorVariants,
    "Ck.UiAuthoring.EcsDebugger.StateMachineInspector.AuthoredVariants", ck_tests_state_machine_authored::kFlags | EAutomationTestFlags::NonNullRHI)

bool FCkTest_StateMachine_AuthoredInspectorVariants::RunTest(const FString& Parameters)
{
    using namespace ck_tests_state_machine_authored;
    if (NOT FSlateApplication::IsInitialized() || NOT FApp::CanEverRender())
    {
        AddError(TEXT("StateMachine authored variant proof requires initialized Slate and real RHI (--no-nullrhi)."));
        return false;
    }

    // The multi-client harness has a documented, pre-existing Iris startup incompatibility. Unreal
    // forwards its one handled ensure as separate header, blank, condition, message, stack and volatile
    // callstack records. Allow only that finite record shape: another ensure's header/condition/message
    // remains an unexpected error, while an extra blank record also breaks the exact blank count.
    AddExpectedErrorPlain(TEXT("LogOutputDevice: === Handled ensure: ==="),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/1);
    AddExpectedErrorPlain(TEXT("LogOutputDevice: "),
        EAutomationExpectedErrorFlags::Exact, /*Occurrences=*/2);
    AddExpectedErrorPlain(TEXT("LogOutputDevice: Ensure condition failed: false"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/1);
    AddExpectedErrorPlain(TEXT("LogOutputDevice: Disallowed to write first packet in batch, with Iris this is not good!"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/1);
    AddExpectedErrorPlain(TEXT("LogOutputDevice: Stack:"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/1);
    AddExpectedErrorPlain(TEXT("LogOutputDevice: [Callstack]"),
        EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/0);

    const auto Scenario = MakeShared<FVariantScenario>();
    Scenario->HierarchyClass = LoadAsStateClass(TEXT("/Script/Angelscript.Ck_SmTest_Hier_Parent_Engage"));
    Scenario->CascadeClass = LoadAsStateClass(TEXT("/Script/Angelscript.Ck_SmTest_GraphWalk_SubSmWrapper_State"));
    Scenario->OverrideBaseClass = LoadAsStateClass(TEXT("/Script/Angelscript.Ck_SmTest_Override_Base"));
    Scenario->OverrideReplacementClass = LoadAsStateClass(TEXT("/Script/Angelscript.Ck_SmTest_Override_Replacement"));
    if (Scenario->HierarchyClass == nullptr || Scenario->CascadeClass == nullptr || Scenario->OverrideBaseClass == nullptr
        || Scenario->OverrideReplacementClass == nullptr)
    {
        AddError(FString::Printf(TEXT("StateMachine authored AS fixtures unresolved (hierarchy=%p cascade=%p base=%p replacement=%p)."),
            Scenario->HierarchyClass.Get(), Scenario->CascadeClass.Get(), Scenario->OverrideBaseClass.Get(),
            Scenario->OverrideReplacementClass.Get()));
        return false;
    }

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(2, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(2, 30.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, Scenario](UWorld* InWorld)
        {
            auto DefaultInspector = FCkInspector_StateMachine{};
            TestFalse(TEXT("default handle is not inspectable"), DefaultInspector.CanInspect(FCk_Handle{}));

            auto InvalidOwner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InWorld, {});
            if (TestTrue(TEXT("invalid-initial-class owner created"), ck::IsValid(InvalidOwner)))
            {
                // One CK ensure may be observed through both the direct-log and editor-message routes.
                AddExpectedErrorPlain(TEXT("Invalid initial state class when creating StateMachine"),
                    EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/0);
                const auto InvalidSm = UCk_Utils_StateMachine_UE::Add(
                    InvalidOwner, FCk_Fragment_StateMachine_ParamsData{});
                TestTrue(TEXT("invalid initial class fails closed without publishing partial StateMachine state"),
                    ck::Is_NOT_Valid(InvalidSm) && NOT InvalidOwner.Has<ck::FFragment_Sm_Params>()
                        && NOT InvalidOwner.Has<ck::FFragment_Sm_Current>()
                        && NOT InvalidOwner.Has<ck::FTag_Sm_RequiresSetup>());
                UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(InvalidOwner);
            }

            Scenario->PreviousStyle = UCkDebuggerStyleSettings::Get_Selection().EditControlStyle;
            Scenario->StyleOverridden = true;
            UCkDebuggerStyleSettings::Get_Mutable()->Selection.EditControlStyle = ECkDebugAxis_EditControlStyle::Hidden;
            Scenario->Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InWorld, {});
            auto Params = FCk_Fragment_StateMachine_ParamsData{Scenario->HierarchyClass};
            Params.Set_AutoStart(ECk_SmAutoStart::Disabled);
            Scenario->Sm = UCk_Utils_StateMachine_UE::Add(Scenario->Owner, Params);
            Scenario->ServerReady = TestTrue(TEXT("hierarchical authored-variant StateMachine composed"),
                ck::IsValid(Scenario->Owner) && ck::IsValid(Scenario->Sm));
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this, FCk_NetAutoTest_Condition::CreateLambda([Scenario]()
        {
            return NOT Scenario->ServerReady || (HasStatus(Scenario->Sm, ECk_SmRunStatus::Stopped)
                && NOT Scenario->Sm.Has<ck::FTag_Sm_RequiresSetup>() && RequestCount(Scenario->Sm) == 0);
        }), 10.0, TEXT("hierarchical StateMachine setup settled")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, Scenario](UWorld* InWorld)
        {
            if (NOT Scenario->ServerReady) { return; }
            auto HiddenInspector = MakeUnique<FCkInspector_StateMachine>();
            const auto Hidden = BuildAuthored(*this, *HiddenInspector, Scenario->Sm);
            if (Hidden.IsValid())
            {
                const auto Root = Hidden->Get_View()->GetRegion(TEXT("main"));
                TestTrue(TEXT("Hidden style omits the StateMachine control row and action widgets"),
                    NOT Hidden->Get_Bool(TEXT("controls-visible"))
                        && NOT FindButton(Root, TEXT("sm-start")).IsValid()
                        && NOT FindButton(Root, TEXT("sm-stop")).IsValid());
                Hidden->Release();
            }
            HiddenInspector->OnDeactivated();

            UCkDebuggerStyleSettings::Get_Mutable()->Selection.EditControlStyle = ECkDebugAxis_EditControlStyle::OnHover;
            Scenario->Inspector = MakeUnique<FCkInspector_StateMachine>();
            Scenario->Authored = BuildAuthored(*this, *Scenario->Inspector, Scenario->Sm);
            if (NOT Scenario->Authored.IsValid()) { Scenario->ServerReady = false; return; }
            const auto Start = FindButton(Scenario->Authored->Get_View()->GetRegion(TEXT("main")), TEXT("sm-start"));
            if (NOT TestTrue(TEXT("OnHover style retains the Start action"),
                Scenario->Authored->Get_Bool(TEXT("controls-visible")) && Start.IsValid()))
            { Scenario->ServerReady = false; return; }
            auto& Slate = FSlateApplication::Get();
            Scenario->PreviousCursor = Slate.GetCursorPos();
            Scenario->CursorCaptured = true;
            Scenario->Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{760.0f, 640.0f})
                .CreateTitleBar(false).HasCloseButton(false)[Scenario->Authored.ToSharedRef()];
            Slate.AddWindow(Scenario->Window.ToSharedRef(), true);
            TickSlate(Slate);
            Scenario->Authored->SlatePrepass(1.0f);
            const auto AwayPosition = Scenario->Window->GetCachedGeometry().LocalToAbsolute(
                Scenario->Window->GetCachedGeometry().GetLocalSize() - FVector2D{4.0f, 4.0f});
            const TSet<FKey> NoButtons;
            Slate.SetCursorPos(AwayPosition);
            Slate.ProcessMouseMoveEvent(FPointerEvent(0, FSlateApplication::CursorPointerIndex,
                AwayPosition, AwayPosition, NoButtons, EKeys::Invalid, 0.0f, FModifierKeysState{}), true);
            TickSlate(Slate);
            if (NOT TestEqual(TEXT("OnHover Start is hidden at a controlled non-hover location"),
                Start->GetVisibility(), EVisibility::Hidden))
            { Scenario->ServerReady = false; return; }
            Scenario->InitialDoExitCount = EventCount(InWorld, Scenario->HierarchyClass,
                ECk_AutoTest_Sm_EventKind::DoExitState);
            if (NOT TestTrue(TEXT("physical pointer hover reveals the OnHover Start action"),
                HoverInspectorAction(Slate, Start.ToSharedRef())))
            { Scenario->ServerReady = false; return; }
            const auto Click = ClickDetailed(Slate, Start.ToSharedRef());
            Scenario->ServerReady = TestTrue(*FString::Printf(TEXT("OnHover Start uses physical hover and routed click: %s"),
                *Click.Describe()), Click.Succeeded());
            Scenario->ServerReady = TestEqual(TEXT("OnHover Start enqueues exactly one request"),
                RequestCount(Scenario->Sm), 1) && Scenario->ServerReady;
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this, FCk_NetAutoTest_Condition::CreateLambda([Scenario]()
        {
            if (NOT Scenario->ServerReady) { return true; }
            Scenario->TopologyReady = ResolveVariantTopology(*Scenario);
            return Scenario->TopologyReady;
        }), 10.0, TEXT("hierarchical task/transition/condition/Sub-SM topology materialized")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [Scenario](UWorld*)
        {
            if (Scenario->TopologyReady)
            { UCk_Utils_StateMachine_UE::Request_Pause(Scenario->Sm, {}); }
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this, FCk_NetAutoTest_Condition::CreateLambda([Scenario]()
        {
            return NOT Scenario->TopologyReady
                || (HasStatus(Scenario->Sm, ECk_SmRunStatus::Paused) && RequestCount(Scenario->Sm) == 0);
        }), 10.0, TEXT("hierarchical fixture paused before projection checks")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, Scenario](UWorld* InWorld)
        {
            Scenario->TopologyReady = ResolveVariantTopology(*Scenario);
            if (NOT Scenario->TopologyReady) { return; }
            auto CheckInspector = MakeUnique<FCkInspector_StateMachine>();
            const auto StateView = BuildAuthored(*this, *CheckInspector, Scenario->State);
            if (StateView.IsValid())
            {
                const auto Rows = CaptureRows(*CheckInspector, Scenario->State);
                TestTrue(TEXT("state hierarchy variant equals native class and hierarchy rows"),
                    StateView->Get_Bool(TEXT("state")) && StateView->Get_Bool(TEXT("state-hierarchy"))
                        && Rows.Contains(TEXT("Class:")) && Rows.Contains(TEXT("Hierarchy:"))
                        && StateView->Get_Text(TEXT("state-class")) == Rows.FindRef(TEXT("Class:"))
                        && StateView->Get_Text(TEXT("state-hierarchy")) == Rows.FindRef(TEXT("Hierarchy:")));
                StateView->Release();
            }

            const auto TaskView = BuildAuthored(*this, *CheckInspector, Scenario->Task);
            if (TaskView.IsValid())
            {
                const auto Rows = CaptureRows(*CheckInspector, Scenario->Task);
                TestTrue(TEXT("task and Sub-SM variants equal native capture"),
                    TaskView->Get_Bool(TEXT("task")) && TaskView->Get_Bool(TEXT("task-class"))
                        && TaskView->Get_Bool(TEXT("task-result")) && TaskView->Get_Bool(TEXT("sub-sm"))
                        && TaskView->Get_Text(TEXT("task-class")) == Rows.FindRef(TEXT("Class:"))
                        && TaskView->Get_Text(TEXT("task-result")) == Rows.FindRef(TEXT("Result:"))
                        && TaskView->Get_Text(TEXT("sub-sm-id")) == Rows.FindRef(TEXT("Sub SM:")));

                Scenario->Window->SetContent(TaskView.ToSharedRef());
                TickSlate(FSlateApplication::Get());
                TaskView->SlatePrepass(1.0f);
                const auto EntityRef = FindType(TaskView->Get_View()->GetRegion(TEXT("main")), TEXT("SCkDebug_EntityRef"));
                if (TestTrue(TEXT("Sub-SM authored variant materializes the real entity reference"), EntityRef.IsValid()))
                {
                    Scenario->EcsDebuggerWasOpen = FGlobalTabmanager::Get()->FindExistingLiveTab(
                        FTabId{TEXT("CkEcsDebugger")}).IsValid();
                    const auto Press = PressDetailed(FSlateApplication::Get(), EntityRef.ToSharedRef());
                    TestTrue(*FString::Printf(TEXT("Sub-SM entity reference uses physical mouse-down: %s"),
                        *Press.Describe()), Press.Succeeded());
                    TestTrue(TEXT("physical Sub-SM navigation selects the exact child StateMachine in ECS debugger"),
                        ck::DebugSelectionSync::Get_PrimaryEcsSelection() == FCk_Handle{Scenario->SubSm});
                }
                Scenario->Window->SetContent(Scenario->Authored.ToSharedRef());
                TickSlate(FSlateApplication::Get());
                TaskView->Release();
            }

            const auto TransitionView = BuildAuthored(*this, *CheckInspector, Scenario->Transition);
            if (TransitionView.IsValid())
            {
                const auto Rows = CaptureRows(*CheckInspector, Scenario->Transition);
                TestTrue(TEXT("transition target/result variants equal native capture"),
                    TransitionView->Get_Bool(TEXT("transition"))
                        && TransitionView->Get_Bool(TEXT("transition-target"))
                        && TransitionView->Get_Bool(TEXT("transition-result"))
                        && TransitionView->Get_Text(TEXT("transition-target")) == Rows.FindRef(TEXT("Target:"))
                        && TransitionView->Get_Text(TEXT("transition-result")) == Rows.FindRef(TEXT("Result:")));
                TransitionView->Release();
            }

            const auto ConditionView = BuildAuthored(*this, *CheckInspector, Scenario->Condition);
            if (ConditionView.IsValid())
            {
                const auto Rows = CaptureRows(*CheckInspector, Scenario->Condition);
                TestTrue(TEXT("condition class/result variants equal native capture"),
                    ConditionView->Get_Bool(TEXT("condition"))
                        && ConditionView->Get_Bool(TEXT("condition-class"))
                        && ConditionView->Get_Bool(TEXT("condition-result"))
                        && ConditionView->Get_Text(TEXT("condition-class")) == Rows.FindRef(TEXT("Class:"))
                        && ConditionView->Get_Text(TEXT("condition-result")) == Rows.FindRef(TEXT("Result:")));
                ConditionView->Release();
            }

            const auto SubStateView = BuildAuthored(*this, *CheckInspector, Scenario->SubState);
            if (SubStateView.IsValid())
            {
                const auto Rows = CaptureRows(*CheckInspector, Scenario->SubState);
                const auto& Hierarchy = Scenario->SubState.Get<ck::FFragment_SmState_Hierarchy>().Get_Hierarchy();
                TestTrue(TEXT("nested Sub-SM state projects its multi-level hierarchy exactly"),
                    Hierarchy.Num() >= 2 && SubStateView->Get_Bool(TEXT("state-hierarchy"))
                        && SubStateView->Get_Text(TEXT("state-hierarchy")) == Rows.FindRef(TEXT("Hierarchy:")));
                SubStateView->Release();
            }
            CheckInspector->OnDeactivated();
            if (const auto Tab = FGlobalTabmanager::Get()->FindExistingLiveTab(FTabId{TEXT("CkEcsDebugger")});
                Tab.IsValid() && NOT Scenario->EcsDebuggerWasOpen)
            { Tab->RequestCloseTab(); }
            TickSlate(FSlateApplication::Get());
            Scenario->VariantsAccepted = true;

            auto OverrideParams = FCk_Fragment_StateMachine_ParamsData{Scenario->OverrideBaseClass};
            OverrideParams.Set_AutoStart(ECk_SmAutoStart::Disabled);
            Scenario->OverrideOwner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InWorld, {});
            Scenario->OverrideSm = UCk_Utils_StateMachine_UE::Add(Scenario->OverrideOwner, OverrideParams);
            if (TestTrue(TEXT("requested-class override fixture composed"), ck::IsValid(Scenario->OverrideSm)))
            { UCk_Utils_StateMachine_UE::Request_AddOverrideState(Scenario->OverrideSm, Scenario->OverrideReplacementClass, {}); }
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this, FCk_NetAutoTest_Condition::CreateLambda([Scenario]()
        {
            return ck::Is_NOT_Valid(Scenario->OverrideSm)
                || (HasStatus(Scenario->OverrideSm, ECk_SmRunStatus::Stopped)
                    && NOT Scenario->OverrideSm.Has<ck::FTag_Sm_RequiresSetup>() && RequestCount(Scenario->OverrideSm) == 0);
        }), 10.0, TEXT("state override request admitted before start")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [Scenario](UWorld*)
        {
            if (ck::IsValid(Scenario->OverrideSm))
            { UCk_Utils_StateMachine_UE::Request_Start(Scenario->OverrideSm, {}); }
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this, FCk_NetAutoTest_Condition::CreateLambda([Scenario]()
        {
            return ck::Is_NOT_Valid(Scenario->OverrideSm)
                || (HasStatus(Scenario->OverrideSm, ECk_SmRunStatus::Running)
                    && UCk_Utils_StateMachine_UE::Get_CurrentStateClass(Scenario->OverrideSm)
                        == Scenario->OverrideReplacementClass
                    && RequestCount(Scenario->OverrideSm) == 0);
        }), 10.0, TEXT("requested state resolved through production override")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, Scenario](UWorld*)
        {
            if (ck::Is_NOT_Valid(Scenario->OverrideSm)) { return; }
            const auto OverrideState = UCk_Utils_StateMachine_UE::Get_CurrentStateHandle(Scenario->OverrideSm);
            auto OverrideInspector = MakeUnique<FCkInspector_StateMachine>();
            const auto OverrideView = BuildAuthored(*this, *OverrideInspector, OverrideState);
            if (OverrideView.IsValid())
            {
                const auto Rows = CaptureRows(*OverrideInspector, OverrideState);
                Scenario->OverrideAccepted = TestTrue(TEXT("requested-class variant exposes requested and resolved classes with native parity"),
                    OverrideView->Get_Bool(TEXT("state-requested")) && Rows.Contains(TEXT("Requested:"))
                        && OverrideView->Get_Text(TEXT("state-requested")) == Rows.FindRef(TEXT("Requested:"))
                        && OverrideView->Get_Text(TEXT("state-class")) == Rows.FindRef(TEXT("Class:")));
                OverrideView->Release();
            }
            OverrideInspector->OnDeactivated();
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(0, FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, Scenario](UWorld* InWorld)
        {
            UCkDebuggerStyleSettings::Get_Mutable()->Selection.EditControlStyle = ECkDebugAxis_EditControlStyle::Inline;
            Scenario->ClientOwner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InWorld, {});
            auto Params = FCk_Fragment_StateMachine_ParamsData{Scenario->HierarchyClass};
            Params.Set_AutoStart(ECk_SmAutoStart::Disabled);
            Scenario->ClientSm = UCk_Utils_StateMachine_UE::Add(Scenario->ClientOwner, Params);
            auto ClientInspector = MakeUnique<FCkInspector_StateMachine>();
            const auto ClientView = BuildAuthored(*this, *ClientInspector, Scenario->ClientSm);
            if (ClientView.IsValid())
            {
                auto& Slate = FSlateApplication::Get();
                const auto ClientWindow = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{520.0f, 320.0f})
                    .CreateTitleBar(false).HasCloseButton(false)[ClientView.ToSharedRef()];
                Slate.AddWindow(ClientWindow, true);
                TickSlate(Slate);
                const auto Start = FindButton(ClientView->Get_View()->GetRegion(TEXT("main")), TEXT("sm-start"));
                const auto Before = RequestCount(Scenario->ClientSm);
                auto Click = FPhysicalClickResult{};
                if (TestTrue(TEXT("client refusal fixture exposes the production Start action"), Start.IsValid()))
                { Click = ClickDetailed(Slate, Start.ToSharedRef()); }
                Scenario->ClientRefusalAccepted = TestTrue(TEXT("client-world authority refusal disables physical dispatch with a reason"),
                    NOT ClientView->Get_CanRequest() && NOT ClientView->Get_RequestDisabledReason().IsEmpty()
                        && NOT Click.Succeeded() && NOT Click.Enabled && RequestCount(Scenario->ClientSm) == Before
                        && HasStatus(Scenario->ClientSm, ECk_SmRunStatus::Stopped));
                ClientWindow->SetContent(SNullWidget::NullWidget);
                Slate.DestroyWindowImmediately(ClientWindow);
                ClientView->Release();
            }
            ClientInspector->OnDeactivated();
            if (ck::IsValid(Scenario->ClientOwner))
            { UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(Scenario->ClientOwner); }
            Scenario->ClientSm = {};
            Scenario->ClientOwner = {};
            UCkDebuggerStyleSettings::Get_Mutable()->Selection.EditControlStyle =
                ECkDebugAxis_EditControlStyle::OnHover;
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, Scenario](UWorld*)
        {
            if (NOT Scenario->VariantsAccepted || NOT Scenario->Authored.IsValid()) { return; }
            Scenario->Window->SetContent(Scenario->Authored.ToSharedRef());
            TickSlate(FSlateApplication::Get());
            const auto Stop = FindButton(Scenario->Authored->Get_View()->GetRegion(TEXT("main")), TEXT("sm-stop"));
            if (NOT TestTrue(TEXT("OnHover Stop remains available while paused"), Stop.IsValid())) { return; }
            if (NOT TestTrue(TEXT("physical pointer hover reveals the OnHover Stop action"),
                HoverInspectorAction(FSlateApplication::Get(), Stop.ToSharedRef())))
            { return; }
            const auto Click = ClickDetailed(FSlateApplication::Get(), Stop.ToSharedRef());
            TestTrue(*FString::Printf(TEXT("OnHover Stop uses physical hover and routed click: %s"),
                *Click.Describe()), Click.Succeeded());
            TestEqual(TEXT("OnHover Stop enqueues exactly one request"), RequestCount(Scenario->Sm), 1);
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this, FCk_NetAutoTest_Condition::CreateLambda([Scenario]()
        {
            auto* World = ck::auto_test::net::Get_ServerWorld();
            return NOT Scenario->VariantsAccepted || (HasStatus(Scenario->Sm, ECk_SmRunStatus::Stopped)
                && RequestCount(Scenario->Sm) == 0
                && EventCount(World, Scenario->HierarchyClass, ECk_AutoTest_Sm_EventKind::DoExitState)
                    == Scenario->InitialDoExitCount + 1);
        }), 10.0, TEXT("physical Stop invoked the authored DoExitState event once")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, Scenario](UWorld* InWorld)
        {
            Scenario->StopAccepted = TestEqual(TEXT("physical Stop invokes DoExitState exactly once"),
                EventCount(InWorld, Scenario->HierarchyClass, ECk_AutoTest_Sm_EventKind::DoExitState),
                Scenario->InitialDoExitCount + 1);
            if (Scenario->Inspector.IsValid()) { Scenario->Inspector->OnDeactivated(); }
            if (Scenario->Window.IsValid())
            {
                Scenario->Window->SetContent(SNullWidget::NullWidget);
                FSlateApplication::Get().DestroyWindowImmediately(Scenario->Window.ToSharedRef());
            }
            Scenario->Window.Reset();
            Scenario->Authored.Reset();
            Scenario->Inspector.Reset();
            Scenario->RestoreCursor();
            Scenario->StaleSm = Scenario->Sm;
            Scenario->CascadeInitialDoExitCount = EventCount(InWorld, Scenario->CascadeClass,
                ECk_AutoTest_Sm_EventKind::DoExitState);
            Scenario->CascadeOwner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InWorld, {});
            Scenario->CascadeSm = UCk_Utils_StateMachine_UE::Add(Scenario->CascadeOwner,
                FCk_Fragment_StateMachine_ParamsData{Scenario->CascadeClass});
            Scenario->CascadeCreated = TestTrue(TEXT("active-destruction StateMachine composed"),
                ck::IsValid(Scenario->CascadeOwner) && ck::IsValid(Scenario->CascadeSm));
            if (ck::IsValid(Scenario->OverrideOwner))
            { UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(Scenario->OverrideOwner); }
            if (ck::IsValid(Scenario->Owner))
            { UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(Scenario->Owner); }
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this, FCk_NetAutoTest_Condition::CreateLambda([Scenario]()
        {
            return NOT Scenario->CascadeCreated || (ck::Is_NOT_Valid(Scenario->StaleSm)
                && ck::Is_NOT_Valid(Scenario->OverrideSm)
                && HasStatus(Scenario->CascadeSm, ECk_SmRunStatus::Running)
                && ck::IsValid(UCk_Utils_StateMachine_UE::Get_CurrentStateHandle(Scenario->CascadeSm)));
        }), 10.0, TEXT("stopped owners tore down and active-destruction StateMachine started")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, Scenario](UWorld*)
        {
            if (NOT Scenario->CascadeCreated) { return; }
            const auto ActiveState = UCk_Utils_StateMachine_UE::Get_CurrentStateHandle(Scenario->CascadeSm);
            if (TestTrue(TEXT("direct owner destruction begins with a genuinely active state"),
                ck::IsValid(ActiveState) && ActiveState.Has<ck::FTag_SmState_Active>()))
            { UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(Scenario->CascadeOwner); }
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this, FCk_NetAutoTest_Condition::CreateLambda([Scenario]()
        {
            auto* World = ck::auto_test::net::Get_ServerWorld();
            return NOT Scenario->CascadeCreated || (ck::Is_NOT_Valid(Scenario->CascadeSm)
                && EventCount(World, Scenario->CascadeClass, ECk_AutoTest_Sm_EventKind::DoExitState)
                    == Scenario->CascadeInitialDoExitCount + 1);
        }), 10.0, TEXT("active owner destruction invoked DoExitState once")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(2));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, Scenario](UWorld* InWorld)
        {
            auto StaleInspector = FCkInspector_StateMachine{};
            Scenario->StaleAccepted = TestTrue(TEXT("stale StateMachine handle is rejected after physical teardown"),
                ck::Is_NOT_Valid(Scenario->StaleSm) && NOT StaleInspector.CanInspect(Scenario->StaleSm));
            Scenario->StaleAccepted = TestEqual(TEXT("owner teardown does not invoke DoExitState a second time"),
                EventCount(InWorld, Scenario->HierarchyClass, ECk_AutoTest_Sm_EventKind::DoExitState),
                Scenario->InitialDoExitCount + 1) && Scenario->StaleAccepted;
            Scenario->CascadeAccepted = TestEqual(TEXT("active owner teardown invokes DoExitState exactly once"),
                EventCount(InWorld, Scenario->CascadeClass, ECk_AutoTest_Sm_EventKind::DoExitState),
                Scenario->CascadeInitialDoExitCount + 1);

            Scenario->RestoreStyle();
            Scenario->State = {};
            Scenario->Task = {};
            Scenario->Transition = {};
            Scenario->Condition = {};
            Scenario->SubState = {};
            Scenario->SubSm = {};
            Scenario->Sm = {};
            Scenario->Owner = {};
            Scenario->OverrideSm = {};
            Scenario->OverrideOwner = {};
            Scenario->CascadeSm = {};
            Scenario->CascadeOwner = {};
            Scenario->StaleSm = {};
            Scenario->ReleasedBeforeEndPIE = TestTrue(TEXT("variant fixture releases UI and handles before EndPIE"),
                Scenario->VariantsAccepted && Scenario->OverrideAccepted && Scenario->ClientRefusalAccepted
                    && Scenario->StopAccepted && Scenario->CascadeAccepted && Scenario->StaleAccepted
                    && NOT Scenario->StyleOverridden
                    && NOT Scenario->Window.IsValid() && NOT Scenario->Authored.IsValid()
                    && NOT Scenario->Inspector.IsValid());
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this, FCk_NetAutoTest_Assertion::CreateLambda([Scenario]()
        {
            return Scenario->ReleasedBeforeEndPIE && ck::auto_test::net::Get_AllPIEWorlds().IsEmpty()
                && NOT Scenario->StyleOverridden && NOT Scenario->Window.IsValid();
        }), TEXT("EndPIE completed after StateMachine variant acceptance teardown")));
    return true;
}

#endif
