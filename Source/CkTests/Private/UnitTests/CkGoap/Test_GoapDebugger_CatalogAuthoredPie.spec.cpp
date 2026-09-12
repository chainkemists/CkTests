#include "CoreMinimal.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkGoapDebugger/ViewModel/CkGoapDebugger_ViewModel.h"
#include "CkGoapDebugger/Window/SCkGoapDebugger_CatalogPanel.h"

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

namespace ck_tests_goap_debugger_catalog_authored_pie
{
    constexpr auto TestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;
    const FName FixtureClassName{TEXT("Ck_Goap_Planner_SquadRosterPieFixture")};

    struct FState final
    {
        TWeakObjectPtr<AActor> Fixture;
        TSharedPtr<FCkGoapDebugger_ViewModel> ViewModel;
        TSharedPtr<SCkGoapDebugger_CatalogPanel> Panel;
        TSharedPtr<SWindow> Window;
        TWeakPtr<SCkGoapDebugger_CatalogPanel> WeakPanel;
        TWeakPtr<FCkUiView> WeakView;
        TWeakPtr<SWidget> WeakCatalogPort;
        FString PlannerName;
        FString PlannerStatus;
        bool bFixtureSpawned = false;
        bool bEmpty = false;
        bool bSelected = false;
        bool bStablePoll = false;
        bool bRejectedReload = false;
        bool bDeselected = false;
        bool bWideCapture = false;
        bool bNarrowCapture = false;
        bool bReset = false;
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
            const TSharedPtr<SWidget> Found = FindTagged(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag);
            if (Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto ContainsText(const TSharedRef<SWidget>& InRoot, const FString& InText) -> bool
    {
        if (InRoot->GetTypeAsString() == TEXT("STextBlock")
            && StaticCastSharedRef<STextBlock>(InRoot)->GetText().ToString().Contains(InText)) { return true; }
        if (InRoot->GetTypeAsString() == TEXT("SCkFlexText")
            && StaticCastSharedRef<SCkFlexText>(InRoot)->GetText().ToString().Contains(InText)) { return true; }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        { if (ContainsText(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InText)) { return true; } }
        return false;
    }

    auto FindType(const TSharedRef<SWidget>& InRoot, const FString& InType) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTypeAsString() == InType) { return InRoot; }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            const TSharedPtr<SWidget> Found = FindType(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InType);
            if (Found.IsValid()) { return Found; }
        }
        return {};
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
        { if (It->GetFName() == FixtureClassName && It->IsChildOf(AActor::StaticClass())) { return *It; } }
        return nullptr;
    }

    auto Refresh(const TSharedRef<FState>& InState) -> void
    {
        AActor* Fixture = InState->Fixture.Get();
        if (!IsValid(Fixture) || !InState->ViewModel.IsValid() || !InState->Panel.IsValid()) { return; }
        InState->ViewModel->Tick(Fixture->GetWorld());
        InState->Panel->RefreshFromViewModel();
        Tick(FSlateApplication::Get());
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
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkGoapDebugger_CatalogAuthoredPie, "Ck.GoapDebugger.Catalog.Authored.PIE", ck_tests_goap_debugger_catalog_authored_pie::TestFlags)

bool FCkGoapDebugger_CatalogAuthoredPie::RunTest(const FString&)
{
    using namespace ck_tests_goap_debugger_catalog_authored_pie;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("GOAP Catalog authored PIE test requires Slate.")); return false; }

    const TSharedRef<FState> State = MakeShared<FState>();
    FSlateApplication& Slate = FSlateApplication::Get();
    State->ViewModel = MakeShared<FCkGoapDebugger_ViewModel>();
    State->Panel = SNew(SCkGoapDebugger_CatalogPanel).ViewModel(State->ViewModel);
    State->WeakPanel = State->Panel;
    State->Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{1100.0f, 700.0f}).CreateTitleBar(false).HasCloseButton(false)[State->Panel.ToSharedRef()];
    Slate.AddWindow(State->Window.ToSharedRef(), true);
    Tick(Slate);

    {
        const TSharedPtr<FCkUiView> InitialView = State->Panel->Get_AuthoredView();
        State->WeakView = InitialView;
        if (!InitialView.IsValid() || !InitialView->GetLastResult().Succeeded)
        {
            AddError(FString::Printf(TEXT("Production Catalog authored surface did not mount. Authored load failure: %s"), *State->Panel->Get_AuthoredLoadFailure()));
            Slate.DestroyWindowImmediately(State->Window.ToSharedRef());
            return false;
        }
    }
    const TSharedPtr<SWidget> Empty = FindTagged(State->Panel.ToSharedRef(), TEXT("goap-catalog-empty"));
    const TSharedPtr<SWidget> Selected = FindTagged(State->Panel.ToSharedRef(), TEXT("goap-catalog-selected"));
    State->bEmpty = Empty.IsValid() && Selected.IsValid() && Empty->GetVisibility().IsVisible() && !Selected->GetVisibility().IsVisible();

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
        const FCkGoapDebugger_PlannerInfo* Planner = State->ViewModel->GetSelectedPlannerInfo();
        if (Planner == nullptr || Planner->ChildActions.IsEmpty()) { return false; }
        State->PlannerName = Planner->DisplayName;
        State->PlannerStatus = StatusText(Planner->PlanStatus);
        return State->bFixtureSpawned = true;
    }), 15.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*)
    {
        const TSharedPtr<SWidget> Selected = FindTagged(State->Panel.ToSharedRef(), TEXT("goap-catalog-selected"));
        const TSharedPtr<SWidget> Title = FindTagged(State->Panel.ToSharedRef(), TEXT("goap-catalog-title"));
        const TSharedPtr<SWidget> Status = FindTagged(State->Panel.ToSharedRef(), TEXT("goap-catalog-status"));
        const TSharedPtr<SWidget> Catalog = FindTagged(State->Panel.ToSharedRef(), TEXT("catalog-body"));
        State->WeakCatalogPort = Catalog;
        const auto IsCompletePane = [](const TSharedPtr<SWidget>& Port) -> bool
        {
            const FVector2D Size = Port.IsValid() ? Port->GetCachedGeometry().GetLocalSize() : FVector2D::ZeroVector;
            return Port.IsValid() && Port->GetChildren()->Num() > 0 && FindType(Port.ToSharedRef(), TEXT("SScrollBox")).IsValid()
                && Size.X > 0.0f && Size.Y > 0.0f;
        };
        State->bSelected = Selected.IsValid() && Selected->GetVisibility().IsVisible() && Title.IsValid() && Status.IsValid()
            && ContainsText(Title.ToSharedRef(), FString::Printf(TEXT("Catalog: %s"), *State->PlannerName)) && ContainsText(Status.ToSharedRef(), State->PlannerStatus)
            && IsCompletePane(Catalog) && FindType(Catalog.ToSharedRef(), TEXT("SSplitter")).IsValid();
        TSharedPtr<FCkUiView> View = State->Panel->Get_AuthoredView();
        if (View.IsValid() && Catalog.IsValid())
        {
            const int64 Revision = View->GetRevision();
            TSharedPtr<SWidget> CatalogChild;
            if (Catalog->GetChildren()->Num() > 0)
            {
                CatalogChild = ConstCastSharedRef<SWidget>(Catalog->GetChildren()->GetChildAt(0));
            }
            State->bStablePoll = !View->PollFiles() && View->GetRevision() == Revision && State->Panel->Get_AuthoredView() == View
                && CatalogChild.IsValid() && &ConstCastSharedRef<SWidget>(Catalog->GetChildren()->GetChildAt(0)).Get() == CatalogChild.Get();
            const FCkUiLoadResult Rejected = View->TryReload(TEXT("<ui version=\"1\"><region name=\"main\"><unknown /></region></ui>"), TEXT(""), TEXT("CatalogAuthoredPie-invalid"));
            State->bRejectedReload = !Rejected.Succeeded && View->GetRevision() == Revision && State->Panel->Get_AuthoredView() == View
                && Catalog->GetChildren()->Num() > 0 && &ConstCastSharedRef<SWidget>(Catalog->GetChildren()->GetChildAt(0)).Get() == CatalogChild.Get();
        }
        State->Window->Resize(FVector2D{1400.0f, 800.0f}); Tick(FSlateApplication::Get());
        State->bWideCapture = SaveCapture(FSlateApplication::Get(), State->Window.ToSharedRef(), FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Automation/GoapDebugger/CatalogAuthoredPie-Wide.png")));
        State->Window->Resize(FVector2D{480.0f, 700.0f}); Tick(FSlateApplication::Get());
        State->bNarrowCapture = SaveCapture(FSlateApplication::Get(), State->Window.ToSharedRef(), FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Automation/GoapDebugger/CatalogAuthoredPie-Narrow.png")));
    })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld*)
    {
        {
            const TSharedPtr<FCkUiView> View = State->Panel->Get_AuthoredView();
            State->ViewModel->SetSelectedActionSet(FCk_Handle_Goap_Planner{}); State->Panel->RefreshFromViewModel(); Tick(FSlateApplication::Get());
            const TSharedPtr<SWidget> Empty = FindTagged(State->Panel.ToSharedRef(), TEXT("goap-catalog-empty"));
            const TSharedPtr<SWidget> Selected = FindTagged(State->Panel.ToSharedRef(), TEXT("goap-catalog-selected"));
            State->bDeselected = View.IsValid() && State->Panel->Get_AuthoredView() == View && Empty.IsValid() && Empty->GetVisibility().IsVisible() && Selected.IsValid() && !Selected->GetVisibility().IsVisible();
        }
        TestTrue(TEXT("GOAP Catalog mounts its authored empty shell"), State->bEmpty);
        TestTrue(TEXT("GOAP Catalog projects the live planner title, status, and complete retained splitter body"), State->bSelected);
        TestTrue(TEXT("GOAP Catalog unchanged poll retains accepted view and native splitter body"), State->bStablePoll);
        TestTrue(TEXT("GOAP Catalog rejected reload retains accepted view and native splitter body"), State->bRejectedReload);
        TestTrue(TEXT("GOAP Catalog captures wide and narrow production surfaces"), State->bWideCapture && State->bNarrowCapture);
        TestTrue(TEXT("GOAP Catalog deselection preserves its authored shell"), State->bDeselected);
        State->Panel->Reset_ForWorldChange(); State->ViewModel->Reset_ForWorldChange(); Tick(FSlateApplication::Get());
        State->bReset = !State->Panel->Get_AuthoredView().IsValid() && !State->WeakCatalogPort.IsValid();
        TestTrue(TEXT("GOAP Catalog reset releases authored ports before world teardown"), State->bReset);
        FSlateApplication::Get().DestroyWindowImmediately(State->Window.ToSharedRef()); State->Window.Reset(); State->Panel.Reset(); State->ViewModel.Reset(); Tick(FSlateApplication::Get());
        if (State->Fixture.IsValid()) { State->Fixture->Destroy(); } State->Fixture.Reset();
        State->bTornDown = !State->WeakPanel.IsValid() && !State->WeakView.IsValid();
        TestTrue(TEXT("GOAP Catalog teardown releases retained authored callbacks"), State->bTornDown);
    })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif
