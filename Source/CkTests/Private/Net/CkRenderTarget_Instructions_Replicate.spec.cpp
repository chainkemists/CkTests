// Channel A (instruction replication) coverage for CkRenderTarget.
//
// A Replicates / InstructionsOnly RenderTarget sync child is composed symmetrically on the server
// and one client via the shared NetSubject. Two scenarios:
//
//   1. Instructions_DrawReplicates — server draws a 2-cmd batch after both worlds composed; the
//      client's replay watermark advances to the batch seq (the rep handler enqueued, the apply
//      processor committed, OnInstructionsApplied fired with the wire seq).
//
//   2. Instructions_EarlyDraw_AppliesAfterComposition — server draws immediately after spawning
//      the subject, before the client has composed its sync child. The container's initial value
//      lands while the client handler returns NotReady; the dispatcher retries until composition
//      completes, then the batch applies (Apply/NotReady contract + stash-and-flush ordering).
//
// Surface in Session Frontend: Ck.RenderTarget.Net.*

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"

#include "CkRenderTarget/RenderTarget/CkRenderTarget_Utils.h"

#include "CkTests/Net/CkAutoTest_NetSubject.h"
#include "CkTests/Net/CkAutoTest_NetSubject_RenderTarget.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_render_target_net_spec
{
    auto DrawTwoCmdBatch(FAutomationTestBase* InTest, UWorld* InServer) -> void
    {
        auto* Subject = Cast<ACk_AutoTest_NetSubject_RenderTarget_UE>(ACk_AutoTest_NetSubject::Find(InServer));
        if (Subject == nullptr || ck::Is_NOT_Valid(Subject->_TestRenderTarget))
        {
            InTest->AddError(TEXT("server-side RenderTarget subject / _TestRenderTarget missing at draw time"));
            return;
        }

        UCk_Utils_RenderTarget_UE::Request_DrawLine(Subject->_TestRenderTarget,
            FCk_Request_RenderTarget_DrawLine{FVector2D{0.0, 0.0}, FVector2D{32.0, 32.0}});
        UCk_Utils_RenderTarget_UE::Request_DrawBox(Subject->_TestRenderTarget,
            FCk_Request_RenderTarget_DrawBox{FVector2D{8.0, 8.0}, FVector2D{16.0, 16.0}});
    }

    auto AssertBothWorldsAtSeq(FAutomationTestBase* InTest, int32 InExpectedSeq) -> bool
    {
        auto* Server = ck::auto_test::net::Get_ServerWorld();
        auto* Client = ck::auto_test::net::Get_ClientWorld(0);
        if (Server == nullptr || Client == nullptr)
        {
            InTest->AddError(TEXT("server and/or client world unavailable at assertion time"));
            return false;
        }

        auto* ServerSubject = Cast<ACk_AutoTest_NetSubject_RenderTarget_UE>(ACk_AutoTest_NetSubject::Find(Server));
        if (ServerSubject != nullptr && ck::IsValid(ServerSubject->_TestRenderTarget))
        {
            InTest->TestEqual(TEXT("server applied the batch locally"),
                UCk_Utils_RenderTarget_UE::Get_LatestAppliedBatchSeq(ServerSubject->_TestRenderTarget),
                InExpectedSeq);
        }
        else
        { InTest->AddError(TEXT("server-side RenderTarget subject / _TestRenderTarget missing at assertion time")); }

        auto* ClientSubject = Cast<ACk_AutoTest_NetSubject_RenderTarget_UE>(ACk_AutoTest_NetSubject::Find(Client));
        if (ClientSubject != nullptr && ck::IsValid(ClientSubject->_TestRenderTarget))
        {
            InTest->TestEqual(TEXT("client replayed the batch from the wire"),
                UCk_Utils_RenderTarget_UE::Get_LatestAppliedBatchSeq(ClientSubject->_TestRenderTarget),
                InExpectedSeq);
        }
        else
        { InTest->AddError(TEXT("client-side RenderTarget subject / _TestRenderTarget missing at assertion time")); }

        return true;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkRenderTargetNet_Instructions_DrawReplicates,
    "Ck.RenderTarget.Net.Instructions_DrawReplicates",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkRenderTargetNet_Instructions_DrawReplicates::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesAfterSpawn = 30;   // symmetric composition + setup on both worlds
    constexpr auto FramesAfterDraw = 30;    // local apply + container delta + client replay

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
            auto* Subject = InServer->SpawnActor<ACk_AutoTest_NetSubject_RenderTarget_UE>(
                ACk_AutoTest_NetSubject_RenderTarget_UE::StaticClass(), FTransform::Identity, SpawnInfo);
            if (Subject == nullptr)
            { AddError(TEXT("server-side SpawnActor of ACk_AutoTest_NetSubject_RenderTarget_UE returned null")); }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterSpawn));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            ck_render_target_net_spec::DrawTwoCmdBatch(this, InServer);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterDraw));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            return ck_render_target_net_spec::AssertBothWorldsAtSeq(this, 1);
        }),
        TEXT("server and client both applied instruction batch seq 1")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            FAutomationTestBase::bSuppressLogErrors = false;
            FAutomationTestBase::bSuppressLogWarnings = false;
            return true;
        }),
        TEXT("restore log suppression statics")));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkRenderTargetNet_Instructions_EarlyDraw_AppliesAfterComposition,
    "Ck.RenderTarget.Net.Instructions_EarlyDraw_AppliesAfterComposition",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkRenderTargetNet_Instructions_EarlyDraw_AppliesAfterComposition::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesForServerCompose = 5;   // enough for the SERVER to compose + setup; the
                                                 // client is typically still composing — the point
    constexpr auto FramesToSettle = 60;          // generous: NotReady retries + composition + replay

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
            auto* Subject = InServer->SpawnActor<ACk_AutoTest_NetSubject_RenderTarget_UE>(
                ACk_AutoTest_NetSubject_RenderTarget_UE::StaticClass(), FTransform::Identity, SpawnInfo);
            if (Subject == nullptr)
            { AddError(TEXT("server-side SpawnActor of ACk_AutoTest_NetSubject_RenderTarget_UE returned null")); }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesForServerCompose));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            ck_render_target_net_spec::DrawTwoCmdBatch(this, InServer);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesToSettle));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            return ck_render_target_net_spec::AssertBothWorldsAtSeq(this, 1);
        }),
        TEXT("a batch drawn before client composition still applies once the client composes")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            FAutomationTestBase::bSuppressLogErrors = false;
            FAutomationTestBase::bSuppressLogWarnings = false;
            return true;
        }),
        TEXT("restore log suppression statics")));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
