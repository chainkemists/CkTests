#include "CkSlateLayout/CkUiDocument.h"
#include "CkSlateLayout/SCkUiSurface.h"

#include "Framework/Application/SlateApplication.h"
#include "Layout/Children.h"
#include "Misc/AutomationTest.h"
#include "Styling/CoreStyle.h"
#include "Widgets/SWindow.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_flex_wrap
{
    auto RowMarkup() -> FString
    {
        return TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"><row id=\"wrapped\" class=\"wrapped\"><button id=\"first\" class=\"item\" action=\"first\">First</button><button id=\"second\" class=\"item\" action=\"second\">Second</button><button id=\"third\" class=\"item\" action=\"third\">Third</button></row><text id=\"after\">After</text></column></region></ui>");
    }

    auto ColumnMarkup() -> FString
    {
        return TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"><column id=\"wrapped\" class=\"wrapped\"><button id=\"first\" class=\"item\" action=\"first\">First</button><button id=\"second\" class=\"item\" action=\"second\">Second</button><button id=\"third\" class=\"item\" action=\"third\">Third</button></column></column></region></ui>");
    }

    auto RowStyles(const TCHAR* InWrap = nullptr) -> FString
    {
        FString Result = TEXT(".wrapped { gap: 10px; } .item { width: 100px; height: 20px; flex-shrink: 0; }");
        if (InWrap != nullptr) { Result += FString::Printf(TEXT(" .wrapped { flex-wrap: %s; }"), InWrap); }
        return Result;
    }

    auto ColumnStyles() -> FString
    {
        return TEXT(".wrapped { flex-wrap: wrap; gap: 10px; height: 140px; } .item { width: 50px; height: 60px; flex-shrink: 0; }");
    }

    auto FindTagged(const TSharedRef<SWidget>& InRoot, const FName InTag) -> TSharedPtr<SWidget>
    {
        if (InRoot->GetTag() == InTag) { return InRoot; }
        const FChildren* Children = InRoot->GetChildren();
        if (Children == nullptr) { return nullptr; }
        for (int32 Index = 0; Index < Children->Num(); ++Index)
        {
            if (const TSharedPtr<SWidget> Found = FindTagged(ConstCastSharedRef<SWidget>(Children->GetChildAt(Index)), InTag); Found.IsValid()) { return Found; }
        }
        return nullptr;
    }

    auto RegionContent(const TSharedRef<SWidget>& InRegion) -> TSharedRef<SWidget>
    {
        return ConstCastSharedRef<SWidget>(InRegion->GetChildren()->GetChildAt(0));
    }

    auto PositionInRegion(const TSharedRef<SWidget>& InRegion, const TSharedRef<SWidget>& InWidget) -> FVector2D
    {
        return InRegion->GetCachedGeometry().AbsoluteToLocal(InWidget->GetCachedGeometry().GetAbsolutePosition());
    }

    auto Tick(FSlateApplication& InSlate) -> void
    {
        InSlate.PumpMessages();
        InSlate.Tick();
        InSlate.Tick();
    }

    auto HasError(const FCkUiLoadResult& InResult, const TCHAR* InNeedle) -> bool
    {
        return InResult.Errors.ContainsByPredicate([InNeedle](const FString& Error) { return Error.Contains(InNeedle, ESearchCase::IgnoreCase); });
    }

    struct FWindowScope final
    {
        explicit FWindowScope(FSlateApplication& InSlate) : Slate(InSlate) {}
        ~FWindowScope() { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } }

        FSlateApplication& Slate;
        TSharedPtr<SWindow> Window;
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiFlexWrap_Runtime,
    "Ck.UiAuthoring.Layout.FlexWrapRenderedGeometryAndValidation",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiFlexWrap_Runtime::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_flex_wrap;

    FSlateApplication& Slate = FSlateApplication::Get();
    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, {
        {TEXT("first"), FSimpleDelegate::CreateLambda([] {})},
        {TEXT("second"), FSimpleDelegate::CreateLambda([] {})},
        {TEXT("third"), FSimpleDelegate::CreateLambda([] {})},
    }, {}, FCoreStyle::GetDefaultFontStyle("Regular", 12));
    const TSharedRef<SWidget> Region = View->GetRegion(TEXT("main"));
    FWindowScope Scope{Slate};
    Scope.Window = SNew(SWindow).AutoCenter(EAutoCenter::None).ClientSize(FVector2D{400.0f, 180.0f})
        .CreateTitleBar(false).HasCloseButton(false)[Region];
    Slate.AddWindow(Scope.Window.ToSharedRef(), true);

    const FCkUiLoadResult InitialLoad = View->TryReload(RowMarkup(), RowStyles(TEXT("wrap")), TEXT("UiFlexWrapInitial"));
    if (!TestTrue(TEXT("Row flex-wrap document loads"), InitialLoad.Succeeded))
    {
        for (const FString& Error : InitialLoad.Errors) { AddError(Error); }
        return false;
    }
    Tick(Slate);
    const TSharedPtr<SWidget> WideFirst = FindTagged(Region, TEXT("first"));
    const TSharedPtr<SWidget> WideThird = FindTagged(Region, TEXT("third"));
    if (!TestTrue(TEXT("Wide row renders authored buttons"), WideFirst.IsValid() && WideThird.IsValid())) { return false; }
    TestTrue(TEXT("Wide row keeps all items on one line"), FMath::IsNearlyEqual(PositionInRegion(Region, WideFirst.ToSharedRef()).Y, PositionInRegion(Region, WideThird.ToSharedRef()).Y));

    Scope.Window->Resize(FVector2D{240.0f, 180.0f});
    Tick(Slate);
    const TSharedPtr<SWidget> NarrowFirst = FindTagged(Region, TEXT("first"));
    const TSharedPtr<SWidget> NarrowThird = FindTagged(Region, TEXT("third"));
    const TSharedPtr<SWidget> After = FindTagged(Region, TEXT("after"));
    const TSharedPtr<SWidget> WrappedRow = FindTagged(Region, TEXT("wrapped"));
    if (!TestTrue(TEXT("Narrow row retains authored buttons and following column content"), NarrowFirst.IsValid() && NarrowThird.IsValid() && After.IsValid() && WrappedRow.IsValid())) { return false; }
    const FGeometry NarrowFirstGeometry = NarrowFirst->GetCachedGeometry();
    const FGeometry NarrowThirdGeometry = NarrowThird->GetCachedGeometry();
    const FVector2D NarrowFirstPosition = PositionInRegion(Region, NarrowFirst.ToSharedRef());
    const FVector2D NarrowThirdPosition = PositionInRegion(Region, NarrowThird.ToSharedRef());
    const FVector2D AfterPosition = PositionInRegion(Region, After.ToSharedRef());
    TestTrue(TEXT("Narrow row moves overflowing item onto a later line with the cross-axis gap"), NarrowThirdPosition.Y >= NarrowFirstPosition.Y + NarrowFirstGeometry.GetLocalSize().Y + 10.0f);
    TestTrue(TEXT("Nested wrapped row is constrained to the narrow containing column and reports both rows"), WrappedRow->GetCachedGeometry().GetLocalSize().X <= 240.0f && WrappedRow->GetCachedGeometry().GetLocalSize().Y >= 50.0f);
    TestTrue(TEXT("Nested wrapped row reports its increased height to containing column"), AfterPosition.Y >= NarrowThirdPosition.Y + NarrowThirdGeometry.GetLocalSize().Y);

    const FCkUiLoadResult ReverseLoad = View->TryReload(RowMarkup(), RowStyles(TEXT("wrap-reverse")), TEXT("UiFlexWrapReverse"));
    if (!TestTrue(TEXT("Wrap-reverse reload succeeds"), ReverseLoad.Succeeded))
    {
        for (const FString& Error : ReverseLoad.Errors) { AddError(Error); }
        return false;
    }
    Tick(Slate);
    const TSharedPtr<SWidget> ReverseFirst = FindTagged(Region, TEXT("first"));
    const TSharedPtr<SWidget> ReverseThird = FindTagged(Region, TEXT("third"));
    if (!TestTrue(TEXT("Wrap-reverse retains authored buttons"), ReverseFirst.IsValid() && ReverseThird.IsValid())) { return false; }
    TestTrue(TEXT("Wrap-reverse reverses wrapped line order"), PositionInRegion(Region, ReverseFirst.ToSharedRef()).Y > PositionInRegion(Region, ReverseThird.ToSharedRef()).Y);

    const FCkUiLoadResult NoWrapLoad = View->TryReload(RowMarkup(), RowStyles(), TEXT("UiFlexNoWrap"));
    if (!TestTrue(TEXT("Default nowrap reload succeeds"), NoWrapLoad.Succeeded)) { return false; }
    Tick(Slate);
    const TSharedPtr<SWidget> NoWrapFirst = FindTagged(Region, TEXT("first"));
    const TSharedPtr<SWidget> NoWrapThird = FindTagged(Region, TEXT("third"));
    if (!TestTrue(TEXT("No-wrap retains authored buttons"), NoWrapFirst.IsValid() && NoWrapThird.IsValid())) { return false; }
    TestTrue(TEXT("Default nowrap preserves one-line compatibility"), FMath::IsNearlyEqual(PositionInRegion(Region, NoWrapFirst.ToSharedRef()).Y, PositionInRegion(Region, NoWrapThird.ToSharedRef()).Y));

    Scope.Window->Resize(FVector2D{240.0f, 240.0f});
    const FCkUiLoadResult ColumnLoad = View->TryReload(ColumnMarkup(), ColumnStyles(), TEXT("UiFlexColumnWrap"));
    if (!TestTrue(TEXT("Column flex-wrap reload succeeds"), ColumnLoad.Succeeded)) { return false; }
    Tick(Slate);
    const TSharedPtr<SWidget> ColumnFirst = FindTagged(Region, TEXT("first"));
    const TSharedPtr<SWidget> ColumnThird = FindTagged(Region, TEXT("third"));
    if (!TestTrue(TEXT("Column wrap retains authored buttons"), ColumnFirst.IsValid() && ColumnThird.IsValid())) { return false; }
    TestTrue(TEXT("Column wrap moves overflowing item to a later column with the cross-axis gap"), PositionInRegion(Region, ColumnThird.ToSharedRef()).X >= PositionInRegion(Region, ColumnFirst.ToSharedRef()).X + ColumnFirst->GetCachedGeometry().GetLocalSize().X + 10.0f);

    const int64 AcceptedRevision = View->GetRevision();
    const TSharedRef<SWidget> AcceptedRoot = RegionContent(Region);
    const FCkUiLoadResult InvalidValue = View->TryReload(RowMarkup(), RowStyles(TEXT("sideways")), TEXT("UiFlexWrapInvalidValue"));
    TestFalse(TEXT("Invalid flex-wrap value rejects"), InvalidValue.Succeeded);
    TestTrue(TEXT("Invalid flex-wrap value reports a diagnostic"), HasError(InvalidValue, TEXT("flex-wrap")));
    TestEqual(TEXT("Invalid flex-wrap value preserves revision"), View->GetRevision(), AcceptedRevision);
    TestTrue(TEXT("Invalid flex-wrap value preserves mounted view"), RegionContent(Region) == AcceptedRoot);

    const FCkUiLoadResult InvalidTarget = View->TryReload(RowMarkup(), RowStyles() + TEXT(" .item { flex-wrap: wrap; }"), TEXT("UiFlexWrapInvalidTarget"));
    TestFalse(TEXT("Flex-wrap on a non-container rejects"), InvalidTarget.Succeeded);
    TestTrue(TEXT("Flex-wrap target rejection reports a diagnostic"), HasError(InvalidTarget, TEXT("not applicable")));
    TestEqual(TEXT("Flex-wrap target rejection preserves revision"), View->GetRevision(), AcceptedRevision);
    TestTrue(TEXT("Flex-wrap target rejection preserves mounted view"), RegionContent(Region) == AcceptedRoot);
    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
