#include "CkGroundNav/Path/CkGroundNavPath_Fragment_Data.h"
#include "CkGroundNav/Path/CkGroundNavPath_Fragment.h"
#include "CkGroundNav/Path/CkGroundNavPath_Processor.h"
#include "CkGroundNav/Path/CkGroundNavPath_Utils.h"
#include "CkGroundNav/Query/CkGroundNav_Query_DynamicObstacles.h"

#include "CkCore/Time/CkTime.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/World/CkEcsWorld.h"

#include "CkGroundNav/Facade/CkGroundNav_WorldFieldRegistry.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"

#include "../CkUnitTest_Common.h"

#include "Test_GroundNav_QueryFixtures.h"

#include <limits>

#include <Engine/World.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_dynamic_path_request
{
    using ck::groundnav::ECk_GroundNav_PathRouteKind;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldPtr;

    using ck_test_groundnav_queryfixtures::Bake;
    using ck_test_groundnav_queryfixtures::kGroundZ;
    using ck_test_groundnav_queryfixtures::kStepHeight;
    using ck_test_groundnav_queryfixtures::kTwoRouteGoal;
    using ck_test_groundnav_queryfixtures::kTwoRouteStart;
    using ck_test_groundnav_queryfixtures::Make_QueryParams;
    using ck_test_groundnav_queryfixtures::Make_TwoRouteScene;

    constexpr auto kSixtyHertz = 1.0 / 60.0;
    constexpr auto kMaxTicks = 4096;
    constexpr auto kAgentRadiusUu = 20.0f;
    constexpr auto kInformEngineOfWorld = false;

    struct FFixture
    {
        ck::FEcsWorld _EcsWorld;
        UWorld* _World = nullptr;
        FCk_GroundNav_FieldPtr _Field;
        FCk_Handle_GroundNavPath _Path;
    };

    auto Make_PathParams() -> FCk_Fragment_GroundNavPath_ParamsData
    {
        auto Params = FCk_Fragment_GroundNavPath_ParamsData{kAgentRadiusUu};
        Params.Set_VerticalToleranceUu(kStepHeight);
        Params.Set_CornerOffsetK(0.0f);
        return Params;
    }

    auto Do_Setup(FFixture& InOutFixture) -> bool
    {
        auto Field = MakeShared<FCk_GroundNav_Field>();
        if (NOT Bake(Make_TwoRouteScene(), Make_QueryParams(), *Field))
        { return false; }

        InOutFixture._Field = Field;
        InOutFixture._World = UWorld::CreateWorld(
            EWorldType::Game, kInformEngineOfWorld, FName{TEXT("CkGroundNavDynamicPathRequest")});
        if (ck::Is_NOT_Valid(InOutFixture._World))
        { return false; }

        ck::groundnav::world_fields::Publish(
            InOutFixture._World, FCk_Handle{}, InOutFixture._Field, {},
            ck::groundnav::world_fields::FCk_GroundNav_PublishClaim::Geometry());

        auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(
            InOutFixture._EcsWorld.Get_Registry());
        Owner.Add<TWeakObjectPtr<UWorld>>(InOutFixture._World);
        InOutFixture._Path = UCk_Utils_GroundNavPath_UE::Add(Owner, Make_PathParams());
        return ck::IsValid(InOutFixture._Path);
    }

    auto Do_Teardown(FFixture& InOutFixture) -> void
    {
        if (ck::Is_NOT_Valid(InOutFixture._World))
        { return; }

        InOutFixture._World->DestroyWorld(kInformEngineOfWorld);
        InOutFixture._World = nullptr;
    }

    auto Do_Drain(FFixture& InOutFixture) -> void
    {
        ck::FProcessor_GroundNavPath_HandleRequests{InOutFixture._EcsWorld.Get_Registry()}.ForEachEntity(
            FCk_Time{kSixtyHertz}, InOutFixture._Path,
            InOutFixture._Path.Get<ck::FFragment_GroundNavPath_Params>(),
            InOutFixture._Path.Get<ck::FFragment_GroundNavPath_Current>(),
            InOutFixture._Path.Get<ck::FFragment_GroundNavPath_Result>(),
            InOutFixture._Path.Get<ck::FFragment_GroundNavPath_Requests>());
    }

    auto Do_RunToPublished(FFixture& InOutFixture) -> bool
    {
        auto Slice = ck::FProcessor_GroundNavPath_Slice{InOutFixture._EcsWorld.Get_Registry()};
        for (auto Tick = 0; Tick < kMaxTicks; ++Tick)
        {
            if (InOutFixture._Path.Get<ck::FFragment_GroundNavPath_Result>().Get_HasFreshResult())
            { return true; }
            Slice.DoTick(FCk_Time{kSixtyHertz});
        }
        return InOutFixture._Path.Get<ck::FFragment_GroundNavPath_Result>().Get_HasFreshResult();
    }

    auto Do_Request(
        FFixture& InOutFixture,
        FCk_Request_GroundNavPath_FindPath InRequest) -> bool
    {
        UCk_Utils_GroundNavPath_UE::Request_FindPath(InOutFixture._Path, InRequest, {});
        Do_Drain(InOutFixture);
        return Do_RunToPublished(InOutFixture);
    }

    auto Make_StrictSnapshot() -> ck::groundnav::FCk_GroundNav_DynamicObstacleSnapshot
    {
        const auto Snapshot = ck::groundnav::Try_MakeDynamicObstacleSnapshot(
            TArray<ck::groundnav::FCk_GroundNav_DynamicObstacleDisc>{
                ck::groundnav::FCk_GroundNav_DynamicObstacleDisc{
                    FVector{100.0f, 700.0f, kGroundZ}, 25.0f, 50.0f}},
            TConstArrayView<ck::groundnav::FCk_GroundNav_DynamicObstacleObb>{});
        return Snapshot.IsSet() ? Snapshot.GetValue() : ck::groundnav::FCk_GroundNav_DynamicObstacleSnapshot{};
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_DynamicPathRequest,
    "CkTests.UnitTests.CkGroundNav.Path.DynamicPathRequest",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_DynamicPathRequest::RunTest(const FString& Parameters)
{
    using namespace ck;
    using namespace ck::groundnav;

    auto Discs = TArray<FCk_GroundNav_DynamicObstacleDisc>{
        FCk_GroundNav_DynamicObstacleDisc{FVector{100.0f, 200.0f, 300.0f}, 50.0f, 80.0f}};
    const auto Snapshot = Try_MakeDynamicObstacleSnapshot(
        Discs, TConstArrayView<FCk_GroundNav_DynamicObstacleObb>{});
    TestTrue(TEXT("the request fixture creates a valid strict snapshot"), Snapshot.IsSet());
    if (NOT Snapshot.IsSet())
    { return false; }

    auto Request = FCk_Request_GroundNavPath_FindPath{FVector::ZeroVector, FVector{500.0f, 0.0f, 0.0f}};
    TestTrue(TEXT("a new request begins permissive with an empty value snapshot"),
        Request.Get_DynamicObstacles().Get_IsEmpty());

    Request.Set_DynamicObstacles(Snapshot.GetValue());
    const auto CopiedRequest = Request;
    Discs[0]._RadiusUu = 0.0f;

    TestFalse(TEXT("copying a request keeps its strict snapshot"),
        CopiedRequest.Get_DynamicObstacles().Get_IsEmpty());
    TestEqual(TEXT("copying a request keeps every strict disc"),
        CopiedRequest.Get_DynamicObstacles().Get_Discs().Num(), 1);
    TestEqual(TEXT("the copied request retains the collected radius"),
        CopiedRequest.Get_DynamicObstacles().Get_Discs()[0]._RadiusUu, 50.0f);

    const auto MovedRequest = MoveTemp(Request);
    TestFalse(TEXT("moving a request preserves the strict snapshot"),
        MovedRequest.Get_DynamicObstacles().Get_IsEmpty());

    auto MalformedDisc = FCk_GroundNav_DynamicObstacleDisc{};
    MalformedDisc._Centre.X = std::numeric_limits<float>::quiet_NaN();
    const auto Malformed = Try_MakeDynamicObstacleSnapshot(
        TArray<FCk_GroundNav_DynamicObstacleDisc>{MalformedDisc},
        TConstArrayView<FCk_GroundNav_DynamicObstacleObb>{});
    TestFalse(TEXT("malformed confirmed-collector input has no partial snapshot to dispatch"),
        Malformed.IsSet());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_DynamicPathRequest_StrictRouteRepairForcesFullReplan,
    "CkTests.UnitTests.CkGroundNav.Path.DynamicPathRequest.StrictRouteRepairForcesFullReplan",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_DynamicPathRequest_StrictRouteRepairForcesFullReplan::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_dynamic_path_request;

    auto Fixture = FFixture{};
    if (NOT TestTrue(TEXT("the production fixture bakes, publishes and composes a path entity"), Do_Setup(Fixture)))
    {
        Do_Teardown(Fixture);
        return false;
    }

    auto Strict = FCk_Request_GroundNavPath_FindPath{kTwoRouteStart, kTwoRouteGoal};
    Strict.Set_RequestRevision(1);
    Strict.Set_DynamicObstacles(Make_StrictSnapshot());

    if (NOT TestTrue(TEXT("the strict request reaches the GroundNav request processor and publishes"),
        Do_Request(Fixture, Strict)))
    {
        Do_Teardown(Fixture);
        return false;
    }

    const auto& StrictResult = Fixture._Path.Get<ck::FFragment_GroundNavPath_Result>().Get_Result();
    const auto& StrictCurrent = Fixture._Path.Get<ck::FFragment_GroundNavPath_Current>();
    if (NOT TestEqual(TEXT("the valid strict snapshot selects the strict-cell production route"),
        StrictCurrent.Get_LastRouteKind(), ECk_GroundNav_PathRouteKind::StrictCell) ||
        NOT TestTrue(TEXT("the strict-cell route completed"),
            StrictResult.Get_Status() == ECk_GroundNav_PathStatus::Ready) ||
        NOT TestTrue(TEXT("the strict-cell route is cached despite carrying no portal keys"),
            StrictCurrent.Get_HasCachedRoute() && StrictCurrent.Get_LastCorridorKeys().IsEmpty()))
    {
        Do_Teardown(Fixture);
        return false;
    }

    auto Repair = FCk_Request_GroundNavPath_FindPath{kTwoRouteStart, kTwoRouteGoal};
    Repair.Set_RequestRevision(2);
    Repair.Set_PlanMode(ECk_GroundNav_PlanMode::Repair);
    TestTrue(TEXT("the next repair deliberately carries a new empty obstacle snapshot"),
        Repair.Get_DynamicObstacles().Get_IsEmpty());

    if (NOT TestTrue(TEXT("the strict-cell repair publishes through the same processor pipeline"),
        Do_Request(Fixture, Repair)))
    {
        Do_Teardown(Fixture);
        return false;
    }

    const auto& Repaired = Fixture._Path.Get<ck::FFragment_GroundNavPath_Result>().Get_Result();
    TestTrue(TEXT("a strict-cell cache reports FullReplan rather than pretending no cache existed"),
        Repaired.Get_RepairVerdict() == ECk_GroundNav_RepairVerdict::FullReplan);
    TestTrue(TEXT("the forced replan still publishes a route"),
        Repaired.Get_Status() == ECk_GroundNav_PathStatus::Ready);
    TestEqual(TEXT("the forced replan belongs to the repair revision"), Repaired.Get_RequestRevision(), 2);

    Do_Teardown(Fixture);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_DynamicPathRequest_RepairWithNoCacheReportsNone,
    "CkTests.UnitTests.CkGroundNav.Path.DynamicPathRequest.RepairWithNoCacheReportsNone",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_DynamicPathRequest_RepairWithNoCacheReportsNone::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_dynamic_path_request;

    auto Fixture = FFixture{};
    if (NOT TestTrue(TEXT("the production fixture bakes, publishes and composes a fresh path entity"), Do_Setup(Fixture)))
    {
        Do_Teardown(Fixture);
        return false;
    }

    const auto& Current = Fixture._Path.Get<ck::FFragment_GroundNavPath_Current>();
    if (NOT TestTrue(TEXT("the fresh path entity has neither portal keys nor a cached strict route"),
        Current.Get_LastCorridorKeys().IsEmpty() && NOT Current.Get_HasCachedRoute()))
    {
        Do_Teardown(Fixture);
        return false;
    }

    auto Repair = FCk_Request_GroundNavPath_FindPath{kTwoRouteStart, kTwoRouteGoal};
    Repair.Set_RequestRevision(1);
    Repair.Set_PlanMode(ECk_GroundNav_PlanMode::Repair);

    if (NOT TestTrue(TEXT("a genuine no-cache repair is planned by the production processors"),
        Do_Request(Fixture, Repair)))
    {
        Do_Teardown(Fixture);
        return false;
    }

    const auto& Published = Fixture._Path.Get<ck::FFragment_GroundNavPath_Result>().Get_Result();
    TestTrue(TEXT("the no-cache repair plans cold and reports no repair verdict"),
        Published.Get_RepairVerdict() == ECk_GroundNav_RepairVerdict::None);
    TestTrue(TEXT("the no-cache repair still produces the ordinary route"),
        Published.Get_Status() == ECk_GroundNav_PathStatus::Ready);

    Do_Teardown(Fixture);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
