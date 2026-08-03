// P3 routing gate: the server Route processor forwards a transmitting talker's bundles to
// CanHear members on OTHER connections (never back to the talker's own), and enforces the N1
// contract - a bundle whose wire ChannelIdx does not resolve is dropped and counted, NEVER
// stashed: allocating that very idx afterwards (with members who would receive it) must not
// resurrect the dropped bundle.
//
// Topology: subject A is server-owned (its talker transmits via the listen-host injection path,
// no self-RPC); subject B is spawned OWNED BY the client's PlayerController, so its talker
// resolves to the client connection - the recipient. Both worlds compose both subjects
// symmetrically; B's talker joins A's channel as a listener.
//
// Surface in Session Frontend: Ck.VoiceChat.Net.Routing_ForwardsAndNeverStashes

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "EngineUtils.h"

#include "CkEcs/OwningActor/CkOwningActor_Utils.h"

#include "CkVoiceChat/Capture/CkVoiceChat_CaptureSource.h"
#include "CkVoiceChat/Codec/CkVoiceChat_Codec.h"
#include "CkVoiceChat/VoiceChannel/CkVoiceChannel_Utils.h"
#include "CkVoiceChat/VoiceTalker/CkVoiceTalker_Utils.h"

#include "CkTests/Net/CkAutoTest_NetSubject_VoiceChat.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include "Misc/ConfigCacheIni.h"
#include "Modules/ModuleManager.h"
#include "VoiceModule.h"

#include <GameFramework/PlayerController.h>
#include <NativeGameplayTags.h>

// --------------------------------------------------------------------------------------------------------------------

UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_VoiceChat_Channel_AutoTest_NeverStash, TEXT("VoiceChat.Channel.AutoTest.NeverStash"));

namespace ck_voice_routing_spec
{
    constexpr auto SampleRate = 48000;

    struct FRoutingSpecState
    {
        int32 ClientInboxAfterTransmit = 0;

        bool HadOriginalVoiceKey = false;
        bool OriginalVoiceEnabled = false;
    };

    // The engine Voice module reads [Voice] bEnabled ONCE at StartupModule; the host project has
    // no [Voice] section, so the encoder factory would return null. Same self-enable +
    // capture-and-restore shape as the pipeline spec.
    auto EnableEngineVoice(FRoutingSpecState& InState) -> void
    {
        InState.HadOriginalVoiceKey = GConfig->GetBool(TEXT("Voice"), TEXT("bEnabled"), InState.OriginalVoiceEnabled, GEngineIni);
        GConfig->SetBool(TEXT("Voice"), TEXT("bEnabled"), true, GEngineIni);

        if (FModuleManager::Get().IsModuleLoaded(TEXT("Voice")) && NOT FVoiceModule::Get().IsVoiceEnabled())
        {
            FModuleManager::Get().UnloadModule(TEXT("Voice"));
        }
    }

    auto RestoreEngineVoice(const FRoutingSpecState& InState) -> void
    {
        if (InState.HadOriginalVoiceKey)
        { GConfig->SetBool(TEXT("Voice"), TEXT("bEnabled"), InState.OriginalVoiceEnabled, GEngineIni); }
        else
        { GConfig->RemoveKey(TEXT("Voice"), TEXT("bEnabled"), GEngineIni); }
    }

    auto Find_Subject(UWorld* InWorld, bool InServerOwned) -> ACk_AutoTest_NetSubject_VoiceChat_UE*
    {
        for (TActorIterator<ACk_AutoTest_NetSubject_VoiceChat_UE> It{InWorld}; It; ++It)
        {
            const auto IsServerOwned = It->GetOwner() == nullptr;
            if (IsServerOwned == InServerOwned)
            { return *It; }
        }

        return nullptr;
    }

    auto Find_RemotePlayerController(UWorld* InServer) -> APlayerController*
    {
        for (auto It = InServer->GetPlayerControllerIterator(); It; ++It)
        {
            if (auto* Controller = It->Get();
                Controller != nullptr && NOT Controller->IsLocalController())
            { return Controller; }
        }

        return nullptr;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkVoiceChatNet_RoutingForwardsAndNeverStashes,
    "Ck.VoiceChat.Net.Routing_ForwardsAndNeverStashes",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkVoiceChatNet_RoutingForwardsAndNeverStashes::RunTest(const FString& Parameters)
{
    using namespace ck_voice_routing_spec;

    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};
    const auto State = MakeShared<FRoutingSpecState, ESPMode::ThreadSafe>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InServer) -> void
        {
            EnableEngineVoice(*State);

            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;

            auto* SubjectA = InServer->SpawnActor<ACk_AutoTest_NetSubject_VoiceChat_UE>(
                ACk_AutoTest_NetSubject_VoiceChat_UE::StaticClass(), FTransform::Identity, SpawnInfo);
            if (SubjectA == nullptr)
            { AddError(TEXT("server-side SpawnActor of subject A returned null")); }

            auto* RemoteController = Find_RemotePlayerController(InServer);
            if (RemoteController == nullptr)
            {
                AddError(TEXT("no remote (client) PlayerController found on the server"));
                return;
            }

            SpawnInfo.Owner = RemoteController;
            auto* SubjectB = InServer->SpawnActor<ACk_AutoTest_NetSubject_VoiceChat_UE>(
                ACk_AutoTest_NetSubject_VoiceChat_UE::StaticClass(), FTransform::Identity, SpawnInfo);
            if (SubjectB == nullptr)
            { AddError(TEXT("server-side SpawnActor of subject B returned null")); }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(40));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* SubjectA = Find_Subject(InServer, true);
            auto* SubjectB = Find_Subject(InServer, false);
            if (SubjectA == nullptr || SubjectB == nullptr
                || ck::Is_NOT_Valid(SubjectA->_TestChannel) || ck::Is_NOT_Valid(SubjectB->_TestTalker))
            {
                AddError(TEXT("subjects/channel/talker missing on the server at join time"));
                return;
            }

            UCk_Utils_VoiceChannel_UE::Request_Join(SubjectA->_TestChannel,
                FCk_Request_VoiceChannel_Join{SubjectA->_TestTalker}, {});
            UCk_Utils_VoiceChannel_UE::Request_Join(SubjectA->_TestChannel,
                FCk_Request_VoiceChannel_Join{SubjectB->_TestTalker}, {});

            // 0.2 s silence (VAD closed), 0.8 s sine (frames flow), trailing silence (VAD closes).
            const auto FakeSource = MakeShared<FCk_VoiceChat_CaptureSource_Fake>(SampleRate);
            FakeSource->Enqueue_Silence(0.2f);
            FakeSource->Enqueue_Sine(0.8f, 0.4f, 300.0f);
            FakeSource->Enqueue_Silence(0.5f);

            UCk_Utils_VoiceTalker_UE::Debug_InjectCaptureSource(SubjectA->_TestTalker, FakeSource);
            UCk_Utils_VoiceTalker_UE::Request_StartTransmit(SubjectA->_TestTalker, {}, {});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(140));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* SubjectA = Find_Subject(InServer, true);
            if (SubjectA == nullptr)
            { return; }

            UCk_Utils_VoiceTalker_UE::Request_StopTransmit(SubjectA->_TestTalker, {});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(20));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr)
            {
                AddError(TEXT("client world unavailable at forward-assertion time"));
                return false;
            }

            auto* ClientSubjectA = Find_Subject(Client, true);
            auto* ClientSubjectB = Find_Subject(Client, false);
            if (ClientSubjectA == nullptr || ClientSubjectB == nullptr
                || ck::Is_NOT_Valid(ClientSubjectA->_TestTalker) || ck::Is_NOT_Valid(ClientSubjectB->_TestTalker))
            {
                AddError(TEXT("client-side subjects/talkers missing at forward-assertion time"));
                return false;
            }

            State->ClientInboxAfterTransmit =
                UCk_Utils_VoiceTalker_UE::Debug_Get_ReceiveInboxNum(ClientSubjectA->_TestTalker);

            TestTrue(TEXT("the client received talker A's bundles (routing forwarded to the CanHear member's connection)"),
                State->ClientInboxAfterTransmit > 0);
            TestEqual(TEXT("nothing was forwarded FOR talker B (it never spoke)"),
                UCk_Utils_VoiceTalker_UE::Debug_Get_ReceiveInboxNum(ClientSubjectB->_TestTalker), 0);

            return true;
        }),
        TEXT("routing forwarded the spurt to the client")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* SubjectA = Find_Subject(InServer, true);
            if (SubjectA == nullptr || ck::Is_NOT_Valid(SubjectA->_TestTalker))
            { return; }

            // A bundle naming a ChannelIdx that does not resolve YET (the next idx the allocator
            // will hand out). N1: the route must drop it now - and must not resurrect it when
            // that idx becomes real below.
            const auto FutureIdx = static_cast<uint8>(2);
            auto Frame = TArray<uint8>{};
            Frame.Init(0x5A, 32);

            const auto Packed = ck::voice_chat::codec::Pack_Bundle(
                FCk_VoiceChat_BundleHeader{1, FutureIdx, 128}, TArray<TArray<uint8>>{Frame});

            UCk_Utils_VoiceTalker_UE::Debug_InjectInboundBundle(SubjectA->_TestTalker, Packed, nullptr);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(10));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* SubjectA = Find_Subject(InServer, true);
            auto* SubjectB = Find_Subject(InServer, false);
            if (SubjectA == nullptr || SubjectB == nullptr)
            { return; }

            // Allocate the idx the dropped bundle named, with members who WOULD receive it if it
            // had been stashed anywhere.
            auto HostEntity = UCk_Utils_OwningActor_UE::Get_ActorEntityHandle(SubjectA);
            auto LateChannel = UCk_Utils_VoiceChannel_UE::Add(HostEntity,
                FCk_Fragment_VoiceChannel_ParamsData{TAG_VoiceChat_Channel_AutoTest_NeverStash});

            UCk_Utils_VoiceChannel_UE::Request_Join(LateChannel,
                FCk_Request_VoiceChannel_Join{SubjectA->_TestTalker}, {});
            UCk_Utils_VoiceChannel_UE::Request_Join(LateChannel,
                FCk_Request_VoiceChannel_Join{SubjectB->_TestTalker}, {});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(30));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            RestoreEngineVoice(*State);

            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            auto* ClientSubjectA = Client != nullptr ? Find_Subject(Client, true) : nullptr;
            if (ClientSubjectA == nullptr || ck::Is_NOT_Valid(ClientSubjectA->_TestTalker))
            {
                AddError(TEXT("client-side subject A missing at never-stash assertion time"));
                return false;
            }

            TestEqual(TEXT("the dropped bundle did NOT resurrect when its ChannelIdx became real (N1: never stash)"),
                UCk_Utils_VoiceTalker_UE::Debug_Get_ReceiveInboxNum(ClientSubjectA->_TestTalker),
                State->ClientInboxAfterTransmit);

            return true;
        }),
        TEXT("N1 never-stash holds")));

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
