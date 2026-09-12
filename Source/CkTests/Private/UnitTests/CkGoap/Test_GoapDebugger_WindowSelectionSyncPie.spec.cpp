#include "CoreMinimal.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkGoapDebugger/ViewModel/CkGoapDebugger_ViewModel.h"
#include "CkGoapDebugger/Window/SCkGoapDebuggerWindow.h"

#include "CkCore/Validation/CkIsValid.h"
#include "CkDebuggerCommon/Navigation/CkDebug_SelectionSync.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include "Engine/World.h"
#include "Framework/Application/SlateApplication.h"
#include "GameFramework/Actor.h"
#include "Misc/AutomationTest.h"
#include "UObject/UObjectIterator.h"
#include "Widgets/SWindow.h"

namespace ck_tests_goap_debugger_window_selection_sync_pie
{
    constexpr auto TestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;
    const FName FixtureClassName{TEXT("Ck_Goap_Planner_SquadRosterPieFixture")};

    struct FState final
    {
        TWeakObjectPtr<AActor> FirstFixture;
        TWeakObjectPtr<AActor> SecondFixture;
        TSharedPtr<SCkGoapDebuggerWindow> Debugger;
        TSharedPtr<SWindow> Host;
        TWeakPtr<SCkGoapDebuggerWindow> WeakDebugger;
        FCk_Handle InitialSelection;
        FCk_Handle ExternalSelection;
        bool bRosterReady = false;
        bool bExternalSelectionApplied = false;
        bool bSelfSourceIgnored = false;
        bool bTornDown = false;
    };

    auto Tick(FSlateApplication& InSlate) -> void
    {
        InSlate.PumpMessages();
        InSlate.Tick();
        InSlate.Tick();
    }

    auto FindFixtureClass() -> UClass*
    {
        for (TObjectIterator<UClass> It; It; ++It)
        {
            if (It->GetFName() == FixtureClassName && It->IsChildOf(AActor::StaticClass())) { return *It; }
        }
        return nullptr;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkGoapDebugger_WindowSelectionSyncPie,
    "Ck.UiAuthoring.GoapDebugger.Window.SelectionSync.PIE",
    ck_tests_goap_debugger_window_selection_sync_pie::TestFlags)

auto FCkGoapDebugger_WindowSelectionSyncPie::RunTest(const FString&) -> bool
{
    using namespace ck_tests_goap_debugger_window_selection_sync_pie;

    if (!FSlateApplication::IsInitialized())
    {
        AddError(TEXT("GOAP window selection-sync test requires Slate."));
        return false;
    }

    const TSharedRef<FState> State = MakeShared<FState>();
    State->Debugger = SNew(SCkGoapDebuggerWindow);
    State->WeakDebugger = State->Debugger;
    State->Host = SNew(SWindow)
        .AutoCenter(EAutoCenter::None)
        .ClientSize(FVector2D{1100.0f, 700.0f})
        .CreateTitleBar(false)
        .HasCloseButton(false)
        [State->Debugger.ToSharedRef()];
    FSlateApplication::Get().AddWindow(State->Host.ToSharedRef(), true);
    Tick(FSlateApplication::Get());

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [State](UWorld* World)
        {
            if (UClass* FixtureClass = FindFixtureClass(); IsValid(World) && FixtureClass != nullptr)
            {
                State->FirstFixture = World->SpawnActor<AActor>(FixtureClass, FTransform::Identity);
                State->SecondFixture = World->SpawnActor<AActor>(FixtureClass, FTransform(FVector{200.0f, 0.0f, 0.0f}));
            }
        })));
    for (int32 Pass = 0; Pass < 120; ++Pass)
    {
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(1));
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
            [](UWorld*) { Tick(FSlateApplication::Get()); })));
    }
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Condition::CreateLambda([State]
        {
            Tick(FSlateApplication::Get());
            const TSharedPtr<FCkGoapDebugger_ViewModel> ViewModel = State->Debugger.IsValid()
                ? State->Debugger->_ViewModel
                : nullptr;
            if (!ViewModel.IsValid() || ViewModel->Get_Roster().Num() != 2) { return false; }

            State->InitialSelection = ViewModel->GetSelectedEntity();
            if (ck::Is_NOT_Valid(State->InitialSelection)) { return false; }
            const FCkGoapDebugger_RosterEntry* Other = ViewModel->Get_Roster().FindByPredicate(
                [State](const FCkGoapDebugger_RosterEntry& InEntry)
                { return InEntry.EntityHandle != State->InitialSelection; });
            if (Other == nullptr || ck::Is_NOT_Valid(Other->EntityHandle)) { return false; }
            State->ExternalSelection = Other->EntityHandle;
            State->bRosterReady = true;
            return true;
        }),
        15.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [State](UWorld*)
        {
            if (!State->bRosterReady) { return; }
            ck::DebugSelectionSync::Broadcast(State->ExternalSelection, TEXT("ExternalWindowSelectionSyncTest"));
            Tick(FSlateApplication::Get());
            const TSharedPtr<FCkGoapDebugger_ViewModel> ViewModel = State->Debugger->_ViewModel;
            State->bExternalSelectionApplied = ViewModel.IsValid()
                && ViewModel->GetSelectedEntity() == State->ExternalSelection;

            ck::DebugSelectionSync::Broadcast(State->InitialSelection, TEXT("GoapDebugger"));
            Tick(FSlateApplication::Get());
            State->bSelfSourceIgnored = ViewModel.IsValid()
                && ViewModel->GetSelectedEntity() == State->ExternalSelection;
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, State](UWorld*)
        {
            TestTrue(TEXT("Production GOAP window acquires a two-agent roster"), State->bRosterReady);
            TestTrue(TEXT("External same-lineage selection updates the production GOAP window"),
                State->bExternalSelectionApplied);
            TestTrue(TEXT("GOAP-originated selection does not echo back into its own window"),
                State->bSelfSourceIgnored);

            FSlateApplication::Get().DestroyWindowImmediately(State->Host.ToSharedRef());
            State->Host.Reset();
            State->Debugger.Reset();
            Tick(FSlateApplication::Get());
            State->bTornDown = !State->WeakDebugger.IsValid();
            TestTrue(TEXT("GOAP window releases its selection-sync subscriber before PIE teardown"),
                State->bTornDown);

            if (State->FirstFixture.IsValid()) { State->FirstFixture->Destroy(); }
            if (State->SecondFixture.IsValid()) { State->SecondFixture->Destroy(); }
            State->FirstFixture.Reset();
            State->SecondFixture.Reset();
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif
