// Encode/decode micro-benchmark through the engine Voice module's Opus factories — the P1 gate
// deliverable that lets the spec's game-thread-encode cost claim exist as a MEASURED number
// (non-negotiable #7). Results land in the log under [VoiceBench]; assertions cover only the
// factory contract (objects exist, frames encode/decode at the expected sizes), never timings.

#include "Misc/AutomationTest.h"

#include "Misc/ConfigCacheIni.h"
#include "Modules/ModuleManager.h"

#include "VoiceModule.h"
#include "Interfaces/VoiceCodec.h"
#include "Net/VoiceConfig.h"

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_voice_chat_opus_benchmark
{
    constexpr auto SampleRate = 48000;
    constexpr auto NumChannels = 1;
    constexpr auto BitrateBps = 24000;
    constexpr auto SamplesPerFrame = 960;                       // 20 ms at 48 kHz
    constexpr auto BytesPerFrame = SamplesPerFrame * 2;         // 16-bit PCM
    constexpr auto WarmupFrames = 10;
    constexpr auto TimedFrames = 500;

    // FVoiceDecoderOpus refuses to decode a frame unless the OUTPUT buffer has capacity for
    // MAX_OPUS_FRAMES (= 6) whole frames (VoiceCodecOpus.cpp:20 + the UncompressedBufferAvail
    // gate in Decode) — a 1-frame buffer silently yields size 0. P2's synth decode target must
    // honor the same capacity floor.
    constexpr auto DecodeCapacityBytes = 6 * BytesPerFrame;

    // 300 Hz sine at 0.3 full scale — a stable, voiced-band signal every frame.
    auto MakeSineFrame(int32 InFrameIdx) -> TArray<uint8>
    {
        auto Frame = TArray<uint8>{};
        Frame.SetNumUninitialized(BytesPerFrame);

        auto* Samples = reinterpret_cast<int16*>(Frame.GetData());
        for (auto SampleIdx = 0; SampleIdx < SamplesPerFrame; ++SampleIdx)
        {
            const auto GlobalSample = InFrameIdx * SamplesPerFrame + SampleIdx;
            const auto Phase = 2.0 * PI * 300.0 * GlobalSample / SampleRate;
            Samples[SampleIdx] = static_cast<int16>(0.3 * 32767.0 * FMath::Sin(Phase));
        }

        return Frame;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoiceChat_OpusMicroBenchmark,
    "CkTests.UnitTests.CkVoiceChat.Codec.OpusMicroBenchmark",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCkTest_VoiceChat_OpusMicroBenchmark::RunTest(const FString& Parameters)
{
    using namespace ck_test_voice_chat_opus_benchmark;

    // Voice-module init warnings (no capture device on a headless lane) are expected noise here.
    bSuppressLogWarnings = true;

    // FVoiceModule reads [Voice] bEnabled from GEngineIni ONCE at StartupModule and its factories
    // return null when disabled. Enable it in the config cache before the module loads; if
    // something loaded it disabled earlier in this session, reload it so StartupModule re-reads
    // the flag. The original config state is captured and RESTORED below (not blindly removed) so
    // this keeps working once the host project ships its own [Voice] bEnabled key.
    auto OriginalEnabled = false;
    const auto HadOriginalKey = GConfig->GetBool(TEXT("Voice"), TEXT("bEnabled"), OriginalEnabled, GEngineIni);

    const auto RestoreVoiceConfig = [HadOriginalKey, OriginalEnabled]() -> void
    {
        if (HadOriginalKey)
        { GConfig->SetBool(TEXT("Voice"), TEXT("bEnabled"), OriginalEnabled, GEngineIni); }
        else
        { GConfig->RemoveKey(TEXT("Voice"), TEXT("bEnabled"), GEngineIni); }
    };

    const auto VoiceWasLoaded = FModuleManager::Get().IsModuleLoaded(TEXT("Voice"));
    GConfig->SetBool(TEXT("Voice"), TEXT("bEnabled"), true, GEngineIni);

    if (VoiceWasLoaded && NOT FVoiceModule::Get().IsVoiceEnabled())
    {
        FModuleManager::Get().UnloadModule(TEXT("Voice"));
    }

    if (NOT TestTrue(TEXT("the Voice module reports enabled after the config-cache override"),
        FVoiceModule::Get().IsVoiceEnabled()))
    {
        RestoreVoiceConfig();
        return true;
    }

    const auto Encoder = FVoiceModule::Get().CreateVoiceEncoder(SampleRate, NumChannels, EAudioEncodeHint::VoiceEncode_Voice);
    const auto Decoder = FVoiceModule::Get().CreateVoiceDecoder(SampleRate, NumChannels);

    RestoreVoiceConfig();

    if (NOT TestTrue(TEXT("engine Voice factory produced an encoder"), Encoder.IsValid()) ||
        NOT TestTrue(TEXT("engine Voice factory produced a decoder"), Decoder.IsValid()))
    { return true; }

    Encoder->SetBitrate(BitrateBps);

    const auto TotalFrames = WarmupFrames + TimedFrames;
    auto PcmFrames = TArray<TArray<uint8>>{};
    PcmFrames.Reserve(TotalFrames);
    for (auto FrameIdx = 0; FrameIdx < TotalFrames; ++FrameIdx)
    {
        PcmFrames.Add(MakeSineFrame(FrameIdx));
    }

    auto EncodedFrames = TArray<TArray<uint8>>{};
    EncodedFrames.SetNum(TotalFrames);

    auto EncodeSeconds = 0.0;
    auto TotalEncodedBytes = 0;
    auto UnencodedRemainderCount = 0;

    for (auto FrameIdx = 0; FrameIdx < TotalFrames; ++FrameIdx)
    {
        auto Compressed = TArray<uint8>{};
        Compressed.SetNumUninitialized(2048);
        auto CompressedSize = static_cast<uint32>(Compressed.Num());

        const auto StartSeconds = FPlatformTime::Seconds();
        const auto UnencodedRemainder = Encoder->Encode(PcmFrames[FrameIdx].GetData(), BytesPerFrame, Compressed.GetData(), CompressedSize);
        const auto ElapsedSeconds = FPlatformTime::Seconds() - StartSeconds;

        if (UnencodedRemainder != 0)
        { ++UnencodedRemainderCount; }

        Compressed.SetNum(static_cast<int32>(CompressedSize));
        EncodedFrames[FrameIdx] = MoveTemp(Compressed);

        if (FrameIdx >= WarmupFrames)
        {
            EncodeSeconds += ElapsedSeconds;
            TotalEncodedBytes += EncodedFrames[FrameIdx].Num();
        }
    }

    auto DecodeSeconds = 0.0;
    auto FullFramesDecoded = 0;
    auto FirstDecodedSizes = FString{};

    for (auto FrameIdx = 0; FrameIdx < TotalFrames; ++FrameIdx)
    {
        auto Decoded = TArray<uint8>{};
        Decoded.SetNumUninitialized(DecodeCapacityBytes);
        auto DecodedSize = static_cast<uint32>(Decoded.Num());

        const auto StartSeconds = FPlatformTime::Seconds();
        Decoder->Decode(EncodedFrames[FrameIdx].GetData(), EncodedFrames[FrameIdx].Num(), Decoded.GetData(), DecodedSize);
        const auto ElapsedSeconds = FPlatformTime::Seconds() - StartSeconds;

        if (static_cast<int32>(DecodedSize) == BytesPerFrame)
        { ++FullFramesDecoded; }

        if (FrameIdx < 3)
        { FirstDecodedSizes += FString::Printf(TEXT("%u "), DecodedSize); }

        if (FrameIdx >= WarmupFrames)
        { DecodeSeconds += ElapsedSeconds; }
    }

    // Aggregate contract asserts: the engine codec may prime on the first packet(s) (its wire is
    // [NumFrames][Generation] + opus data, and a priming packet can carry zero frames), so the
    // yardstick is "essentially every frame round-trips", not frame 0 specifically.
    TestEqual(TEXT("every encode call consumed its whole 20 ms input"), UnencodedRemainderCount, 0);
    TestTrue(TEXT("at least the timed-frame count decoded to full 20 ms PCM"), FullFramesDecoded >= TimedFrames);

    const auto EncodeMicrosecondsPerFrame = EncodeSeconds * 1e6 / TimedFrames;
    const auto DecodeMicrosecondsPerFrame = DecodeSeconds * 1e6 / TimedFrames;
    const auto AverageEncodedBytes = static_cast<float>(TotalEncodedBytes) / TimedFrames;

    UE_LOG(LogTemp, Display,
        TEXT("[VoiceBench] Opus 48 kHz mono @ %d bps, 20 ms frames, %d timed frames: encode %.1f us/frame, decode %.1f us/frame, avg encoded %.1f B/frame (first decoded sizes: %s)"),
        BitrateBps, TimedFrames, EncodeMicrosecondsPerFrame, DecodeMicrosecondsPerFrame, AverageEncodedBytes, *FirstDecodedSizes);

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
