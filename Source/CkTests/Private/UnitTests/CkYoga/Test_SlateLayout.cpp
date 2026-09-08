#include "CkSlateLayout/CkFlex.h"
#include "CkSlateLayout/CkFlexText.h"
#include "Layout/ArrangedChildren.h"
#include "Misc/AutomationTest.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/Layout/SSpacer.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_slate_layout
{
    auto Arrange(const TSharedRef<SCkFlexBox>& InPanel, FVector2D InSize, float InScale = 1.0f) -> FArrangedChildren
    {
        InPanel->SlatePrepass(InScale);
        auto Children = FArrangedChildren{EVisibility::Visible};
        InPanel->OnArrangeChildren(FGeometry::MakeRoot(InSize, FSlateLayoutTransform{InScale}), Children);
        return Children;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkSlateLayout_Rectangles,
    "Ck.TextureDebugger.Layout.RectanglesAndVisibility",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkSlateLayout_Rectangles::RunTest(const FString&) -> bool
{
    using namespace ck_tests_slate_layout;
    const auto First = SNew(SBox).WidthOverride(50.0f).HeightOverride(20.0f);
    const auto Second = SNew(SBox).WidthOverride(50.0f).HeightOverride(20.0f);
    const auto Panel = SNew(SCkFlexBox).Gap(10.0f).Padding(FMargin{5.0f})
        + SCkFlexBox::Slot().Grow(1.0f)[First]
        + SCkFlexBox::Slot().Shrink(0.0f)[Second];
    auto Children = Arrange(Panel, {300.0f, 100.0f});
    TestEqual(TEXT("Two native children arranged"), Children.Num(), 2);
    if (Children.Num() != 2) { return false; }
    TestEqual(TEXT("Grow receives remaining width"), Children[0].Geometry.GetLocalSize().X, 230.0f);
    TestEqual(TEXT("Fixed leaf preserves intrinsic width"), Children[1].Geometry.GetLocalSize().X, 50.0f);
    TestEqual(TEXT("Padding and gap position second child"), Children[1].Geometry.GetAbsolutePosition().X, 245.0f);
    TestEqual(TEXT("Stretch excludes outer padding"), Children[0].Geometry.GetLocalSize().Y, 90.0f);
    const auto Nodes = Panel->Get_NodeCount();
    const auto Allocations = Panel->Get_YogaNodeAllocationCount();
    Children = Arrange(Panel, {200.0f, 100.0f});
    TestEqual(TEXT("Resize recalculates grow"), Children[0].Geometry.GetLocalSize().X, 130.0f);
    TestEqual(TEXT("Resize retains Yoga nodes"), Panel->Get_NodeCount(), Nodes);

    First->SetVisibility(EVisibility::Hidden);
    Children = Arrange(Panel, {200.0f, 100.0f});
    TestEqual(TEXT("Hidden widget omitted from visible arrangement"), Children.Num(), 1);
    if (Children.Num() != 1) { return false; }
    TestEqual(TEXT("Hidden still occupies layout"), Children[0].Geometry.GetAbsolutePosition().X, 145.0f);
    First->SetVisibility(EVisibility::Collapsed);
    Children = Arrange(Panel, {200.0f, 100.0f});
    TestEqual(TEXT("Collapsed removes its gap and footprint"), Children[0].Geometry.GetAbsolutePosition().X, 5.0f);
    First->SetVisibility(EVisibility::Visible);
    Children = Arrange(Panel, {300.0f, 100.0f}, 1.5f);
    TestEqual(TEXT("DPI retains logical rectangle"), Children[0].Geometry.GetLocalSize().X, 230.0f);
    TestEqual(TEXT("Resize/visibility/DPI never allocate Yoga nodes"), Panel->Get_YogaNodeAllocationCount(), Allocations);
    const auto Inserted = SNew(SBox).WidthOverride(30.0f).HeightOverride(20.0f);
    Panel->AddSlot(0).Shrink(0.0f)[Inserted];
    Children = Arrange(Panel, {300.0f, 100.0f});
    TestEqual(TEXT("Insert adds a native child"), Children.Num(), 3);
    TestTrue(TEXT("Insert preserves requested order"), Children[0].Widget == Inserted);
    TestEqual(TEXT("Remove finds the inserted child"), Panel->RemoveSlot(Inserted), 0);
    Children = Arrange(Panel, {300.0f, 100.0f});
    TestEqual(TEXT("Remove restores tree shape"), Children.Num(), 2);
    TestTrue(TEXT("Removal preserves existing child identity"), Children[0].Widget == First);

    const auto Bounded = SNew(SCkFlexBox).Direction(Orient_Vertical).Padding(FMargin{5.0f})
        + SCkFlexBox::Slot().Grow(1.0f).MinHeight(20.0f).MaxHeight(40.0f).Padding(FMargin{2.0f})
        [SNew(SSpacer)];
    const auto BoundedChildren = Arrange(Bounded, {100.0f, 200.0f});
    TestEqual(TEXT("Maximum applies to slot border box"), BoundedChildren[0].Geometry.GetLocalSize().Y, 36.0f);
    TestEqual(TEXT("Slot padding offsets content exactly once"), BoundedChildren[0].Geometry.GetAbsolutePosition().X, 7.0f);
    SCkFlexBox::FSlot* MutableSlot = nullptr;
    const auto MutablePanel = SNew(SCkFlexBox)
        + SCkFlexBox::Slot().Expose(MutableSlot).Grow(1.0f)[SNew(SSpacer)];
    Arrange(MutablePanel, {100.0f, 100.0f});
    MutableSlot->SetPadding(FMargin{10.0f});
    const auto Reconfigured = Arrange(MutablePanel, {100.0f, 100.0f});
    TestEqual(TEXT("Inherited native slot mutation updates Yoga style"), Reconfigured[0].Geometry.GetLocalSize().X, 80.0f);
    const auto Compact = ck::slate::Row(10.0f, {
        ck::slate::Fill(SNew(SBox).WidthOverride(50.0f)),
        ck::slate::Content(SNew(SBox).WidthOverride(50.0f))}, FMargin{5.0f});
    const auto CompactChildren = Arrange(Compact, {300.0f, 100.0f});
    TestEqual(TEXT("Compact authoring preserves typed-slot geometry"), CompactChildren[0].Geometry.GetLocalSize().X, 230.0f);
    TestEqual(TEXT("Compact construction allocates one complete Yoga tree"), Compact->Get_YogaNodeAllocationCount(), 3);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkSlateLayout_ConstrainedText,
    "Ck.TextureDebugger.Layout.ConstrainedTextAndNestedPanels",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkSlateLayout_ConstrainedText::RunTest(const FString&) -> bool
{
    using namespace ck_tests_slate_layout;
    const auto Text = SNew(SCkFlexText).Font(FCoreStyle::GetDefaultFontStyle("Regular", 12)).Text(FText::FromString(TEXT(
        "A long localized texture description must wrap using actual Slate text shaping before the first paint, "
        "and its height must stay stable when the same constrained width is measured repeatedly.")));
    const auto Narrow = Text->Measure(140.0f, YGMeasureModeExactly, YGUndefined, YGMeasureModeUndefined, 1.0f);
    const auto Wide = Text->Measure(420.0f, YGMeasureModeExactly, YGUndefined, YGMeasureModeUndefined, 1.0f);
    TestEqual(TEXT("Exact constraint is honored"), Narrow.X, 140.0);
    TestTrue(TEXT("Narrow text needs more height before paint"), Narrow.Y > Wide.Y);
    const auto Nested = SNew(SCkFlexBox).Direction(Orient_Vertical)
        + SCkFlexBox::Slot().Shrink(0.0f)[Text];
    const auto Outer = SNew(SCkFlexBox).Direction(Orient_Vertical).Gap(8.0f)
        + SCkFlexBox::Slot().Shrink(0.0f)[Nested]
        + SCkFlexBox::Slot().Grow(1.0f)[SNew(SSpacer)];
    auto Children = Arrange(Outer, {140.0f, 600.0f});
    TestEqual(TEXT("Nested text height measured under parent constraint"), static_cast<double>(Children[0].Geometry.GetLocalSize().Y), Narrow.Y);
    const auto InitialHeight = Children[0].Geometry.GetLocalSize().Y;
    for (auto Index = 0; Index < 5; ++Index)
    {
        Children = Arrange(Outer, {140.0f, 600.0f});
        TestEqual(TEXT("Repeated solve does not oscillate"), static_cast<double>(Children[0].Geometry.GetLocalSize().Y), static_cast<double>(InitialHeight));
    }
    Text->SetText(FText::FromString(TEXT("Short text")));
    Children = Arrange(Outer, {140.0f, 600.0f});
    TestTrue(TEXT("Text mutation invalidates nested measurement"), Children[0].Geometry.GetLocalSize().Y < InitialHeight);
    Text->SetFont(FCoreStyle::GetDefaultFontStyle("Regular", 32));
    const auto Large = Text->Measure(140.0f, YGMeasureModeExactly, YGUndefined, YGMeasureModeUndefined, 1.5f);
    TestTrue(TEXT("Font and scale mutation remeasure real shaping"), Large.Y > Children[0].Geometry.GetLocalSize().Y);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkSlateLayout_RejectInvalid,
    "Ck.TextureDebugger.Layout.RejectInvalidBeforeCallbacks",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

auto FCkSlateLayout_RejectInvalid::RunTest(const FString&) -> bool
{
    using namespace ck_tests_slate_layout;
    auto Calls = 0;
    const auto Invalid = SNew(SCkFlexBox).Gap(-1.0f)
        + SCkFlexBox::Slot().Measure([&Calls](const FCkFlexMeasureArgs&) { ++Calls; return FVector2D{10.0f, 10.0f}; })
        [SNew(SSpacer)];
    const auto Rejected = Arrange(Invalid, {100.0f, 100.0f});
    TestEqual(TEXT("Invalid declaration publishes no nodes"), Invalid->Get_NodeCount(), 0);
    TestEqual(TEXT("Invalid declaration arranges no partial children"), Rejected.Num(), 0);
    TestEqual(TEXT("Invalid declaration invokes no callback"), Calls, 0);
    const auto Valid = SNew(SCkFlexBox)
        + SCkFlexBox::Slot().Measure([&Calls](const FCkFlexMeasureArgs&) { ++Calls; return FVector2D{10.0f, 10.0f}; })
        [SNew(SSpacer)];
    Arrange(Valid, {100.0f, 100.0f});
    Calls = 0;
    auto Children = FArrangedChildren{EVisibility::Visible};
    Valid->OnArrangeChildren(FGeometry::MakeRoot(FVector2D{-1.0f, 100.0f}, FSlateLayoutTransform{}), Children);
    TestEqual(TEXT("Invalid geometry invokes no callback"), Calls, 0);
    TestEqual(TEXT("Invalid geometry never publishes stale rectangles"), Children.Num(), 0);
    const auto InvalidMax = SNew(SCkFlexBox)
        + SCkFlexBox::Slot().MaxWidth(YGUndefined)
        .Measure([&Calls](const FCkFlexMeasureArgs&) { ++Calls; return FVector2D{10.0f, 10.0f}; })
        [SNew(SSpacer)];
    Arrange(InvalidMax, {100.0f, 100.0f});
    TestEqual(TEXT("Explicit NaN maximum is rejected before callbacks"), Calls, 0);
    TestEqual(TEXT("Explicit NaN maximum publishes no nodes"), InvalidMax->Get_NodeCount(), 0);
    const auto Metadata = Valid->GetMetaData<FCkFlexMeasureMetaData>();
    Metadata->Measure(FCkFlexMeasureArgs{.LayoutScale = -1.0f});
    Metadata->Measure(FCkFlexMeasureArgs{.WidthMode = YGMeasureModeExactly});
    TestEqual(TEXT("Invalid scale and constrained NaN reject before callbacks"), Calls, 0);
    const auto CountBefore = Valid->GetChildren()->Num();
    const auto AllocationsBefore = Valid->Get_YogaNodeAllocationCount();
    Valid->AddSlot().Grow(-1.0f)[SNew(SSpacer)];
    TestEqual(TEXT("Invalid dynamic slot leaves child topology unchanged"), Valid->GetChildren()->Num(), CountBefore);
    TestEqual(TEXT("Invalid dynamic slot leaves Yoga allocations unchanged"), Valid->Get_YogaNodeAllocationCount(), AllocationsBefore);
    TWeakPtr<SCkFlexBox> WeakPanel;
    const auto ReentrantChild = SNew(SSpacer);
    const auto ReentrantPanel = SNew(SCkFlexBox)
        + SCkFlexBox::Slot()
        .Measure([&WeakPanel, ReentrantChild](const FCkFlexMeasureArgs&)
        {
            if (const auto Panel = WeakPanel.Pin()) { Panel->RemoveSlot(ReentrantChild); }
            return FVector2D{10.0f, 10.0f};
        })
        .OnArranged([&WeakPanel, ReentrantChild](float, float)
        {
            if (const auto Panel = WeakPanel.Pin()) { Panel->RemoveSlot(ReentrantChild); }
        })
        [ReentrantChild];
    WeakPanel = ReentrantPanel;
    const auto ReentrantResult = Arrange(ReentrantPanel, {100.0f, 100.0f});
    TestEqual(TEXT("Measurement and arrangement reject reentrant removal"), ReentrantPanel->GetChildren()->Num(), 1);
    TestEqual(TEXT("Rejected reentrancy leaves valid arrangement"), ReentrantResult.Num(), 1);
    return true;
}

#endif
