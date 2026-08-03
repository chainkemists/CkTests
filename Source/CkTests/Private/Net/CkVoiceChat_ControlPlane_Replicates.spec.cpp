// P3 control-plane replication coverage: a VoiceChannel composed symmetrically on server and
// client via the shared NetSubject replicates its registry entry (wire ChannelIdx) and its
// membership + server-mute state through FCk_RepData_VoiceChat (Apply/NotReady contract). The
// late-join property is implicit in the transport: the container carries FULL state, so a client
// that applies it at all has the complete control plane.
//
// Surface in Session Frontend: Ck.VoiceChat.Net.ControlPlane_Replicates

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"

#include "CkVoiceChat/VoiceChannel/CkVoiceChannel_Fragment_Data.h"
#include "CkVoiceChat/VoiceChannel/CkVoiceChannel_Utils.h"

#include "CkTests/Net/CkAutoTest_NetSubject.h"
#include "CkTests/Net/CkAutoTest_NetSubject_VoiceChat.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_voice_control_plane_spec
{
    auto Get_Subject(UWorld* InWorld) -> ACk_AutoTest_NetSubject_VoiceChat_UE*
    {
        return Cast<ACk_AutoTest_NetSubject_VoiceChat_UE>(ACk_AutoTest_NetSubject::Find(InWorld));
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkVoiceChatNet_ControlPlaneReplicates,
    "Ck.VoiceChat.Net.ControlPlane_Replicates",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkVoiceChatNet_ControlPlaneReplicates::RunTest(const FString& Parameters)
{
    using namespace ck_voice_control_plane_spec;

    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesAfterSpawn = 30;    // symmetric composition + idx assignment + first push
    constexpr auto FramesAfterMutation = 30; // container delta + client deferred apply

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
            auto* Subject = InServer->SpawnActor<ACk_AutoTest_NetSubject_VoiceChat_UE>(
                ACk_AutoTest_NetSubject_VoiceChat_UE::StaticClass(), FTransform::Identity, SpawnInfo);
            if (Subject == nullptr)
            { AddError(TEXT("server-side SpawnActor of ACk_AutoTest_NetSubject_VoiceChat_UE returned null")); }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterSpawn));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Subject = Get_Subject(InServer);
            if (Subject == nullptr || ck::Is_NOT_Valid(Subject->_TestChannel))
            {
                AddError(TEXT("server-side VoiceChat subject / _TestChannel missing at join time"));
                return;
            }

            UCk_Utils_VoiceChannel_UE::Request_Join(Subject->_TestChannel,
                FCk_Request_VoiceChannel_Join{Subject->_TestTalker}, {});
            UCk_Utils_VoiceChannel_UE::Request_ServerMute(Subject->_TestChannel,
                FCk_Request_VoiceChannel_ServerMute{Subject->_TestTalker}, {});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterMutation));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Server == nullptr || Client == nullptr)
            {
                AddError(TEXT("server and/or client world unavailable at assertion time"));
                return false;
            }

            auto* ServerSubject = Get_Subject(Server);
            auto* ClientSubject = Get_Subject(Client);
            if (ServerSubject == nullptr || ClientSubject == nullptr)
            {
                AddError(TEXT("VoiceChat subject missing on server and/or client at assertion time"));
                return false;
            }

            if (NOT TestTrue(TEXT("client composed its channel symmetrically"), ck::IsValid(ClientSubject->_TestChannel)))
            { return true; }

            const auto ServerIdx = UCk_Utils_VoiceChannel_UE::Get_ChannelIdx(ServerSubject->_TestChannel);
            const auto ClientIdx = UCk_Utils_VoiceChannel_UE::Get_ChannelIdx(ClientSubject->_TestChannel);

            TestNotEqual(TEXT("server allocated a real wire idx"), ServerIdx, ck::VoiceChannel_UnassignedIdx);
            TestEqual(TEXT("client received the SERVER's wire idx through the control plane"), ClientIdx, ServerIdx);

            TestTrue(TEXT("membership replicated: client sees its talker as a member"),
                UCk_Utils_VoiceChannel_UE::Get_IsMember(ClientSubject->_TestChannel, ClientSubject->_TestTalker));
            TestTrue(TEXT("server-mute matrix replicated"),
                UCk_Utils_VoiceChannel_UE::Get_IsServerMuted(ClientSubject->_TestChannel, ClientSubject->_TestTalker));

            return true;
        }),
        TEXT("control plane replicated: idx + membership + server mute")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Subject = Get_Subject(InServer);
            if (Subject == nullptr || ck::Is_NOT_Valid(Subject->_TestChannel))
            {
                AddError(TEXT("server-side VoiceChat subject / _TestChannel missing at leave time"));
                return;
            }

            UCk_Utils_VoiceChannel_UE::Request_Leave(Subject->_TestChannel,
                FCk_Request_VoiceChannel_Leave{Subject->_TestTalker}, {});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesAfterMutation));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            auto* ClientSubject = Client != nullptr ? Get_Subject(Client) : nullptr;
            if (ClientSubject == nullptr || ck::Is_NOT_Valid(ClientSubject->_TestChannel))
            {
                AddError(TEXT("client-side VoiceChat subject / _TestChannel missing at leave-assertion time"));
                return false;
            }

            TestFalse(TEXT("leave replicated: client no longer sees the talker as a member"),
                UCk_Utils_VoiceChannel_UE::Get_IsMember(ClientSubject->_TestChannel, ClientSubject->_TestTalker));
            TestTrue(TEXT("server mute SURVIVES leave on the client too (moderation contract)"),
                UCk_Utils_VoiceChannel_UE::Get_IsServerMuted(ClientSubject->_TestChannel, ClientSubject->_TestTalker));

            return true;
        }),
        TEXT("leave replicated; mute survives")));

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
