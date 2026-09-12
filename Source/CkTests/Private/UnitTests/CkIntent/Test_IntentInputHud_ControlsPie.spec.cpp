#include "CoreMinimal.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkIntentDebugger/Window/SCkIntentDebugger_InputHudControls.h"
#include "CkInputHudOverlay/Settings/CkInputHud_UserSettings.h"
#include "CkInputHudOverlay/Subsystem/CkInputHud_Subsystem.h"
#include "CkSlateLayout/SCkUiSurface.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include "Engine/GameInstance.h"
#include "Engine/LocalPlayer.h"
#include "Engine/World.h"
#include "Framework/Application/SlateApplication.h"
#include "HAL/IConsoleManager.h"
#include "Input/Events.h"
#include "Layout/WidgetPath.h"
#include "Misc/AutomationTest.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/Input/SEditableTextBox.h"
#include "Widgets/Layout/SScrollBox.h"
#include "Widgets/SWindow.h"

namespace ck_tests_intent_input_hud_controls_pie
{
    constexpr auto TestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;

    struct FCVarSnapshot final
    {
        FString Value;
        EConsoleVariableFlags Flags = ECVF_Default;
    };

    struct FState final
    {
        TWeakObjectPtr<ULocalPlayer> Player;
        TWeakObjectPtr<UCk_InputHud_Subsystem> Subsystem;
        TSharedPtr<SCkIntentDebugger_InputHudControls> Controls;
        TSharedPtr<SWindow> Window;
        TMap<FName, FCVarSnapshot> CVars;
        ECk_InputHud_AnchorCorner AnchorCorner = ECk_InputHud_AnchorCorner::TopRight;
        float AnchorOffsetX = 0.0f;
        float AnchorOffsetY = 0.0f;
        bool bSnapshotCaptured = false;
        bool bScenarioRan = false;
        bool bRestored = false;
        bool bScaleCommitted = false;
        bool bScalePresentsTwoDigits = false;
        bool bOpacityCommitted = false;
        bool bOffsetXCommitted = false;
        bool bOffsetYCommitted = false;
        bool bModeChanged = false;
        bool bCornerChanged = false;
        bool bPlacementPublished = false;
    };

    auto GetPlayer(UWorld* InWorld) -> ULocalPlayer*
    {
        UGameInstance* Instance = IsValid(InWorld) ? InWorld->GetGameInstance() : nullptr;
        return IsValid(Instance) ? Instance->GetLocalPlayerByIndex(0) : nullptr;
    }

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
            const TSharedRef<SWidget> Child = ConstCastSharedRef<SWidget>(Children->GetChildAt(Index));
            if (const TSharedPtr<SButton> Found = FindButtonDescendant(Child); Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto FindButton(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SButton>
    {
        const TSharedPtr<SWidget> Tagged = FindTagged(InRoot, InTag);
        return Tagged.IsValid() ? FindButtonDescendant(Tagged.ToSharedRef()) : nullptr;
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

    auto ReplaceAndCommit(FSlateApplication& InSlate, const TSharedRef<SEditableTextBox>& InEditor, const FString& InText) -> bool
    {
        InSlate.SetUserFocus(0, InEditor, EFocusCause::SetDirectly);
        Tick(InSlate);
        const FModifierKeysState Control{false, false, true, false, false, false, false, false, false};
        if (!InSlate.ProcessKeyDownEvent(FKeyEvent{EKeys::A, Control, 0, false, 0, 0})) { return false; }
        for (const TCHAR Character : InText)
        {
            if (!InSlate.ProcessKeyCharEvent(FCharacterEvent{Character, FModifierKeysState{}, 0, false}))
            { return false; }
        }
        if (!InSlate.ProcessKeyDownEvent(FKeyEvent{EKeys::Enter, FModifierKeysState{}, 0, false, 0, 0}))
        { return false; }
        Tick(InSlate);
        return true;
    }

    auto CaptureCVars(FState& InOutState) -> bool
    {
        const FName Names[] = {
            TEXT("ck.InputOverlay"), TEXT("ck.InputOverlay.Scale"), TEXT("ck.InputOverlay.Opacity"),
            TEXT("ck.InputOverlay.Corner"), TEXT("ck.InputOverlay.OffsetX"), TEXT("ck.InputOverlay.OffsetY")};
        for (const FName Name : Names)
        {
            IConsoleVariable* CVar = IConsoleManager::Get().FindConsoleVariable(*Name.ToString());
            if (CVar == nullptr) { return false; }
            InOutState.CVars.Add(Name, {CVar->GetString(), static_cast<EConsoleVariableFlags>(CVar->GetFlags())});
        }
        return true;
    }

    auto RestoreCVars(const FState& InState) -> bool
    {
        bool bRestored = true;
        for (const TPair<FName, FCVarSnapshot>& Pair : InState.CVars)
        {
            IConsoleVariable* CVar = IConsoleManager::Get().FindConsoleVariable(*Pair.Key.ToString());
            if (CVar == nullptr) { bRestored = false; continue; }
            const auto CurrentPriority = static_cast<EConsoleVariableFlags>(CVar->GetFlags() & ECVF_SetByMask);
            CVar->Set(*Pair.Value.Value, CurrentPriority);
            CVar->SetFlags(Pair.Value.Flags);
            if (CVar->GetString() != Pair.Value.Value ||
                static_cast<EConsoleVariableFlags>(CVar->GetFlags()) != Pair.Value.Flags)
            { bRestored = false; }
        }
        return bRestored;
    }

    auto GetCVarFloat(const TCHAR* InName) -> float
    {
        if (IConsoleVariable* CVar = IConsoleManager::Get().FindConsoleVariable(InName)) { return CVar->GetFloat(); }
        return -1.0f;
    }

    auto GetCVarInt(const TCHAR* InName) -> int32
    {
        if (IConsoleVariable* CVar = IConsoleManager::Get().FindConsoleVariable(InName)) { return CVar->GetInt(); }
        return INDEX_NONE;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkIntentInputHud_ControlsPie,
    "Ck.IntentDebugger.InputHudControls.PIE",
    ck_tests_intent_input_hud_controls_pie::TestFlags)

bool FCkIntentInputHud_ControlsPie::RunTest(const FString&)
{
    using namespace ck_tests_intent_input_hud_controls_pie;

    const TSharedRef<FState> State = MakeShared<FState>();
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, TEXT("/Engine/Maps/Entry")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            ULocalPlayer* Player = GetPlayer(ck::auto_test::net::Get_ServerWorld());
            return IsValid(Player) && IsValid(Player->GetSubsystem<UCk_InputHud_Subsystem>());
        }),
        10.0f));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld* InWorld) -> void
        {
            ULocalPlayer* Player = GetPlayer(InWorld);
            UCk_InputHud_Subsystem* Subsystem = IsValid(Player) ? Player->GetSubsystem<UCk_InputHud_Subsystem>() : nullptr;
            if (!IsValid(Player) || !IsValid(Subsystem) || !FSlateApplication::IsInitialized()) { return; }

            State->Player = Player;
            State->Subsystem = Subsystem;
            auto* User = UCk_InputHud_UserSettings::Get_Mutable();
            if (!IsValid(User) || !CaptureCVars(*State)) { return; }
            State->AnchorCorner = User->AnchorCorner;
            State->AnchorOffsetX = User->AnchorOffsetX;
            State->AnchorOffsetY = User->AnchorOffsetY;
            State->bSnapshotCaptured = true;

            FSlateApplication& Slate = FSlateApplication::Get();
            State->Controls = SNew(SCkIntentDebugger_InputHudControls);
            State->Window = SNew(SWindow)
                .AutoCenter(EAutoCenter::None)
                .ClientSize(FVector2D(500.0f, 600.0f))
                .CreateTitleBar(false)
                .HasCloseButton(false)
                [State->Controls.ToSharedRef()];
            Slate.AddWindow(State->Window.ToSharedRef(), true);
            Tick(Slate);

            const TSharedPtr<FCkUiView> View = State->Controls->Get_ControlsView();
            if (!View.IsValid() || !View->GetLastResult().Succeeded) { return; }
            const TSharedRef<SWidget> Region = View->GetRegion(TEXT("main"));
            const TSharedPtr<SScrollBox> Scroll = View->GetScroll(TEXT("intent-hud-body"));
            const TSharedPtr<SButton> Mode = FindButton(Region, TEXT("intent-hud-mode-next"));
            const TSharedPtr<SButton> Corner = FindButton(Region, TEXT("intent-hud-corner-next"));
            if (!Scroll.IsValid() || !Mode.IsValid() || !Corner.IsValid()) { return; }

            struct FNumberCase final { FName Id; float Target; float (*Read)(); bool* Result; };
            const FNumberCase Numbers[] = {
                {TEXT("intent-hud-scale-input"), 1.25f, [] { return GetCVarFloat(TEXT("ck.InputOverlay.Scale")); }, &State->bScaleCommitted},
                {TEXT("intent-hud-opacity-input"), 0.75f, [] { return GetCVarFloat(TEXT("ck.InputOverlay.Opacity")); }, &State->bOpacityCommitted},
                {TEXT("intent-hud-offset-x-input"), 37.0f, [] { return GetCVarFloat(TEXT("ck.InputOverlay.OffsetX")); }, &State->bOffsetXCommitted},
                {TEXT("intent-hud-offset-y-input"), 73.0f, [] { return GetCVarFloat(TEXT("ck.InputOverlay.OffsetY")); }, &State->bOffsetYCommitted}};
            for (const FNumberCase& Number : Numbers)
            {
                const TSharedPtr<SEditableTextBox> Editor = FindEditor(Region, Number.Id);
                if (!Editor.IsValid()) { return; }
                Scroll->ScrollDescendantIntoView(Editor.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
                Tick(Slate);
                const float Target = FMath::IsNearlyEqual(Number.Read(), Number.Target)
                    ? (Number.Id == FName(TEXT("intent-hud-scale-input")) ? 1.50f :
                        Number.Id == FName(TEXT("intent-hud-opacity-input")) ? 0.50f : Number.Target * 0.5f)
                    : Number.Target;
                *Number.Result = ReplaceAndCommit(Slate, Editor.ToSharedRef(), FString::SanitizeFloat(Target)) &&
                    FMath::IsNearlyEqual(Number.Read(), Target);
                if (Number.Id == FName(TEXT("intent-hud-scale-input")))
                {
                    Slate.ClearKeyboardFocus(EFocusCause::Cleared);
                    Tick(Slate);
                    State->bScalePresentsTwoDigits = Editor->GetText().ToString() == FString::Printf(TEXT("%.2f"), Target);
                }
            }

            const uint32 PlacementRevision = UCk_InputHud_UserSettings::Get_Revision();
            Scroll->ScrollDescendantIntoView(Mode.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
            Tick(Slate);
            const int32 ModeBefore = GetCVarInt(TEXT("ck.InputOverlay"));
            State->bModeChanged = Click(Slate, Mode.ToSharedRef()) && GetCVarInt(TEXT("ck.InputOverlay")) != ModeBefore;
            Scroll->ScrollDescendantIntoView(Corner.ToSharedRef(), false, EDescendantScrollDestination::IntoView);
            Tick(Slate);
            const int32 CornerBefore = GetCVarInt(TEXT("ck.InputOverlay.Corner"));
            State->bCornerChanged = Click(Slate, Corner.ToSharedRef()) && GetCVarInt(TEXT("ck.InputOverlay.Corner")) != CornerBefore;
            State->bPlacementPublished = UCk_InputHud_UserSettings::Get_Revision() > PlacementRevision &&
                FMath::IsNearlyEqual(User->AnchorOffsetX, GetCVarFloat(TEXT("ck.InputOverlay.OffsetX"))) &&
                FMath::IsNearlyEqual(User->AnchorOffsetY, GetCVarFloat(TEXT("ck.InputOverlay.OffsetY"))) &&
                static_cast<int32>(User->AnchorCorner) == GetCVarInt(TEXT("ck.InputOverlay.Corner"));
            State->bScenarioRan = true;
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            TestTrue(TEXT("PIE creates the real local player and Input HUD LocalPlayer subsystem"),
                State->bScenarioRan && State->Player.IsValid() && State->Subsystem.IsValid());
            TestTrue(TEXT("The real subsystem registers every Input HUD session CVar"), State->CVars.Num() == 6);
            TestTrue(TEXT("Authored session controls route real native numeric commits"),
                State->bScaleCommitted && State->bOpacityCommitted && State->bOffsetXCommitted && State->bOffsetYCommitted);
            TestTrue(TEXT("Scale input presents its committed session value with two authored fractional digits"),
                State->bScalePresentsTwoDigits);
            TestTrue(TEXT("Authored mode and corner actions route through mounted native buttons"),
                State->bModeChanged && State->bCornerChanged);
            TestTrue(TEXT("Offset and corner CVar callbacks publish the persisted placement"), State->bPlacementPublished);
            return true;
        }),
        TEXT("Intent HUD authored controls drive the real PIE LocalPlayer subsystem")));
    ADD_LATENT_AUTOMATION_COMMAND(FDelayedFunctionLatentCommand([State]() -> void
        {
            // This must not depend on locating the PIE server: a failed server command is precisely
            // when the test still needs to release its window and restore process-global CVar state.
            if (FSlateApplication::IsInitialized() && State->Window.IsValid())
            { FSlateApplication::Get().DestroyWindowImmediately(State->Window.ToSharedRef()); }
            State->Window.Reset();
            State->Controls.Reset();

            auto* User = UCk_InputHud_UserSettings::Get_Mutable();
            const bool bCVarsRestored = State->bSnapshotCaptured && RestoreCVars(*State);
            bool bPlacementRestored = State->bSnapshotCaptured && User != nullptr;
            if (bPlacementRestored)
            {
                User->Set_AnchorCorner(State->AnchorCorner);
                User->Set_AnchorOffsetX(State->AnchorOffsetX);
                User->Set_AnchorOffsetY(State->AnchorOffsetY);
                bPlacementRestored = User->AnchorCorner == State->AnchorCorner &&
                    FMath::IsNearlyEqual(User->AnchorOffsetX, State->AnchorOffsetX) &&
                    FMath::IsNearlyEqual(User->AnchorOffsetY, State->AnchorOffsetY);
            }
            State->bRestored = bCVarsRestored && bPlacementRestored;
        }));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            TestTrue(TEXT("PIE fixture restores CVar values, precedence, and user placement before teardown"), State->bRestored);
            return true;
        }),
        TEXT("Intent HUD PIE fixture restores global and persisted state")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif
