#include "CoreMinimal.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkAiDebugger/Window/SCkAiDebuggerWindow.h"

#include "CkCore/Validation/CkIsValid.h"
#include "CkCrowd/Agent/CkCrowdAgent_Utils.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Handle/CkHandle_Utils.h"
#include "CkEcsExt/Transform/CkTransform_Utils.h"
#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkSlateLayout/SCkUiTable.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include "Framework/Application/SlateApplication.h"
#include "HAL/FileManager.h"
#include "ImageUtils.h"
#include "Input/Events.h"
#include "Interfaces/IPluginManager.h"
#include "Misc/AutomationTest.h"
#include "Misc/Paths.h"
#include "Widgets/SWindow.h"
#include "Widgets/Layout/SScrollBox.h"
#include "Widgets/Views/ITableRow.h"

namespace ck_tests_ai_debugger_authored_roster_pie
{
    constexpr auto TestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;
    const FString RosterTableId{TEXT("ai-roster")};

    struct FState final
    {
        FCk_Handle Owner;
        FCk_Handle AgentEntityA;
        FCk_Handle AgentEntityB;
        FCk_Handle_CrowdAgent AgentA;
        FCk_Handle_CrowdAgent AgentB;
        FCk_Handle VerificationOwner;
        FCk_Handle VerificationAgentEntityA;
        FCk_Handle VerificationAgentEntityB;
        FCk_Handle_CrowdAgent VerificationAgentA;
        FCk_Handle_CrowdAgent VerificationAgentB;
        TSharedPtr<SCkAiDebuggerWindow> Panel;
        TSharedPtr<SWindow> Window;
        TWeakPtr<SCkAiDebuggerWindow> WeakPanel;
        TWeakPtr<FCkUiView> WeakView;
        TSharedPtr<SCkUiTable> HeldTable;
        TSharedPtr<const FCkUiRecord> StableARecord;
        TSharedPtr<ITableRow> StableARow;
        FString StableAKey;
        bool bFixtureCreated = false;
        bool bMounted = false;
        bool bInitialProjection = false;
        bool bSelectionClickHandled = false;
        bool bSelectionKeyPublished = false;
        bool bSelectionPhysicalRouted = false;
        bool bSelectionRouted = false;
        bool bRefreshRetainsIdentity = false;
        bool bRemovalAtomic = false;
        bool bCompatibleReloadRetained = false;
        bool bRejectedReloadPreserved = false;
        bool bWideCapture = false;
        bool bNarrowCapture = false;
        bool bNarrowScrollReachable = false;
        bool bHeldSelectionInert = false;
        bool bTeardownRequested = false;
        bool bFixtureDestroyed = false;
        bool bHandlesCleared = false;
    };

    auto Tick(FSlateApplication& InSlate) -> void
    {
        InSlate.PumpMessages();
        InSlate.Tick();
        InSlate.Tick();
    }

    auto SaveCapture(FSlateApplication& InSlate, const TSharedRef<SWidget>& InRoot, const FString& InPath) -> bool
    {
        TArray<FColor> Pixels;
        FIntVector Size = FIntVector::ZeroValue;
        if (NOT InSlate.TakeScreenshot(InRoot, Pixels, Size) || Size.X <= 0 || Size.Y <= 0 || Pixels.Num() < Size.X * Size.Y)
        { return false; }
        IFileManager::Get().MakeDirectory(*FPaths::GetPath(InPath), true);
        const FImageView Image(Pixels.GetData(), Size.X, Size.Y, ERawImageFormat::BGRA8);
        return FImageUtils::SaveImageByExtension(*InPath, Image);
    }

    auto GetResources() -> FString
    {
        const TSharedPtr<IPlugin> Plugin = IPluginManager::Get().FindPlugin(TEXT("CkDebugger"));
        return Plugin.IsValid() ? FPaths::Combine(Plugin->GetBaseDir(), TEXT("Resources/UI")) : FString{};
    }

    auto FieldText(const TSharedPtr<const FCkUiRecord>& InRecord, const TCHAR* InField) -> FString
    {
        const FCkUiFieldValue* Field = InRecord.IsValid() ? InRecord->FindField(InField) : nullptr;
        return Field != nullptr ? Field->Text.ToString() : FString{};
    }

    auto RecordByName(const TSharedPtr<FCkUiCollection>& InCollection, const TCHAR* InName) -> TSharedPtr<const FCkUiRecord>
    {
        if (NOT InCollection.IsValid()) { return {}; }
        for (const TSharedPtr<const FCkUiRecord>& Record : InCollection->GetRecords())
        {
            if (FieldText(Record, TEXT("ai-roster-name")) == InName) { return Record; }
        }
        return {};
    }

    auto HasSchema(const TSharedPtr<FCkUiCollection>& InCollection) -> bool
    {
        if (NOT InCollection.IsValid()) { return false; }
        const TArray<FCkUiFieldSchema>& Schema = InCollection->GetSchema();
        const auto Has = [&Schema](const TCHAR* Name) -> bool
        {
            return Schema.ContainsByPredicate([Name](const FCkUiFieldSchema& Field) { return Field.Name == Name; });
        };
        return Has(TEXT("ai-roster-name")) && Has(TEXT("ai-roster-summary")) && Has(TEXT("ai-roster-context"))
            && Has(TEXT("ai-roster-status")) && Has(TEXT("ai-roster-status-color"))
            && Has(TEXT("ai-roster-status-background"));
    }

    auto KeyCarriesPhysicalEntity(const TSharedPtr<const FCkUiRecord>& InRecord, const FCk_Handle& InPhysicalHandle) -> bool
    {
        if (NOT InRecord.IsValid() || ck::Is_NOT_Valid(InPhysicalHandle)) { return false; }
        const FCk_Entity& Entity = InPhysicalHandle.Get_Entity();
        const FString PhysicalSuffix = FString::Printf(TEXT(":%d:%d"),
            static_cast<int32>(Entity.Get_EntityNumber()), static_cast<int32>(Entity.Get_VersionNumber()));
        return InRecord->GetKey().EndsWith(PhysicalSuffix);
    }

    auto SelectRowByMouseDown(const TSharedRef<SWidget>& InWidget) -> bool
    {
        const FGeometry Geometry = InWidget->GetCachedGeometry();
        if (Geometry.GetLocalSize().IsNearlyZero()) { return false; }
        // The authored table is intentionally wider than its roster pane. Click a visible point near the leading
        // edge of the physical row instead of its clipped/off-pane geometric centre.
        const FVector2D Position = Geometry.GetAbsolutePositionAtCoordinates(FVector2D{0.05f, 0.5f});
        const TSet<FKey> LeftDown{EKeys::LeftMouseButton};
        const FPointerEvent Down(0, FSlateApplication::CursorPointerIndex, Position, Position,
            LeftDown, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        return InWidget->OnMouseButtonDown(Geometry, Down).IsEventHandled();
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkAiDebugger_AuthoredRosterPie,
    "Ck.AiDebugger.AuthoredRoster.PIE",
    ck_tests_ai_debugger_authored_roster_pie::TestFlags)

bool FCkAiDebugger_AuthoredRosterPie::RunTest(const FString&)
{
    using namespace ck_tests_ai_debugger_authored_roster_pie;

    const TSharedRef<FState> State = MakeShared<FState>();
    if (NOT FSlateApplication::IsInitialized())
    {
        AddError(TEXT("AI roster authored PIE fixture requires Slate before PIE."));
        return false;
    }

    {
        FSlateApplication& Slate = FSlateApplication::Get();
        State->Panel = SNew(SCkAiDebuggerWindow);
        State->WeakPanel = State->Panel;
        State->Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{1100.0f, 700.0f})
            .CreateTitleBar(false).HasCloseButton(false)[State->Panel.ToSharedRef()];
        Slate.AddWindow(State->Window.ToSharedRef(), true);

        const TSharedPtr<FCkUiView> View = State->Panel->Get_AiRosterView();
        const TSharedPtr<FCkUiCollection> Collection = State->Panel->Get_AiRosterCollection();
        const TSharedPtr<SCkUiTable> Table = View.IsValid() ? View->GetTable(RosterTableId) : nullptr;
        State->bMounted = View.IsValid() && View->GetLastResult().Succeeded && HasSchema(Collection) && Table.IsValid();
        if (NOT State->bMounted)
        {
            const FString Errors = View.IsValid()
                ? FString::Join(View->GetLastResult().Errors, TEXT(" | "))
                : State->Panel->Get_AiRosterLoadError();
            AddError(FString::Printf(TEXT("AI roster authored preflight rejected: mounted=%d errors=[%s]"), State->bMounted, *Errors));
            Slate.DestroyWindowImmediately(State->Window.ToSharedRef());
            State->Window.Reset();
            State->Panel.Reset();
            Tick(Slate);
            return false;
        }
        Tick(Slate);
    }

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld* InWorld) -> void
    {
        if (NOT IsValid(InWorld)) { return; }
        State->Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InWorld);
        State->AgentEntityA = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(State->Owner);
        State->AgentEntityB = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(State->Owner);
        UCk_Utils_Handle_UE::Set_DebugName(State->AgentEntityA, TEXT("AiRosterAlpha"));
        UCk_Utils_Handle_UE::Set_DebugName(State->AgentEntityB, TEXT("AiRosterBeta"));
        FCk_Handle_Transform TransformA = UCk_Utils_Transform_UE::Add(State->AgentEntityA,
            FTransform{FVector{0.0f, 0.0f, 100.0f}}, ECk_Replication::DoesNotReplicate);
        FCk_Handle_Transform TransformB = UCk_Utils_Transform_UE::Add(State->AgentEntityB,
            FTransform{FVector{200.0f, 0.0f, 100.0f}}, ECk_Replication::DoesNotReplicate);
        State->AgentA = UCk_Utils_CrowdAgent_UE::Add(TransformA, FCk_Fragment_CrowdAgent_ParamsData{42.0f, 192.0f});
        State->AgentB = UCk_Utils_CrowdAgent_UE::Add(TransformB, FCk_Fragment_CrowdAgent_ParamsData{42.0f, 192.0f});
        State->bFixtureCreated = ck::IsValid(State->Owner) && ck::IsValid(State->AgentEntityA) && ck::IsValid(State->AgentEntityB)
            && ck::IsValid(State->AgentA) && ck::IsValid(State->AgentB);
    })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    {
        const TSharedPtr<FCkUiCollection> Collection = State->Panel.IsValid() ? State->Panel->Get_AiRosterCollection() : nullptr;
        return State->bFixtureCreated && ck::IsValid(State->AgentA) && ck::IsValid(State->AgentB) && Collection.IsValid()
            && Collection->GetRecords().Num() == 2 && RecordByName(Collection, TEXT("AiRosterAlpha")).IsValid()
            && RecordByName(Collection, TEXT("AiRosterBeta")).IsValid();
    }), 15.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
    {
        if (NOT State->Panel.IsValid() || NOT FSlateApplication::IsInitialized()) { return; }
        const TSharedPtr<FCkUiView> View = State->Panel->Get_AiRosterView();
        const TSharedPtr<FCkUiCollection> Collection = State->Panel->Get_AiRosterCollection();
        const TSharedPtr<SCkUiTable> Table = View.IsValid() ? View->GetTable(RosterTableId) : nullptr;
        const TSharedPtr<const FCkUiRecord> A = RecordByName(Collection, TEXT("AiRosterAlpha"));
        const TSharedPtr<const FCkUiRecord> B = RecordByName(Collection, TEXT("AiRosterBeta"));
        if (NOT A.IsValid() || NOT B.IsValid() || NOT Table.IsValid()) { return; }

        State->StableARecord = A;
        State->StableAKey = A->GetKey();
        State->HeldTable = Table;
        const TSharedPtr<SListView<SCkUiTable::FRecord>> List = Table->GetList();
        if (List.IsValid())
        {
            List->RequestScrollIntoView(A);
            Tick(FSlateApplication::Get());
            State->StableARow = List->WidgetFromItem(A);
        }

        State->bInitialProjection = HasSchema(Collection)
            && KeyCarriesPhysicalEntity(A, State->AgentA.ConvertToHandle())
            && KeyCarriesPhysicalEntity(B, State->AgentB.ConvertToHandle())
            && A->GetKey() != B->GetKey()
            && NOT FieldText(A, TEXT("ai-roster-summary")).IsEmpty()
            && NOT FieldText(A, TEXT("ai-roster-status")).IsEmpty();
        State->bSelectionClickHandled = State->StableARow.IsValid()
            && SelectRowByMouseDown(State->StableARow->AsWidget());
        State->bSelectionKeyPublished = Table->GetSelectedKey().IsSet()
            && Table->GetSelectedKey().GetValue() == State->StableAKey;
        State->bSelectionPhysicalRouted = State->Panel->Get_AiRosterSelectedPhysicalHandle()
            == State->AgentA.ConvertToHandle();
        State->bSelectionRouted = State->bSelectionClickHandled && State->bSelectionKeyPublished
            && State->bSelectionPhysicalRouted;

        if (State->Window.IsValid())
        {
            State->Window->Resize(FVector2D{1440.0f, 800.0f});
            Tick(FSlateApplication::Get());
            State->bWideCapture = SaveCapture(FSlateApplication::Get(), State->Window.ToSharedRef(),
                FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Automation/AiDebugger/AuthoredRosterPie-Wide.png")));
            State->Window->Resize(FVector2D{1100.0f, 700.0f});
            Tick(FSlateApplication::Get());
            const TSharedPtr<SScrollBox> NarrowScroll = View->GetScroll(TEXT("ai-roster-scroll"));
            if (NarrowScroll.IsValid())
            {
                NarrowScroll->SetScrollOffset(NarrowScroll->GetScrollOffsetOfEnd() * 0.75f);
                Tick(FSlateApplication::Get());
                State->bNarrowScrollReachable = NarrowScroll->GetScrollOffsetOfEnd() > 0.0f
                    && NarrowScroll->GetScrollOffset() > 0.0f;
            }
            State->bNarrowCapture = SaveCapture(FSlateApplication::Get(), State->Window.ToSharedRef(),
                FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Automation/AiDebugger/AuthoredRosterPie-Narrow.png")));
        }

        const FString Resources = GetResources();
        if (NOT Resources.IsEmpty())
        {
            const int64 Revision = View->GetRevision();
            const FCkUiLoadResult Accepted = View->ReloadFiles(FPaths::Combine(Resources, TEXT("AiDebuggerRoster.ui.html")),
                FPaths::Combine(Resources, TEXT("AiDebuggerRoster.ui.css")));
            Tick(FSlateApplication::Get());
            State->bCompatibleReloadRetained = Accepted.Succeeded && View->GetRevision() > Revision
                && State->Panel->Get_AiRosterCollection() == Collection
                && RecordByName(Collection, TEXT("AiRosterAlpha")) == State->StableARecord
                && View->GetTable(RosterTableId) == Table && Table->GetSelectedKey().IsSet()
                && Table->GetSelectedKey().GetValue() == State->StableAKey && List.IsValid()
                && State->StableARow.IsValid() && List->WidgetFromItem(State->StableARecord) == State->StableARow;
            const int64 RejectRevision = View->GetRevision();
            const FCkUiLoadResult Rejected = View->TryReload(
                TEXT("<ui version=\"1\"><region name=\"main\"><unsupported-ai-roster-node/></region></ui>"),
                TEXT(""), TEXT("AiDebuggerRejectedReload"));
            Tick(FSlateApplication::Get());
            State->bRejectedReloadPreserved = NOT Rejected.Succeeded && View->GetRevision() == RejectRevision
                && View->GetTable(RosterTableId) == Table && RecordByName(Collection, TEXT("AiRosterAlpha")) == State->StableARecord;
        }

        if (ck::IsValid(State->AgentA))
        { UCk_Utils_CrowdAgent_UE::Request_SetMaxSpeed(State->AgentA, 480.0f, {}); }
    })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(30));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    {
        const TSharedPtr<FCkUiCollection> Collection = State->Panel.IsValid() ? State->Panel->Get_AiRosterCollection() : nullptr;
        const TSharedPtr<const FCkUiRecord> A = RecordByName(Collection, TEXT("AiRosterAlpha"));
        return ck::IsValid(State->AgentA) && Collection.IsValid() && Collection->GetRecords().Num() == 2
            && A == State->StableARecord && FieldText(A, TEXT("ai-roster-summary")).Contains(TEXT("480"));
    }), 15.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
    {
        if (NOT State->Panel.IsValid()) { return; }
        const TSharedPtr<FCkUiView> View = State->Panel->Get_AiRosterView();
        const TSharedPtr<FCkUiCollection> Collection = State->Panel->Get_AiRosterCollection();
        const TSharedPtr<SCkUiTable> Table = View.IsValid() ? View->GetTable(RosterTableId) : nullptr;
        const TSharedPtr<SListView<SCkUiTable::FRecord>> List = Table.IsValid() ? Table->GetList() : nullptr;
        const TSharedPtr<const FCkUiRecord> A = RecordByName(Collection, TEXT("AiRosterAlpha"));
        State->bRefreshRetainsIdentity = A == State->StableARecord
            && FieldText(A, TEXT("ai-roster-summary")).Contains(TEXT("480"))
            && List.IsValid() && State->StableARow.IsValid() && List->WidgetFromItem(State->StableARecord) == State->StableARow;
        if (ck::IsValid(State->AgentEntityB)) { UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(State->AgentEntityB); }
    })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    {
        const TSharedPtr<FCkUiCollection> Collection = State->Panel.IsValid() ? State->Panel->Get_AiRosterCollection() : nullptr;
        return Collection.IsValid() && Collection->GetRecords().Num() == 1
            && RecordByName(Collection, TEXT("AiRosterAlpha")) == State->StableARecord
            && NOT RecordByName(Collection, TEXT("AiRosterBeta")).IsValid();
    }), 15.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
    {
        const TSharedPtr<FCkUiCollection> Collection = State->Panel.IsValid() ? State->Panel->Get_AiRosterCollection() : nullptr;
        State->bRemovalAtomic = Collection.IsValid() && Collection->GetRecords().Num() == 1
            && RecordByName(Collection, TEXT("AiRosterAlpha")) == State->StableARecord
            && NOT RecordByName(Collection, TEXT("AiRosterBeta")).IsValid();

        if (NOT State->Panel.IsValid() || NOT FSlateApplication::IsInitialized()) { return; }
        State->WeakView = State->Panel->Get_AiRosterView();
        if (State->Window.IsValid()) { FSlateApplication::Get().DestroyWindowImmediately(State->Window.ToSharedRef()); }
        State->Window.Reset();
        State->Panel.Reset();
        Tick(FSlateApplication::Get());
        const TSharedPtr<SListView<SCkUiTable::FRecord>> HeldList = State->HeldTable.IsValid() ? State->HeldTable->GetList() : nullptr;
        if (HeldList.IsValid())
        {
            HeldList->ClearSelection();
            HeldList->SetSelection(State->StableARecord, ESelectInfo::OnMouseClick);
        }
        State->bHeldSelectionInert = HeldList.IsValid() && NOT State->WeakPanel.IsValid() && NOT State->WeakView.IsValid();
        State->VerificationOwner = State->Owner;
        State->VerificationAgentEntityA = State->AgentEntityA;
        State->VerificationAgentEntityB = State->AgentEntityB;
        State->VerificationAgentA = State->AgentA;
        State->VerificationAgentB = State->AgentB;
        if (ck::IsValid(State->VerificationOwner))
        { UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(State->VerificationOwner); }
        State->bTeardownRequested = true;
    })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    {
        return State->bTeardownRequested && ck::Is_NOT_Valid(State->VerificationOwner)
            && ck::Is_NOT_Valid(State->VerificationAgentEntityA) && ck::Is_NOT_Valid(State->VerificationAgentEntityB)
            && ck::Is_NOT_Valid(State->VerificationAgentA) && ck::Is_NOT_Valid(State->VerificationAgentB);
    }), 15.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
    {
        State->bFixtureDestroyed = State->bTeardownRequested && ck::Is_NOT_Valid(State->VerificationOwner)
            && ck::Is_NOT_Valid(State->VerificationAgentEntityA) && ck::Is_NOT_Valid(State->VerificationAgentEntityB)
            && ck::Is_NOT_Valid(State->VerificationAgentA) && ck::Is_NOT_Valid(State->VerificationAgentB);
        State->Owner = {};
        State->AgentEntityA = {};
        State->AgentEntityB = {};
        State->AgentA = {};
        State->AgentB = {};
        State->VerificationOwner = {};
        State->VerificationAgentEntityA = {};
        State->VerificationAgentEntityB = {};
        State->VerificationAgentA = {};
        State->VerificationAgentB = {};
        State->bHandlesCleared = ck::Is_NOT_Valid(State->Owner) && ck::Is_NOT_Valid(State->AgentEntityA)
            && ck::Is_NOT_Valid(State->AgentEntityB) && ck::Is_NOT_Valid(State->AgentA) && ck::Is_NOT_Valid(State->AgentB)
            && ck::Is_NOT_Valid(State->VerificationOwner) && ck::Is_NOT_Valid(State->VerificationAgentEntityA)
            && ck::Is_NOT_Valid(State->VerificationAgentEntityB) && ck::Is_NOT_Valid(State->VerificationAgentA)
            && ck::Is_NOT_Valid(State->VerificationAgentB);
        State->HeldTable.Reset();
        State->StableARow.Reset();
        State->StableARecord.Reset();
    })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this, FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
    {
        if (NOT State->bSelectionRouted)
        {
            AddError(FString::Printf(TEXT("AI roster selection discriminator: click-handled=%d key-published=%d physical-routed=%d"),
                State->bSelectionClickHandled, State->bSelectionKeyPublished, State->bSelectionPhysicalRouted));
        }
        TestTrue(TEXT("AI roster mounts the real authored virtualized table and schema before PIE"), State->bMounted);
        TestTrue(TEXT("Two public transient Crowd-agent children project through physical roster records"), State->bFixtureCreated && State->bInitialProjection);
        TestTrue(TEXT("Native authored table row mouse-down routes the selected physical Crowd handle through production"), State->bSelectionRouted);
        TestTrue(TEXT("Live refresh retains the surviving collection record and native table-row identity"), State->bRefreshRetainsIdentity);
        TestTrue(TEXT("Agent removal changes roster membership atomically without replacing the survivor"), State->bRemovalAtomic);
        TestTrue(TEXT("Compatible installed roster reload preserves collection, record, table, and selection identity"), State->bCompatibleReloadRetained);
        TestTrue(TEXT("Rejected roster reload leaves the accepted roster identities published"), State->bRejectedReloadPreserved);
        TestTrue(TEXT("Wide and scrolled-narrow AI roster captures succeed"), State->bWideCapture && State->bNarrowCapture && State->bNarrowScrollReachable);
        TestTrue(TEXT("A held table selection is inert after its AI-window owner releases"), State->bHeldSelectionInert);
        TestTrue(TEXT("Owner destruction invalidates retained copied owner, child, and Crowd-agent handles"), State->bFixtureDestroyed);
        TestTrue(TEXT("All fixture and verification handles clear only after teardown invalidation before EndPIE"), State->bHandlesCleared);
        return State->bMounted && State->bFixtureCreated && State->bInitialProjection && State->bSelectionRouted
            && State->bRefreshRetainsIdentity && State->bRemovalAtomic && State->bCompatibleReloadRetained
            && State->bRejectedReloadPreserved && State->bWideCapture && State->bNarrowCapture && State->bNarrowScrollReachable
            && State->bHeldSelectionInert && State->bFixtureDestroyed && State->bHandlesCleared;
    }), TEXT("AI debugger authored roster exercises real public Crowd-agent PIE state")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif
