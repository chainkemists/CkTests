#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkCore/Validation/CkIsValid.h"
#include "CkDebuggerCommon/Styles/CkDebuggerStyle.h"
#include "CkDebuggerCommon/Widgets/SCkDebug_Switch.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Fragment.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcsDebugger/Inspectors/CkInspectorWidgetBuilder.h"
#include "CkEcsDebugger/Inspectors/CkInspector_UI.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkWorldSpaceWidget/CkWorldSpaceWidget_Fragment.h"

#include "Framework/Application/SlateApplication.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "Interfaces/IPluginManager.h"
#include "Misc/AutomationTest.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Widgets/Input/SEditableTextBox.h"
#include "Widgets/SNullWidget.h"
#include "Widgets/SWindow.h"

#include <variant>

namespace ck_tests_ui_authored_inspector
{
    constexpr auto kFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;

    auto FindTagged(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTag() == InTag && InRoot->GetVisibility().IsVisible())
        { return InRoot; }
        FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const auto Found = FindTagged(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag);
                Found.IsValid())
            { return Found; }
        }
        return nullptr;
    }

    auto FindType(const TSharedRef<SWidget>& InRoot, const FString& InType) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTypeAsString() == InType && InRoot->GetVisibility().IsVisible())
        { return InRoot; }
        FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const auto Found = FindType(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InType);
                Found.IsValid())
            { return Found; }
        }
        return nullptr;
    }

    auto FindInput(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SEditableTextBox>
    {
        const auto Host = FindTagged(InRoot, InTag);
        if (NOT Host.IsValid()) { return nullptr; }
        auto Input = FindType(Host.ToSharedRef(), TEXT("SEditableTextBox"));
        if (NOT Input.IsValid()) { Input = FindType(Host.ToSharedRef(), TEXT("SCkUiTextInputBox")); }
        return Input.IsValid() ? StaticCastSharedPtr<SEditableTextBox>(Input) : nullptr;
    }

    auto FindSwitch(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SCkDebug_Switch>
    {
        const auto Host = FindTagged(InRoot, InTag);
        const auto Widget = Host.IsValid() ? FindType(Host.ToSharedRef(), TEXT("SCkDebug_Switch")) : nullptr;
        return Widget.IsValid() ? StaticCastSharedPtr<SCkDebug_Switch>(Widget) : nullptr;
    }

    auto FindSelect(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SWidget>
    {
        const auto Host = FindTagged(InRoot, InTag);
        return Host.IsValid() ? FindType(Host.ToSharedRef(), TEXT("SCkUiSelect")) : nullptr;
    }

    auto Tick(FSlateApplication& InSlate) -> void
    { InSlate.PumpMessages(); InSlate.Tick(); InSlate.Tick(); }

    auto Key(const FKey InKey) -> FKeyEvent
    { return FKeyEvent{InKey, FModifierKeysState{}, 0, false, 0, 0}; }

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
        const bool bHandled = InSlate.ProcessKeyDownEvent(Key(EKeys::Enter));
        Tick(InSlate);
        return bHandled;
    }

    auto SelectDown(FSlateApplication& InSlate, const TSharedRef<SWidget>& InSelect) -> bool
    {
        const bool bFocused = InSlate.SetUserFocus(0, InSelect, EFocusCause::SetDirectly);
        Tick(InSlate);
        const bool bHandled = InSlate.ProcessKeyDownEvent(Key(EKeys::Down));
        Tick(InSlate);
        return bFocused && bHandled;
    }

    auto MakeParams() -> FCk_WorldSpaceWidget_Spec
    {
        auto Scaling = FCk_WorldSpaceWidget_ScalingInfo{ECk_WorldSpaceWidget_Scaling_Policy::None};
        Scaling.Set_MaxScale(1.25f)
            .Set_MinScale(0.25f)
            .Set_ScaleFalloff_StartDistance(111.0f)
            .Set_ScaleFalloff_EndDistance(222.0f);
        auto Fading = FCk_WorldSpaceWidget_FadingInfo{ECk_WorldSpaceWidget_Fading_Policy::None};
        Fading.Set_MaxOpacity(0.9f)
            .Set_MinOpacity(0.1f)
            .Set_FadeFalloff_StartDistance(333.0f)
            .Set_FadeFalloff_EndDistance(444.0f);
        auto Occlusion = FCk_WorldSpaceWidget_OcclusionInfo{ECk_WorldSpaceWidget_Occlusion_Policy::None};
        Occlusion.Set_TraceChannel(ECC_Camera);
        auto Params = FCk_WorldSpaceWidget_Spec{};
        Params.Set_ScalingInfo(Scaling).Set_FadingInfo(Fading).Set_OcclusionInfo(Occlusion);
        return Params;
    }

    auto AddFixtureComposition(FCk_Handle& InEntity) -> void
    {
        InEntity.Add<ck::FFragment_WorldSpaceWidget_Params>(MakeParams());
        InEntity.Add<ck::FFragment_WorldSpaceWidget>();
    }

    struct FScenario
    {
        FCk_Handle Owner;
        FCk_Handle Entity;
        FCk_Handle CurrentOnly;
        FCk_Handle DestructorEntity;
        TUniquePtr<FCkInspector_UI> Inspector;
        TSharedPtr<SCkInspector_UIAuthored> Authored;
        TSharedPtr<SCkInspector_UIAuthored> CurrentOnlyAuthored;
        TSharedPtr<FCkUiView> View;
        TSharedPtr<SCkDebug_Switch> EnabledSwitch;
        TSharedPtr<SWidget> ScalingSelect;
        TSharedPtr<SEditableTextBox> MaxOpacityInput;
        TSharedPtr<SWidget> TraceChannelSelect;
        TSharedPtr<SWindow> Window;
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_UI_AuthoredInspectorComposition,
    "Ck.UiAuthoring.EcsDebugger.UIInspector.AuthoredComposition",
    ck_tests_ui_authored_inspector::kFlags)

bool FCkTest_UI_AuthoredInspectorComposition::RunTest(const FString&)
{
    using namespace ck_tests_ui_authored_inspector;
    const auto Scenario = MakeShared<FScenario>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, Scenario](UWorld* InWorld)
        {
            if (NOT FSlateApplication::IsInitialized())
            { AddError(TEXT("authored UI inspector fixture requires Slate")); return; }

            Scenario->Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InWorld);
            Scenario->Entity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Scenario->Owner);
            Scenario->CurrentOnly = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Scenario->Owner);
            Scenario->DestructorEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Scenario->Owner);
            if (NOT TestTrue(TEXT("fixture creates live world-space-widget entities"),
                ck::IsValid(Scenario->Entity) && ck::IsValid(Scenario->CurrentOnly)
                    && ck::IsValid(Scenario->DestructorEntity)))
            { return; }
            AddFixtureComposition(Scenario->Entity);
            Scenario->CurrentOnly.Add<ck::FFragment_WorldSpaceWidget>();
            AddFixtureComposition(Scenario->DestructorEntity);

            Scenario->Inspector = MakeUnique<FCkInspector_UI>();
            auto NativeRows = TMap<FString, FString>{};
            {
                const FCkInspector_RowCaptureScope Capture{};
                Scenario->Inspector->Build_Inspector(Scenario->Entity);
                NativeRows = Capture.Get_Rows();
            }
            TestTrue(TEXT("native capture preserves status and complete control projection"),
                NativeRows.FindRef(TEXT("Wrapper Widget:")) == TEXT("Invalid")
                    && NativeRows.FindRef(TEXT("Owning Player:")) == TEXT("Invalid")
                    && NativeRows.Contains(TEXT("Enabled:"))
                    && NativeRows.Contains(TEXT("Scaling Policy:"))
                    && NativeRows.Contains(TEXT("Max Scale:"))
                    && NativeRows.Contains(TEXT("Max Opacity:"))
                    && NativeRows.Contains(TEXT("Occlusion Policy:"))
                    && NativeRows.Contains(TEXT("Trace Channel:")));

            const TSet<FString> DiffLabels{TEXT("Max Scale:")};
            TSharedRef<SWidget> Rendered = SNullWidget::NullWidget;
            {
                const FCkInspector_DiffMarkScope DiffScope{&DiffLabels};
                Rendered = Scenario->Inspector->Build_Inspector(Scenario->Entity);
            }
            if (NOT TestEqual(TEXT("UI mounts the authored inspector"),
                Rendered->GetTypeAsString(), FString{TEXT("SCkInspector_UIAuthored")}))
            {
                AddError(Scenario->Inspector->Get_LastAuthoredLoadError());
                return;
            }
            Scenario->Authored = StaticCastSharedRef<SCkInspector_UIAuthored>(Rendered);
            Scenario->View = Scenario->Authored->Get_View();
            TestTrue(TEXT("authored UI projects live status, controls, values, and native diff state"),
                Scenario->View.IsValid() && Scenario->Authored->Get_IsAvailable()
                    && Scenario->Authored->Get_HasControls() && Scenario->Authored->Get_CanEdit()
                    && Scenario->Authored->Get_Text(TEXT("wrapper")) == TEXT("Invalid")
                    && Scenario->Authored->Get_Text(TEXT("owner")) == TEXT("Invalid")
                    && Scenario->Authored->Get_Text(TEXT("scaling-policy")) == TEXT("none")
                    && Scenario->Authored->Get_Text(TEXT("fading-policy")) == TEXT("none")
                    && Scenario->Authored->Get_Text(TEXT("occlusion-policy")) == TEXT("none")
                    && FMath::IsNearlyEqual(Scenario->Authored->Get_Number(TEXT("max-scale")), 1.25f)
                    && FMath::IsNearlyEqual(Scenario->Authored->Get_Number(TEXT("max-opacity")), 0.9f)
                    && Scenario->Authored->Get_Color(TEXT("Max Scale:")) == CkStyle::Accent());

            const TSharedRef<SWidget> CurrentOnlyRendered = Scenario->Inspector->Build_Inspector(Scenario->CurrentOnly);
            if (NOT TestEqual(TEXT("Current-only UI state still mounts authored status presentation"),
                CurrentOnlyRendered->GetTypeAsString(), FString{TEXT("SCkInspector_UIAuthored")}))
            { return; }
            Scenario->CurrentOnlyAuthored = StaticCastSharedRef<SCkInspector_UIAuthored>(CurrentOnlyRendered);
            TestTrue(TEXT("Current-only UI presentation is available but has no edit controls"),
                Scenario->CurrentOnlyAuthored->Get_IsAvailable()
                    && NOT Scenario->CurrentOnlyAuthored->Get_HasControls()
                    && NOT Scenario->CurrentOnlyAuthored->Get_CanEdit());

            auto& Slate = FSlateApplication::Get();
            Scenario->Window = SNew(SWindow)
                .AutoCenter(EAutoCenter::None)
                .ClientSize(FVector2D{760.0f, 720.0f})
                .CreateTitleBar(false)
                .HasCloseButton(false)
                [Rendered];
            Slate.AddWindow(Scenario->Window.ToSharedRef(), true);
            Tick(Slate);
            Rendered->SlatePrepass(1.0f);
            Scenario->EnabledSwitch = FindSwitch(Rendered, TEXT("ui-enabled-switch"));
            Scenario->ScalingSelect = FindSelect(Rendered, TEXT("ui-scaling-policy"));
            Scenario->MaxOpacityInput = FindInput(Rendered, TEXT("ui-max-opacity"));
            Scenario->TraceChannelSelect = FindSelect(Rendered, TEXT("ui-trace-channel"));
            if (NOT TestTrue(TEXT("authored UI materializes each representative physical control"),
                Scenario->EnabledSwitch.IsValid() && Scenario->ScalingSelect.IsValid()
                    && Scenario->MaxOpacityInput.IsValid() && Scenario->TraceChannelSelect.IsValid()))
            { return; }

            Toggle(Scenario->EnabledSwitch.ToSharedRef());
            TestTrue(TEXT("physical Enabled switch dispatches the immediate public mutation"),
                Scenario->Entity.Has<ck::FTag_WorldSpaceWidget_Disabled>());

            TestTrue(TEXT("physical scaling select accepts keyboard traversal"),
                SelectDown(Slate, Scenario->ScalingSelect.ToSharedRef()));
            if (TestTrue(TEXT("scaling selection queues exactly one typed request"),
                Scenario->Entity.Has<ck::FFragment_WorldSpaceWidget_Requests>()
                    && Scenario->Entity.Get<ck::FFragment_WorldSpaceWidget_Requests>().Get_Requests().Num() == 1))
            {
                const auto& Requests = Scenario->Entity.Get<ck::FFragment_WorldSpaceWidget_Requests>().Get_Requests();
                TestTrue(TEXT("scaling selection preserves scalars while changing policy"),
                    std::holds_alternative<FCk_Request_WorldSpaceWidget_SetScalingInfo>(Requests[0])
                        && std::get<FCk_Request_WorldSpaceWidget_SetScalingInfo>(Requests[0])
                            .Get_ScalingInfo().Get_ScalingPolicy()
                            == ECk_WorldSpaceWidget_Scaling_Policy::ScaleWithDistance
                        && FMath::IsNearlyEqual(std::get<FCk_Request_WorldSpaceWidget_SetScalingInfo>(Requests[0])
                            .Get_ScalingInfo().Get_MaxScale(), 1.25f));
            }
            Scenario->Entity.Try_Remove<ck::FFragment_WorldSpaceWidget_Requests>();

            TestTrue(TEXT("physical max-opacity editor commits through its retained binding"),
                Commit(Slate, Scenario->MaxOpacityInput.ToSharedRef(), TEXT("0.75")));
            if (TestTrue(TEXT("opacity commit queues exactly one typed request"),
                Scenario->Entity.Has<ck::FFragment_WorldSpaceWidget_Requests>()
                    && Scenario->Entity.Get<ck::FFragment_WorldSpaceWidget_Requests>().Get_Requests().Num() == 1))
            {
                const auto& Requests = Scenario->Entity.Get<ck::FFragment_WorldSpaceWidget_Requests>().Get_Requests();
                TestTrue(TEXT("opacity commit clamps and preserves the fading policy"),
                    std::holds_alternative<FCk_Request_WorldSpaceWidget_SetFadingInfo>(Requests[0])
                        && FMath::IsNearlyEqual(std::get<FCk_Request_WorldSpaceWidget_SetFadingInfo>(Requests[0])
                            .Get_FadingInfo().Get_MaxOpacity(), 0.75f)
                        && std::get<FCk_Request_WorldSpaceWidget_SetFadingInfo>(Requests[0])
                            .Get_FadingInfo().Get_FadingPolicy() == ECk_WorldSpaceWidget_Fading_Policy::None);
            }
            Scenario->Entity.Try_Remove<ck::FFragment_WorldSpaceWidget_Requests>();

            TestTrue(TEXT("physical trace-channel select accepts keyboard traversal"),
                SelectDown(Slate, Scenario->TraceChannelSelect.ToSharedRef()));
            if (TestTrue(TEXT("trace-channel selection queues exactly one typed request"),
                Scenario->Entity.Has<ck::FFragment_WorldSpaceWidget_Requests>()
                    && Scenario->Entity.Get<ck::FFragment_WorldSpaceWidget_Requests>().Get_Requests().Num() == 1))
            {
                const auto& Requests = Scenario->Entity.Get<ck::FFragment_WorldSpaceWidget_Requests>().Get_Requests();
                TestTrue(TEXT("trace-channel selection preserves policy and changes channel"),
                    std::holds_alternative<FCk_Request_WorldSpaceWidget_SetOcclusionInfo>(Requests[0])
                        && std::get<FCk_Request_WorldSpaceWidget_SetOcclusionInfo>(Requests[0])
                            .Get_OcclusionInfo().Get_OcclusionPolicy()
                            == ECk_WorldSpaceWidget_Occlusion_Policy::None
                        && std::get<FCk_Request_WorldSpaceWidget_SetOcclusionInfo>(Requests[0])
                            .Get_OcclusionInfo().Get_TraceChannel() != ECC_Camera);
            }
            Scenario->Entity.Try_Remove<ck::FFragment_WorldSpaceWidget_Requests>();

            const TSharedPtr<IPlugin> Plugin = IPluginManager::Get().FindPlugin(TEXT("CkDebugger"));
            auto Markup = FString{};
            auto Stylesheet = FString{};
            const FString Root = Plugin.IsValid()
                ? FPaths::Combine(Plugin->GetBaseDir(), TEXT("Resources/UI")) : FString{};
            if (NOT TestTrue(TEXT("installed UI inspector resources are readable"),
                Plugin.IsValid()
                    && FFileHelper::LoadFileToString(Markup, *FPaths::Combine(Root, TEXT("EcsInspectorUI.ui.html")))
                    && FFileHelper::LoadFileToString(Stylesheet, *FPaths::Combine(Root, TEXT("EcsInspectorUI.ui.css")))))
            { return; }
            TestTrue(TEXT("HTML owns the complete UI inspector layout without native ports"),
                Markup.Contains(TEXT("id=\"ui-enabled-switch\""))
                    && Markup.Contains(TEXT("id=\"ui-scaling-policy\""))
                    && Markup.Contains(TEXT("id=\"ui-max-opacity\""))
                    && Markup.Contains(TEXT("id=\"ui-trace-channel\""))
                    && NOT Markup.Contains(TEXT("<native")));

            const int64 Revision = Scenario->View->GetRevision();
            const TSharedRef<SWidget> MainBefore = Scenario->View->GetRegion(TEXT("main"));
            TestTrue(TEXT("compatible UI reload advances the retained view"),
                Scenario->View->TryReload(Markup, Stylesheet, TEXT("UI compatible candidate")).Succeeded
                    && Scenario->View->GetRevision() > Revision);
            const int64 CompatibleRevision = Scenario->View->GetRevision();
            TestFalse(TEXT("missing UI action binding is rejected atomically"),
                Scenario->View->TryReload(
                    Markup.Replace(TEXT("ui-enabled-changed"), TEXT("ui-missing-enabled")),
                    Stylesheet, TEXT("UI rejected candidate")).Succeeded);
            TestTrue(TEXT("rejected UI reload preserves its exact tree and revision"),
                &Scenario->View->GetRegion(TEXT("main")).Get() == &MainBefore.Get()
                    && Scenario->View->GetRevision() == CompatibleRevision);

            Scenario->Entity.Try_Remove<ck::FFragment_WorldSpaceWidget_Params>();
            Tick(Slate);
            Toggle(Scenario->EnabledSwitch.ToSharedRef());
            Scenario->ScalingSelect->OnKeyDown(Scenario->ScalingSelect->GetCachedGeometry(), Key(EKeys::Down));
            Commit(Slate, Scenario->MaxOpacityInput.ToSharedRef(), TEXT("0.25"));
            TestTrue(TEXT("composition loss hides controls and leaves held controls inert"),
                Scenario->Authored->Get_IsAvailable() && NOT Scenario->Authored->Get_HasControls()
                    && Scenario->Entity.Has<ck::FTag_WorldSpaceWidget_Disabled>()
                    && NOT Scenario->Entity.Has<ck::FFragment_WorldSpaceWidget_Requests>());

            Scenario->Entity.Add<ck::FFragment_WorldSpaceWidget_Params>(MakeParams());
            Tick(Slate);
            Scenario->Entity.Add<ck::FTag_DestroyEntity_Initiate>();
            Toggle(Scenario->EnabledSwitch.ToSharedRef());
            Scenario->ScalingSelect->OnKeyDown(
                Scenario->ScalingSelect->GetCachedGeometry(), Key(EKeys::Down));
            TestTrue(TEXT("pending destruction makes every held UI control fail closed"),
                NOT Scenario->Inspector->CanInspect(Scenario->Entity)
                    && NOT Scenario->Authored->Get_IsAvailable()
                    && Scenario->Entity.Has<ck::FTag_WorldSpaceWidget_Disabled>()
                    && NOT Scenario->Entity.Has<ck::FFragment_WorldSpaceWidget_Requests>());

            TSharedPtr<SCkInspector_UIAuthored> DestructorAuthored;
            TWeakPtr<FCkUiView> DestructorView;
            {
                auto DestructorInspector = MakeUnique<FCkInspector_UI>();
                DestructorAuthored = StaticCastSharedRef<SCkInspector_UIAuthored>(
                    DestructorInspector->Build_Inspector(Scenario->DestructorEntity));
                DestructorView = DestructorAuthored->Get_View();
            }
            TestTrue(TEXT("UI inspector destruction releases its retained authored view"),
                DestructorAuthored.IsValid() && DestructorAuthored->Is_Inert()
                    && NOT DestructorAuthored->Is_Mounted() && NOT DestructorView.IsValid());

            Scenario->CurrentOnly.Add<ck::FTag_DestroyEntity_Initiate>();
            TestFalse(TEXT("pending destruction disables UI inspection"),
                Scenario->Inspector->CanInspect(Scenario->CurrentOnly));
            TestFalse(TEXT("pending destruction hides the authored UI surface"),
                Scenario->CurrentOnlyAuthored->Get_IsAvailable());

            Scenario->Inspector->OnDeactivated();
            TestTrue(TEXT("UI deactivation releases every retained authored view"),
                Scenario->Authored->Is_Inert() && Scenario->CurrentOnlyAuthored->Is_Inert()
                    && NOT Scenario->Authored->Is_Mounted()
                    && NOT Scenario->CurrentOnlyAuthored->Is_Mounted()
                    && NOT Scenario->Authored->Get_View().IsValid()
                    && NOT Scenario->CurrentOnlyAuthored->Get_View().IsValid());
            if (Scenario->Window.IsValid())
            {
                Slate.DestroyWindowImmediately(Scenario->Window.ToSharedRef());
                Scenario->Window.Reset();
            }
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif
