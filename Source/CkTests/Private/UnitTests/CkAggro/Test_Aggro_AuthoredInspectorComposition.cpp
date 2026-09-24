#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkAggro/CkAggro_Fragment.h"
#include "CkAggro/CkAggro_Utils.h"
#include "CkAggro/CkAggroTarget_Fragment.h"
#include "CkAggro/CkAggroTarget_Utils.h"
#include "CkCore/Validation/CkIsValid.h"
#include "CkDebuggerCommon/Styles/CkDebuggerStyle.h"
#include "CkDebuggerCommon/Widgets/SCkDebug_EntityRef.h"
#include "CkDebuggerCommon/Widgets/SCkDebug_Switch.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Handle/CkHandle_Utils.h"
#include "CkEcsExt/Transform/CkTransform_Utils.h"
#include "CkEcsDebugger/Inspectors/CkInspectorWidgetBuilder.h"
#include "CkEcsDebugger/Inspectors/CkInspector_Aggro.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include "Framework/Application/SlateApplication.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "Interfaces/IPluginManager.h"
#include "Misc/AutomationTest.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/Input/SEditableTextBox.h"
#include "Widgets/SBoxPanel.h"
#include "Widgets/SWindow.h"

namespace ck_tests_aggro_authored
{
    constexpr auto kFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;

    auto FindTagged(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTag() == InTag)
        { return InRoot; }
        FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SWidget> Found = FindTagged(
                ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag); Found.IsValid())
            { return Found; }
        }
        return nullptr;
    }

    auto FindButton(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SButton>
    {
        if (InRoot->GetTypeAsString() == TEXT("SButton") && InRoot->GetTag() == InTag)
        { return StaticCastSharedRef<SButton>(InRoot); }
        FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SButton> Found = FindButton(
                ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag); Found.IsValid())
            { return Found; }
        }
        return nullptr;
    }

    auto FindInput(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SEditableTextBox>
    {
        if (InRoot->GetTypeAsString() == TEXT("SEditableTextBox")
            || InRoot->GetTypeAsString() == TEXT("SCkUiTextInputBox"))
        { return StaticCastSharedRef<SEditableTextBox>(InRoot); }
        FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SEditableTextBox> Found = FindInput(
                ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid())
            { return Found; }
        }
        return nullptr;
    }

    auto FindSwitch(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SCkDebug_Switch>
    {
        if (InRoot->GetTypeAsString() == TEXT("SCkDebug_Switch") && InRoot->GetTag() == InTag)
        { return StaticCastSharedRef<SCkDebug_Switch>(InRoot); }
        FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SCkDebug_Switch> Found = FindSwitch(
                ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag); Found.IsValid())
            { return Found; }
        }
        return nullptr;
    }

    auto Tick(FSlateApplication& InSlate) -> void
    { InSlate.PumpMessages(); InSlate.Tick(); InSlate.Tick(); }

    auto Toggle(const TSharedRef<SCkDebug_Switch>& InSwitch) -> void
    {
        const FGeometry Geometry = FGeometry::MakeRoot(FVector2D{30.0f, 17.0f}, FSlateLayoutTransform{});
        const TSet<FKey> PressedButtons{EKeys::LeftMouseButton};
        const FPointerEvent Click{0, FVector2D{5.0f, 5.0f}, FVector2D{5.0f, 5.0f}, PressedButtons,
            EKeys::LeftMouseButton, 0.0f, FModifierKeysState{}};
        InSwitch->OnMouseButtonDown(Geometry, Click);
    }

    auto Commit(
        FSlateApplication& InSlate,
        const TSharedRef<SEditableTextBox>& InInput,
        const FString& InValue) -> bool
    {
        InSlate.SetUserFocus(0, InInput, EFocusCause::SetDirectly);
        Tick(InSlate);
        InInput->SetText(FText::FromString(InValue));
        if (NOT InSlate.ProcessKeyDownEvent(FKeyEvent{EKeys::Enter, FModifierKeysState{}, 0, false, 0, 0}))
        { return false; }
        Tick(InSlate);
        return true;
    }

    auto OwnerRequestCount(const FCk_Handle& InOwner) -> int32
    {
        return ck::IsValid(InOwner) && InOwner.Has<ck::FFragment_Aggro_Requests>()
            ? InOwner.Get<ck::FFragment_Aggro_Requests>().Get_Requests().Num() : 0;
    }

    auto TargetRequestCount(const FCk_Handle& InTarget) -> int32
    {
        return ck::IsValid(InTarget) && InTarget.Has<ck::FFragment_AggroTarget_Requests>()
            ? InTarget.Get<ck::FFragment_AggroTarget_Requests>().Get_Requests().Num() : 0;
    }

    struct FScenario
    {
        FCk_Handle Owner;
        FCk_Handle AggroEntity;
        FCk_Handle TrackedA;
        FCk_Handle TrackedB;
        FCk_Handle_Aggro Aggro;
        FCk_Handle_AggroTarget TargetA;
        FCk_Handle_AggroTarget TargetB;
        TUniquePtr<FCkInspector_Aggro> Inspector;
        TSharedPtr<SCkInspector_AggroAuthored> OwnerView;
        TSharedPtr<SCkInspector_AggroAuthored> TargetView;
        TSharedPtr<SCkInspector_AggroAuthored> DiffView;
        TSharedPtr<SCkDebug_Switch> Enabled;
        TSharedPtr<SButton> ClearActive;
        TSharedPtr<SButton> ClearAll;
        TSharedPtr<SButton> MarkUnperceived;
        TSharedPtr<SEditableTextBox> SetThreat;
        TSharedPtr<SEditableTextBox> AddThreat;
        int32 OwnerRequestsBefore = 0;
        int32 TargetRequestsBefore = 0;
        bool bBuiltAndDispatched = false;
        bool bReloadAccepted = false;
        bool bReloadRejectedAtomically = false;
        bool bCompositionLossFailedClosed = false;
        bool bReleased = false;
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_Aggro_AuthoredInspectorComposition,
    "Ck.UiAuthoring.EcsDebugger.AggroInspector.AuthoredComposition", ck_tests_aggro_authored::kFlags)

bool FCkTest_Aggro_AuthoredInspectorComposition::RunTest(const FString&)
{
    using namespace ck_tests_aggro_authored;
    const auto Scenario = MakeShared<FScenario>();
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, Scenario](UWorld* World)
        {
            Scenario->Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(World);
            Scenario->AggroEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Scenario->Owner);
            Scenario->TrackedA = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Scenario->Owner);
            Scenario->TrackedB = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Scenario->Owner);
            UCk_Utils_Handle_UE::Set_DebugName(Scenario->AggroEntity, TEXT("AuthoredAggroOwner"));
            UCk_Utils_Handle_UE::Set_DebugName(Scenario->TrackedA, TEXT("AuthoredTargetA"));
            UCk_Utils_Handle_UE::Set_DebugName(Scenario->TrackedB, TEXT("AuthoredTargetB"));
            UCk_Utils_Transform_UE::Add(
                Scenario->AggroEntity, FTransform::Identity, ECk_Replication::DoesNotReplicate);
            UCk_Utils_Transform_UE::Add(
                Scenario->TrackedA, FTransform{FVector{100.0f, 0.0f, 0.0f}}, ECk_Replication::DoesNotReplicate);
            UCk_Utils_Transform_UE::Add(
                Scenario->TrackedB, FTransform{FVector{200.0f, 0.0f, 0.0f}}, ECk_Replication::DoesNotReplicate);
            auto Params = FCk_Aggro_Spec{};
            auto TargetParams = Params.Get_DefaultTargetParams();
            auto Lifetime = TargetParams.Get_LifetimeParams();
            Lifetime.Set_CanBeForgotten(ECk_EnableDisable::Disable);
            TargetParams.Set_LifetimeParams(Lifetime);
            Params.Set_DefaultTargetParams(TargetParams);
            Scenario->Aggro = UCk_Utils_Aggro_UE::Add(Scenario->AggroEntity, Params);
            Scenario->TargetA = UCk_Utils_Aggro_UE::CreateTarget(Scenario->Aggro, Scenario->TrackedA);
            Scenario->TargetB = UCk_Utils_Aggro_UE::CreateTarget(Scenario->Aggro, Scenario->TrackedB);
            UCk_Utils_AggroTarget_UE::Request_MarkPerceived(Scenario->TargetA, FCk_Request_AggroTarget_MarkPerceived{}, {});
            UCk_Utils_AggroTarget_UE::Request_MarkPerceived(Scenario->TargetB, FCk_Request_AggroTarget_MarkPerceived{}, {});
            UCk_Utils_AggroTarget_UE::Request_SetThreat(Scenario->TargetA, 10.0f, {});
            UCk_Utils_AggroTarget_UE::Request_SetThreat(Scenario->TargetB, 20.0f, {});
            TestTrue(TEXT("real Aggro fixture composes owner and two targets"),
                ck::IsValid(Scenario->Owner) && ck::IsValid(Scenario->Aggro)
                    && ck::IsValid(Scenario->TargetA) && ck::IsValid(Scenario->TargetB));
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(60));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([Scenario]()
    {
        return ck::IsValid(Scenario->Aggro) && ck::IsValid(Scenario->TargetA) && ck::IsValid(Scenario->TargetB)
            && UCk_Utils_Aggro_UE::Get_NumTrackedTargets(Scenario->Aggro) == 2
            && UCk_Utils_Aggro_UE::Get_Debug_EvaluationCount(Scenario->Aggro) > 0
            && UCk_Utils_AggroTarget_UE::Get_IsPerceived(Scenario->TargetA)
            && FMath::IsNearlyEqual(UCk_Utils_AggroTarget_UE::Get_Threat(Scenario->TargetA), 10.0f)
            && FMath::IsNearlyEqual(UCk_Utils_AggroTarget_UE::Get_Threat(Scenario->TargetB), 20.0f);
    }), 15.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, Scenario](UWorld*)
        {
            UCk_Utils_Aggro_UE::Request_SetActiveTarget(Scenario->Aggro, Scenario->TrackedA, {});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(30));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([Scenario]()
    {
        return ck::IsValid(Scenario->Aggro)
            && UCk_Utils_Aggro_UE::TryGet_ActiveTrackedEntity(Scenario->Aggro) == Scenario->TrackedA;
    }), 15.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, Scenario](UWorld*)
        {
            Scenario->Inspector = MakeUnique<FCkInspector_Aggro>();
            auto OwnerRows = TMap<FString, FString>{};
            auto TargetRows = TMap<FString, FString>{};
            {
                const FCkInspector_RowCaptureScope Capture{};
                Scenario->Inspector->Build_Inspector(Scenario->Aggro);
                OwnerRows = Capture.Get_Rows();
            }
            {
                const FCkInspector_RowCaptureScope Capture{};
                Scenario->Inspector->Build_Inspector(Scenario->TargetA);
                TargetRows = Capture.Get_Rows();
            }
            TestTrue(TEXT("native row capture remains Aggro comparison authority"),
                OwnerRows.FindRef(TEXT("Tracked Targets:")) == TEXT("2")
                    && OwnerRows.FindRef(TEXT("Enabled:")) == TEXT("Enabled")
                    && TargetRows.FindRef(TEXT("Threat:")) == TEXT("10.0")
                    && TargetRows.FindRef(TEXT("State:")).Contains(TEXT("Perceived")));

            const TSharedRef<SWidget> OwnerBuilt = Scenario->Inspector->Build_Inspector(Scenario->Aggro);
            const FString OwnerError = Scenario->Inspector->Get_LastAuthoredLoadError();
            const TSharedRef<SWidget> TargetBuilt = Scenario->Inspector->Build_Inspector(Scenario->TargetA);
            const FString TargetError = Scenario->Inspector->Get_LastAuthoredLoadError();
            if (NOT TestTrue(*FString::Printf(TEXT("real owner and target mount Aggro authored surfaces (types=%s/%s errors='%s'/'%s')"),
                *OwnerBuilt->GetTypeAsString(), *TargetBuilt->GetTypeAsString(), *OwnerError, *TargetError),
                OwnerBuilt->GetTypeAsString() == TEXT("SCkInspector_AggroAuthored")
                    && TargetBuilt->GetTypeAsString() == TEXT("SCkInspector_AggroAuthored")))
            { return; }
            Scenario->OwnerView = StaticCastSharedRef<SCkInspector_AggroAuthored>(OwnerBuilt);
            Scenario->TargetView = StaticCastSharedRef<SCkInspector_AggroAuthored>(TargetBuilt);
            if (NOT TestTrue(TEXT("owner and target retain independent authored views and exact projections"),
                Scenario->OwnerView->Is_Mounted() && Scenario->TargetView->Is_Mounted()
                    && Scenario->OwnerView->Get_View().IsValid() && Scenario->TargetView->Get_View().IsValid()
                    && Scenario->OwnerView->Get_View() != Scenario->TargetView->Get_View()
                    && Scenario->OwnerView->Get_Text(TEXT("owner-active-name")) == TEXT("AuthoredTargetA")
                    && Scenario->OwnerView->Get_Text(TEXT("owner-tracked")) == TEXT("2")
                    && Scenario->OwnerView->Get_Bool(TEXT("owner-enabled"))
                    && Scenario->TargetView->Get_Text(TEXT("target-tracked-name")) == TEXT("AuthoredTargetA")
                    && Scenario->TargetView->Get_Text(TEXT("target-threat")) == TEXT("10.0")
                    && FMath::IsNearlyEqual(Scenario->TargetView->Get_Number(TEXT("target-threat-fraction")), 0.5f)))
            { return; }

            auto Differing = TSet<FString>{TEXT("Threat:"), TEXT("Enable/Disable:")};
            {
                const FCkInspector_DiffMarkScope DiffScope{&Differing};
                Scenario->DiffView = StaticCastSharedRef<SCkInspector_AggroAuthored>(
                    Scenario->Inspector->Build_Inspector(Scenario->TargetB));
            }
            TestTrue(TEXT("authored Aggro labels expose exact native diff routes"),
                Scenario->DiffView->Get_DiffColor(TEXT("Threat:")) == CkStyle::Accent()
                    && Scenario->DiffView->Get_DiffColor(TEXT("Score:")) == CkStyle::Text());

            const TSharedRef<SWidget> OwnerRoot = Scenario->OwnerView->Get_View()->GetRegion(TEXT("main"));
            const TSharedRef<SWidget> TargetRoot = Scenario->TargetView->Get_View()->GetRegion(TEXT("main"));
            Scenario->Enabled = FindSwitch(OwnerRoot, TEXT("aggro-owner-toggle"));
            Scenario->ClearActive = FindButton(OwnerRoot, TEXT("aggro-owner-clear-active"));
            Scenario->ClearAll = FindButton(OwnerRoot, TEXT("aggro-owner-clear-all"));
            Scenario->MarkUnperceived = FindButton(TargetRoot, TEXT("aggro-target-mark-unperceived"));
            const TSharedPtr<SWidget> SetHost = FindTagged(TargetRoot, TEXT("aggro-target-set-threat"));
            const TSharedPtr<SWidget> AddHost = FindTagged(TargetRoot, TEXT("aggro-target-add-threat"));
            Scenario->SetThreat = SetHost.IsValid() ? FindInput(SetHost.ToSharedRef()) : nullptr;
            Scenario->AddThreat = AddHost.IsValid() ? FindInput(AddHost.ToSharedRef()) : nullptr;
            const TSharedPtr<SWidget> OwnerRef = FindTagged(OwnerRoot, TEXT("aggro-owner-active"));
            const TSharedPtr<SWidget> TargetRef = FindTagged(TargetRoot, TEXT("aggro-target-tracked"));

            FSlateApplication& Slate = FSlateApplication::Get();
            const TSharedRef<SWindow> Window = SNew(SWindow)
                .AutoCenter(EAutoCenter::None)
                .ClientSize(FVector2D{760.0f, 760.0f})
                .CreateTitleBar(false)
                .HasCloseButton(false)
                [
                    SNew(SVerticalBox)
                    + SVerticalBox::Slot().AutoHeight()[Scenario->OwnerView.ToSharedRef()]
                    + SVerticalBox::Slot().AutoHeight()[Scenario->TargetView.ToSharedRef()]
                ];
            Slate.AddWindow(Window, true);
            Tick(Slate);
            const bool bControlsReady = Scenario->OwnerView->Get_CanRequestOwner()
                && Scenario->TargetView->Get_CanRequestTarget()
                && Scenario->Enabled.IsValid() && Scenario->Enabled->IsEnabled()
                && Scenario->ClearActive.IsValid() && Scenario->ClearActive->IsEnabled()
                && Scenario->ClearAll.IsValid() && Scenario->ClearAll->IsEnabled()
                && Scenario->MarkUnperceived.IsValid() && Scenario->MarkUnperceived->IsEnabled()
                && Scenario->SetThreat.IsValid() && Scenario->SetThreat->IsEnabled()
                && Scenario->AddThreat.IsValid() && Scenario->AddThreat->IsEnabled()
                && OwnerRef.IsValid() && TargetRef.IsValid();
            if (NOT TestTrue(TEXT("authored Aggro exposes physical entity references and authority-gated controls"), bControlsReady))
            { Slate.DestroyWindowImmediately(Window); return; }

            Scenario->OwnerRequestsBefore = OwnerRequestCount(Scenario->Aggro);
            Scenario->TargetRequestsBefore = TargetRequestCount(Scenario->TargetA);
            Scenario->ClearActive->SimulateClick();
            const int32 OwnerRequestsAfterClear = OwnerRequestCount(Scenario->Aggro);
            Toggle(Scenario->Enabled.ToSharedRef());
            const bool bToggleAppliedImmediately = NOT UCk_Utils_Aggro_UE::Get_IsEnabled(Scenario->Aggro)
                && OwnerRequestCount(Scenario->Aggro) == OwnerRequestsAfterClear;
            const bool bSetCommitted = Commit(Slate, Scenario->SetThreat.ToSharedRef(), TEXT("80"));
            const bool bAddCommitted = Commit(Slate, Scenario->AddThreat.ToSharedRef(), TEXT("5"));
            Scenario->MarkUnperceived->SimulateClick();
            const int32 TargetRequestsAfter = TargetRequestCount(Scenario->TargetA);
            Scenario->bBuiltAndDispatched = bSetCommitted && bAddCommitted
                && OwnerRequestsAfterClear == Scenario->OwnerRequestsBefore + 1
                && bToggleAppliedImmediately
                && TargetRequestsAfter == Scenario->TargetRequestsBefore + 3;
            TestTrue(TEXT("physical Aggro controls queue one owner and three target requests while toggle applies synchronously"),
                Scenario->bBuiltAndDispatched);

            const TSharedPtr<IPlugin> Plugin = IPluginManager::Get().FindPlugin(TEXT("CkDebugger"));
            FString Markup, Css;
            const FString Resources = Plugin.IsValid()
                ? FPaths::Combine(Plugin->GetBaseDir(), TEXT("Resources/UI")) : FString{};
            if (TestTrue(TEXT("installed Aggro inspector resources are readable"), Plugin.IsValid()
                && FFileHelper::LoadFileToString(Markup, *FPaths::Combine(Resources, TEXT("EcsInspectorAggro.ui.html")))
                && FFileHelper::LoadFileToString(Css, *FPaths::Combine(Resources, TEXT("EcsInspectorAggro.ui.css")))))
            {
                TestTrue(TEXT("Aggro HTML owns both complete modes without native layout ports"),
                    Markup.Contains(TEXT("aggro-owner-active"))
                        && Markup.Contains(TEXT("aggro-owner-clear-all"))
                        && Markup.Contains(TEXT("aggro-target-threat-meter"))
                        && Markup.Contains(TEXT("aggro-target-add-threat"))
                        && Markup.Contains(TEXT("aggro-target-forget"))
                        && Markup.Contains(TEXT("aggro-unavailable"))
                        && NOT Markup.Contains(TEXT("<native")));
                const TSharedPtr<FCkUiView> View = Scenario->TargetView->Get_View();
                const int64 Revision = View->GetRevision();
                const bool bCompatible = View->TryReload(Markup, Css, TEXT("Aggro compatible")).Succeeded;
                const TSharedPtr<SWidget> ReloadedSetHost =
                    FindTagged(View->GetRegion(TEXT("main")), TEXT("aggro-target-set-threat"));
                const TSharedPtr<SEditableTextBox> ReloadedSetThreat = ReloadedSetHost.IsValid()
                    ? FindInput(ReloadedSetHost.ToSharedRef()) : nullptr;
                Scenario->bReloadAccepted = bCompatible && View->GetRevision() > Revision
                    && ReloadedSetThreat == Scenario->SetThreat;
                const int64 RejectedRevision = View->GetRevision();
                const TSharedRef<SWidget> RejectedRoot = View->GetRegion(TEXT("main"));
                const bool bRejected = NOT View->TryReload(
                    Markup.Replace(TEXT("aggro-target-mark-unperceived"), TEXT("aggro-missing-action")),
                    Css,
                    TEXT("Aggro rejected action")).Succeeded;
                Scenario->bReloadRejectedAtomically = bRejected && View->GetRevision() == RejectedRevision
                    && &View->GetRegion(TEXT("main")).Get() == &RejectedRoot.Get();
            }
            Slate.DestroyWindowImmediately(Window);
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(60));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(FCk_NetAutoTest_Condition::CreateLambda([Scenario]()
    {
        return ck::IsValid(Scenario->Aggro) && ck::IsValid(Scenario->TargetA)
            && NOT UCk_Utils_Aggro_UE::Get_IsEnabled(Scenario->Aggro)
            && UCk_Utils_Aggro_UE::TryGet_ActiveTrackedEntity(Scenario->Aggro) == Scenario->TrackedA
            && FMath::IsNearlyEqual(UCk_Utils_AggroTarget_UE::Get_Threat(Scenario->TargetA), 85.0f)
            && NOT UCk_Utils_AggroTarget_UE::Get_IsPerceived(Scenario->TargetA);
    }), 15.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, Scenario](UWorld*)
        {
            TestTrue(TEXT("physical Aggro controls dispatched through public APIs"), Scenario->bBuiltAndDispatched);
            TestFalse(TEXT("production owner toggle settles disabled"),
                UCk_Utils_Aggro_UE::Get_IsEnabled(Scenario->Aggro));
            TestTrue(TEXT("production Clear Active request drains then selection adopts the strongest eligible target"),
                OwnerRequestCount(Scenario->Aggro) == 0
                    && UCk_Utils_Aggro_UE::TryGet_ActiveTrackedEntity(Scenario->Aggro) == Scenario->TrackedA);
            TestTrue(TEXT("production Set Threat then Add Threat requests preserve authored order"),
                FMath::IsNearlyEqual(UCk_Utils_AggroTarget_UE::Get_Threat(Scenario->TargetA), 85.0f));
            TestFalse(TEXT("production Mark Unperceived request settles unperceived"),
                UCk_Utils_AggroTarget_UE::Get_IsPerceived(Scenario->TargetA));
            TestTrue(TEXT("compatible and rejected Aggro reloads preserve retained identity atomically"),
                Scenario->bReloadAccepted && Scenario->bReloadRejectedAtomically);

            const ck::FFragment_AggroTarget_SpatialParams SpatialParams =
                Scenario->TargetA.Get<ck::FFragment_AggroTarget_SpatialParams>();
            Scenario->TargetA.Try_Remove<ck::FFragment_AggroTarget_SpatialParams>();
            Scenario->TargetView->SlatePrepass();
            Scenario->MarkUnperceived->SimulateClick();
            Scenario->bCompositionLossFailedClosed = NOT Scenario->TargetView->Get_IsTargetAvailable()
                && NOT Scenario->TargetView->Get_CanRequestTarget()
                && Scenario->TargetView->Get_Text(TEXT("target-threat")) == TEXT("--")
                && TargetRequestCount(Scenario->TargetA) == 0;
            TestTrue(TEXT("held target controls fail closed after required Aggro composition loss"),
                Scenario->bCompositionLossFailedClosed);
            Scenario->TargetA.Add<ck::FFragment_AggroTarget_SpatialParams>(SpatialParams);

            TSharedPtr<SCkInspector_AggroAuthored> DestructorView;
            {
                auto DestructorInspector = MakeUnique<FCkInspector_Aggro>();
                DestructorView = StaticCastSharedRef<SCkInspector_AggroAuthored>(
                    DestructorInspector->Build_Inspector(Scenario->TargetB));
            }
            Scenario->Inspector->OnDeactivated();
            Scenario->bReleased = DestructorView->Is_Inert()
                && Scenario->OwnerView->Is_Inert() && Scenario->TargetView->Is_Inert()
                && Scenario->DiffView->Is_Inert()
                && NOT Scenario->OwnerView->Is_Mounted() && NOT Scenario->TargetView->Is_Mounted()
                && NOT Scenario->OwnerView->Get_View().IsValid() && NOT Scenario->TargetView->Get_View().IsValid();
            Toggle(Scenario->Enabled.ToSharedRef());
            Scenario->ClearAll->SimulateClick();
            Scenario->MarkUnperceived->SimulateClick();
            TestTrue(TEXT("destruction and deactivation release every Aggro authored surface and held controls stay inert"),
                Scenario->bReleased
                    && OwnerRequestCount(Scenario->Aggro) == 0
                    && TargetRequestCount(Scenario->TargetA) == 0);

            if (ck::IsValid(Scenario->Owner))
            { UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(Scenario->Owner); }
            Scenario->Inspector.Reset();
            Scenario->OwnerView.Reset();
            Scenario->TargetView.Reset();
            Scenario->DiffView.Reset();
            Scenario->Enabled.Reset();
            Scenario->ClearActive.Reset();
            Scenario->ClearAll.Reset();
            Scenario->MarkUnperceived.Reset();
            Scenario->SetThreat.Reset();
            Scenario->AddThreat.Reset();
            Scenario->Owner = {};
            Scenario->AggroEntity = {};
            Scenario->TrackedA = {};
            Scenario->TrackedB = {};
            Scenario->Aggro = {};
            Scenario->TargetA = {};
            Scenario->TargetB = {};
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(2));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif
