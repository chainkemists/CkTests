// Behavior-math gate for CkParticles BehaviorId 17 (LightningRange) — the Vefects NS_Lightning_Range
// range-ring recreation.
//
// This drives UCkParticles_DataInterface::Execute_Stage_CPU, the SAME CPU mirror a CPU sim runs, so it
// needs no Niagara system, no template asset, no RHI and no forked engine. That matters: every other
// CkParticles gate is an existence check (the asset loads, a component spawned, the pins are connected),
// and an existence check passes just as happily against a behavior that outputs nothing.
//
// Expected values are the SOURCE's own curve keys as transcribed in
// CkFoundation/Source/CkParticles/Cookbook/NS_Lightning_Range.md §5 — not values read back out of the
// implementation. Assertions land inside flat segments or on continuous key boundaries, so float wobble
// in NormalizedAge cannot flip a branch and turn the gate into a coin toss.
//
// Cannot pass vacuously: the pre-switch default size is ~8-24 units, so asserting 700 proves the switch
// actually reached case 17.

#include "Misc/AutomationTest.h"

#include "CkParticles/DataInterface/CkParticles_DataInterface.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

// Named (not anonymous) namespace: unity build fuses anonymous namespaces across concatenated TUs and two
// same-named constants collide. See CkUnitTest_Common.h for the incident this rule came from.
namespace ck_test_particles_lightning_range
{
    constexpr auto kBehaviorId = 17;

    // The PS_CkParticles_Template_Single cadence row's particle lifetime (Get_TemplateSpecs()); the source's
    // InitializeParticle.Lifetime. Age is expressed as a fraction of it so the curve keys read verbatim.
    constexpr auto kLifetime  = 1.1f;
    constexpr auto kTolerance = 1.0e-3f;

    // Source curve keys (recipe §5). Duplicated here on purpose — the test's job is to hold the behavior to
    // the SOURCE, so reading these out of the behavior's own header would make the gate tautological.
    constexpr auto kColorSplit = 0.0630213f;
    constexpr auto kAlphaT0    = 0.206364f;
    constexpr auto kAlphaT1    = 0.693235f;
    constexpr auto kAlphaT2    = 0.95397f;

    auto Evaluate(float InNormalizedAge, int32 InSeed) -> FCk_Particles_StageResult
    {
        constexpr auto DeltaTime = 1.0f / 60.0f;

        return UCkParticles_DataInterface::Execute_Stage_CPU(
            kBehaviorId,
            DeltaTime,
            InNormalizedAge * kLifetime,
            kLifetime,
            FVector3f::ZeroVector,
            FVector3f::ZeroVector,
            InSeed);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Particles_LightningRangeBehavior,
    "CkTests.UnitTests.CkParticles.LightningRangeBehavior",
    kCkUnitTestFlags)

bool FCkTest_Particles_LightningRangeBehavior::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_lightning_range;

    constexpr auto Seed = 12345;

    // ---- Size: uniform 700 for the whole life. Also the proof the switch reached case 17 ----
    for (const auto T : { 0.0f, 0.25f, 0.5f, 0.75f, 1.0f })
    {
        const auto Out = Evaluate(T, Seed);
        TestEqual(*FString::Printf(TEXT("size.x is the source's Uniform Sprite Size 700 at T=%.2f"), T),
            Out.Size.X, 700.0f, kTolerance);
        TestEqual(*FString::Printf(TEXT("size.y is the source's Uniform Sprite Size 700 at T=%.2f"), T),
            Out.Size.Y, 700.0f, kTolerance);
    }

    // ---- Renderer contract: VisTag 4 (custom-facing sprite) with a NON-DEGENERATE alignment/facing pair ----
    // A zero vector here does not fail visibly — Niagara's CustomAlignment silently falls back to Unaligned
    // and the quad collapses — which is exactly why it is asserted rather than eyeballed.
    {
        const auto Out = Evaluate(0.5f, Seed);
        TestEqual(TEXT("VisTag is 4 (custom-facing sprite renderer)"), Out.VisTag, 4);

        TestTrue(TEXT("SpriteAlignment is non-degenerate"), Out.SpriteAlignment.SizeSquared() > kTolerance);
        TestTrue(TEXT("SpriteFacing is non-degenerate"),    Out.SpriteFacing.SizeSquared()    > kTolerance);

        TestTrue(TEXT("SpriteAlignment matches the source Sprite Alignment Vector (0,1,0)"),
            Out.SpriteAlignment.Equals(FVector3f(0.0f, 1.0f, 0.0f), kTolerance));
        TestTrue(TEXT("SpriteFacing matches the source Sprite Facing Vector (0,0,1)"),
            Out.SpriteFacing.Equals(FVector3f(0.0f, 0.0f, 1.0f), kTolerance));
    }

    // ---- Colour: warm white at spawn, snapping to saturated blue within the first ~1/16 of the life ----
    {
        const auto AtSpawn = Evaluate(0.0f, Seed);
        TestEqual(TEXT("colour R at T=0 is the source key 1.0"),      AtSpawn.Color.R, 1.0f,      kTolerance);
        TestEqual(TEXT("colour G at T=0 is the source key 0.89627"),  AtSpawn.Color.G, 0.89627f,  kTolerance);
        TestEqual(TEXT("colour B at T=0 is the source key 0.520996"), AtSpawn.Color.B, 0.520996f, kTolerance);

        const auto AtSnap = Evaluate(kColorSplit, Seed);
        TestEqual(TEXT("colour R at the snap key is 0.266356"), AtSnap.Color.R, 0.266356f, kTolerance);
        TestEqual(TEXT("colour G at the snap key is 0.102242"), AtSnap.Color.G, 0.102242f, kTolerance);
        TestEqual(TEXT("colour B at the snap key is 1.0"),      AtSnap.Color.B, 1.0f,      kTolerance);

        // …and HELD from there to death — the source's post-snap keys are constant.
        for (const auto T : { 0.2f, 0.6f, 1.0f })
        {
            const auto Held = Evaluate(T, Seed);
            TestEqual(*FString::Printf(TEXT("colour R held at 0.266356 at T=%.2f"), T), Held.Color.R, 0.266356f, kTolerance);
            TestEqual(*FString::Printf(TEXT("colour G held at 0.102242 at T=%.2f"), T), Held.Color.G, 0.102242f, kTolerance);
            TestEqual(*FString::Printf(TEXT("colour B held at 1.0 at T=%.2f"), T),      Held.Color.B, 1.0f,      kTolerance);
        }

        // The snap is FAST, not a slow crossfade: by 1/16 of the life the blue channel has already arrived.
        const auto EarlyBlue = Evaluate(1.0f / 16.0f, Seed).Color.B;
        TestTrue(TEXT("blue has arrived within the first 1/16 of the life"), EarlyBlue > 0.99f);
    }

    // ---- Alpha: three source keys, flat then a late SWELL (not a fade) ----
    {
        TestEqual(TEXT("alpha at T=0 is the source key 0.15"),    Evaluate(0.0f,     Seed).Color.A, 0.15f, kTolerance);
        TestEqual(TEXT("alpha is still 0.15 mid-flat-segment"),   Evaluate(0.1f,     Seed).Color.A, 0.15f, kTolerance);
        TestEqual(TEXT("alpha at the first key is 0.15"),         Evaluate(kAlphaT0, Seed).Color.A, 0.15f, kTolerance);
        TestEqual(TEXT("alpha at the second key is 0.2"),         Evaluate(kAlphaT1, Seed).Color.A, 0.2f,  kTolerance);
        TestEqual(TEXT("alpha at the third key is 1.0"),          Evaluate(kAlphaT2, Seed).Color.A, 1.0f,  kTolerance);
        TestEqual(TEXT("alpha is held at 1.0 to death"),          Evaluate(1.0f,     Seed).Color.A, 1.0f,  kTolerance);

        // The direction of the late move is the whole visual read: it swells to full, it does not fade out.
        const auto Mid  = Evaluate(kAlphaT1, Seed).Color.A;
        const auto Late = Evaluate(kAlphaT2, Seed).Color.A;
        TestTrue(TEXT("the late alpha move is a SWELL, not a fade"), Late > Mid);

        // Never decreasing anywhere — a dip would read as a flicker the source does not have.
        auto Previous = -1.0f;
        for (auto Step = 0; Step <= 40; ++Step)
        {
            const auto Alpha = Evaluate(static_cast<float>(Step) / 40.0f, Seed).Color.A;
            TestTrue(*FString::Printf(TEXT("alpha never decreases (step %d)"), Step), Alpha >= Previous - kTolerance);
            Previous = Alpha;
        }
    }

    // ---- Dynamic material parameters, in the SOURCE material's own channel order ----
    {
        const auto AtSpawn = Evaluate(0.0f, Seed);
        TestEqual(TEXT("dissolve (x) starts at the source key -1"), AtSpawn.Dynamic.X, -1.0f, kTolerance);

        const auto AtRampEnd = Evaluate(0.4f, Seed);
        TestEqual(TEXT("dissolve (x) reaches the source key 0.2 at 40% of life"), AtRampEnd.Dynamic.X, 0.2f, kTolerance);

        const auto AtDeath = Evaluate(1.0f, Seed);
        TestEqual(TEXT("dissolve (x) is held at 0.2 after the ramp"), AtDeath.Dynamic.X, 0.2f, kTolerance);

        // Erosion only ever progresses — the ramp runs -1 -> 0.2 and never reverses.
        auto Previous = -2.0f;
        for (auto Step = 0; Step <= 40; ++Step)
        {
            const auto Dissolve = Evaluate(static_cast<float>(Step) / 40.0f, Seed).Dynamic.X;
            TestTrue(*FString::Printf(TEXT("dissolve never reverses (step %d)"), Step), Dissolve >= Previous - kTolerance);
            Previous = Dissolve;
        }

        // The inert channels. distortion/offset are 0 because this INSTANCE resolves them off; core_color is
        // -0.5, which saturate() clamps to 0, i.e. the core-colour branch never engages.
        for (const auto T : { 0.0f, 0.5f, 1.0f })
        {
            const auto Out = Evaluate(T, Seed);
            TestEqual(*FString::Printf(TEXT("distortion (y) is inert at T=%.2f"), T),  Out.Dynamic.Y,  0.0f, kTolerance);
            TestEqual(*FString::Printf(TEXT("offset (z) is inert at T=%.2f"), T),      Out.Dynamic.Z,  0.0f, kTolerance);
            TestEqual(*FString::Printf(TEXT("core_color (w) is -0.5 at T=%.2f"), T),   Out.Dynamic.W, -0.5f, kTolerance);
        }
    }

    // ---- The ring never moves and never spins: local space, zero offset, identity orientation ----
    for (const auto T : { 0.0f, 0.5f, 1.0f })
    {
        const auto Out = Evaluate(T, Seed);
        TestTrue(*FString::Printf(TEXT("position stays at the spawn transform at T=%.2f"), T),
            Out.Position.IsNearlyZero(kTolerance));
        TestTrue(*FString::Printf(TEXT("velocity is zero at T=%.2f"), T),
            Out.Velocity.IsNearlyZero(kTolerance));
        TestEqual(*FString::Printf(TEXT("sprite rotation is zero at T=%.2f"), T), Out.Rotation, 0.0f, kTolerance);
        TestTrue(*FString::Printf(TEXT("orientation is identity at T=%.2f"), T),
            Out.Orientation.Equals(FQuat4f::Identity, kTolerance));
    }

    // ---- Seed-independence: the source spawns exactly one particle with no randomness ----
    {
        const auto Reference = Evaluate(0.37f, 0);
        for (const auto OtherSeed : { 1, 7, 4242, -19, 987654321 })
        {
            const auto Other = Evaluate(0.37f, OtherSeed);

            TestEqual(*FString::Printf(TEXT("colour is Seed-independent (seed %d)"), OtherSeed),
                Other.Color, Reference.Color);
            TestEqual(*FString::Printf(TEXT("size is Seed-independent (seed %d)"), OtherSeed),
                Other.Size.X, Reference.Size.X, kTolerance);
            TestEqual(*FString::Printf(TEXT("dissolve is Seed-independent (seed %d)"), OtherSeed),
                Other.Dynamic.X, Reference.Dynamic.X, kTolerance);
            TestEqual(*FString::Printf(TEXT("VisTag is Seed-independent (seed %d)"), OtherSeed),
                Other.VisTag, Reference.VisTag);
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
