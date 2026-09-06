#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"

#include "CkCrowd/Agent/CkCrowdAgent_DebugDraw_Processor.h"
#include "CkCrowd/Agent/CkCrowdAgent_DrawNavProjection_Processor.h"
#include "CkCrowd/Agent/CkCrowdAgent_Utils.h"
#include "CkCrowd/Settings/CkCrowd_DebugSettings.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkEcsExt/Transform/CkTransform_Utils.h"

#include "CkTests/Net/CkNetAutomation_Common.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_crowd_debug_draw_outer_gate
{
    constexpr auto EntryMapPath = TEXT("/Engine/Maps/Entry");
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto AgentSetupTimeoutSeconds = 10.0f;

    static FCk_Handle_CrowdAgent GAgent;
    static bool GDrawSeparationBeforeTest = false;
    static bool GDrawNavProjectionBeforeTest = false;

    auto Get_DrawSettings() -> UCk_Crowd_DebugSettings_UE*
    {
        return GetMutableDefault<UCk_Crowd_DebugSettings_UE>();
    }

    auto Get_IsAgentFullyComposed() -> bool
    {
        return ck::IsValid(GAgent) && GAgent.Has<ck::FTag_CrowdAgent_HasProbe>();
    }

    class FCk_Latent_RestoreCrowdDebugSettings final : public IAutomationLatentCommand
    {
    public:
        FCk_Latent_RestoreCrowdDebugSettings(bool InDrawSeparation, bool InDrawNavProjection)
            : _DrawSeparation(InDrawSeparation)
            , _DrawNavProjection(InDrawNavProjection) {}

        virtual bool Update() override
        {
            if (auto* Settings = Get_DrawSettings())
            {
                Settings->Set_DrawSeparation(_DrawSeparation);
                Settings->Set_DrawNavProjection(_DrawNavProjection);
            }
            return true;
        }

    private:
        bool _DrawSeparation = false;
        bool _DrawNavProjection = false;
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

    auto* Settings = Get_DrawSettings();
    if (NOT TestNotNull(TEXT("crowd debug settings CDO is available"), Settings))
    { return false; }

    GDrawSeparationBeforeTest = Settings->Get_DrawSeparation();
    GDrawNavProjectionBeforeTest = Settings->Get_DrawNavProjection();
    Settings->Set_DrawSeparation(false);
    Settings->Set_DrawNavProjection(false);

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

            TestTrue(TEXT("crowd agent composed through its production utility"), ck::IsValid(GAgent));
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            return Get_IsAgentFullyComposed();
        }),
        AgentSetupTimeoutSeconds,
        TEXT("crowd setup created the production probe and marked the agent HasProbe")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            TestTrue(TEXT("crowd agent completed production probe setup before debug-gate checks"),
                Get_IsAgentFullyComposed());

            auto* Ecs = InServer != nullptr ? InServer->GetSubsystem<UCk_EcsWorld_Subsystem_UE>() : nullptr;
            if (NOT TestNotNull(TEXT("server retains the ECS world for debug-gate checks"), Ecs))
            { return; }

            auto DebugDraw = ck::FProcessor_CrowdAgent_DebugDraw{Ecs->Get_Registry()};
            auto NavProjection = ck::FProcessor_CrowdAgent_DrawNavProjection{Ecs->Get_Registry()};

            TestEqual(TEXT("disabled separation debug skips the production processor view"),
                DebugDraw.Pump(), 0);

            Get_DrawSettings()->Set_DrawSeparation(true);
            TestEqual(TEXT("enabling separation debug immediately restores the composed agent visit"),
                DebugDraw.Pump(), 1);

            Get_DrawSettings()->Set_DrawSeparation(false);
            TestEqual(TEXT("disabling separation debug again removes the processor visit"),
                DebugDraw.Pump(), 0);

            TestEqual(TEXT("disabled nav-projection debug skips the production processor view"),
                NavProjection.Pump(), 0);

            Get_DrawSettings()->Set_DrawNavProjection(true);
            TestEqual(TEXT("enabling nav-projection debug immediately restores the composed agent visit"),
                NavProjection.Pump(), 1);

            Get_DrawSettings()->Set_DrawNavProjection(false);
            TestEqual(TEXT("disabling nav-projection debug again removes the processor visit"),
                NavProjection.Pump(), 0);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RestoreCrowdDebugSettings(
        GDrawSeparationBeforeTest, GDrawNavProjectionBeforeTest));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
