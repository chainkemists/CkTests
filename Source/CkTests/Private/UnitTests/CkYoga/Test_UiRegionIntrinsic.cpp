#include "CkSlateLayout/SCkUiSurface.h"

#include "Framework/Application/SlateApplication.h"
#include "Layout/ArrangedChildren.h"
#include "Misc/AutomationTest.h"
#include "Widgets/SBoxPanel.h"
#include "Widgets/Layout/SBox.h"
#include "Misc/ScopeExit.h"
#include "Widgets/SWindow.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_ui_region_intrinsic
{
    auto EmptyMarkup() -> FString
    {
        return TEXT("<ui version=\"1\"><region name=\"main\"><column id=\"root\"/></region></ui>");
    }

    auto WideMarkup(const FString& InLabel) -> FString
    {
        return FString::Printf(TEXT("<ui version=\"1\"><region name=\"main\"><row id=\"root\"><button id=\"left\" action=\"left\">Left</button><button id=\"wide\" action=\"wide\">%s</button><search id=\"search\" bind=\"query\" class=\"query\"/></row></region></ui>"), *InLabel);
    }

    auto Tick(FSlateApplication& InSlate) -> void
    {
        InSlate.PumpMessages();
        InSlate.Tick();
        InSlate.Tick();
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkUiRegionIntrinsic,
    "Ck.UiAuthoring.RegionIntrinsic", EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkUiRegionIntrinsic::RunTest(const FString&) -> bool
{
    using namespace ck_tests_ui_region_intrinsic;
    if (!FSlateApplication::IsInitialized()) { AddError(TEXT("Region intrinsic test requires initialized Slate.")); return false; }

    FCkUiView::FActions Actions;
    Actions.Add(TEXT("left"), FSimpleDelegate::CreateLambda([] {}));
    Actions.Add(TEXT("wide"), FSimpleDelegate::CreateLambda([] {}));
    FCkUiView::FDataBindings Data;
    Data.Text.Add(TEXT("query"), TAttribute<FText>::CreateLambda([] { return FText::FromString(TEXT("")); }));
    Data.TextChanged.Add(TEXT("query"), FOnTextChanged::CreateLambda([](const FText&) {}));
    const TSharedRef<FCkUiView> View = FCkUiView::Create({}, Actions, {}, FSlateFontInfo{}, MoveTemp(Data));
    FSlateApplication& Slate = FSlateApplication::Get();
    const TSharedRef<SWidget> Region = View->GetRegion(TEXT("main"));
    const TSharedRef<SWidget> Sibling = SNew(SBox).WidthOverride(40.0f).HeightOverride(30.0f);
    const TSharedRef<SHorizontalBox> Host = SNew(SHorizontalBox)
        + SHorizontalBox::Slot().AutoWidth()[Region]
        + SHorizontalBox::Slot().AutoWidth()[Sibling];
    TSharedPtr<SWindow> Window = SNew(SWindow).ClientSize(FVector2D{900.0f, 240.0f}).CreateTitleBar(false).HasCloseButton(false)[Host];
    Slate.AddWindow(Window.ToSharedRef(), true);
    ON_SCOPE_EXIT { if (Window.IsValid()) { Slate.DestroyWindowImmediately(Window.ToSharedRef()); } };

    if (!TestTrue(TEXT("Empty region loads"), View->TryReload(EmptyMarkup(), TEXT(""), TEXT("RegionIntrinsicEmpty")).Succeeded)) { return false; }
    Tick(Slate);
    const FVector2D EmptySize = Region->GetDesiredSize();
    if (!TestTrue(TEXT("Empty mounted region remains measurable"), EmptySize.X >= 0.0f && EmptySize.Y >= 0.0f)) { return false; }

    if (!TestTrue(TEXT("Authored intrinsic region loads"), View->TryReload(WideMarkup(TEXT("Initial intrinsic content")), TEXT(".query { min-width: 180px; }"), TEXT("RegionIntrinsicInitial")).Succeeded)) { return false; }
    Tick(Slate);
    const FVector2D InitialSize = Region->GetDesiredSize();
    // Read both siblings from one native arrangement. An empty SBox has no painted
    // child, so its cached geometry is not a reliable observation of this layout.
    FArrangedChildren Arranged{EVisibility::Visible};
    Host->ArrangeChildren(Host->GetCachedGeometry(), Arranged);
    if (!TestEqual(TEXT("Native host arranges both siblings"), Arranged.Num(), 2)) { return false; }
    const FGeometry& RegionGeometry = Arranged[0].Geometry;
    const FVector2D SiblingPosition = Arranged[1].Geometry.GetAbsolutePosition();
    const float RegionRight = RegionGeometry.LocalToAbsolute(FVector2D(RegionGeometry.GetLocalSize().X, 0.0f)).X;
    TestTrue(TEXT("Authored row has nonzero intrinsic width"), InitialSize.X > 0.0f && InitialSize.Y > 0.0f);
    TestTrue(TEXT("Native AutoWidth allocates the authored content"), Region->GetCachedGeometry().GetLocalSize().X >= 180.0f);
    TestTrue(TEXT("Intrinsic region does not overlap native sibling"), RegionRight <= SiblingPosition.X + 0.5f);

    const float InitialWidth = InitialSize.X;
    if (!TestTrue(TEXT("Wider authored text reloads"), View->TryReload(WideMarkup(TEXT("Much wider intrinsic content that must grow the mounted region")), TEXT(".query { min-width: 180px; }"), TEXT("RegionIntrinsicWider")).Succeeded)) { return false; }
    Tick(Slate);
    const FVector2D WiderSize = Region->GetDesiredSize();
    TestTrue(TEXT("Wider intrinsic content grows AutoWidth host"), WiderSize.X > InitialWidth);

    return true;
}

#endif
