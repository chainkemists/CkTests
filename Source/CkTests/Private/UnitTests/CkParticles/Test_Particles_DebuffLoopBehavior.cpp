// Behavior-math gate for CkParticles BehaviorId 29 (DebuffLoop) — the Vefects NS_DebuffLoop recreation.
//
// Drives UCkParticles_DataInterface::Execute_Stage_CPU, the SAME CPU mirror a CPU sim runs, so it needs no
// Niagara system, no template asset, no RHI and no forked engine.
//
// Expected values are the SOURCE's own values as transcribed in
// CkFoundation/Source/CkParticles/Cookbook/NS_DebuffLoop.md §2/§5 — not values read back out of the
// implementation. Both the clamped-key lerp AND the layer-selection hash are re-implemented here on purpose:
// the keys and the rate shares are the fidelity claim.
//
// The one thing here that no other port has: SPAWN PROBABILITY. Both arrow emitters draw a probability from
// 0.5..1.0 per spawn and then draw against it, so a quarter of their slots render nothing — which makes the
// effective particle count non-deterministic per loop and is exactly what an anti-vacuity assertion has to
// tolerate rather than trip over.
//
// Cannot pass vacuously: behavior 29's VisTags are 91..96 and the pre-switch default is 0.

#include "Misc/AutomationTest.h"

#include "CkParticles/DataInterface/CkParticles_DataInterface.h"
#include "CkParticles/ScriptDefinition/CkParticles_ScriptDefinition_Naming.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_particles_debuff_loop
{
    constexpr auto kBehaviorId = 29;
    constexpr auto kTolerance  = 1.0e-4f;

    // Source facts (recipe §2/§6.1 against corpus v3).
    constexpr auto kLoop      = 2.0f;
    constexpr auto kLifetime  = 2.0f;  // Glow_01's direct 2.0 and the Ring/Flames/Flares 2.0 maxima
    constexpr auto kSpawnRate = 36.0f; // the sum of all nine emitters' Spawn Rate

    constexpr auto kRowAssetName = TEXT("PS_CkParticles_Template_DebuffLoop");

    constexpr auto kVisPart01   = 91;
    constexpr auto kVisPart01Br = 92;
    constexpr auto kVisRing01   = 93;
    constexpr auto kVisFlames01 = 94;
    constexpr auto kVisPart02   = 95;
    constexpr auto kVisArrows   = 96;

    constexpr auto kLayerFlames      = 2;
    constexpr auto kLayerGlow03      = 5;
    constexpr auto kLayerArrowGreen  = 6;
    constexpr auto kLayerArrowPurple = 7;

    struct FLayer { float Rate; float Life; int32 VisTag; const TCHAR* Name; };

    auto Get_Layers() -> TArrayView<const FLayer>
    {
        static const FLayer Layers[] =
        {
            { 4.0f, 1.0f, kVisPart01Br, TEXT("Sparkles_Dark") },
            { 3.0f, 1.0f, kVisRing01,   TEXT("Ring")          },
            { 5.0f, 1.0f, kVisFlames01, TEXT("Flames")        },
            { 2.0f, 2.0f, kVisPart01,   TEXT("Glow_01")       },
            { 4.0f, 1.0f, kVisPart01,   TEXT("Glow_02")       },
            { 4.0f, 1.0f, kVisPart01,   TEXT("Glow_03")       },
            { 4.0f, 0.6f, kVisArrows,   TEXT("Arrow_Green")   },
            { 4.0f, 0.6f, kVisArrows,   TEXT("Arrow_Purple")  },
            { 6.0f, 1.0f, kVisPart02,   TEXT("Flares")        },
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

    // The source's own gate, rebuilt: draw the probability from 0.5..1.0, then draw against it.
    auto Wins_SpawnDraw(int32 InSeed) -> bool
    {
        return Rand(InSeed, 12) < FMath::Lerp(0.5f, 1.0f, Rand(InSeed, 11));
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
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Particles_DebuffLoopBehavior,
    "CkTests.UnitTests.CkParticles.DebuffLoopBehavior",
    kCkUnitTestFlags)

bool FCkTest_Particles_DebuffLoopBehavior::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_debuff_loop;

    // ---- The cadence row ----
    {
        TestEqual(TEXT("behavior 29 routes to the DebuffLoop row"),
            ck::particles::Get_BehaviorTemplateSystemObjectPath(kBehaviorId),
            ck::particles::Get_DebuffLoopTemplateSystemObjectPath());

        TestEqual(TEXT("behavior 29 binds no CkUsf look — all six of its looks ride the row's renderers"),
            ck::particles::Get_BehaviorLookName(kBehaviorId), NAME_None);

        const auto* RowSpec = static_cast<const ck::particles::FCk_ParticlesTemplateSpec*>(nullptr);
        for (const auto& Spec : ck::particles::Get_TemplateSpecs())
        {
            if (FString(Spec.AssetName) == FString(kRowAssetName))
            { RowSpec = &Spec; break; }
        }

        if (TestNotNull(TEXT("the cadence table declares a PS_CkParticles_Template_DebuffLoop row"), RowSpec))
        {
            TestEqual(TEXT("row loop duration matches the source SYSTEM's Infinite 2.0 s"),
                RowSpec->LoopDuration, kLoop, kTolerance);
            TestEqual(TEXT("row particle lifetime covers the 2.0 s glow and the 2.0 s maxima"),
                RowSpec->ParticleLifetime, kLifetime, kTolerance);
            TestEqual(TEXT("row declares NO burst — the source has no burst module anywhere"),
                RowSpec->BurstCount, 0);
            TestEqual(TEXT("row spawn rate is the sum of the nine emitters' Spawn Rate"),
                RowSpec->SpawnRate, kSpawnRate, kTolerance);

            TestEqual(TEXT("the row declares one renderer per distinct source material"),
                RowSpec->RendererOverrides.Num(), 6);

            auto SawFlameSheet   = false;
            auto VelocityAligned = 0;
            for (const auto& Renderer : RowSpec->RendererOverrides)
            {
                if (Renderer.VisTag == kVisFlames01)
                { SawFlameSheet = Renderer.SubImageSize == FIntPoint(2, 2); }
                if (Renderer.Kind == ck::particles::ECk_ParticlesRenderer_Kind::VelocityAlignedSprite)
                { ++VelocityAligned; }
            }
            TestTrue(TEXT("the Flames row renderer declares the source's 2x2 sub-UV grid"), SawFlameSheet);
            TestEqual(TEXT("one renderer is velocity-aligned, and it serves BOTH arrow emitters"),
                VelocityAligned, 1);
        }

        TestTrue(TEXT("the roster VisTag maximum covers the DebuffLoop row's renderers"),
            ck::particles::Get_RosterVisTag_Max() >= kVisArrows);
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
    // The two arrow layers are probability-gated, so a losing slot is legitimately invisible and is skipped.
    {
        auto Index = 0;
        for (const auto& Layer : Get_Layers())
        {
            const auto Seeds = Get_SeedsForLayer(Index, 8);

            if (TestTrue(*FString::Printf(TEXT("%s is reachable by some seed"), Layer.Name), Seeds.Num() == 8))
            {
                auto Visible = 0;
                for (const auto Seed : Seeds)
                {
                    const auto Out = Evaluate(Layer.Life * 0.5f, Seed);
                    if (Is_Hidden(Out))
                    { continue; }

                    ++Visible;
                    TestEqual(*FString::Printf(TEXT("%s (seed %d) draws through its own renderer"), Layer.Name, Seed),
                        Out.VisTag, Layer.VisTag);
                    TestEqual(*FString::Printf(TEXT("%s (seed %d) picks the same layer twice"), Layer.Name, Seed),
                        Evaluate(Layer.Life * 0.25f, Seed).VisTag, Layer.VisTag);
                }
                TestTrue(*FString::Printf(TEXT("%s produced at least one visible sample"), Layer.Name), Visible > 0);
            }
            ++Index;
        }
    }

    // ---- Spawn probability: the arrows lose about a quarter of their slots, and no other layer loses any ----
    // E[1 - P] with P uniform on 0.5..1.0 is exactly 0.25. A behavior that dropped the gate would show 0 %; one
    // that applied it to the wrong layers would show losses outside the two arrow bands.
    {
        for (const auto ArrowLayer : { kLayerArrowGreen, kLayerArrowPurple })
        {
            const auto Seeds = Get_SeedsForLayer(ArrowLayer, 4000);

            auto Lost        = 0;
            auto Disagreements = 0;
            for (const auto Seed : Seeds)
            {
                // The gate is age-independent, so a lost slot is hidden at EVERY age. Counted rather than
                // asserted per sample: four thousand formatted assertions would drown a red run in noise.
                const auto AlwaysHidden = Is_Hidden(Evaluate(0.0f, Seed))
                                       && Is_Hidden(Evaluate(0.2f, Seed))
                                       && Is_Hidden(Evaluate(0.4f, Seed));

                if (AlwaysHidden != (NOT Wins_SpawnDraw(Seed)))
                { ++Disagreements; }

                if (AlwaysHidden)
                { ++Lost; }
            }

            TestEqual(TEXT("the spawn gate agrees with the source's own two draws on every slot"),
                Disagreements, 0);

            const auto LostShare = static_cast<float>(Lost) / static_cast<float>(Seeds.Num());
            TestTrue(*FString::Printf(TEXT("the arrows lose about a quarter of their slots (%.4f)"), LostShare),
                FMath::Abs(LostShare - 0.25f) < 0.03f);
        }

        // Every other layer spawns unconditionally.
        for (const auto Layer : { 0, 1, 2, 3, 4, 5, 8 })
        {
            auto Hidden = 0;
            for (const auto Seed : Get_SeedsForLayer(Layer, 200))
            {
                if (Is_Hidden(Evaluate(0.05f, Seed)))
                { ++Hidden; }
            }
            TestEqual(*FString::Printf(TEXT("layer %d is not probability-gated"), Layer), Hidden, 0);
        }
    }

    // ---- The two arrows are ONE look told apart by colour alone ----
    // Green's dominant channel is G, purple's is B; both draw through the same renderer.
    {
        auto GreenDominant  = 0;
        auto PurpleDominant = 0;

        for (const auto Seed : Get_SeedsForLayer(kLayerArrowGreen, 40))
        {
            const auto Out = Evaluate(0.15f, Seed);
            if (Is_Hidden(Out))
            { continue; }
            if (Out.Color.G > Out.Color.R && Out.Color.G > Out.Color.B)
            { ++GreenDominant; }
        }

        for (const auto Seed : Get_SeedsForLayer(kLayerArrowPurple, 40))
        {
            const auto Out = Evaluate(0.15f, Seed);
            if (Is_Hidden(Out))
            { continue; }
            if (Out.Color.B > Out.Color.R && Out.Color.B > Out.Color.G)
            { ++PurpleDominant; }
        }

        TestTrue(TEXT("Arrow_Green is green-dominant"), GreenDominant > 20);
        TestTrue(TEXT("Arrow_Purple is blue-dominant"), PurpleDominant > 20);
    }

    // ---- Both arrows FALL, and they spawn high before the position offset drops them ----
    {
        for (const auto ArrowLayer : { kLayerArrowGreen, kLayerArrowPurple })
        {
            for (const auto Seed : Get_SeedsForLayer(ArrowLayer, 12))
            {
                const auto Out = Evaluate(0.15f, Seed);
                if (Is_Hidden(Out))
                { continue; }

                TestTrue(TEXT("the arrows travel downward"), Out.Velocity.Z < 0.0f);
                TestTrue(TEXT("the arrows draw a taller-than-wide quad, as the source's (90, 150) authors"),
                    Out.Size.Y > Out.Size.X);
            }
        }
    }

    // ---- Flames: the only flipbook layer, and the only one that drives the distortion channel ----
    {
        const auto Seeds = Get_SeedsForLayer(kLayerFlames, 4);

        if (TestTrue(TEXT("Flames is reachable"), Seeds.Num() == 4))
        {
            auto SeenFrames = TSet<int32>{};
            for (const auto Seed : Seeds)
            {
                for (auto Step = 0; Step <= 20; ++Step)
                {
                    const auto Out = Evaluate(1.0f * static_cast<float>(Step) / 20.0f, Seed);
                    if (Is_Hidden(Out))
                    { continue; }

                    TestTrue(TEXT("Flames' sub-image index stays inside the 2x2 sheet"),
                        Out.SubImageIndex >= 0.0f && Out.SubImageIndex <= 3.0f);
                    SeenFrames.Add(FMath::FloorToInt32(Out.SubImageIndex));
                }
            }
            TestTrue(TEXT("the Flames flipbook actually advances over life"), SeenFrames.Num() > 1);

            const auto Out = Evaluate(0.3f, Seeds[0]);
            TestEqual(TEXT("Flames pins the distortion channel at the source's constant 10"),
                Out.Dynamic.Y, 10.0f, kTolerance);
            TestEqual(TEXT("Flames sits on the source's 20-unit sphere SHELL"),
                Out.Position.Size(), 20.0f, 1.0e-2f);
        }
    }

    // ---- Glow_03: the one layer in the cookbook with no curve of any kind ----
    // Two update modules only, so its Initialize colour renders unchanged for its whole life — a port that gave it
    // an alpha envelope would make the largest sprite in the cookbook fade instead of popping.
    {
        for (const auto Seed : Get_SeedsForLayer(kLayerGlow03, 4))
        {
            const auto Early = Evaluate(0.01f, Seed);
            const auto Late  = Evaluate(0.99f, Seed);

            TestEqual(TEXT("Glow_03 holds its Initialize alpha"), Early.Color.A, 0.4f, kTolerance);
            TestEqual(TEXT("Glow_03 never fades"), Late.Color.A, Early.Color.A, kTolerance);
            TestEqual(TEXT("Glow_03 holds the cookbook's largest sprite size"), Early.Size.X, 1000.0f, kTolerance);
            TestEqual(TEXT("Glow_03 never resizes"), Late.Size.X, Early.Size.X, kTolerance);
        }
    }

    // ---- Sparkles_Dark FALLS, unlike every sparkle stream in the Buff and Heal siblings ----
    {
        for (const auto Seed : Get_SeedsForLayer(0, 12))
        {
            const auto Out = Evaluate(0.2f, Seed);
            if (Is_Hidden(Out))
            { continue; }

            TestTrue(TEXT("Sparkles_Dark travels downward"), Out.Velocity.Z < 0.0f);
        }
    }

    // ---- Anti-vacuity: every layer contributes visible light somewhere in its life ----
    {
        auto Index = 0;
        for (const auto& Layer : Get_Layers())
        {
            auto PeakLuminance = 0.0f;

            for (const auto Seed : Get_SeedsForLayer(Index, 8))
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
