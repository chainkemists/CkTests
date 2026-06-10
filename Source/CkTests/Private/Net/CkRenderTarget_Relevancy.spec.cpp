// Cull-distance relevancy coverage for CkRenderTarget:
//
//   OutOfRange_BaselineInvalidated_FullSyncOnReentry — after a baseline is established, the
//   subject teleports beyond its NetCullDistanceSquared: the pacing processor invalidates the
//   player's baseline. On re-entry, the next capture streams as a FullSync (not a delta) and
//   re-establishes the baseline.
//
// Surface in Session Frontend: Ck.RenderTarget.Net.Relevancy_OutOfRange_FullSyncOnReentry

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"

#include "CkRenderTarget/Pixels/CkRenderTarget_PixelMath.h"
#include "CkRenderTarget/RenderTarget/CkRenderTarget_Utils.h"

#include "CkTests/Net/CkAutoTest_NetSubject.h"
#include "CkTests/Net/CkAutoTest_NetSubject_RenderTarget.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_render_target_relevancy_spec
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
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkRenderTargetNet_Relevancy_OutOfRange_FullSyncOnReentry,
    "Ck.RenderTarget.Net.Relevancy_OutOfRange_FullSyncOnReentry",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkRenderTargetNet_Relevancy_OutOfRange_FullSyncOnReentry::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(2, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(2, 30.0f));

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

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(30));

    // ---- Establish a baseline in range ---------------------------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Subject = ck_render_target_relevancy_spec::Get_ServerSubject(this);
            if (Subject == nullptr) { return; }

            UCk_Utils_RenderTarget_UE::Debug_InjectCapturedPixels(Subject->_TestRenderTarget,
                ck_render_target_relevancy_spec::MakeFlatImage(60),
                FIntPoint{ck_render_target_relevancy_spec::ImageSide, ck_render_target_relevancy_spec::ImageSide});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(90));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Subject = ck_render_target_relevancy_spec::Get_ServerSubject(this);
            if (Subject == nullptr) { return false; }

            TestEqual(TEXT("baseline established while in range"),
                UCk_Utils_RenderTarget_UE::Get_NumBaselinedClients(Subject->_TestRenderTarget), 1);
            return true;
        }),
        TEXT("in-range FullSync establishes the baseline")));

    // ---- Leave cull range: baseline invalidated ------------------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Subject = ck_render_target_relevancy_spec::Get_ServerSubject(this);
            if (Subject == nullptr) { return; }

            Subject->SetNetCullDistanceSquared(100.0f * 100.0f);
            Subject->SetActorLocation(FVector{1000000.0, 0.0, 0.0});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(30));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Subject = ck_render_target_relevancy_spec::Get_ServerSubject(this);
            if (Subject == nullptr) { return false; }

            TestEqual(TEXT("baseline invalidated once the player left cull range"),
                UCk_Utils_RenderTarget_UE::Get_NumBaselinedClients(Subject->_TestRenderTarget), 0);
            return true;
        }),
        TEXT("leaving cull range invalidates the baseline")));

    // ---- Re-enter + capture: FullSync (not delta) re-establishes ------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Subject = ck_render_target_relevancy_spec::Get_ServerSubject(this);
            if (Subject == nullptr) { return; }

            // "Re-enter range" — restore a generous cull distance (the player pawn's exact spawn
            // offset is map-defined; a tiny radius would never re-admit it) and bring the subject
            // back.
            Subject->SetNetCullDistanceSquared(225000000.0f);
            Subject->SetActorLocation(FVector::ZeroVector);

            auto Modified = ck_render_target_relevancy_spec::MakeFlatImage(60);
            Modified[0] = 250;

            UCk_Utils_RenderTarget_UE::Debug_InjectCapturedPixels(Subject->_TestRenderTarget,
                Modified,
                FIntPoint{ck_render_target_relevancy_spec::ImageSide, ck_render_target_relevancy_spec::ImageSide});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(120));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* ServerSubject = ck_render_target_relevancy_spec::Get_ServerSubject(this);
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            auto* ClientSubject = Client != nullptr
                ? Cast<ACk_AutoTest_NetSubject_RenderTarget_UE>(ACk_AutoTest_NetSubject::Find(Client))
                : nullptr;

            if (ServerSubject == nullptr || ClientSubject == nullptr || ck::Is_NOT_Valid(ClientSubject->_TestRenderTarget))
            { AddError(TEXT("subjects unavailable at final assertion")); return false; }

            TestEqual(TEXT("re-entry reconcile arrived as a FullSync (no baseline -> never a delta)"),
                UCk_Utils_RenderTarget_UE::Get_LatestAppliedPixelPayloadKind(ClientSubject->_TestRenderTarget),
                ECk_RenderTarget_PixelPayloadKind::FullSync);

            TestEqual(TEXT("client converged to the server's pixel state"),
                UCk_Utils_RenderTarget_UE::Get_PixelStateHash(ClientSubject->_TestRenderTarget),
                UCk_Utils_RenderTarget_UE::Get_PixelStateHash(ServerSubject->_TestRenderTarget));

            TestEqual(TEXT("baseline re-established after re-entry"),
                UCk_Utils_RenderTarget_UE::Get_NumBaselinedClients(ServerSubject->_TestRenderTarget), 1);

            return true;
        }),
        TEXT("re-entry forces a FullSync and re-establishes the baseline")));

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
