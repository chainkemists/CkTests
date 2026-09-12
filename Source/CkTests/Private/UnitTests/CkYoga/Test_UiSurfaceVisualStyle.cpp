#include "CkSlateLayout/CkUiDocument.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Framework/Application/SlateApplication.h"
#include "Misc/AutomationTest.h"
#include "Widgets/Layout/SBorder.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/SWindow.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_surface_visual_style
{
    auto Markup(const FString& InRoot = TEXT("<column id=\"surface\" class=\"surface\"><text id=\"label\">Surface</text></column>")) -> FString
    {
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"main\">%s</region></ui>"), *InRoot);
    }

    auto Stylesheet() -> FString
    {
        return TEXT(".surface { background-color: #102030; border-color: #405060; border-width: 2px; border-radius: 7px; padding: 3px; }");
    }

    auto Color(const uint8 InRed, const uint8 InGreen, const uint8 InBlue) -> FLinearColor
    {
        return FLinearColor(FColor(InRed, InGreen, InBlue));
    }

    auto FindSurface(const TSharedRef<SWidget>& InRoot) -> TSharedPtr<SBorder>
    {
        if (InRoot->GetTag() == TEXT("surface") && InRoot->GetTypeAsString() == TEXT("SBorder"))
        { return StaticCastSharedRef<SBorder>(InRoot); }
        const FChildren* Children = InRoot->GetChildren();
        for (int32 Index = 0; Children != nullptr && Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SBorder> Found = FindSurface(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index))); Found.IsValid()) { return Found; }
        }
        return {};
    }

    auto HasBrush(const TSharedPtr<SBorder>& InSurface) -> bool
    {
        const FSlateBrush* Brush = InSurface.IsValid() ? InSurface->GetBorderImage() : nullptr;
        return Brush != nullptr && Brush->DrawAs == ESlateBrushDrawType::RoundedBox
            && Brush->TintColor.GetSpecifiedColor().Equals(Color(0x10, 0x20, 0x30))
            && Brush->OutlineSettings.Color.GetSpecifiedColor().Equals(Color(0x40, 0x50, 0x60))
            && FMath::IsNearlyEqual(Brush->OutlineSettings.Width, 2.0f)
            && FMath::IsNearlyEqual(Brush->OutlineSettings.CornerRadii.X, 7.0f)
            && FMath::IsNearlyEqual(Brush->OutlineSettings.CornerRadii.Y, 7.0f)
            && FMath::IsNearlyEqual(Brush->OutlineSettings.CornerRadii.Z, 7.0f)
            && FMath::IsNearlyEqual(Brush->OutlineSettings.CornerRadii.W, 7.0f);
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
    FCkUiSurfaceVisualStyle,
    "Ck.UiAuthoring.Surface.VisualStyle",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiSurfaceVisualStyle::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_surface_visual_style;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Surface visual style test requires Slate.")); return false; }

    auto Document = FCkUiDocument{};
    const FCkUiLoadResult Parsed = FCkUiDocumentParser::TryParse(Markup(), Stylesheet(), {}, Document, TEXT("UiSurfaceVisualStyleParsed"));
    const FCkUiNode* Root = Document.Regions.Find(TEXT("main"));
    if (!TestTrue(TEXT("Generic surface CSS parses on a column"), Parsed.Succeeded && Root != nullptr)) { return false; }
    TestTrue(TEXT("Surface fill parses"), Root->Style.Background.IsSet() && Root->Style.Background.GetValue().Equals(Color(0x10, 0x20, 0x30)));
    TestTrue(TEXT("Surface outline parses"), Root->Style.BorderColor.IsSet() && Root->Style.BorderColor.GetValue().Equals(Color(0x40, 0x50, 0x60))
        && Root->Style.BorderWidth.IsSet() && Root->Style.BorderWidth.GetValue() == 2.0f
        && Root->Style.BorderRadius.IsSet() && Root->Style.BorderRadius.GetValue() == 7.0f);

    const auto ExpectParserReject = [this](const FString& InName, const FString& InMarkup, const FString& InStylesheet)
    {
        auto RejectedDocument = FCkUiDocument{};
        const FCkUiLoadResult Result = FCkUiDocumentParser::TryParse(InMarkup, InStylesheet, {}, RejectedDocument, InName);
        TestFalse(*InName, Result.Succeeded);
        TestTrue(*(InName + TEXT(" reports a parse error")), !Result.Errors.IsEmpty());
    };
    ExpectParserReject(TEXT("Surface border properties reject on text"), Markup(TEXT("<text id=\"surface\" class=\"surface\">Surface</text>")), Stylesheet());
    ExpectParserReject(TEXT("Negative surface border width rejects"), Markup(), Stylesheet().Replace(TEXT("border-width: 2px"), TEXT("border-width: -1px")));
    ExpectParserReject(TEXT("Negative surface border radius rejects"), Markup(), Stylesheet().Replace(TEXT("border-radius: 7px"), TEXT("border-radius: -1px")));
    ExpectParserReject(TEXT("Invalid surface border color rejects"), Markup(), Stylesheet().Replace(TEXT("#405060"), TEXT("not-a-color")));

    const TSharedRef<FCkUiView> View = FCkUiView::Create({});
    const TSharedRef<SBox> Region = StaticCastSharedRef<SBox>(View->GetRegion(TEXT("main")));
    FSlateApplication& Slate = FSlateApplication::Get();
    FWindowScope Scope{Slate};
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D(320.0f, 160.0f)).CreateTitleBar(false).HasCloseButton(false)[Region];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);

    if (!TestTrue(TEXT("Styled surface document mounts"), View->TryReload(Markup(), Stylesheet(), TEXT("UiSurfaceVisualStyleMounted")).Succeeded)) { return false; }
    Tick(Slate);
    const TSharedRef<SWidget> AcceptedRoot = Region->GetChildren()->GetChildAt(0);
    const int64 AcceptedRevision = View->GetRevision();
    const TSharedPtr<SBorder> Surface = FindSurface(AcceptedRoot);
    if (!TestTrue(TEXT("Styled surface creates a tagged rounded border"), Surface.IsValid())) { return false; }
    TestTrue(TEXT("Mounted surface exposes the authored fill, outline, width, and radius"), HasBrush(Surface));

    const FCkUiLoadResult Rejected = View->TryReload(Markup(), Stylesheet().Replace(TEXT("border-width: 2px"), TEXT("border-width: -1px")), TEXT("UiSurfaceVisualStyleRejected"));
    TestFalse(TEXT("Rejected surface stylesheet fails atomically"), Rejected.Succeeded);
    TestEqual(TEXT("Rejected surface stylesheet preserves revision"), View->GetRevision(), AcceptedRevision);
    TestTrue(TEXT("Rejected surface stylesheet preserves mounted root identity"), Region->GetChildren()->GetChildAt(0) == AcceptedRoot);
    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
