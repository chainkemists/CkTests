#include "CkSlateLayout/SCkUiMenuButton.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Framework/Application/SlateApplication.h"
#include "Framework/Application/SlateUser.h"
#include "HAL/PlatformProcess.h"
#include "Input/Events.h"
#include "Input/PopupMethodReply.h"
#include "InputCoreTypes.h"
#include "Layout/Children.h"
#include "Layout/WidgetPath.h"
#include "Misc/AutomationTest.h"
#include "Styling/CoreStyle.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/SOverlay.h"
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"

#if WITH_DEV_AUTOMATION_TESTS
namespace ck_tests_ui_menus_nested
{
    class SCurrentWindowPopupHost final : public SBox
    {
    public:
        virtual auto OnQueryPopupMethod() const -> FPopupMethodReply override
        { return FPopupMethodReply::UseMethod(EPopupMethod::UseCurrentWindow); }
    };

    auto Markup() -> FString
    {
        return TEXT("<ui version=\"1\"><menu id=\"actions\"><submenu key=\"more\" label=\"More\" menu=\"more-actions\"/></menu><menu id=\"more-actions\"><menu-item key=\"extra\" label=\"Extra\" action=\"extra\"/></menu><region name=\"main\"><column id=\"root\"><menu-button id=\"actions-button\" menu=\"actions\" label=\"Actions\"/></column></region></ui>");
    }

    auto Tick(FSlateApplication& InSlate) -> void
    {
        InSlate.PumpMessages();
        InSlate.Tick();
        InSlate.Tick();
    }

    auto Key(const FKey InKey) -> FKeyEvent
    { return FKeyEvent(InKey, FModifierKeysState{}, 0, false, 0, 0); }

    auto FindText(const TSharedRef<SWidget>& InRoot, const FString& InText) -> TSharedPtr<STextBlock>
    {
        if (InRoot->GetTypeAsString() == TEXT("STextBlock"))
        {
            const TSharedRef<STextBlock> Text = StaticCastSharedRef<STextBlock>(InRoot);
            if (Text->GetText().ToString() == InText) { return Text; }
        }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<STextBlock> Found = FindText(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InText); Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto ContainsText(const TSharedRef<SWidget>& InRoot, const FString& InText) -> bool
    { return FindText(InRoot, InText).IsValid(); }

    auto FindMenuEntry(const TSharedRef<SWidget>& InRoot, const FString& InLabel) -> TSharedPtr<SWidget>
    {
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SWidget> Found = FindMenuEntry(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InLabel); Found.IsValid()) { return Found; }
        }
        if (InRoot->GetTypeAsString() == TEXT("SMenuEntryBlock") && ContainsText(InRoot, InLabel)) { return InRoot; }
        return {};
    }

    auto FindButton(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SButton>
    {
        if (InRoot->GetTypeAsString() == TEXT("SButton") || InRoot->GetTypeAsString() == TEXT("SMenuEntryButton")) { return StaticCastSharedRef<SButton>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SButton> Found = FindButton(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto FindVisibleMenuWindow(FSlateApplication& InSlate, const FString& InLabel) -> TSharedPtr<SWindow>
    {
        TArray<TSharedRef<SWindow>> Windows;
        InSlate.GetAllVisibleWindowsOrdered(Windows);
        for (const TSharedRef<SWindow>& Window : Windows)
        {
            if (FindMenuEntry(Window, InLabel).IsValid()) { return Window; }
        }
        return {};
    }

    auto MoveToText(FSlateApplication& InSlate, const TSharedRef<SWindow>& InWindow, const TSharedRef<STextBlock>& InText) -> void
    {
        if (!InWindow->GetNativeWindow().IsValid()) { return; }
        const FGeometry Geometry = InText->GetCachedGeometry();
        const FVector2D Position = Geometry.LocalToAbsolute(Geometry.GetLocalSize() * 0.5f);
        const TSet<FKey> MoveButtons;
        const FPointerEvent Move(0, FSlateApplication::CursorPointerIndex, Position, Position, MoveButtons, EKeys::Invalid, 0.0f, FModifierKeysState{});
        InSlate.SetCursorPos(Position);
        InSlate.ProcessMouseMoveEvent(Move);
        Tick(InSlate);
    }

    auto WaitForVisibleMenuWindow(FSlateApplication& InSlate, const FString& InLabel) -> TSharedPtr<SWindow>
    {
        constexpr int32 Attempts = 100;
        for (int32 Attempt = 0; Attempt < Attempts; ++Attempt)
        {
            if (const TSharedPtr<SWindow> Window = FindVisibleMenuWindow(InSlate, InLabel); Window.IsValid())
            {
                const TSharedPtr<STextBlock> Label = FindText(Window.ToSharedRef(), InLabel);
                const FVector2D Size = Label.IsValid() ? Label->GetCachedGeometry().GetLocalSize() : FVector2D::ZeroVector;
                FWidgetPath Path;
                if (Size.X > 0.0f && Size.Y > 0.0f
                    && InSlate.GeneratePathToWidgetUnchecked(Label.ToSharedRef(), Path)) { return Window; }
            }
            FPlatformProcess::Sleep(0.01f);
            Tick(InSlate);
        }
        return {};
    }

    auto ClickText(FSlateApplication& InSlate, const TSharedRef<SWindow>& InWindow, const TSharedRef<STextBlock>& InText) -> bool
    {
        if (!InWindow->GetNativeWindow().IsValid()) { return false; }
        const FGeometry Geometry = InText->GetCachedGeometry();
        const FVector2D Position = Geometry.LocalToAbsolute(Geometry.GetLocalSize() * 0.5f);
        const TSet<FKey> MoveButtons;
        const FPointerEvent Move(0, FSlateApplication::CursorPointerIndex, Position, Position, MoveButtons, EKeys::Invalid, 0.0f, FModifierKeysState{});
        const TSet<FKey> DownButtons{EKeys::LeftMouseButton};
        const FPointerEvent Down(0, FSlateApplication::CursorPointerIndex, Position, Position, DownButtons, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        const TSet<FKey> UpButtons;
        const FPointerEvent Up(0, FSlateApplication::CursorPointerIndex, Position, Position, UpButtons, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        InSlate.SetCursorPos(Position);
        InSlate.ProcessMouseMoveEvent(Move);
        const bool DownHandled = InSlate.ProcessMouseButtonDownEvent(InWindow->GetNativeWindow(), Down);
        const bool UpHandled = InSlate.ProcessMouseButtonUpEvent(Up);
        Tick(InSlate);
        return DownHandled && UpHandled;
    }

    struct FWindowScope final
    {
        explicit FWindowScope(FSlateApplication& InSlate) : Slate(InSlate), PreviousCursor(InSlate.GetCursorPos()) {}
        ~FWindowScope() { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } Slate.SetCursorPos(PreviousCursor); }
        FSlateApplication& Slate;
        FVector2D PreviousCursor;
        TSharedPtr<SWindow> Window;
    };

    struct FFixture final
    {
        explicit FFixture(const bool InUseCurrentWindow)
            : Slate(FSlateApplication::Get()), UseCurrentWindow(InUseCurrentWindow), Scope(Slate) {}

        auto Load() -> bool
        {
            FCkUiView::FActions Actions;
            Actions.Add(TEXT("extra"), FSimpleDelegate::CreateLambda([this]
            {
                ++ExtraCalls;
                if (ResetOnExtra) { View.Reset(); }
            }));
            View = FCkUiView::Create({}, MoveTemp(Actions), {}, FCoreStyle::GetDefaultFontStyle(TEXT("Regular"), 12));
            Region = View->GetRegion(TEXT("main"));
            External = SNew(SButton).IsFocusable(true);
            const TSharedRef<SWidget> Host = UseCurrentWindow
                ? StaticCastSharedRef<SWidget>(SNew(SCurrentWindowPopupHost)[Region.ToSharedRef()])
                : Region.ToSharedRef();
            Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D(360.0f, 160.0f))
                .CreateTitleBar(false).HasCloseButton(false)
                [SNew(SOverlay) + SOverlay::Slot()[Host] + SOverlay::Slot().HAlign(HAlign_Right).VAlign(VAlign_Bottom)[External.ToSharedRef()]];
            Slate.AddWindow(Scope.Window.ToSharedRef(), true);
            if (!View->TryReload(Markup(), TEXT(".root { padding: 2px; }"), TEXT("UiMenusNestedInitial")).Succeeded) { return false; }
            Tick(Slate);
            Menu = View->GetMenuButton(TEXT("actions-button"));
            AnchorButton = Menu.IsValid() ? FindButton(Menu.ToSharedRef()) : nullptr;
            return Menu.IsValid() && AnchorButton.IsValid() && External.IsValid();
        }

        auto OpenRoot() -> bool
        {
            if (Menu->IsOpen())
            {
                RootWindow = WaitForVisibleMenuWindow(Slate, TEXT("More"));
                return RootWindow.IsValid() && FindMenuEntry(RootWindow.ToSharedRef(), TEXT("More")).IsValid();
            }
            Slate.SetUserFocus(0, AnchorButton, EFocusCause::SetDirectly);
            if (Slate.GetUserFocusedWidget(0) != AnchorButton) { return false; }
            const bool DownHandled = Slate.ProcessKeyDownEvent(Key(EKeys::SpaceBar));
            const bool UpHandled = Slate.ProcessKeyUpEvent(Key(EKeys::SpaceBar));
            Tick(Slate);
            RootWindow = WaitForVisibleMenuWindow(Slate, TEXT("More"));
            return DownHandled && UpHandled && Menu->IsOpen() && RootWindow.IsValid()
                && FindMenuEntry(RootWindow.ToSharedRef(), TEXT("More")).IsValid();
        }

        auto OpenNested() -> bool
        {
            if (!OpenRoot()) { return false; }
            const TSharedPtr<STextBlock> MoreText = FindText(RootWindow.ToSharedRef(), TEXT("More"));
            if (!MoreText.IsValid()) { return false; }
            MoveToText(Slate, RootWindow.ToSharedRef(), MoreText.ToSharedRef());
            NestedWindow = WaitForVisibleMenuWindow(Slate, TEXT("Extra"));
            return NestedWindow.IsValid() && FindMenuEntry(NestedWindow.ToSharedRef(), TEXT("Extra")).IsValid();
        }

        FSlateApplication& Slate;
        bool UseCurrentWindow = false;
        bool ResetOnExtra = false;
        int32 ExtraCalls = 0;
        TSharedPtr<FCkUiView> View;
        TSharedPtr<SWidget> Region;
        TSharedPtr<SCkUiMenuButton> Menu;
        TSharedPtr<SButton> AnchorButton;
        TSharedPtr<SButton> External;
        TSharedPtr<SWindow> RootWindow;
        TSharedPtr<SWindow> NestedWindow;
        FWindowScope Scope;
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiMenus_NestedRuntime,
    "Ck.UiAuthoring.Menus.NestedNativeRuntime",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiMenus_NestedRuntime::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_menus_nested;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Nested menu runtime test requires Slate.")); return false; }

    for (const bool UseCurrentWindow : {false, true})
    {
        FFixture Fixture(UseCurrentWindow);
        if (!TestTrue(UseCurrentWindow ? TEXT("Current-window nested menu fixture loads") : TEXT("New-window nested menu fixture loads"), Fixture.Load())
            || !TestTrue(TEXT("Native SComboButton internal SButton Space down/up opens the root menu"), Fixture.OpenRoot())) { return false; }

        const TSharedPtr<SWidget> MoreEntry = FindMenuEntry(Fixture.RootWindow.ToSharedRef(), TEXT("More"));
        TestTrue(TEXT("Root popup exposes an actual SMenuEntryBlock for More"), MoreEntry.IsValid() && MoreEntry->GetTypeAsString() == TEXT("SMenuEntryBlock"));
        if (!TestTrue(TEXT("Pointer routing opens More's authored submenu"), Fixture.OpenNested())) { return false; }

        const TSharedPtr<SWidget> ExtraEntry = FindMenuEntry(Fixture.NestedWindow.ToSharedRef(), TEXT("Extra"));
        const TSharedPtr<STextBlock> ExtraText = FindText(Fixture.NestedWindow.ToSharedRef(), TEXT("Extra"));
        if (!TestTrue(TEXT("Nested popup exposes an actual SMenuEntryBlock for Extra"), ExtraEntry.IsValid() && ExtraEntry->GetTypeAsString() == TEXT("SMenuEntryBlock"))
            || !TestTrue(TEXT("Nested menu renders the Extra action leaf"), ExtraText.IsValid())) { return false; }
        TestTrue(TEXT("Slate routes a real pointer click to nested Extra"), ClickText(Fixture.Slate, Fixture.NestedWindow.ToSharedRef(), ExtraText.ToSharedRef()));
        TestEqual(TEXT("Nested Extra action dispatches exactly once"), Fixture.ExtraCalls, 1);

        if (!TestTrue(TEXT("Native anchor reopens More after nested action dispatch"), Fixture.OpenNested())) { return false; }
        const TSharedPtr<SWidget> HeldEntry = FindMenuEntry(Fixture.NestedWindow.ToSharedRef(), TEXT("Extra"));
        const TSharedPtr<SWidget> HeldFocusedLeaf = HeldEntry.IsValid() ? FindButton(HeldEntry.ToSharedRef()) : nullptr;
        if (!TestTrue(TEXT("Nested Extra menu leaf is available for focus cleanup"), HeldFocusedLeaf.IsValid())) { return false; }
        Fixture.Slate.SetUserFocus(0, HeldFocusedLeaf.ToSharedRef(), EFocusCause::SetDirectly);
        if (!TestTrue(TEXT("Slate focuses the actual nested command button"), Fixture.Slate.GetUserFocusedWidget(0) == HeldFocusedLeaf)) { return false; }
        FWidgetPath FocusPath;
        if (!TestTrue(TEXT("Focused nested menu leaf is mounted before owner release"), Fixture.Slate.GeneratePathToWidgetUnchecked(HeldFocusedLeaf.ToSharedRef(), FocusPath))) { return false; }

        const TSharedRef<FSlateVirtualUserHandle> VirtualUser = Fixture.Slate.FindOrCreateVirtualUser(193);
        const int32 VirtualUserIndex = VirtualUser->GetUserIndex();
        Fixture.Slate.SetUserFocus(VirtualUserIndex, Fixture.External.ToSharedRef(), EFocusCause::SetDirectly);
        if (!TestTrue(TEXT("External virtual-user focus is established before owner release"), Fixture.Slate.GetUserFocusedWidget(VirtualUserIndex) == Fixture.External)) { return false; }
        const TSharedPtr<SCkUiMenuButton> HeldMenu = Fixture.Menu;
        Fixture.View.Reset();
        Tick(Fixture.Slate);
        TestFalse(TEXT("Owner release closes the root SComboButton popup"), HeldMenu->IsOpen());
        TestFalse(TEXT("Owner release closes every visible nested menu popup"), FindVisibleMenuWindow(Fixture.Slate, TEXT("Extra")).IsValid());
        TestTrue(TEXT("Owner release clears stale nested menu focus"), Fixture.Slate.GetUserFocusedWidget(0) != HeldFocusedLeaf);
        TestTrue(TEXT("Owner release preserves unrelated virtual-user focus"), Fixture.Slate.GetUserFocusedWidget(VirtualUserIndex) == Fixture.External);
        Fixture.Slate.ClearUserFocus(0, EFocusCause::SetDirectly);
        Fixture.Slate.ClearUserFocus(VirtualUserIndex, EFocusCause::SetDirectly);
    }
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiMenus_NestedCallbackRelease,
    "Ck.UiAuthoring.Menus.NestedCallbackRelease",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiMenus_NestedCallbackRelease::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_menus_nested;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Nested callback release test requires Slate.")); return false; }

    FFixture Fixture(false);
    Fixture.ResetOnExtra = true;
    if (!TestTrue(TEXT("Nested callback release fixture loads"), Fixture.Load())
        || !TestTrue(TEXT("Nested callback release opens More and Extra"), Fixture.OpenNested())) { return false; }
    const TSharedPtr<SCkUiMenuButton> HeldMenu = Fixture.Menu;
    const TSharedPtr<STextBlock> ExtraText = FindText(Fixture.NestedWindow.ToSharedRef(), TEXT("Extra"));
    if (!TestTrue(TEXT("Nested callback release exposes the rendered Extra leaf"), ExtraText.IsValid())) { return false; }
    TestTrue(TEXT("Nested Extra callback receives the routed pointer click"), ClickText(Fixture.Slate, Fixture.NestedWindow.ToSharedRef(), ExtraText.ToSharedRef()));
    TestTrue(TEXT("Nested callback can release its owner during dispatch"), Fixture.ExtraCalls == 1 && !Fixture.View.IsValid());
    TestFalse(TEXT("Callback owner release closes the held root popup"), HeldMenu->IsOpen());
    TestFalse(TEXT("Callback owner release leaves no visible nested popup"), FindVisibleMenuWindow(Fixture.Slate, TEXT("Extra")).IsValid());
    return true;
}
#endif // WITH_DEV_AUTOMATION_TESTS
