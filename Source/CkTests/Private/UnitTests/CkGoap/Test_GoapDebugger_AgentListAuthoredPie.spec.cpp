#include "CoreMinimal.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkGoapDebugger/ViewModel/CkGoapDebugger_ViewModel.h"
#include "CkGoapDebugger/Window/SCkGoapDebugger_AgentListPanel.h"

#include "CkDebuggerCommon/Navigation/CkDebug_Navigator.h"
#include "CkDebuggerCommon/Navigation/CkDebug_SelectionSync.h"
#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkSlateLayout/SCkUiTable.h"
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
#include "Widgets/Input/SSearchBox.h"
#include "Widgets/SWindow.h"

namespace ck_tests_goap_debugger_agent_list_authored_pie
{
    constexpr auto TestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;
    const FName FixtureClassName{TEXT("Ck_Goap_Planner_SquadRosterPieFixture")};

    struct FState final
    {
        TWeakObjectPtr<AActor> Fixture;
        TWeakObjectPtr<AActor> SecondFixture;
        TSharedPtr<FCkGoapDebugger_ViewModel> ViewModel;
        TSharedPtr<SCkGoapDebugger_AgentListPanel> Panel;
        TSharedPtr<SWindow> Window;
        TWeakPtr<SCkGoapDebugger_AgentListPanel> WeakPanel;
        TWeakPtr<FCkUiView> WeakView;
        FCk_Handle Entity;
        FCk_Handle NavigatedEntity;
        bool bReady = false;
        bool bWideCapture = false;
        bool bNarrowCapture = false;
        bool bPhysicalEntityRefClick = false;
        bool bProgrammaticSelectionNoEcho = false;
        bool bExternalSelection = false;
        bool bPhysicalRowSelection = false;
        bool bPhysicalRowSingleSync = false;
        bool bTornDown = false;
        FString RowClickDiagnostic;
        FString EntityRefClickDiagnostic;
        FString SelectedKeyBeforeRowClick;
        FString SelectedKeyAfterRowClick;
        FString ScopedSelectionSourceBefore;
        FString ScopedSelectionSourceAfter;
        int32 ScopedSelectionCallbackCount = 0;
        int32 EntityRefNavigatorCount = 0;
        FString EntityRefNavigatorHandleBefore;
        FString EntityRefNavigatorHandleAfter;
        FString EntityRefNavigatorSourceBefore;
        FString EntityRefNavigatorSourceAfter;
    };

    auto Tick(FSlateApplication &InSlate) -> void
    {
        InSlate.PumpMessages();
        InSlate.Tick();
        InSlate.Tick();
    }

    auto FindTagged(const TSharedRef<SWidget> &InRoot, const FName InTag) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTag() == InTag)
        {
            return InRoot;
        }
        const FChildren *Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SWidget> Found =
                    FindTagged(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag);
                Found.IsValid())
            {
                return Found;
            }
        }
        return {};
    }

    auto FindMountedSearch(const TSharedRef<SWidget> &InRoot, const FName InTag) -> TSharedPtr<SSearchBox>
    {
        if (InRoot->GetTag() == InTag && InRoot->GetTypeAsString() == TEXT("SSearchBox"))
        {
            return StaticCastSharedRef<SSearchBox>(InRoot);
        }
        const FChildren *Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SSearchBox> Found =
                    FindMountedSearch(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag);
                Found.IsValid())
            {
                return Found;
            }
        }
        return {};
    }

    auto FindDescendantByType(const TSharedRef<SWidget> &InRoot, const FString &InType) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTypeAsString() == InType)
        {
            return InRoot;
        }
        const FChildren *Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SWidget> Found =
                    FindDescendantByType(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InType);
                Found.IsValid())
            {
                return Found;
            }
        }
        return {};
    }

    auto WidgetPathContains(const FWidgetPath &InPath, const TSharedRef<SWidget> &InWidget) -> bool
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

    auto SaveCapture(FSlateApplication &InSlate, const TSharedRef<SWidget> &InRoot, const FString &InPath) -> bool
    {
        TArray<FColor> Pixels;
        FIntVector Size = FIntVector::ZeroValue;
        if (!InSlate.TakeScreenshot(InRoot, Pixels, Size) || Size.X <= 0 || Size.Y <= 0)
        {
            return false;
        }
        IFileManager::Get().MakeDirectory(*FPaths::GetPath(InPath), true);
        return FImageUtils::SaveImageByExtension(*InPath,
                                                 FImageView(Pixels.GetData(), Size.X, Size.Y, ERawImageFormat::BGRA8));
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

    auto Refresh(const TSharedRef<FState> &InState) -> void
    {
        AActor *Fixture = InState->Fixture.Get();
        if (!IsValid(Fixture) || !InState->ViewModel.IsValid() || !InState->Panel.IsValid())
        {
            return;
        }
        InState->ViewModel->Tick(Fixture->GetWorld());
        InState->Panel->RefreshFromViewModel();
        Tick(FSlateApplication::Get());
    }

    struct FMountedClickResult final
    {
        FString TargetType;
        FName TargetTag;
        FVector2D GeometryCenter = FVector2D::ZeroVector;
        bool bOwningWindowFound = false;
        bool bBringToFrontRequested = false;
        bool bWindowForegrounded = false;
        bool bGeometryHasCenter = false;
        bool bTargetFound = false;
        bool bMouseDownHandled = false;
        bool bCapturedAfterDown = false;
        bool bCapturePathContainsTarget = false;
        bool bTargetStillHitBeforeUp = false;
        bool bMouseUpHandled = false;

        auto IsFullClickHandled() const -> bool
        {
            return bTargetFound && bMouseDownHandled && bMouseUpHandled;
        }

        auto Describe() const -> FString
        {
            return FString::Printf(
                TEXT("target-type=%s target-tag=%s window-found=%d bring-to-front-requested=%d window-foregrounded=%d center=%s "
                     "geometry-valid=%d hit-before-down=%d down-handled=%d captured-after-down=%d "
                     "capture-path-contains-target=%d hit-before-up=%d up-handled=%d"),
                *TargetType, *TargetTag.ToString(), bOwningWindowFound, bBringToFrontRequested, bWindowForegrounded,
                *GeometryCenter.ToString(), bGeometryHasCenter, bTargetFound, bMouseDownHandled,
                bCapturedAfterDown, bCapturePathContainsTarget, bTargetStillHitBeforeUp, bMouseUpHandled);
        }
    };

    auto ClickMounted(FSlateApplication &InSlate, const TSharedRef<SWidget> &InWidget) -> FMountedClickResult
    {
        FMountedClickResult Result;
        Result.TargetType = InWidget->GetTypeAsString();
        Result.TargetTag = InWidget->GetTag();
        const TSharedPtr<SWindow> Window = InSlate.FindWidgetWindow(InWidget);
        Result.bOwningWindowFound = Window.IsValid() && Window->GetNativeWindow().IsValid();
        if (!Window.IsValid() || !Window->GetNativeWindow().IsValid())
        {
            return Result;
        }
        Window->BringToFront(true);
        Result.bBringToFrontRequested = true;
        Tick(InSlate);
        Result.bWindowForegrounded = Window->IsActive();
        InSlate.ReleaseAllPointerCapture(0);
        const FGeometry Geometry = InWidget->GetCachedGeometry();
        Result.GeometryCenter = Geometry.LocalToAbsolute(Geometry.GetLocalSize() * 0.5f);
        Result.bGeometryHasCenter = !Geometry.GetLocalSize().IsNearlyZero();
        if (Geometry.GetLocalSize().IsNearlyZero())
        {
            return Result;
        }
        const FVector2D Position = Result.GeometryCenter;
        const TSet<FKey> None;
        const TSet<FKey> DownButtons{EKeys::LeftMouseButton};
        const FPointerEvent Move(0, FSlateApplication::CursorPointerIndex, Position, Position, None,
                                 EKeys::Invalid, 0.0f, FModifierKeysState{});
        const FPointerEvent Down(0, FSlateApplication::CursorPointerIndex, Position, Position, DownButtons,
                                 EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        const FPointerEvent Up(0, FSlateApplication::CursorPointerIndex, Position, Position, None,
                               EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        InSlate.SetCursorPos(Position);
        InSlate.ProcessMouseMoveEvent(Move, true);
        const FWidgetPath TargetPath =
            InSlate.LocateWindowUnderMouse(Position, InSlate.GetInteractiveTopLevelWindows(), false, 0);
        Result.bTargetFound = TargetPath.IsValid() && WidgetPathContains(TargetPath, InWidget);
        if (!Result.bTargetFound)
        {
            return Result;
        }
        Result.bMouseDownHandled = InSlate.ProcessMouseButtonDownEvent(Window->GetNativeWindow(), Down);
        Result.bCapturedAfterDown = InWidget->HasMouseCapture();
        const TSharedPtr<FSlateUser> CursorUser = InSlate.GetUser(0);
        const FWidgetPath CaptorPath = CursorUser.IsValid()
            ? CursorUser->GetCaptorPath(FSlateApplication::CursorPointerIndex,
                FWeakWidgetPath::EInterruptedPathHandling::ReturnInvalid, &Down)
            : FWidgetPath{};
        Result.bCapturePathContainsTarget = CaptorPath.IsValid() && WidgetPathContains(CaptorPath, InWidget);
        const FWidgetPath UpTargetPath =
            InSlate.LocateWindowUnderMouse(Position, InSlate.GetInteractiveTopLevelWindows(), false, 0);
        Result.bTargetStillHitBeforeUp = UpTargetPath.IsValid() && WidgetPathContains(UpTargetPath, InWidget);
        Result.bMouseUpHandled = InSlate.ProcessMouseButtonUpEvent(Up);
        Tick(InSlate);
        return Result;
    }

    auto MakeExpectedKey(const FCk_Handle &InHandle) -> FString
    {
        const FCk_Entity &Entity = InHandle.Get_Entity();
        return FString::Printf(TEXT("goap-agent:%d:%d"), static_cast<int32>(Entity.Get_EntityNumber()),
                               static_cast<int32>(Entity.Get_VersionNumber()));
    }
} // namespace ck_tests_goap_debugger_agent_list_authored_pie

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkGoapDebugger_AgentListAuthoredPie, "Ck.GoapDebugger.AgentList.Authored.PIE",
                                 ck_tests_goap_debugger_agent_list_authored_pie::TestFlags)

bool FCkGoapDebugger_AgentListAuthoredPie::RunTest(const FString &)
{
    using namespace ck_tests_goap_debugger_agent_list_authored_pie;
    if (!FSlateApplication::IsInitialized())
    {
        AddError(TEXT("GOAP Agent List authored PIE test requires Slate."));
        return false;
    }

    const TSharedRef<FState> State = MakeShared<FState>();
    FSlateApplication &Slate = FSlateApplication::Get();
    State->ViewModel = MakeShared<FCkGoapDebugger_ViewModel>();
    State->Panel = SNew(SCkGoapDebugger_AgentListPanel).ViewModel(State->ViewModel);
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
    if (!View.IsValid() || !View->GetLastResult().Succeeded || !State->Panel->Get_AuthoredTable().IsValid())
    {
        AddError(FString::Printf(TEXT("Production Agent List authored surface did not mount. Authored load failure: %s"),
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
                State->SecondFixture = World->SpawnActor<AActor>(FixtureClass, FTransform(FVector{200.0f, 0.0f, 0.0f}));
            }
        })));
    for (int32 Pass = 0; Pass < 120; ++Pass)
    {
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(1));
        ADD_LATENT_AUTOMATION_COMMAND(
            FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld *) { Refresh(State); })));
    }
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Condition::CreateLambda(
            [State]
            {
                Refresh(State);
                const auto &Roster = State->ViewModel->Get_Roster();
                const TSharedPtr<const FCkUiCollection> Collection = State->Panel->Get_AuthoredCollection();
                if (Roster.Num() != 2 || !Collection.IsValid() || Collection->GetRecords().Num() != 2)
                {
                    return false;
                }
                State->Entity = Roster[0].EntityHandle;
                State->bReady = true;
                return true;
            }),
        15.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, State](UWorld *)
        {
            const TSharedPtr<SCkUiTable> Table = State->Panel->Get_AuthoredTable();
            const TSharedPtr<const FCkUiCollection> Collection = State->Panel->Get_AuthoredCollection();
            if (!State->bReady || !Table.IsValid() || !Collection.IsValid())
            {
                return;
            }
            const TSharedPtr<const FCkUiRecord> Record = Collection->FindRecord(MakeExpectedKey(State->Entity));
            TestTrue(TEXT("Authored Agent List mounts the production table and a roster record"), Record.IsValid());
            if (!Record.IsValid())
            {
                return;
            }
            TestEqual(TEXT("Authored Agent List key is exact full entity number plus version"), Record->GetKey(),
                      MakeExpectedKey(State->Entity));
            TestTrue(TEXT("Authored Agent List has exactly two unique production identities"),
                     Collection->GetRecords()[0]->GetKey() != Collection->GetRecords()[1]->GetKey());
            const FCkUiFieldValue *EntityField = Record->FindField(TEXT("agent-entity-id"));
            const FCkUiFieldValue *NameField = Record->FindField(TEXT("agent-name"));
            const FCkUiFieldValue *PlannerField = Record->FindField(TEXT("agent-planners"));
            TestTrue(TEXT("Authored Agent List publishes exact entity/name/planner fields"),
                     EntityField != nullptr &&
                         EntityField->Text.ToString() == ck::Format_UE(TEXT("{}"), State->Entity) &&
                         NameField != nullptr && !NameField->Text.IsEmpty() && PlannerField != nullptr &&
                         PlannerField->Text.ToString() == TEXT("3 planners"));

            const TSharedPtr<SSearchBox> Filter =
                FindMountedSearch(State->Panel.ToSharedRef(), TEXT("goap-agent-list-filter"));
            const TSharedPtr<SSearchBox> Highlight =
                FindMountedSearch(State->Panel.ToSharedRef(), TEXT("goap-agent-list-highlight"));
            const TSharedPtr<SWidget> Empty = FindTagged(State->Panel.ToSharedRef(), TEXT("goap-agent-list-empty"));
            TestTrue(TEXT("Mounted authored Agent List searches and empty state resolve by production tags"),
                     Filter.IsValid() && Highlight.IsValid() && Empty.IsValid());
            if (Filter.IsValid() && Highlight.IsValid() && Empty.IsValid())
            {
                const FString StableKey = Record->GetKey();
                const FLinearColor BaselineColor = Record->FindField(TEXT("agent-name-color"))->Color;
                Filter->SetText(FText::FromString(TEXT("__no_agent_list_match__")));
                Tick(FSlateApplication::Get());
                TestTrue(TEXT("Unmatched mounted filter clears records and shows empty authored state"),
                         Collection->GetRecords().IsEmpty() && Empty->GetVisibility().IsVisible());
                Filter->SetText(FText::GetEmpty());
                Tick(FSlateApplication::Get());
                TestTrue(TEXT("Clearing mounted filter restores both stable records"),
                         Collection->GetRecords().Num() == 2 && Collection->FindRecord(StableKey).IsValid());
                Highlight->SetText(FText::FromString(Record->FindField(TEXT("agent-name"))->Text.ToString()));
                Tick(FSlateApplication::Get());
                TestTrue(TEXT("Mounted highlight preserves both rows"), Collection->GetRecords().Num() == 2);
                Highlight->SetText(FText::GetEmpty());
                Tick(FSlateApplication::Get());
                TestEqual(TEXT("Clearing mounted highlight restores baseline color"),
                          Collection->FindRecord(StableKey)->FindField(TEXT("agent-name-color"))->Color, BaselineColor);
            }

            const FString CurrentKey = MakeExpectedKey(State->Entity);
            const TSharedPtr<const FCkUiRecord> CurrentRecord = Collection->FindRecord(CurrentKey);
            TestTrue(TEXT("Agent List filter restore reacquires the current production record identity"),
                     CurrentRecord.IsValid());
            if (!CurrentRecord.IsValid())
            {
                return;
            }

            int32 SyncCount = 0;
            const FDelegateHandle SyncHandle = ck::DebugSelectionSync::Get_OnSelection().AddLambda(
                [&SyncCount](const FCk_Handle &, FName) { ++SyncCount; });
            Table->TrySelectKey(CurrentRecord->GetKey(), false); // Programmatic seam: proves direct restore does not echo.
            State->bProgrammaticSelectionNoEcho = SyncCount == 0;
            ck::DebugSelectionSync::Get_OnSelection().Remove(SyncHandle);

            // Real mounted pointer route: this is intentionally separate from the direct seam above.
            Table->TrySelectKey({}, false);
            int32 PhysicalSyncCount = 0;
            FString ScopedSelectionSource = TEXT("<none>");
            const FDelegateHandle PhysicalSyncHandle = ck::DebugSelectionSync::Get_OnSelection().AddLambda(
                [&PhysicalSyncCount, &ScopedSelectionSource, State](const FCk_Handle &InEntity, FName InSource)
                {
                    ScopedSelectionSource = InSource.ToString();
                    if (InEntity == State->Entity && InSource == TEXT("GoapDebugger"))
                    {
                        ++PhysicalSyncCount;
                    }
                });
            TSharedPtr<ITableRow> Row;
            State->SelectedKeyBeforeRowClick = Table->GetSelectedKey().Get(TEXT("<none>"));
            State->ScopedSelectionSourceBefore = ScopedSelectionSource;
            if (const TSharedPtr<SListView<SCkUiTable::FRecord>> List = Table->GetList(); List.IsValid())
            {
                Row = List->WidgetFromItem(CurrentRecord);
                if (Row.IsValid())
                {
                    const FMountedClickResult RowClick = ClickMounted(FSlateApplication::Get(), Row->AsWidget());
                    State->RowClickDiagnostic = RowClick.Describe();
                    State->bPhysicalRowSelection =
                        RowClick.IsFullClickHandled() && State->ViewModel->GetSelectedEntity() == State->Entity;
                }
            }
            if (!Row.IsValid())
            {
                State->RowClickDiagnostic = TEXT("row widget unavailable");
            }
            State->SelectedKeyAfterRowClick = Table->GetSelectedKey().Get(TEXT("<none>"));
            State->ScopedSelectionSourceAfter = ScopedSelectionSource;
            State->ScopedSelectionCallbackCount = PhysicalSyncCount;
            State->bPhysicalRowSingleSync = PhysicalSyncCount == 1;
            ck::DebugSelectionSync::Get_OnSelection().Remove(PhysicalSyncHandle);
            State->EntityRefNavigatorHandleBefore = ck::Format_UE(TEXT("{}"), State->NavigatedEntity);
            State->EntityRefNavigatorHandleAfter = State->EntityRefNavigatorHandleBefore;
            State->EntityRefNavigatorSourceBefore = TEXT("<not invoked>");
            State->EntityRefNavigatorSourceAfter = TEXT("<not invoked>");
            if (Row.IsValid())
            {
                const TSharedPtr<SWidget> EntityRefPort =
                    FindTagged(Row->AsWidget(), TEXT("goap-agent-entity-cell"));
                const TSharedPtr<SWidget> EntityRef = EntityRefPort.IsValid()
                    ? FindDescendantByType(EntityRefPort.ToSharedRef(), TEXT("SCkDebug_EntityRef"))
                    : nullptr;
                if (EntityRef.IsValid())
                {
                    ck::DebugNav::Register_EntityNavigator(
                        [State](const FCk_Handle &InEntity)
                        {
                            ++State->EntityRefNavigatorCount;
                            State->NavigatedEntity = InEntity;
                            State->EntityRefNavigatorSourceAfter = TEXT("SCkDebug_EntityRef::OnMouseButtonDown");
                        });
                    const FMountedClickResult EntityRefClick =
                        ClickMounted(FSlateApplication::Get(), EntityRef.ToSharedRef());
                    State->EntityRefClickDiagnostic = EntityRefClick.Describe();
                    State->EntityRefNavigatorHandleAfter = ck::Format_UE(TEXT("{}"), State->NavigatedEntity);
                    State->bPhysicalEntityRefClick = EntityRefClick.bTargetFound &&
                                                     EntityRefClick.bMouseDownHandled &&
                                                     State->NavigatedEntity == State->Entity;
                    ck::DebugNav::Register_EntityNavigator({});
                }
                else
                {
                    State->EntityRefClickDiagnostic = TEXT("concrete SCkDebug_EntityRef descendant unavailable");
                }
            }
            else
            {
                State->EntityRefClickDiagnostic = TEXT("row widget unavailable");
            }
            ck::DebugSelectionSync::Broadcast(State->Entity, TEXT("ExternalAgentListTest"));
            Tick(FSlateApplication::Get());
            State->bExternalSelection =
                State->ViewModel->GetSelectedEntity() == State->Entity && Table->GetSelectedKey() == CurrentRecord->GetKey();

            State->Window->Resize(FVector2D{1400.0f, 800.0f});
            Tick(FSlateApplication::Get());
            State->bWideCapture =
                SaveCapture(FSlateApplication::Get(), State->Window.ToSharedRef(),
                            FPaths::Combine(FPaths::ProjectSavedDir(),
                                            TEXT("Automation/GoapDebugger/AgentListAuthoredPie-Wide.png")));
            State->Window->Resize(FVector2D{480.0f, 700.0f});
            Tick(FSlateApplication::Get());
            State->bNarrowCapture =
                SaveCapture(FSlateApplication::Get(), State->Window.ToSharedRef(),
                            FPaths::Combine(FPaths::ProjectSavedDir(),
                                            TEXT("Automation/GoapDebugger/AgentListAuthoredPie-Narrow.png")));
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, State](UWorld *)
        {
            TestTrue(TEXT("GOAP Agent List fixture produces a real roster"), State->bReady);
            TestTrue(TEXT("Programmatic authored selection does not echo on DebugSelectionSync"),
                     State->bProgrammaticSelectionNoEcho);
            TestTrue(FString::Printf(TEXT("Physical mounted Agent List row selection updates the production ViewModel: %s; "
                                         "selected-key-before=%s selected-key-after=%s"),
                                     *State->RowClickDiagnostic, *State->SelectedKeyBeforeRowClick,
                                     *State->SelectedKeyAfterRowClick),
                     State->bPhysicalRowSelection);
            TestTrue(FString::Printf(TEXT("Physical mounted Agent List row selection broadcasts exactly once: %s; "
                                         "scoped-count=%d scoped-source-before=%s scoped-source-after=%s"),
                                     *State->RowClickDiagnostic, State->ScopedSelectionCallbackCount,
                                     *State->ScopedSelectionSourceBefore, *State->ScopedSelectionSourceAfter),
                     State->bPhysicalRowSingleSync);
            TestTrue(FString::Printf(TEXT("Physical mounted authored EntityRef targets and handles mouse-down to invoke the navigator "
                                         "with its full handle: %s; navigator-count=%d handle-before=%s handle-after=%s "
                                         "source-before=%s source-after=%s"),
                                     *State->EntityRefClickDiagnostic, State->EntityRefNavigatorCount,
                                     *State->EntityRefNavigatorHandleBefore, *State->EntityRefNavigatorHandleAfter,
                                     *State->EntityRefNavigatorSourceBefore, *State->EntityRefNavigatorSourceAfter),
                     State->bPhysicalEntityRefClick);
            TestTrue(TEXT("External same-lineage selection restores authored table selection"),
                     State->bExternalSelection);
            TestTrue(TEXT("Authored Agent List captures wide and narrow production surfaces"),
                     State->bWideCapture && State->bNarrowCapture);
            if (State->Panel.IsValid())
            {
                State->Panel->Reset_ForWorldChange();
                TestTrue(TEXT("Agent List reset clears the authored collection and selection"),
                         State->Panel->Get_AuthoredCollection()->GetRecords().IsEmpty() &&
                             !State->Panel->Get_AuthoredTable()->GetSelectedKey().IsSet());
            }
            FSlateApplication::Get().DestroyWindowImmediately(State->Window.ToSharedRef());
            State->Window.Reset();
            State->Panel.Reset();
            State->ViewModel.Reset();
            Tick(FSlateApplication::Get());
            if (State->Fixture.IsValid())
            {
                State->Fixture->Destroy();
            }
            State->Fixture.Reset();
            if (State->SecondFixture.IsValid())
            {
                State->SecondFixture->Destroy();
            }
            State->SecondFixture.Reset();
            State->bTornDown = !State->WeakPanel.IsValid() && !State->WeakView.IsValid();
            TestTrue(TEXT("Agent List releases authored state before PIE teardown"), State->bTornDown);
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif
