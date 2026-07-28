// Client-authoring coverage for CkRenderTarget:
//
//   1. ClientDraw_ReachesServerAndOtherClient — on an Allowed target, a client's draw applies
//      locally (prediction), relays to the server (which re-applies + republishes with the
//      sender stamped), and reaches the OTHER client; the author's own watermark advances via
//      echo suppression without a re-apply.
//
//   2. ClientUpload_RoundTrip — a client pixel capture uploads as a FullSync; the server adopts
//      it as the authoritative snapshot (hashes converge) and promotes the uploader's baseline.
//
//   3. ClientUpload_Disallowed_RejectedServerSide — a forged Server_PushPixelChunk against a
//      Disallowed target is rejected server-side (no snapshot adopted, no baseline promoted).
//
// Surface in Session Frontend: Ck.RenderTarget.Net.ClientAuth*

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "GameFramework/PlayerController.h"
#include "GameFramework/PlayerState.h"

#include "CkEcs/OwningActor/CkOwningActor_Utils.h"

#include "CkRenderTarget/Net/CkRenderTargetRelay_Actor.h"
#include "CkRenderTarget/Net/CkRenderTargetRelay_Subsystem.h"
#include "CkRenderTarget/Pixels/CkRenderTarget_PixelMath.h"
#include "CkRenderTarget/RenderTarget/CkRenderTarget_Utils.h"

#include "CkTests/Net/CkAutoTest_NetSubject.h"
#include "CkTests/Net/CkAutoTest_NetSubject_RenderTarget.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_render_target_clientauth_spec
{
    constexpr auto ImageSide = 32;

    auto MakeFlatImage(uint8 InValue) -> TArray<uint8>
    {
        auto Image = TArray<uint8>{};
        Image.SetNumUninitialized(ImageSide * ImageSide * ck::render_target::pixel::BytesPerPixel);
        FMemory::Memset(Image.GetData(), InValue, Image.Num());
        return Image;
    }

    auto Get_SubjectIn(FAutomationTestBase* InTest, UWorld* InWorld, const TCHAR* InWho) -> ACk_AutoTest_NetSubject_RenderTarget_UE*
    {
        if (InWorld == nullptr)
        { InTest->AddError(FString::Printf(TEXT("%s world unavailable"), InWho)); return nullptr; }

        auto* Subject = Cast<ACk_AutoTest_NetSubject_RenderTarget_UE>(ACk_AutoTest_NetSubject::Find(InWorld));
        if (Subject == nullptr || ck::Is_NOT_Valid(Subject->_TestRenderTarget))
        { InTest->AddError(FString::Printf(TEXT("%s RenderTarget subject / _TestRenderTarget missing"), InWho)); return nullptr; }

        return Subject;
    }

    template <typename T_SubjectClass>
    auto SpawnSubject(FAutomationTestBase* InTest, UWorld* InServer) -> void
    {
        auto SpawnInfo = FActorSpawnParameters{};
        SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
        auto* Subject = InServer->SpawnActor<T_SubjectClass>(
            T_SubjectClass::StaticClass(), FTransform::Identity, SpawnInfo);
        if (Subject == nullptr)
        { InTest->AddError(TEXT("server-side SpawnActor of the RenderTarget subject returned null")); }
    }

    auto Get_LocalRelayChannel(UWorld* InWorld) -> ACk_RenderTargetRelay_UE*
    {
        if (InWorld == nullptr)
        { return nullptr; }

        auto* Subsystem = InWorld->GetSubsystem<UCk_RenderTargetRelay_Subsystem_UE>();
        const auto* LocalController = InWorld->GetFirstPlayerController();

        if (Subsystem == nullptr || LocalController == nullptr || LocalController->PlayerState == nullptr)
        { return nullptr; }

        auto Pending = Subsystem->Request_AcquireChannel_ForPlayer(LocalController->PlayerState);
        const auto Result = Subsystem->Try_ResolvePending(Pending);
        return Cast<ACk_RenderTargetRelay_UE>(Result.Get_ChannelActor().Get());
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkRenderTargetNet_ClientAuth_DrawReachesServerAndOtherClient,
    "Ck.RenderTarget.Net.ClientAuth_DrawReachesServerAndOtherClient",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkRenderTargetNet_ClientAuth_DrawReachesServerAndOtherClient::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(3, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(3, 30.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            ck_render_target_clientauth_spec::SpawnSubject<ACk_AutoTest_NetSubject_RenderTargetClientAuth_UE>(this, InServer);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(45));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(0,
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InClient) -> void
        {
            auto* Subject = ck_render_target_clientauth_spec::Get_SubjectIn(this, InClient, TEXT("client0"));
            if (Subject == nullptr) { return; }

            UCk_Utils_RenderTarget_UE::Request_DrawLine(Subject->_TestRenderTarget,
                FCk_Request_RenderTarget_DrawLine{FVector2D{0.0, 0.0}, FVector2D{16.0, 16.0}}, {});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(90));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* ServerSubject = ck_render_target_clientauth_spec::Get_SubjectIn(this, ck::auto_test::net::Get_ServerWorld(), TEXT("server"));
            auto* AuthorSubject = ck_render_target_clientauth_spec::Get_SubjectIn(this, ck::auto_test::net::Get_ClientWorld(0), TEXT("client0"));
            auto* OtherSubject = ck_render_target_clientauth_spec::Get_SubjectIn(this, ck::auto_test::net::Get_ClientWorld(1), TEXT("client1"));
            if (ServerSubject == nullptr || AuthorSubject == nullptr || OtherSubject == nullptr)
            { return false; }

            TestEqual(TEXT("server applied the client batch (server seq 1)"),
                UCk_Utils_RenderTarget_UE::Get_LatestAppliedBatchSeq(ServerSubject->_TestRenderTarget), 1);

            TestEqual(TEXT("the OTHER client replayed the batch"),
                UCk_Utils_RenderTarget_UE::Get_LatestAppliedBatchSeq(OtherSubject->_TestRenderTarget), 1);

            // The author predicted seq 1 locally; the republished copy must advance its
            // watermark via echo suppression (not stall it).
            TestEqual(TEXT("the authoring client's applied seq covers the round-trip"),
                UCk_Utils_RenderTarget_UE::Get_LatestAppliedBatchSeq(AuthorSubject->_TestRenderTarget), 1);

            return true;
        }),
        TEXT("client draw reaches server + other client; author echo-suppressed")));

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
    FCkRenderTargetNet_ClientAuth_UploadRoundTrip,
    "Ck.RenderTarget.Net.ClientAuth_UploadRoundTrip",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkRenderTargetNet_ClientAuth_UploadRoundTrip::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(2, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(2, 30.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            ck_render_target_clientauth_spec::SpawnSubject<ACk_AutoTest_NetSubject_RenderTargetClientAuth_UE>(this, InServer);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(45));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(0,
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InClient) -> void
        {
            auto* Subject = ck_render_target_clientauth_spec::Get_SubjectIn(this, InClient, TEXT("client0"));
            if (Subject == nullptr) { return; }

            UCk_Utils_RenderTarget_UE::Debug_InjectCapturedPixels(Subject->_TestRenderTarget,
                ck_render_target_clientauth_spec::MakeFlatImage(120),
                FIntPoint{ck_render_target_clientauth_spec::ImageSide, ck_render_target_clientauth_spec::ImageSide});
        })));

    // Client capture job + upload pacing + server reassembly/apply + rebroadcast bookkeeping.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(120));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* ServerSubject = ck_render_target_clientauth_spec::Get_SubjectIn(this, ck::auto_test::net::Get_ServerWorld(), TEXT("server"));
            auto* ClientSubject = ck_render_target_clientauth_spec::Get_SubjectIn(this, ck::auto_test::net::Get_ClientWorld(0), TEXT("client0"));
            if (ServerSubject == nullptr || ClientSubject == nullptr)
            { return false; }

            const auto ServerHash = UCk_Utils_RenderTarget_UE::Get_PixelStateHash(ServerSubject->_TestRenderTarget);
            const auto ClientHash = UCk_Utils_RenderTarget_UE::Get_PixelStateHash(ClientSubject->_TestRenderTarget);

            TestNotEqual(TEXT("server adopted the upload as its snapshot"), ServerHash, 0);
            TestEqual(TEXT("server snapshot matches the uploader's pixel state"), ServerHash, ClientHash);

            TestEqual(TEXT("uploader's baseline was promoted (it authored the content)"),
                UCk_Utils_RenderTarget_UE::Get_NumBaselinedClients(ServerSubject->_TestRenderTarget), 1);

            return true;
        }),
        TEXT("client pixel upload round-trips to the server")));

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
    FCkRenderTargetNet_ClientAuth_UploadDisallowed_RejectedServerSide,
    "Ck.RenderTarget.Net.ClientAuth_UploadDisallowed_RejectedServerSide",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkRenderTargetNet_ClientAuth_UploadDisallowed_RejectedServerSide::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(2, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(2, 30.0f));

    // DEFAULT subject — _ClientAuthoring stays Disallowed.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            ck_render_target_clientauth_spec::SpawnSubject<ACk_AutoTest_NetSubject_RenderTarget_UE>(this, InServer);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(60));

    // Forge an upload straight at the relay RPC — the client-side gates are bypassed on
    // purpose; the SERVER must reject it.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(0,
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InClient) -> void
        {
            auto* Subject = ck_render_target_clientauth_spec::Get_SubjectIn(this, InClient, TEXT("client0"));
            if (Subject == nullptr) { return; }

            auto* Channel = ck_render_target_clientauth_spec::Get_LocalRelayChannel(InClient);
            if (Channel == nullptr)
            { AddError(TEXT("client0 relay channel did not resolve in time")); return; }

            auto OwnerEntity = UCk_Utils_OwningActor_UE::Get_ActorEntityHandle(Subject);
            const auto SyncName = FGameplayTag::RequestGameplayTag(TEXT("RenderTarget.AutoTest.Net"));

            const auto Raw = ck_render_target_clientauth_spec::MakeFlatImage(200);
            const auto Compressed = ck::render_target::pixel::Compress(Raw);

            Channel->Server_PushPixelChunk(
                OwnerEntity, SyncName,
                ECk_RenderTarget_PixelPayloadKind::FullSync,
                /*PayloadSeq=*/ 1, /*ChunkIdx=*/ 0, /*NumChunks=*/ 1,
                Raw.Num(),
                FIntPoint{ck_render_target_clientauth_spec::ImageSide, ck_render_target_clientauth_spec::ImageSide},
                /*InstructionWatermark=*/ 0,
                Compressed);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(60));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* ServerSubject = ck_render_target_clientauth_spec::Get_SubjectIn(this, ck::auto_test::net::Get_ServerWorld(), TEXT("server"));
            if (ServerSubject == nullptr)
            { return false; }

            TestEqual(TEXT("server did NOT adopt the forged upload (no snapshot)"),
                UCk_Utils_RenderTarget_UE::Get_PixelStateHash(ServerSubject->_TestRenderTarget), 0);

            TestEqual(TEXT("no baseline was promoted"),
                UCk_Utils_RenderTarget_UE::Get_NumBaselinedClients(ServerSubject->_TestRenderTarget), 0);

            return true;
        }),
        TEXT("forged upload against a Disallowed target is rejected server-side")));

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
