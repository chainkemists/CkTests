// Behavior-math gate for CkParticles BehaviorId 7 (Slash) — the Vefects NS_BasicAttack recreation.
//
// This drives UCkParticles_DataInterface::Execute_Stage_CPU, the SAME CPU mirror a CPU sim runs, so it needs
// no Niagara system, no template asset, no RHI and no forked engine. That matters: every other CkParticles
// gate is an existence check, and an existence check passes just as happily against a behavior that outputs
// nothing.
//
// Expected values are the SOURCE's own curve keys as transcribed in
// CkFoundation/Source/CkParticles/Cookbook/NS_BasicAttack.md §2/§5 — not values read back out of the
// implementation. Assertions land inside flat segments or on continuous key boundaries, so float wobble in
// the age fraction cannot flip a branch and turn the gate into a coin toss.
//
// Cannot pass vacuously: behavior 7's VisTags are 5..9 and the pre-switch default is 0, so every layer
// assertion here proves the switch actually reached case 7.

#include "Misc/AutomationTest.h"

#include "CkParticles/DataInterface/CkParticles_DataInterface.h"
#include "CkParticles/ScriptDefinition/CkParticles_ScriptDefinition_Naming.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

// Named (not anonymous) namespace: unity build fuses anonymous namespaces across concatenated TUs and two
// same-named constants collide.
namespace ck_test_particles_slash
{
    constexpr auto kBehaviorId = 7;

    // The PS_CkParticles_Template_Slash cadence row's particle lifetime — longer than every layer's own life.
    constexpr auto kTemplateLifetime = 0.5f;
    constexpr auto kTolerance        = 1.0e-3f;

    // Source facts (recipe §2/§5), duplicated here on purpose: the test's job is to hold the behavior to the
    // SOURCE, so reading these out of the behavior's own header would make the gate tautological.
    constexpr auto kNumLayers  = 19;
    constexpr auto kLifeSlash  = 0.3f;
    constexpr auto kLifeWind   = 0.5f;
    constexpr auto kSparkDelay = 0.06f;

    constexpr auto kSparkRingRadius   = 209.769f;
    constexpr auto kSparkRingAngleDeg = -6.5f;

    constexpr auto kVisTagSlash01 = 5;
    constexpr auto kVisTagSlash02 = 6;
    constexpr auto kVisTagSlash03 = 7;
    constexpr auto kVisTagWind    = 8;
    constexpr auto kVisTagSpark   = 9;

    // A seed whose layer is InLayer. Seeds are Particles.UniqueID and the partition is Seed % 19, so any
    // representative of the residue class works; the sparks additionally vary per representative.
    auto Get_SeedForLayer(int32 InLayer, int32 InRepeat) -> int32
    {
        return InLayer + kNumLayers * InRepeat;
    }

    auto Evaluate(float InAge, int32 InSeed) -> FCk_Particles_StageResult
    {
        constexpr auto DeltaTime = 1.0f / 60.0f;

        return UCkParticles_DataInterface::Execute_Stage_CPU(
            kBehaviorId, DeltaTime, InAge, kTemplateLifetime,
            FVector3f::ZeroVector, FVector3f::ZeroVector, InSeed);
    }

    // Layer age fraction -> absolute age, which is what the behavior actually reads.
    auto EvaluateAtLayerT(int32 InLayer, float InT, int32 InRepeat) -> FCk_Particles_StageResult
    {
        const auto Life = InLayer == 3 ? kLifeWind : kLifeSlash;
        return Evaluate(InT * Life, Get_SeedForLayer(InLayer, InRepeat));
    }

    auto Is_Hidden(const FCk_Particles_StageResult& InOut) -> bool
    {
        return InOut.Color.A == 0.0f && InOut.Color.R == 0.0f && InOut.Color.G == 0.0f && InOut.Color.B == 0.0f
            && InOut.Size.IsNearlyZero() && InOut.Scale.IsNearlyZero();
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Particles_SlashBehavior,
    "CkTests.UnitTests.CkParticles.SlashBehavior",
    kCkUnitTestFlags)

bool FCkTest_Particles_SlashBehavior::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_slash;

    // ---- The 19-slot partition: every burst draws exactly one particle per source emitter particle ----
    // A drifted modulo would silently collapse two source emitters onto one layer, which reads as a missing
    // slash rather than as an error.
    {
        auto SeenVisTags = TSet<int32>{};
        for (auto Layer = 0; Layer < kNumLayers; ++Layer)
        {
            const auto Life = Layer == 3 ? kLifeWind : kLifeSlash;
            const auto Out  = Evaluate(Layer < 4 ? Life * 0.5f : kSparkDelay + 0.05f, Get_SeedForLayer(Layer, 0));
            SeenVisTags.Add(Out.VisTag);
        }

        TestTrue(TEXT("the 19 layers cover all five source renderers"),
            SeenVisTags.Contains(kVisTagSlash01) && SeenVisTags.Contains(kVisTagSlash02) &&
            SeenVisTags.Contains(kVisTagSlash03) && SeenVisTags.Contains(kVisTagWind) &&
            SeenVisTags.Contains(kVisTagSpark));
        TestEqual(TEXT("the 19 layers use exactly the five source renderers and nothing else"),
            SeenVisTags.Num(), 5);

        // The partition is by residue, so seed + 19 lands on the same layer no matter which burst it came from.
        for (auto Layer = 0; Layer < kNumLayers; ++Layer)
        {
            const auto Age = Layer < 4 ? 0.1f : kSparkDelay + 0.03f;
            TestEqual(*FString::Printf(TEXT("layer %d is stable across bursts"), Layer),
                Evaluate(Age, Get_SeedForLayer(Layer, 0)).VisTag,
                Evaluate(Age, Get_SeedForLayer(Layer, 7)).VisTag);
        }
    }

    // ---- Every VisTag the behavior writes is inside the roster's renderer set ----
    // Row-declared renderers live above the shared 0..4 band; a tag past the roster maximum draws with NO
    // renderer, which is invisible and silent.
    {
        const auto RosterMax = ck::particles::Get_RosterVisTag_Max();
        TestTrue(TEXT("the roster VisTag maximum covers the Slash row's renderers"), RosterMax >= kVisTagSpark);

        for (auto Layer = 0; Layer < kNumLayers; ++Layer)
        {
            const auto Out = Evaluate(0.1f, Get_SeedForLayer(Layer, 0));
            TestTrue(*FString::Printf(TEXT("layer %d writes a VisTag inside the roster set"), Layer),
                Out.VisTag >= 0 && Out.VisTag <= RosterMax);
        }
    }

    // ---- Orientation: all four mesh layers share the source's mesh-local Z -> world (0,1,0) ----
    // The crescent lies flat in mesh XY, so this is what stands the arc up in the world XZ plane. It is a
    // CONSTANT — a per-seed jitter here would fan the layers apart, which the source never does.
    {
        const auto Reference = EvaluateAtLayerT(0, 0.5f, 0).Orientation;

        auto Rotated = Reference.RotateVector(FVector3f(0.0f, 0.0f, 1.0f));
        TestTrue(TEXT("the mesh orientation carries local +Z onto world +Y"),
            Rotated.Equals(FVector3f(0.0f, 1.0f, 0.0f), kTolerance));
        TestTrue(TEXT("the mesh orientation is a unit quaternion"), Reference.IsNormalized());

        for (auto Layer = 0; Layer < 4; ++Layer)
        {
            for (const auto T : { 0.0f, 0.5f, 0.99f })
            {
                for (const auto Repeat : { 0, 3, 11 })
                {
                    TestTrue(*FString::Printf(TEXT("layer %d orientation is constant (t=%.2f, burst %d)"), Layer, T, Repeat),
                        EvaluateAtLayerT(Layer, T, Repeat).Orientation.Equals(Reference, kTolerance));
                }
            }
        }
    }

    // ---- Layer 0 / 1 (Slash_01, Slash_02): a shared colour curve, distinct dynamic params ----
    for (const auto Layer : { 0, 1 })
    {
        const auto AtSpawn = EvaluateAtLayerT(Layer, 0.0f, 0);
        TestEqual(*FString::Printf(TEXT("layer %d R is the source key 1.0 at t=0"), Layer),      AtSpawn.Color.R, 1.0f,    kTolerance);
        TestEqual(*FString::Printf(TEXT("layer %d G is the source key 0.7835 at t=0"), Layer),   AtSpawn.Color.G, 0.7835f, kTolerance);
        TestEqual(*FString::Printf(TEXT("layer %d B is the source key 0.0976 at t=0"), Layer),   AtSpawn.Color.B, 0.0976f, kTolerance);
        TestEqual(*FString::Printf(TEXT("layer %d alpha is 1 at t=0"), Layer),                   AtSpawn.Color.A, 1.0f,    kTolerance);

        const auto AtEnd = EvaluateAtLayerT(Layer, 1.0f, 0);
        TestEqual(*FString::Printf(TEXT("layer %d G reaches the source key 0.4564 at t=1"), Layer), AtEnd.Color.G, 0.4564f, kTolerance);
        TestEqual(*FString::Printf(TEXT("layer %d B reaches the source key 0.0018 at t=1"), Layer), AtEnd.Color.B, 0.0018f, kTolerance);

        TestEqual(*FString::Printf(TEXT("layer %d mesh scale is 1"), Layer),
            EvaluateAtLayerT(Layer, 0.5f, 0).Scale.X, 1.0f, kTolerance);
    }

    {
        // Slash01: dissolve held at -0.1 until 40% of life then ramping to -1; distortion a constant 0.5;
        // offset sweeping -1 -> 0.4; core inert.
        TestEqual(TEXT("layer 0 dissolve is held at -0.1 before the ramp"),
            EvaluateAtLayerT(0, 0.2f, 0).Dynamic.X, -0.1f, kTolerance);
        TestEqual(TEXT("layer 0 dissolve is -0.1 at the ramp's first key"),
            EvaluateAtLayerT(0, 0.4f, 0).Dynamic.X, -0.1f, kTolerance);
        TestEqual(TEXT("layer 0 dissolve reaches -1 at t=1"),
            EvaluateAtLayerT(0, 1.0f, 0).Dynamic.X, -1.0f, kTolerance);
        TestEqual(TEXT("layer 0 distortion is the source's constant 0.5"),
            EvaluateAtLayerT(0, 0.5f, 0).Dynamic.Y, 0.5f, kTolerance);
        TestEqual(TEXT("layer 0 offset starts at -1"),
            EvaluateAtLayerT(0, 0.0f, 0).Dynamic.Z, -1.0f, kTolerance);
        TestEqual(TEXT("layer 0 offset reaches 0.4 at t=1"),
            EvaluateAtLayerT(0, 1.0f, 0).Dynamic.Z, 0.4f, kTolerance);
        TestEqual(TEXT("layer 0 core_color is inert"),
            EvaluateAtLayerT(0, 0.7f, 0).Dynamic.W, 0.0f, kTolerance);

        // Slash02: dissolve pinned at 1, no distortion, a longer offset sweep, a late core ramp.
        TestEqual(TEXT("layer 1 dissolve is the source's constant 1"),
            EvaluateAtLayerT(1, 0.6f, 0).Dynamic.X, 1.0f, kTolerance);
        TestEqual(TEXT("layer 1 distortion is off"),
            EvaluateAtLayerT(1, 0.6f, 0).Dynamic.Y, 0.0f, kTolerance);
        TestEqual(TEXT("layer 1 offset reaches 0.7 at t=1"),
            EvaluateAtLayerT(1, 1.0f, 0).Dynamic.Z, 0.7f, kTolerance);
        TestEqual(TEXT("layer 1 core_color is held at 0 before its ramp"),
            EvaluateAtLayerT(1, 0.3f, 0).Dynamic.W, 0.0f, kTolerance);
        TestEqual(TEXT("layer 1 core_color reaches -0.5 at t=1"),
            EvaluateAtLayerT(1, 1.0f, 0).Dynamic.W, -0.5f, kTolerance);
    }

    // ---- Layer 2 (Slash_03, wearing the Slash04 material): a CONSTANT colour with Scale Alpha 0.2 ----
    for (const auto T : { 0.0f, 0.5f, 1.0f })
    {
        const auto Out = EvaluateAtLayerT(2, T, 0);
        TestEqual(*FString::Printf(TEXT("layer 2 R is the constant 0.3813 at t=%.2f"), T), Out.Color.R, 0.3813f, kTolerance);
        TestEqual(*FString::Printf(TEXT("layer 2 G is the constant 0.1946 at t=%.2f"), T), Out.Color.G, 0.1946f, kTolerance);
        TestEqual(*FString::Printf(TEXT("layer 2 B is the constant 0.0006 at t=%.2f"), T), Out.Color.B, 0.0006f, kTolerance);
        TestEqual(*FString::Printf(TEXT("layer 2 alpha carries Scale Alpha 0.2 at t=%.2f"), T), Out.Color.A, 0.2f, kTolerance);
    }
    TestEqual(TEXT("layer 2 offset reaches 0.6 at t=1"),  EvaluateAtLayerT(2, 1.0f, 0).Dynamic.Z,  0.6f, kTolerance);
    TestEqual(TEXT("layer 2 core_color reaches -0.4 at t=1"), EvaluateAtLayerT(2, 1.0f, 0).Dynamic.W, -0.4f, kTolerance);

    // ---- Layer 3 (Slash_Wind): scale 1.1, an RGB ramp settling by t=0.880, a rise-hold-fall alpha ----
    {
        TestEqual(TEXT("wind mesh scale is the source's 1.1"),
            EvaluateAtLayerT(3, 0.3f, 0).Scale.X, 1.1f, kTolerance);

        const auto AtSpawn = EvaluateAtLayerT(3, 0.0f, 0);
        TestEqual(TEXT("wind RGB starts white (R)"), AtSpawn.Color.R, 1.0f, kTolerance);
        TestEqual(TEXT("wind alpha starts at 0"),    AtSpawn.Color.A, 0.0f, kTolerance);

        const auto AtSettle = EvaluateAtLayerT(3, 0.880f, 0);
        TestEqual(TEXT("wind R reaches 0.2623 by t=0.880"), AtSettle.Color.R, 0.2623f, kTolerance);
        TestEqual(TEXT("wind G reaches 0.1384 by t=0.880"), AtSettle.Color.G, 0.1384f, kTolerance);
        TestEqual(TEXT("wind B reaches 0.0887 by t=0.880"), AtSettle.Color.B, 0.0887f, kTolerance);

        // The alpha envelope is the whole visual read: it fades IN, holds, then fades out — and the module's
        // Scale Alpha 0.2 caps it, which is what keeps the ghost dim.
        TestEqual(TEXT("wind alpha peaks at the envelope's first hold key"),
            EvaluateAtLayerT(3, 0.157f, 0).Color.A, 0.2f, kTolerance);
        TestEqual(TEXT("wind alpha still holds at the envelope's second key"),
            EvaluateAtLayerT(3, 0.316f, 0).Color.A, 0.2f, kTolerance);
        TestEqual(TEXT("wind alpha is back to 0 at t=1"),
            EvaluateAtLayerT(3, 1.0f, 0).Color.A, 0.0f, kTolerance);
        TestTrue(TEXT("wind alpha is falling in the envelope's last segment"),
            EvaluateAtLayerT(3, 0.6f, 0).Color.A > EvaluateAtLayerT(3, 0.9f, 0).Color.A);

        TestEqual(TEXT("wind dissolve is the source's constant -0.27"),
            EvaluateAtLayerT(3, 0.5f, 0).Dynamic.X, -0.27f, kTolerance);
        TestEqual(TEXT("wind offset starts at -0.375"),
            EvaluateAtLayerT(3, 0.0f, 0).Dynamic.Z, -0.375f, kTolerance);
        TestEqual(TEXT("wind offset reaches 0.375 by t=0.8 and holds"),
            EvaluateAtLayerT(3, 0.8f, 0).Dynamic.Z, 0.375f, kTolerance);
        TestEqual(TEXT("wind offset is still 0.375 at t=1"),
            EvaluateAtLayerT(3, 1.0f, 0).Dynamic.Z, 0.375f, kTolerance);
    }

    // ---- Anti-vacuity: every mesh layer contributes visible light SOMEWHERE in its own life ----
    // A layer whose colour or alpha collapsed to zero everywhere would still satisfy every curve assertion
    // above that happens to sample a zero key; this is the check that says the layer is actually drawn.
    for (auto Layer = 0; Layer < 4; ++Layer)
    {
        auto PeakLuminance = 0.0f;
        for (auto Step = 0; Step <= 40; ++Step)
        {
            const auto Out = EvaluateAtLayerT(Layer, static_cast<float>(Step) / 40.0f, 0);
            const auto Lum = (Out.Color.R + Out.Color.G + Out.Color.B) * Out.Color.A;
            PeakLuminance = FMath::Max(PeakLuminance, Lum);
        }
        TestTrue(*FString::Printf(TEXT("mesh layer %d emits nonzero colour x alpha somewhere in its life"), Layer),
            PeakLuminance > kTolerance);
    }

    // ---- Sparks: hidden before the source's 0.06 s spawn delay ----
    for (auto Layer = 4; Layer < kNumLayers; ++Layer)
    {
        for (const auto Age : { 0.0f, 0.02f, 0.0599f })
        {
            TestTrue(*FString::Printf(TEXT("spark layer %d is hidden at age %.4f (before the 0.06 s delay)"), Layer, Age),
                Is_Hidden(Evaluate(Age, Get_SeedForLayer(Layer, 0))));
        }

        TestEqual(*FString::Printf(TEXT("spark layer %d draws on the row's velocity-aligned sprite once visible"), Layer),
            Evaluate(kSparkDelay + 0.01f, Get_SeedForLayer(Layer, 0)).VisTag, kVisTagSpark);
    }

    // ---- Sparks spawn at ONE point on the r=209.769 ring, in the XZ plane, at -6.5 degrees ----
    // Direct U Position pins all fifteen to the same point; a spread here would be an invented ring.
    {
        const auto Angle = FMath::DegreesToRadians(kSparkRingAngleDeg);
        const auto Expected = FVector3f(
            kSparkRingRadius * FMath::Cos(Angle), 0.0f, kSparkRingRadius * FMath::Sin(Angle));

        for (auto Layer = 4; Layer < kNumLayers; ++Layer)
        {
            for (const auto Repeat : { 0, 2, 9 })
            {
                const auto Out = Evaluate(kSparkDelay, Get_SeedForLayer(Layer, Repeat));
                TestTrue(*FString::Printf(TEXT("spark layer %d (burst %d) spawns on the ring point"), Layer, Repeat),
                    Out.Position.Equals(Expected, 1.0e-2f));
            }
        }

        TestTrue(TEXT("the spark spawn point is on the ring's measured radius"),
            FMath::IsNearlyEqual(Expected.Size(), kSparkRingRadius, kTolerance));
        TestTrue(TEXT("the spark ring lies in the XZ plane"), FMath::IsNearlyZero(Expected.Y));
    }

    // ---- Spark initial velocity stays inside the source's per-axis random box ----
    {
        for (auto Layer = 4; Layer < kNumLayers; ++Layer)
        {
            for (const auto Repeat : { 0, 1, 5, 23, 101 })
            {
                const auto V = Evaluate(kSparkDelay, Get_SeedForLayer(Layer, Repeat)).Velocity;

                TestTrue(*FString::Printf(TEXT("spark X in [-3500, -1500] (layer %d, burst %d): %f"), Layer, Repeat, V.X),
                    V.X >= -3500.0f - kTolerance && V.X <= -1500.0f + kTolerance);
                TestTrue(*FString::Printf(TEXT("spark Y in [-500, 500] (layer %d, burst %d): %f"), Layer, Repeat, V.Y),
                    V.Y >= -500.0f - kTolerance && V.Y <= 500.0f + kTolerance);
                TestTrue(*FString::Printf(TEXT("spark Z in [1500, 3000] (layer %d, burst %d): %f"), Layer, Repeat, V.Z),
                    V.Z >= 1500.0f - kTolerance && V.Z <= 3000.0f + kTolerance);
            }
        }

        // The spray is directional, not a symmetric burst: strong -X and +Z is the swipe's follow-through.
        TestTrue(TEXT("the spark spray is strongly -X"), Evaluate(kSparkDelay, Get_SeedForLayer(4, 0)).Velocity.X < -1000.0f);
        TestTrue(TEXT("the spark spray is strongly +Z"), Evaluate(kSparkDelay, Get_SeedForLayer(4, 0)).Velocity.Z > 1000.0f);
    }

    // ---- Spark velocity decays, and Z turns NEGATIVE at the end (the source's falling tail) ----
    {
        constexpr auto Layer = 6;
        const auto Seed = Get_SeedForLayer(Layer, 3);

        // Its own lifetime is random in [0.2, 0.4]; sampling at the delay + 0.19 s stays inside the shortest.
        const auto Early = Evaluate(kSparkDelay + 0.001f, Seed).Velocity;
        const auto Later = Evaluate(kSparkDelay + 0.19f,  Seed).Velocity;

        TestTrue(TEXT("spark horizontal speed decays over life"), FMath::Abs(Later.X) < FMath::Abs(Early.X));
        TestTrue(TEXT("spark Z speed decays over life"), Later.Z < Early.Z);

        // Position is the closed-form integral of that decay, so it must have carried the spark -X and +Z off
        // the ring — the direction of the swipe's follow-through.
        const auto Spawn = Evaluate(kSparkDelay, Seed).Position;
        const auto Flown = Evaluate(kSparkDelay + 0.19f, Seed).Position;
        TestTrue(TEXT("the spark has travelled -X off its spawn point"), Flown.X < Spawn.X);
        TestTrue(TEXT("the spark has travelled +Z off its spawn point"), Flown.Z > Spawn.Z);
    }

    // ---- Spark size: zero at the delay, peaking early, gone by its own death ----
    {
        constexpr auto Layer = 9;
        const auto Seed = Get_SeedForLayer(Layer, 4);

        TestTrue(TEXT("spark size is zero at the instant it becomes visible"),
            Evaluate(kSparkDelay, Seed).Size.IsNearlyZero(kTolerance));

        auto PeakWidth = 0.0f;
        for (auto Step = 1; Step < 40; ++Step)
        {
            const auto Out = Evaluate(kSparkDelay + 0.2f * static_cast<float>(Step) / 40.0f, Seed);
            PeakWidth = FMath::Max(PeakWidth, Out.Size.X);
            TestTrue(TEXT("spark width never exceeds the source's 30-unit maximum"), Out.Size.X <= 30.0f + kTolerance);
            TestTrue(TEXT("spark length never exceeds the source's 70-unit maximum"), Out.Size.Y <= 70.0f + kTolerance);
        }
        TestTrue(TEXT("spark reaches a visible width during its life"), PeakWidth > 5.0f);
    }

    // ---- Layers past their OWN lifetime output nothing at all ----
    // The template particle lives 0.5 s; every layer but the wind dies sooner, and a layer that kept drawing
    // past its own life would leave a slash hanging in the air.
    {
        for (const auto Layer : { 0, 1, 2 })
        {
            for (const auto Age : { kLifeSlash + 0.001f, 0.4f, kTemplateLifetime })
            {
                TestTrue(*FString::Printf(TEXT("mesh layer %d is dead past its 0.3 s life (age %.3f)"), Layer, Age),
                    Is_Hidden(Evaluate(Age, Get_SeedForLayer(Layer, 0))));
            }
        }

        // The wind layer runs the full template lifetime, so it is alive at 0.4 s and dead just past 0.5 s.
        TestFalse(TEXT("the wind layer is still alive at 0.4 s"),
            Is_Hidden(Evaluate(0.4f, Get_SeedForLayer(3, 0))));
        TestTrue(TEXT("the wind layer is dead past its 0.5 s life"),
            Is_Hidden(Evaluate(kLifeWind + 0.001f, Get_SeedForLayer(3, 0))));

        // Sparks live at most 0.4 s from a 0.06 s delay, so nothing survives to the template particle's death.
        for (auto Layer = 4; Layer < kNumLayers; ++Layer)
        {
            TestTrue(*FString::Printf(TEXT("spark layer %d is dead by the template particle's death"), Layer),
                Is_Hidden(Evaluate(kSparkDelay + 0.4f + 0.001f, Get_SeedForLayer(Layer, 0))));
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
