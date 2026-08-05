// P3 control-plane gate (local half): the authority-side channel index allocator hands out
// unique, round-trippable indices; membership requests mutate exactly the state they claim to;
// and the invalid-input boundaries reject with zero partial state (non-negotiable #3). The
// replicated half (RepData, late-join, voice-before-registry) gets its own spec with the Route
// processor.
//
// Surface in Session Frontend: Ck.VoiceChat.Channel.MembershipAndIdx / .InvalidInputs_Rejected

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkCore/GameplayTag/CkGameplayTag_Utils.h"
#include "CkCore/Macros/CkMacros.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkTests/Net/CkNetAutomation_Common.h"

#include "CkVoiceChat/VoiceChannel/CkVoiceChannel_Fragment.h"
#include "CkVoiceChat/VoiceChannel/CkVoiceChannel_Utils.h"
#include "CkVoiceChat/VoiceTalker/CkVoiceTalker_Utils.h"

#include "Engine/World.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_voice_channel_spec
{
    struct FChannelSpecState
    {
        FCk_Handle Host;
        FCk_Handle_VoiceChannel ChannelAlpha;
        FCk_Handle_VoiceChannel ChannelBeta;
        FCk_Handle_VoiceTalker Talker;
    };
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkVoiceChatChannel_MembershipAndIdx,
    "Ck.VoiceChat.Channel.MembershipAndIdx",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkVoiceChatChannel_MembershipAndIdx::RunTest(const FString& Parameters)
{
    using namespace ck_voice_channel_spec;

    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};
    const auto State = MakeShared<FChannelSpecState, ESPMode::ThreadSafe>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld* InServer) -> void
        {
            auto TransientEntity = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
            State->Host = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(TransientEntity);

            State->ChannelAlpha = UCk_Utils_VoiceChannel_UE::Add(State->Host,
                FCk_Fragment_VoiceChannel_ParamsData{
                    UCk_Utils_GameplayTag_UE::ResolveGameplayTag(TEXT("VoiceChat.Channel.TestAlpha"))});
            State->ChannelBeta = UCk_Utils_VoiceChannel_UE::Add(State->Host,
                FCk_Fragment_VoiceChannel_ParamsData{
                    UCk_Utils_GameplayTag_UE::ResolveGameplayTag(TEXT("VoiceChat.Channel.TestBeta"))});

            auto TalkerEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(TransientEntity);
            State->Talker = UCk_Utils_VoiceTalker_UE::Add(TalkerEntity, FCk_Fragment_VoiceTalker_ParamsData{});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(5));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            const auto IdxAlpha = UCk_Utils_VoiceChannel_UE::Get_ChannelIdx(State->ChannelAlpha);
            const auto IdxBeta = UCk_Utils_VoiceChannel_UE::Get_ChannelIdx(State->ChannelBeta);

            TestNotEqual(TEXT("channel Alpha received a real index"), IdxAlpha, ck::VoiceChannel_UnassignedIdx);
            TestNotEqual(TEXT("channel Beta received a real index"), IdxBeta, ck::VoiceChannel_UnassignedIdx);
            TestNotEqual(TEXT("indices are unique"), IdxAlpha, IdxBeta);

            TestTrue(TEXT("Alpha's index round-trips through the registry"),
                UCk_Utils_VoiceChannel_UE::TryGet_ChannelByIdx(State->Host, IdxAlpha) == State->ChannelAlpha);
            TestTrue(TEXT("Beta's index round-trips through the registry"),
                UCk_Utils_VoiceChannel_UE::TryGet_ChannelByIdx(State->Host, IdxBeta) == State->ChannelBeta);
            TestFalse(TEXT("an unallocated index resolves to nothing"),
                ck::IsValid(UCk_Utils_VoiceChannel_UE::TryGet_ChannelByIdx(State->Host, 200)));

            return true;
        }), TEXT("[VoiceChannel] idx allocation assertions")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld* InServer) -> void
        {
            UCk_Utils_VoiceChannel_UE::Request_Join(State->ChannelAlpha,
                FCk_Request_VoiceChannel_Join{State->Talker}, {});
            UCk_Utils_VoiceChannel_UE::Request_ServerMute(State->ChannelAlpha,
                FCk_Request_VoiceChannel_ServerMute{State->Talker}, {});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(5));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            TestTrue(TEXT("talker joined Alpha"),
                UCk_Utils_VoiceChannel_UE::Get_IsMember(State->ChannelAlpha, State->Talker));
            TestFalse(TEXT("talker is NOT a member of Beta"),
                UCk_Utils_VoiceChannel_UE::Get_IsMember(State->ChannelBeta, State->Talker));

            const auto Flags = UCk_Utils_VoiceChannel_UE::Get_MemberFlags(State->ChannelAlpha, State->Talker);
            TestTrue(TEXT("default member flags: CanTalk"), Flags.Get_CanTalk() == ECk_EnableDisable::Enable);
            TestTrue(TEXT("default member flags: CanHear"), Flags.Get_CanHear() == ECk_EnableDisable::Enable);

            TestTrue(TEXT("talker is server-muted on Alpha"),
                UCk_Utils_VoiceChannel_UE::Get_IsServerMuted(State->ChannelAlpha, State->Talker));

            return true;
        }), TEXT("[VoiceChannel] membership assertions")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld* InServer) -> void
        {
            UCk_Utils_VoiceChannel_UE::Request_Leave(State->ChannelAlpha,
                FCk_Request_VoiceChannel_Leave{State->Talker}, {});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(5));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            TestFalse(TEXT("talker left Alpha"),
                UCk_Utils_VoiceChannel_UE::Get_IsMember(State->ChannelAlpha, State->Talker));
            TestTrue(TEXT("server mute deliberately SURVIVES leave (moderation contract: rejoin stays muted)"),
                UCk_Utils_VoiceChannel_UE::Get_IsServerMuted(State->ChannelAlpha, State->Talker));

            return true;
        }), TEXT("[VoiceChannel] leave assertions")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkVoiceChatChannel_InvalidInputsRejected,
    "Ck.VoiceChat.Channel.InvalidInputs_Rejected",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkVoiceChatChannel_InvalidInputsRejected::RunTest(const FString& Parameters)
{
    using namespace ck_voice_channel_spec;

    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    // Whitelist every matching line: one CK ensure can surface through multiple log paths.
    AddExpectedError(TEXT("with an invalid Talker handle"), EAutomationExpectedErrorFlags::Contains, -1);
    AddExpectedError(TEXT("who is not a member"), EAutomationExpectedErrorFlags::Contains, -1);

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};
    const auto State = MakeShared<FChannelSpecState, ESPMode::ThreadSafe>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld* InServer) -> void
        {
            auto TransientEntity = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
            State->Host = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(TransientEntity);

            State->ChannelAlpha = UCk_Utils_VoiceChannel_UE::Add(State->Host,
                FCk_Fragment_VoiceChannel_ParamsData{
                    UCk_Utils_GameplayTag_UE::ResolveGameplayTag(TEXT("VoiceChat.Channel.TestRejection"))});

            auto TalkerEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(TransientEntity);
            State->Talker = UCk_Utils_VoiceTalker_UE::Add(TalkerEntity, FCk_Fragment_VoiceTalker_ParamsData{});

            // Invalid talker on Join; valid-but-never-joined talker on SetMemberFlags. Both must
            // ensure, complete Failed, and leave ZERO membership state behind.
            UCk_Utils_VoiceChannel_UE::Request_Join(State->ChannelAlpha,
                FCk_Request_VoiceChannel_Join{FCk_Handle_VoiceTalker{}}, {});
            UCk_Utils_VoiceChannel_UE::Request_SetMemberFlags(State->ChannelAlpha,
                FCk_Request_VoiceChannel_SetMemberFlags{State->Talker, FCk_VoiceChat_MemberFlags{}}, {});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(10));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            TestTrue(TEXT("zero members after both rejected requests"),
                UCk_Utils_VoiceChannel_UE::Get_Members(State->ChannelAlpha).IsEmpty());
            TestFalse(TEXT("the never-joined talker did not become a member"),
                UCk_Utils_VoiceChannel_UE::Get_IsMember(State->ChannelAlpha, State->Talker));

            return true;
        }), TEXT("[VoiceChannel] rejection assertions")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// The channel-Setup asset-resolution boundary (non-negotiable #3, focused invalid-input half):
// an authored soft ref that cannot resolve ensures once, completes setup on module defaults
// (resolved getters null), and leaves the channel fully functional - no partial state. The
// positive path (a real asset audibly applied) is the Gate_4 [EDITOR-VERIFY] audition.
IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkVoiceChatChannel_AudioAssetResolveFails,
    "Ck.VoiceChat.Channel.AudioAssetResolveFails",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkVoiceChatChannel_AudioAssetResolveFails::RunTest(const FString& Parameters)
{
    using namespace ck_voice_channel_spec;

    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};
    const auto State = MakeShared<FChannelSpecState, ESPMode::ThreadSafe>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld* InServer) -> void
        {
            auto TransientEntity = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
            State->Host = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(TransientEntity);

            auto Params = FCk_Fragment_VoiceChannel_ParamsData{
                UCk_Utils_GameplayTag_UE::ResolveGameplayTag(TEXT("VoiceChat.Channel.TestBadAsset"))}
                .Set_Attenuation(TSoftObjectPtr<USoundAttenuation>{
                    FSoftObjectPath{TEXT("/Game/DoesNotExist/CkVoice_BogusAttenuation.CkVoice_BogusAttenuation")}});

            State->ChannelAlpha = UCk_Utils_VoiceChannel_UE::Add(State->Host, Params);

            auto TalkerHost = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(TransientEntity);
            State->Talker = UCk_Utils_VoiceTalker_UE::Add(TalkerHost, FCk_Fragment_VoiceTalker_ParamsData{});
        })));

    // The failed async load must complete setup, not hang it - poll for the boundary to settle.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
        {
            return ck::IsValid(State->ChannelAlpha) &&
                NOT State->ChannelAlpha.Has<ck::FTag_VoiceChannel_PendingAssetLoad>() &&
                NOT State->ChannelAlpha.Has<ck::FTag_VoiceChannel_NeedsSetup>();
        }),
        15.0,
        TEXT("channel setup completes despite the failed resolve")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld* InServer) -> void
        {
            UCk_Utils_VoiceChannel_UE::Request_Join(State->ChannelAlpha,
                FCk_Request_VoiceChannel_Join{State->Talker}, {});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(10));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            TestTrue(TEXT("resolved attenuation is null after the failed resolve"),
                UCk_Utils_VoiceChannel_UE::Get_ResolvedAttenuation(State->ChannelAlpha) == nullptr);
            TestTrue(TEXT("resolved effect chain is null after the failed resolve"),
                UCk_Utils_VoiceChannel_UE::Get_ResolvedSourceEffectChain(State->ChannelAlpha) == nullptr);

            TestTrue(TEXT("the channel stays fully functional - membership works (no partial state)"),
                UCk_Utils_VoiceChannel_UE::Get_IsMember(State->ChannelAlpha, State->Talker));

            return true;
        }),
        TEXT("failed resolve: defaults + zero partial state")));

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
