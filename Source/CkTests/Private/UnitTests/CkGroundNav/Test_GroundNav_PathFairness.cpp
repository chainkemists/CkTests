// A path-slice cap is a frame budget, not a fixed-order priority policy. Each row observes the first
// actual one-slot service partition, requeues that observed first path, then requires the other path.

#include "CkCore/Time/CkTime.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Fragment.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"
#include "CkGroundNav/Facade/CkGroundNav_WorldFieldRegistry.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Path/CkGroundNavPath_Processor.h"
#include "CkGroundNav/Path/CkGroundNavPath_Utils.h"
#include "CkAutoTest_Utils.h"
#include "../CkUnitTest_Common.h"
#include "Test_GroundNav_QueryFixtures.h"
#include <CoreMinimal.h>
#include <HAL/IConsoleManager.h>
#include <Engine/World.h>

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_pathfairness
{
    using ck_test_groundnav_queryfixtures::Bake;
    using ck_test_groundnav_queryfixtures::kStepHeight;
    using ck_test_groundnav_queryfixtures::kTwoRouteGoal;
    using ck_test_groundnav_queryfixtures::kTwoRouteStart;
    using ck_test_groundnav_queryfixtures::Make_QueryParams;
    using ck_test_groundnav_queryfixtures::Make_TwoRouteScene;
    constexpr auto kInformEngineOfWorld = false;
    constexpr auto kSixtyHertz = 1.0 / 60.0;

    class FScopedCVar
    {
    public:
        explicit FScopedCVar(FName InName, const FString& InValue)
            : _Name(InName)
            , _CVar(IConsoleManager::Get().FindConsoleVariable(*InName.ToString()))
        {
            UCk_Utils_AutoTest_UE::Request_PushCVarOverride(_Name, InValue);
        }
        ~FScopedCVar() { UCk_Utils_AutoTest_UE::Request_PopCVarOverride(_Name); }
        auto HasEffectiveValue(int32 InExpected) const -> bool
        { return _CVar != nullptr && _CVar->GetInt() == InExpected; }
    private:
        FName _Name;
        IConsoleVariable* _CVar = nullptr;
    };

    struct FFixture
    {
        ck::FEcsWorld EcsWorld;
        UWorld* World = nullptr;
        ck::groundnav::FCk_GroundNav_FieldPtr Field;
        FCk_Handle_GroundNavPath First;
        FCk_Handle_GroundNavPath Second;
        FCk_Handle_GroundNavPath Late;
        int32 NextRevision = 1;
    };
    struct FObservedTurn { FCk_Handle_GroundNavPath Early; FCk_Handle_GroundNavPath Next; };

    auto Make_Params() -> FCk_Fragment_GroundNavPath_ParamsData
    {
        auto Params = FCk_Fragment_GroundNavPath_ParamsData{20.0f};
        Params.Set_VerticalToleranceUu(kStepHeight);
        Params.Set_CornerOffsetK(0.0f);
        return Params;
    }
    auto Add_Path(FFixture& InOutFixture) -> FCk_Handle_GroundNavPath
    {
        auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(InOutFixture.EcsWorld.Get_Registry());
        Owner.Add<TWeakObjectPtr<UWorld>>(InOutFixture.World);
        return UCk_Utils_GroundNavPath_UE::Add(Owner, Make_Params());
    }
    auto Do_Drain(FFixture& InOutFixture, FCk_Handle_GroundNavPath InPath) -> void
    {
        ck::FProcessor_GroundNavPath_HandleRequests{InOutFixture.EcsWorld.Get_Registry()}.ForEachEntity(
            FCk_Time{kSixtyHertz}, InPath, InPath.Get<ck::FFragment_GroundNavPath_Params>(),
            InPath.Get<ck::FFragment_GroundNavPath_Current>(), InPath.Get<ck::FFragment_GroundNavPath_Result>(),
            InPath.Get<ck::FFragment_GroundNavPath_Requests>());
    }
    auto Do_Request(FFixture& InOutFixture, FCk_Handle_GroundNavPath InPath) -> void
    {
        auto Request = FCk_Request_GroundNavPath_FindPath{kTwoRouteStart, kTwoRouteGoal};
        Request.Set_RequestRevision(InOutFixture.NextRevision++);
        UCk_Utils_GroundNavPath_UE::Request_FindPath(InPath, Request, {});
        Do_Drain(InOutFixture, InPath);
    }
    auto HasPublished(FCk_Handle_GroundNavPath InPath) -> bool
    { return InPath.Get<ck::FFragment_GroundNavPath_Result>().Get_HasFreshResult(); }
    auto Do_Setup(FFixture& InOutFixture) -> bool
    {
        auto Field = MakeShared<ck::groundnav::FCk_GroundNav_Field>();
        if (NOT Bake(Make_TwoRouteScene(), Make_QueryParams(), *Field)) { return false; }
        InOutFixture.Field = Field;
        InOutFixture.World = UWorld::CreateWorld(EWorldType::Game, kInformEngineOfWorld, FName{TEXT("CkGroundNavPathFairness")});
        if (ck::Is_NOT_Valid(InOutFixture.World)) { return false; }
        ck::groundnav::world_fields::Publish(InOutFixture.World, FCk_Handle{}, InOutFixture.Field, {},
            ck::groundnav::world_fields::FCk_GroundNav_PublishClaim::Geometry());
        InOutFixture.First = Add_Path(InOutFixture);
        InOutFixture.Second = Add_Path(InOutFixture);
        if (NOT ck::IsValid(InOutFixture.First) || NOT ck::IsValid(InOutFixture.Second)) { return false; }
        Do_Request(InOutFixture, InOutFixture.First);
        Do_Request(InOutFixture, InOutFixture.Second);
        return true;
    }
    auto Do_Teardown(FFixture& InOutFixture) -> void
    {
        if (ck::IsValid(InOutFixture.World)) { InOutFixture.World->DestroyWorld(kInformEngineOfWorld); InOutFixture.World = nullptr; }
    }
    auto Do_ObserveFirstTurn(FFixture& InOutFixture, ck::FProcessor_GroundNavPath_Slice& InOutSlice, FObservedTurn& OutTurn) -> bool
    {
        InOutSlice.DoTick(FCk_Time{kSixtyHertz});
        const auto FirstPublished = HasPublished(InOutFixture.First);
        const auto SecondPublished = HasPublished(InOutFixture.Second);
        if (FirstPublished == SecondPublished) { return false; }
        OutTurn.Early = FirstPublished ? InOutFixture.First : InOutFixture.Second;
        OutTurn.Next = FirstPublished ? InOutFixture.Second : InOutFixture.First;
        return true;
    }
    auto Do_AddLate(FFixture& InOutFixture) -> bool
    {
        InOutFixture.Late = Add_Path(InOutFixture);
        if (NOT ck::IsValid(InOutFixture.Late)) { return false; }
        Do_Request(InOutFixture, InOutFixture.Late);
        return NOT HasPublished(InOutFixture.Late);
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_PathFairness_ObservedLaterRequestIsServedWhileEarlyPathReplans,
    "CkTests.UnitTests.CkGroundNav.PathFairness.ObservedLaterRequestIsServedWhileEarlyPathReplans", kCkUnitTestFlags)

bool FCkTest_GroundNav_PathFairness_ObservedLaterRequestIsServedWhileEarlyPathReplans::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathfairness;
    auto Cap = FScopedCVar{FName{TEXT("ck.GroundNav.MaxSearchesPerFrame")}, TEXT("1")};
    if (NOT TestTrue(TEXT("the priority-preserving one-slot override took effect"), Cap.HasEffectiveValue(1))) { return false; }
    auto Fixture = FFixture{};
    if (NOT TestTrue(TEXT("the two-path fair-admission scene bakes and accepts both episodes"), Do_Setup(Fixture))) { Do_Teardown(Fixture); return false; }
    auto Slice = ck::FProcessor_GroundNavPath_Slice{Fixture.EcsWorld.Get_Registry()};
    auto Observed = FObservedTurn{};
    if (NOT TestTrue(TEXT("one and only one path publishes in the first capped pass"), Do_ObserveFirstTurn(Fixture, Slice, Observed))) { Do_Teardown(Fixture); return false; }
    Do_Request(Fixture, Observed.Early);
    Slice.DoTick(FCk_Time{kSixtyHertz});
    const auto NextPublished = HasPublished(Observed.Next);
    TestTrue(TEXT("the observed unserved path receives the next slot while the observed first path replans"), NextPublished);
    Do_Teardown(Fixture);
    return NextPublished;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_PathFairness_DestroyedObservedTurnDoesNotStrandLaterRequest,
    "CkTests.UnitTests.CkGroundNav.PathFairness.DestroyedObservedTurnDoesNotStrandLaterRequest", kCkUnitTestFlags)

bool FCkTest_GroundNav_PathFairness_DestroyedObservedTurnDoesNotStrandLaterRequest::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathfairness;
    auto Cap = FScopedCVar{FName{TEXT("ck.GroundNav.MaxSearchesPerFrame")}, TEXT("1")};
    if (NOT TestTrue(TEXT("the priority-preserving one-slot override took effect"), Cap.HasEffectiveValue(1))) { return false; }
    auto Fixture = FFixture{};
    if (NOT TestTrue(TEXT("the destroyed-turn scene bakes and accepts both initial episodes"), Do_Setup(Fixture))) { Do_Teardown(Fixture); return false; }
    auto Slice = ck::FProcessor_GroundNavPath_Slice{Fixture.EcsWorld.Get_Registry()};
    auto Observed = FObservedTurn{};
    if (NOT TestTrue(TEXT("one and only one path publishes in the first capped pass"), Do_ObserveFirstTurn(Fixture, Slice, Observed))) { Do_Teardown(Fixture); return false; }
    Do_Request(Fixture, Observed.Early);
    // Exactly two live paths made the observed next path the actual saved next turn.
    Observed.Next.AddOrGet<ck::FTag_DestroyEntity_Initiate>();
    if (NOT TestTrue(TEXT("the later request is accepted after that observed next turn is destroyed"), Do_AddLate(Fixture))) { Do_Teardown(Fixture); return false; }
    auto LatePublished = false;
    for (auto Turn = 0; Turn < 3 && NOT LatePublished; ++Turn)
    {
        Slice.DoTick(FCk_Time{kSixtyHertz});
        LatePublished = HasPublished(Fixture.Late);
        if (HasPublished(Observed.Early))
        { Do_Request(Fixture, Observed.Early); }
    }
    TestTrue(TEXT("the later path progresses within bounded turns after its observed predecessor is destroyed"), LatePublished);
    Do_Teardown(Fixture);
    return LatePublished;
}
