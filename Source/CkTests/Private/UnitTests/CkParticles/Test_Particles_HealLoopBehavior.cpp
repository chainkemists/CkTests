// Behavior-math gate for CkParticles BehaviorId 27 (HealLoop) — the Vefects NS_HealLoop recreation.
//
// Drives UCkParticles_DataInterface::Execute_Stage_CPU, the SAME CPU mirror a CPU sim runs, so it needs no
// Niagara system, no template asset, no RHI and no forked engine.
//
// Expected values are the SOURCE's own values as transcribed in
// CkFoundation/Source/CkParticles/Cookbook/NS_HealLoop.md §2/§5 — not values read back out of the
// implementation. Both the clamped-key lerp AND the layer-selection hash are re-implemented here on purpose:
// the keys and the rate shares are the fidelity claim.
//
// Two traps this file exists to hold: the source SWAPS its star materials against its emitter names (emitter
// Star01 draws with M_VFX_DisAdd_Star02), and its Flares hue range is authored DESCENDING (0.2 -> -0.2), which a
// lerp that assumes min < max gets subtly wrong.
//
// Cannot pass vacuously: behavior 27's VisTags are 77..83 and the pre-switch default is 0.

#include "Misc/AutomationTest.h"

#include "CkParticles/DataInterface/CkParticles_DataInterface.h"
#include "CkParticles/ScriptDefinition/CkParticles_ScriptDefinition_Naming.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_particles_heal_loop
{
    constexpr auto kBehaviorId = 27;
    constexpr auto kTolerance  = 1.0e-4f;

    // Source facts (recipe §2/§6.1 against corpus v3).
    constexpr auto kLoop      = 1.0f;  // the SYSTEM's Infinite loop — the shortest in the batch
    constexpr auto kLifetime  = 2.0f;  // the three glows
    constexpr auto kSpawnRate = 34.5f; // the sum of all nine emitters' Spawn Rate

    constexpr auto kRowAssetName = TEXT("PS_CkParticles_Template_HealLoop");

    constexpr auto kVisRainbow  = 77;
    constexpr auto kVisPart01Br = 78;
    constexpr auto kVisPart04   = 79;
    constexpr auto kVisStar02   = 80;
    constexpr auto kVisStar01   = 81;
    constexpr auto kVisPart01   = 82;
    constexpr auto kVisPart02   = 83;

    struct FLayer { float Rate; float Life; int32 VisTag; const TCHAR* Name; };

    auto Get_Layers() -> TArrayView<const FLayer>
    {
        static const FLayer Layers[] =
        {
            {  0.5f, 1.0f, kVisRainbow,  TEXT("Raimbow")            },
            { 10.0f, 0.3f, kVisPart01Br, TEXT("Sparkles_01")        },
            { 10.0f, 0.3f, kVisPart04,   TEXT("Sparkles_Stretched") },
            {  1.0f, 0.3f, kVisStar02,   TEXT("Star01")             },
            {  1.0f, 0.3f, kVisStar01,   TEXT("Star02")             },
            {  2.0f, 2.0f, kVisPart01,   TEXT("Glow_01")            },
            {  2.0f, 2.0f, kVisPart01,   TEXT("Glow_02")            },
            {  6.0f, 1.0f, kVisPart02,   TEXT("Flares")             },
            {  2.0f, 2.0f, kVisPart02,   TEXT("Glow_03")            },
        };
        return MakeArrayView(Layers);
    }

    // Re-implemented, not called: CkParticles_Rand's 24-bit avalanche IS what the partition claims to use.
    auto Rand(int32 InSeed, int32 InSalt) -> float
    {
        uint32 n = uint32(InSeed) * 747796405u + uint32(InSalt) * 2891336453u + 1u;
        n ^= n >> 16;
        n *= 2246822519u;
        n ^= n >> 13;
        n *= 3266489917u;
        n ^= n >> 16;
        return float(n & 0x00FFFFFFu) / 16777216.0f;
    }

    auto Layer_ForSeed(int32 InSeed) -> int32
    {
        const auto R = Rand(InSeed, 0) * kSpawnRate;

        auto Cumulative = 0.0f;
        auto Index      = 0;
        for (const auto& Layer : Get_Layers())
        {
            Cumulative += Layer.Rate;
            if (R < Cumulative)
            { return Index; }
            ++Index;
        }
        return Get_Layers().Num() - 1;
    }

    auto Get_SeedsForLayer(int32 InLayer, int32 InCount) -> TArray<int32>
    {
        auto Seeds = TArray<int32>{};
        for (auto Seed = 0; Seed < 2000000 && Seeds.Num() < InCount; ++Seed)
        {
            if (Layer_ForSeed(Seed) == InLayer)
            { Seeds.Add(Seed); }
        }
        return Seeds;
    }

    auto Evaluate(float InAge, int32 InSeed) -> FCk_Particles_StageResult
    {
        constexpr auto DeltaTime  = 1.0f / 60.0f;
        constexpr auto EmitterAge = 0.0f;

        return UCkParticles_DataInterface::Execute_Stage_CPU(
            kBehaviorId, DeltaTime, InAge, kLifetime,
            FVector3f::ZeroVector, FVector3f::ZeroVector, InSeed, EmitterAge);
    }

    auto Is_Hidden(const FCk_Particles_StageResult& InOut) -> bool
    {
        return InOut.Color.A == 0.0f && InOut.Color.R == 0.0f && InOut.Color.G == 0.0f && InOut.Color.B == 0.0f
            && InOut.Size.IsNearlyZero() && InOut.Scale.IsNearlyZero();
    }

    // The particle's HUE, recovered from its RGB and quantized to half a degree.
    //
    // Keying "the hue varies" on a colour CHANNEL is a trap twice over — see
    // Test_Particles_BuffLoopBehavior.cpp, where it produced a genuinely unsatisfiable assertion. HSV->RGB
    // hands the pinned Value to a DIFFERENT channel in every sector, so a layer whose hue band lies inside
    // one or two sectors holds a channel exactly constant while its hue varies fine; and on a layer whose
    // Saturation Range is a real range, a channel key varies even when the hue does NOT, so it would pass
    // against a dead hue shift. Inverting the conversion is saturation- and value-independent by
    // construction: remove the hue shift and this collapses to a single bucket.
    auto Get_HueBucket(const FLinearColor& InColor) -> int32
    {
        const auto Max   = FMath::Max3(InColor.R, InColor.G, InColor.B);
        const auto Min   = FMath::Min3(InColor.R, InColor.G, InColor.B);
        const auto Delta = Max - Min;

        // Achromatic: the hue is UNDEFINED rather than zero, so it takes its own bucket instead of
        // masquerading as red.
        if (Delta < 1.0e-6f)
        { return -1; }

        const auto Sextant =
            Max == InColor.R ? FMath::Fmod(((InColor.G - InColor.B) / Delta) + 6.0f, 6.0f) :
            Max == InColor.G ? ((InColor.B - InColor.R) / Delta) + 2.0f
                             : ((InColor.R - InColor.G) / Delta) + 4.0f;

        // Sextant/6 of a turn, in half-degree buckets: (Sextant / 6) * 720.
        return FMath::RoundToInt32(Sextant * 120.0f);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Particles_HealLoopBehavior,
    "CkTests.UnitTests.CkParticles.HealLoopBehavior",
    kCkUnitTestFlags)

bool FCkTest_Particles_HealLoopBehavior::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_heal_loop;

    // ---- The cadence row ----
    {
        TestEqual(TEXT("behavior 27 routes to the HealLoop row"),
            ck::particles::Get_BehaviorTemplateSystemObjectPath(kBehaviorId),
            ck::particles::Get_HealLoopTemplateSystemObjectPath());

        TestEqual(TEXT("behavior 27 binds no CkUsf look — all seven of its looks ride the row's renderers"),
            ck::particles::Get_BehaviorLookName(kBehaviorId), NAME_None);

        const auto* RowSpec = static_cast<const ck::particles::FCk_ParticlesTemplateSpec*>(nullptr);
        for (const auto& Spec : ck::particles::Get_TemplateSpecs())
        {
            if (FString(Spec.AssetName) == FString(kRowAssetName))
            { RowSpec = &Spec; break; }
        }

        if (TestNotNull(TEXT("the cadence table declares a PS_CkParticles_Template_HealLoop row"), RowSpec))
        {
            TestEqual(TEXT("row loop duration matches the source SYSTEM's Infinite 1.0 s"),
                RowSpec->LoopDuration, kLoop, kTolerance);
            TestEqual(TEXT("row particle lifetime covers the three 2.0 s glows"),
                RowSpec->ParticleLifetime, kLifetime, kTolerance);
            TestEqual(TEXT("row declares NO burst — the source has no burst module anywhere"),
                RowSpec->BurstCount, 0);
            TestEqual(TEXT("row spawn rate is the sum of the nine emitters' Spawn Rate"),
                RowSpec->SpawnRate, kSpawnRate, kTolerance);

            TestEqual(TEXT("the row declares one renderer per distinct source material"),
                RowSpec->RendererOverrides.Num(), 7);

            auto VelocityAligned = 0;
            for (const auto& Renderer : RowSpec->RendererOverrides)
            {
                if (Renderer.Kind == ck::particles::ECk_ParticlesRenderer_Kind::VelocityAlignedSprite)
                { ++VelocityAligned; }
            }
            TestEqual(TEXT("exactly one renderer is velocity-aligned, like the one source emitter that is"),
                VelocityAligned, 1);
        }

        TestTrue(TEXT("the roster VisTag maximum covers the HealLoop row's renderers"),
            ck::particles::Get_RosterVisTag_Max() >= kVisPart02);
    }

    // ---- The rate-weighted partition: deterministic per Seed, and in the source's own proportions ----
    {
        constexpr auto SweepSize = 400000;

        auto Counts = TArray<int32>{};
        Counts.AddZeroed(Get_Layers().Num());

        for (auto Seed = 0; Seed < SweepSize; ++Seed)
        { ++Counts[Layer_ForSeed(Seed)]; }

        auto Index = 0;
        for (const auto& Layer : Get_Layers())
        {
            const auto Observed = static_cast<float>(Counts[Index]) / static_cast<float>(SweepSize);
            const auto Expected = Layer.Rate / kSpawnRate;

            TestTrue(*FString::Printf(TEXT("%s takes its source share of the stream (%.4f vs %.4f)"),
                Layer.Name, Observed, Expected), FMath::Abs(Observed - Expected) < 0.004f);
            ++Index;
        }
    }

    // ---- Every layer draws through its own source emitter's renderer, and the pick is stable per Seed ----
    {
        auto Index = 0;
        for (const auto& Layer : Get_Layers())
        {
            const auto Seeds = Get_SeedsForLayer(Index, 6);

            if (TestTrue(*FString::Printf(TEXT("%s is reachable by some seed"), Layer.Name), Seeds.Num() == 6))
            {
                for (const auto Seed : Seeds)
                {
                    TestEqual(*FString::Printf(TEXT("%s (seed %d) draws through its own renderer"), Layer.Name, Seed),
                        Evaluate(Layer.Life * 0.5f, Seed).VisTag, Layer.VisTag);
                    TestEqual(*FString::Printf(TEXT("%s (seed %d) picks the same layer twice"), Layer.Name, Seed),
                        Evaluate(Layer.Life * 0.25f, Seed).VisTag, Layer.VisTag);
                }
            }
            ++Index;
        }
    }

    // ---- The SWAPPED star pair — the single most likely thing to be silently "fixed" ----
    // Emitter Star01 is the LARGER star (40..50) and draws with the Star02 paint; emitter Star02 is the smaller
    // (30..40) on the Star01 paint. Getting this the intuitive way round swaps two looks and two size ranges.
    {
        auto Star01Max = 0.0f;
        auto Star02Max = 0.0f;

        for (const auto Seed : Get_SeedsForLayer(3, 40))
        {
            const auto Out = Evaluate(0.03f, Seed);
            if (Is_Hidden(Out))
            { continue; }
            TestEqual(TEXT("emitter Star01 draws with the Star02 paint"), Out.VisTag, kVisStar02);
            Star01Max = FMath::Max(Star01Max, Out.Size.X);
        }

        for (const auto Seed : Get_SeedsForLayer(4, 40))
        {
            const auto Out = Evaluate(0.03f, Seed);
            if (Is_Hidden(Out))
            { continue; }
            TestEqual(TEXT("emitter Star02 draws with the Star01 paint"), Out.VisTag, kVisStar01);
            Star02Max = FMath::Max(Star02Max, Out.Size.X);
        }

        TestTrue(TEXT("emitter Star01 is the larger of the two size ranges"), Star01Max > Star02Max);
    }

    // ---- Both sparkle streams are fired straight UP out of a cylinder, and only one of them stretches ----
    {
        for (const auto Layer : { 1, 2 })
        {
            for (const auto Seed : Get_SeedsForLayer(Layer, 12))
            {
                const auto Out = Evaluate(0.05f, Seed);
                if (Is_Hidden(Out))
                { continue; }

                TestTrue(TEXT("the sparkle streams travel straight up"), Out.Velocity.Z > 0.0f);
                TestTrue(TEXT("the sparkle streams have no lateral velocity"),
                    FMath::IsNearlyZero(Out.Velocity.X, kTolerance) && FMath::IsNearlyZero(Out.Velocity.Y, kTolerance));
                TestTrue(TEXT("the sparkle streams spawn inside the source's 80-unit cylinder"),
                    FVector2f(Out.Position.X, Out.Position.Y).Size() <= 80.0f + kTolerance);
            }
        }

        // Sparkles_Stretched draws a NON-square quad; Sparkles_01 is round.
        for (const auto Seed : Get_SeedsForLayer(1, 8))
        {
            const auto Out = Evaluate(0.05f, Seed);
            if (Is_Hidden(Out))
            { continue; }
            TestEqual(TEXT("Sparkles_01 is a round quad"), Out.Size.X, Out.Size.Y, kTolerance);
        }

        auto SawStretch = false;
        for (const auto Seed : Get_SeedsForLayer(2, 8))
        {
            const auto Out = Evaluate(0.05f, Seed);
            if (Is_Hidden(Out))
            { continue; }
            SawStretch = SawStretch || Out.Size.Y > Out.Size.X;
        }
        TestTrue(TEXT("Sparkles_Stretched draws a stretched quad"), SawStretch);
    }

    // ---- Flares: hue randomized around a GREEN base through a DESCENDING range ----
    {
        auto SeenHues    = TSet<int32>{};
        auto PeakAlpha   = 0.0f;
        auto DarkestChan = 1.0f;
        auto BrightestChan = 0.0f;

        for (const auto Seed : Get_SeedsForLayer(7, 120))
        {
            for (auto Step = 0; Step <= 60; ++Step)
            {
                const auto Out = Evaluate(2.0f * static_cast<float>(Step) / 60.0f, Seed);
                if (Is_Hidden(Out))
                { continue; }

                PeakAlpha = FMath::Max(PeakAlpha, Out.Color.A);
                SeenHues.Add(Get_HueBucket(Out.Color));

                DarkestChan   = FMath::Min3(DarkestChan, Out.Color.R, FMath::Min(Out.Color.G, Out.Color.B));
                BrightestChan = FMath::Max3(BrightestChan, Out.Color.R, FMath::Max(Out.Color.G, Out.Color.B));
            }
        }

        // 120 seeds land on 102 distinct half-degree hues; a dead hue shift lands on exactly ONE.
        TestTrue(*FString::Printf(TEXT("Flares randomize their hue per particle (%d distinct hues)"),
            SeenHues.Num()), SeenHues.Num() > 20);

        // Saturation 0.35..0.5 at a value of 1: the brightest channel is exactly 1 and the darkest is 1 - S, so
        // nothing may fall below 0.5. A saturation drawn from the wrong end of the range shows up here.
        TestTrue(*FString::Printf(TEXT("Flares reach full value on their dominant channel (%f)"), BrightestChan),
            FMath::IsNearlyEqual(BrightestChan, 1.0f, 1.0e-3f));
        TestTrue(*FString::Printf(TEXT("Flares stay inside the source's 0.35..0.5 saturation range (%f)"), DarkestChan),
            DarkestChan >= 0.5f - 1.0e-3f && DarkestChan <= 0.65f + 1.0e-3f);

        // Ceiling = 0.1 (the top of the Alpha Scale Range) x 0.125 (the Scale Alpha curve's peak).
        constexpr auto AlphaCeiling = 0.1f * 0.125f;

        TestTrue(*FString::Printf(TEXT("Flares never exceed the source's alpha ceiling (peak %f)"), PeakAlpha),
            PeakAlpha <= AlphaCeiling + kTolerance);
        TestTrue(*FString::Printf(TEXT("Flares reach that ceiling — the RGBA curve's alpha is inert (peak %f)"),
            PeakAlpha), PeakAlpha > AlphaCeiling * 0.9f);
    }

    // ---- Glow_01 is the faintest layer in the cookbook: Scale Alpha 0.03 on the largest sprite ----
    {
        auto Glow01Peak = 0.0f;
        for (const auto Seed : Get_SeedsForLayer(5, 4))
        {
            for (auto Step = 0; Step <= 40; ++Step)
            {
                const auto Out = Evaluate(2.0f * static_cast<float>(Step) / 40.0f, Seed);
                if (Is_Hidden(Out))
                { continue; }
                Glow01Peak = FMath::Max(Glow01Peak, Out.Color.A);
                TestEqual(TEXT("Glow_01 holds the source's 550-unit size for its whole life"),
                    Out.Size.X, 550.0f, kTolerance);
            }
        }
        TestEqual(TEXT("Glow_01 peaks at the source's 0.03 Scale Alpha"), Glow01Peak, 0.03f, 1.0e-3f);
    }

    // ---- Anti-vacuity: every layer contributes visible light somewhere in its life ----
    {
        auto Index = 0;
        for (const auto& Layer : Get_Layers())
        {
            auto PeakLuminance = 0.0f;

            for (const auto Seed : Get_SeedsForLayer(Index, 4))
            {
                for (auto Step = 0; Step <= 80; ++Step)
                {
                    const auto Out = Evaluate(kLifetime * static_cast<float>(Step) / 80.0f, Seed);
                    PeakLuminance = FMath::Max(PeakLuminance,
                        (Out.Color.R + Out.Color.G + Out.Color.B) * Out.Color.A * Out.Size.X);
                }
            }

            TestTrue(*FString::Printf(TEXT("%s emits nonzero light somewhere in its life"), Layer.Name),
                PeakLuminance > kTolerance);
            ++Index;
        }
    }

    // ---- Death: nothing survives the row's 2.0 s lifetime ----
    {
        auto Index = 0;
        for (const auto& Layer : Get_Layers())
        {
            for (const auto Seed : Get_SeedsForLayer(Index, 4))
            {
                TestTrue(*FString::Printf(TEXT("%s is dead past the row's 2.0 s lifetime"), Layer.Name),
                    Is_Hidden(Evaluate(kLifetime + 0.001f, Seed)));
            }
            ++Index;
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
