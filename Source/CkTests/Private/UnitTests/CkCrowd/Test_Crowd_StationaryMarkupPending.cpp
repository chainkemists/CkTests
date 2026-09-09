// Initial route admission can leave an agent physically still while no corridor has been installed.
// This test drives the real stationary-markup processor over normally composed CrowdAgents, so the
// pending gate is proven at the producer rather than by copying its eligibility expression.

#include "CkCrowd/Agent/CkCrowdAgent_Fragment.h"
#include "CkCrowd/Agent/CkCrowdAgent_StationaryMarkup_Processor.h"
#include "CkCrowd/Agent/CkCrowdAgent_Utils.h"
#include "CkCrowd/Settings/CkCrowd_ProjectSettings.h"

#include "CkCore/Time/CkTime.h"
#include "CkCore/Validation/CkIsValid.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Net/CkNet_Fragment.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"
#include "CkEcsExt/Transform/CkTransform_Utils.h"
#include "CkNavigation/Nav/CkNav_Algorithm.h"
#include "CkNavigation/Nav/CkNav_Fragment.h"
#include "CkNavigation/NavSurface/CkNavSurface_Fragment.h"
#include "CkNavigation/NavSurface/CkNavSurface_Utils.h"

#include "Engine/World.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_StationaryMarkupPending_InitialRoutesDoNotPaint,
    "CkTests.UnitTests.CkCrowd.StationaryMarkup.Pending.InitialRoutesDoNotPaint",
    kCkUnitTestFlags)

bool FCkTest_Crowd_StationaryMarkupPending_InitialRoutesDoNotPaint::RunTest(const FString& InParameters)
{
    constexpr auto kInformEngineOfWorld = false;
    constexpr auto kAgentRadiusUu = 42.0f;
    constexpr auto kAgentHeightUu = 192.0f;

    auto* World = UWorld::CreateWorld(
        EWorldType::Game, kInformEngineOfWorld, FName{TEXT("CrowdStationaryMarkupPending")});
    if (NOT TestNotNull(TEXT("the fixture owns a game world"), World))
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

    // The processor raises a real NavSurface markup request. These are the normal world-owned
    // request fragments; this focused fixture intentionally does not drain them into a provider.
    WorldEntity.AddOrGet<ck::FFragment_NavSurface_Provider>();
    WorldEntity.AddOrGet<ck::FFragment_NavSurface_RevisionWatch>();
    WorldEntity.AddOrGet<ck::FFragment_NavSurface_PendingRebuilds>();
    UCk_Utils_NavSurface_UE::Request_SetProvider(World, ECk_NavSurface_Provider::GroundNav);

    const auto MakeAgent = [&]() -> FCk_Handle_CrowdAgent
    {
        auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(WorldEntity);
        Owner.AddOrGet<ck::FTag_HasAuthority>();
        auto Transform = UCk_Utils_Transform_UE::Add(
            Owner, FTransform{FVector::ZeroVector}, ECk_Replication::DoesNotReplicate);
        return UCk_Utils_CrowdAgent_UE::Add(
            Transform, FCk_Fragment_CrowdAgent_ParamsData{kAgentRadiusUu, kAgentHeightUu});
    };

    const auto RunStationaryMarkup = [](FCk_Handle_CrowdAgent& InAgent, float InSeconds)
    {
        ck::FProcessor_CrowdAgent_StationaryMarkup::ForEachEntity(
            FCk_Time{InSeconds}, InAgent,
            InAgent.Get<ck::FFragment_Transform>(),
            InAgent.Get<ck::FFragment_CrowdAgent_Params>(),
            InAgent.Get<ck::FFragment_CrowdAgent_NavMarkup>());
    };

    auto PendingWithoutSlot = TArray<FCk_Handle_CrowdAgent>{
        MakeAgent(), MakeAgent(), MakeAgent(), MakeAgent(), MakeAgent()};
    auto PendingWithEmptySlot = TArray<FCk_Handle_CrowdAgent>{
        MakeAgent(), MakeAgent(), MakeAgent(), MakeAgent()};
    auto Installed = MakeAgent();
    auto RetainedRoutePending = MakeAgent();
    auto Idle = MakeAgent();

    const auto HasTwelveComposedAgents =
        PendingWithoutSlot.Num() + PendingWithEmptySlot.Num() + 3 == 12;
    auto AllAgentsAreValid = true;
    for (const auto& Agent : PendingWithoutSlot)
    { AllAgentsAreValid = AllAgentsAreValid && ck::IsValid(Agent); }
    for (const auto& Agent : PendingWithEmptySlot)
    { AllAgentsAreValid = AllAgentsAreValid && ck::IsValid(Agent); }
    AllAgentsAreValid = AllAgentsAreValid && ck::IsValid(Installed) &&
        ck::IsValid(RetainedRoutePending) && ck::IsValid(Idle);

    if (NOT TestTrue(TEXT("the fixture composed a twelve-agent Crowd cohort"), HasTwelveComposedAgents) ||
        NOT TestTrue(TEXT("all Crowd fixture agents are composed"), AllAgentsAreValid))
    {
        Teardown();
        return false;
    }

    const auto SetPending = [](FCk_Handle_CrowdAgent& InAgent)
    {
        InAgent.Try_Remove<ck::FTag_CrowdAgent_Idle>();
        InAgent.AddOrGet<ck::FTag_CrowdAgent_PathPending>();
    };

    for (auto& Agent : PendingWithoutSlot)
    { SetPending(Agent); }

    const auto* Settings = UCk_Utils_Crowd_Settings_UE::Get();
    if (NOT TestNotNull(TEXT("stationary-markup settings are available"), Settings) ||
        NOT TestTrue(TEXT("the fixture has a finite positive stationary delay"),
            FMath::IsFinite(Settings->Get_StationaryMarkupDelaySeconds()) &&
            Settings->Get_StationaryMarkupDelaySeconds() > 0.0f) ||
        NOT TestTrue(TEXT("the fixture has stationary markup enabled"),
            Settings->Get_StationaryMarkupMode() == ECk_CrowdStationaryMarkupMode::Enabled))
    {
        Teardown();
        return false;
    }

    // Paint once while idle so the first empty-slot case also proves the new initial-pending branch
    // removes a pre-existing request before it can be confirmed by a provider drain.
    const auto DelaySeconds = Settings->Get_StationaryMarkupDelaySeconds();
    const auto SettleSeconds = DelaySeconds + 0.25f;
    RunStationaryMarkup(PendingWithEmptySlot[0], SettleSeconds);
    if (NOT TestTrue(TEXT("the idle setup pass created a real markup request"),
        ck::IsValid(PendingWithEmptySlot[0].Get<ck::FFragment_CrowdAgent_NavMarkup>().Get_Markup())))
    {
        Teardown();
        return false;
    }

    for (auto& Agent : PendingWithEmptySlot)
    {
        FCk_Nav_Algorithm::MarkPathPending(Agent, 101);
        SetPending(Agent);
    }

    FCk_Nav_Algorithm::InstallExternalPath(
        Installed, TArray<FVector>{FVector{500.0, 0.0, 0.0}}, FVector{500.0, 0.0, 0.0}, 201);
    Installed.Try_Remove<ck::FTag_CrowdAgent_Idle>();
    Installed.AddOrGet<ck::FTag_CrowdAgent_Walking>();

    FCk_Nav_Algorithm::InstallExternalPath(
        RetainedRoutePending, TArray<FVector>{FVector{600.0, 0.0, 0.0}}, FVector{600.0, 0.0, 0.0}, 301);
    SetPending(RetainedRoutePending);
    FCk_Nav_Algorithm::MarkPathPending(RetainedRoutePending, 302);

    if (NOT TestTrue(TEXT("the pending refresh retains its previously installed corridor"),
        RetainedRoutePending.Get<ck::FFragment_Nav_PathResult>().Get_Waypoints().Num() == 1) ||
        NOT TestEqual(TEXT("the retained corridor carries the newer pending revision"),
        RetainedRoutePending.Get<ck::FFragment_Nav_PathResult>().Get_RequestRevision(), 302))
    {
        Teardown();
        return false;
    }

    for (auto& Agent : PendingWithoutSlot)
    { RunStationaryMarkup(Agent, SettleSeconds); }
    for (auto& Agent : PendingWithEmptySlot)
    { RunStationaryMarkup(Agent, SettleSeconds); }

    for (const auto& Agent : PendingWithoutSlot)
    {
        const auto& Markup = Agent.Get<ck::FFragment_CrowdAgent_NavMarkup>();
        TestFalse(TEXT("an initial pending agent without a result slot does not paint"),
            ck::IsValid(Markup.Get_Markup()));
        TestFalse(TEXT("an initial pending agent without a result slot cannot confirm"),
            Markup.Get_ConfirmedOnMesh());
    }

    // Waiting time is intentionally discarded: when the first route arrives, the agent must earn
    // a full stationary delay instead of painting in the next processor call.
    auto& AdmittedAgent = PendingWithoutSlot[0];
    FCk_Nav_Algorithm::InstallExternalPath(
        AdmittedAgent, TArray<FVector>{FVector{700.0, 0.0, 0.0}}, FVector{700.0, 0.0, 0.0}, 401);
    AdmittedAgent.Try_Remove<ck::FTag_CrowdAgent_PathPending>();
    AdmittedAgent.AddOrGet<ck::FTag_CrowdAgent_Walking>();
    RunStationaryMarkup(AdmittedAgent, DelaySeconds * 0.5f);
    TestFalse(TEXT("a route admitted after waiting does not inherit pending stillness"),
        ck::IsValid(AdmittedAgent.Get<ck::FFragment_CrowdAgent_NavMarkup>().Get_Markup()));
    RunStationaryMarkup(AdmittedAgent, SettleSeconds);
    TestTrue(TEXT("the admitted route can paint after its own stationary delay"),
        ck::IsValid(AdmittedAgent.Get<ck::FFragment_CrowdAgent_NavMarkup>().Get_Markup()));

    RunStationaryMarkup(Installed, SettleSeconds);
    RunStationaryMarkup(RetainedRoutePending, SettleSeconds);
    RunStationaryMarkup(Idle, SettleSeconds);
    for (const auto& Agent : PendingWithEmptySlot)
    {
        const auto& Markup = Agent.Get<ck::FFragment_CrowdAgent_NavMarkup>();
        TestFalse(TEXT("an initial pending agent with an empty result slot does not paint"),
            ck::IsValid(Markup.Get_Markup()));
        TestFalse(TEXT("an initial pending agent with an empty result slot cannot confirm"),
            Markup.Get_ConfirmedOnMesh());
    }

    TestTrue(TEXT("an installed route still permits stationary markup"),
        ck::IsValid(Installed.Get<ck::FFragment_CrowdAgent_NavMarkup>().Get_Markup()));
    TestTrue(TEXT("a pending refresh with a retained route still permits stationary markup"),
        ck::IsValid(RetainedRoutePending.Get<ck::FFragment_CrowdAgent_NavMarkup>().Get_Markup()));
    TestTrue(TEXT("an idle agent without a navigation result still permits stationary markup"),
        ck::IsValid(Idle.Get<ck::FFragment_CrowdAgent_NavMarkup>().Get_Markup()));

    Teardown();
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
