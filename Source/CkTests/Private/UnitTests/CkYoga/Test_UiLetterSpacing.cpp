#include "CkSlateLayout/CkFlexText.h"
#include "CkSlateLayout/CkUiDocument.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Framework/Application/SlateApplication.h"
#include "Layout/Children.h"
#include "Misc/AutomationTest.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/SWindow.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_letter_spacing
{
    auto Markup(const FString& InBody = TEXT("<text id=\"label\" class=\"tracked\">Tracked</text>")) -> FString
    {
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\">%s</column></region></ui>"), *InBody);
    }

    auto Css(const FString& InValue = TEXT(".12em")) -> FString
    {
        return TEXT(".tracked { letter-spacing: ") + InValue + TEXT("; }");
    }

    auto FindFlex(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SCkFlexText>
    {
        if (InRoot->GetTypeAsString() == TEXT("SCkFlexText"))
        {
            return StaticCastSharedRef<SCkFlexText>(InRoot);
        }

        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            const TSharedPtr<SCkFlexText> Found = FindFlex(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)));
            if (Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto Tick(FSlateApplication& InSlate) -> void
    {
        InSlate.PumpMessages();
        InSlate.Tick();
        InSlate.Tick();
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkUiLetterSpacing,
    "Ck.UiAuthoring.LetterSpacing",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiLetterSpacing::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_letter_spacing;

    bool bSucceeded = true;
    FCkUiDocument Document;
    const FCkUiLoadResult Parsed = FCkUiDocumentParser::TryParse(Markup(), Css(), {}, Document, TEXT("LetterSpacingParse"));
    const FCkUiNode* Root = Document.Regions.Find(TEXT("main"));
    const FCkUiNode* Text = Root != nullptr && Root->Children.Num() == 1 ? &Root->Children[0] : nullptr;
    bSucceeded = TestTrue(TEXT("Positive em tracking parses"), Parsed.Succeeded && Text != nullptr && Text->Style.LetterSpacing == 120) && bSucceeded;

    const TArray<TPair<FString, FString>> AcceptedCases = {
        {TEXT("negative"), TEXT("-.2em")},
        {TEXT("zero"), TEXT("0")}};
    for (const TPair<FString, FString>& Case : AcceptedCases)
    {
        FCkUiDocument CaseDocument;
        const FCkUiLoadResult CaseResult = FCkUiDocumentParser::TryParse(Markup(), Css(Case.Value), {}, CaseDocument, Case.Key);
        const FCkUiNode* CaseRoot = CaseDocument.Regions.Find(TEXT("main"));
        const bool bHasOneChild = CaseRoot != nullptr && CaseRoot->Children.Num() == 1;
        const int32 ExpectedSpacing = Case.Key == TEXT("negative") ? -200 : 0;
        bSucceeded = TestTrue(
            *FString::Printf(TEXT("%s em tracking parses"), *Case.Key),
            CaseResult.Succeeded && bHasOneChild && CaseRoot->Children[0].Style.LetterSpacing == ExpectedSpacing) && bSucceeded;
    }

    const TArray<FString> InvalidValues = {
        TEXT("2px"), TEXT("normal"), TEXT("10.1em"), TEXT("-1.1em"),
        TEXT(".12emx"), TEXT("-.2emjunk"), TEXT("0junk")};
    for (const FString& InvalidValue : InvalidValues)
    {
        FCkUiDocument InvalidDocument;
        const FCkUiLoadResult InvalidResult = FCkUiDocumentParser::TryParse(
            Markup(), Css(InvalidValue), {}, InvalidDocument, InvalidValue);
        bSucceeded = TestFalse(
            *FString::Printf(TEXT("Invalid letter-spacing rejects: %s"), *InvalidValue),
            InvalidResult.Succeeded) && bSucceeded;
    }

    FCkUiDocument WrongNodeDocument;
    const FCkUiLoadResult WrongNodeResult = FCkUiDocumentParser::TryParse(
        Markup(TEXT("<row id=\"x\" class=\"tracked\"/>")), Css(), {}, WrongNodeDocument, TEXT("Wrong"));
    bSucceeded = TestFalse(TEXT("Non-text node rejects tracking"), WrongNodeResult.Succeeded) && bSucceeded;

    if (!FSlateApplication::IsInitialized()) { return bSucceeded; }

    const TSharedRef<FCkUiView> View = FCkUiView::Create({});
    const TSharedRef<SBox> Region = StaticCastSharedRef<SBox>(View->GetRegion(TEXT("main")));
    FSlateApplication& Slate = FSlateApplication::Get();
    const TSharedRef<SWindow> Window = SNew(SWindow).ClientSize(FVector2D(200, 100))[Region];
    Slate.AddWindow(Window, true);

    const FCkUiLoadResult MountResult = View->TryReload(Markup(), Css(), TEXT("Mount"));
    bSucceeded = TestTrue(TEXT("Tracked text mounts"), MountResult.Succeeded) && bSucceeded;
    Tick(Slate);

    const TSharedPtr<SCkFlexText> Flex = FindFlex(Region);
    bSucceeded = TestTrue(
        TEXT("Runtime flex text receives tracking"),
        Flex.IsValid() && Flex->GetFont().LetterSpacing == 120) && bSucceeded;

    const FCkUiLoadResult ReloadResult = View->TryReload(Markup(), Css(TEXT("-.2em")), TEXT("Reload"));
    Tick(Slate);
    const TSharedPtr<SCkFlexText> ReloadedFlex = FindFlex(Region);
    bSucceeded = TestTrue(
        TEXT("Compatible reload replaces ordinary text and applies tracking"),
        ReloadResult.Succeeded && ReloadedFlex.IsValid() && ReloadedFlex != Flex
            && ReloadedFlex->GetFont().LetterSpacing == -200) && bSucceeded;

    const FCkUiLoadResult ClearResult = View->TryReload(
        Markup(TEXT("<text id=\"label\">Tracked</text>")), TEXT(""), TEXT("Clear"));
    Tick(Slate);
    const TSharedPtr<SCkFlexText> ClearedFlex = FindFlex(Region);
    bSucceeded = TestTrue(
        TEXT("Class-free clear replaces ordinary text and restores base tracking"),
        ClearResult.Succeeded && ClearedFlex.IsValid() && ClearedFlex != ReloadedFlex
            && ClearedFlex->GetFont().LetterSpacing == 0) && bSucceeded;

    Slate.DestroyWindowImmediately(Window);
    return bSucceeded;
}

#endif
