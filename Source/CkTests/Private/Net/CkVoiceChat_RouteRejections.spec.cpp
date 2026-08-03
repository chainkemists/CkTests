// P3 invalid-input coverage (non-negotiable #3 / Gate_3 exit criteria): the two routing
// rejections not covered elsewhere, each proven by NON-DELIVERY at the recipient's RPC boundary
// with a positive control through the identical seam:
//
//   1. Non-member send: a resolvable ChannelIdx from a talker who never joined - dropped at the
//      membership gate, nothing reaches any recipient.
//   2. Forged sender: a bundle whose stamped sender and the talker's owning player BOTH resolve
//      but differ (the spoof shape) - dropped; the diagnostic ensure fires once by design.
//   3. Positive control: the same talker, same channel, CORRECT sender - the recipient's
//      arrival counter moves, proving the two silences above were the gates, not the harness.
//
// (Unresolvable-idx/N1 lives in Routing_ForwardsAndNeverStashes; malformed/oversize wire input
// in CkTests.UnitTests.CkVoiceChat.Wire.*)
//
// Surface in Session Frontend: Ck.VoiceChat.Net.RouteRejections

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "EngineUtils.h"

#include "CkVoiceChat/Codec/CkVoiceChat_Codec.h"
#include "CkVoiceChat/VoiceChannel/CkVoiceChannel_Utils.h"
#include "CkVoiceChat/VoiceTalker/CkVoiceTalker_Utils.h"

#include "CkTests/Net/CkAutoTest_NetSubject_VoiceChat.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include <GameFramework/PlayerController.h>
#include <GameFramework/PlayerState.h>

// --------------------------------------------------------------------------------------------------------------------

namespace ck_voice_rejections_spec
{
    const auto NpcLocation = FVector::ZeroVector;
    const auto TalkerALocation = FVector{100.0, 0.0, 0.0};
    const auto ListenerBLocation = FVector{200.0, 0.0, 0.0};

    struct FRejectionsSpecState
    {
        int32 Client0PlayerId = 0;
        uint8 ChannelIdx = 255;
    };

    auto Find_SubjectNear(UWorld* InWorld, const FVector& InLocation) -> ACk_AutoTest_NetSubject_VoiceChat_UE*
    {
        for (TActorIterator<ACk_AutoTest_NetSubject_VoiceChat_UE> It{InWorld}; It; ++It)
        {
            if (FVector::Dist(It->GetActorLocation(), InLocation) < 50.0)
            { return *It; }
        }

        return nullptr;
    }

    auto Find_ControllerByPlayerId(UWorld* InServer, int32 InPlayerId) -> APlayerController*
    {
        for (auto It = InServer->GetPlayerControllerIterator(); It; ++It)
        {
            if (auto* Controller = It->Get();
                Controller != nullptr && Controller->PlayerState != nullptr &&
                Controller->PlayerState->GetPlayerId() == InPlayerId)
            { return Controller; }
        }

        return nullptr;
    }

    // The server never decodes (G6), so frame CONTENT is irrelevant to Route - only the header
    // has to be honest.
    auto Make_Bundle(uint16 InSeq, uint8 InChannelIdx) -> TArray<uint8>
    {
        auto Frame = TArray<uint8>{};
        Frame.Init(0x42, 60);

        constexpr auto AmplitudeQ8 = uint8{128};
        return ck::voice_chat::codec::Pack_Bundle(
            FCk_VoiceChat_BundleHeader{InSeq, InChannelIdx, AmplitudeQ8}, TArray<TArray<uint8>>{Frame});
    }

    auto Read_Arrivals(UWorld* InWorld, const FVector& InSubjectLocation, uint64& OutArrivals) -> bool
    {
        auto* Subject = Find_SubjectNear(InWorld, InSubjectLocation);

        if (Subject == nullptr || ck::Is_NOT_Valid(Subject->_TestTalker))
        { return false; }

        OutArrivals = UCk_Utils_VoiceTalker_UE::Debug_Get_ReceiveArrivedBundles(Subject->_TestTalker);
        return true;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkVoiceChatNet_RouteRejections,
    "Ck.VoiceChat.Net.RouteRejections",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkVoiceChatNet_RouteRejections::RunTest(const FString& Parameters)
{
    using namespace ck_voice_rejections_spec;

    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};
    const auto State = MakeShared<FRejectionsSpecState, ESPMode::ThreadSafe>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(3, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(3, 30.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(30));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(0,
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InClient) -> void
        {
            const auto* LocalController = InClient->GetFirstPlayerController();
            if (LocalController == nullptr || LocalController->PlayerState == nullptr)
            {
                AddError(TEXT("client 0 has no local PlayerState"));
                return;
            }

            State->Client0PlayerId = LocalController->PlayerState->GetPlayerId();
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InServer) -> void
        {
            auto* Client0Controller = Find_ControllerByPlayerId(InServer, State->Client0PlayerId);
            auto* Client1Controller = static_cast<APlayerController*>(nullptr);
            for (auto It = InServer->GetPlayerControllerIterator(); It; ++It)
            {
                if (auto* Controller = It->Get();
                    Controller != nullptr && NOT Controller->IsLocalController() && Controller != Client0Controller)
                { Client1Controller = Controller; }
            }

            if (Client0Controller == nullptr || Client1Controller == nullptr)
            {
                AddError(TEXT("could not resolve both remote PlayerControllers on the server"));
                return;
            }

            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;

            if (InServer->SpawnActor<ACk_AutoTest_NetSubject_VoiceChat_UE>(
                    ACk_AutoTest_NetSubject_VoiceChat_UE::StaticClass(), FTransform{NpcLocation}, SpawnInfo) == nullptr)
            { AddError(TEXT("spawn of the npc subject failed")); }

            SpawnInfo.Owner = Client0Controller;
            if (InServer->SpawnActor<ACk_AutoTest_NetSubject_VoiceChat_UE>(
                    ACk_AutoTest_NetSubject_VoiceChat_UE::StaticClass(), FTransform{TalkerALocation}, SpawnInfo) == nullptr)
            { AddError(TEXT("spawn of the talker-A subject failed")); }

            SpawnInfo.Owner = Client1Controller;
            if (InServer->SpawnActor<ACk_AutoTest_NetSubject_VoiceChat_UE>(
                    ACk_AutoTest_NetSubject_VoiceChat_UE::StaticClass(), FTransform{ListenerBLocation}, SpawnInfo) == nullptr)
            { AddError(TEXT("spawn of the listener-B subject failed")); }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(40));

    // Join talker A and listener B; the npc talker deliberately NEVER joins.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InServer) -> void
        {
            auto* Npc = Find_SubjectNear(InServer, NpcLocation);
            auto* TalkerA = Find_SubjectNear(InServer, TalkerALocation);
            auto* ListenerB = Find_SubjectNear(InServer, ListenerBLocation);

            if (Npc == nullptr || TalkerA == nullptr || ListenerB == nullptr)
            {
                AddError(TEXT("subjects missing on the server at join time"));
                return;
            }

            UCk_Utils_VoiceChannel_UE::Request_Join(Npc->_TestChannel,
                FCk_Request_VoiceChannel_Join{TalkerA->_TestTalker}, {});
            UCk_Utils_VoiceChannel_UE::Request_Join(Npc->_TestChannel,
                FCk_Request_VoiceChannel_Join{ListenerB->_TestTalker}, {});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(20));

    // Act 1 - non-member send: valid channel idx, a talker who never joined.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InServer) -> void
        {
            auto* Npc = Find_SubjectNear(InServer, NpcLocation);
            if (Npc == nullptr || ck::Is_NOT_Valid(Npc->_TestChannel))
            {
                AddError(TEXT("npc subject missing at act 1"));
                return;
            }

            State->ChannelIdx = UCk_Utils_VoiceChannel_UE::Get_ChannelIdx(Npc->_TestChannel);
            if (State->ChannelIdx == 255)
            {
                AddError(TEXT("channel has no assigned idx at act 1 - control plane did not settle"));
                return;
            }

            UCk_Utils_VoiceTalker_UE::Debug_InjectInboundBundle(
                Npc->_TestTalker, Make_Bundle(1, State->ChannelIdx), nullptr);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(30));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Client1 = ck::auto_test::net::Get_ClientWorld(1);
            auto Arrivals = uint64{0};

            if (Client1 == nullptr || NOT Read_Arrivals(Client1, NpcLocation, Arrivals))
            {
                AddError(TEXT("npc replica missing in client 1's world at act 1 assert"));
                return false;
            }

            TestEqual(TEXT("a NON-MEMBER's bundle on a valid channel reaches nobody"), Arrivals, uint64{0});
            return true;
        }),
        TEXT("non-member send rejected")));

    // Act 2 - forged sender: talker A's bundle stamped as if the HOST sent it. Both the stamp
    // and the owning player resolve, and they differ - the spoof shape. The diagnostic ensure
    // fires once by design (suppressed here); the property under test is non-delivery.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InServer) -> void
        {
            auto* TalkerA = Find_SubjectNear(InServer, TalkerALocation);
            const auto* HostController = InServer->GetFirstPlayerController();

            if (TalkerA == nullptr || HostController == nullptr || HostController->PlayerState == nullptr)
            {
                AddError(TEXT("talker A or the host PlayerState missing at act 2"));
                return;
            }

            UCk_Utils_VoiceTalker_UE::Debug_InjectInboundBundle(
                TalkerA->_TestTalker, Make_Bundle(2, State->ChannelIdx), HostController->PlayerState);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(30));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Client1 = ck::auto_test::net::Get_ClientWorld(1);
            auto Arrivals = uint64{0};

            if (Client1 == nullptr || NOT Read_Arrivals(Client1, TalkerALocation, Arrivals))
            {
                AddError(TEXT("talker-A replica missing in client 1's world at act 2 assert"));
                return false;
            }

            TestEqual(TEXT("a FORGED-sender bundle reaches nobody"), Arrivals, uint64{0});
            return true;
        }),
        TEXT("forged sender rejected")));

    // Act 3 - positive control: identical injection with the CORRECT sender proves the seam
    // delivers when the gates pass.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InServer) -> void
        {
            auto* TalkerA = Find_SubjectNear(InServer, TalkerALocation);
            auto* Client0Controller = Find_ControllerByPlayerId(InServer, State->Client0PlayerId);

            if (TalkerA == nullptr || Client0Controller == nullptr || Client0Controller->PlayerState == nullptr)
            {
                AddError(TEXT("talker A or client 0's PlayerState missing at act 3"));
                return;
            }

            UCk_Utils_VoiceTalker_UE::Debug_InjectInboundBundle(
                TalkerA->_TestTalker, Make_Bundle(3, State->ChannelIdx), Client0Controller->PlayerState);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(40));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Client1 = ck::auto_test::net::Get_ClientWorld(1);
            auto* Client0 = ck::auto_test::net::Get_ClientWorld(0);
            auto ArrivalsAtB = uint64{0};
            auto ArrivalsAtA = uint64{0};

            if (Client1 == nullptr || NOT Read_Arrivals(Client1, TalkerALocation, ArrivalsAtB))
            {
                AddError(TEXT("talker-A replica missing in client 1's world at act 3 assert"));
                return false;
            }

            TestTrue(TEXT("the SAME talker/channel with the correct sender DOES deliver (positive control)"),
                ArrivalsAtB > 0);

            if (Client0 != nullptr && Read_Arrivals(Client0, TalkerALocation, ArrivalsAtA))
            {
                TestEqual(TEXT("nothing echoes back to the sender's own connection"), ArrivalsAtA, uint64{0});
            }

            return true;
        }),
        TEXT("positive control delivers; no echo")));

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

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
