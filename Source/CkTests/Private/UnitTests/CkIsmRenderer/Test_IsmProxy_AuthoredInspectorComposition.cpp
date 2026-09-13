#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkCore/Enums/CkEnums.h"
#include "CkCore/Validation/CkIsValid.h"
#include "CkDebuggerCommon/Widgets/SCkDebug_NumericEditor.h"
#include "CkDebuggerCommon/Widgets/SCkDebug_Switch.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Net/CkNet_Utils.h"
#include "CkEcsDebugger/Inspectors/CkInspectorWidgetBuilder.h"
#include "CkEcsDebugger/Inspectors/CkInspector_IsmProxy.h"
#include "CkEcsExt/Transform/CkTransform_Utils.h"
#include "CkIsmRenderer/CkIsmSubsystem.h"
#include "CkIsmRenderer/Proxy/CkIsmProxy_Fragment.h"
#include "CkIsmRenderer/Proxy/CkIsmProxy_Utils.h"
#include "CkIsmRenderer/Renderer/CkIsmRenderer_TransientFactory.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include "Components/InstancedStaticMeshComponent.h"
#include "Engine/StaticMesh.h"
#include "Engine/World.h"
#include "Framework/Application/SlateApplication.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "Interfaces/IPluginManager.h"
#include "Materials/Material.h"
#include "Materials/MaterialInterface.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Widgets/Input/SEditableTextBox.h"
#include "Widgets/SBoxPanel.h"
#include "Widgets/SNullWidget.h"
#include "Widgets/SWindow.h"

namespace ck_tests_ismproxy_authored_inspector
{
    constexpr auto kTestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;
    constexpr auto kEntryMapPath = TEXT("/Engine/Maps/Entry");
    constexpr auto kReadyTimeoutSeconds = 30.0;

    struct FScenario
    {
        FCk_Handle _OwnerA;
        FCk_Handle _OwnerB;
        FCk_Handle_Transform _TransformA;
        FCk_Handle_Transform _TransformB;
        FCk_Handle_IsmProxy _ProxyA;
        FCk_Handle_IsmProxy _ProxyB;
        TWeakObjectPtr<UCk_IsmRenderer_Subsystem_UE> _RendererSubsystem;
        TUniquePtr<FCkInspector_IsmProxy> _Inspector;
        TSharedPtr<SCkInspector_IsmProxyAuthored> _AuthoredA;
        TSharedPtr<SCkInspector_IsmProxyAuthored> _AuthoredB;
        TSharedPtr<FCkUiView> _ViewA;
        TSharedPtr<FCkUiView> _ViewB;
        TSharedPtr<SWindow> _Window;
        TSharedPtr<SCkDebug_Switch> _SwitchA;
        TSharedPtr<SCkDebug_Switch> _SwitchB;
        TSharedPtr<SEditableTextBox> _IndexInput;
        TSharedPtr<SEditableTextBox> _ValueInput;
    };

    auto MakeAuthorityNetSettings() -> FCk_Net_ConnectionSettings
    {
        return FCk_Net_ConnectionSettings{
            ECk_Replication::DoesNotReplicate,
            ECk_Net_NetModeType::ClientAndHost,
            ECk_Net_EntityNetRole::Authority};
    }

    auto FindTaggedWidget(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTag() == InTag)
        { return InRoot; }
        FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const auto Found = FindTaggedWidget(
                ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag); Found.IsValid())
            { return Found; }
        }
        return nullptr;
    }

    auto FindDescendantByType(const TSharedRef<SWidget>& InRoot, const FString& InType) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTypeAsString() == InType)
        { return InRoot; }
        FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const auto Found = FindDescendantByType(
                ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InType); Found.IsValid())
            { return Found; }
        }
        return nullptr;
    }

    auto TickSlate(FSlateApplication& InSlate) -> void
    {
        InSlate.PumpMessages();
        InSlate.Tick();
        InSlate.Tick();
    }

    auto WidgetPathContains(const FWidgetPath& InPath, const TSharedRef<SWidget>& InWidget) -> bool
    {
        for (int32 Index = 0; Index < InPath.Widgets.Num(); ++Index)
        { if (InPath.Widgets[Index].Widget == InWidget) { return true; } }
        return false;
    }

    auto Click(FSlateApplication& InSlate, const TSharedRef<SWidget>& InWidget) -> bool
    {
        const TSharedPtr<SWindow> Window = InSlate.FindWidgetWindow(InWidget);
        if (NOT Window.IsValid() || NOT Window->GetNativeWindow().IsValid())
        { return false; }
        Window->BringToFront(true);
        TickSlate(InSlate);
        InSlate.ReleaseAllPointerCapture(0);
        const FGeometry Geometry = InWidget->GetCachedGeometry();
        if (Geometry.GetLocalSize().X <= 0.0f || Geometry.GetLocalSize().Y <= 0.0f)
        { return false; }
        const FVector2D Position = Geometry.LocalToAbsolute(Geometry.GetLocalSize() * 0.5f);
        const TSet<FKey> NoButtons;
        const TSet<FKey> LeftDown{EKeys::LeftMouseButton};
        const FPointerEvent MoveEvent(0, FSlateApplication::CursorPointerIndex, Position, Position,
            NoButtons, EKeys::Invalid, 0.0f, FModifierKeysState{});
        const FPointerEvent DownEvent(0, FSlateApplication::CursorPointerIndex, Position, Position,
            LeftDown, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        const FPointerEvent UpEvent(0, FSlateApplication::CursorPointerIndex, Position, Position,
            NoButtons, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        InSlate.SetCursorPos(Position);
        InSlate.ProcessMouseMoveEvent(MoveEvent, true);
        const FWidgetPath TargetPath = InSlate.LocateWindowUnderMouse(
            Position, InSlate.GetInteractiveTopLevelWindows(), false, 0);
        if (NOT WidgetPathContains(TargetPath, InWidget))
        { return false; }
        const bool bDownHandled = InSlate.ProcessMouseButtonDownEvent(Window->GetNativeWindow(), DownEvent);
        InSlate.ProcessMouseButtonUpEvent(UpEvent);
        TickSlate(InSlate);
        return bDownHandled;
    }

    auto SetAndCommit(
        FSlateApplication& InSlate,
        const TSharedRef<SEditableTextBox>& InInput,
        const FString& InText) -> bool
    {
        InSlate.SetUserFocus(0, InInput, EFocusCause::SetDirectly);
        TickSlate(InSlate);
        InInput->SetText(FText::FromString(InText));
        const bool bHandled = InSlate.ProcessKeyDownEvent(
            FKeyEvent{EKeys::Enter, FModifierKeysState{}, 0, false, 0, 0});
        TickSlate(InSlate);
        return bHandled;
    }

    auto HasLiveInstance(const FCk_Handle_IsmProxy& InProxy, UCk_IsmRenderer_Subsystem_UE* InSubsystem) -> bool
    {
        if (NOT ck::IsValid(InProxy) || NOT ck::IsValid(InSubsystem)
            || NOT InProxy.Has<ck::FFragment_IsmProxy_Params>()
            || NOT InProxy.Has<ck::FFragment_IsmProxy_Current>())
        { return false; }
        const auto& RendererData = InProxy.Get<ck::FFragment_IsmProxy_Params>().Get_IsmRenderer().Get();
        if (NOT ck::IsValid(RendererData))
        { return false; }
        UInstancedStaticMeshComponent* const Component =
            InSubsystem->FindOrCache_IsmComponent(RendererData).Get();
        return ck::IsValid(Component)
            && Component->IsValidId(InProxy.Get<ck::FFragment_IsmProxy_Current>().Get_IsmInstanceIndex());
    }

    auto GetLiveCustomValue(
        const FCk_Handle_IsmProxy& InProxy,
        UCk_IsmRenderer_Subsystem_UE* InSubsystem,
        float& OutValue) -> bool
    {
        OutValue = 0.0f;
        if (NOT HasLiveInstance(InProxy, InSubsystem))
        { return false; }
        const auto& RendererData = InProxy.Get<ck::FFragment_IsmProxy_Params>().Get_IsmRenderer().Get();
        UInstancedStaticMeshComponent* const Component =
            InSubsystem->FindOrCache_IsmComponent(RendererData).Get();
        const int32 InstanceIndex = Component->GetInstanceIndexForId(
            InProxy.Get<ck::FFragment_IsmProxy_Current>().Get_IsmInstanceIndex());
        if (InstanceIndex == INDEX_NONE || Component->NumCustomDataFloats <= 0)
        { return false; }
        const int32 Offset = InstanceIndex * Component->NumCustomDataFloats;
        if (NOT Component->PerInstanceSMCustomData.IsValidIndex(Offset))
        { return false; }
        OutValue = Component->PerInstanceSMCustomData[Offset];
        return true;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_IsmProxy_AuthoredInspectorComposition,
    "CkTests.UnitTests.CkIsmRenderer.IsmProxy.AuthoredInspectorComposition",
    ck_tests_ismproxy_authored_inspector::kTestFlags)

bool FCkTest_IsmProxy_AuthoredInspectorComposition::RunTest(const FString&)
{
    using namespace ck_tests_ismproxy_authored_inspector;
    const auto Scenario = MakeShared<FScenario>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, kEntryMapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, kReadyTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, Scenario](UWorld* InWorld) -> void
        {
            UStaticMesh* const Mesh = LoadObject<UStaticMesh>(nullptr, TEXT("/Engine/BasicShapes/Cube.Cube"));
            UMaterialInterface* const Material = LoadObject<UMaterialInterface>(nullptr,
                TEXT("/CkFoundation/CkUsf/GeneratedLooks/M_CkUsf_Look_PerInstanceHue.M_CkUsf_Look_PerInstanceHue"));
            if (NOT TestTrue(TEXT("live fixture loads its mesh and authored ISM material"),
                ck::IsValid(Mesh) && ck::IsValid(Material) && ck::IsValid(Material->GetMaterial())))
            { return; }

            auto* RendererData = UCk_Utils_IsmRenderer_TransientFactory_UE::
                GetOrCreate_ForMeshWithMaterialsAndCustomData(
                    InWorld, Mesh, {FCk_MeshMaterialOverride{0, Material}}, 1, ECk_Mobility::Movable);
            Scenario->_RendererSubsystem = InWorld->GetSubsystem<UCk_IsmRenderer_Subsystem_UE>();
            Scenario->_OwnerA = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InWorld);
            Scenario->_OwnerB = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InWorld);
            if (NOT TestTrue(TEXT("live fixture creates renderer, subsystem, and transient owner"),
                ck::IsValid(RendererData) && Scenario->_RendererSubsystem.IsValid()
                    && ck::IsValid(Scenario->_OwnerA) && ck::IsValid(Scenario->_OwnerB)))
            { return; }
            UCk_Utils_Net_UE::Add(Scenario->_OwnerA, MakeAuthorityNetSettings());
            UCk_Utils_Net_UE::Add(Scenario->_OwnerB, MakeAuthorityNetSettings());

            Scenario->_TransformA = UCk_Utils_Transform_UE::Add(
                Scenario->_OwnerA, FTransform::Identity, ECk_Replication::DoesNotReplicate);
            Scenario->_TransformB = UCk_Utils_Transform_UE::Add(
                Scenario->_OwnerB, FTransform{FVector{100.0, 0.0, 0.0}}, ECk_Replication::DoesNotReplicate);
            auto ParamsA = FCk_Fragment_IsmProxy_ParamsData{RendererData};
            ParamsA.Set_LocalLocationOffset(FVector{11.0, -19.0, 23.0});
            ParamsA.Set_LocalRotationOffset(FRotator{37.0, 53.0, -71.0});
            ParamsA.Set_ScaleMultiplier(FVector{0.5, 1.75, 1.25});
            ParamsA.Get_CustomInstanceDataDefaults().Add(
                FCk_CustomPrimitiveData{0, FCk_CustomPrimitiveData_Value{0.5f}});
            auto ParamsB = FCk_Fragment_IsmProxy_ParamsData{RendererData};
            ParamsB.Set_LocalLocationOffset(FVector{-3.0, 5.0, 7.0});
            ParamsB.Set_LocalRotationOffset(FRotator{1.0, 2.0, 3.0});
            ParamsB.Set_ScaleMultiplier(FVector{2.0, 2.0, 2.0});
            ParamsB.Get_CustomInstanceDataDefaults().Add(
                FCk_CustomPrimitiveData{0, FCk_CustomPrimitiveData_Value{0.25f}});
            Scenario->_ProxyA = UCk_Utils_IsmProxy_UE::Add(Scenario->_TransformA, ParamsA);
            Scenario->_ProxyB = UCk_Utils_IsmProxy_UE::Add(Scenario->_TransformB, ParamsB);
            TestTrue(TEXT("public APIs add two independent movable proxies"),
                ck::IsValid(Scenario->_ProxyA) && ck::IsValid(Scenario->_ProxyB));
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(
        this,
        FCk_NetAutoTest_Condition::CreateLambda([Scenario]() -> bool
        {
            return HasLiveInstance(Scenario->_ProxyA, Scenario->_RendererSubsystem.Get())
                && HasLiveInstance(Scenario->_ProxyB, Scenario->_RendererSubsystem.Get());
        }),
        kReadyTimeoutSeconds,
        TEXT("production setup creates both live ISM instances")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, Scenario](UWorld*) -> void
        {
            if (NOT FSlateApplication::IsInitialized())
            { AddError(TEXT("authored ISM Proxy fixture requires Slate")); return; }
            Scenario->_Inspector = MakeUnique<FCkInspector_IsmProxy>();
            auto RowsA = TMap<FString, FString>{};
            auto RowsB = TMap<FString, FString>{};
            {
                const FCkInspector_RowCaptureScope Capture{};
                Scenario->_Inspector->Build_Inspector(Scenario->_ProxyA);
                RowsA = Capture.Get_Rows();
            }
            {
                const FCkInspector_RowCaptureScope Capture{};
                Scenario->_Inspector->Build_Inspector(Scenario->_ProxyB);
                RowsB = Capture.Get_Rows();
            }
            const TSet<FString> Differing =
                FCkInspectorWidgetBuilder::Compute_DifferingLabels({RowsA, RowsB});
            TestTrue(TEXT("native capture remains complete and drives the expected proxy differences"),
                RowsA.Num() == 9 && RowsB.Num() == 9
                    && RowsA.FindRef(TEXT("Mesh:")) == TEXT("Cube")
                    && RowsA.FindRef(TEXT("Mobility:")) == TEXT("Movable")
                    && Differing.Contains(TEXT("Location Offset:"))
                    && Differing.Contains(TEXT("Rotation Offset (R,P,Y):"))
                    && Differing.Contains(TEXT("Scale Multiplier:"))
                    && Differing.Contains(TEXT("  Value:"))
                    && NOT Differing.Contains(TEXT("Mesh:"))
                    && NOT Differing.Contains(TEXT("Mobility:")));

            TSharedRef<SWidget> WidgetA = SNullWidget::NullWidget;
            TSharedRef<SWidget> WidgetB = SNullWidget::NullWidget;
            {
                const FCkInspector_DiffMarkScope DiffScope{&Differing};
                WidgetA = Scenario->_Inspector->Build_Inspector(Scenario->_ProxyA);
                WidgetB = Scenario->_Inspector->Build_Inspector(Scenario->_ProxyB);
            }
            if (NOT TestTrue(TEXT("production builds two independent authored ISM Proxy bodies"),
                WidgetA->GetTypeAsString() == TEXT("SCkInspector_IsmProxyAuthored")
                    && WidgetB->GetTypeAsString() == TEXT("SCkInspector_IsmProxyAuthored")))
            {
                AddError(Scenario->_Inspector->Get_LastAuthoredLoadError());
                return;
            }
            Scenario->_AuthoredA = StaticCastSharedRef<SCkInspector_IsmProxyAuthored>(WidgetA);
            Scenario->_AuthoredB = StaticCastSharedRef<SCkInspector_IsmProxyAuthored>(WidgetB);
            Scenario->_ViewA = Scenario->_AuthoredA->Get_View();
            Scenario->_ViewB = Scenario->_AuthoredB->Get_View();
            TestTrue(TEXT("authored bodies preserve live values, precision/order, and exact diff state"),
                Scenario->_ViewA.IsValid() && Scenario->_ViewB.IsValid()
                    && Scenario->_ViewA != Scenario->_ViewB
                    && Scenario->_AuthoredA->Get_MeshText() == TEXT("Cube")
                    && Scenario->_AuthoredA->Get_MobilityText() == TEXT("Movable")
                    && Scenario->_AuthoredA->Get_LocationXText() == TEXT("11.0")
                    && Scenario->_AuthoredA->Get_RotationRollText() == TEXT("-71.00")
                    && Scenario->_AuthoredA->Get_RotationPitchText() == TEXT("37.00")
                    && Scenario->_AuthoredA->Get_RotationYawText() == TEXT("53.00")
                    && Scenario->_AuthoredA->Get_ScaleYText() == TEXT("1.75")
                    && FMath::IsNearlyEqual(Scenario->_AuthoredA->Get_CustomDataValue(), 0.5f)
                    && Scenario->_AuthoredA->Is_DiffMarked(TEXT("Location Offset:"))
                    && Scenario->_AuthoredA->Is_DiffMarked(TEXT("  Value:"))
                    && NOT Scenario->_AuthoredA->Is_DiffMarked(TEXT("Mesh:")));

            const TSharedPtr<IPlugin> Plugin = IPluginManager::Get().FindPlugin(TEXT("CkDebugger"));
            FString Markup;
            FString Stylesheet;
            const FString Root = Plugin.IsValid()
                ? FPaths::Combine(Plugin->GetBaseDir(), TEXT("Resources/UI")) : FString{};
            if (NOT TestTrue(TEXT("installed ISM Proxy resources are readable"),
                Plugin.IsValid()
                    && FFileHelper::LoadFileToString(
                        Markup, *FPaths::Combine(Root, TEXT("EcsInspectorIsmProxy.ui.html")))
                    && FFileHelper::LoadFileToString(
                        Stylesheet, *FPaths::Combine(Root, TEXT("EcsInspectorIsmProxy.ui.css")))))
            { return; }
            TestTrue(TEXT("resource owns complete control and axis placement without native ports"),
                Markup.Contains(TEXT("<debug-switch"))
                    && Markup.Contains(TEXT("id=\"ism-proxy-custom-index-input\""))
                    && Markup.Contains(TEXT("id=\"ism-proxy-custom-value-input\""))
                    && NOT Markup.Contains(TEXT("<native")));

            const int64 RevisionA = Scenario->_ViewA->GetRevision();
            const int64 RevisionB = Scenario->_ViewB->GetRevision();
            const TSharedRef<SWidget> MainB = Scenario->_ViewB->GetRegion(TEXT("main"));
            TestTrue(TEXT("compatible reload advances only its retained view"),
                Scenario->_ViewA->TryReload(
                    Markup, Stylesheet, TEXT("ISM Proxy compatible candidate")).Succeeded
                    && Scenario->_ViewA->GetRevision() > RevisionA
                    && Scenario->_ViewB->GetRevision() == RevisionB);
            TestFalse(TEXT("missing mesh binding is rejected atomically"),
                Scenario->_ViewB->TryReload(
                    Markup.Replace(TEXT("bind=\"ism-proxy-mesh\""),
                        TEXT("bind=\"ism-proxy-missing-mesh\"")),
                    Stylesheet, TEXT("ISM Proxy rejected candidate")).Succeeded);
            TestTrue(TEXT("rejected reload retains the exact main tree and revision"),
                &Scenario->_ViewB->GetRegion(TEXT("main")).Get() == &MainB.Get()
                    && Scenario->_ViewB->GetRevision() == RevisionB);

            FSlateApplication& Slate = FSlateApplication::Get();
            Scenario->_Window = SNew(SWindow)
                .AutoCenter(EAutoCenter::None)
                .ClientSize(FVector2D{760.0f, 620.0f})
                .CreateTitleBar(false)
                .HasCloseButton(false)
                [SNew(SVerticalBox)
                    + SVerticalBox::Slot().AutoHeight()[Scenario->_AuthoredA.ToSharedRef()]
                    + SVerticalBox::Slot().AutoHeight()[Scenario->_AuthoredB.ToSharedRef()]];
            Slate.AddWindow(Scenario->_Window.ToSharedRef(), true);
            TickSlate(Slate);

            const auto SwitchAWidget = FindTaggedWidget(
                Scenario->_AuthoredA.ToSharedRef(), TEXT("ism-proxy-enabled-switch"));
            const auto SwitchBWidget = FindTaggedWidget(
                Scenario->_AuthoredB.ToSharedRef(), TEXT("ism-proxy-enabled-switch"));
            const auto IndexWidget = FindTaggedWidget(
                Scenario->_AuthoredA.ToSharedRef(), TEXT("ism-proxy-custom-index-input"));
            const auto ValueWidget = FindTaggedWidget(
                Scenario->_AuthoredA.ToSharedRef(), TEXT("ism-proxy-custom-value-input"));
            if (NOT TestTrue(TEXT("authored resource mounts physical switch and number inputs"),
                SwitchAWidget.IsValid() && SwitchBWidget.IsValid()
                    && IndexWidget.IsValid() && ValueWidget.IsValid()))
            { return; }
            Scenario->_SwitchA = StaticCastSharedPtr<SCkDebug_Switch>(SwitchAWidget);
            Scenario->_SwitchB = StaticCastSharedPtr<SCkDebug_Switch>(SwitchBWidget);
            const auto IndexInput = FindDescendantByType(IndexWidget.ToSharedRef(), TEXT("SCkUiTextInputBox"));
            const auto ValueInput = FindDescendantByType(ValueWidget.ToSharedRef(), TEXT("SCkUiTextInputBox"));
            if (NOT TestTrue(TEXT("both authored number inputs retain canonical Slate editors"),
                IndexInput.IsValid() && ValueInput.IsValid()))
            { return; }
            Scenario->_IndexInput = StaticCastSharedPtr<SEditableTextBox>(IndexInput);
            Scenario->_ValueInput = StaticCastSharedPtr<SEditableTextBox>(ValueInput);
            TestTrue(TEXT("physical controls dispatch through authored bindings"),
                SetAndCommit(Slate, Scenario->_IndexInput.ToSharedRef(), TEXT("0"))
                    && SetAndCommit(Slate, Scenario->_ValueInput.ToSharedRef(), TEXT("0.75"))
                    && Click(Slate, Scenario->_SwitchA.ToSharedRef()));
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(
        this,
        FCk_NetAutoTest_Condition::CreateLambda([Scenario]() -> bool
        {
            const auto Data = ck::IsValid(Scenario->_ProxyA)
                ? UCk_Utils_IsmProxy_UE::Get_CustomInstanceData(Scenario->_ProxyA) : TArray<float>{};
            return ck::IsValid(Scenario->_ProxyA)
                && Scenario->_ProxyA.Has<ck::FTag_IsmProxy_Disabled>()
                && Data.Num() == 1 && FMath::IsNearlyEqual(Data[0], 0.75f);
        }),
        kReadyTimeoutSeconds,
        TEXT("production request lane applies authored value and disable requests")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, Scenario](UWorld*) -> void
        {
            if (NOT TestTrue(TEXT("authored controls remain retained after the first request"),
                Scenario->_AuthoredA.IsValid() && Scenario->_SwitchA.IsValid()))
            { return; }
            TestTrue(TEXT("physical disable removes the live instance and preserves CPU custom data"),
                NOT HasLiveInstance(Scenario->_ProxyA, Scenario->_RendererSubsystem.Get())
                    && FMath::IsNearlyEqual(Scenario->_AuthoredA->Get_CustomDataValue(), 0.75f));
            FSlateApplication& Slate = FSlateApplication::Get();
            Scenario->_SwitchA->SlatePrepass();
            TestTrue(TEXT("physical switch re-enables through the authored route"),
                Click(Slate, Scenario->_SwitchA.ToSharedRef()));
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(
        this,
        FCk_NetAutoTest_Condition::CreateLambda([Scenario]() -> bool
        {
            return NOT Scenario->_ProxyA.Has<ck::FTag_IsmProxy_Disabled>()
                && HasLiveInstance(Scenario->_ProxyA, Scenario->_RendererSubsystem.Get());
        }),
        kReadyTimeoutSeconds,
        TEXT("production request lane restores the live ISM instance")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, Scenario](UWorld*) -> void
        {
            if (NOT TestTrue(TEXT("authored controls remain retained through re-enable"),
                Scenario->_AuthoredA.IsValid() && Scenario->_AuthoredB.IsValid()
                    && Scenario->_SwitchA.IsValid() && Scenario->_SwitchB.IsValid()
                    && Scenario->_ValueInput.IsValid() && Scenario->_Inspector.IsValid()))
            { return; }
            float GpuValue = 0.0f;
            TestTrue(TEXT("re-enabled live instance receives the authored custom-data value"),
                GetLiveCustomValue(
                    Scenario->_ProxyA, Scenario->_RendererSubsystem.Get(), GpuValue)
                    && FMath::IsNearlyEqual(GpuValue, 0.75f));

            Scenario->_ProxyA.Try_Remove<ck::FFragment_IsmProxy_Current>();
            FSlateApplication& Slate = FSlateApplication::Get();
            Scenario->_SwitchA->SlatePrepass();
            Scenario->_ValueInput->SlatePrepass();
            TickSlate(Slate);
            TestFalse(TEXT("partial composition is not inspectable"),
                Scenario->_Inspector->CanInspect(Scenario->_ProxyA));
            TestFalse(TEXT("partial composition is unavailable to the retained authored body"),
                Scenario->_AuthoredA->Get_IsAvailable());
            TestFalse(TEXT("partial composition cannot edit through the retained authored body"),
                Scenario->_AuthoredA->Get_CanEdit());
            TestFalse(TEXT("partial composition disables the retained physical value input"),
                Scenario->_ValueInput->IsEnabled());
            TestEqual(TEXT("partial composition projects the unavailable mesh placeholder"),
            Scenario->_AuthoredA->Get_MeshText(), FString{TEXT("--")});
            Scenario->_ProxyA.Try_Remove<ck::FFragment_IsmProxy_Requests>();
            Click(Slate, Scenario->_SwitchA.ToSharedRef());
            SetAndCommit(Slate, Scenario->_ValueInput.ToSharedRef(), TEXT("0.9"));
            TestFalse(TEXT("stale physical controls cannot publish requests"),
                Scenario->_ProxyA.Has<ck::FFragment_IsmProxy_Requests>());
            {
                const FCkInspector_RowCaptureScope Capture{};
                Scenario->_Inspector->Build_Inspector(Scenario->_ProxyA);
                TestTrue(TEXT("native capture also fails closed after Current disappears"),
                    Capture.Get_Rows().FindRef(TEXT("Mesh:")) == TEXT("--"));
            }

            TSharedPtr<SCkInspector_IsmProxyAuthored> DestructorAuthored;
            {
                auto DestructorInspector = MakeUnique<FCkInspector_IsmProxy>();
                const TSharedRef<SWidget> Widget = DestructorInspector->Build_Inspector(Scenario->_ProxyB);
                DestructorAuthored = StaticCastSharedRef<SCkInspector_IsmProxyAuthored>(Widget);
            }
            TestTrue(TEXT("inspector destruction releases its retained authored body"),
                DestructorAuthored.IsValid() && DestructorAuthored->Is_Inert()
                    && NOT DestructorAuthored->Is_Mounted()
                    && NOT DestructorAuthored->Get_View().IsValid());

            Scenario->_ProxyB.Try_Remove<ck::FFragment_IsmProxy_Requests>();
            Scenario->_Inspector->OnDeactivated();
            Click(Slate, Scenario->_SwitchB.ToSharedRef());
            TestTrue(TEXT("deactivation releases both bodies and leaves held physical controls inert"),
                Scenario->_AuthoredA->Is_Inert() && Scenario->_AuthoredB->Is_Inert()
                    && NOT Scenario->_AuthoredA->Get_View().IsValid()
                    && NOT Scenario->_AuthoredB->Get_View().IsValid()
                    && NOT Scenario->_ProxyB.Has<ck::FFragment_IsmProxy_Requests>());
            if (Scenario->_Window.IsValid())
            {
                Slate.DestroyWindowImmediately(Scenario->_Window.ToSharedRef());
                Scenario->_Window.Reset();
            }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif
