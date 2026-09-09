// The malformed input is injected only after normal CrowdAgent composition. It pins the public
// request processor's strict GroundNav transport boundary, rather than duplicating its collector.

#include <limits>

#include "CkCrowd/Agent/CkCrowdAgent_Fragment.h"
#include "CkCrowd/Agent/CkCrowdAgent_HandleRequests_Processor.h"
#include "CkCrowd/Agent/CkCrowdAgent_OnGroundNavPathResolved_Processor.h"
#include "CkCrowd/Agent/CkCrowdAgent_PathRefresh_Processor.h"
#include "CkCrowd/Agent/CkCrowdAgent_Utils.h"
#include "CkCrowd/CkCrowd_NavGameplayTags.h"

#include "CkCore/Time/CkTime.h"
#include "CkCore/Validation/CkIsValid.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Net/CkNet_Fragment.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"
#include "CkEcsExt/Transform/CkTransform_Utils.h"
#include "CkGroundNav/Path/CkGroundNavPath_Fragment.h"
#include "CkGroundNav/Path/CkGroundNavPath_Utils.h"
#include "CkNavigation/Nav/CkNav_Algorithm.h"
#include "CkNavigation/Nav/CkNav_Fragment.h"
#include "CkNavigation/NavSurface/CkNavSurface_Fragment.h"
#include "CkNavigation/NavSurface/CkNavSurface_Utils.h"
#include "CkShapes/CkShapes_Common.h"

#include "Engine/World.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_StrictDynamicDispatch_MalformedConfirmedBlockerFailsTerminally,
    "CkTests.UnitTests.CkCrowd.StrictDynamicDispatch.MalformedConfirmedBlockerFailsTerminally",
    kCkUnitTestFlags)
bool FCkTest_Crowd_StrictDynamicDispatch_MalformedConfirmedBlockerFailsTerminally::RunTest(
    const FString& InParameters)
{
    constexpr auto kInformEngineOfWorld = false;
    constexpr auto kAgentRadiusUu = 42.0f;
    constexpr auto kAgentHeightUu = 192.0f;

    auto* World = UWorld::CreateWorld(
        EWorldType::Game, kInformEngineOfWorld, FName{TEXT("CrowdStrictDynamicDispatch")});
    if (NOT TestNotNull(TEXT("the native fixture owns a game world"), World))
    { return false; }

    const auto Teardown = [&]
    {
        World->DestroyWorld(kInformEngineOfWorld);
    };

    auto WorldEntity = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(World);
    if (NOT TestTrue(TEXT("the world provides its transient ECS entity"), ck::IsValid(WorldEntity)))
    {
        Teardown();
        return false;
    }

    // A headless native world has no scheduler to install these NavSurface fragments for us.
    WorldEntity.AddOrGet<ck::FFragment_NavSurface_Provider>();
    WorldEntity.AddOrGet<ck::FFragment_NavSurface_RevisionWatch>();
    WorldEntity.AddOrGet<ck::FFragment_NavSurface_PendingRebuilds>();
    UCk_Utils_NavSurface_UE::Request_SetProvider(World, ECk_NavSurface_Provider::GroundNav);

    if (NOT TestEqual(TEXT("the fixture routes crowd planning through GroundNav"),
        UCk_Utils_NavSurface_UE::Get_Provider(World), ECk_NavSurface_Provider::GroundNav))
    {
        Teardown();
        return false;
    }

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(WorldEntity);
    Owner.AddOrGet<ck::FTag_HasAuthority>();
    auto Transform = UCk_Utils_Transform_UE::Add(
        Owner, FTransform{FVector::ZeroVector}, ECk_Replication::DoesNotReplicate);
    auto Agent = UCk_Utils_CrowdAgent_UE::Add(
        Transform, FCk_Fragment_CrowdAgent_ParamsData{kAgentRadiusUu, kAgentHeightUu});

    if (NOT TestTrue(TEXT("the fixture composed a normal authoritative CrowdAgent"), ck::IsValid(Agent)))
    {
        Teardown();
        return false;
    }

    auto BlockerOwner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(WorldEntity);
    auto BlockerTransform = UCk_Utils_Transform_UE::Add(
        BlockerOwner, FTransform{FVector{100.0f, 0.0f, 0.0f}}, ECk_Replication::DoesNotReplicate);
    auto Blocker = UCk_Utils_CrowdAgent_UE::Add(
        BlockerTransform, FCk_Fragment_CrowdAgent_ParamsData{kAgentRadiusUu, kAgentHeightUu});

    if (NOT TestTrue(TEXT("the fixture composed the independent stationary blocker"), ck::IsValid(Blocker)))
    {
        Teardown();
        return false;
    }

    auto& Markup = Blocker.Get<ck::FFragment_CrowdAgent_NavMarkup>();
    const auto BlockerMarkup = UCk_Utils_NavSurface_UE::Request_AreaMarkup(
        World,
        FCk_Request_NavSurface_AreaMarkup{
            FCk_AnyShape{FCk_ShapeBox_Dimensions{FVector{100.0f, 100.0f, 120.0f}}},
            TAG_Nav_Area_Crowd_Agent.GetTag()},
        {});
    if (NOT TestTrue(TEXT("the blocker carries a facade-created markup handle"), ck::IsValid(BlockerMarkup)))
    {
        Teardown();
        return false;
    }

    // This is the sole test-only breach: confirmed markup can never have a non-finite centre in
    // normal gameplay. The named friend above lets this regression pin prove the collector rejects
    // the complete strict snapshot before a GroundNav search or result callback can exist.
    Markup._Markup = BlockerMarkup;
    Markup._MarkupLocation = FVector{100.0f, 0.0f, std::numeric_limits<float>::quiet_NaN()};
    Markup._MarkupRadiusUu = 100.0f;
    Markup._MarkupVerticalHalfExtentUu = 120.0f;
    Markup._ConfirmedOnMesh = true;

    // This reaches the public PathNetwork splice entry before its no-hit exit. The malformed
    // confirmed record is off the candidate corridor, so only the strict snapshot boundary can
    // distinguish rejection from an accidental NotNeeded result.
    auto MalformedDetourWaypoints = TArray<FVector>{};
    const auto MalformedDetour = ck::FProcessor_CrowdAgent_PathRefresh::
        Try_BuildStationaryMarkupDetour(
            Agent, Agent.Get_Entity(), FVector::ZeroVector, FVector{1000.0f, 0.0f, 0.0f},
            Agent.Get<ck::FFragment_CrowdAgent_Params>(), 0.0f,
            TArray<FVector>{FVector{1000.0f, 0.0f, 0.0f}},
            ECk_CrowdAvoidanceVolume_QueryPhase::Strict, FGameplayTag{}, MalformedDetourWaypoints);
    TestEqual(TEXT("malformed confirmed geometry rejects the PathNetwork detour before no-hit"),
        MalformedDetour, ck::ECk_CrowdAgent_StationaryMarkupPathResult::Malformed);
    TestTrue(TEXT("a malformed detour never emits a partial external route"),
        MalformedDetourWaypoints.IsEmpty());

    Markup._MarkupLocation = FVector{100.0f, 0.0f, 10000.0f};
    auto HighZDetourWaypoints = TArray<FVector>{};
    const auto HighZDetour = ck::FProcessor_CrowdAgent_PathRefresh::
        Try_BuildStationaryMarkupDetour(
            Agent, Agent.Get_Entity(), FVector::ZeroVector, FVector{1000.0f, 0.0f, 0.0f},
            Agent.Get<ck::FFragment_CrowdAgent_Params>(), 0.0f,
            TArray<FVector>{FVector{1000.0f, 0.0f, 0.0f}},
            ECk_CrowdAvoidanceVolume_QueryPhase::Strict, FGameplayTag{}, HighZDetourWaypoints);
    TestEqual(TEXT("a valid high-Z blocker is not a false 2D PathNetwork detour hit"),
        HighZDetour, ck::ECk_CrowdAgent_StationaryMarkupPathResult::NotNeeded);
    TestTrue(TEXT("a high-Z no-hit leaves the external route output empty"),
        HighZDetourWaypoints.IsEmpty());

    Markup._MarkupLocation = FVector{100.0f, 0.0f, std::numeric_limits<float>::quiet_NaN()};

    UCk_Utils_CrowdAgent_UE::Request_MoveTo(
        Agent, FCk_Request_CrowdAgent_MoveTo{FVector{1000.0f, 0.0f, 0.0f}}, {});

    if (NOT TestTrue(TEXT("the production MoveTo utility enqueued the request"),
        Agent.Has<ck::FFragment_CrowdAgent_MoveRequests>()))
    {
        Teardown();
        return false;
    }

    AddExpectedError(
        TEXT("confirmed dynamic blocker geometry is malformed"),
        EAutomationExpectedErrorFlags::Contains,
        2); // CK_ENSURE reports through both CkEnsure and CkEnsures.
    ck::FProcessor_CrowdAgent_HandleRequests{WorldEntity.Get_RegistryView()}.ForEachEntity(
        FCk_Time{}, Agent, Agent.Get<ck::FFragment_CrowdAgent_Params>(),
        Agent.Get<ck::FFragment_CrowdAgent_PathFollow>(),
        Agent.Get<ck::FFragment_CrowdAgent_DesiredVelocity>(),
        Agent.Get<ck::FFragment_CrowdAgent_MoveRequests>());

    if (NOT TestTrue(TEXT("the malformed dispatch preallocated its GroundNav result slot"),
        Agent.Has<ck::FFragment_GroundNavPath_Result>()) ||
        NOT TestTrue(TEXT("the malformed dispatch preallocated its terminal navigation slot"),
        Agent.Has<ck::FFragment_Nav_PathResult>()))
    {
        Teardown();
        return false;
    }

    const auto& PathFollow = Agent.Get<ck::FFragment_CrowdAgent_PathFollow>();
    const auto& NavResult = Agent.Get<ck::FFragment_Nav_PathResult>();

    TestEqual(TEXT("the malformed strict snapshot is terminal for this revision"),
        NavResult.Get_Status(), ECk_Nav_PathStatus::Failed);
    TestEqual(TEXT("the terminal reason is malformed-provider NoNavData, not a route miss"),
        NavResult.Get_Diagnostics().Get_LastFailReason(), ECk_Nav_PathFailReason::NoNavData);
    TestEqual(TEXT("the terminal result names the active CrowdAgent revision"),
        NavResult.Get_RequestRevision(), PathFollow.Get_ActiveNavigationRequestRevision());
    TestEqual(TEXT("the active provider remained the actual GroundNav dispatch branch"),
        PathFollow.Get_ActiveProvider(), ECk_CrowdAgent_PathProvider::GroundNav);
    TestEqual(TEXT("the attempt was the strict phase"),
        PathFollow.Get_PlanPhase(), ECk_CrowdAgent_PlanPhase::Strict);

    TestFalse(TEXT("the rejected snapshot did not enqueue a GroundNav search request"),
        Agent.Has<ck::FFragment_GroundNavPath_Requests>());
    TestFalse(TEXT("the rejected snapshot did not mark a GroundNav search in flight"),
        Agent.Has<ck::FTag_GroundNavPath_SearchInFlight>());
    const auto& GroundNavResult = Agent.Get<ck::FFragment_GroundNavPath_Result>();
    TestFalse(TEXT("the rejected snapshot did not publish a GroundNav partial or success result"),
        GroundNavResult.Get_HasFreshResult());
    TestEqual(TEXT("the preallocated GroundNav result remains at its unsearched status"),
        GroundNavResult.Get_Result().Get_Status(), ECk_GroundNav_PathStatus::InProgress);

    // A valid confirmed blocker sitting at the goal must be omitted: joining a queue is allowed to
    // end inside its standing crowd. It reaches the same real processor and has no field work to do.
    Markup._MarkupLocation = FVector{500.0f, 0.0f, 0.0f};
    auto GoalOwner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(WorldEntity);
    GoalOwner.AddOrGet<ck::FTag_HasAuthority>();
    auto GoalTransform = UCk_Utils_Transform_UE::Add(
        GoalOwner, FTransform{FVector{-500.0f, 0.0f, 0.0f}}, ECk_Replication::DoesNotReplicate);
    auto GoalAgent = UCk_Utils_CrowdAgent_UE::Add(
        GoalTransform, FCk_Fragment_CrowdAgent_ParamsData{kAgentRadiusUu, kAgentHeightUu});
    if (NOT TestTrue(TEXT("the fixture composed the goal-exemption agent"), ck::IsValid(GoalAgent)))
    {
        Teardown();
        return false;
    }

    UCk_Utils_CrowdAgent_UE::Request_MoveTo(
        GoalAgent, FCk_Request_CrowdAgent_MoveTo{Markup._MarkupLocation}, {});
    ck::FProcessor_CrowdAgent_HandleRequests{WorldEntity.Get_RegistryView()}.ForEachEntity(
        FCk_Time{}, GoalAgent, GoalAgent.Get<ck::FFragment_CrowdAgent_Params>(),
        GoalAgent.Get<ck::FFragment_CrowdAgent_PathFollow>(),
        GoalAgent.Get<ck::FFragment_CrowdAgent_DesiredVelocity>(),
        GoalAgent.Get<ck::FFragment_CrowdAgent_MoveRequests>());
    TestTrue(TEXT("the collector exempts the valid confirmed blocker at its goal"),
        GoalAgent.Has<ck::FFragment_GroundNavPath_Requests>());

    // The querying agent's own confirmed record likewise cannot obstruct its departure.
    Markup._ConfirmedOnMesh = false;
    auto SelfOwner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(WorldEntity);
    SelfOwner.AddOrGet<ck::FTag_HasAuthority>();
    auto SelfTransform = UCk_Utils_Transform_UE::Add(
        SelfOwner, FTransform{FVector{0.0f, 500.0f, 0.0f}}, ECk_Replication::DoesNotReplicate);
    auto SelfAgent = UCk_Utils_CrowdAgent_UE::Add(
        SelfTransform, FCk_Fragment_CrowdAgent_ParamsData{kAgentRadiusUu, kAgentHeightUu});
    if (NOT TestTrue(TEXT("the fixture composed the self-exemption agent"), ck::IsValid(SelfAgent)))
    {
        Teardown();
        return false;
    }
    auto& SelfMarkup = SelfAgent.Get<ck::FFragment_CrowdAgent_NavMarkup>();
    SelfMarkup._MarkupLocation = FVector{0.0f, 500.0f, std::numeric_limits<float>::quiet_NaN()};
    SelfMarkup._MarkupRadiusUu = 100.0f;
    SelfMarkup._MarkupVerticalHalfExtentUu = 120.0f;
    SelfMarkup._ConfirmedOnMesh = true;

    UCk_Utils_CrowdAgent_UE::Request_MoveTo(
        SelfAgent, FCk_Request_CrowdAgent_MoveTo{FVector{1000.0f, 500.0f, 0.0f}}, {});
    ck::FProcessor_CrowdAgent_HandleRequests{WorldEntity.Get_RegistryView()}.ForEachEntity(
        FCk_Time{}, SelfAgent, SelfAgent.Get<ck::FFragment_CrowdAgent_Params>(),
        SelfAgent.Get<ck::FFragment_CrowdAgent_PathFollow>(),
        SelfAgent.Get<ck::FFragment_CrowdAgent_DesiredVelocity>(),
        SelfAgent.Get<ck::FFragment_CrowdAgent_MoveRequests>());
    TestTrue(TEXT("the collector exempts malformed markup owned by the querying agent"),
        SelfAgent.Has<ck::FFragment_GroundNavPath_Requests>());

    Teardown();

    // The resolver runs after GroundNav has published a terminal answer. These cases inject that
    // completed slot exactly at the consumer seam, then call the real processor. Each owns a fresh
    // world because InstallExternalPath and FailPath both leave deliberately persistent state behind.
    const auto RunStrictResolverCase = [&](const FString& InCaseName,
                                            const TArray<FVector>& InWaypoints,
                                            const TArray<FCk_GroundNavPath_LinkWaypoint>& InLinkWaypoints,
                                            const FVector& InDiscCenter,
                                            const bool InExpectInstall) -> bool
    {
        AddInfo(FString::Printf(TEXT("Strict GroundNav resolver case: %s"), *InCaseName));

        auto* CaseWorld = UWorld::CreateWorld(
            EWorldType::Game, kInformEngineOfWorld, FName{TEXT("CrowdStrictResolver")});
        if (NOT TestNotNull(TEXT("the resolver case owns a game world"), CaseWorld))
        { return false; }

        const auto CaseTeardown = [&]
        {
            CaseWorld->DestroyWorld(kInformEngineOfWorld);
        };

        auto CaseWorldEntity = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(CaseWorld);
        if (NOT TestTrue(TEXT("the resolver case has its transient ECS entity"), ck::IsValid(CaseWorldEntity)))
        {
            CaseTeardown();
            return false;
        }

        CaseWorldEntity.AddOrGet<ck::FFragment_NavSurface_Provider>();
        CaseWorldEntity.AddOrGet<ck::FFragment_NavSurface_RevisionWatch>();
        CaseWorldEntity.AddOrGet<ck::FFragment_NavSurface_PendingRebuilds>();
        UCk_Utils_NavSurface_UE::Request_SetProvider(CaseWorld, ECk_NavSurface_Provider::GroundNav);

        auto CaseOwner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CaseWorldEntity);
        CaseOwner.AddOrGet<ck::FTag_HasAuthority>();
        auto CaseTransform = UCk_Utils_Transform_UE::Add(
            CaseOwner, FTransform{FVector::ZeroVector}, ECk_Replication::DoesNotReplicate);
        auto CaseAgent = UCk_Utils_CrowdAgent_UE::Add(
            CaseTransform, FCk_Fragment_CrowdAgent_ParamsData{kAgentRadiusUu, kAgentHeightUu});

        auto CaseBlockerOwner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CaseWorldEntity);
        auto CaseBlockerTransform = UCk_Utils_Transform_UE::Add(
            CaseBlockerOwner, FTransform{InDiscCenter}, ECk_Replication::DoesNotReplicate);
        auto CaseBlocker = UCk_Utils_CrowdAgent_UE::Add(
            CaseBlockerTransform, FCk_Fragment_CrowdAgent_ParamsData{kAgentRadiusUu, kAgentHeightUu});

        if (NOT TestTrue(TEXT("the resolver case composed an agent"), ck::IsValid(CaseAgent)) ||
            NOT TestTrue(TEXT("the resolver case composed its independent blocker"), ck::IsValid(CaseBlocker)))
        {
            CaseTeardown();
            return false;
        }

        // The verifier admits a disc only when its persisted neutral markup handle is real. Do not
        // fabricate a default handle: Request_AreaMarkup is the public producer used by the painter.
        const auto LiveMarkup = UCk_Utils_NavSurface_UE::Request_AreaMarkup(
            CaseWorld,
            FCk_Request_NavSurface_AreaMarkup{
                FCk_AnyShape{FCk_ShapeBox_Dimensions{FVector{20.0f, 20.0f, 120.0f}}},
                TAG_Nav_Area_Crowd_Agent.GetTag()},
            {});
        if (NOT TestTrue(TEXT("the blocker owns a facade-created markup handle"), ck::IsValid(LiveMarkup)))
        {
            CaseTeardown();
            return false;
        }

        auto& CaseMarkup = CaseBlocker.Get<ck::FFragment_CrowdAgent_NavMarkup>();
        CaseMarkup._Markup = LiveMarkup;
        CaseMarkup._MarkupLocation = InDiscCenter;
        CaseMarkup._MarkupRadiusUu = 20.0f;
        CaseMarkup._MarkupVerticalHalfExtentUu = 120.0f;
        CaseMarkup._ConfirmedOnMesh = true;

        constexpr auto kResolverRevision = 701;
        auto& CasePathFollow = CaseAgent.Get<ck::FFragment_CrowdAgent_PathFollow>();
        CasePathFollow._ActiveGoal = FVector{500.0f, 0.0f, 0.0f};
        CasePathFollow._ActiveArrivalRadius = 0.0f;
        CasePathFollow._ActiveNavigationRequestRevision = kResolverRevision;
        CasePathFollow._ActiveProvider = ECk_CrowdAgent_PathProvider::GroundNav;
        CasePathFollow._PlanPhase = ECk_CrowdAgent_PlanPhase::Strict;
        CasePathFollow._PlanUsesStrictStandingCrowdFilter = true;
        CaseAgent.AddOrGet<ck::FTag_CrowdAgent_PathPending>();

        // These are the two slots the actual GroundNav dispatch establishes before a result reaches
        // this resolver. The test injects only the completed provider answer, never a partial handle.
        FCk_Nav_Algorithm::MarkPathPending(CaseAgent, kResolverRevision);
        UCk_Utils_GroundNavPath_UE::Add(
            CaseAgent, FCk_Fragment_GroundNavPath_ParamsData{kAgentRadiusUu});

        if (NOT TestTrue(TEXT("the resolver fixture composed its GroundNav path feature"),
            UCk_Utils_GroundNavPath_UE::Has(CaseAgent)) ||
            NOT TestTrue(TEXT("the resolver fixture owns a GroundNav result slot"),
            CaseAgent.Has<ck::FFragment_GroundNavPath_Result>()) ||
            NOT TestTrue(TEXT("the resolver fixture owns a terminal navigation slot"),
            CaseAgent.Has<ck::FFragment_Nav_PathResult>()))
        {
            CaseTeardown();
            return false;
        }

        auto Published = FCk_GroundNavPath_Result{};
        Published.Set_Status(ECk_GroundNav_PathStatus::Ready)
            .Set_Waypoints(InWaypoints)
            .Set_RequestRevision(kResolverRevision)
            .Set_LinkWaypoints(InLinkWaypoints);

        auto& Slot = CaseAgent.Get<ck::FFragment_GroundNavPath_Result>();
        Slot._Result = MoveTemp(Published);
        Slot._HasFreshResult = true;

        ck::FProcessor_CrowdAgent_OnGroundNavPathResolved{CaseWorldEntity.Get_RegistryView()}.ForEachEntity(
            FCk_Time{}, CaseAgent, CaseAgent.Get<ck::FFragment_Transform>(), Slot, CasePathFollow);

        const auto& InstalledNav = CaseAgent.Get<ck::FFragment_Nav_PathResult>();
        const auto ExpectedStatus = InExpectInstall ? ECk_Nav_PathStatus::Ready : ECk_Nav_PathStatus::Failed;
        TestEqual(TEXT("the real resolver records the expected terminal navigation state"),
            InstalledNav.Get_Status(), ExpectedStatus);
        TestEqual(TEXT("the resolver acts on the result revision it was given"),
            InstalledNav.Get_RequestRevision(), kResolverRevision);

        if (InExpectInstall)
        {
            TestTrue(TEXT("the verified authored-link result was installed"),
                CaseAgent.Has<ck::FFragment_CrowdAgent_InstalledGroundNavPath>());
        }
        else
        {
            TestEqual(TEXT("the rejected strict result has the crowd-free route failure reason"),
                InstalledNav.Get_Diagnostics().Get_LastFailReason(), ECk_Nav_PathFailReason::FindPathNoPath);
            TestFalse(TEXT("the rejected strict result never installs a ground route identity"),
                CaseAgent.Has<ck::FFragment_CrowdAgent_InstalledGroundNavPath>());
        }

        CaseTeardown();
        return true;
    };

    const auto MakeReadyLinkResult = [](const TArray<FVector>& InWaypoints,
                                        const TArray<FCk_GroundNavPath_LinkWaypoint>& InMetadata)
    {
        return TTuple<TArray<FVector>, TArray<FCk_GroundNavPath_LinkWaypoint>>{InWaypoints, InMetadata};
    };

    constexpr auto kLinkId = 17;
    const auto LinkEntry = [=](int32 InWaypointIndex)
    {
        return FCk_GroundNavPath_LinkWaypoint{
            InWaypointIndex, kLinkId, ECk_GroundNavPath_LinkWaypointRole::Entry,
            ECk_GroundNav_LinkDirection::Forward, 0.0f};
    };
    const auto LinkExit = [=](int32 InWaypointIndex)
    {
        return FCk_GroundNavPath_LinkWaypoint{
            InWaypointIndex, kLinkId, ECk_GroundNavPath_LinkWaypointRole::Exit,
            ECk_GroundNav_LinkDirection::Forward, 0.0f};
    };

    // The link itself may cross a standing disc. The grounded approach and landing stay clear, so
    // only a complete Entry -> Exit pair can make this result installable.
    const auto ValidLink = MakeReadyLinkResult(
        {FVector{100.0f, 0.0f, 0.0f}, FVector{300.0f, 0.0f, 0.0f}, FVector{500.0f, 0.0f, 0.0f}},
        {LinkEntry(0), LinkExit(1)});
    if (NOT RunStrictResolverCase(TEXT("CompleteLinkCrossesDiscInterior"), ValidLink.Get<0>(), ValidLink.Get<1>(),
        FVector{200.0f, 0.0f, 0.0f}, true))
    { return false; }

    // A link cannot escape the initial union: its Entry is a waypoint and the ground leg from the
    // body's actual start to that Entry must still be clear.
    const auto BlockedApproach = MakeReadyLinkResult(
        {FVector{300.0f, 0.0f, 0.0f}, FVector{400.0f, 0.0f, 0.0f}, FVector{500.0f, 0.0f, 0.0f}},
        {LinkEntry(0), LinkExit(1)});
    if (NOT RunStrictResolverCase(TEXT("LinkCannotEscapeInitialUnion"), BlockedApproach.Get<0>(), BlockedApproach.Get<1>(),
        FVector{100.0f, 0.0f, 0.0f}, false))
    { return false; }

    // The Exit only ends the exempt authored traversal; its ground landing is checked like every
    // other ordinary leg.
    const auto BlockedLanding = MakeReadyLinkResult(
        {FVector{100.0f, 0.0f, 0.0f}, FVector{200.0f, 0.0f, 0.0f}, FVector{500.0f, 0.0f, 0.0f}},
        {LinkEntry(0), LinkExit(1)});
    if (NOT RunStrictResolverCase(TEXT("BlockedGroundLandingRejected"), BlockedLanding.Get<0>(), BlockedLanding.Get<1>(),
        FVector{300.0f, 0.0f, 0.0f}, false))
    { return false; }

    // A hand-written pair with a mismatched authored id cannot certify a traversal, even if its
    // geometry otherwise looks like the valid case.
    auto MalformedMetadata = TArray<FCk_GroundNavPath_LinkWaypoint>{LinkEntry(0), LinkExit(1)};
    MalformedMetadata[1] = FCk_GroundNavPath_LinkWaypoint{
        1, kLinkId + 1, ECk_GroundNavPath_LinkWaypointRole::Exit,
        ECk_GroundNav_LinkDirection::Forward, 0.0f};
    if (NOT RunStrictResolverCase(TEXT("MalformedLinkMetadataRejected"), ValidLink.Get<0>(), MalformedMetadata,
        FVector{200.0f, 0.0f, 0.0f}, false))
    { return false; }

    return true;
}
