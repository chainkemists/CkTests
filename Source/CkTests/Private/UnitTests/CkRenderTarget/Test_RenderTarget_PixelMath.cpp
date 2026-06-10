// Unit tests for CkRenderTarget's pure pixel-math surface (no UObjects, no world):
//   - Block diff/patch round-trip, zero-diff, odd (non-multiple-of-block) sizes
//   - Delta wire serialization round-trip + malformed-input rejection
//   - Chunker round-trip
//   - Oodle compression round-trip

#include "Misc/AutomationTest.h"

#include "CkRenderTarget/Pixels/CkRenderTarget_PixelMath.h"

// --------------------------------------------------------------------------------------------------------------------

namespace
{
    constexpr auto kRenderTargetUnitTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::ProductFilter;

    // Deterministic pseudo-random RGBA8 image (no FMath::Rand — tests must be reproducible).
    auto MakeImage(const FIntPoint& InSize, uint32 InSeed) -> TArray<uint8>
    {
        auto Image = TArray<uint8>{};
        Image.SetNumUninitialized(InSize.X * InSize.Y * ck::render_target::pixel::BytesPerPixel);

        auto State = InSeed;
        for (auto Index = 0; Index < Image.Num(); ++Index)
        {
            State = State * 1664525u + 1013904223u;
            Image[Index] = static_cast<uint8>(State >> 24);
        }

        return Image;
    }

    auto SetPixel(TArray<uint8>& InOutImage, const FIntPoint& InSize, int32 InX, int32 InY, uint8 InValue) -> void
    {
        const auto Offset = (InY * InSize.X + InX) * ck::render_target::pixel::BytesPerPixel;
        for (auto Channel = 0; Channel < ck::render_target::pixel::BytesPerPixel; ++Channel)
        {
            InOutImage[Offset + Channel] = InValue;
        }
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_RenderTarget_BlockDiff_RoundTrip,
    "CkTests.UnitTests.CkRenderTarget.BlockDiff.RoundTrip",
    kRenderTargetUnitTestFlags)

bool FCkTest_RenderTarget_BlockDiff_RoundTrip::RunTest(const FString& Parameters)
{
    const auto Size = FIntPoint{64, 48};
    constexpr auto BlockSize = 16;

    const auto Previous = MakeImage(Size, 1);
    auto Current = Previous;
    SetPixel(Current, Size, 5, 5, 250);     // block (0,0)
    SetPixel(Current, Size, 40, 20, 17);    // block (2,1)
    SetPixel(Current, Size, 63, 47, 99);    // block (3,2) — bottom-right corner

    const auto Deltas = ck::render_target::pixel::Diff_Blocks(Current, Previous, Size, BlockSize);
    TestEqual(TEXT("Three touched pixels in three distinct blocks -> three deltas"), Deltas.Num(), 3);

    auto Patched = Previous;
    ck::render_target::pixel::Patch_Blocks(Patched, Size, Deltas, BlockSize);
    TestTrue(TEXT("Patching the previous image with the diff reproduces the current image"), Patched == Current);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_RenderTarget_BlockDiff_NoChange_EmitsNothing,
    "CkTests.UnitTests.CkRenderTarget.BlockDiff.NoChange_EmitsNothing",
    kRenderTargetUnitTestFlags)

bool FCkTest_RenderTarget_BlockDiff_NoChange_EmitsNothing::RunTest(const FString& Parameters)
{
    const auto Size = FIntPoint{32, 32};
    const auto Image = MakeImage(Size, 2);

    const auto Deltas = ck::render_target::pixel::Diff_Blocks(Image, Image, Size, 16);
    TestEqual(TEXT("Identical images diff to zero deltas"), Deltas.Num(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_RenderTarget_BlockDiff_OddSizes,
    "CkTests.UnitTests.CkRenderTarget.BlockDiff.OddSizes",
    kRenderTargetUnitTestFlags)

bool FCkTest_RenderTarget_BlockDiff_OddSizes::RunTest(const FString& Parameters)
{
    // 33x17 at block 16 -> 3x2 block grid with 1-wide and 1-tall edge blocks.
    const auto Size = FIntPoint{33, 17};
    constexpr auto BlockSize = 16;

    const auto BlockCounts = ck::render_target::pixel::Get_BlockCounts(Size, BlockSize);
    TestEqual(TEXT("33 wide at block 16 -> 3 block columns"), BlockCounts.X, 3);
    TestEqual(TEXT("17 tall at block 16 -> 2 block rows"),    BlockCounts.Y, 2);

    const auto Previous = MakeImage(Size, 3);
    auto Current = Previous;
    SetPixel(Current, Size, 32, 16, 200);   // bottom-right corner — the 1x1 edge block (2,1)
    SetPixel(Current, Size, 0, 16, 201);    // bottom edge block (0,1) — 16x1
    SetPixel(Current, Size, 32, 0, 202);    // right edge block (2,0) — 1x16

    const auto Deltas = ck::render_target::pixel::Diff_Blocks(Current, Previous, Size, BlockSize);
    TestEqual(TEXT("Three touched edge blocks -> three deltas"), Deltas.Num(), 3);

    auto Patched = Previous;
    ck::render_target::pixel::Patch_Blocks(Patched, Size, Deltas, BlockSize);
    TestTrue(TEXT("Odd-size patch round-trip reproduces the current image"), Patched == Current);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_RenderTarget_DeltaSerialization_RoundTrip,
    "CkTests.UnitTests.CkRenderTarget.DeltaSerialization.RoundTrip",
    kRenderTargetUnitTestFlags)

bool FCkTest_RenderTarget_DeltaSerialization_RoundTrip::RunTest(const FString& Parameters)
{
    const auto Size = FIntPoint{48, 48};
    constexpr auto BlockSize = 16;

    const auto Previous = MakeImage(Size, 4);
    auto Current = Previous;
    SetPixel(Current, Size, 1, 1, 11);
    SetPixel(Current, Size, 30, 30, 22);

    const auto Deltas = ck::render_target::pixel::Diff_Blocks(Current, Previous, Size, BlockSize);
    const auto Buffer = ck::render_target::pixel::Serialize_Deltas(Deltas);
    const auto Restored = ck::render_target::pixel::Deserialize_Deltas(Buffer);

    if (NOT TestTrue(TEXT("Deserialize succeeds on a serialized buffer"), Restored.IsSet()))
    { return true; }

    auto Patched = Previous;
    ck::render_target::pixel::Patch_Blocks(Patched, Size, *Restored, BlockSize);
    TestTrue(TEXT("Serialize -> deserialize -> patch reproduces the current image"), Patched == Current);

    // Truncated input must be rejected, not crash or partially apply.
    auto Truncated = Buffer;
    Truncated.SetNum(Buffer.Num() / 2);
    TestFalse(TEXT("Truncated delta buffer is rejected"),
        ck::render_target::pixel::Deserialize_Deltas(Truncated).IsSet());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_RenderTarget_Chunker_ReassemblyRoundTrip,
    "CkTests.UnitTests.CkRenderTarget.Chunker.ReassemblyRoundTrip",
    kRenderTargetUnitTestFlags)

bool FCkTest_RenderTarget_Chunker_ReassemblyRoundTrip::RunTest(const FString& Parameters)
{
    const auto Payload = MakeImage(FIntPoint{10, 10}, 5);   // 400 bytes

    const auto Chunks = ck::render_target::pixel::Chunk_Payload(Payload, 96);
    TestEqual(TEXT("400 bytes at 96-byte chunks -> 5 chunks"), Chunks.Num(), 5);
    TestEqual(TEXT("Last chunk carries the remainder"), Chunks.Last().Num(), 400 - 4 * 96);

    const auto Reassembled = ck::render_target::pixel::Reassemble_Chunks(Chunks);
    TestTrue(TEXT("Reassembly is the exact inverse of chunking"), Reassembled == Payload);

    TestEqual(TEXT("Empty payload yields no chunks"),
        ck::render_target::pixel::Chunk_Payload(TArray<uint8>{}, 96).Num(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_RenderTarget_Compression_RoundTrip,
    "CkTests.UnitTests.CkRenderTarget.Compression.RoundTrip",
    kRenderTargetUnitTestFlags)

bool FCkTest_RenderTarget_Compression_RoundTrip::RunTest(const FString& Parameters)
{
    // Flat-color content (whiteboard-like) must round-trip AND compress well.
    auto Raw = TArray<uint8>{};
    Raw.SetNumZeroed(64 * 64 * ck::render_target::pixel::BytesPerPixel);

    const auto Compressed = ck::render_target::pixel::Compress(Raw);
    TestTrue(TEXT("Compression produced a payload"), Compressed.Num() > 0);
    TestTrue(TEXT("Flat content compresses below raw size"), Compressed.Num() < Raw.Num());

    const auto Decompressed = ck::render_target::pixel::Decompress(Compressed, Raw.Num());
    if (NOT TestTrue(TEXT("Decompression succeeds"), Decompressed.IsSet()))
    { return true; }

    TestTrue(TEXT("Compression round-trip is lossless"), *Decompressed == Raw);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
