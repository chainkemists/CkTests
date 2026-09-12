#include "CoreMinimal.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkGoapDebugger/ViewModel/CkGoapDebugger_ViewModel.h"
#include "CkGoapDebugger/Window/SCkGoapDebugger_GraphPane.h"
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
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"

namespace ck_tests_goap_debugger_graph_authored_pie
{
constexpr auto TestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;
const FName FixtureClassName{TEXT("Ck_Goap_Planner_SquadRosterPieFixture")};
struct FState final
{
    TWeakObjectPtr<AActor> Fixture;
    TSharedPtr<FCkGoapDebugger_ViewModel> ViewModel;
    TSharedPtr<SCkGoapDebugger_GraphPane> Pane;
    TSharedPtr<SWindow> Window;
    TWeakPtr<SCkGoapDebugger_GraphPane> WeakPane;
    TWeakPtr<FCkUiView> WeakView;
    TWeakPtr<SWidget> WeakBody;
    FString ExpectedTitle;
    bool bFixtureSpawned = false, bEmpty = false, bProjection = false, bMounted = false;
    bool bCompatibleReload = false, bRejectedReload = false, bDeselection = false;
    bool bWideCapture = false, bNarrowCapture = false, bResetReleased = false, bTornDown = false;
};
auto Tick(FSlateApplication& Slate) -> void { Slate.PumpMessages(); Slate.Tick(); Slate.Tick(); }
auto FindTagged(const TSharedRef<SWidget>& Root, const FName Tag) -> TSharedPtr<SWidget>
{
    if (Root->GetTag() == Tag) { return Root; }
    const FChildren* Children = Root->GetChildren();
    for (int32 I = 0; Children != nullptr && I < Children->Num(); ++I)
        if (const TSharedPtr<SWidget> Found = FindTagged(ConstCastSharedRef<SWidget>(Children->GetChildAt(I)), Tag); Found.IsValid()) { return Found; }
    return {};
}
auto FindType(const TSharedRef<SWidget>& Root, const FString& Type) -> TSharedPtr<SWidget>
{
    if (Root->GetTypeAsString() == Type) { return Root; }
    const FChildren* Children = Root->GetChildren();
    for (int32 I = 0; Children != nullptr && I < Children->Num(); ++I)
        if (const TSharedPtr<SWidget> Found = FindType(ConstCastSharedRef<SWidget>(Children->GetChildAt(I)), Type); Found.IsValid()) { return Found; }
    return {};
}
auto ContainsText(const TSharedRef<SWidget>& Root, const FString& Text) -> bool
{
    if (Root->GetTypeAsString() == TEXT("STextBlock") && StaticCastSharedRef<STextBlock>(Root)->GetText().ToString().Contains(Text)) { return true; }
    if (Root->GetTypeAsString() == TEXT("SCkFlexText") && StaticCastSharedRef<SCkFlexText>(Root)->GetText().ToString().Contains(Text)) { return true; }
    const FChildren* Children = Root->GetChildren();
    for (int32 I = 0; Children != nullptr && I < Children->Num(); ++I)
        if (ContainsText(ConstCastSharedRef<SWidget>(Children->GetChildAt(I)), Text)) { return true; }
    return false;
}
auto SaveCapture(FSlateApplication& Slate, const TSharedRef<SWidget>& Root, const FString& Path) -> bool
{
    TArray<FColor> Pixels; FIntVector Size = FIntVector::ZeroValue;
    if (!Slate.TakeScreenshot(Root, Pixels, Size) || Size.X <= 0 || Size.Y <= 0 || Pixels.Num() < Size.X * Size.Y) { return false; }
    IFileManager::Get().MakeDirectory(*FPaths::GetPath(Path), true);
    return FImageUtils::SaveImageByExtension(*Path, FImageView(Pixels.GetData(), Size.X, Size.Y, ERawImageFormat::BGRA8));
}
auto FindFixtureClass() -> UClass*
{
    for (TObjectIterator<UClass> It; It; ++It)
        if (It->GetFName() == FixtureClassName && It->IsChildOf(AActor::StaticClass())) { return *It; }
    return nullptr;
}
auto Refresh(const TSharedRef<FState>& State) -> void
{
    AActor* Fixture = State->Fixture.Get();
    if (!IsValid(Fixture) || !State->ViewModel.IsValid() || !State->Pane.IsValid()) { return; }
    State->ViewModel->Tick(Fixture->GetWorld()); State->Pane->RefreshFromViewModel(); Tick(FSlateApplication::Get());
}
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkGoapDebugger_GraphAuthoredPie, "Ck.GoapDebugger.Graph.Authored.PIE", ck_tests_goap_debugger_graph_authored_pie::TestFlags)
bool FCkGoapDebugger_GraphAuthoredPie::RunTest(const FString&)
{
    using namespace ck_tests_goap_debugger_graph_authored_pie;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("GOAP Graph authored PIE test requires Slate.")); return false; }
    const TSharedRef<FState> State = MakeShared<FState>(); FSlateApplication& Slate = FSlateApplication::Get();
    State->ViewModel = MakeShared<FCkGoapDebugger_ViewModel>(); State->Pane = SNew(SCkGoapDebugger_GraphPane).ViewModel(State->ViewModel); State->WeakPane = State->Pane;
    State->Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{1100.0f, 700.0f}).CreateTitleBar(false).HasCloseButton(false)[State->Pane.ToSharedRef()];
    Slate.AddWindow(State->Window.ToSharedRef(), true); Tick(Slate);
    { const TSharedPtr<FCkUiView> View = State->Pane->Get_AuthoredView(); State->WeakView = View;
      if (!View.IsValid() || !View->GetLastResult().Succeeded) { AddError(FString::Printf(TEXT("Production Graph authored surface did not mount: %s"), *State->Pane->Get_AuthoredLoadFailure())); return false; } }
    const TSharedPtr<SWidget> Empty = FindTagged(State->Pane.ToSharedRef(), TEXT("goap-graph-empty")); const TSharedPtr<SWidget> Selected = FindTagged(State->Pane.ToSharedRef(), TEXT("goap-graph-selected"));
    State->bEmpty = Empty.IsValid() && Selected.IsValid() && Empty->GetVisibility().IsVisible() && !Selected->GetVisibility().IsVisible();
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(1));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*)
    {
        Tick(FSlateApplication::Get());
        const TSharedPtr<SWidget> Empty = FindTagged(State->Pane.ToSharedRef(), TEXT("goap-graph-empty"));
        const TSharedPtr<SWidget> Selected = FindTagged(State->Pane.ToSharedRef(), TEXT("goap-graph-selected"));
        State->bEmpty = Empty.IsValid() && Selected.IsValid() && Empty->GetVisibility().IsVisible() && !Selected->GetVisibility().IsVisible();
    })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld* World)
    { if (UClass* C = FindFixtureClass(); IsValid(World) && C != nullptr) { State->Fixture = World->SpawnActor<AActor>(C, FTransform::Identity); State->bFixtureSpawned = State->Fixture.IsValid(); } })));
    for (int32 Pass = 0; Pass < 120; ++Pass) { ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(1)); ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) { Refresh(State); }))); }
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    {
        Refresh(State); const auto& Roster = State->ViewModel->Get_Roster(); if (Roster.IsEmpty()) { return false; }
        State->ViewModel->SetSelectedEntity(Roster[0].EntityHandle); const FCkGoapDebugger_EntitySnapshot* Snapshot = State->ViewModel->GetCurrentEntitySnapshot();
        if (Snapshot == nullptr || Snapshot->TopLevelPlanners.IsEmpty()) { return false; }
        State->ViewModel->SetSelectedActionSet(Snapshot->TopLevelPlanners[0].PlannerHandle); Refresh(State);
        const FCkGoapDebugger_PlannerInfo* Planner = State->ViewModel->GetSelectedPlannerInfo(); if (Planner == nullptr || Planner->ChildActions.IsEmpty()) { return false; }
        State->ExpectedTitle = FString::Printf(TEXT("Action graph: %s"), *Planner->DisplayName);
        State->bProjection = true; return true;
    }), 15.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(1));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*)
    {
        const TSharedPtr<SWidget> Selected = FindTagged(State->Pane.ToSharedRef(), TEXT("goap-graph-selected")); const TSharedPtr<SWidget> Title = FindTagged(State->Pane.ToSharedRef(), TEXT("goap-graph-title"));
        const TSharedPtr<SWidget> Status = FindTagged(State->Pane.ToSharedRef(), TEXT("goap-graph-status")); const TSharedPtr<SWidget> Body = FindTagged(State->Pane.ToSharedRef(), TEXT("graph-body")); State->WeakBody = Body;
        const TSharedPtr<SWidget> Canvas = Body.IsValid() ? FindType(Body.ToSharedRef(), TEXT("SCkDebug_GraphCanvas")) : nullptr;
        State->bMounted = Selected.IsValid() && Title.IsValid() && Status.IsValid() && Body.IsValid() && Selected->GetVisibility().IsVisible() && ContainsText(Title.ToSharedRef(), State->ExpectedTitle)
            && ContainsText(Status.ToSharedRef(), TEXT("actions")) && ContainsText(Status.ToSharedRef(), TEXT("edges"))
            && FindType(Body.ToSharedRef(), TEXT("SButton")).IsValid() && Canvas.IsValid()
            && !Body->GetCachedGeometry().GetLocalSize().IsNearlyZero() && !Canvas->GetCachedGeometry().GetLocalSize().IsNearlyZero();
        const TSharedPtr<FCkUiView> View = State->Pane->Get_AuthoredView(); if (!View.IsValid() || !Body.IsValid()) { return; }
        const int64 Revision = View->GetRevision();
        TSharedPtr<SWidget> Native;
        if (Body->GetChildren()->Num() > 0)
        {
            Native = ConstCastSharedRef<SWidget>(Body->GetChildren()->GetChildAt(0));
        }
        State->bCompatibleReload = !View->PollFiles() && View->GetRevision() == Revision && State->Pane->Get_AuthoredView() == View && Native.IsValid() && Body->GetChildren()->Num() > 0 && &ConstCastSharedRef<SWidget>(Body->GetChildren()->GetChildAt(0)).Get() == Native.Get();
        const FCkUiLoadResult Rejected = View->TryReload(TEXT("<ui version=\"1\"><region name=\"main\"><unknown /></region></ui>"), TEXT(""), TEXT("GraphAuthoredPie-invalid"));
        State->bRejectedReload = !Rejected.Succeeded && View->GetRevision() == Revision && State->Pane->Get_AuthoredView() == View && Native.IsValid() && Body->GetChildren()->Num() > 0 && &ConstCastSharedRef<SWidget>(Body->GetChildren()->GetChildAt(0)).Get() == Native.Get();
    })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*)
    { State->Window->Resize(FVector2D{1400.0f, 800.0f}); Tick(FSlateApplication::Get()); State->bWideCapture = SaveCapture(FSlateApplication::Get(), State->Window.ToSharedRef(), FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Automation/GoapDebugger/GraphAuthoredPie-Wide.png")));
      State->Window->Resize(FVector2D{480.0f, 700.0f}); Tick(FSlateApplication::Get()); State->bNarrowCapture = SaveCapture(FSlateApplication::Get(), State->Window.ToSharedRef(), FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Automation/GoapDebugger/GraphAuthoredPie-Narrow.png")));
      const TSharedPtr<SWidget> FinalBody = FindTagged(State->Pane.ToSharedRef(), TEXT("graph-body"));
      const TSharedPtr<SWidget> FinalCanvas = FinalBody.IsValid() ? FindType(FinalBody.ToSharedRef(), TEXT("SCkDebug_GraphCanvas")) : nullptr;
      State->bMounted = State->bMounted && FinalBody.IsValid() && FinalCanvas.IsValid()
          && FinalBody->GetCachedGeometry().GetLocalSize().Y > 200.0f && FinalCanvas->GetCachedGeometry().GetLocalSize().Y > 150.0f; })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*)
    { State->ViewModel->SetSelectedActionSet(FCk_Handle_Goap_Planner{}); State->Pane->RefreshFromViewModel(); Tick(FSlateApplication::Get()); })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(1));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*)
    { const TSharedPtr<FCkUiView> View = State->Pane->Get_AuthoredView(); const TSharedPtr<SWidget> Body = FindTagged(State->Pane.ToSharedRef(), TEXT("graph-body"));
      const TSharedPtr<SWidget> Empty = FindTagged(State->Pane.ToSharedRef(), TEXT("goap-graph-empty")); const TSharedPtr<SWidget> Selected = FindTagged(State->Pane.ToSharedRef(), TEXT("goap-graph-selected"));
      State->bDeselection = View.IsValid() && Body.IsValid() && State->Pane->Get_AuthoredView() == View && Empty.IsValid() && Empty->GetVisibility().IsVisible() && Selected.IsValid() && !Selected->GetVisibility().IsVisible(); })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld*)
    {
        TestTrue(TEXT("GOAP Graph installs its authored resource and empty projection"), State->bEmpty);
        TestTrue(TEXT("GOAP Graph projects the real selected squad planner"), State->bFixtureSpawned && State->bProjection);
        TestTrue(TEXT("GOAP Graph mounts exact title/status and native toolbar canvas geometry"), State->bMounted);
        TestTrue(TEXT("GOAP Graph compatible poll retains accepted view and native graph identity"), State->bCompatibleReload);
        TestTrue(TEXT("GOAP Graph rejected reload retains accepted view and native graph identity"), State->bRejectedReload);
        TestTrue(TEXT("GOAP Graph captures wide and narrow production surfaces"), State->bWideCapture && State->bNarrowCapture);
        TestTrue(TEXT("GOAP Graph deselection preserves its authored shell"), State->bDeselection);
        State->Pane->Reset_ForWorldChange(); State->ViewModel->Reset_ForWorldChange(); Tick(FSlateApplication::Get());
        State->bResetReleased = !State->Pane->Get_AuthoredView().IsValid();
        TestTrue(TEXT("GOAP Graph reset releases its authored view before native graph teardown"), State->bResetReleased);
    })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(1));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld*)
    {
        State->bResetReleased = State->bResetReleased && !State->WeakBody.IsValid() && !State->WeakView.IsValid();
        TestTrue(TEXT("GOAP Graph reset releases its authored view and port after Slate deferred lifetime"), State->bResetReleased);
        State->Pane->Resume_AfterWorldChange();
        State->ViewModel->Broadcast_Changed(); Tick(FSlateApplication::Get());
        State->WeakView = State->Pane->Get_AuthoredView();
        TestTrue(TEXT("GOAP Graph remounts after the world-change subscription resumes"), State->WeakView.IsValid());
        State->Pane->Reset_ForWorldChange(); State->ViewModel->Reset_ForWorldChange(); Tick(FSlateApplication::Get());
        FSlateApplication::Get().DestroyWindowImmediately(State->Window.ToSharedRef()); State->Window.Reset(); State->Pane.Reset(); State->ViewModel.Reset(); Tick(FSlateApplication::Get()); if (State->Fixture.IsValid()) { State->Fixture->Destroy(); } State->Fixture.Reset(); State->bTornDown = !State->WeakPane.IsValid() && !State->WeakView.IsValid();
        TestTrue(TEXT("GOAP Graph teardown releases retained authored callbacks"), State->bTornDown);
    })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE()); return true;
}
#endif
