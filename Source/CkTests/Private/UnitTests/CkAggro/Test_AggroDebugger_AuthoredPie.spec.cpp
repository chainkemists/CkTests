#include "CoreMinimal.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkAggroDebugger/Window/SCkAggroDebuggerWindow.h"

#include "CkAggro/CkAggroTarget_Utils.h"
#include "CkAggro/CkAggro_Utils.h"
#include "CkCore/Validation/CkIsValid.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Handle/CkHandle_Utils.h"
#include "CkEcsExt/Transform/CkTransform_Utils.h"
#include "CkSlateLayout/CkFlexText.h"
#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/SCkUiRepeat.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include "Framework/Application/SlateApplication.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformProcess.h"
#include "ImageUtils.h"
#include "Input/Events.h"
#include "Interfaces/IPluginManager.h"
#include "Misc/AutomationTest.h"
#include "Misc/Paths.h"
#include "Widgets/Input/SCheckBox.h"
#include "Widgets/Input/SEditableTextBox.h"
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"

namespace ck_tests_aggro_debugger_authored_pie
{
    constexpr auto TestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;

    struct FState final
    {
        FCk_Handle Owner;
        FCk_Handle AggroEntity;
        FCk_Handle TrackedA;
        FCk_Handle TrackedB;
        FCk_Handle_Aggro Aggro;
        FCk_Handle_AggroTarget TargetA;
        FCk_Handle_AggroTarget TargetB;
        TSharedPtr<SCkAggroDebuggerWindow> Panel;
        TSharedPtr<SWindow> Window;
        TWeakPtr<SCkAggroDebuggerWindow> WeakPanel;
        TWeakPtr<FCkUiView> WeakView;
        TSharedPtr<SEditableTextBox> HeldFilter;
        TSharedPtr<const FCkUiRecord> StableARecord;
        TSharedPtr<SWidget> StableAItem;
        FString StableAKey;
        bool bFixtureCreated = false;
        bool bMountedUnavailable = false;
        bool bInitialProjection = false;
        bool bControlsRouted = false;
        bool bHighlightIsInert = false;
        bool bTargetSearchKeepsOwner = false;
        bool bOwnerSearchKeepsSiblings = false;
        bool bEngagedOnlyRouted = false;
        bool bWideCapture = false;
        bool bNarrowCapture = false;
        bool bControlGeometry = false;
        bool bRankIdentityRetained = false;
        bool bRemovalAtomic = false;
        bool bCompatibleReloadRetained = false;
        bool bRejectedReloadPreserved = false;
        bool bStaleCallbackInert = false;
        FString FilterDraft;
        FString HighlightDraft;
        int32 InitialAIndex = INDEX_NONE;
        int32 InitialBIndex = INDEX_NONE;
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

    auto FindSearchEditor(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SEditableTextBox>
    {
        if (InRoot->GetTag() == InTag && InRoot->GetTypeAsString() == TEXT("SSearchBox"))
        { return StaticCastSharedRef<SEditableTextBox>(InRoot); }
        FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SEditableTextBox> Found = FindSearchEditor(Children->GetChildAt(Index), InTag); Found.IsValid()) { return Found; }
        }
        return nullptr;
    }

    auto FindCheckbox(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SCheckBox>
    {
        const TSharedPtr<SWidget> Tagged = FindTagged(InRoot, InTag);
        if (!Tagged.IsValid()) { return {}; }
        if (Tagged->GetTypeAsString() == TEXT("SCheckBox")) { return StaticCastSharedPtr<SCheckBox>(Tagged); }
        const FChildren* Children = Tagged->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            const TSharedPtr<SWidget> Child = ConstCastSharedRef<SWidget>(Children->GetChildAt(Index));
            if (Child.IsValid() && Child->GetTypeAsString() == TEXT("SCheckBox")) { return StaticCastSharedPtr<SCheckBox>(Child); }
        }
        return {};
    }

    auto FocusPathContains(FSlateApplication& InSlate, const TSharedRef<SWidget>& InWidget) -> bool
    {
        const TSharedPtr<SWidget> Focused = InSlate.GetUserFocusedWidget(0);
        FWidgetPath Path;
        if (!Focused.IsValid() || !InSlate.GeneratePathToWidgetUnchecked(Focused.ToSharedRef(), Path)) { return false; }
        for (int32 Index = 0; Index < Path.Widgets.Num(); ++Index)
        {
            if (Path.Widgets[Index].Widget == InWidget) { return true; }
        }
        return false;
    }

    auto Click(FSlateApplication& InSlate, const TSharedRef<SWidget>& InWidget) -> bool
    {
        const FGeometry Geometry = InWidget->GetCachedGeometry();
        const TSharedPtr<SWindow> Window = InSlate.FindWidgetWindow(InWidget);
        if (!Window.IsValid() || !Window->GetNativeWindow().IsValid() || Geometry.GetLocalSize().IsNearlyZero()) { return false; }
        const FVector2D Position = Geometry.LocalToAbsolute(Geometry.GetLocalSize() * 0.5f);
        const TSet<FKey> NoButtons;
        const TSet<FKey> LeftDown{EKeys::LeftMouseButton};
        const FPointerEvent Move(0, FSlateApplication::CursorPointerIndex, Position, Position, NoButtons, EKeys::Invalid, 0.0f, FModifierKeysState{});
        const FPointerEvent Down(0, FSlateApplication::CursorPointerIndex, Position, Position, LeftDown, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        const FPointerEvent Up(0, FSlateApplication::CursorPointerIndex, Position, Position, NoButtons, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        InSlate.SetCursorPos(Position);
        InSlate.ProcessMouseMoveEvent(Move, true);
        const bool bHandled = InSlate.ProcessMouseButtonDownEvent(Window->GetNativeWindow(), Down);
        InSlate.ProcessMouseButtonUpEvent(Up);
        Tick(InSlate);
        return bHandled;
    }

    auto Replace(FSlateApplication& InSlate, const TSharedRef<SEditableTextBox>& InEditor, const FString& InText) -> bool
    {
        if (!FocusPathContains(InSlate, InEditor)) { InSlate.SetUserFocus(0, InEditor, EFocusCause::SetDirectly); }
        Tick(InSlate);
        if (!FocusPathContains(InSlate, InEditor)) { return false; }
        const FModifierKeysState Control{false, false, true, false, false, false, false, false, false};
        if (!InSlate.ProcessKeyDownEvent(FKeyEvent{EKeys::A, Control, 0, false, 0, 0})) { return false; }
        for (const TCHAR Character : InText)
        { if (!InSlate.ProcessKeyCharEvent(FCharacterEvent{Character, FModifierKeysState{}, 0, false})) { return false; } }
        if (InText.IsEmpty() && !InSlate.ProcessKeyDownEvent(FKeyEvent{EKeys::BackSpace, FModifierKeysState{}, 0, false, 0, 0})) { return false; }
        // A search without Enter publishes its bound value through SSearchBox's delayed change callback.
        const double Deadline = FPlatformTime::Seconds() + 2.0;
        while (InEditor->GetText().ToString() != InText && FPlatformTime::Seconds() < Deadline)
        {
            Tick(InSlate);
            FPlatformProcess::Sleep(0.01f);
        }
        return InEditor->GetText().ToString() == InText;
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

    auto FieldText(const TSharedPtr<const FCkUiRecord>& InRecord, const FName InField) -> FString
    {
        const FCkUiFieldValue* Field = InRecord.IsValid() ? InRecord->FindField(InField.ToString()) : nullptr;
        return Field != nullptr ? Field->Text.ToString() : FString{};
    }

    auto FieldNumber(const TSharedPtr<const FCkUiRecord>& InRecord, const FName InField) -> float
    {
        const FCkUiFieldValue* Field = InRecord.IsValid() ? InRecord->FindField(InField.ToString()) : nullptr;
        return Field != nullptr ? Field->Number : -1.0f;
    }

    auto TargetRecord(const TSharedPtr<const FCkUiCollection>& InCollection, const FString& InName) -> TSharedPtr<const FCkUiRecord>
    {
        if (!InCollection.IsValid()) { return {}; }
        for (const TSharedPtr<const FCkUiRecord>& Record : InCollection->GetRecords())
        {
            if (FieldText(Record, TEXT("aggro-target-name")) == InName) { return Record; }
        }
        return {};
    }

    auto OwnerRecord(const TSharedPtr<const FCkUiCollection>& InCollection) -> TSharedPtr<const FCkUiRecord>
    {
        if (!InCollection.IsValid()) { return {}; }
        for (const TSharedPtr<const FCkUiRecord>& Record : InCollection->GetRecords())
        {
            const FCkUiFieldValue* IsOwner = Record.IsValid() ? Record->FindField(TEXT("aggro-is-owner")) : nullptr;
            if (IsOwner != nullptr && IsOwner->Bool) { return Record; }
        }
        return {};
    }

    auto TargetIndex(const TSharedPtr<const FCkUiCollection>& InCollection, const FString& InName) -> int32
    {
        if (!InCollection.IsValid()) { return INDEX_NONE; }
        const TArray<TSharedPtr<const FCkUiRecord>>& Records = InCollection->GetRecords();
        for (int32 Index = 0; Index < Records.Num(); ++Index)
        {
            if (FieldText(Records[Index], TEXT("aggro-target-name")) == InName) { return Index; }
        }
        return INDEX_NONE;
    }

    auto HasSchema(const TSharedPtr<const FCkUiCollection>& InCollection) -> bool
    {
        if (!InCollection.IsValid()) { return false; }
        const TArray<FCkUiFieldSchema>& Schema = InCollection->GetSchema();
        const auto Has = [&Schema](const FName Name) { return Schema.ContainsByPredicate([Name](const FCkUiFieldSchema& Field) { return Field.Name == Name.ToString(); }); };
        return Has(TEXT("aggro-is-owner")) && Has(TEXT("aggro-is-target")) && Has(TEXT("aggro-owner-name"))
            && Has(TEXT("aggro-target-name")) && Has(TEXT("aggro-threat-fraction")) && Has(TEXT("aggro-score-fraction"))
            && Has(TEXT("aggro-state")) && Has(TEXT("aggro-detail"));
    }

    auto ReadText(const TSharedRef<SWidget>& InRoot) -> FString
    {
        if (InRoot->GetTypeAsString() == TEXT("STextBlock")) { return StaticCastSharedRef<STextBlock>(InRoot)->GetText().ToString(); }
        if (InRoot->GetTypeAsString() == TEXT("SCkFlexText")) { return StaticCastSharedRef<SCkFlexText>(InRoot)->GetText().ToString(); }
        FString Result;
        FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        { Result += ReadText(Children->GetChildAt(Index)) + TEXT("\n"); }
        return Result;
    }

    auto Resources() -> FString
    {
        const TSharedPtr<IPlugin> Plugin = IPluginManager::Get().FindPlugin(TEXT("CkDebugger"));
        return Plugin.IsValid() ? FPaths::Combine(Plugin->GetBaseDir(), TEXT("Resources/UI")) : FString{};
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkAggroDebugger_AuthoredPie, "Ck.AggroDebugger.Authored.PIE", ck_tests_aggro_debugger_authored_pie::TestFlags)

bool FCkAggroDebugger_AuthoredPie::RunTest(const FString&)
{
    using namespace ck_tests_aggro_debugger_authored_pie;
    const TSharedRef<FState> State = MakeShared<FState>();

    if (!FSlateApplication::IsInitialized())
    {
        AddError(TEXT("Aggro authored preflight rejected: Slate is unavailable before PIE."));
        return false;
    }
    {
        FSlateApplication& Slate = FSlateApplication::Get();
        State->Panel = SNew(SCkAggroDebuggerWindow);
        State->WeakPanel = State->Panel;
        State->Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{520.0f, 620.0f})
            .CreateTitleBar(false).HasCloseButton(false)[State->Panel.ToSharedRef()];
        Slate.AddWindow(State->Window.ToSharedRef(), true);
        Tick(Slate);
        const TSharedPtr<FCkUiView> View = State->Panel->Get_AggroView();
        const TSharedPtr<const FCkUiCollection> Collection = State->Panel->Get_AggroCollection();
        const bool bLoaded = View.IsValid() && View->GetLastResult().Succeeded;
        const bool bSchema = Collection.IsValid() && HasSchema(Collection);
        const bool bControls = bLoaded && FindTagged(View->GetRegion(TEXT("controls")), TEXT("aggro-engaged-only")).IsValid();
        const bool bOverview = bLoaded && FindTagged(View->GetRegion(TEXT("overview")), TEXT("aggro-overview")).IsValid();
        const bool bSearch = bLoaded && FindTagged(View->GetRegion(TEXT("search")), TEXT("aggro-filter")).IsValid();
        const bool bMain = bLoaded && FindTagged(View->GetRegion(TEXT("main")), TEXT("aggro-records")).IsValid();
        State->bMountedUnavailable = bLoaded && bSchema && bControls && bOverview && bSearch && bMain;
        if (!State->bMountedUnavailable)
        {
            const FString Errors = View.IsValid() ? FString::Join(View->GetLastResult().Errors, TEXT(" | ")) : TEXT("view invalid");
            const FString Surface = State->Panel.IsValid() ? ReadText(State->Panel.ToSharedRef()) : TEXT("panel invalid");
            AddError(FString::Printf(TEXT("Aggro authored preflight rejected: loaded=%d schema=%d controls=%d overview=%d search=%d main=%d errors=[%s] surface=[%s]"),
                bLoaded, bSchema, bControls, bOverview, bSearch, bMain, *Errors, *Surface));
            if (State->Window.IsValid()) { Slate.DestroyWindowImmediately(State->Window.ToSharedRef()); }
            State->Window.Reset();
            State->Panel.Reset();
            Tick(Slate);
            return false;
        }
    }

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld* World) -> void
    {
        if (!IsValid(World)) { return; }
        State->Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(World);
        State->AggroEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(State->Owner);
        State->TrackedA = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(State->Owner);
        State->TrackedB = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(State->Owner);
        UCk_Utils_Handle_UE::Set_DebugName(State->AggroEntity, TEXT("AggroOwner"));
        UCk_Utils_Handle_UE::Set_DebugName(State->TrackedA, TEXT("TargetAlpha"));
        UCk_Utils_Handle_UE::Set_DebugName(State->TrackedB, TEXT("TargetBeta"));
        UCk_Utils_Transform_UE::Add(State->AggroEntity, FTransform{FVector::ZeroVector}, ECk_Replication::DoesNotReplicate);
        UCk_Utils_Transform_UE::Add(State->TrackedA, FTransform{FVector{100.0f, 0.0f, 0.0f}}, ECk_Replication::DoesNotReplicate);
        UCk_Utils_Transform_UE::Add(State->TrackedB, FTransform{FVector{100.0f, 0.0f, 0.0f}}, ECk_Replication::DoesNotReplicate);
        FCk_Fragment_Aggro_ParamsData AggroParams{};
        FCk_Fragment_AggroTarget_ParamsData TargetParams = AggroParams.Get_DefaultTargetParams();
        FCk_AggroTarget_LifetimeParams LifetimeParams = TargetParams.Get_LifetimeParams();
        LifetimeParams.Set_CanBeForgotten(ECk_EnableDisable::Disable);
        TargetParams.Set_LifetimeParams(LifetimeParams);
        AggroParams.Set_DefaultTargetParams(TargetParams);
        State->Aggro = UCk_Utils_Aggro_UE::Add(State->AggroEntity, AggroParams);
        State->TargetA = UCk_Utils_Aggro_UE::CreateTarget(State->Aggro, State->TrackedA);
        State->TargetB = UCk_Utils_Aggro_UE::CreateTarget(State->Aggro, State->TrackedB);
        UCk_Utils_AggroTarget_UE::Request_MarkPerceived(State->TargetA, FCk_Request_AggroTarget_MarkPerceived{}, {});
        UCk_Utils_AggroTarget_UE::Request_MarkPerceived(State->TargetB, FCk_Request_AggroTarget_MarkPerceived{}, {});
        UCk_Utils_AggroTarget_UE::Request_SetThreat(State->TargetA, 10.0f, {});
        UCk_Utils_AggroTarget_UE::Request_SetThreat(State->TargetB, 20.0f, {});
        State->bFixtureCreated = ck::IsValid(State->Owner) && ck::IsValid(State->Aggro) && ck::IsValid(State->TargetA) && ck::IsValid(State->TargetB);
    })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(60));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    {
        if (!State->bFixtureCreated || !ck::IsValid(State->Aggro) || !ck::IsValid(State->TargetA) || !ck::IsValid(State->TargetB)) { return false; }
        return UCk_Utils_Aggro_UE::Get_Debug_EvaluationCount(State->Aggro) > 0
            && UCk_Utils_Aggro_UE::Get_NumTrackedTargets(State->Aggro) == 2
            && UCk_Utils_AggroTarget_UE::Get_IsPerceived(State->TargetA) && UCk_Utils_AggroTarget_UE::Get_IsPerceived(State->TargetB)
            && UCk_Utils_AggroTarget_UE::Get_Threat(State->TargetA) == 10.0f && UCk_Utils_AggroTarget_UE::Get_Threat(State->TargetB) == 20.0f;
    }), 15.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    {
        const TSharedPtr<const FCkUiCollection> Collection = State->Panel.IsValid() ? State->Panel->Get_AggroCollection() : nullptr;
        return Collection.IsValid() && Collection->GetRecords().Num() == 3 && TargetRecord(Collection, TEXT("TargetAlpha")).IsValid()
            && TargetRecord(Collection, TEXT("TargetBeta")).IsValid();
    }), 15.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
    {
        if (!State->Panel.IsValid() || !FSlateApplication::IsInitialized()) { return; }
        FSlateApplication& Slate = FSlateApplication::Get();
        Tick(Slate);
        const TSharedPtr<FCkUiView> View = State->Panel->Get_AggroView();
        const TSharedPtr<const FCkUiCollection> Collection = State->Panel->Get_AggroCollection();
        if (!View.IsValid() || !Collection.IsValid()) { return; }
        const TSharedPtr<SEditableTextBox> Filter = FindSearchEditor(View->GetRegion(TEXT("search")), TEXT("aggro-filter"));
        const TSharedPtr<SEditableTextBox> Highlight = FindSearchEditor(View->GetRegion(TEXT("search")), TEXT("aggro-highlight"));
        const TSharedPtr<SCheckBox> Engaged = FindCheckbox(View->GetRegion(TEXT("controls")), TEXT("aggro-engaged-only"));
        State->StableARecord = TargetRecord(Collection, TEXT("TargetAlpha"));
        State->StableAKey = State->StableARecord.IsValid() ? State->StableARecord->GetKey() : FString{};
        State->InitialAIndex = TargetIndex(Collection, TEXT("TargetAlpha"));
        State->InitialBIndex = TargetIndex(Collection, TEXT("TargetBeta"));
        const TSharedPtr<SCkUiRepeat> Repeat = View->GetRepeat(TEXT("aggro-records"));
        State->StableAItem = Repeat.IsValid() ? Repeat->GetItemWidget(State->StableAKey) : nullptr;
        const TSharedPtr<const FCkUiRecord> Owner = OwnerRecord(Collection);
        const TSharedPtr<const FCkUiRecord> B = TargetRecord(Collection, TEXT("TargetBeta"));
        State->bInitialProjection = HasSchema(Collection) && Owner.IsValid() && FieldText(Owner, TEXT("aggro-owner-name")) == TEXT("AggroOwner")
            && State->StableARecord.IsValid() && B.IsValid()
            && FieldText(State->StableARecord, TEXT("aggro-threat-text")).Contains(TEXT("10.0"))
            && FMath::IsNearlyEqual(FieldNumber(State->StableARecord, TEXT("aggro-threat-fraction")), 0.5f)
            && FMath::IsNearlyEqual(FieldNumber(B, TEXT("aggro-threat-fraction")), 1.0f)
            && State->InitialAIndex > State->InitialBIndex;
        State->bControlsRouted = Filter.IsValid() && Highlight.IsValid() && Engaged.IsValid();
        if (!State->bControlsRouted) { return; }
        State->HeldFilter = Filter;
        State->bControlsRouted = Replace(Slate, Highlight.ToSharedRef(), TEXT("kept-draft")) && Replace(Slate, Filter.ToSharedRef(), TEXT("TargetBeta"));
        State->HighlightDraft = Highlight->GetText().ToString();
        State->FilterDraft = Filter->GetText().ToString();
        State->bHighlightIsInert = State->HighlightDraft == TEXT("kept-draft") && Collection->GetRecords().Num() == 3;
        State->bControlGeometry = Filter->GetCachedGeometry().GetLocalSize().X > 0.0f && Filter->GetCachedGeometry().GetLocalSize().Y > 0.0f
            && Highlight->GetCachedGeometry().GetLocalSize().X > 0.0f && Highlight->GetCachedGeometry().GetLocalSize().Y > 0.0f
            && Engaged->GetCachedGeometry().GetLocalSize().X > 0.0f && Engaged->GetCachedGeometry().GetLocalSize().Y > 0.0f;
    })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    { return State->Panel.IsValid() && State->Panel->Get_AggroCollection().IsValid() && State->Panel->Get_AggroCollection()->GetRecords().Num() == 3; }), 10.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
    {
        if (!State->Panel.IsValid() || !FSlateApplication::IsInitialized()) { return; }
        const TSharedPtr<FCkUiView> View = State->Panel->Get_AggroView();
        const TSharedPtr<SEditableTextBox> Filter = View.IsValid() ? FindSearchEditor(View->GetRegion(TEXT("search")), TEXT("aggro-filter")) : nullptr;
        if (!Filter.IsValid()) { return; }
        State->bTargetSearchKeepsOwner = Filter->GetText().ToString() == TEXT("TargetBeta") && State->Panel->Get_AggroCollection()->GetRecords().Num() == 3;
        if (Replace(FSlateApplication::Get(), Filter.ToSharedRef(), TEXT("AggroOwner")))
        {
            State->FilterDraft = Filter->GetText().ToString();
            State->bOwnerSearchKeepsSiblings = State->FilterDraft == TEXT("AggroOwner") && State->Panel->Get_AggroCollection()->GetRecords().Num() == 3;
        }
        UCk_Utils_Aggro_UE::Request_SetActiveTarget(State->Aggro, State->TrackedA, {});
    })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    {
        if (!State->bFixtureCreated || !ck::IsValid(State->Aggro) || !ck::IsValid(State->TrackedA) || !ck::IsValid(State->TargetA)) { return false; }
        return UCk_Utils_Aggro_UE::TryGet_ActiveTrackedEntity(State->Aggro) == State->TrackedA && UCk_Utils_AggroTarget_UE::Get_IsActiveTarget(State->TargetA);
    }), 15.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
    {
        if (!State->Panel.IsValid() || !FSlateApplication::IsInitialized()) { return; }
        const TSharedPtr<FCkUiView> View = State->Panel->Get_AggroView();
        const TSharedPtr<SCheckBox> Engaged = View.IsValid() ? FindCheckbox(View->GetRegion(TEXT("controls")), TEXT("aggro-engaged-only")) : nullptr;
        if (!Engaged.IsValid()) { return; }
        const bool bClicked = Click(FSlateApplication::Get(), Engaged.ToSharedRef()) && Engaged->IsChecked();
        Tick(FSlateApplication::Get());
        const TSharedPtr<const FCkUiRecord> Owner = OwnerRecord(State->Panel->Get_AggroCollection());
        State->bEngagedOnlyRouted = bClicked && State->Panel->Get_AggroCollection()->GetRecords().Num() == 3 && Owner.IsValid()
            && FieldText(Owner, TEXT("aggro-owner-active")).Contains(TEXT("TargetAlpha"));
        const FString Directory = Resources();
        if (State->Window.IsValid())
        {
            State->Window->Resize(FVector2D{960.0f, 640.0f});
            Tick(FSlateApplication::Get());
            State->bWideCapture = SaveCapture(FSlateApplication::Get(), State->Window.ToSharedRef(), FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Automation/AggroDebugger/AuthoredPie-Wide.png")));
            State->Window->Resize(FVector2D{520.0f, 620.0f});
            Tick(FSlateApplication::Get());
            State->bNarrowCapture = SaveCapture(FSlateApplication::Get(), State->Window.ToSharedRef(), FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Automation/AggroDebugger/AuthoredPie-Narrow.png")));
        }
        const TSharedPtr<SEditableTextBox> Filter = View.IsValid() ? FindSearchEditor(View->GetRegion(TEXT("search")), TEXT("aggro-filter")) : nullptr;
        if (!Directory.IsEmpty() && Filter.IsValid())
        {
            const int64 Revision = View->GetRevision();
            const FCkUiLoadResult Accepted = View->ReloadFiles(FPaths::Combine(Directory, TEXT("AggroDebugger.ui.html")), FPaths::Combine(Directory, TEXT("AggroDebugger.ui.css")));
            Tick(FSlateApplication::Get());
            State->bCompatibleReloadRetained = Accepted.Succeeded && View->GetRevision() > Revision
                && FindSearchEditor(View->GetRegion(TEXT("search")), TEXT("aggro-filter")) == Filter && Filter->GetText().ToString() == State->FilterDraft
                && FindSearchEditor(View->GetRegion(TEXT("search")), TEXT("aggro-highlight")).IsValid()
                && FindSearchEditor(View->GetRegion(TEXT("search")), TEXT("aggro-highlight"))->GetText().ToString() == State->HighlightDraft;
            const int64 RejectRevision = View->GetRevision();
            const FCkUiLoadResult Rejected = View->TryReload(TEXT("<ui version=\"1\"><region name=\"main\"><unsupported-aggro-node/></region></ui>"), TEXT(""), TEXT("AggroDebuggerRejectedReload"));
            Tick(FSlateApplication::Get());
            State->bRejectedReloadPreserved = !Rejected.Succeeded && View->GetRevision() == RejectRevision
                && FindSearchEditor(View->GetRegion(TEXT("search")), TEXT("aggro-filter")) == Filter && Filter->GetText().ToString() == State->FilterDraft
                && FindSearchEditor(View->GetRegion(TEXT("search")), TEXT("aggro-highlight")).IsValid()
                && FindSearchEditor(View->GetRegion(TEXT("search")), TEXT("aggro-highlight"))->GetText().ToString() == State->HighlightDraft;
        }
        UCk_Utils_AggroTarget_UE::Request_SetThreat(State->TargetA, 80.0f, {});
    })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(60));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    {
        if (!State->bFixtureCreated || !ck::IsValid(State->Aggro) || !ck::IsValid(State->TargetA) || !ck::IsValid(State->TargetB)) { return false; }
        return UCk_Utils_AggroTarget_UE::Get_Threat(State->TargetA) == 80.0f && UCk_Utils_AggroTarget_UE::Get_Score(State->TargetA) > UCk_Utils_AggroTarget_UE::Get_Score(State->TargetB);
    }), 15.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
    {
        if (!State->Panel.IsValid()) { return; }
        const TSharedPtr<FCkUiView> View = State->Panel->Get_AggroView();
        const TSharedPtr<const FCkUiCollection> Collection = State->Panel->Get_AggroCollection();
        const TSharedPtr<const FCkUiRecord> A = TargetRecord(Collection, TEXT("TargetAlpha"));
        const TSharedPtr<SCkUiRepeat> Repeat = View.IsValid() ? View->GetRepeat(TEXT("aggro-records")) : nullptr;
        State->bRankIdentityRetained = A.IsValid() && A == State->StableARecord && Repeat.IsValid()
            && State->StableAItem.IsValid() && Repeat->GetItemWidget(State->StableAKey) == State->StableAItem
            && FieldText(A, TEXT("aggro-threat-text")).Contains(TEXT("80.0"))
            && FMath::IsNearlyEqual(FieldNumber(A, TEXT("aggro-threat-fraction")), 1.0f)
            && FMath::IsNearlyEqual(FieldNumber(A, TEXT("aggro-score-fraction")), 1.0f)
            && State->InitialAIndex > State->InitialBIndex
            && TargetIndex(Collection, TEXT("TargetAlpha")) < TargetIndex(Collection, TEXT("TargetBeta"));
        UCk_Utils_Aggro_UE::Request_RemoveTarget(State->Aggro, State->TrackedB, {});
    })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(30));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    {
        if (!State->bFixtureCreated || !ck::IsValid(State->Aggro) || !ck::IsValid(State->TrackedB)) { return false; }
        return !ck::IsValid(UCk_Utils_Aggro_UE::TryGet_Target_ByTrackedEntity(State->Aggro, State->TrackedB)) && UCk_Utils_Aggro_UE::Get_NumTrackedTargets(State->Aggro) == 1;
    }), 15.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
    { return State->Panel.IsValid() && State->Panel->Get_AggroCollection().IsValid() && State->Panel->Get_AggroCollection()->GetRecords().Num() == 2; }), 15.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
    {
        const TSharedPtr<const FCkUiCollection> Collection = State->Panel.IsValid() ? State->Panel->Get_AggroCollection() : nullptr;
        State->bRemovalAtomic = Collection.IsValid() && Collection->GetRecords().Num() == 2 && TargetRecord(Collection, TEXT("TargetAlpha")) == State->StableARecord
            && !TargetRecord(Collection, TEXT("TargetBeta")).IsValid();
    })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this, FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
    {
        TestTrue(TEXT("Authored Aggro view mounts controls, overview, search and collection schema before PIE"), State->bMountedUnavailable);
        TestTrue(TEXT("Real authority Aggro owner and targets project through authored rows"), State->bFixtureCreated && State->bInitialProjection);
        TestTrue(TEXT("Target-name filter keeps the complete owner group"), State->bTargetSearchKeepsOwner);
        TestTrue(TEXT("Owner-name filter keeps its target siblings"), State->bOwnerSearchKeepsSiblings);
        TestTrue(TEXT("Highlight retains its draft without changing the projection"), State->bHighlightIsInert);
        TestTrue(TEXT("Engaged-only control follows a public active-target request"), State->bEngagedOnlyRouted);
        TestTrue(TEXT("Wide and narrow authored captures retain usable controls"), State->bWideCapture && State->bNarrowCapture && State->bControlGeometry);
        TestTrue(TEXT("Compatible installed-resource reload preserves retained filter and highlight drafts"), State->bCompatibleReloadRetained);
        TestTrue(TEXT("Rejected installed-resource reload preserves retained filter and highlight drafts"), State->bRejectedReloadPreserved);
        TestTrue(TEXT("Rank changes retain the surviving keyed record and repeat item"), State->bRankIdentityRetained);
        TestTrue(TEXT("Target removal atomically removes only the departed target row"), State->bRemovalAtomic);
        return State->bMountedUnavailable && State->bFixtureCreated && State->bInitialProjection && State->bTargetSearchKeepsOwner
            && State->bOwnerSearchKeepsSiblings && State->bControlsRouted && State->bHighlightIsInert && State->bEngagedOnlyRouted && State->bWideCapture
            && State->bNarrowCapture && State->bControlGeometry && State->bCompatibleReloadRetained && State->bRejectedReloadPreserved
            && State->bRankIdentityRetained && State->bRemovalAtomic;
    }), TEXT("Aggro debugger authored PIE uses real authority data and retained projection")));

    ADD_LATENT_AUTOMATION_COMMAND(FDelayedFunctionLatentCommand([State]() -> void
    {
        if (FSlateApplication::IsInitialized() && State->Window.IsValid()) { FSlateApplication::Get().DestroyWindowImmediately(State->Window.ToSharedRef()); }
        State->WeakView = State->Panel.IsValid() ? State->Panel->Get_AggroView() : nullptr;
        State->Window.Reset();
        State->Panel.Reset();
        if (FSlateApplication::IsInitialized()) { Tick(FSlateApplication::Get()); }
        if (State->HeldFilter.IsValid()) { State->HeldFilter->SetText(FText::FromString(TEXT("stale-dispatch"))); }
        State->bStaleCallbackInert = State->HeldFilter.IsValid() && !State->WeakPanel.IsValid() && !State->WeakView.IsValid();
        State->HeldFilter.Reset();
        if (ck::IsValid(State->Owner)) { UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(State->Owner); }
        State->Owner = {};
        State->AggroEntity = {};
        State->TrackedA = {};
        State->TrackedB = {};
        State->Aggro = {};
        State->TargetA = {};
        State->TargetB = {};
    }));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this, FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
    {
        TestTrue(TEXT("Held authored callback is inert after the Aggro owner surface is released"), State->bStaleCallbackInert);
        return State->bStaleCallbackInert;
    }), TEXT("Aggro debugger fixture releases Slate before transient ECS ownership")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif
