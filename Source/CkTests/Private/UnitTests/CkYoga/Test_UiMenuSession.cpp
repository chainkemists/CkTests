#include "CkSlateLayout/CkUiMenuSession.h"

#include "Framework/Application/SlateApplication.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "Layout/Children.h"
#include "Misc/AutomationTest.h"
#include "Widgets/SWindow.h"

#if WITH_DEV_AUTOMATION_TESTS
namespace ck_tests_ui_menu_session
{
    auto FindCommand(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTypeAsString() == TEXT("SMenuEntryButton")) { return InRoot; }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SWidget> Found = FindCommand(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid()) { return Found; }
        }
        return {};
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiMenuSession_StandaloneLifetime,
    "Ck.UiAuthoring.Menus.StandaloneSessionLifetime",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiMenuSession_StandaloneLifetime::RunTest(const FString&) -> bool
{
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Menu session test requires Slate.")); return false; }
    FSlateApplication& Slate = FSlateApplication::Get();
    TSharedPtr<FCkUiMenuSession> Session = MakeShared<FCkUiMenuSession>();
    int32 Calls = 0;
    bool CanDispatch = true;
    FCkUiMenuSession::FEntry Entry;
    Entry.Key = TEXT("run");
    Entry.Label = FText::FromString(TEXT("Run"));
    Entry.Action = FSimpleDelegate::CreateLambda([&Calls] { ++Calls; });
    const auto Configure = [&Session, &Entry, &CanDispatch]()
    {
        Session->Configure({Entry}, true, TAttribute<bool>::CreateLambda([&CanDispatch] { return CanDispatch; }));
    };
    Configure();
    const TSharedRef<SWidget> FirstContent = Session->BuildMenu();
    struct FWindowScope
    {
        FSlateApplication& Slate;
        TSharedRef<SWindow> Window;
        ~FWindowScope() { Slate.DestroyWindowImmediately(Window); }
    } Scope{Slate, SNew(SWindow).ClientSize(FVector2D(260, 160)).CreateTitleBar(false)[FirstContent]};
    Slate.AddWindow(Scope.Window, true);
    const auto Tick = [&Slate]() { Slate.PumpMessages(); Slate.Tick(); Slate.Tick(); };
    Tick();
    const TSharedPtr<SWidget> FirstCommand = ck_tests_ui_menu_session::FindCommand(FirstContent);
    if (!TestTrue(TEXT("A session builds a native command without a menu-button host"), FirstCommand.IsValid())) { return false; }
    const auto Activate = [&Slate](const TSharedRef<SWidget>& InCommand)
    {
        Slate.SetUserFocus(0, InCommand, EFocusCause::SetDirectly);
        const FKeyEvent Key(EKeys::SpaceBar, FModifierKeysState{}, 0, false, 0, 0);
        Slate.ProcessKeyDownEvent(Key);
        Slate.ProcessKeyUpEvent(Key);
    };
    Activate(FirstCommand.ToSharedRef());
    TestEqual(TEXT("Standalone native command dispatches once"), Calls, 1);
    CanDispatch = false;
    Activate(FirstCommand.ToSharedRef());
    TestEqual(TEXT("Live event gate prevents standalone dispatch"), Calls, 1);
    CanDispatch = true;
    Configure();
    Activate(FirstCommand.ToSharedRef());
    TestEqual(TEXT("Old snapshot cannot dispatch after non-eventful publication"), Calls, 1);
    const TSharedRef<SWidget> CurrentContent = Session->BuildMenu();
    Scope.Window->SetContent(CurrentContent);
    Tick();
    const TSharedPtr<SWidget> CurrentCommand = ck_tests_ui_menu_session::FindCommand(CurrentContent);
    if (!TestTrue(TEXT("New snapshot builds a native command"), CurrentCommand.IsValid())) { return false; }
    Slate.SetUserFocus(0, CurrentCommand, EFocusCause::SetDirectly);
    if (!TestTrue(TEXT("Current session command owns focus before deactivation"), Slate.GetUserFocusedWidget(0) == CurrentCommand)) { return false; }
    Session->Deactivate();
    TestTrue(TEXT("Deactivation clears owned content focus"), Slate.GetUserFocusedWidget(0) != CurrentCommand);
    TestFalse(TEXT("Deactivated session is disabled"), Session->IsEnabled());
    const TWeakPtr<FCkUiMenuSession> WeakSession = Session;
    Session.Reset();
    TestFalse(TEXT("Held native content and snapshots do not retain the session"), WeakSession.IsValid());
    Activate(CurrentCommand.ToSharedRef());
    TestEqual(TEXT("Held native content cannot dispatch after session release"), Calls, 1);
    return true;
}
#endif // WITH_DEV_AUTOMATION_TESTS
