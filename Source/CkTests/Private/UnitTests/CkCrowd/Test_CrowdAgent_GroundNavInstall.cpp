// The map from a ground-path status onto the install vocabulary, checked as a MAP rather than as a
// handful of favourite cases.
//
// A verdict table is only worth having if it is TOTAL, so the first two tests walk every enumerator
// and assert the shape of every row: that the row a status indexes is the row that names it, that the
// table holds exactly as many rows as there are statuses, and that no row says Fail without saying
// why. A row that quietly went missing or slid out of order would otherwise be found by whichever
// agent hit that status in a gym, which is the wrong place to find it.
//
// Three rows are then pinned by name because the crowd's behaviour hangs off them: Unreachable must
// reach the crowd as a PLANNING verdict so the strict-then-permissive retry runs the same sequence
// Recast drives it with, Unbuilt must terminate rather than park forever, and Blocked must read as
// degenerate input rather than as a route that might appear later.
//
// The last two tests take the map at its word and drive the seam it names. They need an entity, not a
// world: the install seam is fragment surgery on a handle, so a private registry is the whole fixture.

#include "CkCrowd/Agent/CkCrowdAgent_GroundNavInstall_Algorithm.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/World/CkEcsWorld.h"

#include "CkNavigation/Nav/CkNav_Algorithm.h"
#include "CkNavigation/Nav/CkNav_Fragment.h"
#include "CkNavigation/Nav/CkNav_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

#include <CoreMinimal.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_tests_crowd_groundnav_install
{
    using ck::ck_crowd_agent_ground_nav_install_algorithm::ECk_CrowdAgent_GroundNavInstallAction;
    using ck::ck_crowd_agent_ground_nav_install_algorithm::FCk_CrowdAgent_GroundNavVerdict;
    using ck::ck_crowd_agent_ground_nav_install_algorithm::Get_GroundNavVerdict;
    using ck::ck_crowd_agent_ground_nav_install_algorithm::kGroundNavVerdicts;

    // The last enumerator plus one. Read off the enum rather than off the table, so a table that lost
    // a row is measured against the statuses instead of against itself.
    constexpr auto kStatusCount = static_cast<int32>(ECk_GroundNav_PathStatus::Blocked) + 1;

    // What a dispatch stamped on the shared slot. Every install and every failure below carries it, so
    // a writer that dropped the caller's revision would let a superseded result be applied.
    constexpr auto kEpisodeRevision = 17;

    // A revision the episode above is not on, used to prove the seam writes the one it was handed.
    constexpr auto kOtherRevision = 4;

    auto Get_StatusText(
        ECk_GroundNav_PathStatus InStatus) -> FString
    {
        return ck::Format_UE(TEXT("{}"), InStatus);
    }

    auto Get_ActionText(
        ECk_CrowdAgent_GroundNavInstallAction InAction) -> FString
    {
        switch (InAction)
        {
            case ECk_CrowdAgent_GroundNavInstallAction::Install:
            { return TEXT("Install"); }

            case ECk_CrowdAgent_GroundNavInstallAction::Fail:
            { return TEXT("Fail"); }

            default:
            { return TEXT("Defer"); }
        }
    }

    auto Get_RowText(
        const FCk_CrowdAgent_GroundNavVerdict& InRow) -> FString
    {
        return FString::Printf(TEXT("%s -> %s as %s because %s"),
            *Get_StatusText(InRow._Status),
            *Get_ActionText(InRow._Action),
            *ck::Format_UE(TEXT("{}"), InRow._InstallAs),
            *ck::Format_UE(TEXT("{}"), InRow._Reason));
    }

    // ----------------------------------------------------------------------------------------------------------------

    // Three of them, so a failure that reset the corridor is told apart from one that shortened it.
    auto Make_Waypoints() -> TArray<FVector>
    {
        return TArray<FVector>{
            FVector{100.0, 0.0, 0.0},
            FVector{200.0, 50.0, 0.0},
            FVector{300.0, 120.0, 0.0}};
    }

    /** A registry and the entities in it: everything the install seam touches, and nothing else. */
    struct FInstallFixture
    {
    public:
        ck::FEcsWorld World;

    public:
        auto CreateEntity() -> FCk_Handle
        {
            return UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
        }
    };
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_GroundNavInstall_VerdictTableIsTotal,
    "CkTests.UnitTests.CkCrowd.GroundNavInstall.VerdictTableIsTotal",
    kCkUnitTestFlags)

auto FCkTest_Crowd_GroundNavInstall_VerdictTableIsTotal::RunTest(const FString& InParameters) -> bool
{
    using namespace ck_tests_crowd_groundnav_install;

    TestEqual(TEXT("the table holds one row per ground path status"),
        static_cast<int32>(UE_ARRAY_COUNT(kGroundNavVerdicts)), kStatusCount);

    auto MisIndexed = 0;
    auto MisLookedUp = 0;

    for (auto Index = 0; Index < kStatusCount; ++Index)
    {
        const auto Status = static_cast<ECk_GroundNav_PathStatus>(Index);

        if (kGroundNavVerdicts[Index]._Status != Status)
        { ++MisIndexed; }

        // The lookup and the row must be the same object, not merely equal ones: the table is indexed
        // by cast, and a reference that came from anywhere else would be a second table.
        if (&Get_GroundNavVerdict(Status) != &kGroundNavVerdicts[Index])
        { ++MisLookedUp; }
    }

    TestEqual(TEXT("every row names the status its own index stands for"), MisIndexed, 0);

    TestEqual(TEXT("and the lookup answers with that same row"), MisLookedUp, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_GroundNavInstall_EveryFailRowCarriesAReason,
    "CkTests.UnitTests.CkCrowd.GroundNavInstall.EveryFailRowCarriesAReason",
    kCkUnitTestFlags)

auto FCkTest_Crowd_GroundNavInstall_EveryFailRowCarriesAReason::RunTest(const FString& InParameters) -> bool
{
    using namespace ck_tests_crowd_groundnav_install;

    auto ReasonlessFail = FString{};
    auto UnfailedFailRow = FString{};
    auto UninstallableInstall = FString{};
    auto ExcusedInstall = FString{};
    auto UnparkedDefer = FString{};

    auto DeferredStatuses = TArray<ECk_GroundNav_PathStatus>{};

    for (const auto& Row : kGroundNavVerdicts)
    {
        switch (Row._Action)
        {
            case ECk_CrowdAgent_GroundNavInstallAction::Fail:
            {
                if (Row._Reason == ECk_Nav_PathFailReason::None && ReasonlessFail.IsEmpty())
                { ReasonlessFail = Get_RowText(Row); }

                if (Row._InstallAs != ECk_Nav_PathStatus::Failed && UnfailedFailRow.IsEmpty())
                { UnfailedFailRow = Get_RowText(Row); }

                break;
            }

            case ECk_CrowdAgent_GroundNavInstallAction::Install:
            {
                const auto InstallAsIsWalkable = Row._InstallAs == ECk_Nav_PathStatus::Ready ||
                    Row._InstallAs == ECk_Nav_PathStatus::Partial;

                if (NOT InstallAsIsWalkable && UninstallableInstall.IsEmpty())
                { UninstallableInstall = Get_RowText(Row); }

                if (Row._Reason != ECk_Nav_PathFailReason::None && ExcusedInstall.IsEmpty())
                { ExcusedInstall = Get_RowText(Row); }

                break;
            }

            default:
            {
                DeferredStatuses.Add(Row._Status);

                const auto DeferParksTheSlot = Row._InstallAs == ECk_Nav_PathStatus::Pending &&
                    Row._Reason == ECk_Nav_PathFailReason::None;

                if (NOT DeferParksTheSlot && UnparkedDefer.IsEmpty())
                { UnparkedDefer = Get_RowText(Row); }

                break;
            }
        }
    }

    TestEqual(TEXT("no failure is reported without a reason"), ReasonlessFail, FString{});

    TestEqual(TEXT("and every failure installs as Failed"), UnfailedFailRow, FString{});

    TestEqual(TEXT("every install lands on a status a follower may walk"), UninstallableInstall, FString{});

    TestEqual(TEXT("and carries no failure reason"), ExcusedInstall, FString{});

    TestEqual(TEXT("a deferral parks the slot at Pending and blames nothing"), UnparkedDefer, FString{});

    // A status that may still become an answer is the only thing allowed to spend no verdict. Anything
    // else deferred would park an episode on a status that will never change, which the pending
    // watchdog could only end as a timeout.
    if (TestEqual(TEXT("exactly one status is deferred"), DeferredStatuses.Num(), 1))
    {
        TestTrue(FString::Printf(TEXT("and it is InProgress, not [%s]"),
                *Get_StatusText(DeferredStatuses[0])),
            DeferredStatuses[0] == ECk_GroundNav_PathStatus::InProgress);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_GroundNavInstall_UnbuiltFailsAsNoNavData,
    "CkTests.UnitTests.CkCrowd.GroundNavInstall.UnbuiltFailsAsNoNavData",
    kCkUnitTestFlags)

auto FCkTest_Crowd_GroundNavInstall_UnbuiltFailsAsNoNavData::RunTest(const FString& InParameters) -> bool
{
    using namespace ck_tests_crowd_groundnav_install;

    const auto& Row = Get_GroundNavVerdict(ECk_GroundNav_PathStatus::Unbuilt);

    // Ground nobody has baked is what CkNavigation reports as NoNavData, and the path feature has
    // already spent its own deferral window before it publishes Unbuilt — so a second wait here would
    // be an episode nothing but the pending watchdog could end.
    TestTrue(FString::Printf(TEXT("unbuilt ground fails rather than defers [%s]"), *Get_RowText(Row)),
        Row._Action == ECk_CrowdAgent_GroundNavInstallAction::Fail);

    TestTrue(FString::Printf(TEXT("and names no nav data [%s]"), *Get_RowText(Row)),
        Row._Reason == ECk_Nav_PathFailReason::NoNavData);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_GroundNavInstall_UnreachableFailsAsNoPath,
    "CkTests.UnitTests.CkCrowd.GroundNavInstall.UnreachableFailsAsNoPath",
    kCkUnitTestFlags)

auto FCkTest_Crowd_GroundNavInstall_UnreachableFailsAsNoPath::RunTest(const FString& InParameters) -> bool
{
    using namespace ck_tests_crowd_groundnav_install;

    const auto& Row = Get_GroundNavVerdict(ECk_GroundNav_PathStatus::Unreachable);

    // FindPathNoPath is the reason the crowd reads as a PLANNING verdict, which is what makes a strict
    // pass that found no route fall through to the permissive one and only then fail the goal.
    TestTrue(FString::Printf(TEXT("no route fails [%s]"), *Get_RowText(Row)),
        Row._Action == ECk_CrowdAgent_GroundNavInstallAction::Fail);

    TestTrue(FString::Printf(TEXT("and names no path [%s]"), *Get_RowText(Row)),
        Row._Reason == ECk_Nav_PathFailReason::FindPathNoPath);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_GroundNavInstall_BlockedFailsAsInvalid,
    "CkTests.UnitTests.CkCrowd.GroundNavInstall.BlockedFailsAsInvalid",
    kCkUnitTestFlags)

auto FCkTest_Crowd_GroundNavInstall_BlockedFailsAsInvalid::RunTest(const FString& InParameters) -> bool
{
    using namespace ck_tests_crowd_groundnav_install;

    const auto& Row = Get_GroundNavVerdict(ECk_GroundNav_PathStatus::Blocked);

    // A body wider than the field's clearance ceiling is degenerate input. Reading it as no-path would
    // buy a permissive retry that cannot answer any differently.
    TestTrue(FString::Printf(TEXT("a body no clearance admits fails [%s]"), *Get_RowText(Row)),
        Row._Action == ECk_CrowdAgent_GroundNavInstallAction::Fail);

    TestTrue(FString::Printf(TEXT("and names invalid input [%s]"), *Get_RowText(Row)),
        Row._Reason == ECk_Nav_PathFailReason::FindPathInvalid);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_GroundNavInstall_FailPreservesWaypoints,
    "CkTests.UnitTests.CkCrowd.GroundNavInstall.FailPreservesWaypoints",
    kCkUnitTestFlags)

auto FCkTest_Crowd_GroundNavInstall_FailPreservesWaypoints::RunTest(const FString& InParameters) -> bool
{
    using namespace ck_tests_crowd_groundnav_install;

    auto Fixture = FInstallFixture{};

    const auto Waypoints = Make_Waypoints();
    const auto Destination = Waypoints.Last();

    auto FailRows = 0;

    for (const auto& Row : kGroundNavVerdicts)
    {
        if (Row._Action != ECk_CrowdAgent_GroundNavInstallAction::Fail)
        { continue; }

        ++FailRows;

        auto Entity = Fixture.CreateEntity();

        if (NOT TestTrue(TEXT("the fixture hands out a valid entity"), ck::IsValid(Entity)))
        { return false; }

        FCk_Nav_Algorithm::InstallExternalPath(
            Entity, Waypoints, Destination, kEpisodeRevision, ECk_Nav_PathStatus::Ready);

        FCk_Nav_Algorithm::FailPath(Entity, Row._Reason, kEpisodeRevision);

        const auto& Result = Entity.Get<ck::FFragment_Nav_PathResult>();
        const auto Report = Get_RowText(Row);

        TestTrue(FString::Printf(TEXT("the slot terminates at Failed [%s]"), *Report),
            Result.Get_Status() == ECk_Nav_PathStatus::Failed);

        TestTrue(FString::Printf(TEXT("carrying the row's own reason [%s]"), *Report),
            Result.Get_Diagnostics().Get_LastFailReason() == Row._Reason);

        TestEqual(FString::Printf(TEXT("and the episode's revision [%s]"), *Report),
            Result.Get_RequestRevision(), kEpisodeRevision);

        // The corridor is what a consumer keeps walking while the next plan is found, so a failure
        // that cleared it would stop an agent dead on ground it was crossing perfectly well.
        TestTrue(FString::Printf(TEXT("and leaves the installed corridor untouched [%s]"), *Report),
            Result.Get_Waypoints() == Waypoints);
    }

    // Without a floor the loop above passes by asserting nothing at all.
    TestTrue(FString::Printf(TEXT("the table offers failure rows to drive [%d]"), FailRows),
        FailRows > 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_GroundNavInstall_InstallAsPartialIsPartial,
    "CkTests.UnitTests.CkCrowd.GroundNavInstall.InstallAsPartialIsPartial",
    kCkUnitTestFlags)

auto FCkTest_Crowd_GroundNavInstall_InstallAsPartialIsPartial::RunTest(const FString& InParameters) -> bool
{
    using namespace ck_tests_crowd_groundnav_install;

    auto Fixture = FInstallFixture{};

    const auto Waypoints = Make_Waypoints();
    const auto Destination = FVector{900.0, 900.0, 0.0};

    auto Entity = Fixture.CreateEntity();

    if (NOT TestTrue(TEXT("the fixture hands out a valid entity"), ck::IsValid(Entity)))
    { return false; }

    const auto& PartialRow = Get_GroundNavVerdict(ECk_GroundNav_PathStatus::Partial);

    FCk_Nav_Algorithm::InstallExternalPath(
        Entity, Waypoints, Destination, kOtherRevision, PartialRow._InstallAs);

    const auto& Result = Entity.Get<ck::FFragment_Nav_PathResult>();

    // Flattening a route that ends short of the goal to Ready is what silences the strict-phase
    // ends-short retry, so the row's own InstallAs has to survive the seam verbatim.
    TestTrue(FString::Printf(TEXT("a partial ground plan installs as Partial [%s]"),
            *Get_RowText(PartialRow)),
        Result.Get_Status() == ECk_Nav_PathStatus::Partial);

    TestTrue(TEXT("with the provider's corridor"), Result.Get_Waypoints() == Waypoints);

    TestEqual(TEXT("its destination"), Result.Get_DestinationLocation(), Destination);

    TestEqual(TEXT("and the revision the dispatch stamped"),
        Result.Get_RequestRevision(), kOtherRevision);

    TestTrue(TEXT("and no failure reason"),
        Result.Get_Diagnostics().Get_LastFailReason() == ECk_Nav_PathFailReason::None);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
