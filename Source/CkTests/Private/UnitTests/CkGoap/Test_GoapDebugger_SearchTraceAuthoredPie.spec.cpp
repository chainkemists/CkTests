#include "CoreMinimal.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkGoapDebugger/ViewModel/CkGoapDebugger_ViewModel.h"
#include "CkGoapDebugger/Window/SCkGoapDebugger_SearchTracePanel.h"

#include "CkEditorTools/Style/CkStyle.h"

#include "CkGoap/EntityScripts/CkGoapAction_EntityScript.h"

#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include "Engine/World.h"
#include "Framework/Application/SlateApplication.h"
#include "GameFramework/Actor.h"
#include "HAL/FileManager.h"
#include "ImageUtils.h"
#include "Misc/AutomationTest.h"
#include "Misc/Paths.h"
#include "Misc/ScopeExit.h"
#include "UObject/UObjectIterator.h"
#include "UObject/UnrealType.h"
#include "Widgets/SWindow.h"

namespace ck_tests_goap_debugger_search_trace_authored_pie
{
constexpr auto TestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;
const FName FixtureClassName{TEXT("Ck_Goap_Planner_SquadRosterPieFixture")};
const FName FixturePulseFunctionName{TEXT("RequestReplanPulse")};

struct FState final
{
    TWeakObjectPtr<AActor> Fixture;
    TSharedPtr<FCkGoapDebugger_ViewModel> ViewModel;
    TSharedPtr<SCkGoapDebugger_SearchTracePanel> Panel;
    TSharedPtr<SWindow> Window;
    TWeakPtr<SCkGoapDebugger_SearchTracePanel> WeakPanel;
    TWeakPtr<FCkUiView> WeakView;
    FCk_Handle_Goap_Planner Planner;
    TArray<FString> InitialKeys;
    int32 InitialAttemptCount = INDEX_NONE;
    int32 PulseResult = INDEX_NONE;
    bool bInitialProjectionReady = false;
    bool bNoOpKeysStable = false;
    bool bPulseProjectionReady = false;
    bool bWideCapture = false;
    bool bNarrowCapture = false;
    bool bResetEmpty = false;
    bool bTornDown = false;
};

auto Tick(FSlateApplication &InSlate) -> void
{
    InSlate.PumpMessages();
    InSlate.Tick();
    InSlate.Tick();
}

auto RefreshProjection(const TSharedRef<FState> &InState) -> void
{
    AActor *Fixture = InState->Fixture.Get();
    UWorld *World = IsValid(Fixture) ? Fixture->GetWorld() : nullptr;
    if (!IsValid(World) || !InState->ViewModel.IsValid() || !InState->Panel.IsValid())
    {
        return;
    }

    InState->ViewModel->Tick(World);
    InState->Panel->RefreshFromViewModel();
    if (FSlateApplication::IsInitialized())
    {
        Tick(FSlateApplication::Get());
    }
}

auto SaveCapture(FSlateApplication &InSlate, const TSharedRef<SWidget> &InRoot, const FString &InPath) -> bool
{
    TArray<FColor> Pixels;
    FIntVector Size = FIntVector::ZeroValue;
    if (!InSlate.TakeScreenshot(InRoot, Pixels, Size) || Size.X <= 0 || Size.Y <= 0 || Pixels.Num() < Size.X * Size.Y)
    {
        return false;
    }

    IFileManager::Get().MakeDirectory(*FPaths::GetPath(InPath), true);
    const FImageView Image(Pixels.GetData(), Size.X, Size.Y, ERawImageFormat::BGRA8);
    return FImageUtils::SaveImageByExtension(*InPath, Image);
}

auto FindFixtureClass() -> UClass *
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

auto InvokeFixturePulse(AActor *InFixture) -> int32
{
    UFunction *Pulse = IsValid(InFixture) ? InFixture->FindFunction(FixturePulseFunctionName) : nullptr;
    const FIntProperty *ReturnProperty = Pulse != nullptr ? CastField<FIntProperty>(Pulse->GetReturnProperty()) : nullptr;
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

auto ExpectedKey(const FCk_Handle_Goap_Planner &InPlanner, int32 InIndex) -> FString
{
    const FCk_Entity &Entity = InPlanner.Get_Entity();
    return FString::Printf(TEXT("goap-search-trace:%d:%d:%d"), static_cast<int32>(Entity.Get_EntityNumber()),
                           static_cast<int32>(Entity.Get_VersionNumber()), InIndex);
}

auto TextField(const TSharedPtr<const FCkUiRecord> &InRecord, const TCHAR *InName) -> FString
{
    const FCkUiFieldValue *Field = InRecord.IsValid() ? InRecord->FindField(InName) : nullptr;
    return Field != nullptr ? Field->Text.ToString() : FString{};
}

auto ColorField(const TSharedPtr<const FCkUiRecord> &InRecord, const TCHAR *InName) -> FLinearColor
{
    const FCkUiFieldValue *Field = InRecord.IsValid() ? InRecord->FindField(InName) : nullptr;
    return Field != nullptr ? Field->Color : FLinearColor::Transparent;
}

auto ExpectedConditions(const FCk_Goap_SearchDebugRow &InRow) -> FString
{
    FString Conditions;
    for (const FCk_GoapWS_Condition_Authored &Condition : InRow.Get_Conditions())
    {
        if (!Conditions.IsEmpty())
        {
            Conditions += TEXT(", ");
        }

        Conditions += Condition.Get_Key().ToString();
        if (!Condition.Get_Value())
        {
            Conditions += TEXT(" = false");
        }
    }

    return Conditions.IsEmpty() ? TEXT("(empty set)") : Conditions;
}

auto ExpectedVia(const FCk_Goap_SearchDebugRow &InRow) -> FString
{
    const TSubclassOf<UCk_GoapAction_EntityScript> ViaAction = InRow.Get_ViaActionClass();
    return FString::Printf(TEXT("via %s"), ViaAction == nullptr ? TEXT("(goal seed)") : *ViaAction->GetName());
}

auto HasExactProjection(const TSharedPtr<const FCkUiCollection> &InCollection, const FCkGoapDebugger_PlannerInfo *InPlanner) -> bool
{
    if (!InCollection.IsValid() || InPlanner == nullptr || InPlanner->SearchDebug.IsEmpty() ||
        InCollection->GetRecords().Num() != InPlanner->SearchDebug.Num())
    {
        return false;
    }

    for (int32 Index = 0; Index < InPlanner->SearchDebug.Num(); ++Index)
    {
        const FCk_Goap_SearchDebugRow &Row = InPlanner->SearchDebug[Index];
        const TSharedPtr<const FCkUiRecord> Record = InCollection->FindRecord(ExpectedKey(InPlanner->PlannerHandle, Index));
        const bool bSatisfied = Row.Get_SatisfiedByWorldState();
        if (!Record.IsValid() || Record->GetKey() != ExpectedKey(InPlanner->PlannerHandle, Index) ||
            TextField(Record, TEXT("trace-index")) != FString::Printf(TEXT("%02d"), Index) ||
            TextField(Record, TEXT("trace-conditions")) != ExpectedConditions(Row) ||
            TextField(Record, TEXT("trace-via")) != ExpectedVia(Row) ||
            TextField(Record, TEXT("trace-heuristic")) != FString::Printf(TEXT("h=%d"), Row.Get_UnsatisfiedCount()) ||
            TextField(Record, TEXT("trace-satisfaction")) != (bSatisfied ? TEXT("SATISFIED") : TEXT("OPEN")) ||
            ColorField(Record, TEXT("trace-row-color")) != (bSatisfied ? CkStyle::Ok() : CkStyle::TextMute()) ||
            ColorField(Record, TEXT("trace-satisfaction-foreground")) != (bSatisfied ? CkStyle::Ok() : CkStyle::TextMute()) ||
            ColorField(Record, TEXT("trace-satisfaction-background")) != (bSatisfied ? CkStyle::OkDim() : CkStyle::Bg2()))
        {
            return false;
        }
    }

    return true;
}

auto CollectKeys(const TSharedPtr<const FCkUiCollection> &InCollection) -> TArray<FString>
{
    TArray<FString> Keys;
    if (!InCollection.IsValid())
    {
        return Keys;
    }

    for (const TSharedPtr<const FCkUiRecord> &Record : InCollection->GetRecords())
    {
        if (!Record.IsValid())
        {
            return {};
        }

        Keys.Add(Record->GetKey());
    }

    return Keys;
}
} // namespace ck_tests_goap_debugger_search_trace_authored_pie

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkGoapDebugger_SearchTraceAuthoredPie, "Ck.GoapDebugger.SearchTrace.Authored.PIE",
                                 ck_tests_goap_debugger_search_trace_authored_pie::TestFlags)

bool FCkGoapDebugger_SearchTraceAuthoredPie::RunTest(const FString &)
{
    using namespace ck_tests_goap_debugger_search_trace_authored_pie;

    if (!FSlateApplication::IsInitialized())
    {
        AddError(TEXT("GOAP Search Trace authored PIE test requires Slate."));
        return false;
    }

    const TSharedRef<FState> State = MakeShared<FState>();
    FSlateApplication &Slate = FSlateApplication::Get();
    State->ViewModel = MakeShared<FCkGoapDebugger_ViewModel>();
    State->Panel = SNew(SCkGoapDebugger_SearchTracePanel).ViewModel(State->ViewModel);
    State->WeakPanel = State->Panel;
    State->Window = SNew(SWindow)
                        .AutoCenter(EAutoCenter::None)
                        .ClientSize(FVector2D{1100.0f, 700.0f})
                        .CreateTitleBar(false)
                        .HasCloseButton(false)[State->Panel.ToSharedRef()];
    Slate.AddWindow(State->Window.ToSharedRef(), true);
    Tick(Slate);

    const TSharedPtr<FCkUiView> View = State->Panel->Get_AuthoredView();
    State->WeakView = View;
    if (!View.IsValid() || !View->GetLastResult().Succeeded || !State->Panel->Get_AuthoredCollection().IsValid())
    {
        AddError(FString::Printf(TEXT("Production Search Trace authored surface did not mount. Authored load failure: %s"),
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
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [State](UWorld *World)
        {
            if (UClass *FixtureClass = FindFixtureClass(); IsValid(World) && FixtureClass != nullptr)
            {
                State->Fixture = World->SpawnActor<AActor>(FixtureClass, FTransform::Identity);
            }
        })));
    for (int32 Pass = 0; Pass < 120; ++Pass)
    {
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(1));
        ADD_LATENT_AUTOMATION_COMMAND(
            FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld *) { RefreshProjection(State); })));
    }
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Condition::CreateLambda(
            [State]
            {
                RefreshProjection(State);
                const FCkGoapDebugger_PlannerInfo *Planner = State->ViewModel->GetSelectedPlannerInfo();
                const TSharedPtr<const FCkUiCollection> Collection = State->Panel->Get_AuthoredCollection();
                if (Planner == nullptr || Planner->SearchDebug.IsEmpty() || !HasExactProjection(Collection, Planner))
                {
                    return false;
                }

                State->Planner = Planner->PlannerHandle;
                State->InitialAttemptCount = Planner->PlanAttemptCount;
                State->InitialKeys = CollectKeys(Collection);
                State->bInitialProjectionReady = !State->InitialKeys.IsEmpty();
                return State->bInitialProjectionReady;
            }),
        15.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [State](UWorld *)
        {
            RefreshProjection(State);
            State->bNoOpKeysStable = State->InitialKeys == CollectKeys(State->Panel->Get_AuthoredCollection());
            State->PulseResult = InvokeFixturePulse(State->Fixture.Get());
        })));
    for (int32 Pass = 0; Pass < 40; ++Pass)
    {
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(1));
        ADD_LATENT_AUTOMATION_COMMAND(
            FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld *) { RefreshProjection(State); })));
    }
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Condition::CreateLambda(
            [State]
            {
                RefreshProjection(State);
                const FCkGoapDebugger_PlannerInfo *Planner = State->ViewModel->GetSelectedPlannerInfo();
                const TSharedPtr<const FCkUiCollection> Collection = State->Panel->Get_AuthoredCollection();
                State->bPulseProjectionReady = State->PulseResult == 1 && Planner != nullptr && Planner->PlannerHandle == State->Planner &&
                                               Planner->PlanAttemptCount > State->InitialAttemptCount &&
                                               HasExactProjection(Collection, Planner);
                return State->bPulseProjectionReady;
            }),
        15.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [State](UWorld *)
        {
            if (!State->Window.IsValid() || !FSlateApplication::IsInitialized())
            {
                return;
            }

            FSlateApplication &LocalSlate = FSlateApplication::Get();
            State->Window->Resize(FVector2D{1400.0f, 800.0f});
            Tick(LocalSlate);
            State->bWideCapture =
                SaveCapture(LocalSlate, State->Window.ToSharedRef(),
                            FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Automation/GoapDebugger/SearchTraceAuthoredPie-Wide.png")));
            State->Window->Resize(FVector2D{480.0f, 700.0f});
            Tick(LocalSlate);
            State->bNarrowCapture =
                SaveCapture(LocalSlate, State->Window.ToSharedRef(),
                            FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Automation/GoapDebugger/SearchTraceAuthoredPie-Narrow.png")));
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, State](UWorld *)
        {
            TestTrue(TEXT("Search Trace mounts the production authored view and projects a selected real planner search"),
                     State->bInitialProjectionReady);
            TestTrue(TEXT("Search Trace preserves full planner-handle discovery keys across a no-op refresh"), State->bNoOpKeysStable);
            TestTrue(TEXT("Search Trace replaces its projection from the fixture's real post-pulse planner search"),
                     State->bPulseProjectionReady);
            TestTrue(TEXT("Search Trace captures wide and narrow mounted authored production surfaces"),
                     State->bWideCapture && State->bNarrowCapture);

            if (State->Panel.IsValid())
            {
                State->ViewModel->Reset_ForWorldChange();
                State->Panel->RefreshFromViewModel();
                Tick(FSlateApplication::Get());
                const TSharedPtr<const FCkUiCollection> Collection = State->Panel->Get_AuthoredCollection();
                State->bResetEmpty = Collection.IsValid() && Collection->GetRecords().IsEmpty();
            }
            TestTrue(TEXT("Search Trace empties its authored projection after ViewModel world reset"), State->bResetEmpty);

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
            TestTrue(TEXT("Search Trace releases authored widget state before PIE teardown"), State->bTornDown);
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif
