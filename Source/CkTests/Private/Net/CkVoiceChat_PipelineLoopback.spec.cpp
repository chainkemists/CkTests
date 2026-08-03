// P2 pipeline gate: the full VoiceTalker loop — fake capture -> gain -> per-frame RMS/VAD ->
// Opus encode -> jitter buffer -> decode — runs headless in a single PIE world and produces
// decoded PCM, with the VAD provably gating both ways (leading/trailing silence produces no
// frames; the sine spurt does). Real microphone and audible output remain human EDITOR-VERIFY
// steps; this is the machine-checkable core.
//
// Surface in Session Frontend: Ck.VoiceChat.Pipeline.FakeCapture_LoopbackDecodes

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkCore/Macros/CkMacros.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkTests/Net/CkNetAutomation_Common.h"

#include "CkVoiceChat/Capture/CkVoiceChat_CaptureSource.h"
#include "CkVoiceChat/VoiceTalker/CkVoiceTalker_Utils.h"

#include "Engine/World.h"
#include "Misc/ConfigCacheIni.h"
#include "Modules/ModuleManager.h"
#include "VoiceModule.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_voice_pipeline_spec
{
    constexpr auto SampleRate = 48000;
    constexpr auto BytesPerSecond = SampleRate * 2;

    struct FPipelineState
    {
        FCk_Handle_VoiceTalker Talker;

        bool HadOriginalVoiceKey = false;
        bool OriginalVoiceEnabled = false;
    };

    auto EnableEngineVoice(FPipelineState& InState) -> void
    {
        InState.HadOriginalVoiceKey = GConfig->GetBool(TEXT("Voice"), TEXT("bEnabled"), InState.OriginalVoiceEnabled, GEngineIni);
        GConfig->SetBool(TEXT("Voice"), TEXT("bEnabled"), true, GEngineIni);

        if (FModuleManager::Get().IsModuleLoaded(TEXT("Voice")) && NOT FVoiceModule::Get().IsVoiceEnabled())
        {
            FModuleManager::Get().UnloadModule(TEXT("Voice"));
        }
    }

    auto RestoreEngineVoice(const FPipelineState& InState) -> void
    {
        if (InState.HadOriginalVoiceKey)
        { GConfig->SetBool(TEXT("Voice"), TEXT("bEnabled"), InState.OriginalVoiceEnabled, GEngineIni); }
        else
        { GConfig->RemoveKey(TEXT("Voice"), TEXT("bEnabled"), GEngineIni); }
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkVoiceChatPipeline_FakeCapture_LoopbackDecodes,
    "Ck.VoiceChat.Pipeline.FakeCapture_LoopbackDecodes",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkVoiceChatPipeline_FakeCapture_LoopbackDecodes::RunTest(const FString& Parameters)
{
    using namespace ck_voice_pipeline_spec;

    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};
    const auto State = MakeShared<FPipelineState, ESPMode::ThreadSafe>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, State](UWorld* InServer) -> void
        {
            EnableEngineVoice(*State);

            auto TransientEntity = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
            auto TalkerEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(TransientEntity);

            auto Params = FCk_Fragment_VoiceTalker_ParamsData{};
            Params.Set_TransmitMode(ECk_VoiceChat_TransmitMode::OpenMic);
            Params.Set_InputGain(1.0f);
            Params.Set_Loopback(ECk_EnableDisable::Enable);

            State->Talker = UCk_Utils_VoiceTalker_UE::Add(TalkerEntity, Params);

            // leading silence (VAD must gate it out), one sine spurt, trailing silence (VAD
            // must close and the loopback must fully drain during it)
            const auto FakeSource = MakeShared<FCk_VoiceChat_CaptureSource_Fake>(SampleRate);
            FakeSource->Enqueue_Silence(0.3f);
            FakeSource->Enqueue_Sine(1.0f, 0.4f, 300.0f);
            FakeSource->Enqueue_Silence(0.6f);

            UCk_Utils_VoiceTalker_UE::Debug_InjectCaptureSource(State->Talker, FakeSource);
            UCk_Utils_VoiceTalker_UE::Request_StartTransmit(State->Talker, {}, {});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
        {
            return ck::IsValid(State->Talker) && UCk_Utils_VoiceTalker_UE::Get_IsSpeaking(State->Talker);
        }), 15.0, TEXT("VAD opened during the sine spurt")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([State]() -> bool
        {
            return ck::IsValid(State->Talker) && NOT UCk_Utils_VoiceTalker_UE::Get_IsSpeaking(State->Talker);
        }), 15.0, TEXT("VAD closed after the spurt ended")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(60));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            RestoreEngineVoice(*State);

            if (NOT TestTrue(TEXT("talker handle still valid"), ck::IsValid(State->Talker)))
            { return true; }

            TestTrue(TEXT("still transmitting (open mic; the spurt ending must not stop transmit)"),
                UCk_Utils_VoiceTalker_UE::Get_IsTransmitting(State->Talker));

            const auto& DecodedPcm = UCk_Utils_VoiceTalker_UE::Debug_Get_LoopbackDecodedPcm(State->Talker);

            UE_LOG(LogTemp, Display, TEXT("[VoicePipeline] loopback decoded %d bytes (%.2f s)"),
                DecodedPcm.Num(), static_cast<float>(DecodedPcm.Num()) / BytesPerSecond);

            TestTrue(TEXT("VAD gated IN the spurt: at least 0.5 s of decoded PCM"),
                DecodedPcm.Num() >= BytesPerSecond / 2);
            TestTrue(TEXT("VAD gated OUT the silence: no more than 1.5 s decoded from 1.9 s of input"),
                DecodedPcm.Num() <= (BytesPerSecond * 3) / 2);

            auto LoudSamples = 0;
            const auto* Samples = reinterpret_cast<const int16*>(DecodedPcm.GetData());
            for (auto SampleIdx = 0; SampleIdx < DecodedPcm.Num() / 2; ++SampleIdx)
            {
                if (FMath::Abs(Samples[SampleIdx]) > 1000)
                { ++LoudSamples; }
            }

            TestTrue(TEXT("decoded PCM carries the sine, not silence"), LoudSamples > 1000);

            return true;
        }), TEXT("[VoicePipeline] loopback assertions")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkVoiceChatPipeline_StartTransmitDisabledRejected,
    "Ck.VoiceChat.Pipeline.StartTransmit_DisabledMode_Rejected",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkVoiceChatPipeline_StartTransmitDisabledRejected::RunTest(const FString& Parameters)
{
    using namespace ck_voice_pipeline_spec;

    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    // Whitelist every matching line: one CK ensure can surface through multiple log paths.
    AddExpectedError(TEXT("whose transmit mode is Disabled"), EAutomationExpectedErrorFlags::Contains, -1);

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};
    const auto State = MakeShared<FPipelineState, ESPMode::ThreadSafe>();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(1, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(1, 30.0f));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([State](UWorld* InServer) -> void
        {
            EnableEngineVoice(*State);

            auto TransientEntity = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
            auto TalkerEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(TransientEntity);

            auto Params = FCk_Fragment_VoiceTalker_ParamsData{};
            Params.Set_TransmitMode(ECk_VoiceChat_TransmitMode::Disabled);

            State->Talker = UCk_Utils_VoiceTalker_UE::Add(TalkerEntity, Params);

            const auto FakeSource = MakeShared<FCk_VoiceChat_CaptureSource_Fake>(SampleRate);
            FakeSource->Enqueue_Sine(1.0f, 0.4f, 300.0f);

            UCk_Utils_VoiceTalker_UE::Debug_InjectCaptureSource(State->Talker, FakeSource);
            UCk_Utils_VoiceTalker_UE::Request_StartTransmit(State->Talker, {}, {});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(30));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, State]() -> bool
        {
            RestoreEngineVoice(*State);

            if (NOT TestTrue(TEXT("talker handle still valid"), ck::IsValid(State->Talker)))
            { return true; }

            TestFalse(TEXT("StartTransmit on a Disabled-mode talker rejects: not transmitting"),
                UCk_Utils_VoiceTalker_UE::Get_IsTransmitting(State->Talker));
            TestFalse(TEXT("no speaking state leaked from the rejected request"),
                UCk_Utils_VoiceTalker_UE::Get_IsSpeaking(State->Talker));
            TestTrue(TEXT("no PCM was decoded (the pipeline never started)"),
                UCk_Utils_VoiceTalker_UE::Debug_Get_LoopbackDecodedPcm(State->Talker).IsEmpty());

            return true;
        }), TEXT("[VoicePipeline] disabled-mode rejection assertions")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
