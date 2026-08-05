// Unit tests for CkVoiceChat's pure codec/policy surface (no UObjects, no world):
//   - Bundle wire pack/unpack round-trip, spec-default size bound (< 256 B split threshold),
//     malformed-input rejection, out-of-contract pack rejection
//   - Amplitude quantization round-trip + clamping
//   - VAD attack/release hysteresis
//   - Jitter buffer: warmup, reorder, gap concealment, late-drop, underrun re-warm,
//     adaptive target depth
//   - Pacing: staleness drops first, oldest-first FIFO under a byte budget

#include "Misc/AutomationTest.h"

#include "CkVoiceChat/Codec/CkVoiceChat_Codec.h"

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_voice_chat_codec
{
    constexpr auto kVoiceChatUnitTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::ProductFilter;

    // Deterministic pseudo-random frame bytes (LCG — tests must be reproducible).
    auto MakeFrame(int32 InNumBytes, uint32 InSeed) -> TArray<uint8>
    {
        auto Frame = TArray<uint8>{};
        Frame.SetNumUninitialized(InNumBytes);

        auto State = InSeed;
        for (auto Index = 0; Index < Frame.Num(); ++Index)
        {
            State = State * 1664525u + 1013904223u;
            Frame[Index] = static_cast<uint8>(State >> 24);
        }

        return Frame;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoiceChat_Wire_RoundTrip,
    "CkTests.UnitTests.CkVoiceChat.Wire.RoundTrip",
    ck_test_voice_chat_codec::kVoiceChatUnitTestFlags)

bool FCkTest_VoiceChat_Wire_RoundTrip::RunTest(const FString& Parameters)
{
    using namespace ck_test_voice_chat_codec;
    namespace codec = ck::voice_chat::codec;

    const auto Frames = TArray<TArray<uint8>>{MakeFrame(60, 1), MakeFrame(60, 2), MakeFrame(60, 3)};
    const auto Header = FCk_VoiceChat_BundleHeader{12345, 7, 200};

    const auto Packed = codec::Pack_Bundle(Header, Frames);

    TestEqual(TEXT("Spec-default bundle (3 x 60 B) packs to header + prefixed frames"),
        Packed.Num(), codec::BundleHeaderBytes + 3 * (codec::FrameSizePrefixBytes + 60));
    TestTrue(TEXT("Spec-default bundle stays under the 256 B server unreliable split threshold (amendment S3)"),
        Packed.Num() < 256);

    const auto Unpacked = codec::Unpack_Bundle(Packed);
    if (NOT TestTrue(TEXT("Round-trip unpacks"), Unpacked.IsSet()))
    { return true; }

    TestEqual(TEXT("Seq survives"), Unpacked->Get_Header().Get_Seq(), static_cast<uint16>(12345));
    TestEqual(TEXT("ChannelIdx survives"), Unpacked->Get_Header().Get_ChannelIdx(), static_cast<uint8>(7));
    TestEqual(TEXT("AmplitudeQ8 survives"), Unpacked->Get_Header().Get_AmplitudeQ8(), static_cast<uint8>(200));
    TestEqual(TEXT("Frame count survives"), Unpacked->Get_Frames().Num(), 3);
    TestTrue(TEXT("Frame contents survive byte-exact"), Unpacked->Get_Frames() == Frames);

    const auto EmptyBundle = codec::Pack_Bundle(FCk_VoiceChat_BundleHeader{1, 0, 0}, {});
    const auto EmptyUnpacked = codec::Unpack_Bundle(EmptyBundle);
    TestTrue(TEXT("Zero-frame bundle round-trips (header-only)"),
        EmptyUnpacked.IsSet() && EmptyUnpacked->Get_Frames().IsEmpty());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoiceChat_Wire_MalformedRejected,
    "CkTests.UnitTests.CkVoiceChat.Wire.MalformedRejected",
    ck_test_voice_chat_codec::kVoiceChatUnitTestFlags)

bool FCkTest_VoiceChat_Wire_MalformedRejected::RunTest(const FString& Parameters)
{
    using namespace ck_test_voice_chat_codec;
    namespace codec = ck::voice_chat::codec;

    const auto Valid = codec::Pack_Bundle(FCk_VoiceChat_BundleHeader{42, 1, 128}, {MakeFrame(60, 1), MakeFrame(60, 2)});

    TestFalse(TEXT("Empty buffer rejected"), codec::Unpack_Bundle({}).IsSet());

    auto TruncatedHeader = Valid;
    TruncatedHeader.SetNum(codec::BundleHeaderBytes - 1);
    TestFalse(TEXT("Truncated header rejected"), codec::Unpack_Bundle(TruncatedHeader).IsSet());

    auto TruncatedPrefix = Valid;
    TruncatedPrefix.SetNum(codec::BundleHeaderBytes + 1);
    TestFalse(TEXT("Truncated frame-size prefix rejected"), codec::Unpack_Bundle(TruncatedPrefix).IsSet());

    auto TruncatedBody = Valid;
    TruncatedBody.SetNum(Valid.Num() - 10);
    TestFalse(TEXT("Truncated frame body rejected"), codec::Unpack_Bundle(TruncatedBody).IsSet());

    auto TrailingGarbage = Valid;
    TrailingGarbage.Add(0xAB);
    TestFalse(TEXT("Trailing garbage rejected (strict consume)"), codec::Unpack_Bundle(TrailingGarbage).IsSet());

    auto ZeroSizeFrame = TArray<uint8>{};
    ZeroSizeFrame.Append({0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00}); // Seq=1, Ch=0, Amp=0, N=1, FrameSize=0
    TestFalse(TEXT("Zero-size frame on the wire rejected"), codec::Unpack_Bundle(ZeroSizeFrame).IsSet());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoiceChat_Wire_PackRejectsOutOfContract,
    "CkTests.UnitTests.CkVoiceChat.Wire.PackRejectsOutOfContract",
    ck_test_voice_chat_codec::kVoiceChatUnitTestFlags)

bool FCkTest_VoiceChat_Wire_PackRejectsOutOfContract::RunTest(const FString& Parameters)
{
    using namespace ck_test_voice_chat_codec;
    namespace codec = ck::voice_chat::codec;

    // Whitelist every matching line: one CK ensure can surface through multiple log paths.
    AddExpectedError(TEXT("Pack_Bundle rejected"), EAutomationExpectedErrorFlags::Contains, -1);

    const auto WithEmptyFrame = codec::Pack_Bundle(FCk_VoiceChat_BundleHeader{1, 0, 0}, {MakeFrame(60, 1), {}});
    TestTrue(TEXT("A bundle containing an empty frame packs to nothing"), WithEmptyFrame.IsEmpty());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoiceChat_Amplitude_QuantizeRoundTrip,
    "CkTests.UnitTests.CkVoiceChat.Amplitude.QuantizeRoundTrip",
    ck_test_voice_chat_codec::kVoiceChatUnitTestFlags)

bool FCkTest_VoiceChat_Amplitude_QuantizeRoundTrip::RunTest(const FString& Parameters)
{
    namespace codec = ck::voice_chat::codec;

    TestEqual(TEXT("Silence -> 0"), codec::Quantize_Amplitude(0.0f), static_cast<uint8>(0));
    TestEqual(TEXT("Full scale -> 255"), codec::Quantize_Amplitude(1.0f), static_cast<uint8>(255));
    TestEqual(TEXT("Below range clamps to 0"), codec::Quantize_Amplitude(-0.5f), static_cast<uint8>(0));
    TestEqual(TEXT("Above range clamps to 255"), codec::Quantize_Amplitude(2.0f), static_cast<uint8>(255));

    for (auto Quantized = 0; Quantized <= 255; Quantized += 5)
    {
        const auto RoundTripped = codec::Quantize_Amplitude(codec::Dequantize_Amplitude(static_cast<uint8>(Quantized)));
        TestEqual(TEXT("Dequantize -> Quantize is the identity on the u8 grid"),
            RoundTripped, static_cast<uint8>(Quantized));
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoiceChat_Vad_AttackRelease,
    "CkTests.UnitTests.CkVoiceChat.Vad.AttackRelease",
    ck_test_voice_chat_codec::kVoiceChatUnitTestFlags)

bool FCkTest_VoiceChat_Vad_AttackRelease::RunTest(const FString& Parameters)
{
    const auto Params = FCk_VoiceChat_VadParams{}
        .Set_Threshold(0.07f)
        .Set_Attack(FCk_Time{0.02})
        .Set_Release(FCk_Time{0.2});

    const auto Step = FCk_Time{0.01};
    auto Vad = FCk_VoiceChat_Vad{};

    TestFalse(TEXT("Starts closed"), Vad.Get_IsOpen());

    TestFalse(TEXT("One loud frame (10 ms < 20 ms attack) does not open"), Vad.Update(0.5f, Step, Params));
    TestTrue(TEXT("Sustained loud (20 ms) opens"), Vad.Update(0.5f, Step, Params));

    for (auto Frame = 0; Frame < 19; ++Frame)
    {
        Vad.Update(0.01f, Step, Params);
    }
    TestTrue(TEXT("A 190 ms dip (< 200 ms release) keeps the gate open"), Vad.Get_IsOpen());

    Vad.Update(0.5f, Step, Params);
    TestTrue(TEXT("Signal returning resets the release accumulator"), Vad.Get_IsOpen());

    for (auto Frame = 0; Frame < 19; ++Frame)
    {
        Vad.Update(0.01f, Step, Params);
    }
    TestTrue(TEXT("Still open at 190 ms of the NEW quiet stretch"), Vad.Get_IsOpen());
    TestFalse(TEXT("Quiet for the full 200 ms release closes"), Vad.Update(0.01f, Step, Params));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoiceChat_Jitter_ReorderConcealLateDrop,
    "CkTests.UnitTests.CkVoiceChat.Jitter.ReorderConcealLateDrop",
    ck_test_voice_chat_codec::kVoiceChatUnitTestFlags)

bool FCkTest_VoiceChat_Jitter_ReorderConcealLateDrop::RunTest(const FString& Parameters)
{
    using namespace ck_test_voice_chat_codec;

    const auto Params = FCk_VoiceChat_JitterParams{};   // 20 ms frames, 60 ms initial target = 3 frames
    auto Buffer = FCk_VoiceChat_JitterBuffer{};

    TestEqual(TEXT("Initial target depth = 60 ms / 20 ms = 3 frames"), Buffer.Get_TargetDepthFrames(Params), 3);
    TestEqual(TEXT("Pop before any push waits"),
        Buffer.Pop(Params).Get_Type(), ECk_VoiceChat_JitterPop::Wait);

    // steady arrivals exactly one frame apart -> jitter estimate stays 0, target stays 3
    auto Now = 0.0;
    const auto PushAt = [&](uint16 InSeq)
    {
        Buffer.Push(InSeq, MakeFrame(60, InSeq + 1), FCk_Time{Now}, Params);
        Now += 0.02;
    };

    PushAt(0);
    PushAt(2);   // out of order: 2 before 1
    TestEqual(TEXT("Below target depth: still warming up"),
        Buffer.Pop(Params).Get_Type(), ECk_VoiceChat_JitterPop::Wait);

    PushAt(1);

    const auto First = Buffer.Pop(Params);
    TestEqual(TEXT("Warmed up: first pop is a frame"), First.Get_Type(), ECk_VoiceChat_JitterPop::Frame);
    TestTrue(TEXT("Playout starts at seq 0 despite the reordered arrival"), First.Get_Frame() == MakeFrame(60, 1));
    TestTrue(TEXT("Seq 1 plays second"), Buffer.Pop(Params).Get_Frame() == MakeFrame(60, 2));
    TestTrue(TEXT("Seq 2 plays third"), Buffer.Pop(Params).Get_Frame() == MakeFrame(60, 3));

    TestEqual(TEXT("Drained: pop waits (and re-warms)"),
        Buffer.Pop(Params).Get_Type(), ECk_VoiceChat_JitterPop::Wait);

    PushAt(3);
    PushAt(5);   // 4 is lost
    PushAt(6);

    TestEqual(TEXT("Re-warmed at 3 buffered: seq 3 plays"),
        Buffer.Pop(Params).Get_Type(), ECk_VoiceChat_JitterPop::Frame);
    TestEqual(TEXT("Missing seq 4 conceals"),
        Buffer.Pop(Params).Get_Type(), ECk_VoiceChat_JitterPop::Conceal);
    TestEqual(TEXT("One concealment counted"), Buffer.Get_ConcealCount(), 1);
    TestTrue(TEXT("Seq 5 plays after the concealment"), Buffer.Pop(Params).Get_Frame() == MakeFrame(60, 6));

    Buffer.Push(2, MakeFrame(60, 99), FCk_Time{Now}, Params);
    TestEqual(TEXT("A frame older than the playout cursor is dropped, never stashed"),
        Buffer.Get_LateDropCount(), 1);
    TestEqual(TEXT("The late frame did not enter the buffer"), Buffer.Get_BufferedFrameCount(), 1);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoiceChat_Jitter_AdaptiveDepth,
    "CkTests.UnitTests.CkVoiceChat.Jitter.AdaptiveDepth",
    ck_test_voice_chat_codec::kVoiceChatUnitTestFlags)

bool FCkTest_VoiceChat_Jitter_AdaptiveDepth::RunTest(const FString& Parameters)
{
    using namespace ck_test_voice_chat_codec;

    const auto Params = FCk_VoiceChat_JitterParams{};
    auto Buffer = FCk_VoiceChat_JitterBuffer{};

    // bursty arrivals: pairs land together, then a 40 ms gap -> per-arrival deviation ~20 ms
    auto Now = 0.0;
    for (auto Seq = 0; Seq < 40; ++Seq)
    {
        Buffer.Push(static_cast<uint16>(Seq), MakeFrame(60, Seq + 1), FCk_Time{Now}, Params);
        Now += (Seq % 2 == 0) ? 0.0 : 0.04;
    }

    const auto AdaptedDepth = Buffer.Get_TargetDepthFrames(Params);
    TestTrue(TEXT("Bursty arrivals grow the target depth past the initial 3 frames"), AdaptedDepth >= 4);
    TestTrue(TEXT("Target depth respects the max (200 ms / 20 ms = 10 frames)"), AdaptedDepth <= 10);

    auto SteadyBuffer = FCk_VoiceChat_JitterBuffer{};
    Now = 0.0;
    for (auto Seq = 0; Seq < 40; ++Seq)
    {
        SteadyBuffer.Push(static_cast<uint16>(Seq), MakeFrame(60, Seq + 1), FCk_Time{Now}, Params);
        Now += 0.02;
    }
    // Near-zero measured jitter converges to the MinDepth floor (20 ms / 20 ms = 1 frame with
    // defaults) — MinDepth is the knob that owns the clean-network depth, not InitialTargetDepth.
    TestEqual(TEXT("Steady arrivals shrink the target depth to the MinDepth floor"),
        SteadyBuffer.Get_TargetDepthFrames(Params), 1);
    TestTrue(TEXT("Bursty arrivals hold a deeper target than steady ones"),
        AdaptedDepth > SteadyBuffer.Get_TargetDepthFrames(Params));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoiceChat_Jitter_SeqWrap,
    "CkTests.UnitTests.CkVoiceChat.Jitter.SeqWrap",
    ck_test_voice_chat_codec::kVoiceChatUnitTestFlags)

bool FCkTest_VoiceChat_Jitter_SeqWrap::RunTest(const FString& Parameters)
{
    using namespace ck_test_voice_chat_codec;

    const auto Params = FCk_VoiceChat_JitterParams{};
    auto Buffer = FCk_VoiceChat_JitterBuffer{};

    auto Now = 0.0;
    const auto PushAt = [&](uint16 InSeq)
    {
        Buffer.Push(InSeq, MakeFrame(60, InSeq), FCk_Time{Now}, Params);
        Now += 0.02;
    };

    PushAt(65534);
    PushAt(65535);
    PushAt(0);   // wraps

    TestTrue(TEXT("Playout crosses the wrap: 65534 first"), Buffer.Pop(Params).Get_Frame() == MakeFrame(60, 65534));
    TestTrue(TEXT("65535 second"), Buffer.Pop(Params).Get_Frame() == MakeFrame(60, 65535));
    TestTrue(TEXT("0 third"), Buffer.Pop(Params).Get_Frame() == MakeFrame(60, 0));

    PushAt(1);
    PushAt(2);
    PushAt(3);

    TestTrue(TEXT("Post-wrap seqs continue in order"), Buffer.Pop(Params).Get_Frame() == MakeFrame(60, 1));

    Buffer.Push(65535, MakeFrame(60, 99), FCk_Time{Now}, Params);
    TestEqual(TEXT("A pre-wrap seq arriving after the wrap is late-dropped (wrap-safe distance)"),
        Buffer.Get_LateDropCount(), 1);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoiceChat_Jitter_SpurtBoundaryDiscontinuity,
    "CkTests.UnitTests.CkVoiceChat.Jitter.SpurtBoundaryDiscontinuity",
    ck_test_voice_chat_codec::kVoiceChatUnitTestFlags)

bool FCkTest_VoiceChat_Jitter_SpurtBoundaryDiscontinuity::RunTest(const FString& Parameters)
{
    using namespace ck_test_voice_chat_codec;

    const auto Params = FCk_VoiceChat_JitterParams{};
    auto Buffer = FCk_VoiceChat_JitterBuffer{};

    auto Now = 0.0;
    const auto PushAt = [&](uint16 InSeq)
    {
        Buffer.Push(InSeq, MakeFrame(60, InSeq), FCk_Time{Now}, Params);
        Now += 0.02;
    };

    PushAt(0);
    PushAt(1);
    PushAt(2);
    Buffer.Pop(Params);
    Buffer.Pop(Params);
    Buffer.Pop(Params);

    const auto DepthBeforeGap = Buffer.Get_TargetDepthFrames(Params);

    // VAD-gated silence between talk spurts: 1 s of nothing, then the next spurt
    Now += 1.0;
    PushAt(30);

    TestEqual(TEXT("The spurt boundary is a discontinuity, not jitter"), Buffer.Get_DiscontinuityCount(), 1);
    TestEqual(TEXT("The 1 s silence did not inflate the depth estimate"),
        Buffer.Get_TargetDepthFrames(Params), DepthBeforeGap);

    PushAt(31);
    PushAt(32);

    const auto First = Buffer.Pop(Params);
    TestEqual(TEXT("The new spurt re-warms and plays from its own first seq"),
        First.Get_Type(), ECk_VoiceChat_JitterPop::Frame);
    TestTrue(TEXT("No conceal-walk across the spurt boundary"), Buffer.Get_ConcealCount() == 0);
    TestTrue(TEXT("Playout resumed at seq 30"), First.Get_Frame() == MakeFrame(60, 30));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoiceChat_Jitter_FarAheadJumpReseeds,
    "CkTests.UnitTests.CkVoiceChat.Jitter.FarAheadJumpReseeds",
    ck_test_voice_chat_codec::kVoiceChatUnitTestFlags)

bool FCkTest_VoiceChat_Jitter_FarAheadJumpReseeds::RunTest(const FString& Parameters)
{
    using namespace ck_test_voice_chat_codec;

    // MinDepth raised to 3 frames so the post-reseed re-warm is observable (at the default
    // 1-frame floor a single arrival completes warmup immediately)
    const auto Params = FCk_VoiceChat_JitterParams{}.Set_MinDepth(FCk_Time{0.06});
    auto Buffer = FCk_VoiceChat_JitterBuffer{};

    auto Now = 0.0;
    const auto PushAt = [&](uint16 InSeq)
    {
        Buffer.Push(InSeq, MakeFrame(60, InSeq), FCk_Time{Now}, Params);
        Now += 0.02;
    };

    PushAt(0);
    PushAt(1);
    PushAt(2);
    Buffer.Pop(Params);   // cursor at 1, frames {1, 2} still buffered

    PushAt(100);   // distance 99 > 50, arrival time steady

    TestEqual(TEXT("A far-ahead seq jump reseeds instead of conceal-walking"),
        Buffer.Get_DiscontinuityCount(), 1);
    TestEqual(TEXT("Stale pre-jump frames were discarded"), Buffer.Get_BufferedFrameCount(), 1);
    TestEqual(TEXT("Playout re-warms after the reseed"),
        Buffer.Pop(Params).Get_Type(), ECk_VoiceChat_JitterPop::Wait);
    TestEqual(TEXT("No concealment was spent crossing the jump"), Buffer.Get_ConcealCount(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoiceChat_Jitter_WarmupBackwardExtend,
    "CkTests.UnitTests.CkVoiceChat.Jitter.WarmupBackwardExtend",
    ck_test_voice_chat_codec::kVoiceChatUnitTestFlags)

bool FCkTest_VoiceChat_Jitter_WarmupBackwardExtend::RunTest(const FString& Parameters)
{
    using namespace ck_test_voice_chat_codec;

    const auto Params = FCk_VoiceChat_JitterParams{};
    auto Buffer = FCk_VoiceChat_JitterBuffer{};

    auto Now = 0.0;
    const auto PushAt = [&](uint16 InSeq)
    {
        Buffer.Push(InSeq, MakeFrame(60, InSeq), FCk_Time{Now}, Params);
        Now += 0.02;
    };

    // reordered-high first packet: seq 2 lands before 0 and 1
    PushAt(2);
    PushAt(0);
    PushAt(1);

    TestEqual(TEXT("Arrivals behind the cursor during warmup are kept, not late-dropped"),
        Buffer.Get_LateDropCount(), 0);
    TestTrue(TEXT("The utterance onset plays from seq 0"), Buffer.Pop(Params).Get_Frame() == MakeFrame(60, 0));
    TestTrue(TEXT("Then seq 1"), Buffer.Pop(Params).Get_Frame() == MakeFrame(60, 1));
    TestTrue(TEXT("Then seq 2"), Buffer.Pop(Params).Get_Frame() == MakeFrame(60, 2));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_VoiceChat_Pacing_BudgetAndStaleness,
    "CkTests.UnitTests.CkVoiceChat.Pacing.BudgetAndStaleness",
    ck_test_voice_chat_codec::kVoiceChatUnitTestFlags)

bool FCkTest_VoiceChat_Pacing_BudgetAndStaleness::RunTest(const FString& Parameters)
{
    namespace codec = ck::voice_chat::codec;

    const auto Queue = TArray<FCk_VoiceChat_PacingEntry>{
        FCk_VoiceChat_PacingEntry{1, 200, FCk_Time{0.30}},   // stale (max age 0.2)
        FCk_VoiceChat_PacingEntry{2, 200, FCk_Time{0.15}},   // oldest fresh
        FCk_VoiceChat_PacingEntry{3, 200, FCk_Time{0.10}},
        FCk_VoiceChat_PacingEntry{4, 200, FCk_Time{0.05}},   // does not fit the 500 B budget
        FCk_VoiceChat_PacingEntry{5, 999, FCk_Time{0.50}},   // stale too
    };

    const auto Result = codec::Select_BundlesToSend(Queue, 500, FCk_Time{0.2});

    TestEqual(TEXT("Both stale entries dropped for freshness"), Result.Get_StaleDropIds().Num(), 2);
    TestTrue(TEXT("Stale ids are 1 and 5"),
        Result.Get_StaleDropIds().Contains(1) && Result.Get_StaleDropIds().Contains(5));

    TestEqual(TEXT("Budget admits exactly the two oldest fresh entries"), Result.Get_SendIds().Num(), 2);
    TestEqual(TEXT("Oldest fresh sends first"), Result.Get_SendIds()[0], 2);
    TestEqual(TEXT("Next oldest sends second"), Result.Get_SendIds()[1], 3);
    TestEqual(TEXT("Selected bytes accounted"), Result.Get_BytesSelected(), 400);

    const auto DrainAll = codec::Select_BundlesToSend(Queue, 100000, FCk_Time{10.0});
    TestEqual(TEXT("A generous budget with no staleness sends everything"), DrainAll.Get_SendIds().Num(), 5);
    TestTrue(TEXT("Nothing dropped when nothing is stale"), DrainAll.Get_StaleDropIds().IsEmpty());

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
