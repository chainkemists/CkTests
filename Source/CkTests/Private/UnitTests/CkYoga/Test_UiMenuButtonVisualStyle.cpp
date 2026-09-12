#include "CkSlateLayout/CkUiDocument.h"
#include "CkSlateLayout/SCkUiMenuButton.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Framework/Application/SlateApplication.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "Layout/Children.h"
#include "Misc/AutomationTest.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/SWindow.h"
#include "Widgets/Text/STextBlock.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_menu_button_visual_style
{
    auto Markup(const FString& InBody = TEXT("<menu-button id=\"actions\" menu=\"commands\" label=\"Actions\" class=\"styled\" />")) -> FString
    {
        return FString::Printf(TEXT("<ui version=\"1\"><menu id=\"commands\"><menu-item key=\"run\" label=\"Run command\" action=\"run\" /></menu><region name=\"main\"><column id=\"root\">%s</column></region></ui>"), *InBody);
    }

    auto Stylesheet() -> FString
    {
        return TEXT(".styled { -ck-menu-button-background: #102030; -ck-menu-button-border-color: #405060; "
            "-ck-menu-button-hover-background: #203040; -ck-menu-button-hover-border-color: #506070; "
            "-ck-menu-button-pressed-background: #304050; -ck-menu-button-pressed-border-color: #607080; "
            "-ck-menu-button-disabled-background: #112233; -ck-menu-button-disabled-border-color: #445566; "
            "-ck-menu-button-radius: 7px; -ck-menu-button-outline-width: 2px; "
            "-ck-menu-button-padding-x: 9px; -ck-menu-button-padding-y: 6px; -ck-menu-button-arrow: hidden; }");
    }

    auto Color(const uint8 InRed, const uint8 InGreen, const uint8 InBlue) -> FLinearColor
    {
        return FLinearColor(FColor(InRed, InGreen, InBlue));
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
        return nullptr;
    }

    auto Click(FSlateApplication& InSlate, const TSharedRef<SWindow>& InWindow, const TSharedRef<SWidget>& InWidget) -> bool
    {
        if (!InWindow->GetNativeWindow().IsValid()) { return false; }
        const FGeometry Geometry = InWidget->GetCachedGeometry();
        if (Geometry.GetLocalSize().X <= 0.0f || Geometry.GetLocalSize().Y <= 0.0f) { return false; }
        const FVector2D Position = Geometry.LocalToAbsolute(Geometry.GetLocalSize() * 0.5f);
        InSlate.SetCursorPos(Position);
        const TSet<FKey> MoveButtons;
        const FPointerEvent Move(0, FSlateApplication::CursorPointerIndex, Position, Position, MoveButtons, EKeys::Invalid, 0.0f, FModifierKeysState{});
        const TSet<FKey> DownButtons{EKeys::LeftMouseButton};
        const FPointerEvent Down(0, FSlateApplication::CursorPointerIndex, Position, Position, DownButtons, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        const TSet<FKey> UpButtons;
        const FPointerEvent Up(0, FSlateApplication::CursorPointerIndex, Position, Position, UpButtons, EKeys::LeftMouseButton, 0.0f, FModifierKeysState{});
        InSlate.ProcessMouseMoveEvent(Move, true);
        const bool bDownHandled = InSlate.ProcessMouseButtonDownEvent(InWindow->GetNativeWindow(), Down);
        const bool bUpHandled = InSlate.ProcessMouseButtonUpEvent(Up);
        InSlate.PumpMessages();
        InSlate.Tick();
        InSlate.Tick();
        return bDownHandled && bUpHandled;
    }

    struct FWindowScope final
    {
        explicit FWindowScope(FSlateApplication& InSlate) : Slate(InSlate) {}
        ~FWindowScope() { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } }

        FSlateApplication& Slate;
        TSharedPtr<SWindow> Window;
    };

    auto Tick(FSlateApplication& InSlate) -> void { InSlate.PumpMessages(); InSlate.Tick(); InSlate.Tick(); }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkUiMenuButtonVisualStyle_Runtime,
    "Ck.UiAuthoring.Menus.VisualStyle",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiMenuButtonVisualStyle_Runtime::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_menu_button_visual_style;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Menu-button visual style runtime test requires Slate.")); return false; }

    FCkUiDocument Document;
    const FCkUiLoadResult Parsed = FCkUiDocumentParser::TryParse(Markup(), Stylesheet(), {}, Document, TEXT("UiMenuButtonVisualStyleParsed"));
    const FCkUiNode* ParsedRoot = Document.Regions.Find(TEXT("main"));
    const FCkUiNode* ParsedMenuButton = ParsedRoot != nullptr && ParsedRoot->Children.Num() == 1 ? &ParsedRoot->Children[0] : nullptr;
    if (!TestTrue(TEXT("Menu-button visual CSS parses into the authored contract"), Parsed.Succeeded && ParsedMenuButton != nullptr
        && ParsedMenuButton->MenuButtonVisualStyle.Enabled
        && ParsedMenuButton->MenuButtonVisualStyle.Background.Get(FLinearColor::Transparent).Equals(Color(0x10, 0x20, 0x30))
        && ParsedMenuButton->MenuButtonVisualStyle.BorderColor.Get(FLinearColor::Transparent).Equals(Color(0x40, 0x50, 0x60))
        && ParsedMenuButton->MenuButtonVisualStyle.HoverBackground.Get(FLinearColor::Transparent).Equals(Color(0x20, 0x30, 0x40))
        && ParsedMenuButton->MenuButtonVisualStyle.HoverBorderColor.Get(FLinearColor::Transparent).Equals(Color(0x50, 0x60, 0x70))
        && ParsedMenuButton->MenuButtonVisualStyle.PressedBackground.Get(FLinearColor::Transparent).Equals(Color(0x30, 0x40, 0x50))
        && ParsedMenuButton->MenuButtonVisualStyle.PressedBorderColor.Get(FLinearColor::Transparent).Equals(Color(0x60, 0x70, 0x80))
        && ParsedMenuButton->MenuButtonVisualStyle.DisabledBackground.Get(FLinearColor::Transparent).Equals(Color(0x11, 0x22, 0x33))
        && ParsedMenuButton->MenuButtonVisualStyle.DisabledBorderColor.Get(FLinearColor::Transparent).Equals(Color(0x44, 0x55, 0x66))
        && ParsedMenuButton->MenuButtonVisualStyle.Radius.Get(0.0f) == 7.0f
        && ParsedMenuButton->MenuButtonVisualStyle.OutlineWidth.Get(0.0f) == 2.0f
        && ParsedMenuButton->MenuButtonVisualStyle.HasContentPadding
        && ParsedMenuButton->MenuButtonVisualStyle.ContentPadding == FMargin(9.0f, 6.0f)
        && ParsedMenuButton->MenuButtonVisualStyle.HasDownArrow.IsSet() && !ParsedMenuButton->MenuButtonVisualStyle.HasDownArrow.GetValue())) { return false; }

    int32 RunCalls = 0;
    FCkUiView::FActions Actions;
    Actions.Add(TEXT("run"), FSimpleDelegate::CreateLambda([&RunCalls]() { ++RunCalls; }));
    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, MoveTemp(Actions));
    const TSharedRef<SBox> Region = StaticCastSharedRef<SBox>(View->GetRegion(TEXT("main")));
    FSlateApplication& Slate = FSlateApplication::Get();
    FWindowScope Scope{Slate};
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D(320.0f, 160.0f)).CreateTitleBar(false).HasCloseButton(false)[Region];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);

    if (!TestTrue(TEXT("Styled menu-button document mounts"), View->TryReload(Markup(), Stylesheet(), TEXT("UiMenuButtonVisualStyleMounted")).Succeeded)) { return false; }
    Tick(Slate);
    const TSharedRef<SWidget> AcceptedRoot = Region->GetChildren()->GetChildAt(0);
    const int64 AcceptedRevision = View->GetRevision();
    const TSharedPtr<SCkUiMenuButton> Menu = View->GetMenuButton(TEXT("actions"));
    if (!TestTrue(TEXT("Visual CSS creates the shared menu-button presenter"), Menu.IsValid())) { return false; }
    const FCkUiMenuButtonVisualStyle& Applied = Menu->GetAppliedVisualStyle();
    TestTrue(TEXT("Mounted menu button exposes authored brush inputs, padding, and hidden arrow"), Applied.Enabled
        && Applied.Background.Get(FLinearColor::Transparent).Equals(Color(0x10, 0x20, 0x30))
        && Applied.BorderColor.Get(FLinearColor::Transparent).Equals(Color(0x40, 0x50, 0x60))
        && Applied.Radius.Get(0.0f) == 7.0f && Applied.OutlineWidth.Get(0.0f) == 2.0f && Applied.HasContentPadding
        && Menu->GetButtonContentPadding() == FMargin(9.0f, 6.0f) && !Menu->HasDownArrow());

    const TSharedPtr<STextBlock> Anchor = FindText(Menu.ToSharedRef(), TEXT("Actions"));
    if (!TestTrue(TEXT("Styled menu button exposes its inner Actions anchor"), Anchor.IsValid())) { return false; }
    if (!TestTrue(TEXT("Native pointer opens the styled menu button"), Click(Slate, Scope.Window.ToSharedRef(), Anchor.ToSharedRef()) && Menu->IsOpen())) { return false; }
    const TSharedPtr<SWidget> InitialContent = Menu->GetFocusTransferTarget();
    const TSharedPtr<SWindow> InitialPopup = Menu->GetMenuWindow();
    const TSharedPtr<STextBlock> InitialAction = InitialContent.IsValid() ? FindText(InitialContent.ToSharedRef(), TEXT("Run command")) : nullptr;
    if (!TestTrue(TEXT("Styled menu button mounts a real action in its owned popup"), InitialAction.IsValid() && InitialPopup.IsValid())) { return false; }
    TestTrue(TEXT("Styled menu button dispatches its real popup action"), Click(Slate, InitialPopup.ToSharedRef(), InitialAction.ToSharedRef()));
    TestEqual(TEXT("Styled menu action dispatches exactly once"), RunCalls, 1);

    const FCkUiLoadResult InvalidColor = View->TryReload(Markup(), Stylesheet().Replace(TEXT("#102030"), TEXT("not-a-color")), TEXT("UiMenuButtonVisualStyleInvalidColor"));
    TestFalse(TEXT("Invalid menu-button color rejects atomically"), InvalidColor.Succeeded);
    TestEqual(TEXT("Invalid menu-button color preserves revision"), View->GetRevision(), AcceptedRevision);
    TestTrue(TEXT("Invalid menu-button color preserves mounted root"), Region->GetChildren()->GetChildAt(0) == AcceptedRoot);

    const FCkUiLoadResult NegativeLength = View->TryReload(Markup(), Stylesheet().Replace(TEXT("-ck-menu-button-radius: 7px"), TEXT("-ck-menu-button-radius: -1px")), TEXT("UiMenuButtonVisualStyleNegativeLength"));
    TestFalse(TEXT("Negative menu-button radius rejects atomically"), NegativeLength.Succeeded);
    const FCkUiLoadResult NonFiniteLength = View->TryReload(Markup(), Stylesheet().Replace(TEXT("-ck-menu-button-radius: 7px"), TEXT("-ck-menu-button-radius: nanpx")), TEXT("UiMenuButtonVisualStyleNonFiniteLength"));
    TestFalse(TEXT("Nonfinite menu-button radius rejects atomically"), NonFiniteLength.Succeeded);
    const FCkUiLoadResult InvalidArrow = View->TryReload(Markup(), Stylesheet().Replace(TEXT("-ck-menu-button-arrow: hidden"), TEXT("-ck-menu-button-arrow: sideways")), TEXT("UiMenuButtonVisualStyleInvalidArrow"));
    TestFalse(TEXT("Invalid menu-button arrow token rejects atomically"), InvalidArrow.Succeeded);
    const FCkUiLoadResult WrongNode = View->TryReload(Markup(TEXT("<button id=\"not-a-menu\" action=\"run\" class=\"styled\">Run command</button>")), Stylesheet(), TEXT("UiMenuButtonVisualStyleWrongNode"));
    TestFalse(TEXT("Menu-button visual property on ordinary button rejects atomically"), WrongNode.Succeeded);
    TestEqual(TEXT("Invalid menu-button declarations preserve revision"), View->GetRevision(), AcceptedRevision);
    TestTrue(TEXT("Invalid menu-button declarations preserve mounted root"), Region->GetChildren()->GetChildAt(0) == AcceptedRoot);

    if (!TestTrue(TEXT("Menu button reopens before compatible visual reload"), Click(Slate, Scope.Window.ToSharedRef(), Anchor.ToSharedRef()) && Menu->IsOpen())) { return false; }
    const FString UpdatedStylesheet = Stylesheet().Replace(TEXT("#102030"), TEXT("#223344")).Replace(TEXT("-ck-menu-button-arrow: hidden"), TEXT("-ck-menu-button-arrow: visible"));
    if (!TestTrue(TEXT("Compatible menu-button visual reload succeeds"), View->TryReload(Markup(), UpdatedStylesheet, TEXT("UiMenuButtonVisualStyleReload")).Succeeded)) { return false; }
    Tick(Slate);
    const TSharedPtr<SCkUiMenuButton> ReloadedMenu = View->GetMenuButton(TEXT("actions"));
    TestTrue(TEXT("Compatible visual reload retains exact menu pointer, applies style and closes deferred popup"), ReloadedMenu == Menu && !Menu->IsOpen()
        && Menu->GetAppliedVisualStyle().Background.Get(FLinearColor::Transparent).Equals(Color(0x22, 0x33, 0x44)) && Menu->HasDownArrow());
    if (!TestTrue(TEXT("Reloaded styled menu button opens"), Click(Slate, Scope.Window.ToSharedRef(), Anchor.ToSharedRef()) && Menu->IsOpen())) { return false; }
    const TSharedPtr<SWidget> ReloadedContent = Menu->GetFocusTransferTarget();
    const TSharedPtr<SWindow> ReloadedPopup = Menu->GetMenuWindow();
    const TSharedPtr<STextBlock> ReloadedAction = ReloadedContent.IsValid() ? FindText(ReloadedContent.ToSharedRef(), TEXT("Run command")) : nullptr;
    if (!TestTrue(TEXT("Reloaded styled menu button retains real popup action"), ReloadedAction.IsValid() && ReloadedPopup.IsValid())) { return false; }
    TestTrue(TEXT("Reloaded styled menu button still dispatches"), Click(Slate, ReloadedPopup.ToSharedRef(), ReloadedAction.ToSharedRef()));
    TestEqual(TEXT("Reloaded menu action dispatches exactly once more"), RunCalls, 2);
    if (!TestTrue(TEXT("Compatible menu-button style-clear reload succeeds"), View->TryReload(Markup(TEXT("<menu-button id=\"actions\" menu=\"commands\" label=\"Actions\" />")), TEXT(""), TEXT("UiMenuButtonVisualStyleClear")).Succeeded)) { return false; }
    Tick(Slate);
    TestTrue(TEXT("Style-clear reload retains menu identity and restores native arrow presentation"), View->GetMenuButton(TEXT("actions")) == Menu
        && !Menu->GetAppliedVisualStyle().Enabled && !Menu->GetAppliedVisualStyle().HasContentPadding && Menu->HasDownArrow());
    if (!TestTrue(TEXT("Style-cleared menu button still opens from its inner anchor"), Click(Slate, Scope.Window.ToSharedRef(), Anchor.ToSharedRef()) && Menu->IsOpen())) { return false; }
    const TSharedPtr<SWidget> ClearedContent = Menu->GetFocusTransferTarget();
    const TSharedPtr<SWindow> ClearedPopup = Menu->GetMenuWindow();
    const TSharedPtr<STextBlock> ClearedAction = ClearedContent.IsValid() ? FindText(ClearedContent.ToSharedRef(), TEXT("Run command")) : nullptr;
    if (!TestTrue(TEXT("Style-cleared menu retains its real popup action"), ClearedAction.IsValid() && ClearedPopup.IsValid())) { return false; }
    TestTrue(TEXT("Style-cleared menu action still dispatches"), Click(Slate, ClearedPopup.ToSharedRef(), ClearedAction.ToSharedRef()));
    TestEqual(TEXT("Style-cleared menu action dispatches exactly once more"), RunCalls, 3);
    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
