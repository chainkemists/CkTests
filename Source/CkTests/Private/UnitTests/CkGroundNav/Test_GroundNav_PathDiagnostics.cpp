// What a viewer is handed when it asks an agent's planner what it is doing.
//
// The fragment is the copy boundary, so the first claim is about the TYPE and needs no world at all:
// a default-constructed one is readable, and every column on it is a value that already means
// something before any pass has run. That is the whole reason it exists - a debugger holding one has
// nothing left to follow back into the registry, and there is no state of the world in which reading
// one is unsafe.
//
// The second claim is the stamp, and every expectation for it is read back off the agent's OWN
// fragments rather than written out as a constant. A diagnostics column asserted against a number
// this file chose would pass on a stamp that copied the wrong field as readily as on one that copied
// the right one; asserted against the fragment it was copied FROM, it fails exactly when the two stop
// agreeing, which is the only failure the copy can have.
//
// The third is the repath flag, taken in both directions on one agent. A flag that simply never
// cleared would pass a test that only ever raised it, and the tag is raised by the invalidator and
// cleared by the path's consumer - so the column has to follow it down as well as up.
//
// The world here is a bare one with no scheduler, so the drain, the slice and the diagnostics pass are
// all ticked by hand, exactly as Test_GroundNav_PathPlanMode ticks the first two - and its clock is set
// by hand too, because a date read off a world sitting at zero is indistinguishable from a date read off
// the platform clock, off a default, or off nothing at all.

#include "CkCore/Time/CkTime.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/World/CkEcsWorld.h"

#include "CkGroundNav/CkGroundNav_Log.h"
#include "CkGroundNav/Facade/CkGroundNav_WorldFieldRegistry.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Path/CkGroundNavPath_Diagnostics_Processor.h"
#include "CkGroundNav/Path/CkGroundNavPath_Processor.h"
#include "CkGroundNav/Path/CkGroundNavPath_Utils.h"

#include "CkNavigation/NavSurface/CkNavSurface_ProviderTable.h"
#include "CkNavigation/NavSurface/CkNavSurface_Utils.h"

#include "../CkUnitTest_Common.h"

#include "Test_GroundNav_QueryFixtures.h"

#include <CoreMinimal.h>
#include <Engine/World.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_pathdiagnostics
{
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldPtr;

    using ck_test_groundnav_queryfixtures::Bake;
    using ck_test_groundnav_queryfixtures::kStepHeight;
    using ck_test_groundnav_queryfixtures::kTwoRouteGoal;
    using ck_test_groundnav_queryfixtures::kTwoRouteStart;
    using ck_test_groundnav_queryfixtures::Make_QueryParams;
    using ck_test_groundnav_queryfixtures::Make_TwoRouteScene;

    constexpr auto kSixtyHertz = 1.0 / 60.0;

    // A real body, so the plan is one an agent of some size could walk rather than a point's.
    constexpr auto kAgentRadiusUu = 20.0f;

    // The corner-offset pass off, for the reason Test_GroundNav_PathPlanMode turns it off: nothing
    // here is about where a waypoint was pushed to, only about how many there are.
    constexpr auto kNoCornerOffset = 0.0f;

    // Far past what this scene needs, so a run that stops on it is a search that never terminated.
    constexpr auto kMaxTicks = 4096;

    constexpr auto kInformEngineOfWorld = false;

    // ----------------------------------------------------------------------------------------------------------------

    /**
     * A published field, a world set to GroundNav to publish it into, and an agent that can plan.
     *
     * The provider is written straight into the per-world mirror rather than requested through the
     * neutral facade: the facade's request also writes the world entity's own fragment, and this
     * world has no scheduler standing behind that entity. The mirror is what Get_Provider reads.
     */
    struct FDiagnosticsFixture
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

        auto Get_Result() const -> const FCk_GroundNavPath_Result&
        {
            return Path.Get<ck::FFragment_GroundNavPath_Result>().Get_Result();
        }

        auto Get_HasFreshResult() const -> bool
        {
            return Path.Get<ck::FFragment_GroundNavPath_Result>().Get_HasFreshResult();
        }

        auto Get_PublishSequence() const -> int32
        {
            return Path.Get<ck::FFragment_GroundNavPath_Result>().Get_PublishSequence();
        }

        auto Get_Diagnostics() const -> FFragment_GroundNavPath_Diagnostics
        {
            return UCk_Utils_GroundNavPath_UE::Get_Diagnostics(Path);
        }
    };

    auto Make_PathParams() -> FCk_Fragment_GroundNavPath_ParamsData
    {
        auto Params = FCk_Fragment_GroundNavPath_ParamsData{kAgentRadiusUu};

        Params.Set_VerticalToleranceUu(kStepHeight);
        Params.Set_CornerOffsetK(kNoCornerOffset);

        return Params;
    }

    auto Do_Setup(
        FDiagnosticsFixture& InOutFixture) -> bool
    {
        auto Baked = MakeShared<FCk_GroundNav_Field>();

        if (NOT Bake(Make_TwoRouteScene(), Make_QueryParams(), *Baked))
        { return false; }

        InOutFixture.Field = Baked;

        InOutFixture.World = UWorld::CreateWorld(
            EWorldType::Game, kInformEngineOfWorld, FName{TEXT("CkGroundNavPathDiagnostics")});

        if (ck::Is_NOT_Valid(InOutFixture.World))
        { return false; }

        ck::nav_surface::Set_ProviderForWorld(
            InOutFixture.World, ECk_NavSurface_Provider::GroundNav);

        ck::groundnav::world_fields::Publish(InOutFixture.World, FCk_Handle{}, InOutFixture.Field, {});

        auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(
            InOutFixture.EcsWorld.Get_Registry());

        Owner.Add<TWeakObjectPtr<UWorld>>(InOutFixture.World);

        InOutFixture.Path = UCk_Utils_GroundNavPath_UE::Add(Owner, Make_PathParams());

        return ck::IsValid(InOutFixture.Path);
    }

    auto Do_Teardown(
        FDiagnosticsFixture& InOutFixture) -> void
    {
        if (ck::Is_NOT_Valid(InOutFixture.World))
        { return; }

        InOutFixture.World->DestroyWorld(kInformEngineOfWorld);
        InOutFixture.World = nullptr;
    }

    // ----------------------------------------------------------------------------------------------------------------

    /** One whole episode: enqueue, drain, and slice until the slot carries a finished one. */
    auto Do_Plan(
        FDiagnosticsFixture& InOutFixture,
        int32                InRevision) -> void
    {
        auto Request = FCk_Request_GroundNavPath_FindPath{kTwoRouteStart, kTwoRouteGoal};

        Request.Set_RequestRevision(InRevision);

        UCk_Utils_GroundNavPath_UE::Request_FindPath(InOutFixture.Path, Request, {});

        ck::FProcessor_GroundNavPath_HandleRequests{InOutFixture.EcsWorld.Get_Registry()}.ForEachEntity(
            FCk_Time{kSixtyHertz},
            InOutFixture.Path,
            InOutFixture.Path.Get<ck::FFragment_GroundNavPath_Params>(),
            InOutFixture.Path.Get<ck::FFragment_GroundNavPath_Current>(),
            InOutFixture.Path.Get<ck::FFragment_GroundNavPath_Result>(),
            InOutFixture.Path.Get<ck::FFragment_GroundNavPath_Requests>());

        auto Slice = ck::FProcessor_GroundNavPath_Slice{InOutFixture.EcsWorld.Get_Registry()};

        auto Ticks = 0;

        while (NOT InOutFixture.Get_HasFreshResult() && Ticks < kMaxTicks)
        {
            Slice.DoTick(FCk_Time{kSixtyHertz});
            ++Ticks;
        }
    }

    /**
     * Move the bare world's clock, which nothing else here does.
     *
     * The two values are arbitrary and only have to differ from each other and from zero: what the
     * date column has to prove is that it reads the WORLD's time rather than the platform clock the
     * pending stamp keeps, and zero is the one value both of those answer.
     */
    constexpr auto kFirstPlanWorldSeconds = 12.5;
    constexpr auto kSecondPlanWorldSeconds = 34.25;

    auto Set_WorldTime(
        FDiagnosticsFixture& InOutFixture,
        double               InSeconds) -> void
    {
        InOutFixture.World->TimeSeconds = InSeconds;
    }

    /** One pass of the diagnostics processor over the one agent, driven the way its group would. */
    auto Do_Stamp(
        FDiagnosticsFixture& InOutFixture) -> void
    {
        ck::FProcessor_GroundNavPath_Diagnostics::ForEachEntity(
            FCk_Time{kSixtyHertz},
            InOutFixture.Path,
            InOutFixture.Path.Get<ck::FFragment_GroundNavPath_Current>(),
            InOutFixture.Path.Get<ck::FFragment_GroundNavPath_Result>());
    }

    auto Get_StatusText(
        ECk_GroundNav_PathStatus InStatus) -> FString
    {
        return ck::Format_UE(TEXT("{}"), InStatus);
    }

    auto Get_ProviderText(
        ECk_NavSurface_Provider InProvider) -> FString
    {
        return ck::Format_UE(TEXT("{}"), InProvider);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_PathDiagnostics_ConstructedWithNoWorldIsAllValues,
    "CkTests.UnitTests.CkGroundNav.PathDiagnostics.ConstructedWithNoWorldIsAllValues",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_PathDiagnostics_ConstructedWithNoWorldIsAllValues::RunTest(
    const FString& Parameters)
{
    using namespace ck_test_groundnav_pathdiagnostics;

    // No world, no registry, no handle: the type is constructed where nothing else exists, which is
    // the state a viewer holding a copy of it is in once the world it came from is gone.
    const auto Fresh = FFragment_GroundNavPath_Diagnostics{};

    TestTrue(TEXT("nothing has been planned, so no verdict stands"),
        Fresh.Get_PathStatus() == ECk_GroundNav_PathStatus::InProgress);

    TestTrue(TEXT("and no profile is named"), NOT Fresh.Get_ProfileTag().IsValid());

    TestEqual(TEXT("and no waypoints are published"), Fresh.Get_PublishedWaypointCount(), 0);

    TestTrue(TEXT("and no corridor names any link"), Fresh.Get_CorridorLinkIds().IsEmpty());

    TestEqual(TEXT("and no corridor was found on any epoch"),
        Fresh.Get_CorridorEpoch(), static_cast<int64>(0));

    TestFalse(TEXT("and nothing has flagged it for a repath"), Fresh.Get_RepathRequired());

    TestEqual(TEXT("and no plan has been dated"),
        Fresh.Get_LastPlanWorldTime().Get_Seconds(), 0.0);

    // A COPY is taken and read on its own: outliving the thing that produced it is the entire reason
    // the fragment is a value, so the copy has to answer everything the original does.
    const auto Copy = FFragment_GroundNavPath_Diagnostics{Fresh};

    TestEqual(TEXT("a copy carries the same epoch as the value it was taken from"),
        Copy.Get_CorridorEpoch(), Fresh.Get_CorridorEpoch());

    TestTrue(TEXT("and the same link list"),
        Copy.Get_CorridorLinkIds() == Fresh.Get_CorridorLinkIds());

    // The read boundary answers the same value for a handle it cannot read, so a caller never has to
    // tell "no such agent" apart from "nothing stamped yet" before it can use what it was handed.
    const auto FromNothing = UCk_Utils_GroundNavPath_UE::Get_Diagnostics(FCk_Handle_GroundNavPath{});

    TestEqual(TEXT("an invalid handle answers the same unstamped value"),
        FromNothing.Get_PublishedWaypointCount(), 0);

    TestEqual(TEXT("with no plan dated on it either"),
        FromNothing.Get_LastPlanWorldTime().Get_Seconds(), 0.0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_PathDiagnostics_StampedValuesMatchThePlannerTheyWereCopiedFrom,
    "CkTests.UnitTests.CkGroundNav.PathDiagnostics.StampedValuesMatchThePlannerTheyWereCopiedFrom",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_PathDiagnostics_StampedValuesMatchThePlannerTheyWereCopiedFrom::RunTest(
    const FString& Parameters)
{
    using namespace ck_test_groundnav_pathdiagnostics;

    auto Fixture = FDiagnosticsFixture{};

    if (NOT TestTrue(TEXT("the two-route scene bakes, publishes and takes an agent"), Do_Setup(Fixture)))
    {
        Do_Teardown(Fixture);
        return false;
    }

    // Composed on first visit, so an agent nothing has looked at carries none. A fragment stamped by
    // Add would be indistinguishable from one a pass wrote, and would read as planner state on an
    // agent no pass has ever seen.
    if (NOT TestFalse(TEXT("an agent no pass has visited carries no diagnostics"),
        Fixture.Path.Has<FFragment_GroundNavPath_Diagnostics>()))
    {
        Do_Teardown(Fixture);
        return false;
    }

    // And the value a reader is handed for that agent says so on its own. Every column below is read
    // under this flag, so a reader never has to tell a stamped default from a default nothing wrote.
    TestFalse(TEXT("and the value it reads back says nothing has stamped it"),
        Fixture.Get_Diagnostics().Get_HasBeenStamped());

    Do_Plan(Fixture, 1);

    const auto& Published = Fixture.Get_Result();

    if (NOT TestTrue(FString::Printf(TEXT("the plan answers Ready [%s]"),
            *Get_StatusText(Published.Get_Status())),
        Published.Get_Status() == ECk_GroundNav_PathStatus::Ready))
    {
        Do_Teardown(Fixture);
        return false;
    }

    // Moved off zero BEFORE the pass runs, so the date it writes is a claim about which clock it read.
    Set_WorldTime(Fixture, kFirstPlanWorldSeconds);

    Do_Stamp(Fixture);

    const auto Diagnostics = Fixture.Get_Diagnostics();
    const auto& Current = Fixture.Get_Current();

    const auto Report = FString::Printf(
        TEXT("[GROUNDNAV-PATH-DIAG] provider=%s status=%s waypoints=%d links=%d epoch=%lld ")
        TEXT("repath=%d plannedAt=%.3f"),
        *Get_ProviderText(Diagnostics.Get_Provider()),
        *Get_StatusText(Diagnostics.Get_PathStatus()),
        Diagnostics.Get_PublishedWaypointCount(),
        Diagnostics.Get_CorridorLinkIds().Num(),
        Diagnostics.Get_CorridorEpoch(),
        Diagnostics.Get_RepathRequired() ? 1 : 0,
        Diagnostics.Get_LastPlanWorldTime().Get_Seconds());

    ck::groundnav::Display(TEXT("{}"), Report);

    TestTrue(FString::Printf(TEXT("the pass composes the fragment it stamps [%s]"), *Report),
        Fixture.Path.Has<FFragment_GroundNavPath_Diagnostics>());

    TestTrue(FString::Printf(TEXT("and the value now says a pass has written it [%s]"), *Report),
        Diagnostics.Get_HasBeenStamped());

    // The world was set to GroundNav before anything was published into it, so a column reading
    // Recast is a stamp that never asked the facade which provider answers this agent.
    TestTrue(FString::Printf(TEXT("the provider column names the world's own provider [%s]"), *Report),
        Diagnostics.Get_Provider() == UCk_Utils_NavSurface_UE::Get_Provider(Fixture.World));

    TestTrue(FString::Printf(TEXT("and it is the one this world was set to [%s]"), *Report),
        Diagnostics.Get_Provider() == ECk_NavSurface_Provider::GroundNav);

    // An untagged request plans over the volume's untagged default, which is what an empty tag means.
    TestTrue(FString::Printf(TEXT("the profile column is the corridor's own [%s]"), *Report),
        Diagnostics.Get_ProfileTag() == Current.Get_ProfileTag());

    TestFalse(FString::Printf(TEXT("and an untagged plan leaves it empty [%s]"), *Report),
        Diagnostics.Get_ProfileTag().IsValid());

    TestTrue(FString::Printf(TEXT("the verdict is the one the slot published [%s]"), *Report),
        Diagnostics.Get_PathStatus() == Published.Get_Status());

    // Both halves: equal to the route's own size, AND that size is not zero. Equality alone would
    // pass on a stamp that copied nothing over a plan that published nothing.
    TestEqual(FString::Printf(TEXT("the waypoint count is the published route's own [%s]"), *Report),
        Diagnostics.Get_PublishedWaypointCount(), Published.Get_Waypoints().Num());

    TestTrue(FString::Printf(TEXT("and the route published some [%s]"), *Report),
        Published.Get_Waypoints().Num() > 0);

    // The two-route scene is boxes and nothing else - it authors no nav links - so the corridor across
    // it crosses none and both sides of this are empty. Equality is still the claim worth making: it is
    // the copy that is under test, and a scene that DID cross a link would assert a non-empty list here.
    TestTrue(FString::Printf(TEXT("the link ids are the cached corridor's own [%s]"), *Report),
        Diagnostics.Get_CorridorLinkIds() == Current.Get_LastCorridorLinkIds());

    TestEqual(FString::Printf(TEXT("and the epoch is the one that corridor was found on [%s]"), *Report),
        Diagnostics.Get_CorridorEpoch(), Current.Get_LastCorridorEpoch()._Value);

    // A field that published is a field with an epoch, so a zero here is a column that never read one.
    TestTrue(FString::Printf(TEXT("which is an epoch a build actually reached [%s]"), *Report),
        Diagnostics.Get_CorridorEpoch() > 0);

    TestFalse(FString::Printf(TEXT("nothing has moved under this route, so it is not flagged [%s]"),
            *Report),
        Diagnostics.Get_RepathRequired());

    // The clock was moved off zero before the pass ran, so this is a claim about WHICH clock: the
    // world's, not the platform clock the pending stamp keeps. At zero the two are the same number.
    TestEqual(FString::Printf(TEXT("the plan is dated by the world it was planned in [%s]"), *Report),
        Diagnostics.Get_LastPlanWorldTime().Get_Seconds(), kFirstPlanWorldSeconds);

    // The clock moves under a plan that has NOT been replanned. A column dated every visit would follow
    // it, and the date would stop saying when the plan was made and start saying when it was last read.
    const auto FirstSequence = Fixture.Get_PublishSequence();

    Set_WorldTime(Fixture, kSecondPlanWorldSeconds);

    Do_Stamp(Fixture);

    TestEqual(TEXT("a standing plan re-read under a moved clock keeps the date it was planned at"),
        Fixture.Get_Diagnostics().Get_LastPlanWorldTime().Get_Seconds(), kFirstPlanWorldSeconds);

    // A SECOND route through the same slot. What separates it from the first is the published sequence,
    // which moves on a publish and on nothing else - so the date has to move with it and not before.
    Do_Plan(Fixture, 2);

    const auto SecondSequence = Fixture.Get_PublishSequence();

    if (NOT TestTrue(TEXT("the second route published, which is the only thing that moves the sequence"),
        SecondSequence > FirstSequence))
    {
        Do_Teardown(Fixture);
        return false;
    }

    Do_Stamp(Fixture);

    const auto Redated = Fixture.Get_Diagnostics();

    TestEqual(TEXT("so the date moves to the world time that plan was published at"),
        Redated.Get_LastPlanWorldTime().Get_Seconds(), kSecondPlanWorldSeconds);

    TestEqual(TEXT("and the date names the sequence it was taken at"),
        Redated.Get_LastPlanSequence(), SecondSequence);

    Do_Teardown(Fixture);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_PathDiagnostics_RepathFlagMirrorsTheTagInBothDirections,
    "CkTests.UnitTests.CkGroundNav.PathDiagnostics.RepathFlagMirrorsTheTagInBothDirections",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_PathDiagnostics_RepathFlagMirrorsTheTagInBothDirections::RunTest(
    const FString& Parameters)
{
    using namespace ck_test_groundnav_pathdiagnostics;

    auto Fixture = FDiagnosticsFixture{};

    if (NOT TestTrue(TEXT("the two-route scene bakes, publishes and takes an agent"), Do_Setup(Fixture)))
    {
        Do_Teardown(Fixture);
        return false;
    }

    Do_Plan(Fixture, 1);

    Do_Stamp(Fixture);

    // The negative FIRST, and on the same agent: a column hard-wired to true would pass every
    // assertion below if the raised half were taken on its own.
    TestFalse(TEXT("an agent nothing has flagged reads back unflagged"),
        Fixture.Get_Diagnostics().Get_RepathRequired());

    Fixture.Path.AddOrGet<ck::FTag_GroundNavPath_RepathRequired>();

    Do_Stamp(Fixture);

    TestTrue(TEXT("the flag follows the tag up"),
        Fixture.Get_Diagnostics().Get_RepathRequired());

    // The tag is raised by the invalidator and cleared by the path's consumer, so a column that only
    // ever latched would go on reporting a repath the agent has already served.
    Fixture.Path.Try_Remove<ck::FTag_GroundNavPath_RepathRequired>();

    Do_Stamp(Fixture);

    TestFalse(TEXT("and back down again"),
        Fixture.Get_Diagnostics().Get_RepathRequired());

    Do_Teardown(Fixture);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_PathDiagnostics_DoCastAnswersTheHandle,
    "CkTests.UnitTests.CkGroundNav.PathDiagnostics.DoCastAnswersTheHandle",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_PathDiagnostics_DoCastAnswersTheHandle::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_pathdiagnostics;

    auto Fixture = FDiagnosticsFixture{};

    if (NOT TestTrue(TEXT("the two-route scene bakes, publishes and takes an agent"), Do_Setup(Fixture)))
    {
        Do_Teardown(Fixture);
        return false;
    }

    // What a viewer holding a BARE handle has to do before it can ask for diagnostics at all. The
    // gate is Has, and every cast on this class - the two C++ templates and the two reflected
    // UFUNCTIONs beside them - answers through it, so this is the one behaviour a wrong answer could
    // come from.
    const auto Bare = FCk_Handle{Fixture.Path};

    TestTrue(TEXT("a bare handle on a planner entity casts to a planner"),
        ck::IsValid(UCk_Utils_GroundNavPath_UE::Cast(Bare)));

    TestEqual(TEXT("and to the SAME entity rather than to some other planner"),
        static_cast<int32>(UCk_Utils_GroundNavPath_UE::Cast(Bare).Get_Entity().Get_EntityNumber()),
        static_cast<int32>(Fixture.Path.Get_Entity().Get_EntityNumber()));

    auto NoPlanner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Fixture.EcsWorld.Get_Registry());

    TestFalse(TEXT("an entity with no path feature casts to nothing"),
        ck::IsValid(UCk_Utils_GroundNavPath_UE::Cast(NoPlanner)));

    // The reflected pair, which is what Blueprint and AngelScript actually reach - neither can call
    // the C++ templates above, and a rename here would break the GroundNav debug submenu at load with
    // no C++ caller to fail first.
    const auto* UtilsClass = UCk_Utils_GroundNavPath_UE::StaticClass();

    TestNotNull(TEXT("the reflected DoCastChecked exists, which is the name a script resolves"),
        UtilsClass->FindFunctionByName(FName{TEXT("DoCastChecked")}));

    TestNotNull(TEXT("and the reflected DoCast beside it"),
        UtilsClass->FindFunctionByName(FName{TEXT("DoCast")}));

    Do_Teardown(Fixture);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
