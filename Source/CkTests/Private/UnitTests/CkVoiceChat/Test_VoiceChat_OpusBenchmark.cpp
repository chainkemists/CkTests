// Encode/decode micro-benchmark through the engine Voice module's Opus factories — the P1 gate
// deliverable that lets the spec's game-thread-encode cost claim exist as a MEASURED number
// (non-negotiable #7). Results land in the log under [VoiceBench]; assertions cover only the
// factory contract (objects exist, frames encode/decode at the expected sizes), never timings.

#include "Misc/AutomationTest.h"

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

    const auto Encoder = FVoiceModule::Get().CreateVoiceEncoder(SampleRate, NumChannels, EAudioEncodeHint::VoiceEncode_Voice);
    const auto Decoder = FVoiceModule::Get().CreateVoiceDecoder(SampleRate, NumChannels);

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

    for (auto FrameIdx = 0; FrameIdx < TotalFrames; ++FrameIdx)
    {
        auto Compressed = TArray<uint8>{};
        Compressed.SetNumUninitialized(2048);
        auto CompressedSize = static_cast<uint32>(Compressed.Num());

        const auto StartSeconds = FPlatformTime::Seconds();
        const auto UnencodedRemainder = Encoder->Encode(PcmFrames[FrameIdx].GetData(), BytesPerFrame, Compressed.GetData(), CompressedSize);
        const auto ElapsedSeconds = FPlatformTime::Seconds() - StartSeconds;

        if (FrameIdx == 0)
        {
            TestEqual(TEXT("a whole 20 ms frame encodes with no unencoded remainder"), UnencodedRemainder, 0);
            TestTrue(TEXT("the encoded frame is non-empty"), CompressedSize > 0);
        }

        Compressed.SetNum(static_cast<int32>(CompressedSize));
        EncodedFrames[FrameIdx] = MoveTemp(Compressed);

        if (FrameIdx >= WarmupFrames)
        {
            EncodeSeconds += ElapsedSeconds;
            TotalEncodedBytes += EncodedFrames[FrameIdx].Num();
        }
    }

    auto DecodeSeconds = 0.0;
    auto FirstDecodedSize = 0u;

    for (auto FrameIdx = 0; FrameIdx < TotalFrames; ++FrameIdx)
    {
        auto Decoded = TArray<uint8>{};
        Decoded.SetNumUninitialized(BytesPerFrame);
        auto DecodedSize = static_cast<uint32>(Decoded.Num());

        const auto StartSeconds = FPlatformTime::Seconds();
        Decoder->Decode(EncodedFrames[FrameIdx].GetData(), EncodedFrames[FrameIdx].Num(), Decoded.GetData(), DecodedSize);
        const auto ElapsedSeconds = FPlatformTime::Seconds() - StartSeconds;

        if (FrameIdx == 0)
        { FirstDecodedSize = DecodedSize; }

        if (FrameIdx >= WarmupFrames)
        { DecodeSeconds += ElapsedSeconds; }
    }

    TestEqual(TEXT("a decoded frame is a whole 20 ms of 16-bit PCM"),
        static_cast<int32>(FirstDecodedSize), BytesPerFrame);

    const auto EncodeMicrosecondsPerFrame = EncodeSeconds * 1e6 / TimedFrames;
    const auto DecodeMicrosecondsPerFrame = DecodeSeconds * 1e6 / TimedFrames;
    const auto AverageEncodedBytes = static_cast<float>(TotalEncodedBytes) / TimedFrames;

    UE_LOG(LogTemp, Display,
        TEXT("[VoiceBench] Opus 48 kHz mono @ %d bps, 20 ms frames, %d timed frames: encode %.1f us/frame, decode %.1f us/frame, avg encoded %.1f B/frame"),
        BitrateBps, TimedFrames, EncodeMicrosecondsPerFrame, DecodeMicrosecondsPerFrame, AverageEncodedBytes);

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
