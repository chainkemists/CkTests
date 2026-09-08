#include "CkResourceInspector/CkResourceInspector_Subsystem.h"

#include "CkCore/Validation/CkIsValid.h"
#include "CkInput/CkInputLayer_Utils.h"
#include "CkInput/Subsystem/CkInputSource_Subsystem.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include "Engine/GameInstance.h"
#include "Engine/GameViewportClient.h"
#include "Engine/LocalPlayer.h"
#include "Engine/World.h"
#include "Framework/Application/SlateApplication.h"
#include "Framework/Application/SlateUser.h"
#include "GameFramework/PlayerController.h"
#include "Layout/WidgetPath.h"
#include "Misc/AutomationTest.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/Text/STextBlock.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_resource_inspector_subsystem
{
    constexpr int32 InputPriority = 1001;
    constexpr auto TestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::EngineFilter;

    struct FLifecycleState final
    {
        TWeakObjectPtr<ULocalPlayer> Player;
        TWeakObjectPtr<UGameViewportClient> Viewport;
        TWeakObjectPtr<APlayerController> Controller;
        TWeakObjectPtr<UCkResourceInspector_Subsystem> Inspector;
        FCk_Handle_InputSource InputSource;
        TSharedPtr<SButton> PreviousFocus;
        TWeakPtr<SWidget> InspectorFocus;
        EMouseCaptureMode PreviousCaptureMode = EMouseCaptureMode::CapturePermanently;
        EMouseLockMode PreviousLockMode = EMouseLockMode::LockAlways;
        bool PreviousShowCursor = false;
        int32 SlateUserIndex = INDEX_NONE;
        bool PrerequisitesReady = false;
        bool PreviousFocusAssigned = false;
        bool Opened = false;
        bool TeardownOpened = false;
    };

    auto GetPlayer(UWorld* InWorld) -> ULocalPlayer*
    {
        UGameInstance* Instance = IsValid(InWorld) ? InWorld->GetGameInstance() : nullptr;
        return IsValid(Instance) ? Instance->GetLocalPlayerByIndex(0) : nullptr;
    }

    auto HasSlatePath(const TSharedPtr<SWidget>& InWidget) -> bool
    {
        if (!InWidget.IsValid() || !FSlateApplication::IsInitialized()) { return false; }

        FWidgetPath Path;
        return FSlateApplication::Get().GeneratePathToWidgetUnchecked(InWidget.ToSharedRef(), Path);
    }

    auto IsInspectorSearchFocus(const TSharedPtr<SWidget>& InFocused) -> bool
    {
        if (!InFocused.IsValid() || !FSlateApplication::IsInitialized()) { return false; }

        FWidgetPath Path;
        if (!FSlateApplication::Get().GeneratePathToWidgetUnchecked(InFocused.ToSharedRef(), Path))
        { return false; }

        bool IsSearchDescendant = false;
        bool IsInspectorDescendant = false;
        for (int32 Index = 0; Index < Path.Widgets.Num(); ++Index)
        {
            const TSharedRef<SWidget>& Widget = Path.Widgets[Index].Widget;
            IsSearchDescendant |= Widget->GetTypeAsString() == TEXT("SSearchBox");
            IsInspectorDescendant |= Widget->GetTag() == TEXT("inspector-root");
        }

        return IsSearchDescendant && IsInspectorDescendant;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkResourceInspector_SubsystemLifecycle,
    "Ck.ResourceInspector.Host.Lifecycle",
    ck_tests_resource_inspector_subsystem::TestFlags)

bool FCkResourceInspector_SubsystemLifecycle::RunTest(const FString& Parameters)
{
    using namespace ck_tests_resource_inspector_subsystem;

    const TSharedRef<FLifecycleState> State = MakeShared<FLifecycleState>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            ULocalPlayer* Player = GetPlayer(ck::auto_test::net::Get_ServerWorld());
            UCk_InputSource_Subsystem* InputSubsystem =
                IsValid(Player) ? Player->GetSubsystem<UCk_InputSource_Subsystem>() : nullptr;
            return IsValid(InputSubsystem) && ck::IsValid(InputSubsystem->Get_InputSource());
        }),
        10.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld* InWorld) -> void
        {
            ULocalPlayer* Player = GetPlayer(InWorld);
            UGameViewportClient* Viewport = IsValid(Player) ? Player->ViewportClient.Get() : nullptr;
            APlayerController* Controller = IsValid(Player) ? Player->GetPlayerController(InWorld) : nullptr;
            UCk_InputSource_Subsystem* InputSubsystem =
                IsValid(Player) ? Player->GetSubsystem<UCk_InputSource_Subsystem>() : nullptr;
            const TSharedPtr<FSlateUser> SlateUser = IsValid(Player) ? Player->GetSlateUser() : nullptr;

            if (!IsValid(Player) || !IsValid(Viewport) || !IsValid(Controller) ||
                !IsValid(InputSubsystem) || !SlateUser.IsValid() || !FSlateApplication::IsInitialized())
            { return; }

            State->InputSource = InputSubsystem->Get_InputSource();
            if (!ck::IsValid(State->InputSource)) { return; }

            State->Player = Player;
            State->Viewport = Viewport;
            State->Controller = Controller;
            State->Inspector = Player->GetSubsystem<UCkResourceInspector_Subsystem>();
            State->SlateUserIndex = SlateUser->GetUserIndex();
            if (!State->Inspector.IsValid() || State->SlateUserIndex == INDEX_NONE) { return; }

            State->PreviousFocus = SNew(SButton)
                .IsFocusable(true)
                [SNew(STextBlock).Text(FText::FromString(TEXT("Previous inspector focus")))];
            Viewport->AddViewportWidgetForPlayer(Player, State->PreviousFocus.ToSharedRef(), -100);
            State->PrerequisitesReady = true;
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
        {
            return State->PrerequisitesReady && HasSlatePath(State->PreviousFocus);
        }),
        5.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld* InWorld) -> void
        {
            UGameViewportClient* Viewport = State->Viewport.Get();
            APlayerController* Controller = State->Controller.Get();
            UCkResourceInspector_Subsystem* Inspector = State->Inspector.Get();
            if (!State->PrerequisitesReady || !IsValid(Viewport) || !IsValid(Controller) ||
                !IsValid(Inspector) || !State->PreviousFocus.IsValid())
            { return; }

            FSlateApplication& Slate = FSlateApplication::Get();
            Slate.SetUserFocus(State->SlateUserIndex, State->PreviousFocus, EFocusCause::SetDirectly);
            State->PreviousFocusAssigned =
                Slate.GetUserFocusedWidget(State->SlateUserIndex) == State->PreviousFocus;
            State->PreviousCaptureMode = Viewport->GetMouseCaptureMode();
            State->PreviousLockMode = Viewport->GetMouseLockMode();
            State->PreviousShowCursor = Controller->bShowMouseCursor;
            State->Opened = Inspector->Request_Open();
            State->InspectorFocus = Slate.GetUserFocusedWidget(State->SlateUserIndex);
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
        {
            if (!ck::IsValid(State->InputSource)) { return false; }
            const FCk_Handle_InputLayer Layer =
                UCk_Utils_InputLayer_UE::TryGet_LayerWithPriority(State->InputSource, InputPriority);
            const TSharedPtr<SWidget> Focused = State->SlateUserIndex != INDEX_NONE && FSlateApplication::IsInitialized()
                ? FSlateApplication::Get().GetUserFocusedWidget(State->SlateUserIndex) : nullptr;
            if (IsInspectorSearchFocus(Focused)) { State->InspectorFocus = Focused; }

            return ck::IsValid(Layer) && UCk_Utils_InputLayer_UE::Get_HasCaptureForKey(
                Layer, ECk_InputLayer_CaptureMatch::CatchAll, FKey{}) && IsInspectorSearchFocus(Focused);
        }),
        5.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            UGameViewportClient* Viewport = State->Viewport.Get();
            APlayerController* Controller = State->Controller.Get();
            UCkResourceInspector_Subsystem* Inspector = State->Inspector.Get();

            if (!TestTrue(TEXT("PIE provides a ready local player, viewport, controller, Slate user, and CkInput source"),
                State->PrerequisitesReady && ck::IsValid(State->InputSource) && IsValid(Viewport) &&
                IsValid(Controller) && IsValid(Inspector)))
            { return true; }

            TestTrue(TEXT("The player-owned preexisting widget held focus before opening"), State->PreviousFocusAssigned);
            TestTrue(TEXT("Production Resource Inspector opens for the real local player"), State->Opened && Inspector->Get_IsOpen());

            const FCk_Handle_InputLayer Layer =
                UCk_Utils_InputLayer_UE::TryGet_LayerWithPriority(State->InputSource, InputPriority);
            TestTrue(TEXT("Opening creates the reserved local CkInput layer"), ck::IsValid(Layer));
            TestTrue(TEXT("Deferred CkInput processor installs the inspector catch-all capture"),
                ck::IsValid(Layer) && UCk_Utils_InputLayer_UE::Get_HasCaptureForKey(
                    Layer, ECk_InputLayer_CaptureMatch::CatchAll, FKey{}));
            TestEqual(TEXT("Opening sets the viewport to no capture"), Viewport->GetMouseCaptureMode(), EMouseCaptureMode::NoCapture);
            TestEqual(TEXT("Opening sets the viewport to no mouse lock"), Viewport->GetMouseLockMode(), EMouseLockMode::DoNotLock);
            TestTrue(TEXT("Opening shows the owning controller cursor"), Controller->bShowMouseCursor);

            const TSharedPtr<SWidget> Focused = FSlateApplication::Get().GetUserFocusedWidget(State->SlateUserIndex);
            TestTrue(TEXT("Opening focuses the authored inspector search control or its native editable descendant"),
                IsInspectorSearchFocus(Focused));
            TestTrue(TEXT("Focused production search control is mounted in the live Slate tree"), HasSlatePath(Focused));
            return true;
        }),
        TEXT("Resource Inspector opens with local input capture, focus, and viewport ownership")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld* InWorld) -> void
        {
            if (UCkResourceInspector_Subsystem* Inspector = State->Inspector.Get(); IsValid(Inspector))
            {
                Inspector->Request_Close();
                Inspector->Request_Close();
            }
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
        {
            if (!ck::IsValid(State->InputSource)) { return false; }
            const FCk_Handle_InputLayer Layer =
                UCk_Utils_InputLayer_UE::TryGet_LayerWithPriority(State->InputSource, InputPriority);
            return ck::IsValid(Layer) && !UCk_Utils_InputLayer_UE::Get_HasCaptureForKey(
                Layer, ECk_InputLayer_CaptureMatch::CatchAll, FKey{});
        }),
        5.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            UGameViewportClient* Viewport = State->Viewport.Get();
            APlayerController* Controller = State->Controller.Get();
            UCkResourceInspector_Subsystem* Inspector = State->Inspector.Get();
            if (!State->PrerequisitesReady || !IsValid(Viewport) || !IsValid(Controller) || !IsValid(Inspector))
            { return true; }

            TestFalse(TEXT("Repeated close leaves the production inspector closed"), Inspector->Get_IsOpen());
            const FCk_Handle_InputLayer Layer =
                UCk_Utils_InputLayer_UE::TryGet_LayerWithPriority(State->InputSource, InputPriority);
            TestTrue(TEXT("The local input layer remains owned for a later reopen"), ck::IsValid(Layer));
            TestFalse(TEXT("Closing removes the deferred catch-all capture"),
                ck::IsValid(Layer) && UCk_Utils_InputLayer_UE::Get_HasCaptureForKey(
                    Layer, ECk_InputLayer_CaptureMatch::CatchAll, FKey{}));
            TestEqual(TEXT("Closing restores the prior viewport capture mode"), Viewport->GetMouseCaptureMode(), State->PreviousCaptureMode);
            TestEqual(TEXT("Closing restores the prior viewport lock mode"), Viewport->GetMouseLockMode(), State->PreviousLockMode);
            TestEqual(TEXT("Closing restores the prior controller cursor state"), Controller->bShowMouseCursor, State->PreviousShowCursor);
            TestTrue(TEXT("Closing returns focus to the prior player-owned widget"),
                FSlateApplication::Get().GetUserFocusedWidget(State->SlateUserIndex) == State->PreviousFocus);
            TestFalse(TEXT("Closing detaches the previously focused inspector search from Slate"),
                HasSlatePath(State->InspectorFocus.Pin()));
            return true;
        }),
        TEXT("Resource Inspector close restores local UI state and removes capture")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld* InWorld) -> void
        {
            UGameViewportClient* Viewport = State->Viewport.Get();
            ULocalPlayer* Player = State->Player.Get();
            if (IsValid(Viewport) && IsValid(Player) && State->PreviousFocus.IsValid())
            { Viewport->RemoveViewportWidgetForPlayer(Player, State->PreviousFocus.ToSharedRef()); }

            if (UCkResourceInspector_Subsystem* Inspector = State->Inspector.Get(); IsValid(Inspector))
            { State->TeardownOpened = Inspector->Request_Open(); }
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
        {
            if (!ck::IsValid(State->InputSource)) { return false; }
            const FCk_Handle_InputLayer Layer =
                UCk_Utils_InputLayer_UE::TryGet_LayerWithPriority(State->InputSource, InputPriority);
            return State->TeardownOpened && ck::IsValid(Layer) &&
                UCk_Utils_InputLayer_UE::Get_HasCaptureForKey(
                    Layer, ECk_InputLayer_CaptureMatch::CatchAll, FKey{});
        }),
        5.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            if (State->PrerequisitesReady)
            {
                TestTrue(TEXT("Inspector can reopen before PIE teardown"), State->TeardownOpened);
                State->InspectorFocus = FSlateApplication::Get().GetUserFocusedWidget(State->SlateUserIndex);
                TestTrue(TEXT("Reopened inspector search is mounted before teardown"), IsInspectorSearchFocus(State->InspectorFocus.Pin()));
                if (UCkResourceInspector_Subsystem* Inspector = State->Inspector.Get(); IsValid(Inspector))
                { TestTrue(TEXT("Inspector remains open for its real subsystem deinitialize path"), Inspector->Get_IsOpen()); }
            }
            return true;
        }),
        TEXT("Resource Inspector remains open through PIE teardown")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            if (UCkResourceInspector_Subsystem* Inspector = State->Inspector.Get(); IsValid(Inspector))
            { TestFalse(TEXT("Subsystem teardown closes a surviving inspector instance"), Inspector->Get_IsOpen()); }
            TestFalse(TEXT("PIE teardown detaches the inspector's last focused widget"),
                HasSlatePath(State->InspectorFocus.Pin()));
            return true;
        }),
        TEXT("Resource Inspector subsystem teardown releases its live Slate mount")));
    return true;
}

#endif
