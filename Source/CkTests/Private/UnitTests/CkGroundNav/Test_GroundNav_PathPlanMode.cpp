// What a plan mode asks for, and what the corridor a plan leaves behind is a box AROUND.
//
// Three claims, each measured against something that is not the thing under test. The corridor box is
// measured against the plates the search itself named — recomputed here from the corridor keys the
// agent kept, with the same lattice arithmetic and none of the processor's code — so a box that grew
// by the wrong margin, or that was built from the crossings rather than from the plates, fails on the
// face rather than on a containment that a generous box would pass anyway. Both faces are asserted
// because only one of them catches an over-wide box, and an over-wide box is the one that would let a
// stale route survive a rebuild that moved it.
//
// The repair mode is measured against the COLD plan of the same query over the same field: a repair
// that expands what a cold search expands has repaired nothing, and a repair that answers a different
// route over a field nothing moved has repaired the wrong thing. The field is deliberately NOT rebuilt
// between the two — a corridor re-offered against the epoch it was planned for is the case where the
// saving is exact rather than merely likely, and it is the case a consumer hits every time it re-asks
// while the world is quiet.
//
// The third claim is the one a mode flag makes cheap to get wrong: asking to repair with nothing
// cached must PLAN, not refuse and not park. The verdict None is what says the repair was never paid
// for, which is the only way a caller can tell the two apart from the result alone.
//
// Everything here is driven through the processors rather than through the search, because the mode
// flag, the corridor cache and the box all live on the fragments and none of them exists below the
// drain. A published field needs a world to be published INTO, so there is a world here; there is no
// scheduler, so the drain and the slice are ticked by hand.

#include "CkCore/Time/CkTime.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/World/CkEcsWorld.h"

#include "CkGroundNav/CkGroundNav_Log.h"
#include "CkGroundNav/Facade/CkGroundNav_WorldFieldRegistry.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Path/CkGroundNavPath_Processor.h"
#include "CkGroundNav/Path/CkGroundNavPath_Utils.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Reachability.h"

#include "../CkUnitTest_Common.h"

#include "Test_GroundNav_QueryFixtures.h"

#include <CoreMinimal.h>
#include <Engine/World.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_pathplanmode
{
    using ck::groundnav::FCk_GroundNav_CrossingKey;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldPtr;
    using ck::groundnav::Get_TileAndPlate;

    using ck_test_groundnav_queryfixtures::Bake;
    using ck_test_groundnav_queryfixtures::kStepHeight;
    using ck_test_groundnav_queryfixtures::kTwoRouteGoal;
    using ck_test_groundnav_queryfixtures::kTwoRouteStart;
    using ck_test_groundnav_queryfixtures::Make_QueryParams;
    using ck_test_groundnav_queryfixtures::Make_TwoRouteScene;

    constexpr auto kSixtyHertz = 1.0 / 60.0;

    // A real body, so the radius half of the inflation is not zero and an implementation that dropped
    // it would still be measured. Well inside the two-route door, which is 100uu wide.
    constexpr auto kAgentRadiusUu = 20.0f;

    // The margin the processor adds on top of the radius: one cell of the default lattice. Written out
    // here rather than reached for, so a change to that constant is a change this test SEES.
    constexpr auto kExpectedMarginUu = 25.0f;

    // The corner-offset pass off, so the published waypoints are the funnel's own taut line and lie on
    // the corridor by construction. With the pass on, a waypoint is pushed off an inside corner by a
    // multiple of the radius, which is a property of that pass and not of the box.
    constexpr auto kNoCornerOffset = 0.0f;

    // Far past what this scene needs, so a run that stops on it is a search that never terminated.
    constexpr auto kMaxTicks = 4096;

    // The corridor must hold at least one door for the plates its keys name to be the plates the plan
    // walked. Below that the scene, not the box, is what failed.
    constexpr auto kMinCorridorCrossings = 1;

    constexpr auto kInformEngineOfWorld = false;

    // ----------------------------------------------------------------------------------------------------------------

    auto Get_VerdictText(
        ECk_GroundNav_RepairVerdict InVerdict) -> FString
    {
        switch (InVerdict)
        {
            case ECk_GroundNav_RepairVerdict::StillValid:
            { return TEXT("StillValid"); }

            case ECk_GroundNav_RepairVerdict::Repaired:
            { return TEXT("Repaired"); }

            case ECk_GroundNav_RepairVerdict::FullReplan:
            { return TEXT("FullReplan"); }

            default:
            { return TEXT("None"); }
        }
    }

    auto Get_StatusText(
        ECk_GroundNav_PathStatus InStatus) -> FString
    {
        return ck::Format_UE(TEXT("{}"), InStatus);
    }

    auto Get_BoxText(
        const FBox& InBox) -> FString
    {
        return FString::Printf(TEXT("min(%.3f, %.3f, %.3f) max(%.3f, %.3f, %.3f)"),
            InBox.Min.X, InBox.Min.Y, InBox.Min.Z, InBox.Max.X, InBox.Max.Y, InBox.Max.Z);
    }

    // ----------------------------------------------------------------------------------------------------------------

    /**
     * A published field, a world to publish it into, and an agent that can plan over it.
     *
     * The world is real because world_fields keys on one and the drain resolves its field through it;
     * the ECS world is a bare registry because nothing here needs a scheduler. The agent carries the
     * world fragment itself rather than leaning on the ownership walk: a bare FEcsWorld's transient
     * entity has no world on it, and that walk ensures rather than answering.
     */
    struct FPlanModeFixture
    {
    public:
        ck::FEcsWorld EcsWorld;

        UWorld* World = nullptr;

        FCk_GroundNav_FieldPtr Field;

        FCk_Handle_GroundNavPath Path;

    public:
        auto Get_Current() const -> const ck::FFragment_GroundNavPath_Current&
        {
            return Path.Get<ck::FFragment_GroundNavPath_Current>();
        }

        auto Get_HasFreshResult() const -> bool
        {
            return Path.Get<ck::FFragment_GroundNavPath_Result>().Get_HasFreshResult();
        }

        auto Get_Result() const -> const FCk_GroundNavPath_Result&
        {
            return Path.Get<ck::FFragment_GroundNavPath_Result>().Get_Result();
        }
    };

    auto Make_PathParams() -> FCk_Fragment_GroundNavPath_ParamsData
    {
        auto Params = FCk_Fragment_GroundNavPath_ParamsData{kAgentRadiusUu};

        Params.Set_VerticalToleranceUu(kStepHeight);
        Params.Set_CornerOffsetK(kNoCornerOffset);

        return Params;
    }

    /** Bakes the two-route scene, publishes it, and gives an agent the path feature. */
    auto Do_Setup(
        FPlanModeFixture& InOutFixture) -> bool
    {
        auto Baked = MakeShared<FCk_GroundNav_Field>();

        if (NOT Bake(Make_TwoRouteScene(), Make_QueryParams(), *Baked))
        { return false; }

        InOutFixture.Field = Baked;

        InOutFixture.World = UWorld::CreateWorld(
            EWorldType::Game, kInformEngineOfWorld, FName{TEXT("CkGroundNavPathPlanMode")});

        if (ck::Is_NOT_Valid(InOutFixture.World))
        { return false; }

        ck::groundnav::world_fields::Publish(InOutFixture.World, FCk_Handle{}, InOutFixture.Field, {});

        auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(
            InOutFixture.EcsWorld.Get_Registry());

        Owner.Add<TWeakObjectPtr<UWorld>>(InOutFixture.World);

        InOutFixture.Path = UCk_Utils_GroundNavPath_UE::Add(Owner, Make_PathParams());

        return ck::IsValid(InOutFixture.Path);
    }

    auto Do_Teardown(
        FPlanModeFixture& InOutFixture) -> void
    {
        if (ck::Is_NOT_Valid(InOutFixture.World))
        { return; }

        InOutFixture.World->DestroyWorld(kInformEngineOfWorld);
        InOutFixture.World = nullptr;
    }

    // ----------------------------------------------------------------------------------------------------------------

    auto Do_DrainRequests(
        FPlanModeFixture& InOutFixture) -> void
    {
        ck::FProcessor_GroundNavPath_HandleRequests{InOutFixture.EcsWorld.Get_Registry()}.ForEachEntity(
            FCk_Time{kSixtyHertz},
            InOutFixture.Path,
            InOutFixture.Path.Get<ck::FFragment_GroundNavPath_Params>(),
            InOutFixture.Path.Get<ck::FFragment_GroundNavPath_Current>(),
            InOutFixture.Path.Get<ck::FFragment_GroundNavPath_Result>(),
            InOutFixture.Path.Get<ck::FFragment_GroundNavPath_Requests>());
    }

    /** Ticks the slice processor until the slot carries a finished episode. Answers the ticks spent. */
    auto Do_RunToPublished(
        FPlanModeFixture& InOutFixture) -> int32
    {
        auto Slice = ck::FProcessor_GroundNavPath_Slice{InOutFixture.EcsWorld.Get_Registry()};

        auto Ticks = 0;

        while (NOT InOutFixture.Get_HasFreshResult() && Ticks < kMaxTicks)
        {
            Slice.DoTick(FCk_Time{kSixtyHertz});
            ++Ticks;
        }

        return Ticks;
    }

    /** One whole episode: enqueue, drain, and slice until it answers. */
    auto Do_Plan(
        FPlanModeFixture&      InOutFixture,
        ECk_GroundNav_PlanMode InPlanMode,
        int32                  InRevision) -> int32
    {
        auto Request = FCk_Request_GroundNavPath_FindPath{kTwoRouteStart, kTwoRouteGoal};

        Request.Set_RequestRevision(InRevision);
        Request.Set_PlanMode(InPlanMode);

        UCk_Utils_GroundNavPath_UE::Request_FindPath(InOutFixture.Path, Request, {});

        Do_DrainRequests(InOutFixture);

        return Do_RunToPublished(InOutFixture);
    }

    // ----------------------------------------------------------------------------------------------------------------

    /**
     * The world box one flat plate covers, recomputed from its tile's own lattice.
     *
     * Deliberately a SECOND, independent statement of the arithmetic rather than a call into the one
     * the processor uses: a box asserted against the function that produced it asserts nothing.
     */
    auto Get_PlateWorldBounds(
        const FCk_GroundNav_Field& InField,
        int32                      InFlatPlate) -> FBox
    {
        int32 TileIndex = INDEX_NONE;
        int32 PlateIndex = INDEX_NONE;

        if (NOT Get_TileAndPlate(InField, InFlatPlate, TileIndex, PlateIndex))
        { return FBox{ForceInit}; }

        if (NOT InField._Tiles.IsValidIndex(TileIndex))
        { return FBox{ForceInit}; }

        const auto& Tile = InField._Tiles[TileIndex];

        if (NOT Tile._Plates._Plates.IsValidIndex(PlateIndex))
        { return FBox{ForceInit}; }

        const auto& Plate = Tile._Plates._Plates[PlateIndex];

        const auto CellSize = static_cast<double>(Tile._CellSizeUu);

        return FBox{
            FVector{Tile._Origin.X + (Plate._MinX * CellSize),
                    Tile._Origin.Y + (Plate._MinY * CellSize),
                    static_cast<double>(InField._Params._MinZUu)},
            FVector{Tile._Origin.X + ((Plate._MaxX + 1) * CellSize),
                    Tile._Origin.Y + ((Plate._MaxY + 1) * CellSize),
                    static_cast<double>(InField._Params._MaxZUu)}};
    }

    /**
     * The union of the plates the kept corridor names.
     *
     * A crossing key names the plate it leaves and the plate it enters, and a corridor is a chain of
     * them, so the two ends of every key are exactly the corridor's plates — which is why this needs
     * at least one door to be the same set the plan walked.
     */
    auto Get_CorridorPlateUnion(
        const FCk_GroundNav_Field&                 InField,
        TConstArrayView<FCk_GroundNav_CrossingKey> InKeys) -> FBox
    {
        auto FlatPlates = TSet<int32>{};

        for (const auto& Key : InKeys)
        {
            FlatPlates.Add(Key._FromFlatPlate);
            FlatPlates.Add(Key._ToFlatPlate);
        }

        auto Union = FBox{ForceInit};

        for (const auto FlatPlate : FlatPlates)
        {
            const auto PlateBounds = Get_PlateWorldBounds(InField, FlatPlate);

            if (PlateBounds.IsValid == 0)
            { continue; }

            Union += PlateBounds;
        }

        return Union;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Path_CorridorBoundsCoverEveryWaypointInflatedByRadiusPlusMargin,
    "CkTests.UnitTests.CkGroundNav.Path.CorridorBoundsCoverEveryWaypointInflatedByRadiusPlusMargin",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Path_CorridorBoundsCoverEveryWaypointInflatedByRadiusPlusMargin::RunTest(
    const FString& Parameters)
{
    using namespace ck_test_groundnav_pathplanmode;

    auto Fixture = FPlanModeFixture{};

    if (NOT TestTrue(TEXT("the two-route scene bakes, publishes and takes an agent"), Do_Setup(Fixture)))
    {
        Do_Teardown(Fixture);
        return false;
    }

    const auto Ticks = Do_Plan(Fixture, ECk_GroundNav_PlanMode::Cold, 1);

    const auto& Published = Fixture.Get_Result();

    if (NOT TestTrue(FString::Printf(TEXT("the cold plan answers Ready in %d ticks [%s]"),
            Ticks, *Get_StatusText(Published.Get_Status())),
        Published.Get_Status() == ECk_GroundNav_PathStatus::Ready))
    {
        Do_Teardown(Fixture);
        return false;
    }

    const auto& Current = Fixture.Get_Current();
    const auto& Keys = Current.Get_LastCorridorKeys();

    if (NOT TestTrue(FString::Printf(
            TEXT("and the route holds doors the box can be measured against [%d]"), Keys.Num()),
        Keys.Num() >= kMinCorridorCrossings))
    {
        Do_Teardown(Fixture);
        return false;
    }

    const auto StoredBounds = UCk_Utils_GroundNavPath_UE::Get_LastCorridorBounds(Fixture.Path);
    const auto StoredInflation = Current.Get_CorridorInflationUu();

    TestEqual(TEXT("the stored inflation is the agent radius plus the corridor margin"),
        StoredInflation, kAgentRadiusUu + kExpectedMarginUu);

    const auto PlateUnion = Get_CorridorPlateUnion(*Fixture.Field, Keys);

    if (NOT TestTrue(TEXT("the corridor's plates resolve to a box"), PlateUnion.IsValid != 0))
    {
        Do_Teardown(Fixture);
        return false;
    }

    const auto Expected = PlateUnion.ExpandBy(static_cast<double>(StoredInflation));

    // BOTH faces. Containment alone would pass for any box large enough, and an over-wide box is
    // exactly the failure that lets a rebuild which moved the route read as leaving it alone.
    TestTrue(FString::Printf(TEXT("the stored box's near face is the plates' union inflated [%s vs %s]"),
        *Get_BoxText(StoredBounds), *Get_BoxText(Expected)), StoredBounds.Min == Expected.Min);

    TestTrue(FString::Printf(TEXT("and its far face is too [%s vs %s]"),
        *Get_BoxText(StoredBounds), *Get_BoxText(Expected)), StoredBounds.Max == Expected.Max);

    // Shrunk by exactly what was applied, the box is the plates again — so a waypoint inside it is a
    // waypoint on ground the corridor actually named, not one the margin happened to reach.
    const auto Shrunk = StoredBounds.ExpandBy(-static_cast<double>(StoredInflation));

    auto Outside = FString{};

    for (auto Index = 0; Index < Published.Get_Waypoints().Num(); ++Index)
    {
        const auto& Waypoint = Published.Get_Waypoints()[Index];

        if (Shrunk.IsInsideOrOn(Waypoint))
        { continue; }

        Outside += FString::Printf(TEXT(" %d:(%.1f, %.1f, %.1f)"),
            Index, Waypoint.X, Waypoint.Y, Waypoint.Z);
    }

    TestTrue(FString::Printf(
            TEXT("every published waypoint lies on the plates the box was built from ")
            TEXT("[%d waypoints, outside:%s]"),
            Published.Get_Waypoints().Num(), Outside.IsEmpty() ? TEXT(" none") : *Outside),
        Outside.IsEmpty());

    Do_Teardown(Fixture);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Path_RepairPlanModeReusesTheCachedCorridor,
    "CkTests.UnitTests.CkGroundNav.Path.RepairPlanModeReusesTheCachedCorridor",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Path_RepairPlanModeReusesTheCachedCorridor::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathplanmode;

    auto Fixture = FPlanModeFixture{};

    if (NOT TestTrue(TEXT("the two-route scene bakes, publishes and takes an agent"), Do_Setup(Fixture)))
    {
        Do_Teardown(Fixture);
        return false;
    }

    Do_Plan(Fixture, ECk_GroundNav_PlanMode::Cold, 1);

    const auto Cold = Fixture.Get_Result();

    if (NOT TestTrue(FString::Printf(TEXT("the cold plan answers Ready [%s]"),
            *Get_StatusText(Cold.Get_Status())),
        Cold.Get_Status() == ECk_GroundNav_PathStatus::Ready))
    {
        Do_Teardown(Fixture);
        return false;
    }

    // A cold plan that expanded nothing would make "fewer expansions" unfalsifiable.
    if (NOT TestTrue(FString::Printf(TEXT("and pays for it in expansions [%d]"),
            Cold.Get_ExpansionCount()),
        Cold.Get_ExpansionCount() > 0))
    {
        Do_Teardown(Fixture);
        return false;
    }

    TestTrue(TEXT("a cold plan carries no repair verdict"),
        Cold.Get_RepairVerdict() == ECk_GroundNav_RepairVerdict::None);

    Do_Plan(Fixture, ECk_GroundNav_PlanMode::Repair, 2);

    const auto& Warm = Fixture.Get_Result();

    const auto Report = FString::Printf(
        TEXT("[PLANMODE] two-route repair: warm %d expansions, cold %d, verdict %s, status %s"),
        Warm.Get_ExpansionCount(), Cold.Get_ExpansionCount(),
        *Get_VerdictText(Warm.Get_RepairVerdict()), *Get_StatusText(Warm.Get_Status()));

    ck::groundnav::Display(TEXT("{}"), Report);

    TestTrue(FString::Printf(TEXT("the repair answers Ready [%s]"), *Report),
        Warm.Get_Status() == ECk_GroundNav_PathStatus::Ready);

    TestTrue(FString::Printf(
            TEXT("and reports what it did with the corridor it was handed [%s]"), *Report),
        Warm.Get_RepairVerdict() == ECk_GroundNav_RepairVerdict::StillValid ||
        Warm.Get_RepairVerdict() == ECk_GroundNav_RepairVerdict::Repaired);

    // The saving is the whole point: a repair that expands what a cold search expands has repaired
    // nothing and merely paid for the walk that proved it.
    TestTrue(FString::Printf(TEXT("and expands strictly less than the cold plan [%s]"), *Report),
        Warm.Get_ExpansionCount() < Cold.Get_ExpansionCount());

    // Nothing moved between the two plans, so a cheaper answer must be the SAME answer. A repair that
    // saved expansions by answering a different route saved nothing anybody wanted.
    TestTrue(FString::Printf(TEXT("and answers the cold plan's own route [%d vs %d waypoints] [%s]"),
            Warm.Get_Waypoints().Num(), Cold.Get_Waypoints().Num(), *Report),
        Warm.Get_Waypoints() == Cold.Get_Waypoints());

    TestEqual(FString::Printf(TEXT("stamped with the revision that asked for it [%s]"), *Report),
        Warm.Get_RequestRevision(), 2);

    Do_Teardown(Fixture);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Path_RepairWithoutACachedCorridorPlansCold,
    "CkTests.UnitTests.CkGroundNav.Path.RepairWithoutACachedCorridorPlansCold",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Path_RepairWithoutACachedCorridorPlansCold::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathplanmode;

    auto Fixture = FPlanModeFixture{};

    if (NOT TestTrue(TEXT("the two-route scene bakes, publishes and takes an agent"), Do_Setup(Fixture)))
    {
        Do_Teardown(Fixture);
        return false;
    }

    if (NOT TestTrue(TEXT("the fresh agent holds no corridor to repair"),
        Fixture.Get_Current().Get_LastCorridorKeys().IsEmpty()))
    {
        Do_Teardown(Fixture);
        return false;
    }

    const auto Ticks = Do_Plan(Fixture, ECk_GroundNav_PlanMode::Repair, 1);

    const auto& Published = Fixture.Get_Result();

    // Planned, not refused and not parked: a repair of nothing is a cold plan.
    TestTrue(TEXT("the slot carries a finished episode"), Fixture.Get_HasFreshResult());

    TestTrue(FString::Printf(TEXT("and it answers Ready in %d ticks [%s]"),
            Ticks, *Get_StatusText(Published.Get_Status())),
        Published.Get_Status() == ECk_GroundNav_PathStatus::Ready);

    // None is what says the repair was never paid for, which is the only thing separating this from a
    // repair that ran and threw the corridor away.
    TestTrue(FString::Printf(TEXT("carrying no repair verdict [%s]"),
            *Get_VerdictText(Published.Get_RepairVerdict())),
        Published.Get_RepairVerdict() == ECk_GroundNav_RepairVerdict::None);

    TestTrue(TEXT("and the plan it did make is cached for the next repair to start from"),
        NOT Fixture.Get_Current().Get_LastCorridorKeys().IsEmpty());

    Do_Teardown(Fixture);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
