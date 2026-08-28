// Pure C++ coverage for the OBB-to-wall contract used by crowd avoidance volumes. These
// assertions deliberately need no ECS world, probes, or processors; runtime overlap discovery is
// covered separately by the Crowd AutoTests.

#include <limits>

#include "CkCrowd/Agent/CkCrowdAgent_AvoidanceSample_Algorithm.h"
#include "CkCrowd/AvoidanceVolume/CkCrowdAvoidanceVolume_Algorithm.h"
#include "CkCrowd/AvoidanceVolume/CkCrowdAvoidanceVolume_Fragment.h"
#include "CkCrowd/AvoidanceVolume/CkCrowdAvoidanceVolume_Utils.h"

#include "CkCore/Validation/CkIsValid.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Handle/CkHandle_Utils.h"
#include "CkEcs/World/CkEcsWorld.h"
#include "CkEcsExt/Transform/CkTransform_Utils.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_tests_crowd_avoidance_volume
{
    using ck::ck_crowd_agent_avoidance_sample_algorithm::BuildAvoidanceVolumeWalls;
    using ck::ck_crowd_agent_avoidance_sample_algorithm::Dot2D;
    using ck::ck_crowd_agent_avoidance_sample_algorithm::MakeWallOutwardNormal;
    using ck::crowd_avoidance_volume::ContainsPoint;
    using ck::crowd_avoidance_volume::FindNearestFaceEscapePoint;
    using ck::crowd_avoidance_volume::FindRayExitPoint;
    using ck::crowd_avoidance_volume::GetSegmentInsideInterval;
    using ck::crowd_avoidance_volume::IntersectsSegment;
    using ck::crowd_avoidance_volume::MakeEffectiveAgentObb;
    using ck::crowd_avoidance_volume::MakeObb;
    using ck::FCk_CrowdAvoidanceVolume_Obstacle;

    auto MakeObstacle(
        const FVector& InLocation,
        const FVector& InHalfExtents,
        const FRotator& InRotation = FRotator::ZeroRotator,
        const FVector& InScale = FVector::OneVector) -> FCk_CrowdAvoidanceVolume_Obstacle
    {
        return FCk_CrowdAvoidanceVolume_Obstacle{
            FTransform{InRotation, InLocation, InScale},
            InHalfExtents};
    }

    auto Build(
        const FVector& InAgentPosition,
        const float InAgentRadius,
        const FCk_CrowdAvoidanceVolume_Obstacle& InObstacle)
    {
        const auto Obstacles = TArray<FCk_CrowdAvoidanceVolume_Obstacle>{InObstacle};
        return BuildAvoidanceVolumeWalls(InAgentPosition, InAgentRadius, Obstacles);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_AvoidanceSample_AvoidanceVolume_OutsideBuildsOutwardWalls,
    "CkTests.UnitTests.CkCrowd.AvoidanceSample.AvoidanceVolume.OutsideBuildsOutwardWalls",
    kCkUnitTestFlags)
bool FCkTest_Crowd_AvoidanceSample_AvoidanceVolume_OutsideBuildsOutwardWalls::RunTest(const FString& InParameters)
{
    using namespace ck_tests_crowd_avoidance_volume;

    const auto Centre = FVector{100.0f, 200.0f, 0.0f};
    const auto Built = Build(FVector{400.0f, 200.0f, 0.0f}, 0.0f, MakeObstacle(Centre, FVector{20.0f, 10.0f, 30.0f}));

    TestEqual(TEXT("An outside agent receives all four box faces"), Built._Walls.Num(), 4);
    TestTrue(TEXT("An outside agent has no escape override"), Built._EscapeDirection.IsNearlyZero());
    if (Built._Walls.Num() != 4)
    { return false; }

    TestTrue(TEXT("First wall starts at the positive-X positive-Y corner"),
        Built._Walls[0]._Start.Equals(FVector{120.0f, 210.0f, 0.0f}, 0.001f));
    TestTrue(TEXT("Clockwise winding continues to the positive-X negative-Y corner"),
        Built._Walls[0]._End.Equals(FVector{120.0f, 190.0f, 0.0f}, 0.001f));
    for (const auto& Wall : Built._Walls)
    {
        const auto Midpoint = (Wall._Start + Wall._End) * 0.5f;
        TestTrue(TEXT("Each generated wall normal points away from the OBB centre"),
            Dot2D(MakeWallOutwardNormal(Wall), Midpoint - Centre) > 0.0);
        TestFalse(TEXT("Avoidance-volume walls use their inverse touch blocking convention"),
            Wall._BlocksPositiveNormalAtTouch);
    }
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_AvoidanceVolume_CanonicalObbAppliesScaleOnce,
    "CkTests.UnitTests.CkCrowd.AvoidanceVolume.CanonicalObbAppliesScaleOnce",
    kCkUnitTestFlags)
bool FCkTest_Crowd_AvoidanceVolume_CanonicalObbAppliesScaleOnce::RunTest(const FString& InParameters)
{
    using namespace ck_tests_crowd_avoidance_volume;

    const auto Obb = MakeObb(
        FTransform{FRotator{30.0f, 90.0f, 40.0f}, FVector{100.0f, 200.0f, 300.0f}, FVector{2.0f, 3.0f, 4.0f}},
        FVector{10.0f, 20.0f, 30.0f});

    TestTrue(TEXT("The canonical OBB is valid"), Obb.IsFiniteAndPositive());
    TestTrue(TEXT("Authored non-uniform scale is applied exactly once"),
        Obb._WorldHalfExtents.Equals(FVector{20.0f, 60.0f, 120.0f}, 0.001f));
    TestTrue(TEXT("Canonical OBB strips inherited scale"),
        Obb._YawTransform.GetScale3D().Equals(FVector::OneVector, 0.001f));
    TestTrue(TEXT("Canonical OBB preserves authored location"),
        Obb._YawTransform.GetLocation().Equals(FVector{100.0f, 200.0f, 300.0f}, 0.001f));
    TestTrue(TEXT("Canonical OBB retains yaw only"),
        FMath::IsNearlyEqual(Obb._YawTransform.Rotator().Yaw, 90.0f) &&
        FMath::IsNearlyZero(Obb._YawTransform.Rotator().Pitch) &&
        FMath::IsNearlyZero(Obb._YawTransform.Rotator().Roll));

    const auto Physical = MakeObb(FTransform::Identity, FVector{100.0f});
    const auto Painted = MakeObb(FTransform::Identity, FVector{200.0f, 200.0f, 100.0f});
    const auto Effective = MakeEffectiveAgentObb(Physical, Painted, 20.0f);
    TestTrue(TEXT("Paint clearance wins when it exceeds physical radius expansion"),
        Effective._WorldHalfExtents.Equals(FVector{200.0f, 200.0f, 100.0f}, 0.001f));
    TestTrue(TEXT("An agent in the painted clearance band is treated as inside"),
        ContainsPoint(Effective, FVector{180.0f, 0.0f, 0.0f}));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_AvoidanceVolume_SegmentGeometryIsClosedAtContact,
    "CkTests.UnitTests.CkCrowd.AvoidanceVolume.SegmentGeometryIsClosedAtContact",
    kCkUnitTestFlags)
bool FCkTest_Crowd_AvoidanceVolume_SegmentGeometryIsClosedAtContact::RunTest(const FString& InParameters)
{
    using namespace ck_tests_crowd_avoidance_volume;

    const auto Obb = MakeObb(FTransform::Identity, FVector{10.0f, 20.0f, 30.0f});
    const auto VerticalInterval = GetSegmentInsideInterval(Obb, FVector{0.0f, 0.0f, -40.0f}, FVector{0.0f, 0.0f, 40.0f});
    TestTrue(TEXT("A 3D segment reports its interval through the OBB"), VerticalInterval.IsSet());
    if (VerticalInterval.IsSet())
    {
        TestTrue(TEXT("The 3D interval enters at the lower Z face"), FMath::IsNearlyEqual(VerticalInterval->Key, 0.125f));
        TestTrue(TEXT("The 3D interval exits at the upper Z face"), FMath::IsNearlyEqual(VerticalInterval->Value, 0.875f));
    }

    const auto TangentInterval = GetSegmentInsideInterval(Obb, FVector{-20.0f, 0.0f, 30.0f}, FVector{20.0f, 0.0f, 30.0f});
    TestTrue(TEXT("A segment tangent to the top face remains unsafe"), TangentInterval.IsSet());
    TestTrue(TEXT("A segment above the top face is clear"),
        NOT IntersectsSegment(Obb, FVector{-20.0f, 0.0f, 30.1f}, FVector{20.0f, 0.0f, 30.1f}));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_AvoidanceVolume_InvalidInputsFailClosed,
    "CkTests.UnitTests.CkCrowd.AvoidanceVolume.InvalidInputsFailClosed",
    kCkUnitTestFlags)
bool FCkTest_Crowd_AvoidanceVolume_InvalidInputsFailClosed::RunTest(const FString& InParameters)
{
    using namespace ck_tests_crowd_avoidance_volume;

    const auto NaN = std::numeric_limits<float>::quiet_NaN();
    const auto ValidObb = MakeObb(FTransform::Identity, FVector{10.0f, 20.0f, 30.0f});
    const auto InvalidObb = MakeObb(FTransform::Identity, FVector{NaN, 20.0f, 30.0f});

    TestFalse(TEXT("A non-finite authored extent is invalid"), InvalidObb.IsFiniteAndPositive());
    TestFalse(TEXT("Point containment rejects an invalid OBB"), ContainsPoint(InvalidObb, FVector::ZeroVector));
    TestFalse(TEXT("Segment intersection rejects an invalid OBB"),
        IntersectsSegment(InvalidObb, FVector{-20.0f, 0.0f, 0.0f}, FVector{20.0f, 0.0f, 0.0f}));
    TestFalse(TEXT("A NaN point is not admitted"), ContainsPoint(ValidObb, FVector{NaN, 0.0f, 0.0f}));
    TestFalse(TEXT("A negative expansion radius fails closed"), ValidObb.ExpandedXY(-1.0f).IsFiniteAndPositive());
    TestFalse(TEXT("A non-finite expansion radius fails closed"), ValidObb.ExpandedXY(NaN).IsFiniteAndPositive());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_AvoidanceVolume_EscapeHelpersLeaveTheObb,
    "CkTests.UnitTests.CkCrowd.AvoidanceVolume.EscapeHelpersLeaveTheObb",
    kCkUnitTestFlags)
bool FCkTest_Crowd_AvoidanceVolume_EscapeHelpersLeaveTheObb::RunTest(const FString& InParameters)
{
    using namespace ck_tests_crowd_avoidance_volume;

    const auto Obb = MakeObb(FTransform::Identity, FVector{10.0f, 20.0f, 30.0f});
    const auto NearestFace = FindNearestFaceEscapePoint(Obb, FVector{8.0f, 5.0f, 0.0f}, 2.0f);
    TestTrue(TEXT("Nearest-face escape exists from the OBB interior"), NearestFace.IsSet());
    if (NearestFace.IsSet())
    {
        TestTrue(TEXT("Nearest-face escape uses the nearest positive X face"),
            NearestFace.GetValue().Equals(FVector{12.0f, 5.0f, 0.0f}, 0.001f));
        TestFalse(TEXT("Nearest-face escape is outside the OBB"), ContainsPoint(Obb, NearestFace.GetValue()));
    }

    const auto RayExit = FindRayExitPoint(Obb, FVector::ZeroVector, FVector2D{0.0f, 1.0f}, 2.0f);
    TestTrue(TEXT("Ray escape exists from the OBB interior"), RayExit.IsSet());
    if (RayExit.IsSet())
    {
        TestTrue(TEXT("Ray escape clears the positive Y face by its margin"),
            RayExit.GetValue().Equals(FVector{0.0f, 22.0f, 0.0f}, 0.001f));
        TestFalse(TEXT("Ray escape is outside the OBB"), ContainsPoint(Obb, RayExit.GetValue()));
    }
    TestFalse(TEXT("Nearest-face escape rejects an exterior point"),
        FindNearestFaceEscapePoint(Obb, FVector{11.0f, 0.0f, 0.0f}, 0.0f).IsSet());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_AvoidanceSample_AvoidanceVolume_RotationPreservesObbFaces,
    "CkTests.UnitTests.CkCrowd.AvoidanceSample.AvoidanceVolume.RotationPreservesObbFaces",
    kCkUnitTestFlags)
bool FCkTest_Crowd_AvoidanceSample_AvoidanceVolume_RotationPreservesObbFaces::RunTest(const FString& InParameters)
{
    using namespace ck_tests_crowd_avoidance_volume;

    const auto Built = Build(
        FVector{500.0f, 0.0f, 0.0f},
        0.0f,
        MakeObstacle(FVector::ZeroVector, FVector{40.0f, 10.0f, 30.0f}, FRotator{0.0f, 90.0f, 0.0f}));

    TestEqual(TEXT("A yaw-rotated OBB still produces four faces"), Built._Walls.Num(), 4);
    if (Built._Walls.Num() != 4)
    { return false; }

    TestTrue(TEXT("Yaw rotates the first corner into world negative-X positive-Y"),
        Built._Walls[0]._Start.Equals(FVector{-10.0f, 40.0f, 0.0f}, 0.001f));
    TestTrue(TEXT("Yaw rotates the next clockwise corner into world positive-X positive-Y"),
        Built._Walls[0]._End.Equals(FVector{10.0f, 40.0f, 0.0f}, 0.001f));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_AvoidanceSample_AvoidanceVolume_ScaleAppliedOnce,
    "CkTests.UnitTests.CkCrowd.AvoidanceSample.AvoidanceVolume.ScaleAppliedOnce",
    kCkUnitTestFlags)
bool FCkTest_Crowd_AvoidanceSample_AvoidanceVolume_ScaleAppliedOnce::RunTest(const FString& InParameters)
{
    using namespace ck_tests_crowd_avoidance_volume;

    const auto Built = Build(
        FVector{1000.0f, 0.0f, 0.0f},
        0.0f,
        MakeObstacle(FVector::ZeroVector, FVector{10.0f, 20.0f, 30.0f}, FRotator::ZeroRotator, FVector{2.0f, 3.0f, 4.0f}));

    TestEqual(TEXT("A scaled OBB still produces four faces"), Built._Walls.Num(), 4);
    if (Built._Walls.Num() != 4)
    { return false; }

    TestTrue(TEXT("Scale expands X exactly once"),
        Built._Walls[0]._Start.Equals(FVector{20.0f, 60.0f, 0.0f}, 0.001f));
    TestTrue(TEXT("Scale expands Y exactly once"),
        Built._Walls[0]._End.Equals(FVector{20.0f, -60.0f, 0.0f}, 0.001f));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_AvoidanceSample_AvoidanceVolume_ZSeparatedIgnored,
    "CkTests.UnitTests.CkCrowd.AvoidanceSample.AvoidanceVolume.ZSeparatedIgnored",
    kCkUnitTestFlags)
bool FCkTest_Crowd_AvoidanceSample_AvoidanceVolume_ZSeparatedIgnored::RunTest(const FString& InParameters)
{
    using namespace ck_tests_crowd_avoidance_volume;

    const auto Built = Build(
        FVector{100.0f, 0.0f, 31.0f},
        10.0f,
        MakeObstacle(FVector::ZeroVector, FVector{20.0f, 20.0f, 30.0f}));

    TestEqual(TEXT("An agent outside the OBB vertical span receives no horizontal walls"), Built._Walls.Num(), 0);
    TestTrue(TEXT("A Z-separated OBB does not request an escape"), Built._EscapeDirection.IsNearlyZero());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_AvoidanceSample_AvoidanceVolume_AgentRadiusInflatesFootprint,
    "CkTests.UnitTests.CkCrowd.AvoidanceSample.AvoidanceVolume.AgentRadiusInflatesFootprint",
    kCkUnitTestFlags)
bool FCkTest_Crowd_AvoidanceSample_AvoidanceVolume_AgentRadiusInflatesFootprint::RunTest(const FString& InParameters)
{
    using namespace ck_tests_crowd_avoidance_volume;

    const auto Built = Build(
        FVector{100.0f, 0.0f, 0.0f},
        5.0f,
        MakeObstacle(FVector::ZeroVector, FVector{10.0f, 20.0f, 30.0f}));

    TestEqual(TEXT("An inflated footprint still produces four faces"), Built._Walls.Num(), 4);
    if (Built._Walls.Num() != 4)
    { return false; }

    TestTrue(TEXT("Agent radius expands the physical X extent"),
        Built._Walls[0]._Start.Equals(FVector{15.0f, 25.0f, 0.0f}, 0.001f));
    TestTrue(TEXT("Agent radius expands the physical Y extent"),
        Built._Walls[0]._End.Equals(FVector{15.0f, -25.0f, 0.0f}, 0.001f));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_AvoidanceSample_AvoidanceVolume_InsideEscapesNearestFace,
    "CkTests.UnitTests.CkCrowd.AvoidanceSample.AvoidanceVolume.InsideEscapesNearestFace",
    kCkUnitTestFlags)
bool FCkTest_Crowd_AvoidanceSample_AvoidanceVolume_InsideEscapesNearestFace::RunTest(const FString& InParameters)
{
    using namespace ck_tests_crowd_avoidance_volume;

    const auto Built = Build(
        FVector{8.0f, 5.0f, 0.0f},
        0.0f,
        MakeObstacle(FVector::ZeroVector, FVector{10.0f, 20.0f, 30.0f}));

    TestEqual(TEXT("An inside agent does not score inward box walls"), Built._Walls.Num(), 0);
    TestTrue(TEXT("An inside agent receives a nonzero escape direction"), Built._EscapeDirection.SizeSquared2D() > 0.0f);
    TestTrue(TEXT("The nearest X face supplies the escape direction"),
        Built._EscapeDirection.Equals(FVector::ForwardVector, 0.001f));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_AvoidanceSample_AvoidanceVolume_ContactRetainsWalls,
    "CkTests.UnitTests.CkCrowd.AvoidanceSample.AvoidanceVolume.ContactRetainsWalls",
    kCkUnitTestFlags)
bool FCkTest_Crowd_AvoidanceSample_AvoidanceVolume_ContactRetainsWalls::RunTest(const FString& InParameters)
{
    using namespace ck_tests_crowd_avoidance_volume;

    const auto Built = Build(
        FVector{10.0f, 0.0f, 0.0f},
        0.0f,
        MakeObstacle(FVector::ZeroVector, FVector{10.0f, 20.0f, 30.0f}));

    TestEqual(TEXT("Exact boundary contact retains the wall contract instead of producing an empty result"),
        Built._Walls.Num(), 4);
    TestTrue(TEXT("Exact boundary contact does not request a contradictory escape direction"),
        Built._EscapeDirection.IsNearlyZero());
    if (Built._Walls.Num() == 4)
    {
        TestTrue(TEXT("The contacted face is marked touching"), Built._Walls[0]._Touching);
        TestFalse(TEXT("The contacted volume face lets positive-normal motion escape"),
            Built._Walls[0]._BlocksPositiveNormalAtTouch);
    }
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_AvoidanceVolume_TraversalPoliciesBuildPhaseOverlays,
    "CkTests.UnitTests.CkCrowd.AvoidanceVolume.TraversalPolicies.BuildPhaseOverlays",
    kCkUnitTestFlags)
bool FCkTest_Crowd_AvoidanceVolume_TraversalPoliciesBuildPhaseOverlays::RunTest(const FString& InParameters)
{
    const auto DefaultParams = FCk_Fragment_CrowdAvoidanceVolume_ParamsData{};
    TestEqual(TEXT("AvoidIfPossible remains the authored default"),
        DefaultParams.Get_TraversalPolicy(), ECk_CrowdAvoidanceVolume_TraversalPolicy::AvoidIfPossible);

    TestTrue(TEXT("strict excludes AvoidIfPossible"),
        UCk_Utils_CrowdAvoidanceVolume_UE::Get_IsTraversalPolicyExcluded(
            ECk_CrowdAvoidanceVolume_TraversalPolicy::AvoidIfPossible,
            ECk_CrowdAvoidanceVolume_QueryPhase::Strict));
    TestTrue(TEXT("strict excludes HardExclude"),
        UCk_Utils_CrowdAvoidanceVolume_UE::Get_IsTraversalPolicyExcluded(
            ECk_CrowdAvoidanceVolume_TraversalPolicy::HardExclude,
            ECk_CrowdAvoidanceVolume_QueryPhase::Strict));
    TestFalse(TEXT("strict keeps CostOnly traversable"),
        UCk_Utils_CrowdAvoidanceVolume_UE::Get_IsTraversalPolicyExcluded(
            ECk_CrowdAvoidanceVolume_TraversalPolicy::CostOnly,
            ECk_CrowdAvoidanceVolume_QueryPhase::Strict));
    TestTrue(TEXT("permissive still excludes HardExclude"),
        UCk_Utils_CrowdAvoidanceVolume_UE::Get_IsTraversalPolicyExcluded(
            ECk_CrowdAvoidanceVolume_TraversalPolicy::HardExclude,
            ECk_CrowdAvoidanceVolume_QueryPhase::Permissive));
    TestFalse(TEXT("permissive allows AvoidIfPossible"),
        UCk_Utils_CrowdAvoidanceVolume_UE::Get_IsTraversalPolicyExcluded(
            ECk_CrowdAvoidanceVolume_TraversalPolicy::AvoidIfPossible,
            ECk_CrowdAvoidanceVolume_QueryPhase::Permissive));
    TestFalse(TEXT("permissive allows CostOnly"),
        UCk_Utils_CrowdAvoidanceVolume_UE::Get_IsTraversalPolicyExcluded(
            ECk_CrowdAvoidanceVolume_TraversalPolicy::CostOnly,
            ECk_CrowdAvoidanceVolume_QueryPhase::Permissive));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_AvoidanceVolume_DebugSnapshots_AreCopiedAndPendingWithoutRecast,
    "CkTests.UnitTests.CkCrowd.AvoidanceVolume.DebugSnapshots.CopiedAndPendingWithoutRecast",
    kCkUnitTestFlags)
bool FCkTest_Crowd_AvoidanceVolume_DebugSnapshots_AreCopiedAndPendingWithoutRecast::RunTest(const FString& InParameters)
{
    auto EcsWorld = ck::FEcsWorld{};
    auto& Registry = EcsWorld.Get_Registry();
    auto Selector = FCk_Handle{Registry.Get_TransientEntity(), Registry.Get_RegistryHandle()};

    TestTrue(TEXT("An invalid world selector produces no debug snapshots"),
        UCk_Utils_CrowdAvoidanceVolume_UE::Get_DebugSnapshots(FCk_Handle{}).IsEmpty());

    auto Volume = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Selector, {});
    if (NOT TestTrue(TEXT("fixture created a volume entity"), ck::IsValid(Volume)))
    { return false; }

    const auto AuthoredTransform = FTransform{
        FRotator{30.0f, 90.0f, 40.0f}, FVector{100.0f, 200.0f, 300.0f}, FVector{2.0f, 3.0f, 4.0f}};
    const auto VolumeTransform = UCk_Utils_Transform_UE::Add(
        Volume, AuthoredTransform, ECk_Replication::DoesNotReplicate);
    if (NOT TestTrue(TEXT("fixture added a volume transform"), ck::IsValid(VolumeTransform)))
    { return false; }

    UCk_Utils_Handle_UE::Set_DebugName(Volume, TEXT("SnapshotVolume"));
    auto Params = FCk_Fragment_CrowdAvoidanceVolume_ParamsData{};
    Params.Set_HalfExtents(FVector{10.0f, 20.0f, 30.0f});
    Params.Set_InfluenceRange(25.0f);
    Params.Set_PathPlanningClearance(15.0f);
    Params.Set_TraversalPolicy(ECk_CrowdAvoidanceVolume_TraversalPolicy::HardExclude);
    Volume.Add<ck::FFragment_CrowdAvoidanceVolume_Params>(Params);
    Volume.Add<ck::FFragment_CrowdAvoidanceVolume_ProbeRef>();
    Volume.Add<ck::FTag_CrowdAvoidanceVolume_NeedsSetup>();

    const auto Snapshots = UCk_Utils_CrowdAvoidanceVolume_UE::Get_DebugSnapshots(Selector);
    if (NOT TestEqual(TEXT("one pending volume is collected without Recast"), Snapshots.Num(), 1))
    { return false; }

    const auto Snapshot = Snapshots[0];
    TestEqual(TEXT("the copied identity is the live entity identity"),
        Snapshot.Get_VolumeIdentity(), static_cast<int64>(Volume.Get_Entity().Get_ID()));
    TestEqual(TEXT("the copied debug name is not a handle reference"),
        Snapshot.Get_VolumeDebugName(), FName{TEXT("SnapshotVolume")});
    TestEqual(TEXT("pending setup is reported before any nav-area paint"),
        Snapshot.Get_State(), ECk_CrowdAvoidanceVolume_DebugState::PendingSetup);
    TestEqual(TEXT("the authored traversal policy is copied into the detached snapshot"),
        Snapshot.Get_TraversalPolicy(), ECk_CrowdAvoidanceVolume_TraversalPolicy::HardExclude);
    TestTrue(TEXT("scaled pending geometry is safe to render"), Snapshot.Get_HasValidGeometry());
    TestTrue(TEXT("the copied yaw transform retains location"),
        Snapshot.Get_YawWorldTransform().GetLocation().Equals(FVector{100.0f, 200.0f, 300.0f}, 0.001f));
    TestTrue(TEXT("the copied yaw transform strips pitch, roll, and scale"),
        FMath::IsNearlyEqual(Snapshot.Get_YawWorldTransform().Rotator().Yaw, 90.0f) &&
        FMath::IsNearlyZero(Snapshot.Get_YawWorldTransform().Rotator().Pitch) &&
        FMath::IsNearlyZero(Snapshot.Get_YawWorldTransform().Rotator().Roll) &&
        Snapshot.Get_YawWorldTransform().GetScale3D().Equals(FVector::OneVector, 0.001f));
    TestTrue(TEXT("physical world half extents apply authored scale once"),
        Snapshot.Get_PhysicalWorldHalfExtents().Equals(FVector{20.0f, 60.0f, 120.0f}, 0.001f));
    TestTrue(TEXT("influence extents expand physical XY only"),
        Snapshot.Get_InfluenceWorldHalfExtents().Equals(FVector{45.0f, 85.0f, 120.0f}, 0.001f));
    TestTrue(TEXT("painted extents apply path clearance to XY only"),
        Snapshot.Get_PaintedWorldHalfExtents().Equals(FVector{35.0f, 75.0f, 120.0f}, 0.001f));

    // The returned DTO must remain usable after the producer no longer exposes its source fragments.
    Volume.Try_Remove<ck::FFragment_CrowdAvoidanceVolume_Params>();
    Volume.Try_Remove<ck::FFragment_CrowdAvoidanceVolume_ProbeRef>();
    Volume.Try_Remove<ck::FFragment_Transform>();
    TestTrue(TEXT("a copied snapshot survives source-fragment teardown"),
        Snapshot.Get_PhysicalWorldHalfExtents().Equals(FVector{20.0f, 60.0f, 120.0f}, 0.001f) &&
        Snapshot.Get_InfluenceWorldHalfExtents().Equals(FVector{45.0f, 85.0f, 120.0f}, 0.001f) &&
        Snapshot.Get_PaintedWorldHalfExtents().Equals(FVector{35.0f, 75.0f, 120.0f}, 0.001f) &&
        Snapshot.Get_State() == ECk_CrowdAvoidanceVolume_DebugState::PendingSetup &&
        Snapshot.Get_TraversalPolicy() == ECk_CrowdAvoidanceVolume_TraversalPolicy::HardExclude);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
