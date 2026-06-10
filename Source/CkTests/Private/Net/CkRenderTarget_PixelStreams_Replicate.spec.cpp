// Channel B (pixel stream) coverage for CkRenderTarget, driven through the
// Debug_InjectCapturedPixels seam so everything runs under -nullrhi.
//
//   1. FullSync_BaselineEstablished — server injects a capture; the client receives the chunked
//      FullSync, applies it into its CPU staging mirror (hash == server snapshot hash), acks, and
//      the server promotes the client's baseline.
//
//   2. Delta_AfterBaseline — a second, modified capture after the baseline streams as a Delta
//      payload (kind asserted on the client) and converges to the same hash.
//
//   3. InstructionsBelowWatermark_Dropped — draws precede the capture, so the FullSync carries an
//      instruction watermark covering them; the client's baseline watermark and applied-batch seq
//      reflect the bake-in, and a post-capture draw still replays on top.
//
// Surface in Session Frontend: Ck.RenderTarget.Net.Pixel*

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"

#include "CkRenderTarget/Pixels/CkRenderTarget_PixelMath.h"
#include "CkRenderTarget/RenderTarget/CkRenderTarget_Utils.h"

#include "CkTests/Net/CkAutoTest_NetSubject.h"
#include "CkTests/Net/CkAutoTest_NetSubject_RenderTarget.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_render_target_pixel_spec
{
    constexpr auto ImageSide = 32;

    auto MakeFlatImage(uint8 InValue) -> TArray<uint8>
    {
        auto Image = TArray<uint8>{};
        Image.SetNumUninitialized(ImageSide * ImageSide * ck::render_target::pixel::BytesPerPixel);
        FMemory::Memset(Image.GetData(), InValue, Image.Num());
        return Image;
    }

    auto Get_ServerSubject(FAutomationTestBase* InTest) -> ACk_AutoTest_NetSubject_RenderTarget_UE*
    {
        auto* Server = ck::auto_test::net::Get_ServerWorld();
        if (Server == nullptr)
        { InTest->AddError(TEXT("server world unavailable")); return nullptr; }

        auto* Subject = Cast<ACk_AutoTest_NetSubject_RenderTarget_UE>(ACk_AutoTest_NetSubject::Find(Server));
        if (Subject == nullptr || ck::Is_NOT_Valid(Subject->_TestRenderTarget))
        { InTest->AddError(TEXT("server-side RenderTarget subject / _TestRenderTarget missing")); return nullptr; }

        return Subject;
    }

    auto Get_ClientSubject(FAutomationTestBase* InTest) -> ACk_AutoTest_NetSubject_RenderTarget_UE*
    {
        auto* Client = ck::auto_test::net::Get_ClientWorld(0);
        if (Client == nullptr)
        { InTest->AddError(TEXT("client world unavailable")); return nullptr; }

        auto* Subject = Cast<ACk_AutoTest_NetSubject_RenderTarget_UE>(ACk_AutoTest_NetSubject::Find(Client));
        if (Subject == nullptr || ck::Is_NOT_Valid(Subject->_TestRenderTarget))
        { InTest->AddError(TEXT("client-side RenderTarget subject / _TestRenderTarget missing")); return nullptr; }

        return Subject;
    }

    auto SpawnSubject(FAutomationTestBase* InTest, UWorld* InServer) -> void
    {
        auto SpawnInfo = FActorSpawnParameters{};
        SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
        auto* Subject = InServer->SpawnActor<ACk_AutoTest_NetSubject_RenderTarget_UE>(
            ACk_AutoTest_NetSubject_RenderTarget_UE::StaticClass(), FTransform::Identity, SpawnInfo);
        if (Subject == nullptr)
        { InTest->AddError(TEXT("server-side SpawnActor of ACk_AutoTest_NetSubject_RenderTarget_UE returned null")); }
    }

    auto AssertHashesConverged(FAutomationTestBase* InTest, const TCHAR* InWhat) -> void
    {
        auto* ServerSubject = Get_ServerSubject(InTest);
        auto* ClientSubject = Get_ClientSubject(InTest);
        if (ServerSubject == nullptr || ClientSubject == nullptr)
        { return; }

        const auto ServerHash = UCk_Utils_RenderTarget_UE::Get_PixelStateHash(ServerSubject->_TestRenderTarget);
        const auto ClientHash = UCk_Utils_RenderTarget_UE::Get_PixelStateHash(ClientSubject->_TestRenderTarget);

        InTest->TestNotEqual(FString::Printf(TEXT("%s: server has pixel state"), InWhat), ServerHash, 0);
        InTest->TestEqual(FString::Printf(TEXT("%s: client staging hash matches server snapshot hash"), InWhat),
            ClientHash, ServerHash);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkRenderTargetNet_Pixel_FullSync_BaselineEstablished,
    "Ck.RenderTarget.Net.Pixel_FullSync_BaselineEstablished",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkRenderTargetNet_Pixel_FullSync_BaselineEstablished::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(2, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(2, 30.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            ck_render_target_pixel_spec::SpawnSubject(this, InServer);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(30));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Subject = ck_render_target_pixel_spec::Get_ServerSubject(this);
            if (Subject == nullptr) { return; }

            UCk_Utils_RenderTarget_UE::Debug_InjectCapturedPixels(Subject->_TestRenderTarget,
                ck_render_target_pixel_spec::MakeFlatImage(50),
                FIntPoint{ck_render_target_pixel_spec::ImageSide, ck_render_target_pixel_spec::ImageSide});
        })));

    // Capture job + dispatch + chunk pacing + client reassembly/apply + ack round-trip.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(90));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            ck_render_target_pixel_spec::AssertHashesConverged(this, TEXT("FullSync"));

            auto* ServerSubject = ck_render_target_pixel_spec::Get_ServerSubject(this);
            auto* ClientSubject = ck_render_target_pixel_spec::Get_ClientSubject(this);
            if (ServerSubject == nullptr || ClientSubject == nullptr)
            { return false; }

            TestEqual(TEXT("client applied a FullSync payload"),
                UCk_Utils_RenderTarget_UE::Get_LatestAppliedPixelPayloadKind(ClientSubject->_TestRenderTarget),
                ECk_RenderTarget_PixelPayloadKind::FullSync);

            TestEqual(TEXT("server promoted the client's baseline on ack"),
                UCk_Utils_RenderTarget_UE::Get_NumBaselinedClients(ServerSubject->_TestRenderTarget), 1);

            return true;
        }),
        TEXT("FullSync streams, applies, and promotes the baseline")));

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
    FCkRenderTargetNet_Pixel_Delta_AfterBaseline,
    "Ck.RenderTarget.Net.Pixel_Delta_AfterBaseline",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkRenderTargetNet_Pixel_Delta_AfterBaseline::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(2, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(2, 30.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            ck_render_target_pixel_spec::SpawnSubject(this, InServer);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(30));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Subject = ck_render_target_pixel_spec::Get_ServerSubject(this);
            if (Subject == nullptr) { return; }

            UCk_Utils_RenderTarget_UE::Debug_InjectCapturedPixels(Subject->_TestRenderTarget,
                ck_render_target_pixel_spec::MakeFlatImage(50),
                FIntPoint{ck_render_target_pixel_spec::ImageSide, ck_render_target_pixel_spec::ImageSide});
        })));

    // First capture must fully round-trip (incl. ack) so the second one streams as a delta.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(90));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Subject = ck_render_target_pixel_spec::Get_ServerSubject(this);
            if (Subject == nullptr) { return; }

            auto Modified = ck_render_target_pixel_spec::MakeFlatImage(50);
            Modified[0] = 200;   // one changed pixel -> one changed block

            UCk_Utils_RenderTarget_UE::Debug_InjectCapturedPixels(Subject->_TestRenderTarget,
                Modified,
                FIntPoint{ck_render_target_pixel_spec::ImageSide, ck_render_target_pixel_spec::ImageSide});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(90));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            ck_render_target_pixel_spec::AssertHashesConverged(this, TEXT("Delta"));

            auto* ClientSubject = ck_render_target_pixel_spec::Get_ClientSubject(this);
            if (ClientSubject == nullptr)
            { return false; }

            TestEqual(TEXT("second payload streamed as a Delta"),
                UCk_Utils_RenderTarget_UE::Get_LatestAppliedPixelPayloadKind(ClientSubject->_TestRenderTarget),
                ECk_RenderTarget_PixelPayloadKind::Delta);

            TestEqual(TEXT("client applied payload seq 2"),
                UCk_Utils_RenderTarget_UE::Get_LatestAppliedPixelPayloadSeq(ClientSubject->_TestRenderTarget), 2);

            return true;
        }),
        TEXT("post-baseline capture streams as Delta and converges")));

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
    FCkRenderTargetNet_Pixel_InstructionsBelowWatermark_Dropped,
    "Ck.RenderTarget.Net.Pixel_InstructionsBelowWatermark_Dropped",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkRenderTargetNet_Pixel_InstructionsBelowWatermark_Dropped::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(2, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(2, 30.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            ck_render_target_pixel_spec::SpawnSubject(this, InServer);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(30));

    // Two draw batches (seqs 1 + 2), then a capture whose watermark covers them.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Subject = ck_render_target_pixel_spec::Get_ServerSubject(this);
            if (Subject == nullptr) { return; }

            UCk_Utils_RenderTarget_UE::Request_DrawLine(Subject->_TestRenderTarget,
                FCk_Request_RenderTarget_DrawLine{FVector2D{0.0, 0.0}, FVector2D{8.0, 8.0}});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(5));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Subject = ck_render_target_pixel_spec::Get_ServerSubject(this);
            if (Subject == nullptr) { return; }

            UCk_Utils_RenderTarget_UE::Request_DrawBox(Subject->_TestRenderTarget,
                FCk_Request_RenderTarget_DrawBox{FVector2D{4.0, 4.0}, FVector2D{8.0, 8.0}});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(5));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Subject = ck_render_target_pixel_spec::Get_ServerSubject(this);
            if (Subject == nullptr) { return; }

            TestEqual(TEXT("server applied both draw batches before capture"),
                UCk_Utils_RenderTarget_UE::Get_LatestAppliedBatchSeq(Subject->_TestRenderTarget), 2);

            UCk_Utils_RenderTarget_UE::Debug_InjectCapturedPixels(Subject->_TestRenderTarget,
                ck_render_target_pixel_spec::MakeFlatImage(80),
                FIntPoint{ck_render_target_pixel_spec::ImageSide, ck_render_target_pixel_spec::ImageSide});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(90));

    // A post-capture draw must still replay on top of the baseline.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Subject = ck_render_target_pixel_spec::Get_ServerSubject(this);
            if (Subject == nullptr) { return; }

            UCk_Utils_RenderTarget_UE::Request_DrawLine(Subject->_TestRenderTarget,
                FCk_Request_RenderTarget_DrawLine{FVector2D{8.0, 8.0}, FVector2D{16.0, 16.0}});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(30));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* ClientSubject = ck_render_target_pixel_spec::Get_ClientSubject(this);
            if (ClientSubject == nullptr)
            { return false; }

            TestEqual(TEXT("client's baseline carries the capture-time instruction watermark (2)"),
                UCk_Utils_RenderTarget_UE::Get_BaselineInstructionWatermark(ClientSubject->_TestRenderTarget), 2);

            TestEqual(TEXT("client's applied batch seq covers the post-capture draw (3)"),
                UCk_Utils_RenderTarget_UE::Get_LatestAppliedBatchSeq(ClientSubject->_TestRenderTarget), 3);

            return true;
        }),
        TEXT("instructions below the baseline watermark are dropped; newer ones replay")));

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
