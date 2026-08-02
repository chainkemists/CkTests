// Behavior-math gate for CkParticles BehaviorId 26 (PickupLoop) — the Vefects NS_PickupLoop recreation.
//
// Drives UCkParticles_DataInterface::Execute_Stage_CPU, the SAME CPU mirror a CPU sim runs, so it needs no
// Niagara system, no template asset, no RHI and no forked engine.
//
// Expected values are the SOURCE's own values as transcribed in
// CkFoundation/Source/CkParticles/Cookbook/NS_PickupLoop.md §2/§5 — not values read back out of the
// implementation. Both the clamped-key lerp AND the layer-selection hash are re-implemented here on purpose:
// the keys and the rate shares are the fidelity claim.
//
// This is the cookbook's FIRST rate-only port, so the partition is the test's centre of gravity. A rate-only
// source has no per-loop burst to slice, so a layer is a weighted draw against CkParticles_Rand(Seed, 0) rather
// than a residue — and a drifted threshold does not fail loudly, it just quietly gives one source emitter the
// wrong share of the stream. Ring01 at 0.5 of 27.5 particles per second is 1.8 % of it; a slot-counting
// partition could not express that share at all.
//
// Cannot pass vacuously: behavior 26's VisTags are 71..76 and the pre-switch default is 0.

#include "Misc/AutomationTest.h"

#include "CkParticles/DataInterface/CkParticles_DataInterface.h"
#include "CkParticles/ScriptDefinition/CkParticles_ScriptDefinition_Naming.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_particles_pickup_loop
{
    constexpr auto kBehaviorId = 26;
    constexpr auto kTolerance  = 1.0e-4f;

    // Source facts (recipe §2/§6.1 against corpus v3).
    constexpr auto kLoop      = 2.0f;  // the SYSTEM's Infinite loop
    constexpr auto kLifetime  = 4.0f;  // Ring01, the longest-lived layer
    constexpr auto kSpawnRate = 27.5f; // the sum of all nine emitters' Spawn Rate

    constexpr auto kRowAssetName = TEXT("PS_CkParticles_Template_PickupLoop");

    constexpr auto kVisPart01   = 71;
    constexpr auto kVisPart01Br = 72;
    constexpr auto kVisPart02   = 73;
    constexpr auto kVisRing03   = 74;
    constexpr auto kVisStar01   = 75;
    constexpr auto kVisStar02   = 76;

    // The nine source emitters, in the source's own order, with the Spawn Rate each one declares.
    struct FLayer { float Rate; float Life; int32 VisTag; const TCHAR* Name; };

    auto Get_Layers() -> TArrayView<const FLayer>
    {
        static const FLayer Layers[] =
        {
            { 2.0f, 2.0f, kVisPart01,   TEXT("Bomb_Glow_01") },
            { 2.0f, 1.0f, kVisPart01,   TEXT("Bomb_Glow_02") },
            { 4.0f, 1.0f, kVisPart01,   TEXT("Bomb_Glow_03") },
            { 4.0f, 1.0f, kVisPart02,   TEXT("Bomb_Glow_04") },
            { 5.0f, 0.6f, kVisPart01Br, TEXT("Sparkles")     },
            { 0.5f, 4.0f, kVisRing03,   TEXT("Ring01")       },
            { 2.0f, 1.0f, kVisStar01,   TEXT("Star01")       },
            { 2.0f, 0.8f, kVisStar02,   TEXT("Star02")       },
            { 6.0f, 1.0f, kVisPart02,   TEXT("Flares")       },
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

    // The cumulative-share cascade, rebuilt from the rate table above rather than from the behavior's constants.
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
    FCkTest_Particles_PickupLoopBehavior,
    "CkTests.UnitTests.CkParticles.PickupLoopBehavior",
    kCkUnitTestFlags)

bool FCkTest_Particles_PickupLoopBehavior::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_pickup_loop;

    // ---- The cadence row: the cookbook's first CONTINUOUS one ----
    {
        TestEqual(TEXT("behavior 26 routes to the PickupLoop row"),
            ck::particles::Get_BehaviorTemplateSystemObjectPath(kBehaviorId),
            ck::particles::Get_PickupLoopTemplateSystemObjectPath());

        TestEqual(TEXT("behavior 26 binds no CkUsf look — all six of its looks ride the row's renderers"),
            ck::particles::Get_BehaviorLookName(kBehaviorId), NAME_None);

        const auto* RowSpec = static_cast<const ck::particles::FCk_ParticlesTemplateSpec*>(nullptr);
        for (const auto& Spec : ck::particles::Get_TemplateSpecs())
        {
            if (FString(Spec.AssetName) == FString(kRowAssetName))
            { RowSpec = &Spec; break; }
        }

        if (TestNotNull(TEXT("the cadence table declares a PS_CkParticles_Template_PickupLoop row"), RowSpec))
        {
            TestEqual(TEXT("row loop duration matches the source SYSTEM's Infinite 2.0 s"),
                RowSpec->LoopDuration, kLoop, kTolerance);
            TestEqual(TEXT("row particle lifetime covers Ring01's 4.0 s"),
                RowSpec->ParticleLifetime, kLifetime, kTolerance);
            TestEqual(TEXT("row declares NO burst — the source has no burst module anywhere"),
                RowSpec->BurstCount, 0);
            TestEqual(TEXT("row spawn rate is the sum of the nine emitters' Spawn Rate"),
                RowSpec->SpawnRate, kSpawnRate, kTolerance);

            TestEqual(TEXT("the row declares one renderer per distinct source material"),
                RowSpec->RendererOverrides.Num(), 6);

            for (const auto& Renderer : RowSpec->RendererOverrides)
            {
                TestEqual(TEXT("every PickupLoop renderer is camera-facing, like all nine source renderers"),
                    static_cast<int32>(Renderer.Kind),
                    static_cast<int32>(ck::particles::ECk_ParticlesRenderer_Kind::CameraFacingSprite));
                TestTrue(TEXT("no PickupLoop renderer divides a sub-UV sheet — the source has no flipbook"),
                    Renderer.SubImageSize == FIntPoint(0, 0));
            }
        }

        TestTrue(TEXT("the roster VisTag maximum covers the PickupLoop row's renderers"),
            ck::particles::Get_RosterVisTag_Max() >= kVisStar02);
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

            // 0.4 % absolute: far tighter than the smallest layer's own 1.8 % share, so a swapped or dropped
            // threshold cannot hide inside it.
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
                    const auto Out = Evaluate(Layer.Life * 0.5f, Seed);

                    TestEqual(*FString::Printf(TEXT("%s (seed %d) draws through its own renderer"), Layer.Name, Seed),
                        Out.VisTag, Layer.VisTag);

                    // The draw is a pure function of the seed: re-evaluating must not move it.
                    TestEqual(*FString::Printf(TEXT("%s (seed %d) picks the same layer twice"), Layer.Name, Seed),
                        Evaluate(Layer.Life * 0.25f, Seed).VisTag, Layer.VisTag);
                }
            }
            ++Index;
        }
    }

    // ---- Ring01: the only layer whose dissolve is ANIMATED, and the only 4-second one ----
    {
        const auto Seed = Get_SeedsForLayer(5, 1);
        if (TestTrue(TEXT("Ring01 is reachable"), Seed.Num() == 1))
        {
            TestEqual(TEXT("Ring01 opens with its dissolve fully un-assembled"),
                Evaluate(0.0f, Seed[0]).Dynamic.X, -1.0f, kTolerance);
            TestEqual(TEXT("Ring01 peaks at the source's 0.5 dissolve at mid-life"),
                Evaluate(2.0f, Seed[0]).Dynamic.X, 0.5f, kTolerance);
            TestEqual(TEXT("Ring01 erodes back to -1 by the end"),
                Evaluate(3.999f, Seed[0]).Dynamic.X, -1.0f, 1.0e-2f);

            TestFalse(TEXT("Ring01 is still alive at 3.9 s, where every other layer is long gone"),
                Is_Hidden(Evaluate(3.9f, Seed[0])));
        }
    }

    // ---- Sparkles: Add Velocity from Point is DISABLED in the source, so they never move ----
    {
        for (const auto Seed : Get_SeedsForLayer(4, 8))
        {
            const auto Early = Evaluate(0.05f, Seed);
            const auto Late  = Evaluate(0.5f, Seed);

            if (Is_Hidden(Early) || Is_Hidden(Late))
            { continue; }

            TestTrue(TEXT("Sparkles hold their spawn position — the velocity module is off"),
                (Late.Position - Early.Position).IsNearlyZero());
            TestTrue(TEXT("Sparkles carry no velocity"), Late.Velocity.IsNearlyZero());
            TestTrue(TEXT("Sparkles spawn inside the source's 70-unit ball"),
                Early.Position.Size() <= 70.0f + kTolerance);
        }
    }

    // ---- Flares: hue-randomized, and the source's ALPHA is the separate Scale Alpha curve alone ----
    // Reading the Scale-RGBA curve's alpha channel as a second multiplier would darken the layer by ~20 %.
    {
        auto SeenHues  = TSet<int32>{};
        auto PeakAlpha = 0.0f;

        for (const auto Seed : Get_SeedsForLayer(8, 120))
        {
            for (auto Step = 0; Step <= 60; ++Step)
            {
                const auto Out = Evaluate(2.0f * static_cast<float>(Step) / 60.0f, Seed);
                if (Is_Hidden(Out))
                { continue; }

                PeakAlpha = FMath::Max(PeakAlpha, Out.Color.A);
                SeenHues.Add(Get_HueBucket(Out.Color));
            }
        }

        // 120 seeds land on 82 distinct half-degree hues; a dead hue shift lands on exactly ONE.
        TestTrue(*FString::Printf(TEXT("Flares randomize their hue per particle (%d distinct hues)"),
            SeenHues.Num()), SeenHues.Num() > 20);

        // Ceiling = 0.2 (the top of the Alpha Scale Range) x 0.125 (the Scale Alpha curve's peak). Both bounds
        // matter: the ceiling catches an over-bright layer, and the floor catches the transcription error this
        // recipe's §5 warns about — folding the Scale-RGBA curve's own alpha in as a SECOND multiplier, which the
        // "RGB and Alpha Separately" mode makes inert. That reading tops out near 0.0198 and would fail here.
        constexpr auto AlphaCeiling = 0.2f * 0.125f;

        TestTrue(*FString::Printf(TEXT("Flares never exceed the source's alpha ceiling (peak %f)"), PeakAlpha),
            PeakAlpha <= AlphaCeiling + kTolerance);
        TestTrue(*FString::Printf(TEXT("Flares reach that ceiling — the RGBA curve's alpha is inert (peak %f)"),
            PeakAlpha), PeakAlpha > AlphaCeiling * 0.9f);
    }

    // ---- Star02 carries the system's only non-integer static dissolve ----
    {
        const auto Seed = Get_SeedsForLayer(7, 1);
        if (TestTrue(TEXT("Star02 is reachable"), Seed.Num() == 1))
        {
            TestEqual(TEXT("Star02 pins dissolve at the source's 0.745454"),
                Evaluate(0.4f, Seed[0]).Dynamic.X, 0.745454f, kTolerance);
        }
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

    // ---- Death: nothing survives the row's 4.0 s lifetime, and only Ring01 reaches it ----
    {
        auto Index = 0;
        for (const auto& Layer : Get_Layers())
        {
            for (const auto Seed : Get_SeedsForLayer(Index, 4))
            {
                TestTrue(*FString::Printf(TEXT("%s is dead past the row's 4.0 s lifetime"), Layer.Name),
                    Is_Hidden(Evaluate(kLifetime + 0.001f, Seed)));

                if (Layer.VisTag == kVisRing03)
                { continue; }

                TestTrue(*FString::Printf(TEXT("%s is dead well before the row's lifetime (its own is %.1f s)"),
                    Layer.Name, Layer.Life), Is_Hidden(Evaluate(2.001f, Seed)));
            }
            ++Index;
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
