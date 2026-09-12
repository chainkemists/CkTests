#include "CoreMinimal.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkGoapDebugger/ViewModel/CkGoapDebugger_ViewModel.h"
#include "CkGoapDebugger/Window/SCkGoapDebugger_WorldStateRail.h"

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
#include "Widgets/SNullWidget.h"
#include "Widgets/Text/STextBlock.h"

namespace ck_tests_goap_debugger_world_state_authored_pie
{
    constexpr auto TestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;
    const FName FixtureClassName{TEXT("Ck_Goap_Planner_SquadRosterPieFixture")};

    struct FState final
    {
        TWeakObjectPtr<AActor> Fixture;
        TSharedPtr<FCkGoapDebugger_ViewModel> ViewModel;
        TSharedPtr<SCkGoapDebugger_WorldStateRail> Rail;
        TSharedPtr<SWindow> Window;
        TWeakPtr<SCkGoapDebugger_WorldStateRail> WeakRail;
        TWeakPtr<FCkUiView> WeakView;
        TWeakPtr<SWidget> WeakBody;
        FString ExpectedTitle;
        FString ExpectedCount;
        bool bFixtureSpawned = false;
        bool bEmptyContract = false;
        bool bProjectionReady = false;
        bool bMountedContract = false;
        bool bNoChangeReloadRetained = false;
        bool bRejectedReloadRetained = false;
        bool bDeselectionRetainsShell = false;
        bool bWideCapture = false;
        bool bNarrowCapture = false;
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
        if (InRoot->GetTag() == InTag) { return InRoot; }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SWidget> Found = FindTagged(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag); Found.IsValid())
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

    auto SaveCapture(FSlateApplication& InSlate, const TSharedRef<SWidget>& InRoot, const FString& InPath) -> bool
    {
        TArray<FColor> Pixels;
        FIntVector Size = FIntVector::ZeroValue;
        if (!InSlate.TakeScreenshot(InRoot, Pixels, Size) || Size.X <= 0 || Size.Y <= 0 || Pixels.Num() < Size.X * Size.Y)
        { return false; }
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
        if (!IsValid(Fixture) || !InState->ViewModel.IsValid() || !InState->Rail.IsValid()) { return; }
        InState->ViewModel->Tick(Fixture->GetWorld());
        InState->Rail->RefreshFromViewModel();
        Tick(FSlateApplication::Get());
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkGoapDebugger_WorldStateAuthoredPie,
    "Ck.GoapDebugger.WorldState.Authored.PIE",
    ck_tests_goap_debugger_world_state_authored_pie::TestFlags)

bool FCkGoapDebugger_WorldStateAuthoredPie::RunTest(const FString&)
{
    using namespace ck_tests_goap_debugger_world_state_authored_pie;
    if (!FSlateApplication::IsInitialized())
    {
        AddError(TEXT("GOAP World State authored PIE test requires Slate."));
        return false;
    }

    const TSharedRef<FState> State = MakeShared<FState>();
    FSlateApplication& Slate = FSlateApplication::Get();
    State->ViewModel = MakeShared<FCkGoapDebugger_ViewModel>();
    State->Rail = SNew(SCkGoapDebugger_WorldStateRail).ViewModel(State->ViewModel);
    State->WeakRail = State->Rail;
    State->Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{1100.0f, 700.0f})
        .CreateTitleBar(false).HasCloseButton(false)[State->Rail.ToSharedRef()];
    Slate.AddWindow(State->Window.ToSharedRef(), true);
    Tick(Slate);

    {
        const TSharedPtr<FCkUiView> InitialView = State->Rail->Get_AuthoredView();
        State->WeakView = InitialView;
        if (!InitialView.IsValid() || !InitialView->GetLastResult().Succeeded)
        {
            AddError(FString::Printf(TEXT("Production World State authored surface did not mount: %s"), *State->Rail->Get_AuthoredLoadFailure()));
            return false;
        }
    }
    const TSharedPtr<SWidget> Empty = FindTagged(State->Rail.ToSharedRef(), TEXT("goap-world-empty"));
    const TSharedPtr<SWidget> Selected = FindTagged(State->Rail.ToSharedRef(), TEXT("goap-world-selected"));
    State->bEmptyContract = Empty.IsValid() && Selected.IsValid() && Empty->GetVisibility().IsVisible()
        && !Selected->GetVisibility().IsVisible() && ContainsText(Empty.ToSharedRef(), TEXT("Select an agent"));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld* World)
    {
        if (UClass* FixtureClass = FindFixtureClass(); IsValid(World) && FixtureClass != nullptr)
        { State->Fixture = World->SpawnActor<AActor>(FixtureClass, FTransform::Identity); State->bFixtureSpawned = State->Fixture.IsValid(); }
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
        State->ViewModel->SetSelectedActionSet(Snapshot->TopLevelPlanners[0].PlannerHandle);
        Refresh(State);
        const FCkGoapDebugger_ActionSetInfo* ActionSet = State->ViewModel->GetSelectedActionSetInfo();
        if (ActionSet == nullptr || ActionSet->WorldState.IsEmpty()) { return false; }
        State->ExpectedTitle = ActionSet->WorldStateSourceLabel.IsEmpty() ? TEXT("World State") : ActionSet->WorldStateSourceLabel;
        State->ExpectedCount = FString::Printf(TEXT("%d keys"), ActionSet->WorldState.Num());
        State->bProjectionReady = true;
        return true;
    }), 15.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*)
    {
        const TSharedPtr<SWidget> Selected = FindTagged(State->Rail.ToSharedRef(), TEXT("goap-world-selected"));
        const TSharedPtr<SWidget> Title = FindTagged(State->Rail.ToSharedRef(), TEXT("goap-world-title"));
        const TSharedPtr<SWidget> Count = FindTagged(State->Rail.ToSharedRef(), TEXT("goap-world-count"));
        const TSharedPtr<SWidget> Body = FindTagged(State->Rail.ToSharedRef(), TEXT("goap-world-body"));
        State->WeakBody = Body;
        State->bMountedContract = Selected.IsValid() && Title.IsValid() && Count.IsValid() && Body.IsValid()
            && Selected->GetVisibility().IsVisible() && ContainsText(Title.ToSharedRef(), State->ExpectedTitle)
            && ContainsText(Count.ToSharedRef(), State->ExpectedCount) && Body->GetChildren()->Num() > 0
            && FindType(Body.ToSharedRef(), TEXT("SScrollBox")).IsValid();

        const TSharedPtr<FCkUiView> View = State->Rail->Get_AuthoredView();
        if (View.IsValid() && Body.IsValid())
        {
            const int64 Revision = View->GetRevision();
            TSharedPtr<SWidget> NativeBefore;
            if (Body->GetChildren()->Num() > 0)
            {
                NativeBefore = ConstCastSharedRef<SWidget>(Body->GetChildren()->GetChildAt(0));
            }
            State->bNoChangeReloadRetained = !View->PollFiles() && View->GetRevision() == Revision
                && State->Rail->Get_AuthoredView() == View && FindTagged(State->Rail.ToSharedRef(), TEXT("goap-world-body")) == Body
                && NativeBefore.IsValid() && Body->GetChildren()->Num() > 0
                && &ConstCastSharedRef<SWidget>(Body->GetChildren()->GetChildAt(0)).Get() == NativeBefore.Get();
            const FCkUiLoadResult Rejected = View->TryReload(TEXT("<ui version=\"1\"><region name=\"main\"><unknown /></region></ui>"), TEXT(""), TEXT("WorldStateAuthoredPie-invalid"));
            State->bRejectedReloadRetained = !Rejected.Succeeded && View->GetRevision() == Revision
                && State->Rail->Get_AuthoredView() == View && FindTagged(State->Rail.ToSharedRef(), TEXT("goap-world-body")) == Body
                && NativeBefore.IsValid() && Body->GetChildren()->Num() > 0
                && &ConstCastSharedRef<SWidget>(Body->GetChildren()->GetChildAt(0)).Get() == NativeBefore.Get();
        }
    })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*)
    {
        State->Window->Resize(FVector2D{1400.0f, 800.0f}); Tick(FSlateApplication::Get());
        State->bWideCapture = SaveCapture(FSlateApplication::Get(), State->Window.ToSharedRef(), FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Automation/GoapDebugger/WorldStateAuthoredPie-Wide.png")));
        State->Window->Resize(FVector2D{480.0f, 700.0f}); Tick(FSlateApplication::Get());
        State->bNarrowCapture = SaveCapture(FSlateApplication::Get(), State->Window.ToSharedRef(), FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Automation/GoapDebugger/WorldStateAuthoredPie-Narrow.png")));
    })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*)
    {
        const TSharedPtr<FCkUiView> View = State->Rail->Get_AuthoredView();
        const TSharedPtr<SWidget> Body = FindTagged(State->Rail.ToSharedRef(), TEXT("goap-world-body"));
        State->ViewModel->SetSelectedActionSet(FCk_Handle_Goap_Planner{});
        State->Rail->RefreshFromViewModel(); Tick(FSlateApplication::Get());
        const TSharedPtr<SWidget> Empty = FindTagged(State->Rail.ToSharedRef(), TEXT("goap-world-empty"));
        const TSharedPtr<SWidget> Selected = FindTagged(State->Rail.ToSharedRef(), TEXT("goap-world-selected"));
        auto NativePort = TSharedPtr<SWidget>{};
        if (Body.IsValid() && Body->GetChildren()->Num() == 1)
        { NativePort = ConstCastSharedRef<SWidget>(Body->GetChildren()->GetChildAt(0)); }
        const bool bNativePortCleared = NativePort.IsValid() && NativePort->GetChildren()->Num() == 1
            && NativePort->GetChildren()->GetChildAt(0) == SNullWidget::NullWidget;
        State->bDeselectionRetainsShell = View.IsValid() && Body.IsValid() && State->Rail->Get_AuthoredView() == View
            && FindTagged(State->Rail.ToSharedRef(), TEXT("goap-world-body")) == Body && bNativePortCleared
            && Empty.IsValid() && Empty->GetVisibility().IsVisible() && Selected.IsValid() && !Selected->GetVisibility().IsVisible();
    })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld*)
    {
        TestTrue(TEXT("GOAP World State installs the authored resource and exposes its empty contract"), State->bEmptyContract);
        TestTrue(TEXT("GOAP World State projects the real squad fixture ActionSet"), State->bFixtureSpawned && State->bProjectionReady);
        TestTrue(TEXT("GOAP World State mounts exact title/count bindings and the complete native scroll body"), State->bMountedContract);
        TestTrue(TEXT("GOAP World State compatible poll retains the accepted view and native body"), State->bNoChangeReloadRetained);
        TestTrue(TEXT("GOAP World State rejected reload retains live authored state and native body"), State->bRejectedReloadRetained);
        TestTrue(TEXT("GOAP World State captures wide and narrow production surfaces"), State->bWideCapture && State->bNarrowCapture);
        TestTrue(TEXT("GOAP World State deselection preserves the shell and clears its native port"), State->bDeselectionRetainsShell);

        State->Rail->Reset_ForWorldChange();
        State->ViewModel->Reset_ForWorldChange();
        Tick(FSlateApplication::Get());
        State->bResetReleased = !State->Rail->Get_AuthoredView().IsValid() && !State->WeakBody.IsValid();
        TestTrue(TEXT("GOAP World State reset releases the authored view port before registry teardown"), State->bResetReleased);
        FSlateApplication::Get().DestroyWindowImmediately(State->Window.ToSharedRef());
        State->Window.Reset(); State->Rail.Reset(); State->ViewModel.Reset(); Tick(FSlateApplication::Get());
        if (State->Fixture.IsValid()) { State->Fixture->Destroy(); }
        State->Fixture.Reset();
        State->bTornDown = !State->WeakRail.IsValid() && !State->WeakView.IsValid();
        TestTrue(TEXT("GOAP World State releases retained authored callbacks after teardown"), State->bTornDown);
    })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif
