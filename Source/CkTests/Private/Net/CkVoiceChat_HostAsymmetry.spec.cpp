// P3 listen-server asymmetry matrix. Host-TALKS is already pinned by the routing spec (its
// speaker transmits via the host-injection path); these cover the remaining quadrants:
//
//   HostHearsClient  (2 worlds): a CLIENT-owned talker transmits from the client world through
//     the real client-origin path (client-side encoder, client-side relay resolve, spoof guard
//     passing on matching sender/owner) and the HOST's ears decode it - the "Client RPC on a
//     host-owned relay executes locally" leg.
//
//   ClientToClient  (3 worlds): client 0 speaks, client 1 hears, and the SPEAKER's own world
//     decodes nothing for its own talker (a talker's frames are never forwarded back to its own
//     connection).
//
// Surface in Session Frontend: Ck.VoiceChat.Net.HostHearsClient / .ClientToClient

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "EngineUtils.h"

#include "CkVoiceChat/Capture/CkVoiceChat_CaptureSource.h"
#include "CkVoiceChat/VoiceChannel/CkVoiceChannel_Utils.h"
#include "CkVoiceChat/VoiceTalker/CkVoiceTalker_Utils.h"

#include "CkTests/Net/CkAutoTest_NetSubject_VoiceChat.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include "Misc/ConfigCacheIni.h"
#include "Modules/ModuleManager.h"
#include "VoiceModule.h"

#include <GameFramework/PlayerController.h>
#include <GameFramework/PlayerState.h>

// --------------------------------------------------------------------------------------------------------------------

namespace ck_voice_asymmetry_spec
{
    constexpr auto SampleRate = 48000;

    struct FAsymmetrySpecState
    {
        int32 Client0PlayerId = -1;

        bool HadOriginalVoiceKey = false;
        bool OriginalVoiceEnabled = false;
    };

    auto EnableEngineVoice(FAsymmetrySpecState& InState) -> void
    {
        InState.HadOriginalVoiceKey = GConfig->GetBool(TEXT("Voice"), TEXT("bEnabled"), InState.OriginalVoiceEnabled, GEngineIni);
        GConfig->SetBool(TEXT("Voice"), TEXT("bEnabled"), true, GEngineIni);

        if (FModuleManager::Get().IsModuleLoaded(TEXT("Voice")) && NOT FVoiceModule::Get().IsVoiceEnabled())
        {
            FModuleManager::Get().UnloadModule(TEXT("Voice"));
        }
    }

    auto RestoreEngineVoice(const FAsymmetrySpecState& InState) -> void
    {
        if (InState.HadOriginalVoiceKey)
        { GConfig->SetBool(TEXT("Voice"), TEXT("bEnabled"), InState.OriginalVoiceEnabled, GEngineIni); }
        else
        { GConfig->RemoveKey(TEXT("Voice"), TEXT("bEnabled"), GEngineIni); }
    }

    // The subject whose owning PlayerController is (or is not) locally controlled ON THE GIVEN
    // WORLD - locality flips per world, which is exactly how the tests tell "mine" from "theirs".
    auto Find_SubjectByLocalOwnership(UWorld* InWorld, bool InLocallyOwned) -> ACk_AutoTest_NetSubject_VoiceChat_UE*
    {
        for (TActorIterator<ACk_AutoTest_NetSubject_VoiceChat_UE> It{InWorld}; It; ++It)
        {
            const auto* OwnerController = ::Cast<APlayerController>(It->GetOwner());
            if (OwnerController == nullptr)
            { continue; }

            if (OwnerController->IsLocalController() == InLocallyOwned)
            { return *It; }
        }

        return nullptr;
    }

    auto Find_SubjectByOwnerPlayerId(UWorld* InWorld, int32 InPlayerId) -> ACk_AutoTest_NetSubject_VoiceChat_UE*
    {
        for (TActorIterator<ACk_AutoTest_NetSubject_VoiceChat_UE> It{InWorld}; It; ++It)
        {
            const auto* OwnerController = ::Cast<APlayerController>(It->GetOwner());
            if (OwnerController == nullptr || OwnerController->PlayerState == nullptr)
            { continue; }

            if (OwnerController->PlayerState->GetPlayerId() == InPlayerId)
            { return *It; }
        }

        return nullptr;
    }

    // On a THIRD PARTY's world, another client's subject has a NULL owner - PlayerControllers
    // replicate only to their owning client, so the owner reference cannot resolve there. "Not
    // locally owned" (null or non-local owner) is how a bystander world identifies it.
    auto Find_SubjectNotLocallyOwned(UWorld* InWorld) -> ACk_AutoTest_NetSubject_VoiceChat_UE*
    {
        for (TActorIterator<ACk_AutoTest_NetSubject_VoiceChat_UE> It{InWorld}; It; ++It)
        {
            const auto* OwnerController = ::Cast<APlayerController>(It->GetOwner());
            if (OwnerController == nullptr || NOT OwnerController->IsLocalController())
            { return *It; }
        }

        return nullptr;
    }

    auto TransmitFromSubject(FAutomationTestBase* InTest, ACk_AutoTest_NetSubject_VoiceChat_UE* InSubject) -> void
    {
        if (InSubject == nullptr || ck::Is_NOT_Valid(InSubject->_TestTalker))
        {
            InTest->AddError(TEXT("speaker subject / talker missing at transmit time"));
            return;
        }

        const auto FakeSource = MakeShared<FCk_VoiceChat_CaptureSource_Fake>(SampleRate);
        FakeSource->Enqueue_Silence(FCk_Time{0.2f});
        FakeSource->Enqueue_Sine(FCk_Time{0.8f}, 0.4f, 300.0f);
        FakeSource->Enqueue_Silence(FCk_Time{0.5f});

        UCk_Utils_VoiceTalker_UE::Debug_InjectCaptureSource(InSubject->_TestTalker, FakeSource);
        UCk_Utils_VoiceTalker_UE::Request_StartTransmit(InSubject->_TestTalker, {}, {});
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkVoiceChatNet_HostHearsClient,
    "Ck.VoiceChat.Net.HostHearsClient",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkVoiceChatNet_HostHearsClient::RunTest(const FString& Parameters)
{
    using namespace ck_voice_asymmetry_spec;

    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};
    const auto State = MakeShared<FAsymmetrySpecState, ESPMode::ThreadSafe>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(2, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(2, 30.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InServer) -> void
        {
            EnableEngineVoice(*State);

            auto* HostController = InServer->GetFirstPlayerController();
            auto* RemoteController = static_cast<APlayerController*>(nullptr);
            for (auto It = InServer->GetPlayerControllerIterator(); It; ++It)
            {
                if (auto* Controller = It->Get();
                    Controller != nullptr && NOT Controller->IsLocalController())
                { RemoteController = Controller; }
            }

            if (HostController == nullptr || RemoteController == nullptr)
            {
                AddError(TEXT("host and/or remote PlayerController missing on the server"));
                return;
            }

            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;

            SpawnInfo.Owner = RemoteController;   // the SPEAKER - client-owned
            if (InServer->SpawnActor<ACk_AutoTest_NetSubject_VoiceChat_UE>(
                    ACk_AutoTest_NetSubject_VoiceChat_UE::StaticClass(), FTransform::Identity, SpawnInfo) == nullptr)
            { AddError(TEXT("spawn of the client-owned speaker subject failed")); }

            SpawnInfo.Owner = HostController;     // the EARS - host-owned
            if (InServer->SpawnActor<ACk_AutoTest_NetSubject_VoiceChat_UE>(
                    ACk_AutoTest_NetSubject_VoiceChat_UE::StaticClass(), FTransform::Identity, SpawnInfo) == nullptr)
            { AddError(TEXT("spawn of the host-owned ears subject failed")); }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(40));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Speaker = Find_SubjectByLocalOwnership(InServer, false);
            auto* Ears = Find_SubjectByLocalOwnership(InServer, true);
            if (Speaker == nullptr || Ears == nullptr)
            {
                AddError(TEXT("speaker/ears subjects missing on the server at join time"));
                return;
            }

            UCk_Utils_VoiceChannel_UE::Request_Join(Speaker->_TestChannel,
                FCk_Request_VoiceChannel_Join{Speaker->_TestTalker}, {});
            UCk_Utils_VoiceChannel_UE::Request_Join(Speaker->_TestChannel,
                FCk_Request_VoiceChannel_Join{Ears->_TestTalker}, {});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(10));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(0,
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InClient) -> void
        {
            TransmitFromSubject(this, Find_SubjectByLocalOwnership(InClient, true));
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(140));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(0,
        FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InClient) -> void
        {
            if (auto* Speaker = Find_SubjectByLocalOwnership(InClient, true); Speaker != nullptr)
            { UCk_Utils_VoiceTalker_UE::Request_StopTransmit(Speaker->_TestTalker, {}); }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(60));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            RestoreEngineVoice(*State);

            auto* Server = ck::auto_test::net::Get_ServerWorld();
            auto* ServerSpeaker = Server != nullptr ? Find_SubjectByLocalOwnership(Server, false) : nullptr;
            if (ServerSpeaker == nullptr || ck::Is_NOT_Valid(ServerSpeaker->_TestTalker))
            {
                AddError(TEXT("server-side speaker subject missing at assertion time"));
                return false;
            }

            TestTrue(TEXT("the HOST decoded the client's voice (client-origin path end to end)"),
                UCk_Utils_VoiceTalker_UE::Debug_Get_LoopbackDecodedPcm(ServerSpeaker->_TestTalker).Num() > 0);

            return true;
        }),
        TEXT("host hears client")));

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
    FCkVoiceChatNet_ClientToClient,
    "Ck.VoiceChat.Net.ClientToClient",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkVoiceChatNet_ClientToClient::RunTest(const FString& Parameters)
{
    using namespace ck_voice_asymmetry_spec;

    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};
    const auto State = MakeShared<FAsymmetrySpecState, ESPMode::ThreadSafe>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(3, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(3, 30.0f));

    // A client's LOCAL PlayerState arrives with the initial replication after login - it is not
    // guaranteed to exist the moment PIE-ready fires.
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
            EnableEngineVoice(*State);

            auto* SpeakerController = static_cast<APlayerController*>(nullptr);
            auto* EarsController = static_cast<APlayerController*>(nullptr);
            for (auto It = InServer->GetPlayerControllerIterator(); It; ++It)
            {
                auto* Controller = It->Get();
                if (Controller == nullptr || Controller->IsLocalController() || Controller->PlayerState == nullptr)
                { continue; }

                if (Controller->PlayerState->GetPlayerId() == State->Client0PlayerId)
                { SpeakerController = Controller; }
                else
                { EarsController = Controller; }
            }

            if (SpeakerController == nullptr || EarsController == nullptr)
            {
                AddError(TEXT("could not resolve both remote PlayerControllers on the server"));
                return;
            }

            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;

            SpawnInfo.Owner = SpeakerController;
            if (InServer->SpawnActor<ACk_AutoTest_NetSubject_VoiceChat_UE>(
                    ACk_AutoTest_NetSubject_VoiceChat_UE::StaticClass(), FTransform::Identity, SpawnInfo) == nullptr)
            { AddError(TEXT("spawn of the client-0-owned speaker subject failed")); }

            SpawnInfo.Owner = EarsController;
            if (InServer->SpawnActor<ACk_AutoTest_NetSubject_VoiceChat_UE>(
                    ACk_AutoTest_NetSubject_VoiceChat_UE::StaticClass(), FTransform::Identity, SpawnInfo) == nullptr)
            { AddError(TEXT("spawn of the client-1-owned ears subject failed")); }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(40));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InServer) -> void
        {
            auto* Speaker = Find_SubjectByOwnerPlayerId(InServer, State->Client0PlayerId);
            auto* Ears = static_cast<ACk_AutoTest_NetSubject_VoiceChat_UE*>(nullptr);
            for (TActorIterator<ACk_AutoTest_NetSubject_VoiceChat_UE> It{InServer}; It; ++It)
            {
                if (*It != Speaker)
                { Ears = *It; }
            }

            if (Speaker == nullptr || Ears == nullptr)
            {
                AddError(TEXT("speaker/ears subjects missing on the server at join time"));
                return;
            }

            UCk_Utils_VoiceChannel_UE::Request_Join(Speaker->_TestChannel,
                FCk_Request_VoiceChannel_Join{Speaker->_TestTalker}, {});
            UCk_Utils_VoiceChannel_UE::Request_Join(Speaker->_TestChannel,
                FCk_Request_VoiceChannel_Join{Ears->_TestTalker}, {});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(10));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(0,
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InClient) -> void
        {
            TransmitFromSubject(this, Find_SubjectByLocalOwnership(InClient, true));
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(140));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnClient(0,
        FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InClient) -> void
        {
            if (auto* Speaker = Find_SubjectByLocalOwnership(InClient, true); Speaker != nullptr)
            { UCk_Utils_VoiceTalker_UE::Request_StopTransmit(Speaker->_TestTalker, {}); }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(60));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            RestoreEngineVoice(*State);

            auto* Client1 = ck::auto_test::net::Get_ClientWorld(1);
            auto* HeardSpeaker = Client1 != nullptr ? Find_SubjectNotLocallyOwned(Client1) : nullptr;
            if (HeardSpeaker == nullptr || ck::Is_NOT_Valid(HeardSpeaker->_TestTalker))
            {
                AddError(TEXT("client 1's replica of the speaker subject missing at assertion time"));
                return false;
            }

            TestTrue(TEXT("client 1 decoded client 0's voice (client-to-client through the server)"),
                UCk_Utils_VoiceTalker_UE::Debug_Get_LoopbackDecodedPcm(HeardSpeaker->_TestTalker).Num() > 0);

            auto* Client0 = ck::auto_test::net::Get_ClientWorld(0);
            auto* OwnSpeaker = Client0 != nullptr ? Find_SubjectByLocalOwnership(Client0, true) : nullptr;
            if (OwnSpeaker == nullptr || ck::Is_NOT_Valid(OwnSpeaker->_TestTalker))
            {
                AddError(TEXT("client 0's own speaker subject missing at assertion time"));
                return false;
            }

            TestEqual(TEXT("the speaker's own world decoded NOTHING for its own talker (no echo back)"),
                UCk_Utils_VoiceTalker_UE::Debug_Get_LoopbackDecodedPcm(OwnSpeaker->_TestTalker).Num(), 0);

            return true;
        }),
        TEXT("client-to-client voice + no echo")));

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
