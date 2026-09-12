#include "CkSlateLayout/SCkUiMenuButton.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Framework/Application/SlateApplication.h"
#include "Input/Events.h"
#include "Input/PopupMethodReply.h"
#include "InputCoreTypes.h"
#include "Layout/Children.h"
#include "Misc/AutomationTest.h"
#include "Styling/CoreStyle.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"

#if WITH_DEV_AUTOMATION_TESTS
namespace ck_tests_ui_menus
{
    class SCurrentWindowPopupHost final : public SBox
    {
    public:
        virtual auto OnQueryPopupMethod() const -> FPopupMethodReply override
        { return FPopupMethodReply::UseMethod(EPopupMethod::UseCurrentWindow); }
    };

    auto Markup(const bool InUseBoundRunLabel = false, const bool InUseBadAction = false) -> FString
    {
        const FString RunLabel = InUseBoundRunLabel ? TEXT("label-bind=\"run-label\"") : TEXT("label=\"Run\"");
        const FString RunAction = InUseBadAction ? TEXT("missing-action") : TEXT("run");
        return FString::Printf(TEXT("<ui version=\"1\"><menu id=\"actions\"><menu-item key=\"run\" %s action=\"%s\" enabled-bind=\"can-run\"/><separator key=\"sep\"/><submenu key=\"more\" label=\"More\" menu=\"extras\"/></menu><menu id=\"extras\"><menu-item key=\"extra\" label=\"Extra\" action=\"extra\"/></menu><region name=\"main\"><column id=\"root\"><menu-button id=\"actions-button\" menu=\"actions\" label=\"Actions\"/></column></region></ui>"), *RunLabel, *RunAction);
    }

    auto Tick(FSlateApplication& InSlate) -> void
    {
        InSlate.PumpMessages();
        InSlate.Tick();
        InSlate.Tick();
    }

    auto Key(const FKey InKey) -> FKeyEvent
    { return FKeyEvent(InKey, FModifierKeysState{}, 0, false, 0, 0); }

    auto ContainsText(const TSharedRef<SWidget>& InRoot, const FString& InText) -> bool
    {
        if (InRoot->GetTypeAsString() == TEXT("STextBlock")
            && StaticCastSharedRef<STextBlock>(InRoot)->GetText().ToString() == InText) { return true; }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (ContainsText(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InText)) { return true; }
        }
        return false;
    }

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

    auto FindMenuEntry(const TSharedRef<SWidget>& InRoot, const FString& InLabel) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTypeAsString() == TEXT("SMenuEntryBlock") && ContainsText(InRoot, InLabel)) { return InRoot; }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SWidget> Found = FindMenuEntry(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InLabel); Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto FindButton(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SButton>
    {
        if (InRoot->GetTypeAsString() == TEXT("SButton")) { return StaticCastSharedRef<SButton>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SButton> Found = FindButton(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto FindPopupWindow(FSlateApplication& InSlate, const FString& InText) -> TSharedPtr<SWindow>
    {
        TArray<TSharedRef<SWindow>> Windows;
        InSlate.GetAllVisibleWindowsOrdered(Windows);
        for (const TSharedRef<SWindow>& Window : Windows)
        {
            if (FindText(Window, InText).IsValid() && FindMenuEntry(Window, InText).IsValid()) { return Window; }
        }
        return {};
    }

    auto ClickText(FSlateApplication& InSlate, const TSharedRef<SWindow>& InWindow, const TSharedRef<STextBlock>& InText) -> bool
    {
        if (!InWindow->GetNativeWindow().IsValid()) { return false; }
        const FGeometry Geometry = InText->GetCachedGeometry();
        const FVector2D Position = Geometry.LocalToAbsolute(Geometry.GetLocalSize() * 0.5f);
        const TSet<FKey> MoveButtons;
        const FPointerEvent Move(0, FSlateApplication::CursorPointerIndex, Position, Position, MoveButtons,
            EKeys::Invalid, 0.0f, FModifierKeysState{});
        const TSet<FKey> DownButtons{EKeys::LeftMouseButton};
        const FPointerEvent Down(0, FSlateApplication::CursorPointerIndex, Position, Position, DownButtons,
            EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        const TSet<FKey> UpButtons;
        const FPointerEvent Up(0, FSlateApplication::CursorPointerIndex, Position, Position, UpButtons,
            EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        InSlate.ProcessMouseMoveEvent(Move);
        const bool DownHandled = InSlate.ProcessMouseButtonDownEvent(InWindow->GetNativeWindow(), Down);
        const bool UpHandled = InSlate.ProcessMouseButtonUpEvent(Up);
        Tick(InSlate);
        return DownHandled && UpHandled;
    }

    struct FWindowScope final
    {
        explicit FWindowScope(FSlateApplication& InSlate) : Slate(InSlate) {}
        ~FWindowScope() { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } }
        FSlateApplication& Slate;
        TSharedPtr<SWindow> Window;
    };

    struct FFixture final
    {
        explicit FFixture(const bool InUseCurrentWindow)
            : Slate(FSlateApplication::Get()), UseCurrentWindow(InUseCurrentWindow), Scope(Slate) {}

        auto Load() -> bool
        {
            FCkUiView::FDataBindings Data;
            Data.Text.Add(TEXT("run-label"), TAttribute<FText>::CreateLambda([this] { return FText::FromString(RunLabel); }));
            Data.Visibility.Add(TEXT("can-run"), TAttribute<bool>::CreateLambda([this] { return CanRun; }));
            FCkUiView::FActions Actions;
            Actions.Add(TEXT("run"), FSimpleDelegate::CreateLambda([this] { ++RunCalls; }));
            Actions.Add(TEXT("extra"), FSimpleDelegate::CreateLambda([this] { ++ExtraCalls; }));
            View = FCkUiView::Create({}, MoveTemp(Actions), {}, FCoreStyle::GetDefaultFontStyle(TEXT("Regular"), 12), MoveTemp(Data));
            Region = View->GetRegion(TEXT("main"));
            const TSharedRef<SWidget> Host = UseCurrentWindow
                ? StaticCastSharedRef<SWidget>(SNew(SCurrentWindowPopupHost)[Region.ToSharedRef()])
                : Region.ToSharedRef();
            Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D(360.0f, 160.0f))
                .CreateTitleBar(false).HasCloseButton(false)[Host];
            Slate.AddWindow(Scope.Window.ToSharedRef(), true);
            if (!View->TryReload(Markup(true), TEXT(".root { padding: 2px; }"), TEXT("UiMenusInitial")).Succeeded) { return false; }
            Tick(Slate);
            Menu = View->GetMenuButton(TEXT("actions-button"));
            AnchorButton = Menu.IsValid() ? FindButton(Menu.ToSharedRef()) : nullptr;
            return Menu.IsValid() && AnchorButton.IsValid();
        }

        auto Open() -> bool
        {
            if (Menu->IsOpen())
            {
                PopupWindow = FindPopupWindow(Slate, RunLabel);
                return PopupWindow.IsValid() && FindMenuEntry(PopupWindow.ToSharedRef(), RunLabel).IsValid();
            }
            Slate.SetUserFocus(0, AnchorButton, EFocusCause::SetDirectly);
            if (Slate.GetUserFocusedWidget(0) != AnchorButton) { return false; }
            const bool DownHandled = Slate.ProcessKeyDownEvent(Key(EKeys::SpaceBar));
            const bool UpHandled = Slate.ProcessKeyUpEvent(Key(EKeys::SpaceBar));
            Tick(Slate);
            PopupWindow = FindPopupWindow(Slate, RunLabel);
            return DownHandled && UpHandled && Menu->IsOpen() && PopupWindow.IsValid() && FindMenuEntry(PopupWindow.ToSharedRef(), RunLabel).IsValid();
        }

        FSlateApplication& Slate;
        bool UseCurrentWindow = false;
        bool CanRun = true;
        FString RunLabel = TEXT("Run");
        int32 RunCalls = 0;
        int32 ExtraCalls = 0;
        TSharedPtr<FCkUiView> View;
        TSharedPtr<SWidget> Region;
        TSharedPtr<SCkUiMenuButton> Menu;
        TSharedPtr<SButton> AnchorButton;
        TSharedPtr<SWindow> PopupWindow;
        FWindowScope Scope;
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiMenus_Runtime,
    "Ck.UiAuthoring.Menus.NativeRuntime",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiMenus_Runtime::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_menus;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Menu runtime test requires Slate.")); return false; }

    for (const bool UseCurrentWindow : {false, true})
    {
        FFixture Fixture(UseCurrentWindow);
        if (!TestTrue(UseCurrentWindow ? TEXT("Current-window menu fixture loads") : TEXT("New-window menu fixture loads"), Fixture.Load())
            || !TestTrue(TEXT("Native SpaceBar opens the authored menu"), Fixture.Open())) { return false; }

        const TSharedPtr<STextBlock> Run = FindText(Fixture.PopupWindow.ToSharedRef(), Fixture.RunLabel);
        if (!TestTrue(TEXT("Opened popup exposes the rendered Run entry"), Run.IsValid())) { return false; }
        TestTrue(TEXT("Slate routes a real pointer click to the menu entry"), ClickText(Fixture.Slate, Fixture.PopupWindow.ToSharedRef(), Run.ToSharedRef()));
        TestEqual(TEXT("Pointer activation dispatches Run exactly once"), Fixture.RunCalls, 1);
        TestEqual(TEXT("Run does not dispatch the unrelated submenu action"), Fixture.ExtraCalls, 0);

        if (!TestTrue(TEXT("Native SpaceBar reopens the menu for disabled-entry routing"), Fixture.Open())) { return false; }
        Fixture.CanRun = false;
        Tick(Fixture.Slate);
        const TSharedPtr<STextBlock> DisabledRun = FindText(Fixture.PopupWindow.ToSharedRef(), Fixture.RunLabel);
        if (!TestTrue(TEXT("Disabled menu remains rendered for native Slate gating"), DisabledRun.IsValid())) { return false; }
        ClickText(Fixture.Slate, Fixture.PopupWindow.ToSharedRef(), DisabledRun.ToSharedRef());
        TestEqual(TEXT("Disabled Run entry cannot dispatch"), Fixture.RunCalls, 1);

        Fixture.Menu->ReleasePopup();
        Fixture.CanRun = true;
        Tick(Fixture.Slate);
        if (!TestTrue(TEXT("Native SpaceBar reopens the restored menu"), Fixture.Open())) { return false; }
        const TSharedPtr<SWindow> StalePopupWindow = Fixture.PopupWindow;
        const TSharedPtr<STextBlock> StaleRun = FindText(StalePopupWindow.ToSharedRef(), Fixture.RunLabel);
        const TSharedPtr<SCkUiMenuButton> RetainedMenu = Fixture.Menu;
        const int64 Revision = Fixture.View->GetRevision();
        const FCkUiLoadResult Rejected = Fixture.View->TryReload(Markup(true, true), TEXT(".root { padding: 13px; }"), TEXT("UiMenusRejectedReload"));
        TestTrue(TEXT("Invalid menu reload rejects while the popup is open"), !Rejected.Succeeded && Fixture.View->GetRevision() == Revision && RetainedMenu->IsOpen());
        if (!TestTrue(TEXT("Compatible menu reload publishes"), Fixture.View->TryReload(Markup(true), TEXT(".root { padding: 13px; }"), TEXT("UiMenusReload")).Succeeded)) { return false; }
        Tick(Fixture.Slate);
        TestTrue(TEXT("Compatible reload advances the view revision once"), Fixture.View->GetRevision() == Revision + 1);
        TestTrue(TEXT("Compatible reload retains the exact native menu anchor"), Fixture.View->GetMenuButton(TEXT("actions-button")) == RetainedMenu);
        TestFalse(TEXT("Compatible reload closes the owned popup"), RetainedMenu->IsOpen());
        if (StaleRun.IsValid()) { ClickText(Fixture.Slate, StalePopupWindow.ToSharedRef(), StaleRun.ToSharedRef()); }
        TestEqual(TEXT("Stale popup row cannot dispatch after a compatible reload"), Fixture.RunCalls, 1);

        if (!TestTrue(TEXT("Retained anchor reopens after compatible reload"), Fixture.Open())) { return false; }
        const TSharedPtr<STextBlock> HeldRun = FindText(Fixture.PopupWindow.ToSharedRef(), Fixture.RunLabel);
        Fixture.View.Reset();
        Tick(Fixture.Slate);
        TestFalse(TEXT("Owner release closes a held menu popup"), RetainedMenu->IsOpen());
        if (HeldRun.IsValid()) { ClickText(Fixture.Slate, Fixture.PopupWindow.ToSharedRef(), HeldRun.ToSharedRef()); }
        TestEqual(TEXT("Held popup input is inert after its owner releases"), Fixture.RunCalls, 1);
    }
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiMenus_Prevalidation,
    "Ck.UiAuthoring.Menus.PrevalidationRejectsMissingAction",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiMenus_Prevalidation::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_menus;
    FCkUiView::FDataBindings Data;
    Data.Visibility.Add(TEXT("can-run"), TAttribute<bool>(true));
    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, {}, {}, {}, MoveTemp(Data));
    View->GetRegion(TEXT("main"));
    const int64 Revision = View->GetRevision();
    const FCkUiLoadResult Result = View->TryReload(Markup(false, true), TEXT(""), TEXT("UiMenusMissingAction"));
    TestFalse(TEXT("Missing menu action rejects before menu staging"), Result.Succeeded);
    TestEqual(TEXT("Rejected menu action leaves revision unchanged"), View->GetRevision(), Revision);
    TestFalse(TEXT("Rejected menu action creates no retained menu button"), View->GetMenuButton(TEXT("actions-button")).IsValid());
    return true;
}
#endif // WITH_DEV_AUTOMATION_TESTS
