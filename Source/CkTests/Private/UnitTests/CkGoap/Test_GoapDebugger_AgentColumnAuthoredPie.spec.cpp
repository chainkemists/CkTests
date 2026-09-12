#include "CoreMinimal.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkGoapDebugger/ViewModel/CkGoapDebugger_ViewModel.h"
#include "CkGoapDebugger/Window/SCkGoapDebugger_AgentColumn.h"

#include "CkCore/Validation/CkIsValid.h"
#include "CkGoap/Planner/CkGoap_Planner_Utils.h"
#include "CkSlateLayout/CkFlexText.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include "Engine/World.h"
#include "Framework/Application/SlateApplication.h"
#include "Framework/Application/SlateUser.h"
#include "GameFramework/Actor.h"
#include "HAL/FileManager.h"
#include "ImageUtils.h"
#include "Input/Events.h"
#include "Layout/WidgetPath.h"
#include "Misc/AutomationTest.h"
#include "Misc/Paths.h"
#include "UObject/UObjectIterator.h"
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"

namespace ck_tests_goap_debugger_agent_column_authored_pie
{
    constexpr auto TestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;
    const FName FixtureClassName{TEXT("Ck_Goap_Planner_SquadRosterPieFixture")};

    struct FState final
    {
        TWeakObjectPtr<AActor> Fixture;
        TSharedPtr<FCkGoapDebugger_ViewModel> ViewModel;
        TSharedPtr<SCkGoapDebugger_AgentColumn> Panel;
        TSharedPtr<SWindow> Window;
        TWeakPtr<SCkGoapDebugger_AgentColumn> WeakPanel;
        TWeakPtr<FCkUiView> WeakView;
        TWeakPtr<SWidget> WeakEnabled;
        FCk_Handle Entity;
        FCk_Handle_Goap_Planner Planner;
        FString EntityName;
        FString PlannerName;
        FString PlannerStatus;
        FString PlanOnStart;
        FString Defaults;
        int32 ReplanAttemptCountBeforeClick = INDEX_NONE;
        int64 SearchBudgetMicroseconds = INDEX_NONE;
        ECk_EnableDisable ExpectedEnabled = ECk_EnableDisable::Enable;
        ECk_Goap_ReplanPolicy PolicyBeforeProposal = ECk_Goap_ReplanPolicy::Explicit;
        bool bFixtureSpawned = false;
        bool bProjectionReady = false;
        bool bMountedContractReady = false;
        bool bNoChangePollStable = false;
        bool bRejectedReloadRetained = false;
        bool bReplanClicked = false;
        bool bReplanObserved = false;
        bool bPolicyInputRejected = false;
        bool bPolicyObserved = false;
        bool bEnabledClicked = false;
        bool bEnabledObserved = false;
        bool bWideCapture = false;
        bool bNarrowCapture = false;
        bool bResetEmpty = false;
        bool bTornDown = false;
        FString ReplanClickDiagnostic;
        FString SwitchClickDiagnostic;
        FString PolicyClickDiagnostic;
    };

    auto Tick(FSlateApplication& InSlate) -> void
    {
        InSlate.PumpMessages();
        InSlate.Tick();
        InSlate.Tick();
    }

    auto FindTagged(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTag() == InTag) { return InRoot; }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SWidget> Found = FindTagged(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag); Found.IsValid())
            { return Found; }
        }
        return {};
    }

    auto FindType(const TSharedRef<SWidget>& InRoot, const FString& InType) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTypeAsString() == InType) { return InRoot; }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SWidget> Found = FindType(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InType); Found.IsValid())
            { return Found; }
        }
        return {};
    }

    auto ContainsText(const TSharedRef<SWidget>& InRoot, const FString& InText) -> bool
    {
        if (InRoot->GetTypeAsString() == TEXT("STextBlock") && StaticCastSharedRef<STextBlock>(InRoot)->GetText().ToString().Contains(InText))
        { return true; }
        if (InRoot->GetTypeAsString() == TEXT("SCkFlexText") && StaticCastSharedRef<SCkFlexText>(InRoot)->GetText().ToString().Contains(InText))
        { return true; }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (ContainsText(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InText)) { return true; }
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

    struct FMountedClickResult final
    {
        bool bTargeted = false;
        bool bDownHandled = false;
        bool bUpHandled = false;
        FString Describe() const
        {
            return FString::Printf(TEXT("targeted=%d down=%d up=%d"), bTargeted, bDownHandled, bUpHandled);
        }
        auto Succeeded() const -> bool { return bTargeted && bDownHandled && bUpHandled; }
        auto DownSucceeded() const -> bool { return bTargeted && bDownHandled; }
    };

    auto ClickMounted(FSlateApplication& InSlate, const TSharedRef<SWidget>& InWidget) -> FMountedClickResult
    {
        FMountedClickResult Result;
        const TSharedPtr<SWindow> Window = InSlate.FindWidgetWindow(InWidget);
        if (!Window.IsValid() || !Window->GetNativeWindow().IsValid()) { return Result; }
        Window->BringToFront(true);
        Tick(InSlate);
        InSlate.ReleaseAllPointerCapture(0);
        const FGeometry Geometry = InWidget->GetCachedGeometry();
        if (Geometry.GetLocalSize().IsNearlyZero()) { return Result; }
        const FVector2D Position = Geometry.LocalToAbsolute(Geometry.GetLocalSize() * 0.5f);
        const TSet<FKey> None;
        const TSet<FKey> DownButtons{EKeys::LeftMouseButton};
        const FPointerEvent Move(0, FSlateApplication::CursorPointerIndex, Position, Position, None, EKeys::Invalid, 0.0f, FModifierKeysState{});
        const FPointerEvent Down(0, FSlateApplication::CursorPointerIndex, Position, Position, DownButtons, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        const FPointerEvent Up(0, FSlateApplication::CursorPointerIndex, Position, Position, None, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        InSlate.SetCursorPos(Position);
        InSlate.ProcessMouseMoveEvent(Move, true);
        Result.bTargeted = WidgetPathContains(InSlate.LocateWindowUnderMouse(Position, InSlate.GetInteractiveTopLevelWindows(), false, 0), InWidget);
        if (!Result.bTargeted) { return Result; }
        Result.bDownHandled = InSlate.ProcessMouseButtonDownEvent(Window->GetNativeWindow(), Down);
        Result.bUpHandled = InSlate.ProcessMouseButtonUpEvent(Up);
        Tick(InSlate);
        return Result;
    }

    auto SaveCapture(FSlateApplication& InSlate, const TSharedRef<SWidget>& InRoot, const FString& InPath) -> bool
    {
        TArray<FColor> Pixels;
        FIntVector Size = FIntVector::ZeroValue;
        if (!InSlate.TakeScreenshot(InRoot, Pixels, Size) || Size.X <= 0 || Size.Y <= 0 || Pixels.Num() < Size.X * Size.Y) { return false; }
        IFileManager::Get().MakeDirectory(*FPaths::GetPath(InPath), true);
        return FImageUtils::SaveImageByExtension(*InPath, FImageView(Pixels.GetData(), Size.X, Size.Y, ERawImageFormat::BGRA8));
    }

    auto FindFixtureClass() -> UClass*
    {
        for (TObjectIterator<UClass> It; It; ++It)
        {
            if (It->GetFName() == FixtureClassName && It->IsChildOf(AActor::StaticClass())) { return *It; }
        }
        return nullptr;
    }

    auto Refresh(const TSharedRef<FState>& InState) -> void
    {
        AActor* Fixture = InState->Fixture.Get();
        if (!IsValid(Fixture) || !InState->ViewModel.IsValid() || !InState->Panel.IsValid()) { return; }
        InState->ViewModel->Tick(Fixture->GetWorld());
        InState->Panel->RefreshFromViewModel();
        if (FSlateApplication::IsInitialized()) { Tick(FSlateApplication::Get()); }
    }

    auto StatusText(const ECk_GoapPlanStatus InStatus) -> FString
    {
        switch (InStatus)
        {
            case ECk_GoapPlanStatus::PlanFound: return TEXT("Plan Found");
            case ECk_GoapPlanStatus::Planning: return TEXT("Planning…");
            case ECk_GoapPlanStatus::PlanFailed: return TEXT("Plan Failed");
            case ECk_GoapPlanStatus::CostThresholdReached: return TEXT("Cost Threshold");
            default: return TEXT("Idle");
        }
    }

} // namespace ck_tests_goap_debugger_agent_column_authored_pie

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkGoapDebugger_AgentColumnAuthoredPie,
    "Ck.GoapDebugger.AgentColumn.Authored.PIE",
    ck_tests_goap_debugger_agent_column_authored_pie::TestFlags)

bool FCkGoapDebugger_AgentColumnAuthoredPie::RunTest(const FString&)
{
    using namespace ck_tests_goap_debugger_agent_column_authored_pie;

    if (!FSlateApplication::IsInitialized())
    {
        AddError(TEXT("GOAP Agent Column authored PIE test requires Slate."));
        return false;
    }

    const TSharedRef<FState> State = MakeShared<FState>();
    FSlateApplication& Slate = FSlateApplication::Get();
    State->ViewModel = MakeShared<FCkGoapDebugger_ViewModel>();
    State->Panel = SNew(SCkGoapDebugger_AgentColumn).ViewModel(State->ViewModel);
    State->WeakPanel = State->Panel;
    State->Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{1100.0f, 700.0f})
        .CreateTitleBar(false).HasCloseButton(false)[State->Panel.ToSharedRef()];
    Slate.AddWindow(State->Window.ToSharedRef(), true);
    Tick(Slate);

    const TSharedPtr<FCkUiView> View = State->Panel->Get_AuthoredView();
    State->WeakView = View;
    if (!View.IsValid() || !View->GetLastResult().Succeeded)
    {
        AddError(FString::Printf(TEXT("Production Agent Column authored surface did not mount. Authored load failure: %s"),
            *State->Panel->Get_AuthoredLoadFailure()));
        Slate.DestroyWindowImmediately(State->Window.ToSharedRef());
        State->Window.Reset();
        State->Panel.Reset();
        State->ViewModel.Reset();
        Tick(Slate);
        return false;
    }

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
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) { Refresh(State); })));
    }
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    {
        Refresh(State);
        const auto& Roster = State->ViewModel->Get_Roster();
        if (Roster.IsEmpty()) { return false; }
        State->ViewModel->SetSelectedEntity(Roster[0].EntityHandle);
        const FCkGoapDebugger_EntitySnapshot* Snapshot = State->ViewModel->GetCurrentEntitySnapshot();
        if (Snapshot == nullptr || Snapshot->TopLevelPlanners.IsEmpty()) { return false; }
        const FCkGoapDebugger_PlannerInfo* Wanted = Snapshot->TopLevelPlanners.FindByPredicate([](const FCkGoapDebugger_PlannerInfo& InPlanner)
        { return InPlanner.DisplayName == TEXT("FallbackVsChain"); });
        if (Wanted == nullptr) { return false; }
        const FCk_Handle_Goap_Planner WantedHandle = Wanted->PlannerHandle;
        State->ViewModel->SetSelectedActionSet(WantedHandle);
        Refresh(State);
        const FCkGoapDebugger_PlannerInfo* Planner = State->ViewModel->GetSelectedPlannerInfo();
        const FCkGoapDebugger_EntitySnapshot* SelectedSnapshot = State->ViewModel->GetCurrentEntitySnapshot();
        if (Planner == nullptr || SelectedSnapshot == nullptr || Planner->PlannerHandle != WantedHandle || Planner->PlanClassNames.IsEmpty() || Planner->GoalAuthored.IsEmpty()) { return false; }

        State->Entity = Roster[0].EntityHandle;
        State->Planner = Planner->PlannerHandle;
        State->EntityName = SelectedSnapshot->DebugName.IsEmpty() ? Planner->DisplayName : SelectedSnapshot->DebugName;
        State->PlannerName = Planner->DisplayName;
        State->PlannerStatus = StatusText(Planner->PlanStatus);
        State->PlanOnStart = Planner->PlanOnStart ? TEXT("true") : TEXT("false");
        State->Defaults = Planner->AllowPlanFailed
            ? TEXT("plan failure allowed")
            : Planner->HasUnconditionalFallback ? TEXT("fallback present") : TEXT("fallback missing");
        State->SearchBudgetMicroseconds = Planner->SearchBudgetMicroseconds;
        State->bProjectionReady = State->bFixtureSpawned && ck::IsValid(State->Planner)
            && UCk_Utils_Goap_Planner_UE::Get_SearchBudgetMicroseconds(State->Planner) == State->SearchBudgetMicroseconds;
        return State->bProjectionReady;
    }), 15.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld*)
    {
        const TSharedPtr<FCkUiView> View = State->Panel.IsValid() ? State->Panel->Get_AuthoredView() : nullptr;
        if (!State->bProjectionReady || !State->Panel.IsValid() || !View.IsValid()) { return; }
        const TSharedPtr<SWidget> Name = FindTagged(State->Panel.ToSharedRef(), TEXT("goap-agent-name"));
        const TSharedPtr<SWidget> Status = FindTagged(State->Panel.ToSharedRef(), TEXT("goap-agent-status"));
        const TSharedPtr<SWidget> Policy = FindTagged(State->Panel.ToSharedRef(), TEXT("goap-agent-policy"));
        const TSharedPtr<SWidget> Enabled = FindTagged(State->Panel.ToSharedRef(), TEXT("goap-agent-enabled"));
        const TSharedPtr<SWidget> Replan = FindTagged(State->Panel.ToSharedRef(), TEXT("goap-agent-replan"));
        const TSharedPtr<SWidget> Breadcrumb = FindTagged(State->Panel.ToSharedRef(), TEXT("goap-agent-breadcrumb-body"));
        const TSharedPtr<SWidget> Goal = FindTagged(State->Panel.ToSharedRef(), TEXT("goap-agent-goal-body"));
        const TSharedPtr<SWidget> Plan = FindTagged(State->Panel.ToSharedRef(), TEXT("goap-agent-plan-body"));
        const TSharedPtr<SWidget> Budget = FindTagged(State->Panel.ToSharedRef(), TEXT("goap-agent-budget-body"));
        const TSharedPtr<SWidget> Interval = FindTagged(State->Panel.ToSharedRef(), TEXT("goap-agent-min-interval"));
        const TSharedPtr<SWidget> Threshold = FindTagged(State->Panel.ToSharedRef(), TEXT("goap-agent-threshold"));
        const TSharedPtr<SWidget> PlanOnStart = FindTagged(State->Panel.ToSharedRef(), TEXT("goap-agent-plan-on-start"));
        const TSharedPtr<SWidget> Defaults = FindTagged(State->Panel.ToSharedRef(), TEXT("goap-agent-defaults"));
        const TSharedPtr<SWidget> LastResult = FindTagged(State->Panel.ToSharedRef(), TEXT("goap-agent-last-result"));
        State->bMountedContractReady = Name.IsValid() && Status.IsValid() && Policy.IsValid() && Enabled.IsValid() && Replan.IsValid()
            && Breadcrumb.IsValid() && Goal.IsValid() && Plan.IsValid() && Budget.IsValid() && Interval.IsValid() && Threshold.IsValid()
            && PlanOnStart.IsValid() && Defaults.IsValid() && LastResult.IsValid()
            && FindType(Policy.ToSharedRef(), TEXT("SCkUiSelect")).IsValid()
            && FindType(Enabled.ToSharedRef(), TEXT("SCkDebug_Switch")).IsValid()
            && FindType(Replan.ToSharedRef(), TEXT("SButton")).IsValid()
            && FindType(Budget.ToSharedRef(), TEXT("SCkDebug_NumericEditor")).IsValid()
            && Goal->GetChildren()->Num() > 0 && Plan->GetChildren()->Num() > 0
            && ContainsText(Name.ToSharedRef(), State->EntityName) && ContainsText(Status.ToSharedRef(), State->PlannerStatus)
            && ContainsText(PlanOnStart.ToSharedRef(), State->PlanOnStart)
            && ContainsText(Defaults.ToSharedRef(), State->Defaults)
            && ContainsText(LastResult.ToSharedRef(), State->PlannerStatus);
        State->WeakEnabled = Enabled;

        const int64 Revision = View->GetRevision();
        const TSharedPtr<SWidget> BudgetBeforePoll = Budget;
        State->bNoChangePollStable = !View->PollFiles()
            && View->GetRevision() == Revision
            && State->Panel->Get_AuthoredView() == View
            && FindTagged(State->Panel.ToSharedRef(), TEXT("goap-agent-budget-body")) == BudgetBeforePoll;
    })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*)
    {
        if (!State->bMountedContractReady) { return; }
        if (!State->Panel.IsValid())
        {
            State->ReplanClickDiagnostic = TEXT("Agent Column panel unavailable before mounted replan input");
            return;
        }
        FSlateApplication& LocalSlate = FSlateApplication::Get();
        const TSharedPtr<SWidget> Replan = FindTagged(State->Panel.ToSharedRef(), TEXT("goap-agent-replan"));
        const FCkGoapDebugger_PlannerInfo* Planner = State->ViewModel.IsValid() ? State->ViewModel->GetSelectedPlannerInfo() : nullptr;
        if (!Replan.IsValid() || Planner == nullptr || Planner->PlannerHandle != State->Planner)
        {
            State->ReplanClickDiagnostic = TEXT("mounted replan target or selected planner unavailable");
            return;
        }
        State->ReplanAttemptCountBeforeClick = Planner->PlanAttemptCount;
        const FMountedClickResult Click = ClickMounted(LocalSlate, Replan.ToSharedRef());
        State->ReplanClickDiagnostic = Click.Describe();
        State->bReplanClicked = Click.Succeeded();
    })));
    for (int32 Pass = 0; Pass < 40; ++Pass)
    {
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(1));
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) { Refresh(State); })));
    }
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    {
        Refresh(State);
        const FCkGoapDebugger_PlannerInfo* Planner = State->ViewModel->GetSelectedPlannerInfo();
        State->bReplanObserved = Planner != nullptr && Planner->PlannerHandle == State->Planner
            && State->ReplanAttemptCountBeforeClick != INDEX_NONE
            && Planner->PlanAttemptCount > State->ReplanAttemptCountBeforeClick;
        return State->bReplanObserved;
    }), 15.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*)
    {
        if (!State->bMountedContractReady) { return; }
        if (!State->Panel.IsValid())
        {
            State->PolicyClickDiagnostic = TEXT("Agent Column panel unavailable before mounted policy input");
            return;
        }
        FSlateApplication& LocalSlate = FSlateApplication::Get();
        const TSharedPtr<SWidget> PolicyPort = FindTagged(State->Panel.ToSharedRef(), TEXT("goap-agent-policy"));
        const TSharedPtr<SWidget> Policy = PolicyPort.IsValid()
            ? FindType(PolicyPort.ToSharedRef(), TEXT("SCkUiSelect"))
            : nullptr;
        const FCkGoapDebugger_PlannerInfo* Planner = State->ViewModel.IsValid() ? State->ViewModel->GetSelectedPlannerInfo() : nullptr;
        if (!PolicyPort.IsValid() || !Policy.IsValid() || Planner == nullptr || Planner->PlannerHandle != State->Planner)
        {
            State->PolicyClickDiagnostic = FString::Printf(TEXT("policy-port=%s concrete-select=%s selected-planner=%d"),
                PolicyPort.IsValid() ? *PolicyPort->GetTypeAsString() : TEXT("<missing>"),
                Policy.IsValid() ? *Policy->GetTypeAsString() : TEXT("<missing>"),
                Planner != nullptr && Planner->PlannerHandle == State->Planner);
            return;
        }
        State->PolicyBeforeProposal = Planner->ReplanPolicy;
        const bool bDisabled = !Policy->IsEnabled();
        LocalSlate.SetUserFocus(0, Policy.ToSharedRef(), EFocusCause::SetDirectly);
        const bool bFocused = LocalSlate.GetUserFocusedWidget(0) == Policy;
        const bool bDownHandled = LocalSlate.ProcessKeyDownEvent(FKeyEvent(EKeys::Down, FModifierKeysState{}, 0, false, 0, 0));
        State->PolicyClickDiagnostic = FString::Printf(TEXT("policy-port=%s concrete-select=%s disabled=%d focus=%d down=%d prior=%d"),
            *PolicyPort->GetTypeAsString(), *Policy->GetTypeAsString(), bDisabled, bFocused, bDownHandled,
            static_cast<int32>(State->PolicyBeforeProposal));
        // Slate may report the globally routed key handled even when this disabled select cannot act on it.
        // The authoritative assertion below proves its live policy remains read-only.
        State->bPolicyInputRejected = bDisabled;
        Tick(LocalSlate);
    })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*)
    {
        // Runtime replan-policy mutation is unsupported, so the authored select is deliberately disabled.
        // Global key routing is diagnostic-only; the authoritative policy must remain unchanged.
        Refresh(State);
        const FCkGoapDebugger_PlannerInfo* Planner = State->ViewModel->GetSelectedPlannerInfo();
        State->bPolicyObserved = Planner != nullptr && Planner->PlannerHandle == State->Planner
            && Planner->ReplanPolicy == State->PolicyBeforeProposal;
    })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*)
    {
        if (!State->bMountedContractReady) { return; }
        if (!State->Panel.IsValid())
        {
            State->SwitchClickDiagnostic = TEXT("Agent Column panel unavailable before mounted enabled input");
            return;
        }
        const TSharedPtr<SWidget> Enabled = FindTagged(State->Panel.ToSharedRef(), TEXT("goap-agent-enabled"));
        const FCkGoapDebugger_PlannerInfo* Planner = State->ViewModel.IsValid() ? State->ViewModel->GetSelectedPlannerInfo() : nullptr;
        if (!Enabled.IsValid() || Planner == nullptr || Planner->PlannerHandle != State->Planner)
        {
            State->SwitchClickDiagnostic = TEXT("mounted enabled target or selected planner unavailable");
            return;
        }
        State->ExpectedEnabled = Planner->EnableToggle == ECk_EnableDisable::Enable
            ? ECk_EnableDisable::Disable
            : ECk_EnableDisable::Enable;
        const FMountedClickResult Click = ClickMounted(FSlateApplication::Get(), Enabled.ToSharedRef());
        State->SwitchClickDiagnostic = Click.Describe();
        // SCkDebug_Switch dispatches on mouse-down and intentionally has no mouse-up override.
        State->bEnabledClicked = Click.DownSucceeded();
    })));
    for (int32 Pass = 0; Pass < 20; ++Pass)
    {
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(1));
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) { Refresh(State); })));
    }
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    {
        Refresh(State);
        const FCkGoapDebugger_PlannerInfo* Planner = State->ViewModel->GetSelectedPlannerInfo();
        State->bEnabledObserved = Planner != nullptr && Planner->PlannerHandle == State->Planner && Planner->EnableToggle == State->ExpectedEnabled;
        return State->bEnabledObserved;
    }), 15.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*)
    {
        if (!State->Window.IsValid() || !State->Panel.IsValid()) { return; }
        FSlateApplication& LocalSlate = FSlateApplication::Get();
        State->Window->Resize(FVector2D{1400.0f, 800.0f});
        Tick(LocalSlate);
        State->bWideCapture = SaveCapture(LocalSlate, State->Window.ToSharedRef(),
            FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Automation/GoapDebugger/AgentColumnAuthoredPie-Wide.png")));
        State->Window->Resize(FVector2D{480.0f, 700.0f});
        Tick(LocalSlate);
        State->bNarrowCapture = SaveCapture(LocalSlate, State->Window.ToSharedRef(),
            FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Automation/GoapDebugger/AgentColumnAuthoredPie-Narrow.png")));
        const TSharedPtr<FCkUiView> View = State->Panel->Get_AuthoredView();
        const TSharedPtr<SWidget> Budget = FindTagged(State->Panel.ToSharedRef(), TEXT("goap-agent-budget-body"));
        if (View.IsValid() && Budget.IsValid())
        {
            const int64 Revision = View->GetRevision();
            const FCkUiLoadResult Rejected = View->TryReload(
                TEXT("<ui version=\"1\"><region name=\"main\"><unknown /></region></ui>"), TEXT(""), TEXT("AgentColumnAuthoredPie-invalid"));
            State->bRejectedReloadRetained = !Rejected.Succeeded && View->GetRevision() == Revision
                && FindTagged(State->Panel.ToSharedRef(), TEXT("goap-agent-budget-body")) == Budget;
        }
    })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld*)
    {
        TestTrue(TEXT("GOAP Agent Column selects and projects a live FallbackVsChain fixture planner"), State->bProjectionReady);
        TestTrue(TEXT("GOAP Agent Column mounts its authored controls and live native plan, goal, and int64-budget ports"), State->bMountedContractReady);
        TestTrue(TEXT("GOAP Agent Column unchanged authored file poll retains the live surface and native budget port identity"), State->bNoChangePollStable);
        TestTrue(TEXT("GOAP Agent Column rejected authored reload retains the accepted mounted surface and native budget port identity"), State->bRejectedReloadRetained);
        TestTrue(FString::Printf(TEXT("Physical mounted Replan action produces a real planner attempt: %s"), *State->ReplanClickDiagnostic), State->bReplanClicked && State->bReplanObserved);
        TestTrue(FString::Printf(TEXT("Mounted disabled Replan policy select remains read-only and preserves the live policy: %s"), *State->PolicyClickDiagnostic), State->bPolicyInputRejected && State->bPolicyObserved);
        TestTrue(FString::Printf(TEXT("Physical mounted Enabled switch reaches the live planner: %s"), *State->SwitchClickDiagnostic), State->bEnabledClicked && State->bEnabledObserved);
        TestTrue(TEXT("GOAP Agent Column captures wide and narrow mounted production surfaces"), State->bWideCapture && State->bNarrowCapture);

        if (State->Panel.IsValid())
        {
            State->ViewModel->Reset_ForWorldChange();
            State->Panel->Reset_ForWorldChange();
            Tick(FSlateApplication::Get());
            State->bResetEmpty = !State->Panel->Get_AuthoredView().IsValid() && !State->WeakEnabled.IsValid();
        }
        TestTrue(TEXT("GOAP Agent Column reset removes handle-bearing authored ports before teardown"), State->bResetEmpty);
        if (FSlateApplication::IsInitialized() && State->Window.IsValid()) { FSlateApplication::Get().DestroyWindowImmediately(State->Window.ToSharedRef()); }
        State->Window.Reset();
        State->Panel.Reset();
        State->ViewModel.Reset();
        if (FSlateApplication::IsInitialized()) { Tick(FSlateApplication::Get()); }
        if (State->Fixture.IsValid()) { State->Fixture->Destroy(); }
        State->Fixture.Reset();
        State->bTornDown = !State->WeakPanel.IsValid() && !State->WeakView.IsValid();
        TestTrue(TEXT("GOAP Agent Column releases its authored view and cannot retain late handle callbacks"), State->bTornDown);
    })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif
