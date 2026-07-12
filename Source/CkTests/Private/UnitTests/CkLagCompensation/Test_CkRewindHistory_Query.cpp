// C++ unit tests for the lag-compensation rewind query layer — ring buffer, frame interpolation,
// and the analytic rewind sweeps. All headless: these types are deliberately world-free so the
// hit-validation math is testable (and deterministic) without a physics engine.
//
// Surface in Session Frontend: CkTests.UnitTests.CkLagCompensation.RewindQuery.<scenario>

#include "Misc/AutomationTest.h"

#include "CkLagCompensation/RewindHistory/CkRewindHistory_Query.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_tests_rewind
{
    inline auto Make_SphereSnapshot(const FVector& InCenter, double InRadius) -> FCk_LagComp_HitShapeSnapshot
    {
        return FCk_LagComp_HitShapeSnapshot{
            FGameplayTag::EmptyTag,
            FCk_AnyShape{FCk_ShapeSphere_Dimensions{static_cast<float>(InRadius)}},
            FTransform{InCenter}};
    }

    inline auto Make_SphereFrame(double InTime, const FVector& InCenter, double InRadius) -> FCk_LagComp_RewindFrame
    {
        auto Snapshot = Make_SphereSnapshot(InCenter, InRadius);
        const auto Bounds = ck::lag_comp::Get_SnapshotWorldBounds(Snapshot);

        return FCk_LagComp_RewindFrame{FCk_Time{InTime}, TArray{Snapshot}, Bounds};
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_RewindQuery_RingBufferWraparound,
    "CkTests.UnitTests.CkLagCompensation.RewindQuery.RingBufferWraparound",
    kCkUnitTestFlags)

bool FCkTest_RewindQuery_RingBufferWraparound::RunTest(const FString& Parameters)
{
    auto Buffer = FCk_LagComp_FrameBuffer{};
    Buffer.Init(4);

    for (auto Index = 0; Index < 10; ++Index)
    {
        Buffer.Push(ck_tests_rewind::Make_SphereFrame(Index * 0.1, FVector{Index * 100.0, 0.0, 0.0}, 50.0));
    }

    TestEqual(TEXT("Count saturates at capacity"), Buffer.Get_Count(), 4);
    TestEqual(TEXT("Oldest frame is the 7th pushed (t=0.6)"),
        Buffer.Get_FrameAt(0).Get_WorldTime().Get_Seconds(), 0.6);
    TestEqual(TEXT("Newest frame is the 10th pushed (t=0.9)"),
        Buffer.Get_FrameAt(3).Get_WorldTime().Get_Seconds(), 0.9);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_RewindQuery_InterpolationBetweenFrames,
    "CkTests.UnitTests.CkLagCompensation.RewindQuery.InterpolationBetweenFrames",
    kCkUnitTestFlags)

bool FCkTest_RewindQuery_InterpolationBetweenFrames::RunTest(const FString& Parameters)
{
    auto Buffer = FCk_LagComp_FrameBuffer{};
    Buffer.Init(8);
    Buffer.Push(ck_tests_rewind::Make_SphereFrame(1.0, FVector{0.0, 0.0, 0.0}, 50.0));
    Buffer.Push(ck_tests_rewind::Make_SphereFrame(2.0, FVector{100.0, 0.0, 0.0}, 50.0));

    const auto Snapshots = ck::lag_comp::Get_InterpolatedSnapshots(Buffer, FCk_Time{1.5});

    if (Snapshots.Num() != 1)
    {
        AddError(TEXT("Expected exactly one interpolated snapshot"));
        return false;
    }

    TestTrue(TEXT("Position halfway between frames is the midpoint"),
        Snapshots[0].Get_WorldTransform().GetLocation().Equals(FVector{50.0, 0.0, 0.0}, 0.01));

    const auto Clamped = ck::lag_comp::Get_InterpolatedSnapshots(Buffer, FCk_Time{0.5});
    TestTrue(TEXT("Time before the recorded window clamps to the oldest pose"),
        Clamped[0].Get_WorldTransform().GetLocation().Equals(FVector::ZeroVector, 0.01));

    const auto TooFewFrames = FCk_LagComp_FrameBuffer{};
    TestEqual(TEXT("An empty buffer interpolates to nothing"),
        ck::lag_comp::Get_InterpolatedSnapshots(TooFewFrames, FCk_Time{1.0}).Num(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_RewindQuery_SweepHitsPastPoseNotPresent,
    "CkTests.UnitTests.CkLagCompensation.RewindQuery.SweepHitsPastPoseNotPresent",
    kCkUnitTestFlags)

bool FCkTest_RewindQuery_SweepHitsPastPoseNotPresent::RunTest(const FString& Parameters)
{
    // Target sphere (r=50) sat at X=0 around t=1, then strafed to Y=500 by t=2
    auto Buffer = FCk_LagComp_FrameBuffer{};
    Buffer.Init(8);
    Buffer.Push(ck_tests_rewind::Make_SphereFrame(0.9, FVector{0.0, 0.0, 0.0}, 50.0));
    Buffer.Push(ck_tests_rewind::Make_SphereFrame(1.1, FVector{0.0, 0.0, 0.0}, 50.0));
    Buffer.Push(ck_tests_rewind::Make_SphereFrame(1.9, FVector{0.0, 500.0, 0.0}, 50.0));
    Buffer.Push(ck_tests_rewind::Make_SphereFrame(2.1, FVector{0.0, 500.0, 0.0}, 50.0));

    const auto SegmentStart = FVector{-200.0, 0.0, 0.0};
    const auto SegmentEnd = FVector{200.0, 0.0, 0.0};

    // Shot fired through the OLD position during [0.95, 1.05] — must hit
    const auto PastHit = ck::lag_comp::Sweep_SegmentVsHistory(
        Buffer, SegmentStart, SegmentEnd, FCk_Time{0.95}, FCk_Time{1.05}, 5.0);

    TestTrue(TEXT("Sweep through the rewound pose registers a hit"), PastHit.IsSet());

    if (PastHit.IsSet())
    {
        // Entry point of a ray from -X into a 50+5 sphere at origin is x=-55
        TestTrue(TEXT("Hit location is at the inflated sphere entry point"),
            PastHit->Get_HitLocation().Equals(FVector{-55.0, 0.0, 0.0}, 1.0));
        TestTrue(TEXT("Hit normal faces the shooter"),
            PastHit->Get_HitNormal().Equals(FVector{-1.0, 0.0, 0.0}, 0.01));
        TestTrue(TEXT("Hit time falls inside the swept slice"),
            PastHit->Get_HitWorldTime().Get_Seconds() > 0.95 && PastHit->Get_HitWorldTime().Get_Seconds() < 1.05);
    }

    // The same shot evaluated at t≈2 (target has strafed away) — must miss
    const auto PresentMiss = ck::lag_comp::Sweep_SegmentVsHistory(
        Buffer, SegmentStart, SegmentEnd, FCk_Time{1.95}, FCk_Time{2.05}, 5.0);

    TestFalse(TEXT("Sweep through the old position at the new time misses"), PresentMiss.IsSet());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_RewindQuery_SweepCompensatesTargetMotion,
    "CkTests.UnitTests.CkLagCompensation.RewindQuery.SweepCompensatesTargetMotion",
    kCkUnitTestFlags)

bool FCkTest_RewindQuery_SweepCompensatesTargetMotion::RunTest(const FString& Parameters)
{
    // Target moves +Y at 1000 cm/s through the slice; the projectile aims where the target will
    // be mid-slice. The relative-motion solve must register the crossing
    auto Buffer = FCk_LagComp_FrameBuffer{};
    Buffer.Init(8);
    Buffer.Push(ck_tests_rewind::Make_SphereFrame(1.0, FVector{300.0, 0.0, 0.0}, 50.0));
    Buffer.Push(ck_tests_rewind::Make_SphereFrame(1.1, FVector{300.0, 100.0, 0.0}, 50.0));

    // Projectile crosses X=300 at slice-midpoint, aimed at Y=50 — exactly where the target is then
    const auto Hit = ck::lag_comp::Sweep_SegmentVsHistory(
        Buffer, FVector{0.0, 50.0, 0.0}, FVector{600.0, 50.0, 0.0}, FCk_Time{1.0}, FCk_Time{1.1}, 5.0);

    TestTrue(TEXT("Lead shot on a strafing target connects via relative-motion sweep"), Hit.IsSet());

    // A shot aimed at where the target USED to be (Y=0) while it moves away should still clip it
    // early in the slice but a shot well behind its path (Y=-200) must miss
    const auto Miss = ck::lag_comp::Sweep_SegmentVsHistory(
        Buffer, FVector{0.0, -200.0, 0.0}, FVector{600.0, -200.0, 0.0}, FCk_Time{1.0}, FCk_Time{1.1}, 5.0);

    TestFalse(TEXT("Shot far behind the strafing target misses"), Miss.IsSet());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_RewindQuery_SweepShapes,
    "CkTests.UnitTests.CkLagCompensation.RewindQuery.SweepShapes",
    kCkUnitTestFlags)

bool FCkTest_RewindQuery_SweepShapes::RunTest(const FString& Parameters)
{
    const auto SegmentStart = FVector{-300.0, 0.0, 0.0};
    const auto SegmentEnd = FVector{300.0, 0.0, 0.0};
    constexpr auto SweepRadius = 0.0;

    // Capsule standing upright at the origin (half-height 100, radius 30): ray along X hits at x=-30
    const auto CapsuleSnapshot = FCk_LagComp_HitShapeSnapshot{
        FGameplayTag::EmptyTag,
        FCk_AnyShape{FCk_ShapeCapsule_Dimensions{100.0f, 30.0f}},
        FTransform::Identity};

    const auto CapsuleHit = ck::lag_comp::Sweep_SegmentVsSnapshot(
        SegmentStart, SegmentEnd, SweepRadius, CapsuleSnapshot, CapsuleSnapshot);

    TestTrue(TEXT("Ray hits the upright capsule"), CapsuleHit.IsSet());
    if (CapsuleHit.IsSet())
    {
        TestTrue(TEXT("Capsule hit at the cylinder wall (x=-30)"),
            CapsuleHit->_Location.Equals(FVector{-30.0, 0.0, 0.0}, 0.5));
    }

    // Ray above the capsule's top cap must miss
    const auto CapsuleMiss = ck::lag_comp::Sweep_SegmentVsSnapshot(
        SegmentStart + FVector{0.0, 0.0, 150.0}, SegmentEnd + FVector{0.0, 0.0, 150.0},
        SweepRadius, CapsuleSnapshot, CapsuleSnapshot);

    TestFalse(TEXT("Ray above the capsule misses"), CapsuleMiss.IsSet());

    // Box rotated 45° about Z, half-extents 50: ray along X hits the rotated face
    const auto BoxSnapshot = FCk_LagComp_HitShapeSnapshot{
        FGameplayTag::EmptyTag,
        FCk_AnyShape{FCk_ShapeBox_Dimensions{FVector{50.0}}},
        FTransform{FRotator{0.0, 45.0, 0.0}, FVector::ZeroVector}};

    const auto BoxHit = ck::lag_comp::Sweep_SegmentVsSnapshot(
        SegmentStart, SegmentEnd, SweepRadius, BoxSnapshot, BoxSnapshot);

    TestTrue(TEXT("Ray hits the rotated box"), BoxHit.IsSet());
    if (BoxHit.IsSet())
    {
        // Corner-on: the diagonal half-width is 50·√2 ≈ 70.7
        TestTrue(TEXT("Rotated box entry at the corner distance"),
            FMath::IsNearlyEqual(BoxHit->_Location.X, -70.7, 1.0));
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_RewindQuery_AncientTimesRejected,
    "CkTests.UnitTests.CkLagCompensation.RewindQuery.AncientTimesRejected",
    kCkUnitTestFlags)

bool FCkTest_RewindQuery_AncientTimesRejected::RunTest(const FString& Parameters)
{
    auto Buffer = FCk_LagComp_FrameBuffer{};
    Buffer.Init(8);
    Buffer.Push(ck_tests_rewind::Make_SphereFrame(10.0, FVector{0.0, 0.0, 0.0}, 50.0));
    Buffer.Push(ck_tests_rewind::Make_SphereFrame(10.1, FVector{0.0, 0.0, 0.0}, 50.0));
    Buffer.Push(ck_tests_rewind::Make_SphereFrame(10.2, FVector{0.0, 0.0, 0.0}, 50.0));

    TestEqual(TEXT("A time more than one frame interval before the oldest frame interpolates to nothing"),
        ck::lag_comp::Get_InterpolatedSnapshots(Buffer, FCk_Time{9.5}).Num(), 0);

    TestEqual(TEXT("A time within one frame interval of the oldest frame still clamps to the oldest pose"),
        ck::lag_comp::Get_InterpolatedSnapshots(Buffer, FCk_Time{9.95}).Num(), 1);

    TestEqual(TEXT("A time after the newest frame clamps to the newest pose"),
        ck::lag_comp::Get_InterpolatedSnapshots(Buffer, FCk_Time{25.0}).Num(), 1);

    // The sweep must refuse to manufacture hits in the pre-history era: this segment passes dead
    // through where the sphere has ALWAYS been, but the requested window predates the buffer
    const auto AncientHit = ck::lag_comp::Sweep_SegmentVsHistory(
        Buffer, FVector{-200.0, 0.0, 0.0}, FVector{200.0, 0.0, 0.0},
        FCk_Time{5.0}, FCk_Time{5.1}, 5.0);
    TestFalse(TEXT("Sweep in the pre-history era does not hit"), AncientHit.IsSet());

    const auto RecordedHit = ck::lag_comp::Sweep_SegmentVsHistory(
        Buffer, FVector{-200.0, 0.0, 0.0}, FVector{200.0, 0.0, 0.0},
        FCk_Time{10.05}, FCk_Time{10.15}, 5.0);
    TestTrue(TEXT("The same sweep inside the recorded window hits"), RecordedHit.IsSet());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
