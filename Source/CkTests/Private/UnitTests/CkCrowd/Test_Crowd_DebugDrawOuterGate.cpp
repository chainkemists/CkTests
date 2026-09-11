#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"

#include "CkCrowd/Agent/CkCrowdAgent_DebugDraw_Processor.h"
#include "CkCrowd/Agent/CkCrowdAgent_DrawNavStatus_Processor.h"
#include "CkCrowd/Agent/CkCrowdAgent_Utils.h"
#include "CkCrowd/Settings/CkCrowd_DebugSettings.h"

#include "CkCore/Diagnostics/CkDiagnosticVisibility.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkEcsExt/Transform/CkTransform_Utils.h"

#include "CkNavigation/Utils/CkNav_Utils.h"

#include "CkTests/Net/CkNetAutomation_Common.h"

#include "../CkUnitTest_Common.h"

#include <HAL/IConsoleManager.h>

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_crowd_debug_draw_outer_gate
{
    constexpr auto EntryMapPath = TEXT("/Engine/Maps/Entry");
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto AgentSetupTimeoutSeconds = 10.0f;

    static FCk_Handle_CrowdAgent GAgent;
    static bool GDrawSeparationBeforeTest = false;
    static bool GDrawPathTroubleBeforeTest = false;
    static IConsoleVariable* GStreamerModeCVar = nullptr;
    static FString GStreamerModeBeforeTest;
    static EConsoleVariableFlags GStreamerModePriorityBeforeTest = ECVF_SetByConstructor;

    auto Get_DrawSettings() -> UCk_Crowd_DebugSettings_UE*
    {
        return GetMutableDefault<UCk_Crowd_DebugSettings_UE>();
    }

    auto Get_IsAgentFullyComposed() -> bool
    {
        return ck::IsValid(GAgent) &&
               GAgent.Has<ck::FTag_CrowdAgent_HasProbe>() &&
               GAgent.Has<ck::FFragment_Nav_PathResult>() &&
               GAgent.Has<ck::FFragment_CrowdAgent_PathFollow>() &&
               GAgent.Has<ck::FFragment_CrowdAgent_PathTrouble>();
    }

    auto Restore_StreamerMode() -> void
    {
        if (GStreamerModeCVar == nullptr)
        { return; }

        const auto CurrentPriority = static_cast<EConsoleVariableFlags>(
            GStreamerModeCVar->GetFlags() & ECVF_SetByMask);
        GStreamerModeCVar->Set(*GStreamerModeBeforeTest, CurrentPriority);
        GStreamerModeCVar->SetFlags(static_cast<EConsoleVariableFlags>(
            (GStreamerModeCVar->GetFlags() & ~ECVF_SetByMask) | GStreamerModePriorityBeforeTest));
    }

    class FCk_Latent_RestoreCrowdDebugSettings final : public IAutomationLatentCommand
    {
    public:
        FCk_Latent_RestoreCrowdDebugSettings(bool InDrawSeparation, bool InDrawPathTrouble)
            : _DrawSeparation(InDrawSeparation)
            , _DrawPathTrouble(InDrawPathTrouble) {}

        virtual bool Update() override
        {
            if (auto* Settings = Get_DrawSettings())
            {
                Settings->Set_DrawSeparation(_DrawSeparation);
                Settings->Set_DrawPathTrouble(_DrawPathTrouble);
            }
            return true;
        }

    private:
        bool _DrawSeparation = false;
        bool _DrawPathTrouble = false;
    };

    class FCk_Latent_RestoreStreamerMode final : public IAutomationLatentCommand
    {
    public:
        virtual bool Update() override
        {
            Restore_StreamerMode();
            return true;
        }
    };
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_DebugDrawOuterGate_TogglesLive,
    "CkTests.UnitTests.CkCrowd.DebugDraw.OuterGateTogglesLive",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkTest_Crowd_DebugDrawOuterGate_TogglesLive::RunTest(const FString& Parameters)
{
    using namespace ck_test_crowd_debug_draw_outer_gate;

    GAgent = FCk_Handle_CrowdAgent{};

    GStreamerModeCVar = IConsoleManager::Get().FindConsoleVariable(TEXT("ck.Debug.StreamerMode"));
    if (NOT TestNotNull(TEXT("streamer-mode CVar is available"), GStreamerModeCVar))
    { return false; }

    GStreamerModeBeforeTest = GStreamerModeCVar->GetString();
    GStreamerModePriorityBeforeTest = static_cast<EConsoleVariableFlags>(
        GStreamerModeCVar->GetFlags() & ECVF_SetByMask);
    GStreamerModeCVar->Set(0, ECVF_SetByCode);
    if (NOT TestFalse(TEXT("the test can force diagnostic visibility outside streamer mode"),
        ck::diagnostic_visibility::Is_HiddenForStreamerMode()))
    {
        Restore_StreamerMode();
        return false;
    }

    auto* Settings = Get_DrawSettings();
    if (NOT TestNotNull(TEXT("crowd debug settings CDO is available"), Settings))
    {
        Restore_StreamerMode();
        return false;
    }

    GDrawSeparationBeforeTest = Settings->Get_DrawSeparation();
    GDrawPathTroubleBeforeTest = Settings->Get_DrawPathTrouble();
    Settings->Set_DrawSeparation(false);
    Settings->Set_DrawPathTrouble(false);

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, EntryMapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, ReadyTimeoutSeconds));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Ecs = InServer != nullptr ? InServer->GetSubsystem<UCk_EcsWorld_Subsystem_UE>() : nullptr;
            if (NOT TestNotNull(TEXT("server has an ECS world for crowd composition"), Ecs))
            { return; }

            auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InServer, {});
            auto Transform = UCk_Utils_Transform_UE::Add(
                Owner, FTransform{FVector{10000.0f, 10000.0f, 10000.0f}}, ECk_Replication::DoesNotReplicate);
            GAgent = UCk_Utils_CrowdAgent_UE::Add(
                Transform, FCk_Fragment_CrowdAgent_ParamsData{42.0f, 192.0f});
            if (NOT TestTrue(TEXT("crowd agent composed through its production utility"), ck::IsValid(GAgent)))
            { return; }

            // Crowd owns the movement episode as well as its lazy Nav result. A direct Nav request
            // would create a pending slot without that episode and violate the watchdog contract.
            UCk_Utils_CrowdAgent_UE::Request_MoveTo(
                GAgent, FCk_Request_CrowdAgent_MoveTo{FVector{10100.0f, 10000.0f, 10000.0f}}, {});

        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            return Get_IsAgentFullyComposed();
        }),
        AgentSetupTimeoutSeconds,
        TEXT("crowd setup created the production fragments required by both debug processors")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            if (NOT TestTrue(TEXT("crowd agent completed production composition before debug-gate checks"),
                Get_IsAgentFullyComposed()))
            { return; }

            auto* Ecs = InServer != nullptr ? InServer->GetSubsystem<UCk_EcsWorld_Subsystem_UE>() : nullptr;
            if (NOT TestNotNull(TEXT("server retains the ECS world for debug-gate checks"), Ecs))
            { return; }

            auto DebugDraw = ck::FProcessor_CrowdAgent_DebugDraw{Ecs->Get_Registry()};
            auto NavStatus = ck::FProcessor_CrowdAgent_DrawNavStatus{Ecs->Get_Registry()};

            TestEqual(TEXT("disabled separation debug skips the production processor view"),
                DebugDraw.Pump(), 0);

            Get_DrawSettings()->Set_DrawSeparation(true);
            TestEqual(TEXT("enabling separation debug immediately restores the composed agent visit"),
                DebugDraw.Pump(), 1);

            Get_DrawSettings()->Set_DrawSeparation(false);
            TestEqual(TEXT("disabling separation debug again removes the processor visit"),
                DebugDraw.Pump(), 0);

            TestEqual(TEXT("disabled nav-status debug skips the production processor view"),
                NavStatus.Pump(), 0);

            Get_DrawSettings()->Set_DrawPathTrouble(true);
            TestEqual(TEXT("enabling nav-status debug immediately restores the composed agent visit"),
                NavStatus.Pump(), 1);

            Get_DrawSettings()->Set_DrawPathTrouble(false);
            TestEqual(TEXT("disabling nav-status debug again removes the processor visit"),
                NavStatus.Pump(), 0);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RestoreCrowdDebugSettings(
        GDrawSeparationBeforeTest, GDrawPathTroubleBeforeTest));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RestoreStreamerMode());
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
