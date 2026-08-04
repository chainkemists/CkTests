// Per-part tuning gate for CkParticles — the layer-level tuning block the DI hands the stage per system instance.
//
// Three claims:
//   1. The row APPLICATION is exactly the documented transform, field by field: size, stretch, mesh scale, speed,
//      tint, alpha, per-axis dynamic, rotation offset, the visibility window's hard hide, and the position offset.
//   2. An IDENTITY block is a bit-identical passthrough. That is the load-bearing one: a missing entry must render
//      byte-for-byte as the untuned effect does today, and "byte-for-byte" is asserted exactly rather than
//      toleranced, because a tuning layer that perturbs an untuned system by a little is a regression nobody sees
//      until it has shipped.
//   3. The DataAsset CONVERSION packs the designer's row into exactly those float4s — global tint folded into the
//      row tint, tint alpha ignored — and a row on a VisTag the behavior no longer declares reaches no part at all.
//
// This drives ck::particles::Apply_PartTuningRows / Apply_PartTuning — the CPU mirror of CkParticles_ApplyPartTuning
// (/CkParticles/Common.ush) that the DI's template wrapper runs on the GPU — plus Execute_Stage_CPU for the
// passthrough claim. No Niagara, no template asset, no RHI, no forked engine.
//
// Expected values are computed by hand from the layout comment on FCkParticles_PartTuningBlock, not read back out
// of the implementation.

#include "Misc/AutomationTest.h"

#include "CkParticles/DataInterface/CkParticles_DataInterface.h"
#include "CkParticles/DataInterface/CkParticles_PartTuning.h"
#include "CkParticles/ScriptDefinition/CkParticles_ScriptDefinition_Naming.h"
#include "CkParticles/ScriptDefinition/CkParticles_TuningDefinition.h"

#include "CkCore/Macros/CkMacros.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

// Named (not anonymous) namespace: unity build fuses anonymous namespaces across concatenated TUs and two
// same-named constants collide. See CkUnitTest_Common.h for the incident this rule came from.
namespace ck_test_particles_part_tuning
{
    constexpr auto kTolerance = 1.0e-5f;

    // A synthetic stage result with a distinct, non-default value in every field the transform touches, so a
    // mis-wired row lands somewhere visible rather than on a value that happened to match.
    auto Make_Result(int32 InVisTag) -> FCk_Particles_StageResult
    {
        auto Result = FCk_Particles_StageResult{};

        Result.Position = FVector3f(10.0f, 20.0f, 30.0f);
        Result.Velocity = FVector3f(1.0f, 2.0f, 3.0f);
        Result.Color    = FLinearColor(0.5f, 0.4f, 0.25f, 0.8f);
        Result.Size     = FVector2f(7.0f, 11.0f);
        Result.Scale    = FVector3f(2.0f, 3.0f, 4.0f);
        Result.Dynamic  = FVector4f(0.1f, 0.2f, 0.3f, 0.4f);
        Result.Rotation = 15.0f;
        Result.VisTag   = InVisTag;

        return Result;
    }

    // Powers of two and exact binary fractions throughout, so every expected product below is representable and the
    // assertions test the transform rather than float rounding.
    const auto kR0 = FVector4f( 2.0f,  4.0f,  8.0f,  0.5f); // SizeMul, StretchMul, MeshScaleMul, SpeedMul
    const auto kR1 = FVector4f( 0.5f,  0.25f, 4.0f,  0.125f); // TintRGB, AlphaMul
    const auto kR2 = FVector4f( 2.0f,  4.0f,  8.0f, 16.0f); // per-axis Dynamic
    const auto kR3 = FVector4f(90.0f,  0.25f, 0.75f, 0.0f); // RotationOffsetDeg, WindowStart, WindowEnd
    const auto kR4 = FVector4f(100.0f, -50.0f, 25.0f, 0.0f); // PosOffsetXYZ

    // Ages/lifetimes/seeds the passthrough claim is sampled at. Both lifetimes matter: 0 takes
    // CkParticles_NormalizedAgeOf's unset-lifetime branch, which is the one a window could mis-handle.
    const float kAges[]      = { 0.0f, 0.13f, 0.5f, 0.87f, 1.0f };
    const float kLifetimes[] = { 0.0f, 0.5f, 1.1f, 2.0f };
    const int32 kSeeds[]     = { 0, 1, 7, 12345, 99991 };

    auto Is_IdentityPart(const FCkParticles_PartTuningBlock& InBlock, int32 InPart) -> bool
    {
        const auto Ones = FVector4f(1.0f, 1.0f, 1.0f, 1.0f);

        return InBlock.Get_Row(InPart, 0) == Ones
            && InBlock.Get_Row(InPart, 1) == Ones
            && InBlock.Get_Row(InPart, 2) == Ones
            && InBlock.Get_Row(InPart, 3) == FVector4f(0.0f, 0.0f, 1.0f, 0.0f)
            && InBlock.Get_Row(InPart, 4) == FVector4f(0.0f, 0.0f, 0.0f, 0.0f);
    }

    auto Is_Identical(const FCk_Particles_StageResult& InA, const FCk_Particles_StageResult& InB) -> bool
    {
        return InA.Position == InB.Position
            && InA.Velocity == InB.Velocity
            && InA.Color    == InB.Color
            && InA.Size     == InB.Size
            && InA.Scale    == InB.Scale
            && InA.Orientation.X == InB.Orientation.X
            && InA.Orientation.Y == InB.Orientation.Y
            && InA.Orientation.Z == InB.Orientation.Z
            && InA.Orientation.W == InB.Orientation.W
            && InA.Dynamic       == InB.Dynamic
            && InA.Rotation      == InB.Rotation
            && InA.MeshIndex     == InB.MeshIndex
            && InA.VisTag        == InB.VisTag
            && InA.SpriteAlignment == InB.SpriteAlignment
            && InA.SpriteFacing    == InB.SpriteFacing
            && InA.SubImageIndex   == InB.SubImageIndex;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Particles_PartTuningRows,
    "CkTests.UnitTests.CkParticles.PartTuningRows",
    kCkUnitTestFlags)

bool FCkTest_Particles_PartTuningRows::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_part_tuning;

    // ---- Every field, inside the visibility window ----
    {
        constexpr auto NormalizedAge = 0.5f;

        auto Result = Make_Result(0);
        ck::particles::Apply_PartTuningRows(Result, NormalizedAge, kR0, kR1, kR2, kR3, kR4);

        // Size.x takes SizeMul alone; Size.y takes SizeMul AND StretchMul — 11 * 2 * 4.
        TestEqual(TEXT("size.x scales by SizeMul"),                Result.Size.X, 14.0f, kTolerance);
        TestEqual(TEXT("size.y scales by SizeMul then StretchMul"), Result.Size.Y, 88.0f, kTolerance);

        TestEqual(TEXT("scale.x scales by MeshScaleMul"), Result.Scale.X, 16.0f, kTolerance);
        TestEqual(TEXT("scale.y scales by MeshScaleMul"), Result.Scale.Y, 24.0f, kTolerance);
        TestEqual(TEXT("scale.z scales by MeshScaleMul"), Result.Scale.Z, 32.0f, kTolerance);

        TestEqual(TEXT("velocity.x scales by SpeedMul"), Result.Velocity.X, 0.5f, kTolerance);
        TestEqual(TEXT("velocity.y scales by SpeedMul"), Result.Velocity.Y, 1.0f, kTolerance);
        TestEqual(TEXT("velocity.z scales by SpeedMul"), Result.Velocity.Z, 1.5f, kTolerance);

        TestEqual(TEXT("color.r scales by TintR"), Result.Color.R, 0.25f,   kTolerance);
        TestEqual(TEXT("color.g scales by TintG"), Result.Color.G, 0.1f,    kTolerance);
        TestEqual(TEXT("color.b scales by TintB"), Result.Color.B, 1.0f,    kTolerance);
        TestEqual(TEXT("color.a scales by AlphaMul"), Result.Color.A, 0.1f, kTolerance);

        TestEqual(TEXT("dynamic.x scales per axis"), Result.Dynamic.X, 0.2f, kTolerance);
        TestEqual(TEXT("dynamic.y scales per axis"), Result.Dynamic.Y, 0.8f, kTolerance);
        TestEqual(TEXT("dynamic.z scales per axis"), Result.Dynamic.Z, 2.4f, kTolerance);
        TestEqual(TEXT("dynamic.w scales per axis"), Result.Dynamic.W, 6.4f, kTolerance);

        TestEqual(TEXT("rotation takes the offset in degrees"), Result.Rotation, 105.0f, kTolerance);

        TestEqual(TEXT("position.x takes the offset"), Result.Position.X, 110.0f, kTolerance);
        TestEqual(TEXT("position.y takes the offset"), Result.Position.Y, -30.0f, kTolerance);
        TestEqual(TEXT("position.z takes the offset"), Result.Position.Z,  55.0f, kTolerance);
    }

    // ---- Visibility window: a HARD hide outside [start, end], and only of the three hiding fields ----
    for (const auto NormalizedAge : { 0.0f, 0.24f, 0.76f, 1.0f })
    {
        auto Result = Make_Result(0);
        ck::particles::Apply_PartTuningRows(Result, NormalizedAge, kR0, kR1, kR2, kR3, kR4);

        TestEqual(*FString::Printf(TEXT("alpha is hidden outside the window at nAge=%.2f"), NormalizedAge),
            Result.Color.A, 0.0f, kTolerance);
        TestEqual(*FString::Printf(TEXT("size is hidden outside the window at nAge=%.2f"), NormalizedAge),
            Result.Size.X + Result.Size.Y, 0.0f, kTolerance);
        TestEqual(*FString::Printf(TEXT("scale is hidden outside the window at nAge=%.2f"), NormalizedAge),
            Result.Scale.X + Result.Scale.Y + Result.Scale.Z, 0.0f, kTolerance);

        // The hide is not a bail-out: everything the row already applied still stands.
        TestEqual(*FString::Printf(TEXT("position offset survives the hide at nAge=%.2f"), NormalizedAge),
            Result.Position.X, 110.0f, kTolerance);
        TestEqual(*FString::Printf(TEXT("rotation offset survives the hide at nAge=%.2f"), NormalizedAge),
            Result.Rotation, 105.0f, kTolerance);
    }

    // The window bounds are INCLUSIVE — the comparison is strict on both sides, so a layer authored to run for
    // exactly [0.25, 0.75] is visible at both of its own keys.
    for (const auto NormalizedAge : { 0.25f, 0.75f })
    {
        auto Result = Make_Result(0);
        ck::particles::Apply_PartTuningRows(Result, NormalizedAge, kR0, kR1, kR2, kR3, kR4);

        TestEqual(*FString::Printf(TEXT("the window bound itself is visible at nAge=%.2f"), NormalizedAge),
            Result.Color.A, 0.1f, kTolerance);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Particles_PartTuningAddressing,
    "CkTests.UnitTests.CkParticles.PartTuningAddressing",
    kCkUnitTestFlags)

bool FCkTest_Particles_PartTuningAddressing::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_part_tuning;

    constexpr auto BandStart      = 10;
    const auto     FirstBandRow   = ck::particles::SharedRendererVisTag_Max + 1;

    // ---- Row addressing: the shared set maps onto itself, a band's first part onto the first row above it ----
    TestEqual(TEXT("shared VisTag 0 reads row 0"), ck::particles::Get_PartTuningRowIndex(0, BandStart), 0);
    TestEqual(TEXT("shared VisTag 4 reads row 4"),
        ck::particles::Get_PartTuningRowIndex(ck::particles::SharedRendererVisTag_Max, BandStart),
        ck::particles::SharedRendererVisTag_Max);
    TestEqual(TEXT("the band's first VisTag reads the first row above the shared set"),
        ck::particles::Get_PartTuningRowIndex(BandStart, BandStart), FirstBandRow);
    TestEqual(TEXT("the band's second VisTag reads the next row"),
        ck::particles::Get_PartTuningRowIndex(BandStart + 1, BandStart), FirstBandRow + 1);

    // A tag outside the budget is SKIPPED, not wrapped or clamped — clamping would retune an unrelated layer.
    TestEqual(TEXT("a VisTag past the budget has no row"),
        ck::particles::Get_PartTuningRowIndex(BandStart + ck::particles::MaxTunedParts, BandStart), INDEX_NONE);
    TestEqual(TEXT("a VisTag far below its own band has no row"),
        ck::particles::Get_PartTuningRowIndex(FirstBandRow, BandStart + ck::particles::MaxTunedParts), INDEX_NONE);

    // The interval BETWEEN the shared set and the band belongs to no part of this behavior. It is the dangerous
    // case, not merely an absent one: running the band arithmetic backwards from here lands on rows 0..4, so a tag
    // the behavior never draws would retune a SHARED layer that every template carries.
    for (auto VisTag = ck::particles::SharedRendererVisTag_Max + 1; VisTag < BandStart; ++VisTag)
    {
        TestEqual(*FString::Printf(TEXT("VisTag %d, between the shared set and the band, has no row"), VisTag),
            ck::particles::Get_PartTuningRowIndex(VisTag, BandStart), INDEX_NONE);
    }

    // ---- A block tuned at the band's first part reaches a particle carrying that band's first VisTag ----
    {
        auto Block = FCkParticles_PartTuningBlock{};
        Block.BandStart = BandStart;
        Block.Set_Row(FirstBandRow, 0, kR0);
        Block.Set_Row(FirstBandRow, 1, kR1);
        Block.Set_Row(FirstBandRow, 2, kR2);
        Block.Set_Row(FirstBandRow, 3, kR3);
        Block.Set_Row(FirstBandRow, 4, kR4);

        auto Tuned = Make_Result(BandStart);
        ck::particles::Apply_PartTuning(Tuned, 0.5f, Block);

        TestEqual(TEXT("the banded VisTag picked up its own part's SizeMul"), Tuned.Size.X, 14.0f, kTolerance);
        TestEqual(TEXT("the banded VisTag picked up its own part's position offset"),
            Tuned.Position.X, 110.0f, kTolerance);

        // Every OTHER tag on the same block is still at the identity, which is what makes per-part tuning per-part.
        auto Neighbour = Make_Result(BandStart + 1);
        ck::particles::Apply_PartTuning(Neighbour, 0.5f, Block);
        TestTrue(TEXT("the next VisTag in the band is untouched by the tuned part"),
            Is_Identical(Neighbour, Make_Result(BandStart + 1)));

        auto Shared = Make_Result(2);
        ck::particles::Apply_PartTuning(Shared, 0.5f, Block);
        TestTrue(TEXT("a shared VisTag is untouched by a tuned band part"),
            Is_Identical(Shared, Make_Result(2)));

        auto OutOfRange = Make_Result(BandStart + ck::particles::MaxTunedParts);
        ck::particles::Apply_PartTuning(OutOfRange, 0.5f, Block);
        TestTrue(TEXT("a VisTag past the budget is left entirely untuned"),
            Is_Identical(OutOfRange, Make_Result(BandStart + ck::particles::MaxTunedParts)));
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Particles_PartTuningIdentityPassthrough,
    "CkTests.UnitTests.CkParticles.PartTuningIdentityPassthrough",
    kCkUnitTestFlags)

bool FCkTest_Particles_PartTuningIdentityPassthrough::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_part_tuning;

    // The default-constructed block IS the identity. Asserting that here rather than trusting the constructor is
    // the difference between "renders as today" and "renders black and invisible": a zero-filled block would hide
    // every particle on every system that never asked to be tuned.
    const auto Identity = FCkParticles_PartTuningBlock{};

    for (auto Part = 0; Part < ck::particles::MaxTunedParts; ++Part)
    {
        const auto Ones = FVector4f(1.0f, 1.0f, 1.0f, 1.0f);

        TestTrue(*FString::Printf(TEXT("part %d row 0 is the identity"), Part),
            Identity.Get_Row(Part, 0) == Ones);
        TestTrue(*FString::Printf(TEXT("part %d row 1 is the identity"), Part),
            Identity.Get_Row(Part, 1) == Ones);
        TestTrue(*FString::Printf(TEXT("part %d row 2 is the identity"), Part),
            Identity.Get_Row(Part, 2) == Ones);
        TestTrue(*FString::Printf(TEXT("part %d row 3 opens the full visibility window"), Part),
            Identity.Get_Row(Part, 3) == FVector4f(0.0f, 0.0f, 1.0f, 0.0f));
        TestTrue(*FString::Printf(TEXT("part %d row 4 offsets nothing"), Part),
            Identity.Get_Row(Part, 4) == FVector4f(0.0f, 0.0f, 0.0f, 0.0f));
    }

    // ---- The whole roster, through the real stage: an identity block changes NOTHING, bit for bit ----
    constexpr auto DeltaTime  = 1.0f / 60.0f;
    constexpr auto EmitterAge = 0.0f;

    auto Mismatches = 0;

    for (auto BehaviorId = 0; BehaviorId < ck::particles::NumBehaviors; ++BehaviorId)
    {
        for (const auto Lifetime : kLifetimes)
        {
            for (const auto NormalizedAge : kAges)
            {
                for (const auto Seed : kSeeds)
                {
                    const auto Age = NormalizedAge * (Lifetime > 0.0f ? Lifetime : 1.0f);

                    const auto Untuned = UCkParticles_DataInterface::Execute_Stage_CPU(
                        BehaviorId, DeltaTime, Age, Lifetime,
                        FVector3f::ZeroVector, FVector3f::ZeroVector, Seed, EmitterAge);

                    const auto Tuned = UCkParticles_DataInterface::Execute_Stage_CPU(
                        BehaviorId, DeltaTime, Age, Lifetime,
                        FVector3f::ZeroVector, FVector3f::ZeroVector, Seed, EmitterAge,
                        FVector4f(1.0f, 1.0f, 1.0f, 1.0f), &Identity);

                    if (NOT Is_Identical(Untuned, Tuned))
                    {
                        ++Mismatches;

                        if (Mismatches == 1)
                        {
                            AddError(FString::Printf(
                                TEXT("an identity part-tuning block changed behavior %d at age %.3f / lifetime %.3f / seed %d"),
                                BehaviorId, Age, Lifetime, Seed));
                        }
                    }
                }
            }
        }
    }

    TestEqual(TEXT("an identity block is a bit-identical passthrough across the whole roster"), Mismatches, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Particles_PartTuningAssetConversion,
    "CkTests.UnitTests.CkParticles.PartTuningAssetConversion",
    kCkUnitTestFlags)

bool FCkTest_Particles_PartTuningAssetConversion::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_part_tuning;

    // The stale-row claim below drives a diagnostic Warning on purpose; it is the point of that half of the test.
    bSuppressLogWarnings = true;

    // The first behavior on the roster that declares a band — roster-driven, so this test cannot be pinned to a
    // behavior whose renderers later move. Addressing has its own test; what is asserted here is the PACKING, so
    // the part index comes from the same resolver the conversion uses rather than being restated.
    auto BehaviorId = static_cast<int32>(INDEX_NONE);
    for (auto Candidate = 0; Candidate < ck::particles::NumBehaviors; ++Candidate)
    {
        if (ck::particles::Get_BehaviorBandStart(Candidate) == 0)
        { continue; }

        BehaviorId = Candidate;
        break;
    }

    TestTrue(TEXT("the roster declares at least one banded behavior to convert against"), BehaviorId != INDEX_NONE);
    if (BehaviorId == INDEX_NONE)
    { return false; }

    const auto BandStart = ck::particles::Get_BehaviorBandStart(BehaviorId);
    const auto Parts     = ck::particles::Get_BehaviorTunableParts(BehaviorId);

    // The LAST part, so the tuned row sits at neither end of the block and a fencepost lands somewhere visible.
    const auto TunedVisTag = Parts.Last().VisTag;
    const auto TunedPart   = ck::particles::Get_PartTuningRowIndex(TunedVisTag, BandStart);

    TestTrue(TEXT("the behavior's last part addresses a row inside the block"), TunedPart != INDEX_NONE);

    // A VisTag no behavior on the roster can reach, so the row is unambiguously stale rather than merely unusual.
    constexpr auto StaleVisTag = 100000;

    auto* Tuning = NewObject<UCkParticles_TuningDefinition>();

    // Powers of two and exact binary fractions, so every expected product is representable.
    auto Row = FCkParticles_PartTuning_AssetRow{};
    Row._PartName              = Parts.Last().DisplayName;
    Row._VisTag                = TunedVisTag;
    Row._SizeMultiplier        = 2.0f;
    Row._StretchMultiplier     = 4.0f;
    Row._MeshScaleMultiplier   = 8.0f;
    Row._SpeedMultiplier       = 0.5f;
    // The tint's ALPHA is deliberately 0: it must not reach the block, or a colour picked in the wheel would hide
    // the layer. Fading is _AlphaMultiplier's job and nothing else's.
    Row._Tint                  = FLinearColor(0.5f, 0.25f, 0.125f, 0.0f);
    Row._AlphaMultiplier       = 0.125f;
    Row._DissolveMultiplier    = 2.0f;
    Row._DistortionMultiplier  = 4.0f;
    Row._UvPanMultiplier       = 8.0f;
    Row._EmissiveMultiplier    = 16.0f;
    Row._RotationOffsetDegrees = 90.0f;
    Row._WindowStart           = 0.25f;
    Row._WindowEnd             = 0.75f;
    Row._PositionOffset        = FVector(100.0, -50.0, 25.0);

    auto StaleRow = FCkParticles_PartTuning_AssetRow{};
    StaleRow._PartName = FName(TEXT("A part this behavior no longer draws"));
    StaleRow._VisTag   = StaleVisTag;

    Tuning->_Parts.Add(Row);
    Tuning->_Parts.Add(StaleRow);
    Tuning->_GlobalTint = FLinearColor(0.5f, 2.0f, 4.0f, 0.0f);

    const auto Block = Tuning->Get_AsPartTuningBlock(BehaviorId);

    TestEqual(TEXT("the block carries the behavior's own band start"), Block.BandStart, BandStart);

    TestTrue(TEXT("R0 packs size, stretch, mesh scale and speed"),
        Block.Get_Row(TunedPart, 0) == FVector4f(2.0f, 4.0f, 8.0f, 0.5f));

    // R1's rgb is the row's tint FOLDED with the asset's global tint — the global has no slot of its own in the
    // User.CkTuning float4, so this is the only place it can land. R1.w is the row's alpha, untouched by either.
    TestTrue(TEXT("R1 packs the row tint folded with the global tint, and the row's alpha"),
        Block.Get_Row(TunedPart, 1) == FVector4f(0.25f, 0.5f, 0.5f, 0.125f));

    TestTrue(TEXT("R2 packs dissolve, distortion, UV pan and emissive onto the per-axis Dynamic"),
        Block.Get_Row(TunedPart, 2) == FVector4f(2.0f, 4.0f, 8.0f, 16.0f));

    TestTrue(TEXT("R3 packs the rotation offset and the visibility window"),
        Block.Get_Row(TunedPart, 3) == FVector4f(90.0f, 0.25f, 0.75f, 0.0f));

    TestTrue(TEXT("R4 packs the position offset"),
        Block.Get_Row(TunedPart, 4) == FVector4f(100.0f, -50.0f, 25.0f, 0.0f));

    // The stale row is SKIPPED, not folded onto some other part: every part but the tuned one is still the identity,
    // which is the claim that keeps a not-yet-reconciled asset from retuning a layer nobody addressed.
    auto NumPerturbed = 0;
    for (auto Part = 0; Part < ck::particles::MaxTunedParts; ++Part)
    {
        if (Part == TunedPart || Is_IdentityPart(Block, Part))
        { continue; }

        ++NumPerturbed;

        if (NumPerturbed == 1)
        {
            AddError(FString::Printf(
                TEXT("part %d is not the identity, so a row this behavior does not declare reached it"), Part));
        }
    }

    TestEqual(TEXT("a row on a VisTag the behavior does not declare reaches no part at all"), NumPerturbed, 0);

    return true;
}
