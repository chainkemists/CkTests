#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkAttribute/FloatAttribute/CkFloatAttribute_Utils.h"
#include "CkCamera/Camera/CkCamera_Component.h"
#include "CkCamera/Camera/CkCamera_Fragment.h"
#include "CkCamera/Camera/CkCamera_Utils.h"
#include "CkCamera/Camera/CameraLayer/CkCameraLayer_Fragment.h"
#include "CkCamera/Camera/CameraLayer/CkCameraLayer_Utils.h"
#include "CkCamera/Camera/CameraLayer/EntityScripts/CkCameraLayer_EntityScript.h"
#include "CkCore/Validation/CkIsValid.h"
#include "CkDebuggerCommon/Styles/CkDebuggerStyle.h"
#include "CkDebuggerCommon/Widgets/SCkDebug_Switch.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Fragment.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcsExt/Transform/CkTransform_Utils.h"
#include "CkEcsDebugger/Inspectors/CkInspectorWidgetBuilder.h"
#include "CkEcsDebugger/Inspectors/CkInspector_Camera.h"
#include "CkSlateLayout/CkUiCollection.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include "Engine/World.h"
#include "Framework/Application/SlateApplication.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "Interfaces/IPluginManager.h"
#include "Misc/AutomationTest.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Misc/ScopeExit.h"
#include "Widgets/Input/SEditableTextBox.h"
#include "Widgets/IToolTip.h"
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"

namespace ck_tests_camera_authored
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

    auto FindSwitchWidget(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SCkDebug_Switch>
    {
        if (InRoot->GetTypeAsString() == TEXT("SCkDebug_Switch"))
        { return StaticCastSharedRef<SCkDebug_Switch>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        if (Children == nullptr) { return nullptr; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SCkDebug_Switch> Found = FindSwitchWidget(
                ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid())
            { return Found; }
        }
        return nullptr;
    }

    auto FindSwitch(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SCkDebug_Switch>
    {
        const TSharedPtr<SWidget> Host = FindTagged(InRoot, InTag);
        return Host.IsValid() ? FindSwitchWidget(Host.ToSharedRef()) : nullptr;
    }

    auto FindText(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<STextBlock>
    {
        if (InRoot->GetTypeAsString() == TEXT("STextBlock")) { return StaticCastSharedRef<STextBlock>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        if (Children == nullptr) { return nullptr; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<STextBlock> Found = FindText(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid())
            { return Found; }
        }
        return nullptr;
    }

    auto TooltipText(const TSharedRef<SWidget>& InWidget) -> FString
    {
        const TSharedPtr<IToolTip> Tooltip = InWidget->GetToolTip();
        const TSharedPtr<STextBlock> Text = Tooltip.IsValid() ? FindText(Tooltip->GetContentWidget()) : nullptr;
        return Text.IsValid() ? Text->GetText().ToString() : FString{};
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

    auto Commit(FSlateApplication& InSlate, const TSharedRef<SEditableTextBox>& InInput,
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

    struct FWindowScope final
    {
        explicit FWindowScope(FSlateApplication& InSlate) : Slate(InSlate) {}
        ~FWindowScope() { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } }
        FSlateApplication& Slate;
        TSharedPtr<SWindow> Window;
    };

    struct FScenario
    {
        FCk_Handle Owner;
        FCk_Handle_Camera Camera;
        FCk_Handle_CameraLayer Layer;
        TObjectPtr<UCk_CameraComponent> Component;
        TUniquePtr<FCkInspector_Camera> Inspector;
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_Camera_AuthoredInspectorComposition,
    "Ck.UiAuthoring.EcsDebugger.CameraInspector.AuthoredComposition", ck_tests_camera_authored::kFlags)

bool FCkTest_Camera_AuthoredInspectorComposition::RunTest(const FString&)
{
    using namespace ck_tests_camera_authored;
    const auto Scenario = MakeShared<FScenario>();
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, Scenario](UWorld* World)
        {
            Scenario->Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(World);
            auto Transform = UCk_Utils_Transform_UE::Add(
                Scenario->Owner, FTransform::Identity, ECk_Replication::DoesNotReplicate);
            Scenario->Component = NewObject<UCk_CameraComponent>(World);
            if (NOT TestTrue(TEXT("production camera prerequisites exist"),
                ck::IsValid(Scenario->Owner) && ck::IsValid(Transform) && ck::IsValid(Scenario->Component)))
            { return; }

            Scenario->Camera = UCk_Utils_Camera_UE::Add(
                Transform, FCk_Camera_Spec{Scenario->Component});
            if (NOT TestTrue(TEXT("public Camera Add composes the complete director"),
                ck::IsValid(Scenario->Camera)
                    && Scenario->Camera.Has_All<ck::FFragment_Camera_Params,
                        ck::FFragment_Camera,
                        ck::FFragment_Camera_OrientationControl>()))
            { return; }
            auto MutableCamera = Scenario->Camera;
            ck::FUtils_RecordOfCameraLayers::ForEach_ValidEntry(MutableCamera,
                [Scenario](FCk_Handle_CameraLayer InLayer) { Scenario->Layer = InLayer; });
            if (NOT TestTrue(TEXT("production Add creates its persistent default layer"),
                ck::IsValid(Scenario->Layer)
                    && Scenario->Layer.Has_All<ck::FFragment_CameraLayer_Params,
                        ck::FFragment_CameraLayer_Blend>()))
            { return; }

            Scenario->Inspector = MakeUnique<FCkInspector_Camera>();
            auto DirectorRowsBefore = TMap<FString, FString>{};
            auto LayerRowsBefore = TMap<FString, FString>{};
            {
                const FCkInspector_RowCaptureScope Capture{};
                Scenario->Inspector->Build_Inspector(Scenario->Camera);
                DirectorRowsBefore = Capture.Get_Rows();
            }
            {
                const FCkInspector_RowCaptureScope Capture{};
                Scenario->Inspector->Build_Inspector(Scenario->Layer);
                LayerRowsBefore = Capture.Get_Rows();
            }
            TestTrue(TEXT("native row capture remains Camera comparison authority"),
                DirectorRowsBefore.Contains(TEXT("FOV:"))
                    && DirectorRowsBefore.Contains(TEXT("Snap Boom Rotation (R,P,Y):"))
                    && DirectorRowsBefore.Contains(TEXT("Base (resting)"))
                    && LayerRowsBefore.Contains(TEXT("Alpha (cur → target):")));

            const TSharedRef<SWidget> DirectorBuilt = Scenario->Inspector->Build_Inspector(Scenario->Camera);
            const FString DirectorLoadError = Scenario->Inspector->Get_LastAuthoredLoadError();
            const TSharedRef<SWidget> LayerBuilt = Scenario->Inspector->Build_Inspector(Scenario->Layer);
            const FString LayerLoadError = Scenario->Inspector->Get_LastAuthoredLoadError();
            if (NOT TestTrue(*FString::Printf(TEXT("real director and selected layer use authored types (director: %s; layer: %s; errors: %s | %s)"),
                *DirectorBuilt->GetTypeAsString(), *LayerBuilt->GetTypeAsString(), *DirectorLoadError, *LayerLoadError),
                DirectorBuilt->GetTypeAsString() == TEXT("SCkInspector_CameraAuthored")
                    && LayerBuilt->GetTypeAsString() == TEXT("SCkInspector_CameraAuthored")))
            { return; }
            const TSharedRef<SCkInspector_CameraAuthored> Director = StaticCastSharedRef<SCkInspector_CameraAuthored>(DirectorBuilt);
            const TSharedRef<SCkInspector_CameraAuthored> Layer = StaticCastSharedRef<SCkInspector_CameraAuthored>(LayerBuilt);
            if (NOT TestTrue(TEXT("real director and selected layer mount independent authored bodies"),
                Director->Is_Mounted() && Layer->Is_Mounted()
                    && Director->Get_View().IsValid() && Layer->Get_View().IsValid()
                    && Director->Get_View() != Layer->Get_View()
                    && Director->Get_LayersCollection() != Layer->Get_LayersCollection()))
            { return; }

            const TSharedPtr<FCkUiView> View = Director->Get_View();
            const TSharedPtr<FCkUiCollection> Layers = Director->Get_LayersCollection();
            const TSharedRef<SWidget> Rendered = View->GetRegion(TEXT("main"));
            const TSharedPtr<SCkDebug_Switch> FixedBoom =
                FindSwitch(Rendered, TEXT("camera-fixed-boom-switch"));
            const TSharedPtr<SWidget> BoomYawHost = FindTagged(Rendered, TEXT("camera-boom-yaw-input"));
            const TSharedPtr<SWidget> YawMinHost = FindTagged(Rendered, TEXT("camera-yaw-min-input"));
            const TSharedPtr<SWidget> IntentionXHost = FindTagged(Rendered, TEXT("camera-intention-x-input"));
            const TSharedPtr<SEditableTextBox> BoomYaw = BoomYawHost.IsValid() ? FindInput(BoomYawHost.ToSharedRef()) : nullptr;
            const TSharedPtr<SEditableTextBox> YawMin = YawMinHost.IsValid() ? FindInput(YawMinHost.ToSharedRef()) : nullptr;
            const TSharedPtr<SEditableTextBox> IntentionX = IntentionXHost.IsValid() ? FindInput(IntentionXHost.ToSharedRef()) : nullptr;

            FSlateApplication& Slate = FSlateApplication::Get();
            FWindowScope WindowScope{Slate};
            WindowScope.Window = SNew(SWindow)
                .AutoCenter(EAutoCenter::None)
                .ClientSize(FVector2D{720.0f, 900.0f})
                .CreateTitleBar(false)
                .HasCloseButton(false)
                [Director];
            Slate.AddWindow(WindowScope.Window.ToSharedRef(), true);
            Tick(Slate);
            const bool bControlsReady = Director->Get_CanEdit() && FixedBoom.IsValid() && FixedBoom->IsEnabled()
                && BoomYaw.IsValid() && YawMin.IsValid() && IntentionX.IsValid();
            if (NOT TestTrue(*FString::Printf(TEXT("authored Camera exposes enabled physical controls (can-edit=%d reason='%s' switch=%d/%d boom=%d yaw-min=%d intention=%d)"),
                Director->Get_CanEdit(), *Director->Get_EditDisabledReason(), FixedBoom.IsValid(),
                FixedBoom.IsValid() && FixedBoom->IsEnabled(), BoomYaw.IsValid(), YawMin.IsValid(), IntentionX.IsValid()),
                bControlsReady))
            { return; }

            const bool bFixedBefore = Scenario->Camera.Get<ck::FFragment_Camera>().Get_UseFixedBoomRotation();
            Toggle(FixedBoom.ToSharedRef());
            TestEqual(TEXT("physical fixed-boom switch mutates the real camera Current"),
                Scenario->Camera.Get<ck::FFragment_Camera>().Get_UseFixedBoomRotation(), NOT bFixedBefore);
            if (NOT TestTrue(TEXT("physical boom, yaw-limit, and intention commits dispatch"),
                Commit(Slate, BoomYaw.ToSharedRef(), TEXT("47.5"))
                    && Commit(Slate, YawMin.ToSharedRef(), TEXT("-81.25"))
                    && Commit(Slate, IntentionX.ToSharedRef(), TEXT("0.625"))))
            { return; }
            TestTrue(TEXT("physical boom and intention inputs update real Current immediately"),
                FMath::IsNearlyEqual(
                    Scenario->Camera.Get<ck::FFragment_Camera>().Get_PovState()._BoomArmRotation.Yaw, 47.5f)
                    && FMath::IsNearlyEqual(
                        Scenario->Camera.Get<ck::FFragment_Camera>().Get_OrientationIntention().X, 0.625f));
            TSharedPtr<SCkInspector_CameraAuthored> DedicatedView;
            UWorld* const DedicatedWorld = UWorld::CreateWorld(EWorldType::PIE, false);
            ON_SCOPE_EXIT { if (DedicatedWorld != nullptr) { DedicatedWorld->DestroyWorld(false); } };
            if (TestTrue(TEXT("fixture creates a dedicated-server cosmetic-denial world"),
                DedicatedWorld != nullptr))
            {
                DedicatedWorld->SetPlayInEditorInitialNetMode(NM_DedicatedServer);
                auto DedicatedOwner =
                    UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(DedicatedWorld);
                auto DedicatedTransform = UCk_Utils_Transform_UE::Add(
                    DedicatedOwner, FTransform::Identity, ECk_Replication::DoesNotReplicate);
                TObjectPtr<UCk_CameraComponent> DedicatedComponent =
                    NewObject<UCk_CameraComponent>(DedicatedWorld);
                auto DedicatedCamera = UCk_Utils_Camera_UE::Add(
                    DedicatedTransform, FCk_Camera_Spec{DedicatedComponent});
                if (NOT TestTrue(TEXT("dedicated production Camera composition succeeds"),
                    ck::IsValid(DedicatedOwner) && ck::IsValid(DedicatedTransform)
                        && ck::IsValid(DedicatedComponent) && ck::IsValid(DedicatedCamera)
                        && DedicatedCamera.Has_All<ck::FFragment_Camera_Params,
                            ck::FFragment_Camera>()))
                { return; }
                const TSharedRef<SWidget> DedicatedBuilt =
                    Scenario->Inspector->Build_Inspector(DedicatedCamera);
                if (NOT TestEqual(TEXT("dedicated Camera still mounts the authored surface"),
                    DedicatedBuilt->GetTypeAsString(), FString{TEXT("SCkInspector_CameraAuthored")}))
                { return; }
                DedicatedView = StaticCastSharedRef<SCkInspector_CameraAuthored>(DedicatedBuilt);
                if (NOT TestTrue(TEXT("dedicated authored Camera owns a valid view"),
                    DedicatedView->Is_Mounted() && DedicatedView->Get_View().IsValid()))
                { return; }
                const TSharedPtr<SCkDebug_Switch> DedicatedFixedBoom = FindSwitch(
                    DedicatedView->Get_View()->GetRegion(TEXT("main")), TEXT("camera-fixed-boom-switch"));
                const TSharedPtr<SWidget> DedicatedBoomYawHost = FindTagged(
                    DedicatedView->Get_View()->GetRegion(TEXT("main")), TEXT("camera-boom-yaw-input"));
                const TSharedPtr<SEditableTextBox> DedicatedBoomYaw = DedicatedBoomYawHost.IsValid()
                    ? FindInput(DedicatedBoomYawHost.ToSharedRef()) : nullptr;
                if (DedicatedFixedBoom.IsValid())
                { DedicatedFixedBoom->SlatePrepass(); }
                if (DedicatedBoomYaw.IsValid())
                { DedicatedBoomYaw->SlatePrepass(); }
                const bool bDedicatedBefore =
                    DedicatedCamera.Get<ck::FFragment_Camera>().Get_UseFixedBoomRotation();
                const FString DedicatedSwitchTooltip = DedicatedFixedBoom.IsValid()
                    ? TooltipText(DedicatedFixedBoom.ToSharedRef()) : FString{};
                const FString DedicatedNumberTooltip = DedicatedBoomYaw.IsValid()
                    ? TooltipText(DedicatedBoomYaw.ToSharedRef()) : FString{};
                const bool bDedicatedDenied = DedicatedWorld->GetNetMode() == NM_DedicatedServer
                        && NOT DedicatedView->Get_CanEdit()
                        && DedicatedView->Get_EditDisabledReason().Contains(TEXT("Dedicated server"))
                        && DedicatedFixedBoom.IsValid() && NOT DedicatedFixedBoom->IsEnabled()
                        && DedicatedSwitchTooltip.Contains(TEXT("Dedicated server"))
                        && DedicatedBoomYawHost.IsValid() && DedicatedBoomYaw.IsValid()
                        && NOT DedicatedBoomYaw->IsEnabled()
                        && DedicatedNumberTooltip.Contains(TEXT("Dedicated server"));
                TestTrue(*FString::Printf(TEXT("dedicated Camera controls deny with reasons (mode=%d can-edit=%d reason='%s' switch=%d/%d/'%s' number=%d/%d/'%s')"),
                    DedicatedWorld->GetNetMode(), DedicatedView->Get_CanEdit(), *DedicatedView->Get_EditDisabledReason(),
                    DedicatedFixedBoom.IsValid(), DedicatedFixedBoom.IsValid() && DedicatedFixedBoom->IsEnabled(),
                    *DedicatedSwitchTooltip, DedicatedBoomYaw.IsValid(), DedicatedBoomYaw.IsValid() && DedicatedBoomYaw->IsEnabled(),
                    *DedicatedNumberTooltip), bDedicatedDenied);
                if (DedicatedFixedBoom.IsValid())
                { Toggle(DedicatedFixedBoom.ToSharedRef()); }
                TestEqual(TEXT("disabled dedicated-server physical control cannot mutate Camera Current"),
                    DedicatedCamera.Get<ck::FFragment_Camera>().Get_UseFixedBoomRotation(),
                    bDedicatedBefore);
            }

            Scenario->Layer.Get<ck::FFragment_CameraLayer_Blend>().Set_Alpha(0.375f);
            auto DirectorRowsAfter = TMap<FString, FString>{};
            auto LayerRowsAfter = TMap<FString, FString>{};
            {
                const FCkInspector_RowCaptureScope Capture{};
                Scenario->Inspector->Build_Inspector(Scenario->Camera);
                DirectorRowsAfter = Capture.Get_Rows();
            }
            {
                const FCkInspector_RowCaptureScope Capture{};
                Scenario->Inspector->Build_Inspector(Scenario->Layer);
                LayerRowsAfter = Capture.Get_Rows();
            }
            TSet<FString> Differing = FCkInspectorWidgetBuilder::Compute_DifferingLabels(
                {DirectorRowsBefore, DirectorRowsAfter});
            for (const FString& Label : FCkInspectorWidgetBuilder::Compute_DifferingLabels(
                {LayerRowsBefore, LayerRowsAfter}))
            { Differing.Add(Label); }
            TSharedPtr<SCkInspector_CameraAuthored> DiffView;
            {
                const FCkInspector_DiffMarkScope DiffScope{&Differing};
                DiffView = StaticCastSharedRef<SCkInspector_CameraAuthored>(
                    Scenario->Inspector->Build_Inspector(Scenario->Camera));
            }
            const TSharedPtr<const FCkUiRecord> BaseRecord =
                DiffView.IsValid() && DiffView->Get_LayersCollection().IsValid()
                    ? DiffView->Get_LayersCollection()->FindRecord(Scenario->Layer.ToString()) : nullptr;
            const FCkUiFieldValue* BaseLabelColor = BaseRecord.IsValid()
                ? BaseRecord->FindField(TEXT("label-color")) : nullptr;
            const bool bFixedDiff = DiffView.IsValid() && DiffView->Is_DiffMarked(TEXT("Use Fixed Boom Rotation:"));
            const bool bBoomDiff = DiffView.IsValid() && DiffView->Is_DiffMarked(TEXT("Snap Boom Rotation (R,P,Y):"));
            const bool bBaseDiff = DiffView.IsValid() && DiffView->Is_DiffMarked(TEXT("Base (resting)"));
            const bool bBaseAccent = BaseLabelColor != nullptr && BaseLabelColor->Color == CkStyle::Accent();
            TestTrue(*FString::Printf(TEXT("authored Camera preserves exact native diff verdicts (labels='%s' fixed=%d boom=%d base=%d accent=%d)"),
                *FString::Join(Differing.Array(), TEXT(",")), bFixedDiff, bBoomDiff, bBaseDiff, bBaseAccent),
                DiffView.IsValid()
                    && NOT bFixedDiff && bBoomDiff && bBaseDiff && bBaseAccent);
            TSharedPtr<SCkInspector_CameraAuthored> ControlDiffView;
            auto ControlDiffering = TSet<FString>{TEXT("Use Fixed Boom Rotation:")};
            {
                const FCkInspector_DiffMarkScope DiffScope{&ControlDiffering};
                ControlDiffView = StaticCastSharedRef<SCkInspector_CameraAuthored>(
                    Scenario->Inspector->Build_Inspector(Scenario->Camera));
            }
            TestTrue(TEXT("authored fixed-boom control exposes its native-label diff projection route"),
                ControlDiffView.IsValid() && ControlDiffView->Is_DiffMarked(TEXT("Use Fixed Boom Rotation:")));

            const TSharedPtr<IPlugin> Plugin = IPluginManager::Get().FindPlugin(TEXT("CkDebugger"));
            FString Markup, Css;
            const FString ResourceRoot = Plugin.IsValid()
                ? FPaths::Combine(Plugin->GetBaseDir(), TEXT("Resources/UI")) : FString{};
            if (NOT TestTrue(TEXT("installed Camera authored resources are readable"), Plugin.IsValid()
                && FFileHelper::LoadFileToString(Markup, *FPaths::Combine(ResourceRoot, TEXT("EcsInspectorCamera.ui.html")))
                && FFileHelper::LoadFileToString(Css, *FPaths::Combine(ResourceRoot, TEXT("EcsInspectorCamera.ui.css")))))
            { return; }
            TestTrue(TEXT("Camera HTML owns all parity sections and controls without native layout ports"),
                Markup.Contains(TEXT("camera-layer-records"))
                    && Markup.Contains(TEXT("camera-fixed-boom-switch"))
                    && Markup.Contains(TEXT("camera-boom-yaw-input"))
                    && Markup.Contains(TEXT("camera-layer-detail"))
                    && Markup.Contains(TEXT("camera-unavailable"))
                    && NOT Markup.Contains(TEXT("<native")));

            const int64 RevisionBefore = View->GetRevision();
            const TSharedPtr<const FCkUiRecord> BaseBefore = Layers->FindRecord(Scenario->Layer.ToString());
            TestTrue(TEXT("compatible Camera reload preserves view, record, and physical control identity"),
                View->TryReload(Markup, Css, TEXT("Camera compatible")).Succeeded
                    && View->GetRevision() > RevisionBefore
                    && Layers->FindRecord(Scenario->Layer.ToString()) == BaseBefore
                    && FindSwitch(Rendered, TEXT("camera-fixed-boom-switch")) == FixedBoom);
            const int64 RevisionBeforeRejected = View->GetRevision();
            const TSharedRef<SWidget> RootBeforeRejected = View->GetRegion(TEXT("main"));
            TestFalse(TEXT("missing Camera action binding is rejected atomically"), View->TryReload(
                Markup.Replace(TEXT("fixed-boom-changed"), TEXT("camera-missing-action")),
                Css, TEXT("Camera rejected action")).Succeeded);
            TestTrue(TEXT("rejected Camera reload retains the prior tree and revision"),
                &View->GetRegion(TEXT("main")).Get() == &RootBeforeRejected.Get()
                    && View->GetRevision() == RevisionBeforeRejected);

            auto ExtraLayer = UCk_Utils_CameraLayer_UE::Create(
                Scenario->Camera, UCk_CameraLayer_Default_EntityScript::StaticClass());
            Director->Tick(FGeometry::MakeRoot(FVector2D{1.0f, 1.0f}, FSlateLayoutTransform{}), 0.0, 0.0f);
            TestTrue(TEXT("authored layer collection reconciles a live production record without replacing the base record"),
                ck::IsValid(ExtraLayer) && Layers->GetRecords().Num() == 2
                    && Layers->FindRecord(Scenario->Layer.ToString()) == BaseBefore
                    && Layers->FindRecord(ExtraLayer.ToString()).IsValid());

            const bool bBeforeCompositionLoss =
                Scenario->Camera.Get<ck::FFragment_Camera>().Get_UseFixedBoomRotation();
            const ck::FFragment_Camera_Params ParamsBeforeCompositionLoss =
                Scenario->Camera.Get<ck::FFragment_Camera_Params>();
            Scenario->Camera.Try_Remove<ck::FFragment_Camera_Params>();
            FixedBoom->SlatePrepass();
            Toggle(FixedBoom.ToSharedRef());
            TestTrue(TEXT("held control fails closed after required Camera composition loss"),
                NOT Director->Get_CanEdit() && NOT FixedBoom->IsEnabled()
                    && Scenario->Camera.Get<ck::FFragment_Camera>().Get_UseFixedBoomRotation()
                        == bBeforeCompositionLoss);
            Scenario->Camera.Add<ck::FFragment_Camera_Params>(ParamsBeforeCompositionLoss);

            TSharedPtr<SCkInspector_CameraAuthored> DestructorView;
            {
                auto DestructorInspector = MakeUnique<FCkInspector_Camera>();
                DestructorView = StaticCastSharedRef<SCkInspector_CameraAuthored>(
                    DestructorInspector->Build_Inspector(Scenario->Layer));
            }
            Scenario->Inspector->OnDeactivated();
            TestTrue(TEXT("Camera inspector destruction and deactivation release every retained authored surface"),
                DestructorView->Is_Inert() && Director->Is_Inert() && Layer->Is_Inert() && DiffView->Is_Inert()
                    && ControlDiffView->Is_Inert()
                    && DedicatedView.IsValid() && DedicatedView->Is_Inert()
                    && NOT DestructorView->Is_Mounted() && NOT Director->Is_Mounted()
                    && NOT Director->Get_View().IsValid() && NOT Director->Get_LayersCollection().IsValid());
            Toggle(FixedBoom.ToSharedRef());
            TestEqual(TEXT("held physical control remains inert after Camera deactivation"),
                Scenario->Camera.Get<ck::FFragment_Camera>().Get_UseFixedBoomRotation(),
                bBeforeCompositionLoss);
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(2));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(FCk_NetAutoTest_ServerAction::CreateLambda(
        [this, Scenario](UWorld*)
        {
            if (NOT TestTrue(TEXT("Camera retains its orientation-control composition through teardown coverage"),
                ck::IsValid(Scenario->Camera) && Scenario->Camera.Has<ck::FFragment_Camera_OrientationControl>()))
            { return; }
            const FCk_Handle_FloatAttribute YawLimits =
                Scenario->Camera.Get<ck::FFragment_Camera_OrientationControl>()._Yaw._Limits;
            TestTrue(TEXT("physical yaw input reaches the materialized orientation attribute after processor settlement"),
                FMath::IsNearlyEqual(UCk_Utils_FloatAttribute_UE::Get_FinalValue(
                    YawLimits, ECk_MinMaxCurrent::Min), -81.25f));
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif
