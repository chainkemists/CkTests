#include "CoreMinimal.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkGoapDebugger/ViewModel/CkGoapDebugger_ViewModel.h"
#include "CkGoapDebugger/Window/SCkGoapDebugger_SquadTable.h"

#include "CkCore/Validation/CkIsValid.h"
#include "CkGoap/Planner/CkGoap_Planner_Utils.h"
#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/CkUiFloatSeries.h"
#include "CkSlateLayout/SCkUiRepeat.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include "Engine/World.h"
#include "Framework/Application/SlateApplication.h"
#include "Framework/Application/SlateUser.h"
#include "GameFramework/Actor.h"
#include "HAL/FileManager.h"
#include "ImageUtils.h"
#include "Input/Events.h"
#include "Misc/AutomationTest.h"
#include "Misc/Paths.h"
#include "UObject/UnrealType.h"
#include "UObject/UObjectIterator.h"
#include "Layout/WidgetPath.h"
#include "Widgets/SWindow.h"

namespace ck_tests_goap_debugger_squad_authored_pie
{
    constexpr auto TestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;
    const FName FixtureClassName{TEXT("Ck_Goap_Planner_SquadRosterPieFixture")};
    const FName FixturePulseFunctionName{TEXT("RequestReplanPulse")};

    struct FState final
    {
        TWeakObjectPtr<AActor> Fixture;
        TSharedPtr<FCkGoapDebugger_ViewModel> ViewModel;
        TSharedPtr<SCkGoapDebugger_SquadTable> Table;
        TSharedPtr<SWindow> Window;
        TWeakPtr<SCkGoapDebugger_SquadTable> WeakTable;
        TWeakPtr<FCkUiView> WeakView;
        FCk_Handle InspectedEntity;
        FCk_Handle_Goap_Planner InspectedPlanner;
        bool bFixtureSpawned = false;
        int32 FirstPulseResult = INDEX_NONE;
        int32 SecondPulseResult = INDEX_NONE;
        bool bInitialProjectionReady = false;
        bool bFirstProjectionReady = false;
        bool bFinalProjectionReady = false;
        bool bPhysicalInspectClickHandled = false;
        bool bPhysicalInspectTargeted = false;
        bool bPhysicalInspectDownHandled = false;
        bool bPhysicalInspectCapturedAfterDown = false;
        bool bPhysicalInspectCaptorPathContainsTarget = false;
        bool bPhysicalInspectTargetedBeforeUp = false;
        bool bPhysicalInspectUpHandled = false;
        bool bPhysicalInspectDelegateReceived = false;
        bool bClickedPlannerPlanMatches = false;
        bool bEntityRefTargeted = false;
        bool bEntityRefDownHandled = false;
        bool bWideCapture = false;
        bool bNarrowCapture = false;
        bool bTornDown = false;
        FString InitialProjectionSummary;
        FString FirstProjectionSummary;
        FString FinalProjectionSummary;
    };

    auto Tick(FSlateApplication& InSlate) -> void
    {
        InSlate.PumpMessages();
        InSlate.Tick();
        InSlate.Tick();
    }

    auto RefreshProjectionFromFixture(const TSharedRef<FState>& InState) -> void
    {
        AActor* Fixture = InState->Fixture.Get();
        UWorld* World = IsValid(Fixture) ? Fixture->GetWorld() : nullptr;
        if (!IsValid(World) || !InState->ViewModel.IsValid() || !InState->Table.IsValid()) { return; }
        InState->ViewModel->Tick(World);
        InState->Table->RefreshFromViewModel();
        if (FSlateApplication::IsInitialized()) { Tick(FSlateApplication::Get()); }
    }

    auto FindTagged(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTag() == InTag) { return InRoot; }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SWidget> Found = FindTagged(
                    ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag); Found.IsValid())
            { return Found; }
        }
        return {};
    }

    auto WidgetPathContains(const FWidgetPath& InPath, const TSharedRef<SWidget>& InWidget) -> bool
    {
        for (int32 Index = 0; Index < InPath.Widgets.Num(); ++Index)
        {
            if (InPath.Widgets[Index].Widget == InWidget) { return true; }
        }
        return false;
    }

    struct FPhysicalClickResult final
    {
        bool Targeted = false;
        bool DownHandled = false;
        bool CapturedAfterDown = false;
        bool CaptorPathContainsTarget = false;
        bool TargetedBeforeUp = false;
        bool UpHandled = false;

        auto Succeeded() const -> bool
        {
            return Targeted && DownHandled && CapturedAfterDown && CaptorPathContainsTarget && TargetedBeforeUp && UpHandled;
        }
    };

    auto ClickDetailed(FSlateApplication& InSlate, const TSharedRef<SWidget>& InWidget) -> FPhysicalClickResult
    {
        auto Result = FPhysicalClickResult{};
        const TSharedPtr<SWindow> Window = InSlate.FindWidgetWindow(InWidget);
        if (!Window.IsValid() || !Window->GetNativeWindow().IsValid()) { return Result; }
        Window->BringToFront(true);
        Tick(InSlate);
        InSlate.ReleaseAllPointerCapture(0);
        const FGeometry Geometry = InWidget->GetCachedGeometry();
        if (Geometry.GetLocalSize().IsNearlyZero()) { return Result; }
        const FVector2D Position = Geometry.LocalToAbsolute(Geometry.GetLocalSize() * 0.5f);
        const TSet<FKey> NoButtons;
        const TSet<FKey> LeftDown{EKeys::LeftMouseButton};
        const FPointerEvent Move(0, FSlateApplication::CursorPointerIndex, Position, Position, NoButtons, EKeys::Invalid, 0.0f, FModifierKeysState{});
        const FPointerEvent Down(0, FSlateApplication::CursorPointerIndex, Position, Position, LeftDown, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        const FPointerEvent Up(0, FSlateApplication::CursorPointerIndex, Position, Position, NoButtons, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        InSlate.SetCursorPos(Position);
        InSlate.ProcessMouseMoveEvent(Move, true);
        const FWidgetPath TargetPath = InSlate.LocateWindowUnderMouse(
            Position, InSlate.GetInteractiveTopLevelWindows(), false, 0);
        Result.Targeted = WidgetPathContains(TargetPath, InWidget);
        if (!Result.Targeted) { return Result; }
        Result.DownHandled = InSlate.ProcessMouseButtonDownEvent(Window->GetNativeWindow(), Down);
        Result.CapturedAfterDown = InWidget->HasMouseCapture();
        const TSharedPtr<FSlateUser> CursorUser = InSlate.GetUser(0);
        const FWidgetPath CaptorPath = CursorUser.IsValid()
            ? CursorUser->GetCaptorPath(FSlateApplication::CursorPointerIndex,
                FWeakWidgetPath::EInterruptedPathHandling::ReturnInvalid, &Down)
            : FWidgetPath{};
        Result.CaptorPathContainsTarget = CaptorPath.IsValid() && WidgetPathContains(CaptorPath, InWidget);
        const FWidgetPath UpTargetPath = InSlate.LocateWindowUnderMouse(
            Position, InSlate.GetInteractiveTopLevelWindows(), false, 0);
        Result.TargetedBeforeUp = WidgetPathContains(UpTargetPath, InWidget);
        Result.UpHandled = InSlate.ProcessMouseButtonUpEvent(Up);
        Tick(InSlate);
        return Result;
    }

    auto SaveCapture(FSlateApplication& InSlate, const TSharedRef<SWidget>& InRoot, const FString& InPath) -> bool
    {
        TArray<FColor> Pixels;
        FIntVector Size = FIntVector::ZeroValue;
        if (!InSlate.TakeScreenshot(InRoot, Pixels, Size) || Size.X <= 0 || Size.Y <= 0 || Pixels.Num() < Size.X * Size.Y) { return false; }
        IFileManager::Get().MakeDirectory(*FPaths::GetPath(InPath), true);
        const FImageView Image(Pixels.GetData(), Size.X, Size.Y, ERawImageFormat::BGRA8);
        return FImageUtils::SaveImageByExtension(*InPath, Image);
    }

    auto FieldText(const TSharedPtr<const FCkUiRecord>& InRecord, const TCHAR* InField) -> FString
    {
        const FCkUiFieldValue* Field = InRecord.IsValid() ? InRecord->FindField(InField) : nullptr;
        return Field != nullptr ? Field->Text.ToString() : FString{};
    }

    auto FieldBool(const TSharedPtr<const FCkUiRecord>& InRecord, const TCHAR* InField) -> bool
    {
        const FCkUiFieldValue* Field = InRecord.IsValid() ? InRecord->FindField(InField) : nullptr;
        return Field != nullptr && Field->Bool;
    }

    auto RecordByPlannerLabel(const TSharedPtr<const FCkUiCollection>& InCollection, const TCHAR* InLabel) -> TSharedPtr<const FCkUiRecord>
    {
        if (!InCollection.IsValid()) { return {}; }
        for (const TSharedPtr<const FCkUiRecord>& Record : InCollection->GetRecords())
        {
            if (FieldText(Record, TEXT("squad-planner")) == InLabel) { return Record; }
        }
        return {};
    }

    auto GetReplanKindEventCount(const TSharedPtr<const FCkUiRecord>& InRecord) -> float
    {
        const FCkUiFieldValue* Field = InRecord.IsValid() ? InRecord->FindField(TEXT("squad-replan-samples")) : nullptr;
        const TSharedPtr<FCkUiFloatSeries> Series = Field != nullptr ? Field->FloatSeries.Pin() : nullptr;
        if (!Series.IsValid()) { return 0.0f; }

        float ReplanKindEventCount = 0.0f;
        for (const float Sample : Series->GetSamples()) { ReplanKindEventCount += Sample; }
        return ReplanKindEventCount;
    }

    auto GetAlertSummary(const TSharedPtr<const FCkUiRecord>& InRecord) -> FString
    {
        auto Alerts = TArray<FString>{};
        if (FieldBool(InRecord, TEXT("squad-alert-fallback-visible"))) { Alerts.Add(TEXT("fallback")); }
        if (FieldBool(InRecord, TEXT("squad-alert-no-fallback-visible"))) { Alerts.Add(TEXT("no fallback")); }
        if (FieldBool(InRecord, TEXT("squad-alert-threshold-visible"))) { Alerts.Add(TEXT("threshold")); }
        return Alerts.IsEmpty() ? TEXT("none") : FString::Join(Alerts, TEXT(","));
    }

    auto DescribeProjectionRecord(const TSharedPtr<const FCkUiRecord>& InRecord, const TCHAR* InLabel) -> FString
    {
        return FString::Printf(TEXT("%s{label=%s status=%s chain=%s attempts=%s alerts=%s spark-sum=%.0f}"),
            InLabel,
            *FieldText(InRecord, TEXT("squad-planner")),
            *FieldText(InRecord, TEXT("squad-status")),
            *FieldText(InRecord, TEXT("squad-chain")),
            *FieldText(InRecord, TEXT("squad-attempts")),
            *GetAlertSummary(InRecord),
            GetReplanKindEventCount(InRecord));
    }

    auto DescribeProjection(const TSharedPtr<const FCkUiCollection>& InCollection) -> FString
    {
        const auto Records = TArray<FString>{
            DescribeProjectionRecord(RecordByPlannerLabel(InCollection, TEXT("FallbackVsChain")), TEXT("planned")),
            DescribeProjectionRecord(RecordByPlannerLabel(InCollection, TEXT("FallbackOnly")), TEXT("fallback")),
            DescribeProjectionRecord(RecordByPlannerLabel(InCollection, TEXT("Set")), TEXT("threshold"))};
        return FString::Join(Records, TEXT(" | "));
    }

    auto GetReflectedClassName(const TSubclassOf<UCk_GoapAction_EntityScript>& InClass) -> FString
    {
        const UClass* Class = InClass.Get();
        return IsValid(Class) ? Class->GetName() : FString{};
    }

    auto HasExpectedClickedPlannerPlan(const FCk_Handle_Goap_Planner& InPlanner) -> bool
    {
        if (!ck::IsValid(InPlanner)) { return false; }
        const TArray<TSubclassOf<UCk_GoapAction_EntityScript>> PlanClasses = UCk_Utils_Goap_Planner_UE::Get_PlanClasses(InPlanner);
        return PlanClasses.Num() == 2
            && GetReflectedClassName(PlanClasses[0]) == TEXT("Ck_AutoTestAction_Goap_FallbackVsChain_Setup")
            && GetReflectedClassName(PlanClasses[1]) == TEXT("Ck_AutoTestAction_Goap_FallbackVsChain_Finalize");
    }

    auto HasExpectedProjection(
        const TSharedPtr<const FCkUiCollection>& InCollection,
        const bool InWorldStateRaised,
        const int32 InExpectedAttempts) -> bool
    {
        const TSharedPtr<const FCkUiRecord> Planned = RecordByPlannerLabel(InCollection, TEXT("FallbackVsChain"));
        const TSharedPtr<const FCkUiRecord> Fallback = RecordByPlannerLabel(InCollection, TEXT("FallbackOnly"));
        const TSharedPtr<const FCkUiRecord> Threshold = RecordByPlannerLabel(InCollection, TEXT("Set"));
        return InCollection.IsValid() && InCollection->GetRecords().Num() == 3
            && Planned.IsValid() && Fallback.IsValid() && Threshold.IsValid()
            && FieldText(Planned, TEXT("squad-status")) == TEXT("Plan Found")
            && FieldText(Planned, TEXT("squad-chain")) == (InWorldStateRaised ? TEXT("Finalize") : TEXT("Setup"))
            && FieldText(Fallback, TEXT("squad-status")) == TEXT("Plan Found")
            && FieldText(Fallback, TEXT("squad-chain")) == (InWorldStateRaised ? TEXT("Gated") : TEXT("Fallback"))
            && FieldBool(Fallback, TEXT("squad-alert-fallback-visible")) != InWorldStateRaised
            && FieldText(Threshold, TEXT("squad-status")) == TEXT("Cost Threshold")
            && FieldBool(Threshold, TEXT("squad-alert-threshold-visible"))
            && FCString::Atoi(*FieldText(Planned, TEXT("squad-attempts"))) == InExpectedAttempts
            && FCString::Atoi(*FieldText(Fallback, TEXT("squad-attempts"))) == InExpectedAttempts
            && FCString::Atoi(*FieldText(Threshold, TEXT("squad-attempts"))) == InExpectedAttempts;
    }

    auto InvokeFixturePulse(AActor* InFixture) -> int32
    {
        UFunction* Pulse = IsValid(InFixture) ? InFixture->FindFunction(FixturePulseFunctionName) : nullptr;
        const FIntProperty* ReturnProperty = Pulse != nullptr ? CastField<FIntProperty>(Pulse->GetReturnProperty()) : nullptr;
        if (ReturnProperty == nullptr || Pulse->ParmsSize <= 0) { return -1; }

        TArray<uint8> Params;
        Params.SetNumZeroed(Pulse->ParmsSize);
        Pulse->InitializeStruct(Params.GetData());
        ON_SCOPE_EXIT { Pulse->DestroyStruct(Params.GetData()); };
        InFixture->ProcessEvent(Pulse, Params.GetData());
        return ReturnProperty->GetPropertyValue_InContainer(Params.GetData());
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
    FCkGoapDebugger_SquadAuthoredPie,
    "Ck.GoapDebugger.Squad.Authored.PIE",
    ck_tests_goap_debugger_squad_authored_pie::TestFlags)

bool FCkGoapDebugger_SquadAuthoredPie::RunTest(const FString&)
{
    using namespace ck_tests_goap_debugger_squad_authored_pie;

    const TSharedRef<FState> State = MakeShared<FState>();
    if (!FSlateApplication::IsInitialized())
    {
        AddError(TEXT("GOAP Squad authored PIE fixture requires Slate before PIE."));
        return false;
    }

    {
        FSlateApplication& Slate = FSlateApplication::Get();
        const TWeakPtr<FState> WeakState = State;
        State->ViewModel = MakeShared<FCkGoapDebugger_ViewModel>();
        State->Table = SNew(SCkGoapDebugger_SquadTable)
            .ViewModel(State->ViewModel)
            .OnInspect(FOnCkGoapDebug_SquadInspect::CreateLambda([WeakState](FCk_Handle Entity, FCk_Handle_Goap_Planner Planner)
            {
                if (const TSharedPtr<FState> PinnedState = WeakState.Pin())
                {
                    PinnedState->InspectedEntity = Entity;
                    PinnedState->InspectedPlanner = Planner;
                }
            }));
        State->WeakTable = State->Table;
        State->Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{1100.0f, 700.0f})
            .CreateTitleBar(false).HasCloseButton(false)[State->Table.ToSharedRef()];
        Slate.AddWindow(State->Window.ToSharedRef(), true);
        Tick(Slate);

        const TSharedPtr<FCkUiView> View = State->Table->Get_AuthoredView();
        State->WeakView = View;
        if (!View.IsValid() || !View->GetLastResult().Succeeded || !State->Table->Get_AuthoredCollection().IsValid())
        {
            AddError(FString::Printf(TEXT("GOAP Squad authored preflight rejected: %s"),
                View.IsValid() ? *FString::Join(View->GetLastResult().Errors, TEXT(" | ")) : TEXT("view invalid")));
            Slate.DestroyWindowImmediately(State->Window.ToSharedRef());
            State->Window.Reset();
            State->Table.Reset();
            State->ViewModel.Reset();
            Tick(Slate);
            return false;
        }
    }

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld* World) -> void
    {
        if (!IsValid(World)) { return; }
        if (UClass* FixtureClass = FindFixtureClass(); FixtureClass != nullptr)
        {
            State->Fixture = World->SpawnActor<AActor>(FixtureClass, FTransform::Identity);
            State->bFixtureSpawned = State->Fixture.IsValid();
        }
    })));
    const FCk_NetAutoTest_ServerAction RefreshRoster = FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
    {
        RefreshProjectionFromFixture(State);
    });
    // Sample the asynchronous construction one frame at a time until the initial roster is stable.
    // A ViewModel snapshot precedes every external pulse, so DataCollector has a real previous row.
    for (int32 RefreshPass = 0; RefreshPass != 120; ++RefreshPass)
    {
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(1));
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(RefreshRoster));
    }
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    {
        RefreshProjectionFromFixture(State);
        const TSharedPtr<const FCkUiCollection> Collection = State->Table.IsValid() ? State->Table->Get_AuthoredCollection() : nullptr;
        State->InitialProjectionSummary = DescribeProjection(Collection);
        State->bInitialProjectionReady = State->bFixtureSpawned && State->Fixture.IsValid()
            && HasExpectedProjection(Collection, false, 1);
        return State->bInitialProjectionReady;
    }), 15.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
    {
        State->FirstPulseResult = InvokeFixturePulse(State->Fixture.Get());
    })));
    for (int32 RefreshPass = 0; RefreshPass != 30; ++RefreshPass)
    {
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(1));
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(RefreshRoster));
    }
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    {
        RefreshProjectionFromFixture(State);
        const TSharedPtr<const FCkUiCollection> Collection = State->Table.IsValid() ? State->Table->Get_AuthoredCollection() : nullptr;
        State->FirstProjectionSummary = DescribeProjection(Collection);
        State->bFirstProjectionReady = State->FirstPulseResult == 1 && HasExpectedProjection(Collection, true, 2)
            && GetReplanKindEventCount(RecordByPlannerLabel(Collection, TEXT("FallbackVsChain"))) >= 1.0f
            && GetReplanKindEventCount(RecordByPlannerLabel(Collection, TEXT("FallbackOnly"))) >= 1.0f
            && GetReplanKindEventCount(RecordByPlannerLabel(Collection, TEXT("Set"))) >= 1.0f;
        return State->bFirstProjectionReady;
    }), 15.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
    {
        State->SecondPulseResult = InvokeFixturePulse(State->Fixture.Get());
    })));
    for (int32 RefreshPass = 0; RefreshPass != 30; ++RefreshPass)
    {
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(1));
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(RefreshRoster));
    }
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    {
        RefreshProjectionFromFixture(State);
        const TSharedPtr<const FCkUiCollection> Collection = State->Table.IsValid() ? State->Table->Get_AuthoredCollection() : nullptr;
        const TSharedPtr<const FCkUiRecord> Planned = RecordByPlannerLabel(Collection, TEXT("FallbackVsChain"));
        const TSharedPtr<const FCkUiRecord> Fallback = RecordByPlannerLabel(Collection, TEXT("FallbackOnly"));
        const TSharedPtr<const FCkUiRecord> Threshold = RecordByPlannerLabel(Collection, TEXT("Set"));
        State->FinalProjectionSummary = DescribeProjection(Collection);
        const bool bReady = State->SecondPulseResult == 2 && HasExpectedProjection(Collection, false, 3)
            && GetReplanKindEventCount(Planned) >= FCString::Atoi(*FieldText(Planned, TEXT("squad-attempts"))) - 1
            && GetReplanKindEventCount(Fallback) >= FCString::Atoi(*FieldText(Fallback, TEXT("squad-attempts"))) - 1
            && GetReplanKindEventCount(Threshold) >= FCString::Atoi(*FieldText(Threshold, TEXT("squad-attempts"))) - 1;
        State->bFinalProjectionReady = bReady;
        return bReady;
    }), 15.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
    {
        if (!State->Table.IsValid() || !FSlateApplication::IsInitialized()) { return; }
        FSlateApplication& Slate = FSlateApplication::Get();
        const TSharedPtr<FCkUiView> View = State->Table->Get_AuthoredView();
        const TSharedPtr<const FCkUiCollection> Collection = State->Table->Get_AuthoredCollection();
        const TSharedPtr<const FCkUiRecord> Planned = RecordByPlannerLabel(Collection, TEXT("FallbackVsChain"));
        if (!View.IsValid() || !Planned.IsValid()) { return; }

        State->Window->Resize(FVector2D{1440.0f, 800.0f});
        Tick(Slate);
        State->bWideCapture = SaveCapture(Slate, State->Window.ToSharedRef(),
            FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Automation/GoapDebugger/SquadAuthoredPie-Wide.png")));

        const TSharedPtr<SCkUiRepeat> Repeat = View->GetRepeat(TEXT("goap-squad-records"));
        const TSharedPtr<SWidget> PlannedItem = Repeat.IsValid() ? Repeat->GetItemWidget(Planned->GetKey()) : nullptr;
        const TSharedPtr<SWidget> Inspect = PlannedItem.IsValid()
            ? FindTagged(PlannedItem.ToSharedRef(), TEXT("goap-squad-inspect")) : nullptr;
        const FPhysicalClickResult InspectClick = Inspect.IsValid()
            ? ClickDetailed(Slate, Inspect.ToSharedRef()) : FPhysicalClickResult{};
        State->bPhysicalInspectClickHandled = InspectClick.Succeeded();
        State->bPhysicalInspectTargeted = InspectClick.Targeted;
        State->bPhysicalInspectDownHandled = InspectClick.DownHandled;
        State->bPhysicalInspectCapturedAfterDown = InspectClick.CapturedAfterDown;
        State->bPhysicalInspectCaptorPathContainsTarget = InspectClick.CaptorPathContainsTarget;
        State->bPhysicalInspectTargetedBeforeUp = InspectClick.TargetedBeforeUp;
        State->bPhysicalInspectUpHandled = InspectClick.UpHandled;
        State->bPhysicalInspectDelegateReceived = Planned->GetKey().StartsWith(TEXT("goap-squad:"))
            && ck::IsValid(State->InspectedEntity) && ck::IsValid(State->InspectedPlanner);
        State->bClickedPlannerPlanMatches = HasExpectedClickedPlannerPlan(State->InspectedPlanner);

        if (PlannedItem.IsValid())
        {
            if (const TSharedPtr<SWidget> EntityRef = FindTagged(PlannedItem.ToSharedRef(), TEXT("goap-squad-entity")); EntityRef.IsValid())
            {
                const FPhysicalClickResult EntityRefClick = ClickDetailed(Slate, EntityRef.ToSharedRef());
                State->bEntityRefTargeted = EntityRefClick.Targeted;
                State->bEntityRefDownHandled = EntityRefClick.DownHandled;
            }
        }

        State->Window->Resize(FVector2D{760.0f, 700.0f});
        Tick(Slate);
        State->bNarrowCapture = SaveCapture(Slate, State->Window.ToSharedRef(),
            FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Automation/GoapDebugger/SquadAuthoredPie-Narrow.png")));

    })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld*) -> void
    {
        TestTrue(TEXT("GOAP Squad fixture spawned from its persistent production actor"), State->bFixtureSpawned && State->Fixture.IsValid());
        TestEqual(TEXT("GOAP Squad first reflected fixture pulse returns serial 1"), State->FirstPulseResult, 1);
        TestEqual(TEXT("GOAP Squad second reflected fixture pulse returns serial 2"), State->SecondPulseResult, 2);
        TestTrue(FString::Printf(TEXT("GOAP Squad initial projection preserves exact attempt 1: %s"),
            *State->InitialProjectionSummary), State->bInitialProjectionReady);
        TestTrue(FString::Printf(TEXT("GOAP Squad first-pulse projection preserves exact attempt 2: %s"),
            *State->FirstProjectionSummary), State->bFirstProjectionReady);
        TestTrue(FString::Printf(TEXT("GOAP Squad final projection preserves exact attempt 3: %s"),
            *State->FinalProjectionSummary), State->bFinalProjectionReady);
        TestTrue(TEXT("GOAP Squad captures the real authored wide surface"), State->bWideCapture);
        TestTrue(TEXT("GOAP Squad captures the real authored narrow surface"), State->bNarrowCapture);
        TestTrue(TEXT("GOAP Squad physical Inspect target is present in the Slate path under its pointer"), State->bPhysicalInspectTargeted);
        TestTrue(TEXT("GOAP Squad physical Inspect mouse down is handled"), State->bPhysicalInspectDownHandled);
        TestTrue(TEXT("GOAP Squad physical Inspect captures the mouse after down"), State->bPhysicalInspectCapturedAfterDown);
        TestTrue(TEXT("GOAP Squad physical Inspect capture path retains the targeted mounted control"), State->bPhysicalInspectCaptorPathContainsTarget);
        TestTrue(TEXT("GOAP Squad physical Inspect target remains in the Slate path before mouse up"), State->bPhysicalInspectTargetedBeforeUp);
        TestTrue(TEXT("GOAP Squad physical Inspect mouse up is handled"), State->bPhysicalInspectUpHandled);
        TestTrue(TEXT("GOAP Squad physical Inspect click is handled while its wide authored control is visible"), State->bPhysicalInspectClickHandled);
        TestTrue(TEXT("GOAP Squad physical Inspect delegate receives valid production handles"), State->bPhysicalInspectDelegateReceived);
        TestTrue(TEXT("GOAP Squad clicked production planner restores the ordered Setup then Finalize plan"), State->bClickedPlannerPlanMatches);
        TestTrue(TEXT("GOAP Squad physical EntityRef target is present in the Slate path under its pointer"), State->bEntityRefTargeted);
        TestTrue(TEXT("GOAP Squad physical EntityRef link handles mouse down through the mounted authored control"), State->bEntityRefDownHandled);
    })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
    {
        if (FSlateApplication::IsInitialized() && State->Window.IsValid())
        { FSlateApplication::Get().DestroyWindowImmediately(State->Window.ToSharedRef()); }
        State->Window.Reset();
        if (State->Table.IsValid()) { State->Table->Reset_ForWorldChange(); }
        State->Table.Reset();
        State->ViewModel.Reset();
        if (FSlateApplication::IsInitialized()) { Tick(FSlateApplication::Get()); }
        if (State->Fixture.IsValid()) { State->Fixture->Destroy(); }
        State->Fixture.Reset();
        State->bTornDown = !State->WeakTable.IsValid() && !State->WeakView.IsValid();
    })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld*) -> void
    {
        TestTrue(TEXT("GOAP Squad teardown releases authored widget state before PIE cleanup"), State->bTornDown);
    })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif
