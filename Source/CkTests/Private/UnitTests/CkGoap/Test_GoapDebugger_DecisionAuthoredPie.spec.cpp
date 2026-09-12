#include "CoreMinimal.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkGoapDebugger/ViewModel/CkGoapDebugger_ViewModel.h"
#include "CkGoapDebugger/Window/SCkGoapDebugger_DecisionPanel.h"

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
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"

namespace ck_tests_goap_debugger_decision_authored_pie
{
    constexpr auto TestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;
    const FName FixtureClassName{TEXT("Ck_Goap_Planner_SquadRosterPieFixture")};

    struct FState final
    {
        TWeakObjectPtr<AActor> Fixture;
        TSharedPtr<FCkGoapDebugger_ViewModel> ViewModel;
        TSharedPtr<SCkGoapDebugger_DecisionPanel> Panel;
        TSharedPtr<SWindow> Window;
        TWeakPtr<SCkGoapDebugger_DecisionPanel> WeakPanel;
        TWeakPtr<FCkUiView> WeakView;
        TWeakPtr<SWidget> WeakDecisionBody;
        FCk_Handle Entity;
        FCk_Handle_Goap_Planner Planner;
        FString PlannerName;
        FString PlannerStatus;
        bool bFixtureSpawned = false;
        bool bProjectionReady = false;
        bool bEmptyContractReady = false;
        bool bSelectedContractReady = false;
        bool bNoChangePollStable = false;
        bool bRejectedReloadRetained = false;
        bool bWideCapture = false;
        bool bNarrowCapture = false;
        bool bResetEmpty = false;
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

    auto Refresh(const TSharedRef<FState>& InState) -> void
    {
        AActor* Fixture = InState->Fixture.Get();
        if (!IsValid(Fixture) || !InState->ViewModel.IsValid() || !InState->Panel.IsValid())
        {
            return;
        }

        InState->ViewModel->Tick(Fixture->GetWorld());
        InState->Panel->RefreshFromViewModel();
        if (FSlateApplication::IsInitialized())
        {
            Tick(FSlateApplication::Get());
        }
    }

    auto StatusText(const ECk_GoapPlanStatus InStatus) -> FString
    {
        switch (InStatus)
        {
            case ECk_GoapPlanStatus::PlanFound:
                return TEXT("Plan Found");
            case ECk_GoapPlanStatus::Planning:
                return TEXT("Planning…");
            case ECk_GoapPlanStatus::PlanFailed:
                return TEXT("Plan Failed");
            case ECk_GoapPlanStatus::CostThresholdReached:
                return TEXT("Cost Threshold");
            default:
                return TEXT("Idle");
        }
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkGoapDebugger_DecisionAuthoredPie,
    "Ck.GoapDebugger.Decision.Authored.PIE",
    ck_tests_goap_debugger_decision_authored_pie::TestFlags)

bool FCkGoapDebugger_DecisionAuthoredPie::RunTest(const FString&)
{
    using namespace ck_tests_goap_debugger_decision_authored_pie;

    if (!FSlateApplication::IsInitialized())
    {
        AddError(TEXT("GOAP Decision authored PIE test requires Slate."));
        return false;
    }

    const TSharedRef<FState> State = MakeShared<FState>();
    FSlateApplication& Slate = FSlateApplication::Get();
    State->ViewModel = MakeShared<FCkGoapDebugger_ViewModel>();
    State->Panel = SNew(SCkGoapDebugger_DecisionPanel).ViewModel(State->ViewModel);
    State->WeakPanel = State->Panel;
    State->Window = SNew(SWindow)
        .AutoCenter(EAutoCenter::None)
        .ClientSize(FVector2D{1100.0f, 700.0f})
        .CreateTitleBar(false)
        .HasCloseButton(false)
        [
            State->Panel.ToSharedRef()
        ];
    Slate.AddWindow(State->Window.ToSharedRef(), true);
    Tick(Slate);

    {
        const TSharedPtr<FCkUiView> View = State->Panel->Get_AuthoredView();
        State->WeakView = View;
        if (!View.IsValid() || !View->GetLastResult().Succeeded)
        {
            AddError(FString::Printf(TEXT("Production Decision authored surface did not mount. Authored load failure: %s"),
                *State->Panel->Get_AuthoredLoadFailure()));
            Slate.DestroyWindowImmediately(State->Window.ToSharedRef());
            State->Window.Reset();
            State->Panel.Reset();
            State->ViewModel.Reset();
            Tick(Slate);
            return false;
        }
    }

    const TSharedPtr<SWidget> Empty = FindTagged(State->Panel.ToSharedRef(), TEXT("goap-decision-empty"));
    const TSharedPtr<SWidget> EmptyText = FindTagged(State->Panel.ToSharedRef(), TEXT("goap-decision-empty-text"));
    const TSharedPtr<SWidget> Selected = FindTagged(State->Panel.ToSharedRef(), TEXT("goap-decision-selected"));
    State->bEmptyContractReady = Empty.IsValid() && EmptyText.IsValid() && Selected.IsValid()
        && Empty->GetVisibility().IsVisible() && !Selected->GetVisibility().IsVisible()
        && ContainsText(EmptyText.ToSharedRef(), TEXT("Select a Planner"));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld* World)
    {
        UClass* FixtureClass = FindFixtureClass();
        if (IsValid(World) && FixtureClass != nullptr)
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
        const FCkGoapDebugger_EntitySnapshot* Snapshot = State->ViewModel->GetCurrentEntitySnapshot();
        if (Snapshot == nullptr || Snapshot->TopLevelPlanners.IsEmpty())
        {
            return false;
        }

        const FCkGoapDebugger_PlannerInfo* Wanted = Snapshot->TopLevelPlanners.FindByPredicate([](const FCkGoapDebugger_PlannerInfo& InPlanner)
        {
            return InPlanner.DisplayName == TEXT("FallbackVsChain");
        });
        if (Wanted == nullptr)
        {
            return false;
        }

        State->ViewModel->SetSelectedActionSet(Wanted->PlannerHandle);
        Refresh(State);
        const FCkGoapDebugger_PlannerInfo* Planner = State->ViewModel->GetSelectedPlannerInfo();
        if (Planner == nullptr || Planner->PlannerHandle != Wanted->PlannerHandle || Planner->ChildActions.IsEmpty())
        {
            return false;
        }

        State->Entity = Roster[0].EntityHandle;
        State->Planner = Planner->PlannerHandle;
        State->PlannerName = Planner->DisplayName;
        State->PlannerStatus = StatusText(Planner->PlanStatus);
        State->bProjectionReady = State->bFixtureSpawned && ck::IsValid(State->Entity) && ck::IsValid(State->Planner);
        return State->bProjectionReady;
    }), 15.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*)
    {
        if (!State->bProjectionReady || !State->Panel.IsValid())
        {
            return;
        }

        const TSharedPtr<SWidget> Empty = FindTagged(State->Panel.ToSharedRef(), TEXT("goap-decision-empty"));
        const TSharedPtr<SWidget> Selected = FindTagged(State->Panel.ToSharedRef(), TEXT("goap-decision-selected"));
        const TSharedPtr<SWidget> Title = FindTagged(State->Panel.ToSharedRef(), TEXT("goap-decision-title"));
        const TSharedPtr<SWidget> Status = FindTagged(State->Panel.ToSharedRef(), TEXT("goap-decision-status"));
        const TSharedPtr<SWidget> DecisionBody = FindTagged(State->Panel.ToSharedRef(), TEXT("decision-body"));
        TSharedPtr<SWidget> NativeBody;
        if (DecisionBody.IsValid() && DecisionBody->GetChildren() != nullptr && DecisionBody->GetChildren()->Num() > 0)
        {
            NativeBody = ConstCastSharedRef<SWidget>(DecisionBody->GetChildren()->GetChildAt(0));
        }
        State->bSelectedContractReady = Empty.IsValid() && Selected.IsValid() && Title.IsValid() && Status.IsValid() && DecisionBody.IsValid()
            && !Empty->GetVisibility().IsVisible() && Selected->GetVisibility().IsVisible()
            && ContainsText(Title.ToSharedRef(), FString::Printf(TEXT("Decision: %s"), *State->PlannerName))
            && ContainsText(Status.ToSharedRef(), State->PlannerStatus)
            && NativeBody.IsValid();
        State->WeakDecisionBody = DecisionBody;

        const TSharedPtr<FCkUiView> CurrentView = State->Panel->Get_AuthoredView();
        if (CurrentView.IsValid())
        {
            const int64 Revision = CurrentView->GetRevision();
            const TSharedPtr<SWidget> BodyBeforePoll = DecisionBody;
            const TSharedPtr<SWidget> NativeBodyBeforePoll = NativeBody;
            State->bNoChangePollStable = !CurrentView->PollFiles()
                && CurrentView->GetRevision() == Revision
                && State->Panel->Get_AuthoredView() == CurrentView
                && FindTagged(State->Panel.ToSharedRef(), TEXT("decision-body")) == BodyBeforePoll
                && NativeBodyBeforePoll.IsValid() && BodyBeforePoll->GetChildren()->Num() > 0
                && &ConstCastSharedRef<SWidget>(BodyBeforePoll->GetChildren()->GetChildAt(0)).Get() == NativeBodyBeforePoll.Get();
        }
    })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*)
    {
        if (!State->Panel.IsValid() || !State->Window.IsValid())
        {
            return;
        }

        FSlateApplication& LocalSlate = FSlateApplication::Get();
        State->Window->Resize(FVector2D{1400.0f, 800.0f});
        Tick(LocalSlate);
        State->bWideCapture = SaveCapture(LocalSlate, State->Window.ToSharedRef(),
            FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Automation/GoapDebugger/DecisionAuthoredPie-Wide.png")));
        State->Window->Resize(FVector2D{480.0f, 700.0f});
        Tick(LocalSlate);
        State->bNarrowCapture = SaveCapture(LocalSlate, State->Window.ToSharedRef(),
            FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Automation/GoapDebugger/DecisionAuthoredPie-Narrow.png")));

        const TSharedPtr<FCkUiView> CurrentView = State->Panel->Get_AuthoredView();
        const TSharedPtr<SWidget> DecisionBody = FindTagged(State->Panel.ToSharedRef(), TEXT("decision-body"));
        if (CurrentView.IsValid() && DecisionBody.IsValid())
        {
            const int64 Revision = CurrentView->GetRevision();
            TSharedPtr<SWidget> NativeBody;
            if (DecisionBody->GetChildren() != nullptr && DecisionBody->GetChildren()->Num() > 0)
            {
                NativeBody = ConstCastSharedRef<SWidget>(DecisionBody->GetChildren()->GetChildAt(0));
            }
            const FCkUiLoadResult Rejected = CurrentView->TryReload(
                TEXT("<ui version=\"1\"><region name=\"main\"><unknown /></region></ui>"),
                TEXT(""), TEXT("DecisionAuthoredPie-invalid"));
            State->bRejectedReloadRetained = !Rejected.Succeeded && CurrentView->GetRevision() == Revision
                && State->Panel->Get_AuthoredView() == CurrentView
                && FindTagged(State->Panel.ToSharedRef(), TEXT("decision-body")) == DecisionBody
                && NativeBody.IsValid() && DecisionBody->GetChildren() != nullptr && DecisionBody->GetChildren()->Num() > 0
                && &ConstCastSharedRef<SWidget>(DecisionBody->GetChildren()->GetChildAt(0)).Get() == NativeBody.Get();
        }
    })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld*)
    {
        TestTrue(TEXT("GOAP Decision mounts the authored empty shell before any planner is selected"), State->bEmptyContractReady);
        TestTrue(TEXT("GOAP Decision selects and projects a live FallbackVsChain planner through authored title, status, and native body port"),
            State->bProjectionReady && State->bSelectedContractReady);
        TestTrue(TEXT("GOAP Decision unchanged authored file poll retains the accepted view and native decision body identity"), State->bNoChangePollStable);
        TestTrue(TEXT("GOAP Decision rejected authored reload retains the accepted view and native decision body"), State->bRejectedReloadRetained);
        TestTrue(TEXT("GOAP Decision captures wide and narrow mounted production surfaces"), State->bWideCapture && State->bNarrowCapture);

        if (State->Panel.IsValid() && State->ViewModel.IsValid())
        {
            State->ViewModel->Reset_ForWorldChange();
            State->Panel->Reset_ForWorldChange();
            Tick(FSlateApplication::Get());
            State->bResetEmpty = !State->Panel->Get_AuthoredView().IsValid() && !State->WeakDecisionBody.IsValid();
        }
        TestTrue(TEXT("GOAP Decision reset clears the authored shell and releases its native body port"), State->bResetEmpty);

        if (FSlateApplication::IsInitialized() && State->Window.IsValid())
        {
            FSlateApplication::Get().DestroyWindowImmediately(State->Window.ToSharedRef());
        }
        State->Window.Reset();
        State->Panel.Reset();
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
        State->bTornDown = !State->WeakPanel.IsValid() && !State->WeakView.IsValid();
        TestTrue(TEXT("GOAP Decision teardown releases the authored view and panel"), State->bTornDown);
    })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif
