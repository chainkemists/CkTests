#include "CkSlateLayout/CkFlexText.h"
#include "CkSlateLayout/CkUiDocument.h"
#include "CkSlateLayout/SCkUiStyledButton.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Framework/Application/SlateApplication.h"
#include "Misc/AutomationTest.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/SWindow.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_button_visual_style
{
    auto Markup(const FString& InBody = TEXT("<button id=\"run\" action=\"run\" enabled-bind=\"run-enabled\" class=\"styled\">Run task</button>")) -> FString
    {
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\">%s</column></region></ui>"), *InBody);
    }

    auto Stylesheet() -> FString
    {
        return TEXT(".styled { font-size: 11px; -ck-button-background: #102030; -ck-button-border-color: #405060; "
            "-ck-button-hover-background: #203040; -ck-button-hover-border-color: #506070; "
            "-ck-button-pressed-background: #304050; -ck-button-pressed-border-color: #607080; "
            "-ck-button-disabled-background: #112233; -ck-button-disabled-border-color: #445566; "
            "-ck-button-color: #d0e0f0; -ck-button-disabled-color: #708090; -ck-button-radius: 7px; "
            "-ck-button-outline-width: 2px; -ck-button-padding-x: 9px; -ck-button-padding-y: 4px; }");
    }

    auto FindButton(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SCkUiStyledButton>
    {
        if (InRoot->GetTag() == TEXT("run") && InRoot->GetTypeAsString() == TEXT("SCkUiStyledButton"))
        { return StaticCastSharedRef<SCkUiStyledButton>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SCkUiStyledButton> Found = FindButton(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto Color(const uint8 InRed, const uint8 InGreen, const uint8 InBlue) -> FLinearColor
    {
        return FLinearColor(FColor(InRed, InGreen, InBlue));
    }

    auto HasBrush(const FSlateBrush* InBrush, const FLinearColor& InFill, const FLinearColor& InOutline) -> bool
    {
        return InBrush != nullptr && InBrush->DrawAs == ESlateBrushDrawType::RoundedBox
            && InBrush->TintColor.GetSpecifiedColor().Equals(InFill)
            && InBrush->OutlineSettings.Color.GetSpecifiedColor().Equals(InOutline)
            && FMath::IsNearlyEqual(InBrush->OutlineSettings.Width, 2.0f)
            && FMath::IsNearlyEqual(InBrush->OutlineSettings.CornerRadii.X, 7.0f)
            && FMath::IsNearlyEqual(InBrush->OutlineSettings.CornerRadii.Y, 7.0f)
            && FMath::IsNearlyEqual(InBrush->OutlineSettings.CornerRadii.Z, 7.0f)
            && FMath::IsNearlyEqual(InBrush->OutlineSettings.CornerRadii.W, 7.0f);
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
    FCkUiButtonVisualStyle_Runtime,
    "Ck.UiAuthoring.Button.VisualStyle",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiButtonVisualStyle_Runtime::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_button_visual_style;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Button visual style runtime test requires Slate.")); return false; }

    auto Document = FCkUiDocument{};
    const FCkUiLoadResult Parsed = FCkUiDocumentParser::TryParse(Markup(), Stylesheet(), {}, Document, TEXT("UiButtonVisualStyleParsed"));
    const FCkUiNode* ParsedRoot = Document.Regions.Find(TEXT("main"));
    const FCkUiNode* ParsedButton = ParsedRoot != nullptr && ParsedRoot->Children.Num() == 1 ? &ParsedRoot->Children[0] : nullptr;
    if (!TestTrue(TEXT("Button visual CSS parses into the authored button contract"), Parsed.Succeeded && ParsedButton != nullptr
        && ParsedButton->ButtonVisualStyle.Enabled && ParsedButton->Style.FontSize.Get(0.0f) == 11.0f
        && ParsedButton->ButtonVisualStyle.ContentPadding == FMargin(9.0f, 4.0f)
        && ParsedButton->ButtonVisualStyle.Background.Get(FLinearColor::Transparent).Equals(Color(0x10, 0x20, 0x30))
        && ParsedButton->ButtonVisualStyle.BorderColor.Get(FLinearColor::Transparent).Equals(Color(0x40, 0x50, 0x60))
        && ParsedButton->ButtonVisualStyle.HoverBackground.Get(FLinearColor::Transparent).Equals(Color(0x20, 0x30, 0x40))
        && ParsedButton->ButtonVisualStyle.HoverBorderColor.Get(FLinearColor::Transparent).Equals(Color(0x50, 0x60, 0x70))
        && ParsedButton->ButtonVisualStyle.PressedBackground.Get(FLinearColor::Transparent).Equals(Color(0x30, 0x40, 0x50))
        && ParsedButton->ButtonVisualStyle.PressedBorderColor.Get(FLinearColor::Transparent).Equals(Color(0x60, 0x70, 0x80))
        && ParsedButton->ButtonVisualStyle.DisabledBackground.Get(FLinearColor::Transparent).Equals(Color(0x11, 0x22, 0x33))
        && ParsedButton->ButtonVisualStyle.DisabledBorderColor.Get(FLinearColor::Transparent).Equals(Color(0x44, 0x55, 0x66))
        && ParsedButton->ButtonVisualStyle.Radius.Get(0.0f) == 7.0f && ParsedButton->ButtonVisualStyle.OutlineWidth.Get(0.0f) == 2.0f))
    { return false; }

    int32 RunCalls = 0;
    bool bRunEnabled = true;
    auto Data = FCkUiView::FDataBindings{};
    Data.Visibility.Add(TEXT("run-enabled"), TAttribute<bool>::CreateLambda([&bRunEnabled]() { return bRunEnabled; }));
    auto Actions = FCkUiView::FActions{};
    Actions.Add(TEXT("run"), FSimpleDelegate::CreateLambda([&RunCalls]() { ++RunCalls; }));
    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, MoveTemp(Actions), {}, FSlateFontInfo(), MoveTemp(Data));
    const TSharedRef<SBox> Region = StaticCastSharedRef<SBox>(View->GetRegion(TEXT("main")));
    FSlateApplication& Slate = FSlateApplication::Get();
    FWindowScope Scope{Slate};
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D(320.0f, 160.0f)).CreateTitleBar(false).HasCloseButton(false)[Region];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);

    if (!TestTrue(TEXT("Styled button document mounts"), View->TryReload(Markup(), Stylesheet(), TEXT("UiButtonVisualStyleMounted")).Succeeded)) { return false; }
    Tick(Slate);
    const TSharedRef<SWidget> AcceptedRoot = Region->GetChildren()->GetChildAt(0);
    const int64 AcceptedRevision = View->GetRevision();
    const TSharedPtr<SCkUiStyledButton> Button = FindButton(AcceptedRoot);
    if (!TestTrue(TEXT("Visual CSS creates the Foundation styled button"), Button.IsValid())) { return false; }

    TestTrue(TEXT("Normal state exposes the authored rounded brush"), HasBrush(Button->GetBorderImage(), Color(0x10, 0x20, 0x30), Color(0x40, 0x50, 0x60)));
    Button->SimulateClick();
    TestEqual(TEXT("Styled button click dispatches the authored action"), RunCalls, 1);

    bRunEnabled = false;
    Button->SlatePrepass(1.0f);
    TestFalse(TEXT("Styled button reflects the disabled binding"), Button->IsEnabled());
    Button->SimulateClick();
    TestEqual(TEXT("Disabled styled button rejects dispatch"), RunCalls, 1);

    const FCkUiLoadResult InvalidColor = View->TryReload(Markup(), Stylesheet().Replace(TEXT("#102030"), TEXT("not-a-color")), TEXT("UiButtonVisualStyleInvalidColor"));
    TestFalse(TEXT("Invalid button color rejects atomically"), InvalidColor.Succeeded);
    TestEqual(TEXT("Invalid button color preserves revision"), View->GetRevision(), AcceptedRevision);
    TestTrue(TEXT("Invalid button color preserves mounted root"), Region->GetChildren()->GetChildAt(0) == AcceptedRoot);

    const FCkUiLoadResult NegativeLength = View->TryReload(Markup(), Stylesheet().Replace(TEXT("-ck-button-radius: 7px"), TEXT("-ck-button-radius: -1px")), TEXT("UiButtonVisualStyleNegativeLength"));
    TestFalse(TEXT("Negative button radius rejects atomically"), NegativeLength.Succeeded);
    TestEqual(TEXT("Negative button radius preserves revision"), View->GetRevision(), AcceptedRevision);
    TestTrue(TEXT("Negative button radius preserves mounted root"), Region->GetChildren()->GetChildAt(0) == AcceptedRoot);

    const FCkUiLoadResult WrongNode = View->TryReload(Markup(TEXT("<text id=\"not-a-button\" class=\"styled\">Not a button</text>")), Stylesheet(), TEXT("UiButtonVisualStyleWrongNode"));
    TestFalse(TEXT("Button visual property on text rejects atomically"), WrongNode.Succeeded);
    TestEqual(TEXT("Wrong-node button visual property preserves revision"), View->GetRevision(), AcceptedRevision);
    TestTrue(TEXT("Wrong-node button visual property preserves mounted root"), Region->GetChildren()->GetChildAt(0) == AcceptedRoot);
    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
