// Native C API integration coverage for CkYoga. These tests deliberately do not
// exercise Slate or a C++ wrapper: their job is to prove CkTests links the vendor
// module and that the public Yoga C API has the expected layout/lifecycle behavior.

#include "CkCore/Macros/CkMacros.h"

#include "Misc/AutomationTest.h"

#include <yoga/Yoga.h>

#if WITH_DEV_AUTOMATION_TESTS

namespace ck_tests_yoga_integration
{
    struct FYogaTree final
    {
        explicit FYogaTree(const bool InUseWebDefaults)
            : Config{YGConfigNew()}
        {
            if (Config != nullptr)
            {
                YGConfigSetUseWebDefaults(Config, InUseWebDefaults);
                Root = YGNodeNewWithConfig(Config);
            }
        }

        ~FYogaTree()
        {
            // Nodes retain their config. Release the entire owned tree before its config.
            if (Root != nullptr)
            {
                YGNodeFreeRecursive(Root);
            }
            if (Config != nullptr)
            {
                YGConfigFree(Config);
            }
        }

        FYogaTree(const FYogaTree&) = delete;
        auto operator=(const FYogaTree&) -> FYogaTree& = delete;

        YGConfigRef Config = nullptr;
        YGNodeRef Root = nullptr;
    };

    auto RequireTree(FAutomationTestBase& Test, const FYogaTree& Tree) -> bool
    {
        Test.TestNotNull(TEXT("Yoga config allocated"), Tree.Config);
        Test.TestNotNull(TEXT("Yoga root allocated"), Tree.Root);
        return Tree.Config != nullptr && Tree.Root != nullptr;
    }

    struct FMeasureState
    {
        int32 CallCount = 0;
        float DesiredWidth = 640.0f;
        float DesiredHeight = 24.0f;
        float LastAvailableWidth = 0.0f;
        YGMeasureMode LastWidthMode = YGMeasureModeUndefined;
    };

    auto MeasureLeaf(
        YGNodeConstRef Node,
        const float AvailableWidth,
        const YGMeasureMode WidthMode,
        const float /*AvailableHeight*/,
        const YGMeasureMode /*HeightMode*/) -> YGSize
    {
        auto* State = static_cast<FMeasureState*>(YGNodeGetContext(Node));
        ++State->CallCount;
        State->LastAvailableWidth = AvailableWidth;
        State->LastWidthMode = WidthMode;
        const auto Width = WidthMode == YGMeasureModeUndefined
            ? State->DesiredWidth
            : (AvailableWidth < State->DesiredWidth ? AvailableWidth : State->DesiredWidth);
        return YGSize{Width, State->DesiredHeight};
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkYogaIntegration_UndefinedDimensionsPreserveNaNSemantics,
    "Ck.Yoga.Integration.UndefinedDimensionsPreserveNaNSemantics",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

auto
    FCkYogaIntegration_UndefinedDimensionsPreserveNaNSemantics::
    RunTest(
        const FString&)
    -> bool
{
    TestTrue(TEXT("NaN remains Yoga's undefined dimension sentinel"), YGFloatIsUndefined(YGUndefined));
    TestFalse(TEXT("Zero is a defined dimension"), YGFloatIsUndefined(0.0f));
    TestFalse(TEXT("Finite width is a defined dimension"), YGFloatIsUndefined(320.0f));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkYogaIntegration_WebDefaultsOwnsTreeAndLayoutsPane,
    "Ck.Yoga.Integration.WebDefaultsOwnsTreeAndLayoutsPane",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

auto
    FCkYogaIntegration_WebDefaultsOwnsTreeAndLayoutsPane::
    RunTest(
        const FString&)
    -> bool
{
    using namespace ck_tests_yoga_integration;

    auto Tree = FYogaTree{true};
    if (NOT RequireTree(*this, Tree))
    {
        return false;
    }

    TestTrue(TEXT("Web defaults enabled"), YGConfigGetUseWebDefaults(Tree.Config));
    TestEqual(TEXT("Web default direction is row"), YGNodeStyleGetFlexDirection(Tree.Root), YGFlexDirectionRow);
    TestEqual(TEXT("Root retains supplied config"), YGNodeGetConfig(Tree.Root), static_cast<YGConfigConstRef>(Tree.Config));

    const auto Sidebar = YGNodeNewWithConfig(Tree.Config);
    TestNotNull(TEXT("Sidebar allocated"), Sidebar);
    if (Sidebar == nullptr)
    {
        return false;
    }
    YGNodeInsertChild(Tree.Root, Sidebar, 0);

    const auto Pane = YGNodeNewWithConfig(Tree.Config);
    TestNotNull(TEXT("Flex pane allocated"), Pane);
    if (Pane == nullptr)
    {
        return false;
    }
    YGNodeInsertChild(Tree.Root, Pane, 1);

    YGNodeStyleSetWidth(Tree.Root, 600.0f);
    YGNodeStyleSetHeight(Tree.Root, 240.0f);
    YGNodeStyleSetPadding(Tree.Root, YGEdgeAll, 10.0f);
    YGNodeStyleSetGap(Tree.Root, YGGutterColumn, 20.0f);
    YGNodeStyleSetWidth(Sidebar, 160.0f);
    YGNodeStyleSetFlexGrow(Pane, 1.0f);
    TestEqual(TEXT("Root owns sidebar"), YGNodeGetOwner(Sidebar), Tree.Root);
    TestEqual(TEXT("Root owns flex pane"), YGNodeGetOwner(Pane), Tree.Root);
    TestEqual(TEXT("Root child count"), static_cast<int32>(YGNodeGetChildCount(Tree.Root)), 2);

    YGNodeCalculateLayout(Tree.Root, 600.0f, 240.0f, YGDirectionLTR);

    TestEqual(TEXT("Sidebar left honors padding"), YGNodeLayoutGetLeft(Sidebar), 10.0f);
    TestEqual(TEXT("Sidebar top honors padding"), YGNodeLayoutGetTop(Sidebar), 10.0f);
    TestEqual(TEXT("Sidebar fixed width"), YGNodeLayoutGetWidth(Sidebar), 160.0f);
    TestEqual(TEXT("Sidebar stretches within vertical padding"), YGNodeLayoutGetHeight(Sidebar), 220.0f);
    TestEqual(TEXT("Pane left honors sidebar and gap"), YGNodeLayoutGetLeft(Pane), 190.0f);
    TestEqual(TEXT("Pane computed flex width"), YGNodeLayoutGetWidth(Pane), 400.0f);
    TestEqual(TEXT("Pane stretches within vertical padding"), YGNodeLayoutGetHeight(Pane), 220.0f);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkYogaIntegration_ResizeAndStyleDirtyInvalidateDeterministically,
    "Ck.Yoga.Integration.ResizeAndStyleDirtyInvalidateDeterministically",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

auto
    FCkYogaIntegration_ResizeAndStyleDirtyInvalidateDeterministically::
    RunTest(
        const FString&)
    -> bool
{
    using namespace ck_tests_yoga_integration;

    auto Tree = FYogaTree{true};
    if (NOT RequireTree(*this, Tree))
    {
        return false;
    }

    const auto Sidebar = YGNodeNewWithConfig(Tree.Config);
    TestNotNull(TEXT("Sidebar allocated"), Sidebar);
    if (Sidebar == nullptr)
    {
        return false;
    }
    YGNodeInsertChild(Tree.Root, Sidebar, 0);

    const auto Pane = YGNodeNewWithConfig(Tree.Config);
    TestNotNull(TEXT("Flex pane allocated"), Pane);
    if (Pane == nullptr)
    {
        return false;
    }
    YGNodeInsertChild(Tree.Root, Pane, 1);

    YGNodeStyleSetFlexDirection(Tree.Root, YGFlexDirectionRow);
    YGNodeStyleSetWidth(Tree.Root, 500.0f);
    YGNodeStyleSetHeight(Tree.Root, 100.0f);
    YGNodeStyleSetPadding(Tree.Root, YGEdgeAll, 10.0f);
    YGNodeStyleSetGap(Tree.Root, YGGutterColumn, 10.0f);
    YGNodeStyleSetWidth(Sidebar, 100.0f);
    YGNodeStyleSetFlexGrow(Pane, 1.0f);
    YGNodeCalculateLayout(Tree.Root, 500.0f, 100.0f, YGDirectionLTR);
    TestEqual(TEXT("Initial flex width"), YGNodeLayoutGetWidth(Pane), 370.0f);
    TestFalse(TEXT("Tree clean after initial calculation"), YGNodeIsDirty(Tree.Root));

    YGNodeStyleSetWidth(Tree.Root, 700.0f);
    TestTrue(TEXT("Style change dirties tree"), YGNodeIsDirty(Tree.Root));
    YGNodeCalculateLayout(Tree.Root, 700.0f, 100.0f, YGDirectionLTR);
    TestEqual(TEXT("Resize recomputes flex width"), YGNodeLayoutGetWidth(Pane), 570.0f);
    TestFalse(TEXT("Tree clean after resize calculation"), YGNodeIsDirty(Tree.Root));

    YGNodeStyleSetPadding(Tree.Root, YGEdgeHorizontal, 20.0f);
    TestTrue(TEXT("Padding change dirties tree"), YGNodeIsDirty(Tree.Root));
    YGNodeCalculateLayout(Tree.Root, 700.0f, 100.0f, YGDirectionLTR);
    TestEqual(TEXT("Padding shifts sidebar"), YGNodeLayoutGetLeft(Sidebar), 20.0f);
    TestEqual(TEXT("Padding shifts flex pane"), YGNodeLayoutGetLeft(Pane), 130.0f);
    TestEqual(TEXT("Padding recomputes flex width"), YGNodeLayoutGetWidth(Pane), 550.0f);

    YGNodeCalculateLayout(Tree.Root, 700.0f, 100.0f, YGDirectionLTR);
    TestEqual(TEXT("Unchanged calculation keeps pane left"), YGNodeLayoutGetLeft(Pane), 130.0f);
    TestEqual(TEXT("Unchanged calculation keeps pane width"), YGNodeLayoutGetWidth(Pane), 550.0f);
    TestFalse(TEXT("Tree remains clean after identical calculation"), YGNodeIsDirty(Tree.Root));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkYogaIntegration_MeasuredLeafUsesConstraintsAndExplicitDirtyRemeasure,
    "Ck.Yoga.Integration.MeasuredLeafUsesConstraintsAndExplicitDirtyRemeasure",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

auto
    FCkYogaIntegration_MeasuredLeafUsesConstraintsAndExplicitDirtyRemeasure::
    RunTest(
        const FString&)
    -> bool
{
    using namespace ck_tests_yoga_integration;

    // State must outlive the node because Yoga may consult it during tree teardown.
    auto State = FMeasureState{};
    auto Tree = FYogaTree{true};
    if (NOT RequireTree(*this, Tree))
    {
        return false;
    }

    const auto Leaf = YGNodeNewWithConfig(Tree.Config);
    TestNotNull(TEXT("Measured leaf allocated"), Leaf);
    if (Leaf == nullptr)
    {
        return false;
    }

    YGNodeStyleSetFlexDirection(Tree.Root, YGFlexDirectionColumn);
    YGNodeStyleSetWidth(Tree.Root, 320.0f);
    YGNodeStyleSetPadding(Tree.Root, YGEdgeHorizontal, 10.0f);
    YGNodeSetContext(Leaf, &State);
    YGNodeSetMeasureFunc(Leaf, &MeasureLeaf);
    YGNodeInsertChild(Tree.Root, Leaf, 0);

    YGNodeCalculateLayout(Tree.Root, 320.0f, YGUndefined, YGDirectionLTR);
    const auto InitialMeasureCalls = State.CallCount;
    TestTrue(TEXT("Measure callback ran"), InitialMeasureCalls > 0);
    TestEqual(TEXT("Measured leaf receives padded available width"), State.LastAvailableWidth, 300.0f);
    TestEqual(TEXT("Measured leaf receives exact stretched width"), State.LastWidthMode, YGMeasureModeExactly);
    TestFalse(TEXT("Measured width is defined"), YGFloatIsUndefined(YGNodeLayoutGetWidth(Leaf)));
    TestFalse(TEXT("Measured height is defined"), YGFloatIsUndefined(YGNodeLayoutGetHeight(Leaf)));
    TestEqual(TEXT("Measured leaf layout width is constrained"), YGNodeLayoutGetWidth(Leaf), 300.0f);
    TestEqual(TEXT("Measured leaf initial height"), YGNodeLayoutGetHeight(Leaf), 24.0f);

    State.DesiredHeight = 64.0f;
    YGNodeMarkDirty(Leaf);
    TestTrue(TEXT("Explicit measured-content change dirties leaf"), YGNodeIsDirty(Leaf));
    YGNodeCalculateLayout(Tree.Root, 320.0f, YGUndefined, YGDirectionLTR);
    TestTrue(TEXT("Dirty measured leaf remeasured"), State.CallCount > InitialMeasureCalls);
    TestFalse(TEXT("Remeasured height is defined"), YGFloatIsUndefined(YGNodeLayoutGetHeight(Leaf)));
    TestEqual(TEXT("Explicit dirty remeasure updates height"), YGNodeLayoutGetHeight(Leaf), 64.0f);
    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
