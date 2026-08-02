// Behavior-math gate for CkParticles BehaviorId 35 (LightningCast) — the Vefects NS_Lightning_Cast recreation.
//
// Drives UCkParticles_DataInterface::Execute_Stage_CPU, the SAME CPU mirror a CPU sim runs, so it needs no
// Niagara system, no template asset, no RHI and no forked engine.
//
// Expected values are the SOURCE's own values as transcribed in
// CkFoundation/Source/CkParticles/Cookbook/NS_Lightning_Cast.md §2/§5. The 30-slot burst partition and the
// rate-weighted draw are re-implemented here on purpose: the per-emitter counts and Spawn Rates ARE the
// fidelity claim.
//
// The load-bearing claims specific to this port:
//   - the spawn-phase split (burst / rate / past-window), each asserted against its own opposite;
//   - the RATE THINNING — the source's bolt emitter streams at a falling 20 -> 0 per second, and a flat row
//     rate only reproduces that if a rate particle's survival probability falls linearly with phase. This is
//     the cookbook's first non-constant source rate and the assertion is two-sided: the surviving fraction
//     must fall across the window AND integrate to a half;
//   - the STROBING alpha of the bolt layer, which a "fade to zero" simplification would silently destroy.
//
// Cannot pass vacuously: behavior 35's VisTags are 147..156 and the pre-switch default is 0.

#include "Misc/AutomationTest.h"

#include "CkParticles/DataInterface/CkParticles_DataInterface.h"
#include "CkParticles/ScriptDefinition/CkParticles_ScriptDefinition_Naming.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_particles_lightning_cast
{
    constexpr auto kBehaviorId = 35;
    constexpr auto kTolerance  = 1.0e-4f;

    // Source facts (recipe §2/§6.1 against corpus v3).
    constexpr auto kLoop      = 2.0f;  // the SYSTEM's Loop Once / 2.0 s
    constexpr auto kLifetime  = 1.55f; // Sparkles' 0.05 s beat plus its resolved 1.5 s maximum
    constexpr auto kBurst     = 30;
    constexpr auto kSpawnRate = 40.0f; // Sparkles_Stretched 20/s flat + Lightning 20/s peak

    constexpr auto kWindowStretch   = 0.4f;
    constexpr auto kWindowLightning = 0.5f;

    constexpr auto kRowAssetName = TEXT("PS_CkParticles_Template_LightningCast");

    constexpr auto kVisPart01    = 147;
    constexpr auto kVisPart02    = 148;
    constexpr auto kVisRainbow   = 149;
    constexpr auto kVisRing01    = 150;
    constexpr auto kVisPart01Br  = 151;
    constexpr auto kVisPart04    = 152;
    constexpr auto kVisStar02    = 153;
    constexpr auto kVisPart03Br  = 154;
    constexpr auto kVisStar03    = 155;
    constexpr auto kVisLightning = 156;

    constexpr auto kLayerLightning = 15;
    constexpr auto kLayerStretch   = 18;

    // Layer index -> its source facts. Rate 0 marks a layer the source only ever BURSTS.
    struct FLayer { int32 BurstCount; float Rate; float Window; float Delay; float Life; int32 VisTag; const TCHAR* Name; };

    auto Get_Layers() -> TArrayView<const FLayer>
    {
        static const FLayer Layers[] =
        {
            {  1,  0.0f, 0.0f, 0.0f,  1.0f, kVisPart01,    TEXT("Glow_01")            },
            {  1,  0.0f, 0.0f, 0.0f,  1.0f, kVisPart02,    TEXT("Glow_02")            },
            {  1,  0.0f, 0.0f, 0.0f,  1.0f, kVisPart01,    TEXT("Glow_03")            },
            {  1,  0.0f, 0.0f, 0.1f,  0.3f, kVisRainbow,   TEXT("Raimbow")            },
            {  1,  0.0f, 0.0f, 0.05f, 0.75f, kVisRing01,   TEXT("Ring")               },
            { 10,  0.0f, 0.0f, 0.05f, 1.5f, kVisPart01Br,  TEXT("Sparkles")           },
            {  1,  0.0f, 0.0f, 0.1f,  0.5f, kVisPart02,    TEXT("Flare_01")           },
            {  1,  0.0f, 0.0f, 0.1f,  0.5f, kVisPart02,    TEXT("Flare_02")           },
            {  1,  0.0f, 0.0f, 0.0f,  0.3f, kVisStar02,    TEXT("Big_Star")           },
            {  1,  0.0f, 0.0f, 0.0f,  1.2f, kVisPart01,    TEXT("Flare_Stretched_01") },
            {  1,  0.0f, 0.0f, 0.0f,  1.2f, kVisPart03Br,  TEXT("Flare_Stretched_02") },
            {  1,  0.0f, 0.0f, 0.0f,  1.2f, kVisPart03Br,  TEXT("Flare_Stretched_03") },
            {  1,  0.0f, 0.0f, 0.0f,  1.2f, kVisStar03,    TEXT("Flare_Stretched_04") },
            {  1,  0.0f, 0.0f, 0.85f, 0.1f, kVisStar02,    TEXT("Star_01")            },
            {  1,  0.0f, 0.0f, 0.95f, 0.1f, kVisStar02,    TEXT("Star_02")            },
            {  3, 20.0f, kWindowLightning, 0.0f, 0.5f, kVisLightning, TEXT("Lightning") },
            {  2,  0.0f, 0.0f, 0.1f,  0.4f, kVisPart03Br,  TEXT("Flare_03")           },
            {  1,  0.0f, 0.0f, 0.0f,  0.3f, kVisPart01Br,  TEXT("Flare_04")           },
            {  0, 20.0f, kWindowStretch,   0.0f, 0.6f, kVisPart04,    TEXT("Sparkles_Stretched") },
        };
        return MakeArrayView(Layers);
    }

    // Burst slot -> layer. The RANGES are the source's own per-emitter burst counts.
    auto Layer_ForBurstSlot(int32 InSeed) -> int32
    {
        const auto S = ((InSeed % kBurst) + kBurst) % kBurst;

        if (S < 5)   { return S; }
        if (S < 15)  { return 5; }
        if (S < 24)  { return S - 9; }   // 15..23 -> layers 6..14
        if (S < 27)  { return kLayerLightning; }
        if (S < 29)  { return 16; }
        return 17;
    }

    // Re-implemented, not called: CkParticles_Rand's 24-bit avalanche IS what the rate draw claims to use.
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

    auto Layer_ForRateDraw(int32 InSeed) -> int32
    {
        return Rand(InSeed, 0) * kSpawnRate < 20.0f ? kLayerStretch : kLayerLightning;
    }

    auto Get_SeedsForBurstLayer(int32 InLayer, int32 InCount) -> TArray<int32>
    {
        auto Seeds = TArray<int32>{};
        for (auto Seed = 0; Seed < 100000 && Seeds.Num() < InCount; ++Seed)
        {
            if (Layer_ForBurstSlot(Seed) == InLayer)
            { Seeds.Add(Seed); }
        }
        return Seeds;
    }

    auto Get_SeedsForRateLayer(int32 InLayer, int32 InCount) -> TArray<int32>
    {
        auto Seeds = TArray<int32>{};
        for (auto Seed = 0; Seed < 200000 && Seeds.Num() < InCount; ++Seed)
        {
            if (Layer_ForRateDraw(Seed) == InLayer)
            { Seeds.Add(Seed); }
        }
        return Seeds;
    }

    // InSpawnPhase is where in the loop the particle was born: 0 is the burst, anything else is the rate stack.
    auto Evaluate(float InAge, int32 InSeed, float InSpawnPhase) -> FCk_Particles_StageResult
    {
        constexpr auto DeltaTime = 1.0f / 60.0f;

        return UCkParticles_DataInterface::Execute_Stage_CPU(
            kBehaviorId, DeltaTime, InAge, kLifetime,
            FVector3f::ZeroVector, FVector3f::ZeroVector, InSeed, InAge + InSpawnPhase);
    }

    auto Evaluate_Burst(float InAge, int32 InSeed) -> FCk_Particles_StageResult
    {
        return Evaluate(InAge, InSeed, 0.0f);
    }

    auto Is_Hidden(const FCk_Particles_StageResult& InOut) -> bool
    {
        return InOut.Color.A == 0.0f && InOut.Color.R == 0.0f && InOut.Color.G == 0.0f && InOut.Color.B == 0.0f
            && InOut.Size.IsNearlyZero() && InOut.Scale.IsNearlyZero();
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Particles_LightningCastBehavior,
    "CkTests.UnitTests.CkParticles.LightningCastBehavior",
    kCkUnitTestFlags)

bool FCkTest_Particles_LightningCastBehavior::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_lightning_cast;

    // ---- The cadence row ----
    {
        TestEqual(TEXT("behavior 35 routes to the LightningCast row"),
            ck::particles::Get_BehaviorTemplateSystemObjectPath(kBehaviorId),
            ck::particles::Get_LightningCastTemplateSystemObjectPath());

        TestEqual(TEXT("behavior 35 binds no CkUsf look — all ten of its looks ride the row's renderers"),
            ck::particles::Get_BehaviorLookName(kBehaviorId), NAME_None);

        const auto* RowSpec = static_cast<const ck::particles::FCk_ParticlesTemplateSpec*>(nullptr);
        for (const auto& Spec : ck::particles::Get_TemplateSpecs())
        {
            if (FString(Spec.AssetName) == FString(kRowAssetName))
            { RowSpec = &Spec; break; }
        }

        if (TestNotNull(TEXT("the cadence table declares a PS_CkParticles_Template_LightningCast row"), RowSpec))
        {
            TestEqual(TEXT("row loop duration matches the source SYSTEM's Loop Once 2.0 s"),
                RowSpec->LoopDuration, kLoop, kTolerance);
            TestEqual(TEXT("row particle lifetime is the longest (spawn delay + resolved lifetime)"),
                RowSpec->ParticleLifetime, kLifetime, kTolerance);
            TestEqual(TEXT("row burst is the source's exact per-firing burst total"),
                RowSpec->BurstCount, kBurst);
            TestEqual(TEXT("row spawn rate is the two streaming emitters' rates, the bolt one at its PEAK"),
                RowSpec->SpawnRate, kSpawnRate, kTolerance);

            TestEqual(TEXT("the row declares one renderer per distinct source material"),
                RowSpec->RendererOverrides.Num(), 10);

            auto Meshes          = 0;
            auto VelocityAligned = 0;
            auto SubUvSheets     = 0;
            for (const auto& Renderer : RowSpec->RendererOverrides)
            {
                if (Renderer.Kind == ck::particles::ECk_ParticlesRenderer_Kind::Mesh)
                { ++Meshes; }
                if (Renderer.Kind == ck::particles::ECk_ParticlesRenderer_Kind::VelocityAlignedSprite)
                { ++VelocityAligned; }
                if (Renderer.SubImageSize != FIntPoint(0, 0))
                {
                    ++SubUvSheets;
                    TestTrue(TEXT("the bolt sheet is the source's 2x2 grid"),
                        Renderer.SubImageSize == FIntPoint(2, 2));
                }
            }
            TestEqual(TEXT("the source has no mesh renderer anywhere, so neither does the row"), Meshes, 0);
            TestEqual(TEXT("exactly one renderer is velocity-aligned"), VelocityAligned, 1);
            TestEqual(TEXT("exactly one renderer declares a flipbook"), SubUvSheets, 1);
        }

        TestTrue(TEXT("the roster VisTag maximum covers the LightningCast row's renderers"),
            ck::particles::Get_RosterVisTag_Max() >= kVisLightning);
    }

    // ---- Burst particles take the source's exact per-emitter counts ----
    {
        auto Counts = TArray<int32>{};
        Counts.AddZeroed(Get_Layers().Num());

        for (auto Slot = 0; Slot < kBurst; ++Slot)
        { ++Counts[Layer_ForBurstSlot(Slot)]; }

        auto Index = 0;
        for (const auto& Layer : Get_Layers())
        {
            TestEqual(*FString::Printf(TEXT("%s takes its source burst count"), Layer.Name),
                Counts[Index], Layer.BurstCount);
            ++Index;
        }

        Index = 0;
        for (const auto& Layer : Get_Layers())
        {
            if (Layer.BurstCount == 0)
            { ++Index; continue; }

            for (const auto Seed : Get_SeedsForBurstLayer(Index, 3))
            {
                TestEqual(*FString::Printf(TEXT("%s (burst seed %d) draws through its own renderer"),
                    Layer.Name, Seed),
                    Evaluate_Burst(Layer.Delay + Layer.Life * 0.2f, Seed).VisTag, Layer.VisTag);
            }
            ++Index;
        }
    }

    // ---- Rate particles take a 50/50 draw, and NEVER a burst-only layer ----
    {
        constexpr auto SweepSize = 400000;

        auto Stretch = 0;
        auto Bolts   = 0;
        for (auto Seed = 0; Seed < SweepSize; ++Seed)
        {
            if (Layer_ForRateDraw(Seed) == kLayerStretch) { ++Stretch; }
            else                                          { ++Bolts; }
        }

        const auto Share = static_cast<float>(Stretch) / static_cast<float>(SweepSize);
        TestTrue(*FString::Printf(TEXT("the two streams split evenly (%.4f vs 0.5)"), Share),
            FMath::Abs(Share - 0.5f) < 0.004f);
        TestTrue(TEXT("both streams are reachable"), Stretch > 0 && Bolts > 0);
    }

    // ---- The spawn-phase split, asserted against its own opposite ----
    {
        auto RateMatchesRateTable = 0;
        auto ThinnedAtHead        = 0;
        auto HiddenPastWindow     = 0;
        auto BurstReadsBurstTable = 0;
        auto Sampled              = 0;

        for (auto Seed = 0; Seed < 2000; ++Seed)
        {
            const auto BurstLayer = Layer_ForBurstSlot(Seed);
            const auto RateLayer  = Layer_ForRateDraw(Seed);

            // Sampled at the very head of the window, where the bolt stream's thinning removes almost nothing.
            const auto AsRate = Evaluate(0.02f, Seed, 0.002f);
            const auto AsLate = Evaluate(0.02f, Seed, Get_Layers()[RateLayer].Window + 0.25f);

            if (Is_Hidden(AsRate))
            { ++ThinnedAtHead; }
            else if (AsRate.VisTag == Get_Layers()[RateLayer].VisTag)
            { ++RateMatchesRateTable; }

            if (Is_Hidden(AsLate))
            { ++HiddenPastWindow; }

            // Only the layers that open the effect at zero are readable this early on the burst path.
            if (Get_Layers()[BurstLayer].Delay <= 0.0f
                && Evaluate_Burst(0.02f, Seed).VisTag == Get_Layers()[BurstLayer].VisTag)
            { ++BurstReadsBurstTable; }

            ++Sampled;
        }

        TestEqual(TEXT("every rate particle that survives its stream's thinning draws its rate layer"),
            RateMatchesRateTable + ThinnedAtHead, Sampled);
        TestTrue(*FString::Printf(TEXT("thinning removes almost nothing at the head of the window (%d of %d)"),
            ThinnedAtHead, Sampled), ThinnedAtHead * 50 < Sampled);
        TestEqual(TEXT("every rate particle born past its window is hidden"), HiddenPastWindow, Sampled);
        TestTrue(TEXT("the burst path is reachable and reads the burst table"), BurstReadsBurstTable > 0);
    }

    // ---- The rate THINNING: the bolt stream's density must FALL across its window ----
    // The source's Spawn Rate curve runs 20 -> 0 over 0.5 s. A flat row rate reproduces that only if a rate
    // particle's survival probability is (1 - phase / window). Two-sided: the surviving fraction has to fall
    // monotonically AND integrate to a half, and the control is the OTHER stream, whose rate is flat and
    // whose survival must therefore stay at 1 across its whole window.
    {
        constexpr auto Bands   = 5;
        constexpr auto PerBand = 4000;

        auto BoltSurvival    = TArray<float>{};
        auto StretchSurvival = TArray<float>{};

        for (auto Band = 0; Band < Bands; ++Band)
        {
            const auto Phase = kWindowLightning * (static_cast<float>(Band) + 0.5f) / static_cast<float>(Bands);

            auto BoltSeen     = 0;
            auto BoltAlive    = 0;
            auto StretchSeen  = 0;
            auto StretchAlive = 0;

            for (auto Seed = 0; Seed < PerBand * 4 && BoltSeen < PerBand; ++Seed)
            {
                if (Layer_ForRateDraw(Seed) != kLayerLightning)
                { continue; }

                ++BoltSeen;
                if (NOT Is_Hidden(Evaluate(0.01f, Seed, Phase)))
                { ++BoltAlive; }
            }

            const auto StretchPhase = kWindowStretch * (static_cast<float>(Band) + 0.5f) / static_cast<float>(Bands);
            for (auto Seed = 0; Seed < PerBand * 4 && StretchSeen < PerBand; ++Seed)
            {
                if (Layer_ForRateDraw(Seed) != kLayerStretch)
                { continue; }

                ++StretchSeen;
                if (NOT Is_Hidden(Evaluate(0.01f, Seed, StretchPhase)))
                { ++StretchAlive; }
            }

            BoltSurvival.Add(static_cast<float>(BoltAlive) / static_cast<float>(BoltSeen));
            StretchSurvival.Add(static_cast<float>(StretchAlive) / static_cast<float>(StretchSeen));
        }

        auto Total = 0.0f;
        for (auto Band = 0; Band < Bands; ++Band)
        {
            const auto Expected = 1.0f - (static_cast<float>(Band) + 0.5f) / static_cast<float>(Bands);

            TestTrue(*FString::Printf(TEXT("bolt band %d survives at the source's own ramp (%.3f vs %.3f)"),
                Band, BoltSurvival[Band], Expected), FMath::Abs(BoltSurvival[Band] - Expected) < 0.03f);

            TestTrue(*FString::Printf(TEXT("the flat-rate control stream is NOT thinned in band %d (%.3f)"),
                Band, StretchSurvival[Band]), StretchSurvival[Band] > 0.999f);

            if (Band > 0)
            {
                TestTrue(*FString::Printf(TEXT("bolt survival falls from band %d to %d"), Band - 1, Band),
                    BoltSurvival[Band] < BoltSurvival[Band - 1]);
            }

            Total += BoltSurvival[Band];
        }

        const auto Mean = Total / static_cast<float>(Bands);
        TestTrue(*FString::Printf(TEXT("the thinned bolt stream integrates to half the flat one (%.3f)"), Mean),
            FMath::Abs(Mean - 0.5f) < 0.02f);
    }

    // ---- The bolt layer's STROBING alpha ----
    // Its alpha runs 1 / 0 / 1 / 0 / 1 across one life. A monotone fade would read as an ordinary sprite and
    // lose the flicker that makes the layer read as lightning, so the assertion counts sign changes.
    {
        for (const auto Seed : Get_SeedsForBurstLayer(kLayerLightning, 4))
        {
            auto Crossings = 0;
            auto WasLow    = true;

            for (auto Step = 0; Step <= 120; ++Step)
            {
                const auto Out = Evaluate_Burst(0.3f * static_cast<float>(Step) / 120.0f, Seed);
                if (Is_Hidden(Out))
                { continue; }

                const auto IsLow = Out.Color.A < 0.25f;
                if (IsLow != WasLow) { ++Crossings; }
                WasLow = IsLow;
            }

            TestTrue(*FString::Printf(TEXT("the bolt alpha strobes rather than fading (seed %d, %d crossings)"),
                Seed, Crossings), Crossings >= 3);
        }
    }

    // ---- The bolt flipbook: LINEAR mode, so every particle starts on frame 0 ----
    {
        auto SeenFrames = TSet<int32>{};

        for (const auto Seed : Get_SeedsForBurstLayer(kLayerLightning, 6))
        {
            TestEqual(TEXT("a LINEAR sub-UV run starts on frame 0"),
                FMath::RoundToInt32(Evaluate_Burst(0.0f, Seed).SubImageIndex), 0);

            for (auto Step = 0; Step <= 60; ++Step)
            {
                const auto Out = Evaluate_Burst(0.5f * static_cast<float>(Step) / 60.0f, Seed);
                if (Is_Hidden(Out))
                { continue; }

                TestTrue(TEXT("the bolt frame never leaves the 2x2 sheet"),
                    Out.SubImageIndex >= 0.0f && Out.SubImageIndex <= 3.0f);
                SeenFrames.Add(FMath::RoundToInt32(Out.SubImageIndex));
            }
        }

        TestTrue(*FString::Printf(TEXT("the bolt sheet uses all four frames (%d seen)"), SeenFrames.Num()),
            SeenFrames.Num() == 4);
    }

    // ---- The two closing stars fire late, and Star_02 after Star_01 ----
    {
        const auto Star01 = Get_SeedsForBurstLayer(13, 1)[0];
        const auto Star02 = Get_SeedsForBurstLayer(14, 1)[0];

        TestTrue(TEXT("Star_01 has not fired at half a second"), Is_Hidden(Evaluate_Burst(0.5f, Star01)));
        TestTrue(TEXT("Star_01 is alive just past its 0.85 s beat"),
            NOT Is_Hidden(Evaluate_Burst(0.86f, Star01)));
        TestTrue(TEXT("Star_02 has still not fired when Star_01 is alive"),
            Is_Hidden(Evaluate_Burst(0.86f, Star02)));
        TestTrue(TEXT("Star_02 is alive just past its 0.95 s beat"),
            NOT Is_Hidden(Evaluate_Burst(0.96f, Star02)));
        TestEqual(TEXT("Star_01 carries the source's fixed 45 degree tilt"),
            Evaluate_Burst(0.86f, Star01).Rotation, 45.0f, kTolerance);
    }

    // ---- Anti-vacuity: every layer contributes visible light somewhere in its life ----
    {
        auto Index = 0;
        for (const auto& Layer : Get_Layers())
        {
            auto PeakLuminance = 0.0f;

            const auto Seeds = Layer.BurstCount > 0
                ? Get_SeedsForBurstLayer(Index, 4)
                : Get_SeedsForRateLayer(Index, 4);

            for (const auto Seed : Seeds)
            {
                for (auto Step = 0; Step <= 80; ++Step)
                {
                    const auto Age = kLifetime * static_cast<float>(Step) / 80.0f;
                    const auto Out = Layer.BurstCount > 0
                        ? Evaluate_Burst(Age, Seed)
                        : Evaluate(Age, Seed, 0.002f);

                    PeakLuminance = FMath::Max(PeakLuminance,
                        (Out.Color.R + Out.Color.G + Out.Color.B) * Out.Color.A * Out.Size.X);
                }
            }

            TestTrue(*FString::Printf(TEXT("%s emits nonzero light somewhere in its life"), Layer.Name),
                PeakLuminance > kTolerance);
            ++Index;
        }
    }

    // ---- Death: nothing survives the row's lifetime, on either spawn path ----
    {
        for (auto Seed = 0; Seed < 200; ++Seed)
        {
            TestTrue(*FString::Printf(TEXT("burst seed %d is dead past the row's 1.55 s lifetime"), Seed),
                Is_Hidden(Evaluate(kLifetime + 0.001f, Seed, 0.0f)));
            TestTrue(*FString::Printf(TEXT("streamed seed %d is dead past the row's 1.55 s lifetime"), Seed),
                Is_Hidden(Evaluate(kLifetime + 0.001f, Seed, 0.002f)));
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
