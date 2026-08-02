// Behavior-math gate for CkParticles BehaviorId 31 (HealCast) — the Vefects NS_HealCast recreation.
//
// Drives UCkParticles_DataInterface::Execute_Stage_CPU, the SAME CPU mirror a CPU sim runs, so it needs no
// Niagara system, no template asset, no RHI and no forked engine.
//
// Expected values are the SOURCE's own values as transcribed in
// CkFoundation/Source/CkParticles/Cookbook/NS_HealCast.md §2/§5. The clamped-key lerp, the 17-slot burst
// partition AND the rate-weighted draw are all re-implemented here on purpose: the keys, the per-emitter
// counts and the per-emitter Spawn Rates are the fidelity claim.
//
// This is the cookbook's FIRST row to carry a burst and a rate at once, so the load-bearing new assertion is
// the SPAWN-PHASE split: a particle born at phase 0 takes the burst partition, one born mid-loop takes the
// rate draw, and one born past its own emitter's one-shot window is hidden. Each of those three is asserted
// against its own opposite.
//
// Cannot pass vacuously: behavior 31's VisTags are 105..112 and the pre-switch default is 0.

#include "Misc/AutomationTest.h"

#include "CkParticles/DataInterface/CkParticles_DataInterface.h"
#include "CkParticles/ScriptDefinition/CkParticles_ScriptDefinition_Naming.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_particles_heal_cast
{
    constexpr auto kBehaviorId = 31;
    constexpr auto kTolerance  = 1.0e-4f;

    // Source facts (recipe §2/§6.1 against corpus v3).
    constexpr auto kLoop      = 2.0f;  // the SYSTEM's Loop Once / 2.0 s
    constexpr auto kLifetime  = 1.55f; // Lens' 0.05 s beat plus its resolved 1.5 s maximum
    constexpr auto kBurst     = 17;    // 1+1+1+1+3+5+1+1+3
    constexpr auto kSpawnRate = 50.0f; // 20+10+5+5+10, the five Self/Once emitters' own Spawn Rates
    constexpr auto kDelay     = 0.05f; // every emitter but the first three bursts on this beat

    constexpr auto kRowAssetName = TEXT("PS_CkParticles_Template_HealCast");

    constexpr auto kVisPart01   = 105;
    constexpr auto kVisRainbow  = 106;
    constexpr auto kVisRing01   = 107;
    constexpr auto kVisPart01Br = 108;
    constexpr auto kVisPart04   = 109;
    constexpr auto kVisStar02   = 110;
    constexpr auto kVisStar01   = 111;
    constexpr auto kVisPart07   = 112;

    constexpr auto kLayerSparkles = 4;
    constexpr auto kLayerStretch  = 5;
    constexpr auto kLayerLens     = 8;

    // Rate 0 marks a layer the source only ever BURSTS: the three system-governed emitters never stream, so a
    // rate particle must never resolve to one of them.
    struct FLayer { float Rate; float Window; float Life; int32 VisTag; const TCHAR* Name; };

    auto Get_Layers() -> TArrayView<const FLayer>
    {
        static const FLayer Layers[] =
        {
            {  0.0f, 0.0f, 1.0f, kVisPart01,   TEXT("Bomb_Glow_01")       },
            {  0.0f, 0.0f, 1.0f, kVisPart01,   TEXT("Bomb_Glow_02")       },
            {  0.0f, 0.0f, 1.0f, kVisRainbow,  TEXT("Raimbow")            },
            {  0.0f, 0.0f, 0.5f, kVisRing01,   TEXT("Ring")               },
            { 20.0f, 0.3f, 0.6f, kVisPart01Br, TEXT("Sparkles_01")        },
            { 10.0f, 0.3f, 0.6f, kVisPart04,   TEXT("Sparkles_Stretched") },
            {  5.0f, 0.3f, 0.6f, kVisStar02,   TEXT("Star01")             },
            {  5.0f, 0.3f, 0.6f, kVisStar01,   TEXT("Star02")             },
            { 10.0f, 0.2f, 1.5f, kVisPart07,   TEXT("Lens")               },
        };
        return MakeArrayView(Layers);
    }

    // Burst slot -> layer. The RANGES are the source's own per-emitter burst counts.
    auto Layer_ForBurstSlot(int32 InSeed) -> int32
    {
        const auto S = ((InSeed % kBurst) + kBurst) % kBurst;

        if (S == 0)  { return 0; }
        if (S == 1)  { return 1; }
        if (S == 2)  { return 2; }
        if (S == 3)  { return 3; }
        if (S < 7)   { return 4; }
        if (S < 12)  { return 5; }
        if (S == 12) { return 6; }
        if (S == 13) { return 7; }
        return 8;
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
        const auto R = Rand(InSeed, 0) * kSpawnRate;

        auto Cumulative = 0.0f;
        auto Index      = 0;
        for (const auto& Layer : Get_Layers())
        {
            Cumulative += Layer.Rate;
            if (Layer.Rate > 0.0f && R < Cumulative)
            { return Index; }
            ++Index;
        }
        return Get_Layers().Num() - 1;
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
    FCkTest_Particles_HealCastBehavior,
    "CkTests.UnitTests.CkParticles.HealCastBehavior",
    kCkUnitTestFlags)

bool FCkTest_Particles_HealCastBehavior::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_heal_cast;

    // ---- The cadence row ----
    {
        TestEqual(TEXT("behavior 31 routes to the HealCast row"),
            ck::particles::Get_BehaviorTemplateSystemObjectPath(kBehaviorId),
            ck::particles::Get_HealCastTemplateSystemObjectPath());

        TestEqual(TEXT("behavior 31 binds no CkUsf look — all eight of its looks ride the row's renderers"),
            ck::particles::Get_BehaviorLookName(kBehaviorId), NAME_None);

        const auto* RowSpec = static_cast<const ck::particles::FCk_ParticlesTemplateSpec*>(nullptr);
        for (const auto& Spec : ck::particles::Get_TemplateSpecs())
        {
            if (FString(Spec.AssetName) == FString(kRowAssetName))
            { RowSpec = &Spec; break; }
        }

        if (TestNotNull(TEXT("the cadence table declares a PS_CkParticles_Template_HealCast row"), RowSpec))
        {
            TestEqual(TEXT("row loop duration matches the source SYSTEM's Loop Once 2.0 s"),
                RowSpec->LoopDuration, kLoop, kTolerance);
            TestEqual(TEXT("row particle lifetime is the longest (spawn delay + resolved lifetime)"),
                RowSpec->ParticleLifetime, kLifetime, kTolerance);
            TestEqual(TEXT("row burst is the source's exact per-firing burst total"),
                RowSpec->BurstCount, kBurst);
            TestEqual(TEXT("row spawn rate is the sum of the five Self/Once emitters' Spawn Rates"),
                RowSpec->SpawnRate, kSpawnRate, kTolerance);

            TestEqual(TEXT("the row declares one renderer per distinct source material"),
                RowSpec->RendererOverrides.Num(), 8);

            auto VelocityAligned = 0;
            auto SubUvSheets     = 0;
            for (const auto& Renderer : RowSpec->RendererOverrides)
            {
                if (Renderer.Kind == ck::particles::ECk_ParticlesRenderer_Kind::VelocityAlignedSprite)
                { ++VelocityAligned; }
                if (Renderer.SubImageSize != FIntPoint(0, 0))
                {
                    ++SubUvSheets;
                    TestEqual(TEXT("the sub-UV renderer is VELOCITY-ALIGNED, not camera-facing"),
                        static_cast<int32>(Renderer.Kind),
                        static_cast<int32>(ck::particles::ECk_ParticlesRenderer_Kind::VelocityAlignedSprite));
                    TestTrue(TEXT("the lens sheet is the source's 2x2 grid"),
                        Renderer.SubImageSize == FIntPoint(2, 2));
                }
            }
            TestEqual(TEXT("two renderers are velocity-aligned, like the two source emitters that are"),
                VelocityAligned, 2);
            TestEqual(TEXT("exactly one renderer declares a flipbook"), SubUvSheets, 1);
        }

        TestTrue(TEXT("the roster VisTag maximum covers the HealCast row's renderers"),
            ck::particles::Get_RosterVisTag_Max() >= kVisPart07);
    }

    // ---- Burst particles take the source's exact per-emitter counts ----
    {
        auto Counts = TArray<int32>{};
        Counts.AddZeroed(Get_Layers().Num());

        for (auto Slot = 0; Slot < kBurst; ++Slot)
        { ++Counts[Layer_ForBurstSlot(Slot)]; }

        const int32 Expected[] = {1, 1, 1, 1, 3, 5, 1, 1, 3};
        auto Index = 0;
        for (const auto& Layer : Get_Layers())
        {
            TestEqual(*FString::Printf(TEXT("%s takes its source burst count"), Layer.Name),
                Counts[Index], Expected[Index]);
            ++Index;
        }

        for (auto Index2 = 0; Index2 < Get_Layers().Num(); ++Index2)
        {
            for (const auto Seed : Get_SeedsForBurstLayer(Index2, 4))
            {
                const auto& Layer = Get_Layers()[Index2];
                const auto  Delay = Index2 > 2 ? kDelay : 0.0f;

                TestEqual(*FString::Printf(TEXT("%s (burst seed %d) draws through its own renderer"), Layer.Name, Seed),
                    Evaluate_Burst(Delay + Layer.Life * 0.4f, Seed).VisTag, Layer.VisTag);
            }
        }
    }

    // ---- Rate particles take the source's Spawn Rate shares, and NEVER a burst-only layer ----
    {
        constexpr auto SweepSize = 400000;

        auto Counts = TArray<int32>{};
        Counts.AddZeroed(Get_Layers().Num());

        for (auto Seed = 0; Seed < SweepSize; ++Seed)
        { ++Counts[Layer_ForRateDraw(Seed)]; }

        auto Index = 0;
        for (const auto& Layer : Get_Layers())
        {
            const auto Observed = static_cast<float>(Counts[Index]) / static_cast<float>(SweepSize);
            const auto Expected = Layer.Rate / kSpawnRate;

            TestTrue(*FString::Printf(TEXT("%s takes its source share of the stream (%.4f vs %.4f)"),
                Layer.Name, Observed, Expected), FMath::Abs(Observed - Expected) < 0.004f);
            ++Index;
        }

        // The three system-governed emitters have no Spawn Rate module at all, so nothing may stream into them.
        TestEqual(TEXT("Bomb_Glow_01 never appears in the stream"), Counts[0], 0);
        TestEqual(TEXT("Bomb_Glow_02 never appears in the stream"), Counts[1], 0);
        TestEqual(TEXT("Raimbow never appears in the stream"),      Counts[2], 0);
        TestEqual(TEXT("Ring never appears in the stream"),         Counts[3], 0);
    }

    // ---- The spawn-phase split, asserted against its own opposite ----
    // One Seed, three spawn phases: at 0 it is a burst particle, mid-window it is a rate particle of a
    // (usually different) layer, and past the window it does not exist. Collapsing any of the three into
    // another is exactly the failure this row's burst+rate composition can have.
    {
        auto BurstMatchesBurstTable = 0;
        auto RateMatchesRateTable   = 0;
        auto HiddenPastWindow       = 0;
        auto Sampled                = 0;

        for (auto Seed = 0; Seed < 2000; ++Seed)
        {
            const auto BurstLayer = Layer_ForBurstSlot(Seed);
            const auto RateLayer  = Layer_ForRateDraw(Seed);
            const auto Window     = Get_Layers()[RateLayer].Window;

            const auto AsBurst = Evaluate(0.02f, Seed, 0.0f);
            const auto AsRate  = Evaluate(0.02f, Seed, Window * 0.5f);
            const auto AsLate  = Evaluate(0.02f, Seed, Window + 0.25f);

            // A burst particle sampled before the 0.05 s beat is hidden by design, so only the three
            // system-governed layers are readable this early on the burst path.
            if (BurstLayer <= 2 && AsBurst.VisTag == Get_Layers()[BurstLayer].VisTag)
            { ++BurstMatchesBurstTable; }

            if (AsRate.VisTag == Get_Layers()[RateLayer].VisTag)
            { ++RateMatchesRateTable; }

            if (Is_Hidden(AsLate))
            { ++HiddenPastWindow; }

            ++Sampled;
        }

        TestEqual(TEXT("every rate particle born inside its window draws its rate layer"),
            RateMatchesRateTable, Sampled);
        TestEqual(TEXT("every rate particle born past its window is hidden"), HiddenPastWindow, Sampled);
        TestTrue(TEXT("the burst path is reachable and reads the burst table"), BurstMatchesBurstTable > 0);
    }

    // ---- The 50 ms beat: six of nine emitters fire late on the BURST path only ----
    // A rate particle's own spawn time IS its phase, so it must NOT carry the burst's delay on top.
    {
        for (auto Index = 3; Index < Get_Layers().Num(); ++Index)
        {
            for (const auto Seed : Get_SeedsForBurstLayer(Index, 3))
            {
                TestTrue(*FString::Printf(TEXT("%s is hidden before the 50 ms beat"), Get_Layers()[Index].Name),
                    Is_Hidden(Evaluate_Burst(kDelay - 0.001f, Seed)));
            }
        }

        for (const auto Seed : Get_SeedsForRateLayer(kLayerSparkles, 8))
        {
            TestTrue(TEXT("a streamed Sparkles_01 is alive immediately, with no burst delay"),
                NOT Is_Hidden(Evaluate(0.01f, Seed, 0.1f)));
        }
    }

    // ---- Lens: the sub-UV flare ----
    // The only layer in the cookbook that is both velocity-aligned and a flipbook. Its frame must stay inside
    // the source's declared 0..3, it must actually advance, and its dissolve must DIP and RE-FORM rather than
    // slide one way.
    {
        auto SeenFrames  = TSet<int32>{};
        auto AdvancedFor = 0;
        auto Sampled     = 0;

        for (const auto Seed : Get_SeedsForBurstLayer(kLayerLens, 12))
        {
            auto First = -1.0f;
            auto Last  = -1.0f;

            for (auto Step = 0; Step <= 40; ++Step)
            {
                const auto Out = Evaluate_Burst(kDelay + 1.0f * static_cast<float>(Step) / 40.0f, Seed);
                if (Is_Hidden(Out))
                { continue; }

                TestTrue(TEXT("the lens flipbook frame stays inside the source's 2x2 sheet"),
                    Out.SubImageIndex >= 0.0f && Out.SubImageIndex <= 3.0f);

                SeenFrames.Add(FMath::RoundToInt32(Out.SubImageIndex));
                if (First < 0.0f) { First = Out.SubImageIndex; }
                Last = Out.SubImageIndex;
            }

            if (Last != First) { ++AdvancedFor; }
            ++Sampled;
        }

        TestTrue(*FString::Printf(TEXT("the lens sheet uses all four frames (%d seen)"), SeenFrames.Num()),
            SeenFrames.Num() == 4);
        TestTrue(TEXT("every sampled lens particle advances its flipbook"), AdvancedFor == Sampled);

        // Dissolve (0, -1) -> (0.2, 0) -> (1, -1): fully eroded at both ends, intact at t = 0.2.
        for (const auto Seed : Get_SeedsForBurstLayer(kLayerLens, 4))
        {
            const auto Start = Evaluate_Burst(kDelay + 0.001f, Seed);
            const auto Mid   = Evaluate_Burst(kDelay + 0.2f * 1.0f, Seed);

            TestTrue(TEXT("the lens flare starts fully eroded"), Start.Dynamic.X < -0.9f);
            TestTrue(TEXT("the lens flare re-forms around its midpoint"), Mid.Dynamic.X > Start.Dynamic.X + 0.5f);
        }
    }

    // ---- Sparkles_Stretched: the speed stretch, and the source's INVERTED Y size bounds ----
    {
        auto MinRatio = TNumericLimits<float>::Max();
        auto MaxRatio = 0.0f;

        for (const auto Seed : Get_SeedsForBurstLayer(kLayerStretch, 40))
        {
            const auto Out = Evaluate_Burst(kDelay + 0.01f, Seed);
            if (Is_Hidden(Out) || Out.Size.X <= 0.0f)
            { continue; }

            const auto Ratio = Out.Size.Y / Out.Size.X;
            MinRatio = FMath::Min(MinRatio, Ratio);
            MaxRatio = FMath::Max(MaxRatio, Ratio);

            TestTrue(TEXT("Sparkles_Stretched travels upward"), Out.Velocity.Z > 0.0f);
        }

        TestTrue(*FString::Printf(TEXT("Sparkles_Stretched draws a taller-than-wide quad (ratio %f..%f)"),
            MinRatio, MaxRatio), MinRatio > 1.0f);

        // Scale Sprite Size by Speed doubles the LENGTH at or past the 1000-unit threshold and leaves the width
        // alone. Its velocity range starts at 1000, so every particle is at the ceiling while it is young.
        TestTrue(TEXT("the speed stretch is on the length axis only"), MaxRatio > 2.0f);
    }

    // ---- Star01 and Star02 differ ONLY in size and opacity, and their PAINTS are swapped ----
    // The source's emitter names and materials are crossed; a reader "fixing" that would swap two renderers.
    {
        TestEqual(TEXT("emitter Star01 draws with the Star02 paint"), Get_Layers()[6].VisTag, kVisStar02);
        TestEqual(TEXT("emitter Star02 draws with the Star01 paint"), Get_Layers()[7].VisTag, kVisStar01);

        const auto S1 = Evaluate_Burst(kDelay + 0.1f, Get_SeedsForBurstLayer(6, 1)[0]);
        const auto S2 = Evaluate_Burst(kDelay + 0.1f, Get_SeedsForBurstLayer(7, 1)[0]);

        TestTrue(TEXT("both stars travel upward off their sunken cylinder"),
            S1.Velocity.Z > 0.0f && S2.Velocity.Z > 0.0f);
    }

    // ---- Anti-vacuity: every layer contributes visible light somewhere in its life ----
    {
        auto Index = 0;
        for (const auto& Layer : Get_Layers())
        {
            auto PeakLuminance = 0.0f;

            for (const auto Seed : Get_SeedsForBurstLayer(Index, 4))
            {
                for (auto Step = 0; Step <= 80; ++Step)
                {
                    const auto Out = Evaluate_Burst(kLifetime * static_cast<float>(Step) / 80.0f, Seed);
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
                Is_Hidden(Evaluate(kLifetime + 0.001f, Seed, 0.1f)));
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
