#include "Misc/AutomationTest.h"

#include "CkPathNetwork/Network/CkPathNetwork_PathSimplify.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_pathnetwork_path_simplify
{
    auto
    MakePath(std::initializer_list<FVector> InPoints) -> TArray<FVector>
    {
        return TArray<FVector>{InPoints};
    }

    auto
    TestSamePath(
        FAutomationTestBase& InTest,
        const TArray<FVector>& InActual,
        const TArray<FVector>& InExpected,
        const FString& InLabel) -> bool
    {
        if (NOT InTest.TestEqual(InLabel + TEXT(" count"), InActual.Num(), InExpected.Num()))
        { return false; }

        for (auto Index = 0; Index < InExpected.Num(); ++Index)
        {
            if (NOT InTest.TestTrue(
                    FString::Printf(TEXT("%s point %d"), *InLabel, Index),
                    InActual[Index].Equals(InExpected[Index], KINDA_SMALL_NUMBER)))
            { return false; }
        }

        return true;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_PathSimplify_IsTotalForSmallInputs,
    "Ck.PathNetwork.PathSimplify.IsTotalForSmallInputs",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_PathSimplify_IsTotalForSmallInputs::RunTest(const FString& Parameters)
{
    using namespace ck_test_pathnetwork_path_simplify;

    const auto AlwaysTraversable = [](const FVector&, const FVector&) { return true; };
    const auto Empty = MakePath({});
    const auto Single = MakePath({FVector{25, 50, 75}});
    const auto Pair = MakePath({FVector{0, 0, 0}, FVector{100, 0, 0}});

    return
        TestSamePath(
            *this,
            ck::pathnetwork::Simplify_PathByTraversal(Empty, AlwaysTraversable, 0.0f),
            Empty,
            TEXT("empty input")) &&
        TestSamePath(
            *this,
            ck::pathnetwork::Simplify_PathByTraversal(Single, AlwaysTraversable, 0.0f),
            Single,
            TEXT("single-point input")) &&
        TestSamePath(
            *this,
            ck::pathnetwork::Simplify_PathByTraversal(Pair, AlwaysTraversable, 0.0f),
            Pair,
            TEXT("two-point input"));
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_PathSimplify_RemovesIsolatedLateralJuts,
    "Ck.PathNetwork.PathSimplify.RemovesIsolatedLateralJuts",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_PathSimplify_RemovesIsolatedLateralJuts::RunTest(const FString& Parameters)
{
    using namespace ck_test_pathnetwork_path_simplify;

    const auto Path = MakePath({
        FVector{0, 0, 0},
        FVector{100, 50, 0},
        FVector{200, -50, 0},
        FVector{300, 0, 0}});
    const auto Simplified = ck::pathnetwork::Simplify_PathByTraversal(
        Path,
        [](const FVector&, const FVector&) { return true; },
        1.0f);

    return TestSamePath(
        *this,
        Simplified,
        MakePath({FVector{0, 0, 0}, FVector{300, 0, 0}}),
        TEXT("visible lateral juts collapse"));
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_PathSimplify_PreservesObstacleCorner,
    "Ck.PathNetwork.PathSimplify.PreservesObstacleCorner",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_PathSimplify_PreservesObstacleCorner::RunTest(const FString& Parameters)
{
    using namespace ck_test_pathnetwork_path_simplify;

    const auto Path = MakePath({
        FVector{0, 0, 0},
        FVector{100, 0, 0},
        FVector{100, 100, 0},
        FVector{200, 100, 0}});
    const auto Simplified = ck::pathnetwork::Simplify_PathByTraversal(
        Path,
        [](const FVector& InFrom, const FVector& InTo)
        {
            return
                InFrom.Equals(FVector{0, 0, 0}) && InTo.Equals(FVector{100, 0, 0}) ||
                InFrom.Equals(FVector{100, 0, 0}) && InTo.Equals(FVector{100, 100, 0}) ||
                InFrom.Equals(FVector{100, 100, 0}) && InTo.Equals(FVector{200, 100, 0});
        },
        1.0f);

    return TestSamePath(*this, Simplified, Path, TEXT("required obstacle corner remains"));
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_PathSimplify_PreservesVerticalProfile,
    "Ck.PathNetwork.PathSimplify.PreservesVerticalProfile",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_PathSimplify_PreservesVerticalProfile::RunTest(const FString& Parameters)
{
    using namespace ck_test_pathnetwork_path_simplify;

    const auto Path = MakePath({
        FVector{0, 0, 0},
        FVector{100, 0, 100},
        FVector{200, 0, 0}});
    const auto Simplified = ck::pathnetwork::Simplify_PathByTraversal(
        Path,
        [](const FVector&, const FVector&) { return true; },
        10.0f);

    return TestSamePath(*this, Simplified, Path, TEXT("ramp summit remains"));
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_PathSimplify_PreservesEndpointsAndOrder,
    "Ck.PathNetwork.PathSimplify.PreservesEndpointsAndOrder",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_PathSimplify_PreservesEndpointsAndOrder::RunTest(const FString& Parameters)
{
    using namespace ck_test_pathnetwork_path_simplify;

    const auto Path = MakePath({
        FVector{0, 0, 0},
        FVector{100, 0, 0},
        FVector{200, 0, 0},
        FVector{300, 0, 0}});
    const auto Simplified = ck::pathnetwork::Simplify_PathByTraversal(
        Path,
        [](const FVector& InFrom, const FVector& InTo)
        {
            return FVector::DistSquared(InFrom, InTo) <= FMath::Square(100.0f);
        },
        0.0f);

    return TestSamePath(*this, Simplified, Path, TEXT("ordered adjacent-only route"));
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_PathNetwork_PathSimplify_InvalidToleranceReturnsInput,
    "Ck.PathNetwork.PathSimplify.InvalidToleranceReturnsInput",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCk_PathNetwork_PathSimplify_InvalidToleranceReturnsInput::RunTest(const FString& Parameters)
{
    using namespace ck_test_pathnetwork_path_simplify;

    const auto Path = MakePath({
        FVector{0, 0, 0},
        FVector{100, 50, 0},
        FVector{200, 0, 0}});
    auto CallbackWasInvoked = false;
    const auto Simplified = ck::pathnetwork::Simplify_PathByTraversal(
        Path,
        [&CallbackWasInvoked](const FVector&, const FVector&)
        {
            CallbackWasInvoked = true;
            return true;
        },
        -1.0f);

    TestFalse(TEXT("invalid tolerance never evaluates visibility"), CallbackWasInvoked);
    return TestSamePath(*this, Simplified, Path, TEXT("invalid tolerance preserves input"));
}

// --------------------------------------------------------------------------------------------------------------------
