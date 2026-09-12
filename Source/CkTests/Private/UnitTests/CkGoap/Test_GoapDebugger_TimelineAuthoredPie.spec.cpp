#include "CoreMinimal.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkGoapDebugger/Data/CkGoapDebugger_DataCollector.h"
#include "CkGoapDebugger/ViewModel/CkGoapDebugger_ViewModel.h"
#include "CkGoapDebugger/Window/SCkGoapDebugger_TimelineDock.h"

#include "CkCore/Validation/CkIsValid.h"
#include "CkSlateLayout/CkFlexText.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include "Engine/World.h"
#include "Framework/Application/SlateApplication.h"
#include "GameFramework/Actor.h"
#include "HAL/FileManager.h"
#include "ImageUtils.h"
#include "Misc/AutomationTest.h"
#include "Misc/Paths.h"
#include "UObject/UObjectIterator.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/Layout/SScrollBox.h"
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"

namespace ck_tests_goap_debugger_timeline_authored_pie
{
    constexpr auto TestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;
    const FName FixtureClassName{TEXT("Ck_Goap_Planner_SquadRosterPieFixture")};
    const FName FixturePulseFunctionName{TEXT("RequestReplanPulse")};

    struct FState final
    {
        TWeakObjectPtr<AActor> Fixture;
        TSharedPtr<FCkGoapDebugger_ViewModel> ViewModel;
        TSharedPtr<SCkGoapDebugger_TimelineDock> Dock;
        TSharedPtr<SWindow> Window;
        TWeakPtr<SCkGoapDebugger_TimelineDock> WeakDock;
        TWeakPtr<FCkUiView> WeakView;
        TWeakPtr<SWidget> WeakTimelineBody;
        FCk_Handle Entity;
        int32 InitialEventCount = INDEX_NONE;
        int32 PulseResult = INDEX_NONE;
        int32 ScrubEventIndex = INDEX_NONE;
        FString ClickDiagnostic;
        bool bFixtureSpawned = false;
        bool bEmptyContractReady = false;
        bool bHistoryReady = false;
        bool bPulseHistoryAdvanced = false;
        bool bMountedContractReady = false;
        bool bNativeFillsDock = false;
        bool bPhysicalScrubReady = false;
        bool bNoChangePollStable = false;
        bool bRejectedReloadRetained = false;
        bool bDeselectionRetainsShell = false;
        bool bWideCapture = false;
        bool bNarrowCapture = false;
        bool bNarrowScrollReachable = false;
        bool bResetReleased = false;
        bool bTornDown = false;
    };

    auto Tick(FSlateApplication& InSlate) -> void
    {
        InSlate.PumpMessages();
        InSlate.Tick();
        InSlate.Tick();
    }

    auto FindTagged(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTag() == InTag)
        {
            return InRoot;
        }

        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            const TSharedPtr<SWidget> Found = FindTagged(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag);
            if (Found.IsValid())
            {
                return Found;
            }
        }

        return {};
    }

    auto ContainsText(const TSharedRef<SWidget>& InRoot, const FString& InText) -> bool
    {
        if (InRoot->GetTypeAsString() == TEXT("STextBlock")
            && StaticCastSharedRef<STextBlock>(InRoot)->GetText().ToString().Contains(InText))
        {
            return true;
        }
        if (InRoot->GetTypeAsString() == TEXT("SCkFlexText")
            && StaticCastSharedRef<SCkFlexText>(InRoot)->GetText().ToString().Contains(InText))
        {
            return true;
        }

        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (ContainsText(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InText))
            {
                return true;
            }
        }

        return false;
    }

    auto FindType(const TSharedRef<SWidget>& InRoot, const FString& InType) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTypeAsString() == InType)
        {
            return InRoot;
        }

        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            const TSharedPtr<SWidget> Found = FindType(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InType);
            if (Found.IsValid())
            {
                return Found;
            }
        }

        return {};
    }

    auto FindJumpButton(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SButton>
    {
        if (InRoot->GetTypeAsString() == TEXT("SButton") && ContainsText(InRoot, TEXT("#")))
        {
            return StaticCastSharedRef<SButton>(InRoot);
        }

        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            const TSharedPtr<SButton> Found = FindJumpButton(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)));
            if (Found.IsValid())
            {
                return Found;
            }
        }

        return {};
    }

    auto WidgetPathContains(const FWidgetPath& InPath, const TSharedRef<SWidget>& InWidget) -> bool
    {
        for (int32 Index = 0; Index < InPath.Widgets.Num(); ++Index)
        {
            if (InPath.Widgets[Index].Widget == InWidget)
            {
                return true;
            }
        }
        return false;
    }

    struct FMountedClickResult final
    {
        bool bTargeted = false;
        bool bDownHandled = false;
        bool bUpHandled = false;

        auto Succeeded() const -> bool { return bTargeted && bDownHandled && bUpHandled; }
        auto Describe() const -> FString
        {
            return FString::Printf(TEXT("targeted=%d down=%d up=%d"), bTargeted, bDownHandled, bUpHandled);
        }
    };

    auto ClickMounted(FSlateApplication& InSlate, const TSharedRef<SWidget>& InWidget) -> FMountedClickResult
    {
        FMountedClickResult Result;
        const TSharedPtr<SWindow> Window = InSlate.FindWidgetWindow(InWidget);
        if (!Window.IsValid() || !Window->GetNativeWindow().IsValid())
        {
            return Result;
        }

        Window->BringToFront(true);
        Tick(InSlate);
        InSlate.ReleaseAllPointerCapture(0);
        const FGeometry Geometry = InWidget->GetCachedGeometry();
        if (Geometry.GetLocalSize().IsNearlyZero())
        {
            return Result;
        }

        const FVector2D Position = Geometry.LocalToAbsolute(Geometry.GetLocalSize() * 0.5f);
        const TSet<FKey> None;
        const TSet<FKey> DownButtons{EKeys::LeftMouseButton};
        const FPointerEvent Move(0, FSlateApplication::CursorPointerIndex, Position, Position, None, EKeys::Invalid, 0.0f, FModifierKeysState{});
        const FPointerEvent Down(0, FSlateApplication::CursorPointerIndex, Position, Position, DownButtons, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        const FPointerEvent Up(0, FSlateApplication::CursorPointerIndex, Position, Position, None, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        InSlate.SetCursorPos(Position);
        InSlate.ProcessMouseMoveEvent(Move, true);
        Result.bTargeted = WidgetPathContains(InSlate.LocateWindowUnderMouse(Position, InSlate.GetInteractiveTopLevelWindows(), false, 0), InWidget);
        if (!Result.bTargeted)
        {
            return Result;
        }

        Result.bDownHandled = InSlate.ProcessMouseButtonDownEvent(Window->GetNativeWindow(), Down);
        Result.bUpHandled = InSlate.ProcessMouseButtonUpEvent(Up);
        Tick(InSlate);
        return Result;
    }

    auto SaveCapture(FSlateApplication& InSlate, const TSharedRef<SWidget>& InRoot, const FString& InPath) -> bool
    {
        TArray<FColor> Pixels;
        FIntVector Size = FIntVector::ZeroValue;
        if (!InSlate.TakeScreenshot(InRoot, Pixels, Size) || Size.X <= 0 || Size.Y <= 0 || Pixels.Num() < Size.X * Size.Y)
        {
            return false;
        }

        IFileManager::Get().MakeDirectory(*FPaths::GetPath(InPath), true);
        return FImageUtils::SaveImageByExtension(*InPath, FImageView(Pixels.GetData(), Size.X, Size.Y, ERawImageFormat::BGRA8));
    }

    auto FindFixtureClass() -> UClass*
    {
        for (TObjectIterator<UClass> It; It; ++It)
        {
            if (It->GetFName() == FixtureClassName && It->IsChildOf(AActor::StaticClass()))
            {
                return *It;
            }
        }

        return nullptr;
    }

    auto InvokeFixturePulse(AActor* InFixture) -> int32
    {
        UFunction* Pulse = IsValid(InFixture) ? InFixture->FindFunction(FixturePulseFunctionName) : nullptr;
        const FIntProperty* ReturnProperty = Pulse != nullptr ? CastField<FIntProperty>(Pulse->GetReturnProperty()) : nullptr;
        if (ReturnProperty == nullptr || Pulse->ParmsSize <= 0)
        {
            return -1;
        }

        TArray<uint8> Params;
        Params.SetNumZeroed(Pulse->ParmsSize);
        Pulse->InitializeStruct(Params.GetData());
        ON_SCOPE_EXIT { Pulse->DestroyStruct(Params.GetData()); };
        InFixture->ProcessEvent(Pulse, Params.GetData());
        return ReturnProperty->GetPropertyValue_InContainer(Params.GetData());
    }

    auto Refresh(const TSharedRef<FState>& InState) -> void
    {
        AActor* Fixture = InState->Fixture.Get();
        if (!IsValid(Fixture) || !InState->ViewModel.IsValid() || !InState->Dock.IsValid())
        {
            return;
        }

        InState->ViewModel->Tick(Fixture->GetWorld());
        InState->Dock->RefreshFromViewModel();
        if (FSlateApplication::IsInitialized())
        {
            Tick(FSlateApplication::Get());
        }
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkGoapDebugger_TimelineAuthoredPie,
    "Ck.GoapDebugger.Timeline.Authored.PIE",
    ck_tests_goap_debugger_timeline_authored_pie::TestFlags)

bool FCkGoapDebugger_TimelineAuthoredPie::RunTest(const FString&)
{
    using namespace ck_tests_goap_debugger_timeline_authored_pie;

    if (!FSlateApplication::IsInitialized())
    {
        AddError(TEXT("GOAP Timeline authored PIE test requires Slate."));
        return false;
    }

    const TSharedRef<FState> State = MakeShared<FState>();
    FSlateApplication& Slate = FSlateApplication::Get();
    State->ViewModel = MakeShared<FCkGoapDebugger_ViewModel>();
    State->Dock = SNew(SCkGoapDebugger_TimelineDock).ViewModel(State->ViewModel);
    State->WeakDock = State->Dock;
    State->Window = SNew(SWindow)
        .AutoCenter(EAutoCenter::None)
        .ClientSize(FVector2D{1100.0f, 700.0f})
        .CreateTitleBar(false)
        .HasCloseButton(false)
        [
            State->Dock.ToSharedRef()
        ];
    Slate.AddWindow(State->Window.ToSharedRef(), true);
    Tick(Slate);

    {
        const TSharedPtr<FCkUiView> View = State->Dock->Get_AuthoredView();
        State->WeakView = View;
        if (!View.IsValid() || !View->GetLastResult().Succeeded)
        {
            AddError(FString::Printf(TEXT("Production Timeline authored surface did not mount. Authored load failure: %s"),
                *State->Dock->Get_AuthoredLoadFailure()));
            Slate.DestroyWindowImmediately(State->Window.ToSharedRef());
            State->Window.Reset();
            State->Dock.Reset();
            State->ViewModel.Reset();
            Tick(Slate);
            return false;
        }
    }

    const TSharedPtr<SWidget> Empty = FindTagged(State->Dock.ToSharedRef(), TEXT("goap-timeline-empty"));
    const TSharedPtr<SWidget> EmptyText = FindTagged(State->Dock.ToSharedRef(), TEXT("goap-timeline-empty-text"));
    const TSharedPtr<SWidget> Selected = FindTagged(State->Dock.ToSharedRef(), TEXT("goap-timeline-selected"));
    State->bEmptyContractReady = Empty.IsValid() && EmptyText.IsValid() && Selected.IsValid()
        && Empty->GetVisibility().IsVisible() && !Selected->GetVisibility().IsVisible()
        && ContainsText(EmptyText.ToSharedRef(), TEXT("Select an agent"));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld* World)
    {
        if (UClass* FixtureClass = FindFixtureClass(); IsValid(World) && FixtureClass != nullptr)
        {
            State->Fixture = World->SpawnActor<AActor>(FixtureClass, FTransform::Identity);
            State->bFixtureSpawned = State->Fixture.IsValid();
        }
    })));
    for (int32 Pass = 0; Pass < 120; ++Pass)
    {
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(1));
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*)
        {
            Refresh(State);
        })));
    }
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    {
        Refresh(State);
        const auto& Roster = State->ViewModel->Get_Roster();
        if (Roster.IsEmpty())
        {
            return false;
        }

        State->ViewModel->SetSelectedEntity(Roster[0].EntityHandle);
        Refresh(State);
        const FCk_Handle Entity = State->ViewModel->GetSelectedEntity();
        if (ck::Is_NOT_Valid(Entity))
        {
            return false;
        }

        State->Entity = Entity;
        State->InitialEventCount = FCkGoapDebugger_DataCollector::GetHistory(Entity).Num();
        State->bHistoryReady = State->bFixtureSpawned;
        return State->bHistoryReady;
    }), 15.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*)
    {
        if (State->bHistoryReady)
        {
            State->PulseResult = InvokeFixturePulse(State->Fixture.Get());
        }
    })));
    for (int32 Pass = 0; Pass < 40; ++Pass)
    {
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(1));
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*)
        {
            Refresh(State);
        })));
    }
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    {
        Refresh(State);
        State->bPulseHistoryAdvanced = State->PulseResult == 1 && !ck::Is_NOT_Valid(State->Entity)
            && FCkGoapDebugger_DataCollector::GetHistory(State->Entity).Num() > State->InitialEventCount;
        return State->bPulseHistoryAdvanced;
    }), 15.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*)
    {
        if (!State->Dock.IsValid() || !State->ViewModel.IsValid())
        {
            return;
        }

        const TSharedPtr<SWidget> Selected = FindTagged(State->Dock.ToSharedRef(), TEXT("goap-timeline-selected"));
        const TSharedPtr<SWidget> Title = FindTagged(State->Dock.ToSharedRef(), TEXT("goap-timeline-title"));
        const TSharedPtr<SWidget> Status = FindTagged(State->Dock.ToSharedRef(), TEXT("goap-timeline-status"));
        const TSharedPtr<SWidget> TimelineBody = FindTagged(State->Dock.ToSharedRef(), TEXT("timeline-body"));
        const TSharedPtr<SWidget> Timeline = TimelineBody.IsValid()
            ? FindType(TimelineBody.ToSharedRef(), TEXT("SCkDebug_EventTimeline"))
            : nullptr;
        const TSharedPtr<SButton> Jump = TimelineBody.IsValid() ? FindJumpButton(TimelineBody.ToSharedRef()) : nullptr;
        State->bMountedContractReady = Selected.IsValid() && Title.IsValid() && Status.IsValid() && TimelineBody.IsValid()
            && Selected->GetVisibility().IsVisible() && ContainsText(Title.ToSharedRef(), TEXT("Timeline"))
            && ContainsText(Status.ToSharedRef(), FString::Printf(TEXT("%d events"), FCkGoapDebugger_DataCollector::GetHistory(State->Entity).Num()))
            && Timeline.IsValid() && Jump.IsValid();
        const FGeometry DockGeometry = State->Dock->GetCachedGeometry();
        const FGeometry BodyGeometry = TimelineBody.IsValid() ? TimelineBody->GetCachedGeometry() : DockGeometry;
        State->bNativeFillsDock = TimelineBody.IsValid() && !DockGeometry.GetLocalSize().IsNearlyZero() && !BodyGeometry.GetLocalSize().IsNearlyZero()
            && BodyGeometry.GetLocalSize().Y >= DockGeometry.GetLocalSize().Y * 0.60f;
        State->WeakTimelineBody = TimelineBody;

        if (Jump.IsValid())
        {
            const FMountedClickResult Click = ClickMounted(FSlateApplication::Get(), Jump.ToSharedRef());
            State->ClickDiagnostic = Click.Describe();
            State->ScrubEventIndex = State->ViewModel->GetScrubEventIndex();
            const TArray<FCkGoapDebugger_HistoryEvent>& History = FCkGoapDebugger_DataCollector::GetHistory(State->Entity);
            State->bPhysicalScrubReady = Click.Succeeded() && State->ViewModel->GetMode() == FCkGoapDebugger_ViewModel::EMode::Scrub
                && History.IsValidIndex(State->ScrubEventIndex);
        }

        const TSharedPtr<FCkUiView> CurrentView = State->Dock->Get_AuthoredView();
        if (CurrentView.IsValid() && TimelineBody.IsValid())
        {
            const int64 Revision = CurrentView->GetRevision();
            const TSharedPtr<SWidget> BodyBeforePoll = TimelineBody;
            TSharedPtr<SWidget> NativeBeforePoll;
            if (BodyBeforePoll->GetChildren() != nullptr && BodyBeforePoll->GetChildren()->Num() > 0)
            {
                NativeBeforePoll = ConstCastSharedRef<SWidget>(BodyBeforePoll->GetChildren()->GetChildAt(0));
            }
            State->bNoChangePollStable = !CurrentView->PollFiles() && CurrentView->GetRevision() == Revision
                && State->Dock->Get_AuthoredView() == CurrentView
                && FindTagged(State->Dock.ToSharedRef(), TEXT("timeline-body")) == BodyBeforePoll
                && NativeBeforePoll.IsValid() && BodyBeforePoll->GetChildren()->Num() > 0
                && &ConstCastSharedRef<SWidget>(BodyBeforePoll->GetChildren()->GetChildAt(0)).Get() == NativeBeforePoll.Get();

            const FCkUiLoadResult Rejected = CurrentView->TryReload(
                TEXT("<ui version=\"1\"><region name=\"main\"><unknown /></region></ui>"), TEXT(""), TEXT("TimelineAuthoredPie-invalid"));
            State->bRejectedReloadRetained = !Rejected.Succeeded && CurrentView->GetRevision() == Revision
                && State->Dock->Get_AuthoredView() == CurrentView
                && FindTagged(State->Dock.ToSharedRef(), TEXT("timeline-body")) == BodyBeforePoll
                && NativeBeforePoll.IsValid() && BodyBeforePoll->GetChildren() != nullptr && BodyBeforePoll->GetChildren()->Num() > 0
                && &ConstCastSharedRef<SWidget>(BodyBeforePoll->GetChildren()->GetChildAt(0)).Get() == NativeBeforePoll.Get();
        }
    })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*)
    {
        if (!State->Dock.IsValid() || !State->Window.IsValid())
        {
            return;
        }

        FSlateApplication& LocalSlate = FSlateApplication::Get();
        State->Window->Resize(FVector2D{1400.0f, 800.0f});
        Tick(LocalSlate);
        State->bWideCapture = SaveCapture(LocalSlate, State->Window.ToSharedRef(),
            FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Automation/GoapDebugger/TimelineAuthoredPie-Wide.png")));
        State->Window->Resize(FVector2D{480.0f, 700.0f});
        Tick(LocalSlate);
        const TSharedPtr<SWidget> TimelineBody = FindTagged(State->Dock.ToSharedRef(), TEXT("timeline-body"));
        const TSharedPtr<SWidget> NativeScrollWidget = TimelineBody.IsValid()
            ? FindType(TimelineBody.ToSharedRef(), TEXT("SScrollBox"))
            : nullptr;
        if (NativeScrollWidget.IsValid())
        {
            const TSharedPtr<SScrollBox> NativeScroll = StaticCastSharedRef<SScrollBox>(NativeScrollWidget.ToSharedRef());
            NativeScroll->SetScrollOffset(NativeScroll->GetScrollOffsetOfEnd() * 0.75f);
            Tick(LocalSlate);
            State->bNarrowScrollReachable = NativeScroll->GetCachedGeometry().GetLocalSize().X <= 480.0f
                && NativeScroll->GetScrollOffsetOfEnd() > 0.0f && NativeScroll->GetScrollOffset() > 0.0f;
        }
        State->bNarrowCapture = SaveCapture(LocalSlate, State->Window.ToSharedRef(),
            FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Automation/GoapDebugger/TimelineAuthoredPie-Narrow.png")));
    })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld*)
    {
        TestTrue(TEXT("GOAP Timeline mounts the authored empty shell before an agent is selected"), State->bEmptyContractReady);
        TestTrue(TEXT("GOAP Timeline reads the real selected agent history after a production replan pulse"),
            State->bHistoryReady && State->bPulseHistoryAdvanced);
        TestTrue(TEXT("GOAP Timeline exposes its live event count and retained SCkDebug_EventTimeline through the authored port"),
            State->bMountedContractReady);
        TestTrue(TEXT("GOAP Timeline native port substantially fills the selected authored dock height"), State->bNativeFillsDock);
        TestTrue(FString::Printf(TEXT("GOAP Timeline physically routes mounted jump-to-replan input into scrub mode (%s)"), *State->ClickDiagnostic),
            State->bPhysicalScrubReady);
        TestTrue(TEXT("GOAP Timeline unchanged authored file poll retains the accepted view and native timeline body identity"), State->bNoChangePollStable);
        TestTrue(TEXT("GOAP Timeline rejected authored reload retains the accepted view and native timeline body"), State->bRejectedReloadRetained);
        TestTrue(TEXT("GOAP Timeline captures wide and narrow mounted production surfaces"), State->bWideCapture && State->bNarrowCapture);
        TestTrue(TEXT("GOAP Timeline narrow native body has reachable horizontal overflow"), State->bNarrowScrollReachable);

        if (State->Dock.IsValid() && State->ViewModel.IsValid())
        {
            {
                const TSharedPtr<FCkUiView> ViewBeforeDeselection = State->Dock->Get_AuthoredView();
                const TSharedPtr<SWidget> BodyBeforeDeselection = FindTagged(State->Dock.ToSharedRef(), TEXT("timeline-body"));
                State->ViewModel->SetSelectedEntity(FCk_Handle{});
                State->Dock->RefreshFromViewModel();
                Tick(FSlateApplication::Get());
                const TSharedPtr<SWidget> Empty = FindTagged(State->Dock.ToSharedRef(), TEXT("goap-timeline-empty"));
                const TSharedPtr<SWidget> Selected = FindTagged(State->Dock.ToSharedRef(), TEXT("goap-timeline-selected"));
                State->bDeselectionRetainsShell = ViewBeforeDeselection.IsValid() && BodyBeforeDeselection.IsValid()
                    && State->Dock->Get_AuthoredView() == ViewBeforeDeselection
                    && FindTagged(State->Dock.ToSharedRef(), TEXT("timeline-body")) == BodyBeforeDeselection
                    && Empty.IsValid() && Empty->GetVisibility().IsVisible()
                    && Selected.IsValid() && !Selected->GetVisibility().IsVisible();
            }
            State->ViewModel->Reset_ForWorldChange();
            State->Dock->Reset_ForWorldChange();
            Tick(FSlateApplication::Get());
            State->bResetReleased = !State->Dock->Get_AuthoredView().IsValid() && !State->WeakTimelineBody.IsValid();
        }
        TestTrue(TEXT("GOAP Timeline transient deselection retains the admitted authored empty shell and native port"),
            State->bDeselectionRetainsShell);
        TestTrue(TEXT("GOAP Timeline reset releases the authored shell native timeline port"), State->bResetReleased);

        if (FSlateApplication::IsInitialized() && State->Window.IsValid())
        {
            FSlateApplication::Get().DestroyWindowImmediately(State->Window.ToSharedRef());
        }
        State->Window.Reset();
        State->Dock.Reset();
        State->ViewModel.Reset();
        if (FSlateApplication::IsInitialized())
        {
            Tick(FSlateApplication::Get());
        }
        if (State->Fixture.IsValid())
        {
            State->Fixture->Destroy();
        }
        State->Fixture.Reset();
        State->bTornDown = !State->WeakDock.IsValid() && !State->WeakView.IsValid();
        TestTrue(TEXT("GOAP Timeline teardown releases the authored view and dock"), State->bTornDown);
    })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif
