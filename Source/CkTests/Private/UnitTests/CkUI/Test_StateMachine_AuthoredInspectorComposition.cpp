#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkCore/Validation/CkIsValid.h"
#include "CkDebuggerCommon/Settings/CkDebuggerStyleSettings.h"
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
#include "CkTests/Net/CkAutoTest_Sm_Recorder.h"
#include "CkTests/Net/CkAutoTest_Sm_RecordingState.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include "Engine/World.h"
#include "Framework/Application/SlateApplication.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "Interfaces/IPluginManager.h"
#include "Layout/WidgetPath.h"
#include "Misc/App.h"
#include "Misc/AutomationTest.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
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
        for (const auto& Entry : InHistory)
        {
            Timeline->Set_View(Entry.RealTimeSeconds - MinGap * 0.25, MinGap * 0.5);
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
                    if (NOT Text.IsEmpty()) { Hovered.AddUnique(Text); }
                }
            }
            // More than one marker in an isolated window is also a content mismatch.
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
        bool Targeted = false;
        bool DownHandled = false;
        bool Captured = false;
        bool TargetedBeforeUp = false;
        bool UpHandled = false;

        auto Succeeded() const -> bool
        { return NativeWindow && Enabled && Arranged && Targeted && DownHandled && Captured && TargetedBeforeUp && UpHandled; }

        auto Describe() const -> FString
        {
            return FString::Printf(TEXT("native=%d enabled=%d arranged=%d hit=%d down=%d capture=%d up-hit=%d up=%d"),
                NativeWindow, Enabled, Arranged, Targeted, DownHandled, Captured, TargetedBeforeUp, UpHandled);
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
        Result.Targeted = ContainsWidget(InSlate.LocateWindowUnderMouse(
            Position, InSlate.GetInteractiveTopLevelWindows(), false, 0), InButton);
        if (NOT Result.Targeted) { return Result; }
        Result.DownHandled = InSlate.ProcessMouseButtonDownEvent(Window->GetNativeWindow(), DownEvent);
        Result.Captured = InButton->HasMouseCapture();
        Result.TargetedBeforeUp = ContainsWidget(InSlate.LocateWindowUnderMouse(
            Position, InSlate.GetInteractiveTopLevelWindows(), false, 0), InButton);
        Result.UpHandled = InSlate.ProcessMouseButtonUpEvent(UpEvent);
        TickSlate(InSlate);
        return Result;
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
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_StateMachine_AuthoredInspectorComposition,
    "Ck.UiAuthoring.EcsDebugger.StateMachineInspector.AuthoredComposition", ck_tests_state_machine_authored::kFlags)

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

#endif
