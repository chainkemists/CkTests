#include "CoreMinimal.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkVisualLodDebugger/Window/SCkVisualLodDebuggerWindow.h"
#include "CkVisualLodDebugger/Data/CkVisualLodDebugger_Types.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcsExt/Transform/CkTransform_Utils.h"
#include "CkIskmRenderer/Renderer/CkIskmRenderer_Fragment_Data.h"
#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/SCkUiRepeat.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkVisualLod/CkVisualLodArbiter_Utils.h"
#include "CkVisualLod/CkVisualLod_Utils.h"
#include "CkDebuggerCommon/Widgets/SCkDebug_InspectorPanel.h"

#include "Framework/Application/SlateApplication.h"
#include "Application/ThrottleManager.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformMath.h"
#include "ImageUtils.h"
#include "Input/Events.h"
#include "Interfaces/IPluginManager.h"
#include "Misc/AutomationTest.h"
#include "Misc/Paths.h"
#include "UObject/UObjectIterator.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/Input/SEditableTextBox.h"
#include "Widgets/Layout/SScrollBox.h"
#include "Widgets/SWindow.h"

namespace ck_tests_visual_lod_arbiter_tuners_pie
{
    constexpr auto TestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;

    struct FState final
    {
        FCk_Handle Owner;
        FCk_Handle_VisualLodArbiter ArbiterA;
        FCk_Handle_VisualLodArbiter ArbiterB;
        FCk_Handle MemberA;
        FCk_Handle MemberB;
        TWeakObjectPtr<UCk_VisualLodArbiter_Data> ConfigB;
        TSharedPtr<SCkVisualLodDebuggerWindow> Panel;
        TSharedPtr<SWindow> Window;
        TSharedPtr<SWindow> StaleWindow;
        TSharedPtr<FCkUiView> ViewA;
        TSharedPtr<SEditableTextBox> StaleEditor;
        TWeakPtr<SCkVisualLodDebuggerWindow> WeakPanel;
        TWeakPtr<FCkUiView> WeakViewA;
        FCk_VisualLodArbiter_RuntimeTuners BeforeA;
        FCk_VisualLodArbiter_RuntimeTuners ExpectedB;
        FCk_VisualLodArbiter_RuntimeTuners AuthoredB;
        bool bFixtureCreated = false;
        bool bUnavailableTunersExpanded = false;
        bool bUnavailableViewMounted = false;
        bool bUnavailableResetMounted = false;
        bool bUnavailableResetDisabled = false;
        bool bMembersResolved = false;
        bool bTargetedA = false;
        bool bSwitchedToB = false;
        bool bStaleCommitRejected = false;
        bool bStaleCommitDispatched = false;
        int32 StaleTickPolls = 0;
        bool bCompatibleReloadRetainedDraft = false;
        bool bRejectedReloadRetainedDraft = false;
        bool bReloadDraftCancelled = false;
        bool bAllNativeFieldsCommitted = false;
        bool bLastNativeFieldCommitted = false;
        bool bLastNativeFocusMatched = false;
        FString LastNativeFocusedLeaf;
        FString LastNativeDraftBeforeEnter;
        FString LastNativeTextAfterEnter;
        bool bMalformedFadeErrorVisible = false;
        bool bMalformedFadeAllowsExpensiveTasks = false;
        bool bPromoteClicked = false;
        bool bUnrenderedClicked = false;
        bool bResetClicked = false;
        bool bCrowdTunersLoaded = false;
        bool bInnermostProfileCommitDispatched = false;
        bool bInnermostProfileCommitted = false;
        bool bDynamicTargetBRequested = false;
        bool bDynamicReadinessReady = false;
        bool bDynamicControlsPrepared = false;
        FString DynamicReadinessStage;
        FString DynamicReadinessDiagnostics;
        FString CrowdKey;
        FString InnermostBandKey;
        FCk_VisualLodArbiter_RuntimeTuners ExpectedCrowdProfileB;
        bool bWideDynamicCrowdCapture = false;
        bool bNarrowDynamicCrowdCapture = false;
        bool bTornDown = false;
    };

    struct FNativeCase final
    {
        FName Id;
        FString Value;
        TFunction<void(FCk_VisualLodArbiter_RuntimeTuners&)> Apply;
    };

    auto Tick(FSlateApplication& InSlate) -> void
    {
        InSlate.PumpMessages();
        InSlate.Tick();
        InSlate.Tick();
    }

    auto FocusPathContains(FSlateApplication& InSlate, const TSharedRef<SWidget>& InWidget) -> bool
    {
        const TSharedPtr<SWidget> Focused = InSlate.GetUserFocusedWidget(0);
        if (!Focused.IsValid()) { return false; }
        FWidgetPath Path;
        if (!InSlate.GeneratePathToWidgetUnchecked(Focused.ToSharedRef(), Path)) { return false; }
        for (int32 Index = 0; Index < Path.Widgets.Num(); ++Index)
        {
            if (Path.Widgets[Index].Widget == InWidget) { return true; }
        }
        return false;
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

    auto FindButtonDescendant(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SButton>
    {
        if (InRoot->GetTypeAsString() == TEXT("SButton")) { return StaticCastSharedRef<SButton>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SButton> Found = FindButtonDescendant(
                ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid())
            { return Found; }
        }
        return {};
    }

    auto FindButton(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SButton>
    {
        const TSharedPtr<SWidget> Tagged = FindTagged(InRoot, InTag);
        return Tagged.IsValid() ? FindButtonDescendant(Tagged.ToSharedRef()) : nullptr;
    }

    auto FindInspectorPanel(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SCkDebug_InspectorPanel>
    {
        if (InRoot->GetTypeAsString() == TEXT("SCkDebug_InspectorPanel"))
        { return StaticCastSharedRef<SCkDebug_InspectorPanel>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SCkDebug_InspectorPanel> Found = FindInspectorPanel(
                ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid())
            { return Found; }
        }
        return {};
    }

    auto FindEditor(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SEditableTextBox>
    {
        if (InRoot->GetTag() == InTag && InRoot->GetTypeAsString() == TEXT("SCkUiTextInputBox"))
        { return StaticCastSharedRef<SEditableTextBox>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SEditableTextBox> Found = FindEditor(
                ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag); Found.IsValid())
            { return Found; }
        }
        return {};
    }

    auto FindRepeat(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SCkUiRepeat>
    {
        if (InRoot->GetTag() == InTag && InRoot->GetTypeAsString() == TEXT("SCkUiRepeat"))
        { return StaticCastSharedRef<SCkUiRepeat>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SCkUiRepeat> Found = FindRepeat(
                ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag); Found.IsValid())
            { return Found; }
        }
        return {};
    }

    auto Click(FSlateApplication& InSlate, const TSharedRef<SWidget>& InWidget) -> bool
    {
        const FGeometry Geometry = InWidget->GetCachedGeometry();
        const TSharedPtr<SWindow> Window = InSlate.FindWidgetWindow(InWidget);
        if (!Window.IsValid() || !Window->GetNativeWindow().IsValid() ||
            Geometry.GetLocalSize().X <= 0.0f || Geometry.GetLocalSize().Y <= 0.0f)
        { return false; }

        const FVector2D Position = Geometry.LocalToAbsolute(Geometry.GetLocalSize() * 0.5f);
        const TSet<FKey> NoButtons;
        const TSet<FKey> LeftDown{EKeys::LeftMouseButton};
        const FPointerEvent Move(0, FSlateApplication::CursorPointerIndex, Position, Position,
            NoButtons, EKeys::Invalid, 0.0f, FModifierKeysState{});
        const FPointerEvent Down(0, FSlateApplication::CursorPointerIndex, Position, Position,
            LeftDown, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        const FPointerEvent Up(0, FSlateApplication::CursorPointerIndex, Position, Position,
            NoButtons, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        InSlate.SetCursorPos(Position);
        InSlate.ProcessMouseMoveEvent(Move, true);
        const bool bHandled = InSlate.ProcessMouseButtonDownEvent(Window->GetNativeWindow(), Down);
        InSlate.ProcessMouseButtonUpEvent(Up);
        Tick(InSlate);
        return bHandled;
    }

    struct FReplaceDiagnostics final
    {
        bool bFocusMatched = false;
        FString FocusedLeaf;
        FString DraftBeforeEnter;
        FString TextAfterEnter;
    };

    auto Replace(FSlateApplication& InSlate, const TSharedRef<SEditableTextBox>& InEditor, const FString& InText,
        const bool bCommit, FReplaceDiagnostics* OutDiagnostics = nullptr) -> bool
    {
        if (OutDiagnostics != nullptr) { *OutDiagnostics = {}; }
        if (!FocusPathContains(InSlate, InEditor))
        { InSlate.SetUserFocus(0, InEditor, EFocusCause::SetDirectly); }
        Tick(InSlate);
        const TSharedPtr<SWidget> Focused = InSlate.GetUserFocusedWidget(0);
        const bool bFocusMatched = FocusPathContains(InSlate, InEditor);
        if (OutDiagnostics != nullptr)
        {
            OutDiagnostics->bFocusMatched = bFocusMatched;
            OutDiagnostics->FocusedLeaf = Focused.IsValid() ? Focused->GetTypeAsString() : TEXT("<none>");
        }
        if (!bFocusMatched) { return false; }
        const FModifierKeysState Control{false, false, true, false, false, false, false, false, false};
        if (!InSlate.ProcessKeyDownEvent(FKeyEvent{EKeys::A, Control, 0, false, 0, 0})) { return false; }
        for (const TCHAR Character : InText)
        {
            if (!InSlate.ProcessKeyCharEvent(FCharacterEvent{Character, FModifierKeysState{}, 0, false}))
            { return false; }
        }
        if (OutDiagnostics != nullptr)
        {
            InEditor->SelectAllText();
            OutDiagnostics->DraftBeforeEnter = InEditor->GetSelectedText().ToString();
        }
        if (bCommit && !InSlate.ProcessKeyDownEvent(FKeyEvent{EKeys::Enter, FModifierKeysState{}, 0, false, 0, 0}))
        { return false; }
        if (OutDiagnostics != nullptr)
        {
            OutDiagnostics->TextAfterEnter = InEditor->GetText().ToString();
        }
        Tick(InSlate);
        return true;
    }

    auto SaveCapture(FSlateApplication& InSlate, const TSharedRef<SWidget>& InRoot, const FString& InPath) -> bool
    {
        TArray<FColor> Pixels;
        FIntVector Size = FIntVector::ZeroValue;
        if (!InSlate.TakeScreenshot(InRoot, Pixels, Size) || Size.X <= 0 || Size.Y <= 0 || Pixels.Num() < Size.X * Size.Y)
        { return false; }
        IFileManager::Get().MakeDirectory(*FPaths::GetPath(InPath), true);
        const FImageView Image(Pixels.GetData(), Size.X, Size.Y, ERawImageFormat::BGRA8);
        return FImageUtils::SaveImageByExtension(*InPath, Image);
    }

    auto FindConfig(const TCHAR* InName) -> UCk_VisualLodArbiter_Data*
    {
        for (TObjectIterator<UCk_VisualLodArbiter_Data> It; It; ++It)
        {
            if (It->GetName() == InName) { return *It; }
        }
        return nullptr;
    }

    auto FindRendererData() -> UCk_IskmRenderer_Data*
    {
        for (TObjectIterator<UCk_IskmRenderer_Data> It; It; ++It)
        {
            if (It->GetName() == TEXT("Asset_RendererData_Demo")) { return *It; }
        }
        return nullptr;
    }

    auto SameTuners(const FCk_VisualLodArbiter_RuntimeTuners& A,
        const FCk_VisualLodArbiter_RuntimeTuners& B) -> bool
    {
        FCkVisualLodDebugger_ArbiterInfo Comparison;
        Comparison.RuntimeTuners = A;
        Comparison.AuthoredRuntimeTuners = B;
        return !Comparison.Get_RuntimeTunersDifferFromAuthored();
    }

    auto TryGetRuntimeTuners(const FCk_Handle_VisualLodArbiter& InArbiter,
        FCk_VisualLodArbiter_RuntimeTuners& OutTuners) -> bool
    {
        if (ck::Is_NOT_Valid(InArbiter) || !UCk_Utils_VisualLodArbiter_UE::Has(InArbiter)) { return false; }
        OutTuners = UCk_Utils_VisualLodArbiter_UE::Get_RuntimeTuners(InArbiter);
        return true;
    }

    auto RuntimeTunersMatch(const FCk_Handle_VisualLodArbiter& InArbiter,
        const FCk_VisualLodArbiter_RuntimeTuners& InExpected) -> bool
    {
        FCk_VisualLodArbiter_RuntimeTuners Actual;
        return TryGetRuntimeTuners(InArbiter, Actual) && SameTuners(Actual, InExpected);
    }

    auto DescribeTuners(const FCk_VisualLodArbiter_RuntimeTuners& InTuners) -> FString
    {
        return FString::Printf(
            TEXT("near=%d lock=%d preempts=%d promote=%.9g demote=%.9g lockMax=%.9g always=%.9g view=%.9g preempt=%.9g fade=%.9g lead=%.9g lag=%.9g policy=%d crowds=%d"),
            InTuners.Get_NearBudget(), InTuners.Get_LockBudget(), InTuners.Get_MaxPreemptsPerTick(),
            InTuners.Get_PromoteDistance(), InTuners.Get_DemoteDistance(), InTuners.Get_LockPromoteMaxDistance(),
            InTuners.Get_AlwaysInViewDistance(), InTuners.Get_ViewConeMarginDeg(), InTuners.Get_PreemptDistanceMargin(),
            InTuners.Get_FadeDuration().Get_Seconds(), InTuners.Get_FadeAnchorLeadFrames(),
            InTuners.Get_FadeAnchorBakeLagIntervals(), static_cast<int32>(InTuners.Get_ExhaustionPolicy()),
            InTuners.Get_CrowdTuners().Num());
    }

    auto GetResources() -> FString
    {
        const TSharedPtr<IPlugin> Plugin = IPluginManager::Get().FindPlugin(TEXT("CkDebugger"));
        return Plugin.IsValid() ? FPaths::Combine(Plugin->GetBaseDir(), TEXT("Resources/UI")) : FString{};
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkVisualLod_ArbiterTunersPie,
    "Ck.VisualLodDebugger.ArbiterTuners.PIE",
    ck_tests_visual_lod_arbiter_tuners_pie::TestFlags)

bool FCkVisualLod_ArbiterTunersPie::RunTest(const FString&)
{
    using namespace ck_tests_visual_lod_arbiter_tuners_pie;

    const TSharedRef<FState> State = MakeShared<FState>();
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld* InWorld) -> void
        {
            if (!IsValid(InWorld) || !FSlateApplication::IsInitialized()) { return; }

            FSlateApplication& Slate = FSlateApplication::Get();
            State->Panel = SNew(SCkVisualLodDebuggerWindow);
            State->WeakPanel = State->Panel;
            State->Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{360.0f, 520.0f})
                .CreateTitleBar(false).HasCloseButton(false)[State->Panel.ToSharedRef()];
            Slate.AddWindow(State->Window.ToSharedRef(), true);
            Tick(Slate);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
        {
            if (!State->Panel.IsValid() || !FSlateApplication::IsInitialized()) { return; }
            const TSharedPtr<SCkDebug_InspectorPanel> Tuners = FindInspectorPanel(State->Panel.ToSharedRef());
            const TSharedPtr<SButton> TunersHeader = Tuners.IsValid() ? FindButtonDescendant(Tuners.ToSharedRef()) : nullptr;
            if (!Tuners.IsValid() || !TunersHeader.IsValid()) { return; }
            if (!Tuners->Is_Expanded() && !Click(FSlateApplication::Get(), TunersHeader.ToSharedRef())) { return; }
            Tick(FSlateApplication::Get());
            State->bUnavailableTunersExpanded = Tuners->Is_Expanded();
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
        {
            if (!State->bUnavailableTunersExpanded || !State->Panel.IsValid()) { return false; }
            const TSharedPtr<FCkUiView> View = State->Panel->Get_ArbiterTunersView();
            if (!View.IsValid() || !View->GetLastResult().Succeeded) { return false; }
            const TSharedPtr<SButton> Reset = FindButton(View->GetRegion(TEXT("main")), TEXT("vl-arbiter-reset"));
            if (!Reset.IsValid() || !FSlateApplication::Get().FindWidgetWindow(Reset.ToSharedRef()).IsValid()) { return false; }
            State->bUnavailableViewMounted = true;
            State->bUnavailableResetMounted = true;
            State->bUnavailableResetDisabled = !Reset->IsEnabled();
            return true;
        }), 15.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld* InWorld) -> void
        {
            UCk_VisualLodArbiter_Data* ConfigA = FindConfig(TEXT("Asset_VisualLodArbiterTunersPie_ConfigA"));
            UCk_VisualLodArbiter_Data* ConfigB = FindConfig(TEXT("Asset_VisualLodArbiterTunersPie_ConfigB"));
            UCk_IskmRenderer_Data* RendererData = FindRendererData();
            if (!IsValid(InWorld) || !IsValid(ConfigA) || !IsValid(ConfigB) || !IsValid(RendererData)) { return; }
            State->Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InWorld);
            FCk_Handle ArbiterAEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(State->Owner);
            FCk_Handle ArbiterBEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(State->Owner);
            const FCk_Fragment_VisualLodArbiter_ParamsData ArbiterAParams{ConfigA};
            const FCk_Fragment_VisualLodArbiter_ParamsData ArbiterBParams{ConfigB};
            State->ArbiterA = UCk_Utils_VisualLodArbiter_UE::Add(ArbiterAEntity, ArbiterAParams);
            State->ArbiterB = UCk_Utils_VisualLodArbiter_UE::Add(ArbiterBEntity, ArbiterBParams);

            State->MemberA = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(State->Owner);
            State->MemberB = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(State->Owner);
            UCk_Utils_Transform_UE::Add(State->MemberA, FTransform{FVector{0.0f, 0.0f, 0.0f}}, ECk_Replication::DoesNotReplicate);
            UCk_Utils_Transform_UE::Add(State->MemberB, FTransform{FVector{100.0f, 0.0f, 0.0f}}, ECk_Replication::DoesNotReplicate);
            FCk_Fragment_VisualLod_ParamsData MemberAParams{ConfigA->Get_DomainTag()};
            FCk_Fragment_VisualLod_ParamsData MemberBParams{ConfigB->Get_DomainTag()};
            MemberAParams.Set_Renderer(RendererData);
            MemberBParams.Set_Renderer(RendererData);
            UCk_Utils_VisualLod_UE::Add(State->MemberA, MemberAParams);
            UCk_Utils_VisualLod_UE::Add(State->MemberB, MemberBParams);

            State->ConfigB = ConfigB;
            State->AuthoredB = ck::visual_lod::MakeRuntimeTuners(*ConfigB);
            State->ExpectedB = State->AuthoredB;
            State->bFixtureCreated = ck::IsValid(State->Owner) && ck::IsValid(State->ArbiterA)
                && ck::IsValid(State->ArbiterB) && ck::IsValid(State->MemberA) && ck::IsValid(State->MemberB);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
        {
            if (!State->bFixtureCreated
                || !UCk_Utils_VisualLodArbiter_UE::Has(State->ArbiterA)
                || !UCk_Utils_VisualLodArbiter_UE::Has(State->ArbiterB)
                || !UCk_Utils_VisualLod_UE::Has(State->MemberA)
                || !UCk_Utils_VisualLod_UE::Has(State->MemberB)
                || State->MemberA.Get<ck::FFragment_VisualLod_Current>().Get_Arbiter() != State->ArbiterA
                || State->MemberB.Get<ck::FFragment_VisualLod_Current>().Get_Arbiter() != State->ArbiterB)
            { return false; }
            if (!State->Panel.IsValid()) { return false; }
            State->bMembersResolved = true;
            State->Panel->TargetEntity(State->MemberA);
            return State->Panel->Get_ArbiterTunersView().IsValid();
        }), 15.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
        {
            if (!State->Panel.IsValid() || !FSlateApplication::IsInitialized()
                || !UCk_Utils_VisualLodArbiter_UE::Has(State->ArbiterA)
                || !UCk_Utils_VisualLodArbiter_UE::Has(State->ArbiterB)) { return; }
            Tick(FSlateApplication::Get());
            State->ViewA = State->Panel->Get_ArbiterTunersView();
            State->WeakViewA = State->ViewA;
            if (!State->ViewA.IsValid() || !State->ViewA->GetLastResult().Succeeded) { return; }
            const TSharedPtr<SCkDebug_InspectorPanel> Tuners = FindInspectorPanel(State->Panel.ToSharedRef());
            const TSharedPtr<SButton> TunersHeader = Tuners.IsValid() ? FindButtonDescendant(Tuners.ToSharedRef()) : nullptr;
            if (!Tuners.IsValid() || !TunersHeader.IsValid()
                || (!Tuners->Is_Expanded() && !Click(FSlateApplication::Get(), TunersHeader.ToSharedRef()))
                || !Tuners->Is_Expanded()) { return; }
            const TSharedRef<SWidget> Region = State->ViewA->GetRegion(TEXT("main"));
            const TSharedPtr<SScrollBox> Scroll = State->ViewA->GetScroll(TEXT("vl-arbiter-scroll"));
            const TSharedPtr<SEditableTextBox> Editor = FindEditor(Region, TEXT("vl-arbiter-fade-duration-input"));
            if (!Scroll.IsValid() || !Editor.IsValid()) { return; }
            Scroll->ScrollDescendantIntoView(Editor.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
            Tick(FSlateApplication::Get());
            if (!TryGetRuntimeTuners(State->ArbiterA, State->BeforeA)) { return; }
            State->StaleEditor = Editor;
            State->bTargetedA = Replace(FSlateApplication::Get(), Editor.ToSharedRef(), TEXT("0.731"), false)
                && Editor->GetText().ToString() == TEXT("0.731");
            State->Panel->TargetEntity(State->MemberB);
            Tick(FSlateApplication::Get());
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
        {
            return State->Panel.IsValid() && State->ViewA.IsValid()
                && State->Panel->Get_ArbiterTunersView().IsValid()
                && State->Panel->Get_ArbiterTunersView() != State->ViewA;
        }), 15.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
        {
            if (!State->Panel.IsValid() || !State->ViewA.IsValid() || !State->StaleEditor.IsValid() || !FSlateApplication::IsInitialized()) { return; }
            const TSharedPtr<FCkUiView> ViewB = State->Panel->Get_ArbiterTunersView();
            if (!ViewB.IsValid() || ViewB == State->ViewA) { return; }
            State->bSwitchedToB = true;
            State->StaleWindow = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{420.0f, 260.0f})
                .CreateTitleBar(false).HasCloseButton(false)[State->ViewA->GetRegion(TEXT("main"))];
            FSlateApplication::Get().AddWindow(State->StaleWindow.ToSharedRef(), true);
            Tick(FSlateApplication::Get());
            State->bStaleCommitDispatched = Replace(FSlateApplication::Get(), State->StaleEditor.ToSharedRef(), TEXT("0.741"), true);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
        {
            // A false first poll forces a real PIE update between the held old-view event and the public readback.
            return ++State->StaleTickPolls >= 2;
        }), 5.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
        {
            State->bStaleCommitRejected = false;
            if (State->ViewA.IsValid() && State->StaleEditor.IsValid()
                && UCk_Utils_VisualLodArbiter_UE::Has(State->ArbiterA)
                && UCk_Utils_VisualLodArbiter_UE::Has(State->ArbiterB))
            {
                const TSharedPtr<SButton> StaleReset = FindButton(State->ViewA->GetRegion(TEXT("main")), TEXT("vl-arbiter-reset"));
                State->bStaleCommitRejected = !State->StaleEditor->IsEnabled()
                    && StaleReset.IsValid() && !StaleReset->IsEnabled()
                    && RuntimeTunersMatch(State->ArbiterA, State->BeforeA)
                    && RuntimeTunersMatch(State->ArbiterB, State->AuthoredB);
            }
            if (FSlateApplication::IsInitialized() && State->StaleWindow.IsValid())
            { FSlateApplication::Get().DestroyWindowImmediately(State->StaleWindow.ToSharedRef()); }
            State->StaleWindow.Reset();
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
        {
            if (!State->Panel.IsValid() || !FSlateApplication::IsInitialized()) { return; }
            const TSharedPtr<FCkUiView> ViewB = State->Panel->Get_ArbiterTunersView();
            if (!ViewB.IsValid()) { return; }
            const TSharedRef<SWidget> Region = ViewB->GetRegion(TEXT("main"));
            const TSharedPtr<SScrollBox> Scroll = ViewB->GetScroll(TEXT("vl-arbiter-scroll"));
            const TSharedPtr<SEditableTextBox> DraftEditor = FindEditor(Region, TEXT("vl-arbiter-fade-duration-input"));
            if (!Scroll.IsValid() || !DraftEditor.IsValid()) { return; }
            Scroll->ScrollDescendantIntoView(DraftEditor.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
            Tick(FSlateApplication::Get());
            const bool bDrafted = Replace(FSlateApplication::Get(), DraftEditor.ToSharedRef(), TEXT("0.611"), false);
            const TSharedPtr<SWidget> FocusBefore = FSlateApplication::Get().GetUserFocusedWidget(0);
            const FString Resources = GetResources();
            const FCkUiLoadResult Reload = ViewB->ReloadFiles(
                FPaths::Combine(Resources, TEXT("VisualLodArbiterTuners.ui.html")),
                FPaths::Combine(Resources, TEXT("VisualLodArbiterTuners.ui.css")));
            Tick(FSlateApplication::Get());
            State->bCompatibleReloadRetainedDraft = bDrafted && Reload.Succeeded
                && FindEditor(ViewB->GetRegion(TEXT("main")), TEXT("vl-arbiter-fade-duration-input")) == DraftEditor
                && FSlateApplication::Get().GetUserFocusedWidget(0) == FocusBefore
                && DraftEditor->GetText().ToString() == TEXT("0.611");
            const int64 RevisionBeforeReject = ViewB->GetRevision();
            const FCkUiLoadResult Rejected = ViewB->TryReload(
                TEXT("<ui version=\"1\"><region name=\"main\"><unsupported-tuner-node/></region></ui>"),
                TEXT(""), TEXT("ArbiterTunersRejectedReload"));
            Tick(FSlateApplication::Get());
            State->bRejectedReloadRetainedDraft = !Rejected.Succeeded && ViewB->GetRevision() == RevisionBeforeReject
                && FindEditor(ViewB->GetRegion(TEXT("main")), TEXT("vl-arbiter-fade-duration-input")) == DraftEditor
                && FSlateApplication::Get().GetUserFocusedWidget(0) == FocusBefore
                && DraftEditor->GetText().ToString() == TEXT("0.611");
            State->bReloadDraftCancelled = FSlateApplication::Get().ProcessKeyDownEvent(
                FKeyEvent{EKeys::Escape, FModifierKeysState{}, 0, false, 0, 0});
            Tick(FSlateApplication::Get());
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
        {
            return State->bReloadDraftCancelled
                && RuntimeTunersMatch(State->ArbiterB, State->AuthoredB);
        }), 15.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            FCk_VisualLodArbiter_RuntimeTuners Actual;
            const bool bMatches = State->bReloadDraftCancelled
                && TryGetRuntimeTuners(State->ArbiterB, Actual) && SameTuners(Actual, State->AuthoredB);
            TestTrue(FString::Printf(TEXT("Cancelling the retained reload draft preserves B runtime tuners; expected {%s}; actual {%s}"),
                *DescribeTuners(State->AuthoredB), *DescribeTuners(Actual)), bMatches);
            return bMatches;
        }), TEXT("VisualLod retained reload draft cancels without publication")));

    const FNativeCase Cases[] = {
        {TEXT("vl-arbiter-near-budget-input"), TEXT("-1"), [](auto& T) { T.Set_NearBudget(0); }},
        {TEXT("vl-arbiter-fade-duration-input"), TEXT("-1"), [](auto& T) { T.Set_FadeDuration(FCk_Time{0.0f}); }},
        {TEXT("vl-arbiter-fade-duration-input"), TEXT("oops"), [](auto&) {}},
        {TEXT("vl-arbiter-near-budget-input"), TEXT("16777217"), [](auto& T) { T.Set_NearBudget(16777217); }},
        {TEXT("vl-arbiter-lock-budget-input"), TEXT("2147483647"), [](auto& T) { T.Set_LockBudget(MAX_int32); }},
        {TEXT("vl-arbiter-max-preempts-input"), TEXT("2147483647"), [](auto& T) { T.Set_MaxPreemptsPerTick(MAX_int32); }},
        {TEXT("vl-arbiter-promote-distance-input"), TEXT("610"), [](auto& T) { T.Set_PromoteDistance(610.0f); }},
        {TEXT("vl-arbiter-demote-distance-input"), TEXT("910"), [](auto& T) { T.Set_DemoteDistance(910.0f); }},
        {TEXT("vl-arbiter-lock-max-distance-input"), TEXT("1700"), [](auto& T) { T.Set_LockPromoteMaxDistance(1700.0f); }},
        {TEXT("vl-arbiter-always-in-view-input"), TEXT("270"), [](auto& T) { T.Set_AlwaysInViewDistance(270.0f); }},
        {TEXT("vl-arbiter-view-margin-input"), TEXT("13.5"), [](auto& T) { T.Set_ViewConeMarginDeg(13.5f); }},
        {TEXT("vl-arbiter-preempt-margin-input"), TEXT("95"), [](auto& T) { T.Set_PreemptDistanceMargin(95.0f); }},
        {TEXT("vl-arbiter-fade-duration-input"), TEXT("0.456"), [](auto& T) { T.Set_FadeDuration(FCk_Time{0.456f}); }},
        {TEXT("vl-arbiter-fade-anchor-lead-input"), TEXT("-1.75"), [](auto& T) { T.Set_FadeAnchorLeadFrames(-1.75f); }},
        {TEXT("vl-arbiter-fade-anchor-lag-input"), TEXT("-0.875"), [](auto& T) { T.Set_FadeAnchorBakeLagIntervals(-0.875f); }},
        // The UI clamps the pair against the sibling before the full arbiter validator sees it.
        {TEXT("vl-arbiter-promote-distance-input"), TEXT("9999"), [](auto& T) { T.Set_PromoteDistance(910.0f); }},
        {TEXT("vl-arbiter-demote-distance-input"), TEXT("0"), [](auto& T) { T.Set_DemoteDistance(910.0f); }},
    };
    State->bAllNativeFieldsCommitted = true;
    for (const FNativeCase& Case : Cases)
    {
        const bool bMalformedFadeCase = Case.Id == TEXT("vl-arbiter-fade-duration-input") && Case.Value == TEXT("oops");
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
            FCk_NetAutoTest_ServerAction::CreateLambda([State, Case, bMalformedFadeCase](UWorld*) -> void
            {
                State->bLastNativeFieldCommitted = false;
                if (!State->Panel.IsValid() || !FSlateApplication::IsInitialized()) { return; }
                const TSharedPtr<FCkUiView> View = State->Panel->Get_ArbiterTunersView();
                if (!View.IsValid()) { return; }
                const TSharedPtr<SEditableTextBox> Editor = FindEditor(View->GetRegion(TEXT("main")), Case.Id);
                const TSharedPtr<SScrollBox> Scroll = View->GetScroll(TEXT("vl-arbiter-scroll"));
                if (!Editor.IsValid() || !Scroll.IsValid()) { return; }
                Scroll->ScrollDescendantIntoView(Editor.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
                Tick(FSlateApplication::Get());
                auto Diagnostics = FReplaceDiagnostics{};
                State->bLastNativeFieldCommitted = Replace(FSlateApplication::Get(), Editor.ToSharedRef(), Case.Value, true, &Diagnostics);
                State->bLastNativeFocusMatched = Diagnostics.bFocusMatched;
                State->LastNativeFocusedLeaf = MoveTemp(Diagnostics.FocusedLeaf);
                State->LastNativeDraftBeforeEnter = MoveTemp(Diagnostics.DraftBeforeEnter);
                State->LastNativeTextAfterEnter = MoveTemp(Diagnostics.TextAfterEnter);
                if (bMalformedFadeCase)
                {
                    State->bMalformedFadeErrorVisible = Editor->HasError();
                    State->bMalformedFadeAllowsExpensiveTasks = FSlateThrottleManager::Get().IsAllowingExpensiveTasks();
                }
                if (State->bLastNativeFieldCommitted) { Case.Apply(State->ExpectedB); }
                State->bAllNativeFieldsCommitted &= State->bLastNativeFieldCommitted;
            })));
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
            FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
            {
                return State->bLastNativeFieldCommitted
                    && RuntimeTunersMatch(State->ArbiterB, State->ExpectedB);
            }), 15.0f));
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
            FCk_NetAutoTest_Assertion::CreateLambda([this, State, Case]() -> bool
            {
                FCk_VisualLodArbiter_RuntimeTuners Actual;
                const bool bMatches = State->bLastNativeFieldCommitted
                    && TryGetRuntimeTuners(State->ArbiterB, Actual) && SameTuners(Actual, State->ExpectedB);
                AddInfo(FString::Printf(TEXT("Native tuner '%s': draft='%s' focusMatched=%s leaf='%s' afterEnter='%s'"),
                    *Case.Id.ToString(), *State->LastNativeDraftBeforeEnter, State->bLastNativeFocusMatched ? TEXT("true") : TEXT("false"),
                    *State->LastNativeFocusedLeaf, *State->LastNativeTextAfterEnter));
                TestTrue(FString::Printf(TEXT("Native tuner '%s' publishes its full expected runtime snapshot; draft='%s' focusMatched=%s leaf='%s' afterEnter='%s'; expected {%s}; actual {%s}"),
                    *Case.Id.ToString(), *State->LastNativeDraftBeforeEnter, State->bLastNativeFocusMatched ? TEXT("true") : TEXT("false"),
                    *State->LastNativeFocusedLeaf, *State->LastNativeTextAfterEnter, *DescribeTuners(State->ExpectedB), *DescribeTuners(Actual)), bMatches);
                return bMatches;
            }), FString::Printf(TEXT("VisualLod native numeric publishes: %s"), *Case.Id.ToString())));
        if (bMalformedFadeCase)
        {
            ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
                FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
                {
                    const bool bErrorIsVisibleAndProcessingContinues = State->bMalformedFadeErrorVisible
                        && State->bMalformedFadeAllowsExpensiveTasks;
                    TestTrue(FString::Printf(TEXT("Malformed fade keeps a visible native error without throttling expensive work; error=%s expensive=%s"),
                        State->bMalformedFadeErrorVisible ? TEXT("true") : TEXT("false"),
                        State->bMalformedFadeAllowsExpensiveTasks ? TEXT("true") : TEXT("false")), bErrorIsVisibleAndProcessingContinues);
                    return bErrorIsVisibleAndProcessingContinues;
                }), TEXT("VisualLod malformed numeric error does not throttle PIE processing")));
        }
    }

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
        {
            if (!State->Panel.IsValid() || !FSlateApplication::IsInitialized()) { return; }
            const TSharedPtr<FCkUiView> View = State->Panel->Get_ArbiterTunersView();
            const TSharedPtr<SButton> Promote = View.IsValid() ? FindButton(View->GetRegion(TEXT("main")), TEXT("vl-arbiter-policy-promote")) : nullptr;
            const TSharedPtr<SScrollBox> Scroll = View.IsValid() ? View->GetScroll(TEXT("vl-arbiter-scroll")) : nullptr;
            if (!Promote.IsValid() || !Scroll.IsValid()) { return; }
            Scroll->ScrollDescendantIntoView(Promote.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
            Tick(FSlateApplication::Get());
            State->bPromoteClicked = Click(FSlateApplication::Get(), Promote.ToSharedRef());
            State->ExpectedB.Set_ExhaustionPolicy(ECk_VisualLod_PoolExhaustionPolicy::PromoteInstead);
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
        {
            return State->bPromoteClicked && RuntimeTunersMatch(State->ArbiterB, State->ExpectedB);
        }), 15.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            FCk_VisualLodArbiter_RuntimeTuners Actual;
            const bool bMatches = State->bPromoteClicked
                && TryGetRuntimeTuners(State->ArbiterB, Actual) && SameTuners(Actual, State->ExpectedB);
            TestTrue(FString::Printf(TEXT("Promote policy publishes its full runtime snapshot; expected {%s}; actual {%s}"),
                *DescribeTuners(State->ExpectedB), *DescribeTuners(Actual)), bMatches);
            return bMatches;
        }), TEXT("VisualLod promote policy publishes")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
        {
            if (!State->Panel.IsValid() || !FSlateApplication::IsInitialized()) { return; }
            const TSharedPtr<FCkUiView> View = State->Panel->Get_ArbiterTunersView();
            if (!View.IsValid()) { return; }
            const TSharedRef<SWidget> Region = View->GetRegion(TEXT("main"));
            const TSharedPtr<SScrollBox> Scroll = View->GetScroll(TEXT("vl-arbiter-scroll"));
            const TSharedPtr<SButton> Unrendered = FindButton(Region, TEXT("vl-arbiter-policy-unrendered"));
            if (!Scroll.IsValid() || !Unrendered.IsValid()) { return; }
            Scroll->ScrollDescendantIntoView(Unrendered.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
            Tick(FSlateApplication::Get());
            State->bUnrenderedClicked = Click(FSlateApplication::Get(), Unrendered.ToSharedRef());
            State->ExpectedB.Set_ExhaustionPolicy(ECk_VisualLod_PoolExhaustionPolicy::Unrendered);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
        {
            return State->bUnrenderedClicked
                && RuntimeTunersMatch(State->ArbiterB, State->ExpectedB);
        }), 15.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            FCk_VisualLodArbiter_RuntimeTuners Actual;
            const bool bMatches = State->bUnrenderedClicked
                && TryGetRuntimeTuners(State->ArbiterB, Actual) && SameTuners(Actual, State->ExpectedB);
            TestTrue(FString::Printf(TEXT("Unrendered policy publishes its full runtime snapshot; expected {%s}; actual {%s}"),
                *DescribeTuners(State->ExpectedB), *DescribeTuners(Actual)), bMatches);
            return bMatches;
        }), TEXT("VisualLod unrendered policy publishes")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
        {
            if (!State->Panel.IsValid() || !FSlateApplication::IsInitialized()) { return; }
            const TSharedPtr<FCkUiView> View = State->Panel->Get_ArbiterTunersView();
            if (!View.IsValid()) { return; }
            const TSharedRef<SWidget> Region = View->GetRegion(TEXT("main"));
            const TSharedPtr<SScrollBox> Scroll = View->GetScroll(TEXT("vl-arbiter-scroll"));
            const TSharedPtr<SButton> Reset = FindButton(Region, TEXT("vl-arbiter-reset"));
            if (!Scroll.IsValid() || !Reset.IsValid()) { return; }
            Scroll->ScrollDescendantIntoView(Reset.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
            Tick(FSlateApplication::Get());
            State->bResetClicked = Click(FSlateApplication::Get(), Reset.ToSharedRef());
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
        {
            return State->bResetClicked
                && RuntimeTunersMatch(State->ArbiterB, State->AuthoredB);
        }), 15.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            FCk_VisualLodArbiter_RuntimeTuners Actual;
            const bool bMatches = State->bResetClicked
                && TryGetRuntimeTuners(State->ArbiterB, Actual) && SameTuners(Actual, State->AuthoredB);
            TestTrue(FString::Printf(TEXT("Reset restores the complete authored runtime snapshot; expected {%s}; actual {%s}"),
                *DescribeTuners(State->AuthoredB), *DescribeTuners(Actual)), bMatches);
            return bMatches;
        }), TEXT("VisualLod reset restores authored snapshot")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
        {
            if (!State->Panel.IsValid() || !FSlateApplication::IsInitialized())
            {
                State->DynamicReadinessStage = TEXT("panel");
                State->DynamicReadinessDiagnostics = TEXT("panelValid=false or slateInitialized=false before TargetEntity(MemberB)");
                return;
            }
            State->Panel->TargetEntity(State->MemberB);
            State->bDynamicTargetBRequested = true;
            State->DynamicReadinessStage = TEXT("target-requested");
            State->DynamicReadinessDiagnostics = TEXT("TargetEntity(MemberB) dispatched; awaiting B runtime and B-scoped collection records");
            Tick(FSlateApplication::Get());
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
        {
            const auto Fail = [State](const TCHAR* InStage, FString InDetails) -> bool
            {
                State->DynamicReadinessStage = InStage;
                State->DynamicReadinessDiagnostics = MoveTemp(InDetails);
                return false;
            };
            if (!State->Panel.IsValid() || !State->bDynamicTargetBRequested)
            {
                return Fail(TEXT("panel/target"), FString::Printf(TEXT("panelValid=%s targetBRequested=%s"),
                    State->Panel.IsValid() ? TEXT("true") : TEXT("false"),
                    State->bDynamicTargetBRequested ? TEXT("true") : TEXT("false")));
            }
            FCk_VisualLodArbiter_RuntimeTuners RuntimeB;
            const bool bGotRuntimeB = TryGetRuntimeTuners(State->ArbiterB, RuntimeB);
            if (!bGotRuntimeB)
            {
                return Fail(TEXT("runtime-read"), TEXT("TryGetRuntimeTuners(ArbiterB)=false"));
            }
            const auto& Crowds = RuntimeB.Get_CrowdTuners();
            const int32 BandCount = Crowds.IsValidIndex(0) ? Crowds[0].Get_RenderBands().Num() : INDEX_NONE;
            if (!SameTuners(RuntimeB, State->AuthoredB) || !Crowds.IsValidIndex(0) || BandCount <= 0)
            {
                return Fail(TEXT("runtime-shape"), FString::Printf(
                    TEXT("runtime={%s} authoredB={%s} crowdCount=%d band0Count=%d"),
                    *DescribeTuners(RuntimeB), *DescribeTuners(State->AuthoredB), Crowds.Num(), BandCount));
            }

            const FCk_Entity ArbiterBEntity = ck::GetEntity(State->ArbiterB.ConvertToHandle());
            const FString TargetKey = FString::Printf(TEXT("arbiter-%d-%d"),
                static_cast<int32>(ArbiterBEntity.Get_EntityNumber()),
                static_cast<int32>(ArbiterBEntity.Get_VersionNumber()));
            const FString ExpectedCrowdKey = FString::Printf(TEXT("%s/crowd-0"), *TargetKey);
            const FString ExpectedBandKey = FString::Printf(TEXT("%s/band-0"), *ExpectedCrowdKey);
            const TSharedPtr<const FCkUiCollection> Collection = State->Panel->Get_CrowdTunersCollection();
            if (!Collection.IsValid())
            {
                return Fail(TEXT("collection"), FString::Printf(TEXT("expectedCrowd='%s' expectedBand='%s' collectionValid=false"),
                    *ExpectedCrowdKey, *ExpectedBandKey));
            }
            if (Collection->GetRecords().Num() != Crowds.Num() || Collection->GetRecords().IsEmpty())
            {
                return Fail(TEXT("collection-count"), FString::Printf(TEXT("expectedCrowd='%s' expectedBand='%s' expectedCount=%d actualCount=%d"),
                    *ExpectedCrowdKey, *ExpectedBandKey, Crowds.Num(), Collection->GetRecords().Num()));
            }
            const TSharedPtr<const FCkUiRecord> CrowdRecord = Collection->GetRecords()[0];
            const TSharedPtr<const FCkUiCollection> Bands = CrowdRecord.IsValid()
                ? CrowdRecord->FindChildCollection(TEXT("bands")) : nullptr;
            const FString ActualCrowdKey = CrowdRecord.IsValid() ? CrowdRecord->GetKey() : TEXT("<null>");
            const FString ActualBandKey = Bands.IsValid() && !Bands->GetRecords().IsEmpty()
                ? Bands->GetRecords()[0]->GetKey() : TEXT("<none>");
            if (!CrowdRecord.IsValid() || ActualCrowdKey != ExpectedCrowdKey
                || !Bands.IsValid() || Bands->GetRecords().Num() != BandCount || ActualBandKey != ExpectedBandKey)
            {
                return Fail(TEXT("collection-keys"), FString::Printf(
                    TEXT("expectedCrowd='%s' actualCrowd='%s' expectedBand='%s' actualBand='%s' actualBandCount=%d"),
                    *ExpectedCrowdKey, *ActualCrowdKey, *ExpectedBandKey, *ActualBandKey,
                    Bands.IsValid() ? Bands->GetRecords().Num() : INDEX_NONE));
            }
            State->CrowdKey = ExpectedCrowdKey;
            State->InnermostBandKey = ExpectedBandKey;
            const TSharedPtr<FCkUiView> CrowdView = State->Panel->Get_CrowdTunersView();
            if (!CrowdView.IsValid() || !CrowdView->GetLastResult().Succeeded)
            {
                return Fail(TEXT("crowd-view"), FString::Printf(TEXT("crowdViewValid=%s crowdViewSucceeded=%s crowdViewErrors='%s'"),
                    CrowdView.IsValid() ? TEXT("true") : TEXT("false"),
                    CrowdView.IsValid() && CrowdView->GetLastResult().Succeeded ? TEXT("true") : TEXT("false"),
                    CrowdView.IsValid() ? *FString::Join(CrowdView->GetLastResult().Errors, TEXT(" | ")) : TEXT("<unavailable>")));
            }
            const TSharedPtr<SCkUiRepeat> CrowdRepeat = CrowdView->GetRepeat(TEXT("vl-crowd-repeat"));
            if (!CrowdRepeat.IsValid())
            {
                return Fail(TEXT("crowd-repeat"), TEXT("crowdViewValid=true crowdViewSucceeded=true outerRepeatValid=false"));
            }
            const bool bCrowdRefreshSucceeded = CrowdRepeat->TryRefresh();
            const TSharedPtr<SWidget> CrowdItem = CrowdRepeat.IsValid()
                ? CrowdRepeat->GetItemWidget(State->CrowdKey) : nullptr;
            const TSharedPtr<SCkUiRepeat> BandRepeat = CrowdItem.IsValid()
                ? FindRepeat(CrowdItem.ToSharedRef(), TEXT("vl-band-repeat")) : nullptr;
            const TSharedPtr<SWidget> BandItem = BandRepeat.IsValid()
                ? BandRepeat->GetItemWidget(State->InnermostBandKey) : nullptr;
            if (!CrowdItem.IsValid() || !BandItem.IsValid())
            {
                return Fail(TEXT("mounted-repeat"), FString::Printf(TEXT("crowdViewValid=true crowdViewSucceeded=true outerRepeatValid=true outerRefreshSucceeded=%s outerLastFailure='%s' outerItemCount=%d crowdItemMounted=%s nestedRepeatValid=%s nestedItemCount=%d nestedLastFailure='%s' bandItemMounted=%s expectedCrowd='%s' expectedBand='%s'"),
                    bCrowdRefreshSucceeded ? TEXT("true") : TEXT("false"),
                    *CrowdRepeat->GetLastFailure(),
                    CrowdRepeat->GetItemCount(),
                    CrowdItem.IsValid() ? TEXT("true") : TEXT("false"),
                    BandRepeat.IsValid() ? TEXT("true") : TEXT("false"),
                    BandRepeat.IsValid() ? BandRepeat->GetItemCount() : INDEX_NONE,
                    BandRepeat.IsValid() ? *BandRepeat->GetLastFailure() : TEXT("<unavailable>"),
                    BandItem.IsValid() ? TEXT("true") : TEXT("false"), *ExpectedCrowdKey, *ExpectedBandKey));
            }
            State->bDynamicReadinessReady = true;
            State->DynamicReadinessStage = TEXT("ready");
            State->DynamicReadinessDiagnostics = FString::Printf(TEXT("runtimeB/authoredB match; crowdViewValid=true crowdViewSucceeded=true outerRepeatValid=true outerRefreshSucceeded=%s outerLastFailure='%s' outerItemCount=%d crowdItemMounted=true nestedRepeatValid=true nestedItemCount=%d nestedLastFailure='%s' bandItemMounted=true crowd='%s' band='%s'"),
                bCrowdRefreshSucceeded ? TEXT("true") : TEXT("false"), *CrowdRepeat->GetLastFailure(), CrowdRepeat->GetItemCount(), BandRepeat->GetItemCount(), *BandRepeat->GetLastFailure(),
                *ExpectedCrowdKey, *ExpectedBandKey);
            return true;
        }), 15.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            FCk_VisualLodArbiter_RuntimeTuners RuntimeB;
            const bool bGotRuntimeB = TryGetRuntimeTuners(State->ArbiterB, RuntimeB);
            const FString RuntimeSnapshot = bGotRuntimeB ? DescribeTuners(RuntimeB) : FString(TEXT("<unavailable>"));
            TestTrue(FString::Printf(TEXT("Dynamic VisualLod crowd readiness reaches the B-scoped mounted repeat stage; last stage=%s; runtimeB={%s}; authoredB={%s}; %s"),
                *State->DynamicReadinessStage, *RuntimeSnapshot, *DescribeTuners(State->AuthoredB), *State->DynamicReadinessDiagnostics),
                State->bDynamicReadinessReady);
            return State->bDynamicReadinessReady;
        }), TEXT("VisualLod dynamic crowd readiness provenance")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld*) -> void
        {
            if (!State->bDynamicReadinessReady) { return; }
            if (!State->Panel.IsValid() || !State->Window.IsValid() || !FSlateApplication::IsInitialized())
            {
                State->DynamicReadinessStage = TEXT("capture-shell");
                State->DynamicReadinessDiagnostics = FString::Printf(TEXT("panelValid=%s windowValid=%s slateInitialized=%s"),
                    State->Panel.IsValid() ? TEXT("true") : TEXT("false"), State->Window.IsValid() ? TEXT("true") : TEXT("false"),
                    FSlateApplication::IsInitialized() ? TEXT("true") : TEXT("false"));
                return;
            }
            const TSharedPtr<FCkUiView> CrowdView = State->Panel->Get_CrowdTunersView();
            const TSharedPtr<SCkUiRepeat> CrowdRepeat = CrowdView.IsValid() && CrowdView->GetLastResult().Succeeded
                ? CrowdView->GetRepeat(TEXT("vl-crowd-repeat")) : nullptr;
            const TSharedPtr<SWidget> CrowdItem = CrowdRepeat.IsValid()
                ? CrowdRepeat->GetItemWidget(State->CrowdKey) : nullptr;
            const TSharedPtr<SCkUiRepeat> BandRepeat = CrowdItem.IsValid()
                ? FindRepeat(CrowdItem.ToSharedRef(), TEXT("vl-band-repeat")) : nullptr;
            const TSharedPtr<SWidget> BandItem = BandRepeat.IsValid()
                ? BandRepeat->GetItemWidget(State->InnermostBandKey) : nullptr;
            const TSharedPtr<SCkDebug_InspectorPanel> CrowdInspector = CrowdItem.IsValid()
                ? FindInspectorPanel(CrowdItem.ToSharedRef()) : nullptr;
            const TSharedPtr<SCkDebug_InspectorPanel> BandInspector = BandItem.IsValid()
                ? FindInspectorPanel(BandItem.ToSharedRef()) : nullptr;
            if (!CrowdView.IsValid() || !CrowdView->GetLastResult().Succeeded || !CrowdItem.IsValid() || !BandItem.IsValid()
                || !CrowdInspector.IsValid() || !BandInspector.IsValid())
            {
                State->DynamicReadinessStage = TEXT("capture-inspectors");
                State->DynamicReadinessDiagnostics = FString::Printf(TEXT("crowdViewValid=%s crowdViewSucceeded=%s crowdViewErrors='%s' outerRepeatValid=%s outerItemCount=%d outerLastFailure='%s' crowdItem=%s nestedRepeatValid=%s nestedItemCount=%d nestedLastFailure='%s' bandItem=%s crowdInspector=%s bandInspector=%s"),
                    CrowdView.IsValid() ? TEXT("true") : TEXT("false"),
                    CrowdView.IsValid() && CrowdView->GetLastResult().Succeeded ? TEXT("true") : TEXT("false"),
                    CrowdView.IsValid() ? *FString::Join(CrowdView->GetLastResult().Errors, TEXT(" | ")) : TEXT("<unavailable>"),
                    CrowdRepeat.IsValid() ? TEXT("true") : TEXT("false"), CrowdRepeat.IsValid() ? CrowdRepeat->GetItemCount() : INDEX_NONE,
                    CrowdRepeat.IsValid() ? *CrowdRepeat->GetLastFailure() : TEXT("<unavailable>"),
                    CrowdItem.IsValid() ? TEXT("true") : TEXT("false"),
                    BandRepeat.IsValid() ? TEXT("true") : TEXT("false"), BandRepeat.IsValid() ? BandRepeat->GetItemCount() : INDEX_NONE,
                    BandRepeat.IsValid() ? *BandRepeat->GetLastFailure() : TEXT("<unavailable>"),
                    BandItem.IsValid() ? TEXT("true") : TEXT("false"),
                    CrowdInspector.IsValid() ? TEXT("true") : TEXT("false"), BandInspector.IsValid() ? TEXT("true") : TEXT("false"));
                return;
            }

            CrowdInspector->Set_Expanded(true);
            BandInspector->Set_Expanded(true);
            Tick(FSlateApplication::Get());
            const TSharedPtr<SEditableTextBox> Editor = FindEditor(BandItem.ToSharedRef(), TEXT("vl-profile-bounds"));
            const TSharedPtr<SScrollBox> Scroll = CrowdView->GetScroll(TEXT("vl-crowd-tuners-scroll"));
            if (!CrowdInspector->Is_Expanded() || !BandInspector->Is_Expanded() || !Editor.IsValid() || !Scroll.IsValid())
            {
                State->DynamicReadinessStage = TEXT("capture-editor-scroll");
                State->DynamicReadinessDiagnostics = FString::Printf(TEXT("crowdExpanded=%s bandExpanded=%s bandEditor=%s crowdScroll=%s"),
                    CrowdInspector->Is_Expanded() ? TEXT("true") : TEXT("false"), BandInspector->Is_Expanded() ? TEXT("true") : TEXT("false"),
                    Editor.IsValid() ? TEXT("true") : TEXT("false"), Scroll.IsValid() ? TEXT("true") : TEXT("false"));
                return;
            }
            State->bDynamicControlsPrepared = true;
            State->DynamicReadinessStage = TEXT("capture-ready");
            State->DynamicReadinessDiagnostics = TEXT("mounted crowd/band inspectors expanded; nested bounds editor and arbiter scroll resolved");

            State->Window->Resize(FVector2D{1120.0f, 820.0f});
            Scroll->ScrollDescendantIntoView(Editor.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
            Tick(FSlateApplication::Get());
            State->bWideDynamicCrowdCapture = SaveCapture(FSlateApplication::Get(), State->Window.ToSharedRef(),
                FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Automation/VisualLodArbiterTuners-PIE-Wide.png")));
            State->Window->Resize(FVector2D{360.0f, 520.0f});
            Scroll->ScrollDescendantIntoView(Editor.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
            Tick(FSlateApplication::Get());
            State->bNarrowDynamicCrowdCapture = SaveCapture(FSlateApplication::Get(), State->Window.ToSharedRef(),
                FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("Automation/VisualLodArbiterTuners-PIE-Narrow.png")));

            const auto& Crowds = State->AuthoredB.Get_CrowdTuners();
            if (!Crowds.IsValidIndex(0) || !Crowds[0].Get_RenderBands().IsValidIndex(0)) { return; }
            State->ExpectedCrowdProfileB = State->AuthoredB;
            auto ExpectedCrowds = State->ExpectedCrowdProfileB.Get_CrowdTuners();
            auto ExpectedCrowd = ExpectedCrowds[0];
            auto ExpectedBands = ExpectedCrowd.Get_RenderBands();
            auto ExpectedBand = ExpectedBands[0];
            auto ExpectedProfile = ExpectedBand.Get_ProfileTuners();
            const float BoundsScale = ExpectedProfile.Get_BoundsScale() <= 10.0f
                ? ExpectedProfile.Get_BoundsScale() + 0.25f : ExpectedProfile.Get_BoundsScale() - 0.25f;
            ExpectedProfile.Set_BoundsScale(FMath::Max(0.01f, BoundsScale));
            ExpectedBand.Set_ProfileTuners(ExpectedProfile);
            ExpectedBands[0] = MoveTemp(ExpectedBand);
            ExpectedCrowd.Set_RenderBands(ExpectedBands);
            ExpectedCrowds[0] = MoveTemp(ExpectedCrowd);
            State->ExpectedCrowdProfileB.Set_CrowdTuners(ExpectedCrowds);
            State->bCrowdTunersLoaded = true;
            State->bInnermostProfileCommitDispatched = Replace(FSlateApplication::Get(), Editor.ToSharedRef(),
                FString::SanitizeFloat(ExpectedProfile.Get_BoundsScale()), true);
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            if (!State->bDynamicReadinessReady) { return true; }
            TestTrue(FString::Printf(TEXT("Dynamic VisualLod crowd capture controls resolve; last stage=%s; %s"),
                *State->DynamicReadinessStage, *State->DynamicReadinessDiagnostics), State->bDynamicControlsPrepared);
            return State->bDynamicControlsPrepared;
        }), TEXT("VisualLod dynamic crowd capture controls")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
        {
            if (!State->bDynamicReadinessReady || !State->bDynamicControlsPrepared) { return true; }
            State->bInnermostProfileCommitted = State->bCrowdTunersLoaded
                && State->bInnermostProfileCommitDispatched
                && RuntimeTunersMatch(State->ArbiterB, State->ExpectedCrowdProfileB);
            return State->bInnermostProfileCommitted;
        }), 15.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            if (!State->bDynamicReadinessReady || !State->bDynamicControlsPrepared) { return true; }
            FCk_VisualLodArbiter_RuntimeTuners Actual;
            const bool bMatches = State->bInnermostProfileCommitted
                && TryGetRuntimeTuners(State->ArbiterB, Actual) && SameTuners(Actual, State->ExpectedCrowdProfileB);
            TestTrue(FString::Printf(TEXT("The authored crowd tuner repeat loads stable item key '%s' and routes its innermost profile bounds commit through the selected arbiter; expected {%s}; actual {%s}"),
                *State->InnermostBandKey, *DescribeTuners(State->ExpectedCrowdProfileB), *DescribeTuners(Actual)), bMatches);
            return bMatches;
        }), TEXT("VisualLod crowd profile commit publishes through keyed real window")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            TestTrue(TEXT("PIE fixture owns two real configured arbiter domains and members"), State->bFixtureCreated && State->bMembersResolved);
            TestTrue(TEXT("The unavailable Tuners inspector opens before any live arbiter exists"), State->bUnavailableTunersExpanded);
            TestTrue(TEXT("The unavailable authored tuner view loads and mounts"), State->bUnavailableViewMounted);
            TestTrue(TEXT("The unavailable authored reset control mounts"), State->bUnavailableResetMounted);
            TestTrue(TEXT("The unavailable authored reset control is disabled"), State->bUnavailableResetDisabled);
            TestTrue(TEXT("A member-target switches the authored tuner view across domains"), State->bTargetedA && State->bSwitchedToB);
            TestTrue(TEXT("Old-domain draft callback is inert after the target generation changes"), State->bStaleCommitRejected);
            TestTrue(TEXT("Compatible same-target reload retains native editor identity, focus, and draft"), State->bCompatibleReloadRetainedDraft);
            TestTrue(TEXT("Rejected same-target document leaves the published editor, focus, draft, and revision intact"), State->bRejectedReloadRetainedDraft);
            TestTrue(TEXT("Every authored numeric field, both policy actions, and reset reach public runtime tuners"), State->bAllNativeFieldsCommitted && State->bPromoteClicked && State->bUnrenderedClicked && State->bResetClicked);
            if (State->bDynamicReadinessReady && State->bDynamicControlsPrepared)
            {
                TestTrue(TEXT("The authored dynamic crowd tuner loads a keyed innermost profile and publishes its typed edit"), State->bInnermostProfileCommitted);
                TestTrue(TEXT("The wide real debugger window captures expanded dynamic crowd and band controls"), State->bWideDynamicCrowdCapture);
                TestTrue(TEXT("The narrow real debugger window captures expanded dynamic crowd and band controls"), State->bNarrowDynamicCrowdCapture);
            }
            return true;
        }), TEXT("VisualLod authored arbiter tuners drive real PIE domains")));

    ADD_LATENT_AUTOMATION_COMMAND(FDelayedFunctionLatentCommand([State]() -> void
        {
            if (FSlateApplication::IsInitialized() && State->StaleWindow.IsValid())
            { FSlateApplication::Get().DestroyWindowImmediately(State->StaleWindow.ToSharedRef()); }
            if (FSlateApplication::IsInitialized() && State->Window.IsValid())
            { FSlateApplication::Get().DestroyWindowImmediately(State->Window.ToSharedRef()); }
            State->StaleWindow.Reset();
            State->Window.Reset();
            State->StaleEditor.Reset();
            State->ViewA.Reset();
            State->Panel.Reset();
            if (ck::IsValid(State->Owner))
            { UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(State->Owner); }
            State->Owner = {};
            State->ArbiterA = {};
            State->ArbiterB = {};
            State->MemberA = {};
            State->MemberB = {};
            State->bTornDown = !State->WeakPanel.IsValid() && !State->WeakViewA.IsValid();
        }));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            TestTrue(TEXT("Fixture releases the native debugger host and its transient entity owner"), State->bTornDown);
            return true;
        }), TEXT("VisualLod arbiter-tuner PIE fixture tears down")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif
