#include "CkSlateLayout/SCkUiSurface.h"

#include "Framework/Application/SlateApplication.h"
#include "Framework/Application/SlateUser.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "Layout/Children.h"
#include "Layout/WidgetPath.h"
#include "Misc/AutomationTest.h"
#include "Styling/CoreStyle.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/SOverlay.h"
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_tabs_users
{
    auto Markup() -> FString
    {
        return TEXT("<ui version=\"1\"><region name=\"main\"><tabs id=\"tabs\" value-bind=\"active\" changed=\"activate\"><tab id=\"first\" key=\"first\" label=\"First\" enabled-bind=\"first-enabled\"><text id=\"first-body\">First panel</text></tab><tab id=\"second\" key=\"second\" label=\"Second\" enabled-bind=\"second-enabled\"><text id=\"second-body\">Second panel</text></tab><tab id=\"third\" key=\"third\" label=\"Third\" enabled-bind=\"third-enabled\"><text id=\"third-body\">Third panel</text></tab></tabs></region></ui>");
    }

    auto ContainsText(const TSharedRef<SWidget>& InRoot, const FString& InText) -> bool
    {
        if (InRoot->GetTypeAsString() == TEXT("STextBlock") && StaticCastSharedRef<STextBlock>(InRoot)->GetText().ToString() == InText) { return true; }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (ContainsText(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InText)) { return true; }
        }
        return false;
    }

    auto FindHeader(const TSharedRef<SWidget>& InRoot, const FString& InLabel) -> TSharedPtr<SButton>
    {
        if (InRoot->GetTypeAsString() == TEXT("SButton") && ContainsText(InRoot, InLabel)) { return StaticCastSharedRef<SButton>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SButton> Found = FindHeader(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InLabel); Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto Tick(FSlateApplication& InSlate) -> void { InSlate.PumpMessages(); InSlate.Tick(); InSlate.Tick(); }
    auto Key(const FKey InKey, const int32 InUser) -> FKeyEvent { return FKeyEvent(InKey, FModifierKeysState{}, InUser, false, 0, 0); }

    struct FWindowScope final
    {
        explicit FWindowScope(FSlateApplication& InSlate) : Slate(InSlate) {}
        ~FWindowScope() { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } }
        FSlateApplication& Slate;
        TSharedPtr<SWindow> Window;
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiTabsUsers,
    "Ck.UiAuthoring.Tabs.MultiUserFocus",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiTabsUsers::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_tabs_users;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Tabs users test requires Slate.")); return false; }

    FString Active = TEXT("second");
    bool FirstEnabled = true;
    bool SecondEnabled = true;
    bool ThirdEnabled = true;
    int32 ActivationCalls = 0;
    auto Data = FCkUiView::FDataBindings{};
    Data.String.Add(TEXT("active"), TAttribute<FString>::CreateLambda([&Active]() { return Active; }));
    Data.Visibility.Add(TEXT("first-enabled"), TAttribute<bool>::CreateLambda([&FirstEnabled]() { return FirstEnabled; }));
    Data.Visibility.Add(TEXT("second-enabled"), TAttribute<bool>::CreateLambda([&SecondEnabled]() { return SecondEnabled; }));
    Data.Visibility.Add(TEXT("third-enabled"), TAttribute<bool>::CreateLambda([&ThirdEnabled]() { return ThirdEnabled; }));
    Data.StringChanged.Add(TEXT("activate"), FCkUiOnStringChanged::CreateLambda([&Active, &ActivationCalls](const FString& InKey)
    {
        ++ActivationCalls;
        Active = InKey;
    }));

    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, {}, {}, FCoreStyle::GetDefaultFontStyle(TEXT("Regular"), 12), MoveTemp(Data));
    FSlateApplication& Slate = FSlateApplication::Get();
    FWindowScope Scope{Slate};
    const TSharedRef<SButton> External = SNew(SButton).IsFocusable(true);
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{440.0f, 220.0f}).CreateTitleBar(false).HasCloseButton(false)
        [SNew(SOverlay) + SOverlay::Slot()[View->GetRegion(TEXT("main"))] + SOverlay::Slot().HAlign(HAlign_Right).VAlign(VAlign_Bottom)[External]];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);
    if (!TestTrue(TEXT("Three authored tabs load"), View->TryReload(Markup(), TEXT(""), TEXT("UiTabsUsers")).Succeeded)) { return false; }
    Tick(Slate);

    const TSharedPtr<SButton> First = FindHeader(View->GetRegion(TEXT("main")), TEXT("First"));
    const TSharedPtr<SButton> Second = FindHeader(View->GetRegion(TEXT("main")), TEXT("Second"));
    const TSharedPtr<SButton> Third = FindHeader(View->GetRegion(TEXT("main")), TEXT("Third"));
    if (!TestTrue(TEXT("Authored tabs expose all three native enabled headers"), First.IsValid() && Second.IsValid() && Third.IsValid()
        && First->IsEnabled() && Second->IsEnabled() && Third->IsEnabled())) { return false; }

    const TSharedRef<FSlateVirtualUserHandle> VirtualHandle = Slate.FindOrCreateVirtualUser(127);
    const int32 VirtualUser = VirtualHandle->GetUserIndex();
    Slate.SetUserFocus(0, External, EFocusCause::SetDirectly);
    Slate.SetUserFocus(VirtualUser, First.ToSharedRef(), EFocusCause::SetDirectly);
    Tick(Slate);
    if (!TestTrue(TEXT("Initial Slate users own independent focus"), Slate.GetUserFocusedWidget(0) == External && Slate.GetUserFocusedWidget(VirtualUser) == First)) { return false; }

    const int32 CallsBeforeNavigation = ActivationCalls;
    TestTrue(TEXT("Virtual Right reaches the native tab header"), Slate.ProcessKeyDownEvent(Key(EKeys::Right, VirtualUser)));
    Tick(Slate);
    TestTrue(TEXT("Virtual Right focuses Second without changing the model"), Slate.GetUserFocusedWidget(VirtualUser) == Second
        && Slate.GetUserFocusedWidget(0) == External && Active == TEXT("second") && ActivationCalls == CallsBeforeNavigation);
    TestTrue(TEXT("Virtual Home reaches the first header"), Slate.ProcessKeyDownEvent(Key(EKeys::Home, VirtualUser)));
    Tick(Slate);
    TestTrue(TEXT("Virtual Home preserves owner focus and model"), Slate.GetUserFocusedWidget(VirtualUser) == First
        && Slate.GetUserFocusedWidget(0) == External && Active == TEXT("second") && ActivationCalls == CallsBeforeNavigation);
    TestTrue(TEXT("Virtual End reaches the last header"), Slate.ProcessKeyDownEvent(Key(EKeys::End, VirtualUser)));
    Tick(Slate);
    TestTrue(TEXT("Virtual End preserves owner focus and model"), Slate.GetUserFocusedWidget(VirtualUser) == Third
        && Slate.GetUserFocusedWidget(0) == External && Active == TEXT("second") && ActivationCalls == CallsBeforeNavigation);

    const TSharedRef<FSlateVirtualUserHandle> SecondVirtualHandle = Slate.FindOrCreateVirtualUser(128);
    const int32 SecondVirtualUser = SecondVirtualHandle->GetUserIndex();
    Slate.SetUserFocus(SecondVirtualUser, Third.ToSharedRef(), EFocusCause::SetDirectly);
    Tick(Slate);
    if (!TestTrue(TEXT("Both virtual users focus Third before its header disables"), Slate.GetUserFocusedWidget(VirtualUser) == Third
        && Slate.GetUserFocusedWidget(SecondVirtualUser) == Third && Slate.GetUserFocusedWidget(0) == External
        && Active == TEXT("second") && ActivationCalls == CallsBeforeNavigation)) { return false; }

    ThirdEnabled = false;
    Tick(Slate);
    TestTrue(TEXT("Disabling Third moves both virtual users to the enabled selected header"), !Third->IsEnabled()
        && Slate.GetUserFocusedWidget(VirtualUser) == Second && Slate.GetUserFocusedWidget(SecondVirtualUser) == Second
        && Slate.GetUserFocusedWidget(0) == External && Active == TEXT("second") && ActivationCalls == CallsBeforeNavigation);

    SecondEnabled = false;
    Tick(Slate);
    TestTrue(TEXT("Disabling Second moves both virtual users to the first enabled header"), !Second->IsEnabled()
        && Slate.GetUserFocusedWidget(VirtualUser) == First && Slate.GetUserFocusedWidget(SecondVirtualUser) == First
        && Slate.GetUserFocusedWidget(0) == External && Active == TEXT("second") && ActivationCalls == CallsBeforeNavigation);

    FirstEnabled = false;
    Tick(Slate);
    TestTrue(TEXT("Disabling all headers clears both virtual users' owned focus"), !First->IsEnabled()
        && !Slate.GetUserFocusedWidget(VirtualUser).IsValid() && !Slate.GetUserFocusedWidget(SecondVirtualUser).IsValid()
        && Slate.GetUserFocusedWidget(0) == External && Active == TEXT("second") && ActivationCalls == CallsBeforeNavigation);

    FirstEnabled = true;
    SecondEnabled = true;
    ThirdEnabled = true;
    Tick(Slate);
    Slate.SetUserFocus(VirtualUser, Second.ToSharedRef(), EFocusCause::SetDirectly);
    if (!TestTrue(TEXT("Virtual user can refocus a retained header before reload"), Slate.GetUserFocusedWidget(VirtualUser) == Second)) { return false; }
    FWidgetPath PreviousMountedPath;
    if (!TestTrue(TEXT("Focused retained header has a mounted pre-reload path"), Slate.GeneratePathToWidgetUnchecked(Second.ToSharedRef(), PreviousMountedPath))) { return false; }
    if (!TestTrue(TEXT("Compatible three-tab reload succeeds"), View->TryReload(Markup(), TEXT(""), TEXT("UiTabsUsersCompatible")).Succeeded)) { return false; }
    Tick(Slate);
    FWidgetPath CurrentMountedPath;
    if (!TestTrue(TEXT("Focused retained header has a current mounted path"), Slate.GeneratePathToWidgetUnchecked(Second.ToSharedRef(), CurrentMountedPath))) { return false; }
    const TSharedPtr<FSlateUser> User = Slate.GetUser(VirtualUser);
    if (!TestTrue(TEXT("Virtual Slate user remains available after reload"), User.IsValid())) { return false; }
    TestTrue(TEXT("Compatible reload retains focused header identity and external owner focus"), FindHeader(View->GetRegion(TEXT("main")), TEXT("Second")) == Second
        && Slate.GetUserFocusedWidget(VirtualUser) == Second && Slate.GetUserFocusedWidget(0) == External);
    for (int32 CurrentIndex = 0; CurrentIndex < CurrentMountedPath.Widgets.Num(); ++CurrentIndex)
    {
        TestTrue(TEXT("Every current header ancestor belongs to the virtual focus path"), User->IsWidgetInFocusPath(CurrentMountedPath.Widgets[CurrentIndex].Widget));
    }
    for (int32 PreviousIndex = 0; PreviousIndex < PreviousMountedPath.Widgets.Num(); ++PreviousIndex)
    {
        const TSharedRef<SWidget> Previous = PreviousMountedPath.Widgets[PreviousIndex].Widget;
        bool StillMounted = false;
        for (int32 CurrentIndex = 0; CurrentIndex < CurrentMountedPath.Widgets.Num(); ++CurrentIndex)
        {
            StillMounted |= CurrentMountedPath.Widgets[CurrentIndex].Widget == Previous;
        }
        if (!StillMounted)
        {
            TestFalse(TEXT("Detached header ancestor is absent from the virtual focus path"), User->IsWidgetInFocusPath(Previous));
        }
    }

    Slate.ClearUserFocus(0, EFocusCause::SetDirectly);
    Slate.ClearUserFocus(VirtualUser, EFocusCause::SetDirectly);
    Slate.ClearUserFocus(SecondVirtualUser, EFocusCause::SetDirectly);
    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
