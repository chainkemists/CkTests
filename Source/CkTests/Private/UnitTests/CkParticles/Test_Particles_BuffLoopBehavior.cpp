// Behavior-math gate for CkParticles BehaviorId 28 (BuffLoop) — the Vefects NS_BuffLoop recreation.
//
// Drives UCkParticles_DataInterface::Execute_Stage_CPU, the SAME CPU mirror a CPU sim runs, so it needs no
// Niagara system, no template asset, no RHI and no forked engine.
//
// Expected values are the SOURCE's own values as transcribed in
// CkFoundation/Source/CkParticles/Cookbook/NS_BuffLoop.md §2/§5 — not values read back out of the
// implementation. Both the clamped-key lerp AND the layer-selection hash are re-implemented here on purpose:
// the keys and the rate shares are the fidelity claim.
//
// This is the batch's only port with a FORCE. Sparkles_Spiral's Vortex Force is a plain tangential vortex about
// +Z whose Origin Pull Amount is 0, which is a falsifiable claim in two halves: the radius must be invariant over
// the particle's whole life, and the polar angle must advance. A curl-noise implementation, or one that let the
// force pull inward, fails the first half; an inert one fails the second.
//
// Cannot pass vacuously: behavior 28's VisTags are 84..90 and the pre-switch default is 0.

#include "Misc/AutomationTest.h"

#include "CkParticles/DataInterface/CkParticles_DataInterface.h"
#include "CkParticles/ScriptDefinition/CkParticles_ScriptDefinition_Naming.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_particles_buff_loop
{
    constexpr auto kBehaviorId = 28;
    constexpr auto kTolerance  = 1.0e-4f;

    // Source facts (recipe §2/§6.1 against corpus v3).
    constexpr auto kLoop      = 2.0f;
    constexpr auto kLifetime  = 2.0f;  // Glow_01's direct 2.0 and Flares' 2.0 maximum
    constexpr auto kSpawnRate = 48.0f; // the sum of all nine emitters' Spawn Rate — the batch's densest

    constexpr auto kRowAssetName = TEXT("PS_CkParticles_Template_BuffLoop");

    constexpr auto kVisPart01   = 84;
    constexpr auto kVisRainbow  = 85;
    constexpr auto kVisArrows   = 86;
    constexpr auto kVisStar01   = 87;
    constexpr auto kVisPart04   = 88;
    constexpr auto kVisPart01Br = 89;
    constexpr auto kVisPart02   = 90;

    constexpr auto kLayerSparkles = 6;
    constexpr auto kLayerSpiral   = 8;

    struct FLayer { float Rate; float Life; int32 VisTag; const TCHAR* Name; };

    auto Get_Layers() -> TArrayView<const FLayer>
    {
        static const FLayer Layers[] =
        {
            {  2.0f, 2.0f, kVisPart01,   TEXT("Glow_01")            },
            {  1.0f, 0.5f, kVisRainbow,  TEXT("Raimbow")            },
            {  3.0f, 1.5f, kVisArrows,   TEXT("Arrow")              },
            {  2.0f, 0.3f, kVisStar01,   TEXT("Stars")              },
            { 10.0f, 0.3f, kVisPart04,   TEXT("Sparkles_Stretched") },
            {  4.0f, 1.0f, kVisPart01,   TEXT("Glow_02")            },
            { 10.0f, 0.3f, kVisPart01Br, TEXT("Sparkles_01")        },
            {  6.0f, 1.0f, kVisPart02,   TEXT("Flares")             },
            { 10.0f, 0.3f, kVisPart01Br, TEXT("Sparkles_Spiral")    },
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

    auto Get_PlanarRadius(const FCk_Particles_StageResult& InOut) -> float
    {
        return FVector2f(InOut.Position.X, InOut.Position.Y).Size();
    }

    auto Get_PlanarAngle(const FCk_Particles_StageResult& InOut) -> float
    {
        return FMath::Atan2(InOut.Position.Y, InOut.Position.X);
    }

    // The particle's HUE, recovered from its RGB and quantized to half a degree.
    //
    // Keying "the hue varies" on a colour CHANNEL is a trap twice over, and this layer is where it bit:
    //
    //   * HSV->RGB hands the pinned Value to a DIFFERENT channel in every sector, so a layer whose hue band
    //     lies inside one or two sectors holds a channel exactly constant while its hue varies perfectly
    //     well. The source's Hue Shift Range (0.5, 0.8) off a base hue of 0.99888 puts this band at
    //     [0.4989, 0.7989] — sectors 3 and 4 plus 0.37 % of sector 2 — and BLUE is the pinned Value across
    //     all of it (measured minimum 0.99867 over 20 000 seeds). A blue key sees ONE bucket, forever.
    //   * On the sibling systems whose Saturation Range is a real range, a channel key varies even when the
    //     hue does NOT — so it would pass against a dead hue shift, which is the defect it exists to catch.
    //
    // Inverting the conversion is saturation- and value-independent by construction: remove the hue shift
    // and this collapses to a single bucket on all three Flare layers in the batch.
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
    FCkTest_Particles_BuffLoopBehavior,
    "CkTests.UnitTests.CkParticles.BuffLoopBehavior",
    kCkUnitTestFlags)

bool FCkTest_Particles_BuffLoopBehavior::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_buff_loop;

    // ---- The cadence row ----
    {
        TestEqual(TEXT("behavior 28 routes to the BuffLoop row"),
            ck::particles::Get_BehaviorTemplateSystemObjectPath(kBehaviorId),
            ck::particles::Get_BuffLoopTemplateSystemObjectPath());

        TestEqual(TEXT("behavior 28 binds no CkUsf look — all seven of its looks ride the row's renderers"),
            ck::particles::Get_BehaviorLookName(kBehaviorId), NAME_None);

        const auto* RowSpec = static_cast<const ck::particles::FCk_ParticlesTemplateSpec*>(nullptr);
        for (const auto& Spec : ck::particles::Get_TemplateSpecs())
        {
            if (FString(Spec.AssetName) == FString(kRowAssetName))
            { RowSpec = &Spec; break; }
        }

        if (TestNotNull(TEXT("the cadence table declares a PS_CkParticles_Template_BuffLoop row"), RowSpec))
        {
            TestEqual(TEXT("row loop duration matches the source SYSTEM's Infinite 2.0 s"),
                RowSpec->LoopDuration, kLoop, kTolerance);
            TestEqual(TEXT("row particle lifetime covers the 2.0 s glow and the 2.0 s flare maximum"),
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
            TestEqual(TEXT("two renderers are velocity-aligned, like the two source emitters that are"),
                VelocityAligned, 2);
        }

        TestTrue(TEXT("the roster VisTag maximum covers the BuffLoop row's renderers"),
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

    // ---- The Vortex Force: tangential only, and it actually turns ----
    // Origin Pull Amount is 0 in the source, so the radius is invariant; the force is the whole reason this layer
    // exists, so the angle must move. Sparkles_01 is the control — same cylinder shape, no force.
    {
        auto TurnedLayers   = 0;
        auto RadiusFailures = 0;
        auto TotalSwirl     = 0.0f;

        for (const auto Seed : Get_SeedsForLayer(kLayerSpiral, 24))
        {
            const auto Early = Evaluate(0.01f, Seed);
            const auto Late  = Evaluate(0.29f, Seed);

            if (Is_Hidden(Early) || Is_Hidden(Late))
            { continue; }

            const auto EarlyRadius = Get_PlanarRadius(Early);
            const auto LateRadius  = Get_PlanarRadius(Late);

            if (NOT FMath::IsNearlyEqual(EarlyRadius, LateRadius, 1.0e-2f))
            { ++RadiusFailures; }

            const auto Swirl = FMath::Abs(FMath::UnwindRadians(Get_PlanarAngle(Late) - Get_PlanarAngle(Early)));
            TotalSwirl += Swirl;

            if (Swirl > 1.0e-3f)
            { ++TurnedLayers; }
        }

        TestEqual(TEXT("the vortex never changes a particle's radius — Origin Pull Amount is 0"),
            RadiusFailures, 0);
        TestTrue(TEXT("every spiral particle actually turns about the axis"), TurnedLayers >= 20);
        TestTrue(*FString::Printf(TEXT("the swirl is a visible fraction of a turn, not a rounding artefact (mean %f rad)"),
            TotalSwirl / 24.0f), TotalSwirl / 24.0f > 0.1f);

        // The control: Sparkles_01 shares the cylinder shape and the velocity range but carries no force.
        auto ControlSwirl = 0.0f;
        for (const auto Seed : Get_SeedsForLayer(kLayerSparkles, 24))
        {
            const auto Early = Evaluate(0.01f, Seed);
            const auto Late  = Evaluate(0.29f, Seed);

            if (Is_Hidden(Early) || Is_Hidden(Late))
            { continue; }

            ControlSwirl += FMath::Abs(FMath::UnwindRadians(Get_PlanarAngle(Late) - Get_PlanarAngle(Early)));
        }
        TestTrue(TEXT("Sparkles_01 does NOT swirl — only Sparkles_Spiral carries the force"),
            ControlSwirl < 1.0e-3f);
    }

    // ---- Arrow: the source's only 1.5 s layer, drawn on a NON-square velocity-aligned quad ----
    {
        for (const auto Seed : Get_SeedsForLayer(2, 8))
        {
            const auto Out = Evaluate(0.15f, Seed);
            if (Is_Hidden(Out))
            { continue; }

            TestTrue(TEXT("Arrow travels upward"), Out.Velocity.Z > 0.0f);
            TestTrue(TEXT("Arrow draws a taller-than-wide quad, as the source's (80, 130) authors"),
                Out.Size.Y > Out.Size.X);
        }

        // Position Offset (0, 0, -119.316) composes with the cylinder's own +30 lift, so the layer opens BELOW
        // the spawn point. Dropping either term puts the whole stream in the wrong place.
        auto LowestSpawn = 0.0f;
        for (const auto Seed : Get_SeedsForLayer(2, 40))
        {
            const auto Out = Evaluate(0.0f, Seed);
            if (Is_Hidden(Out))
            { continue; }
            LowestSpawn = FMath::Min(LowestSpawn, Out.Position.Z);
        }
        TestTrue(*FString::Printf(TEXT("Arrow spawns below the origin (lowest %f)"), LowestSpawn),
            LowestSpawn < -100.0f);
    }

    // ---- Flares: hue randomized 0.5..0.8 off a RED base, which lands them in the cyans and blues ----
    {
        auto SeenHues      = TSet<int32>{};
        auto PeakAlpha     = 0.0f;
        auto DarkestChan   = 1.0f;
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

        // 120 seeds land on 93 distinct half-degree hues; a dead hue shift lands on exactly ONE. The bar
        // sits far above the broken case and far below the healthy one, so it fails on a dead shift rather
        // than on a retune.
        TestTrue(*FString::Printf(TEXT("Flares randomize their hue per particle (%d distinct hues)"),
            SeenHues.Num()), SeenHues.Num() > 20);

        // Saturation Range is (0.2, 0.2) — a single value — so every channel sits between 0.8 and 1.
        TestTrue(*FString::Printf(TEXT("Flares reach full value on their dominant channel (%f)"), BrightestChan),
            FMath::IsNearlyEqual(BrightestChan, 1.0f, 1.0e-3f));
        TestTrue(*FString::Printf(TEXT("Flares carry the source's pinned 0.2 saturation (%f)"), DarkestChan),
            FMath::IsNearlyEqual(DarkestChan, 0.8f, 1.0e-3f));

        // Ceiling = 0.13 (the pinned Alpha Scale) x 0.125 (the Scale Alpha curve's peak).
        constexpr auto AlphaCeiling = 0.13f * 0.125f;

        TestTrue(*FString::Printf(TEXT("Flares never exceed the source's alpha ceiling (peak %f)"), PeakAlpha),
            PeakAlpha <= AlphaCeiling + kTolerance);
        TestTrue(*FString::Printf(TEXT("Flares reach that ceiling — the RGBA curve's alpha is inert (peak %f)"),
            PeakAlpha), PeakAlpha > AlphaCeiling * 0.9f);
    }

    // ---- Stars' two DISABLED modules stay disabled ----
    // Its Sprite Rotation Rate curve is authored (0, 720) -> (1, 0) but the module is off, and the BuffCast
    // sibling has the same module ENABLED — so implementing it here would import the wrong system's behaviour.
    {
        for (const auto Seed : Get_SeedsForLayer(3, 12))
        {
            const auto Early = Evaluate(0.02f, Seed);
            const auto Late  = Evaluate(0.28f, Seed);

            if (Is_Hidden(Early) || Is_Hidden(Late))
            { continue; }

            TestEqual(TEXT("Stars never rotate — the source's rotation-rate module is disabled"),
                Late.Rotation, Early.Rotation, kTolerance);
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
