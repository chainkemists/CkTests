// Behavior-math gate for CkParticles BehaviorId 22 (GunshotHit) — the Vefects NS_Gunshot_Hit recreation.
//
// Drives UCkParticles_DataInterface::Execute_Stage_CPU, the SAME CPU mirror a CPU sim runs, so it needs no
// Niagara system, no template asset, no RHI and no forked engine.
//
// Expected values are the SOURCE's own values as transcribed in
// CkFoundation/Source/CkParticles/Cookbook/NS_Gunshot_Hit.md §2/§5 — not values read back out of the
// implementation. The clamped-key lerp is re-implemented here on purpose: the KEYS are the fidelity claim.
//
// Cannot pass vacuously: behavior 22's VisTags are 28..36 and the pre-switch default is 0, so every layer
// assertion here proves the switch actually reached case 22.

#include "Misc/AutomationTest.h"

#include "CkParticles/DataInterface/CkParticles_DataInterface.h"
#include "CkParticles/ScriptDefinition/CkParticles_ScriptDefinition_Naming.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_particles_gunshot_hit
{
    constexpr auto kBehaviorId = 22;
    constexpr auto kTolerance  = 1.0e-4f;

    // Source facts (recipe §2/§5 against corpus v3).
    constexpr auto kNumLayers = 40;   // the source's FULL enabled particle count, Sparkles_01 folded in
    constexpr auto kLifetime  = 0.65f; // max over layers of (spawn delay + resolved lifetime)
    constexpr auto kLoop      = 2.0f;

    constexpr auto kDelayEarly = 0.04f;
    constexpr auto kDelayLate  = 0.05f;

    constexpr auto kRowAssetName = TEXT("PS_CkParticles_Template_GunshotHit");

    constexpr auto kVisPart01   = 28;
    constexpr auto kVisPart02   = 29;
    constexpr auto kVisPart04   = 30;
    constexpr auto kVisPart03Br = 31;
    constexpr auto kVisStar01   = 32;
    constexpr auto kVisImpact02 = 33;
    constexpr auto kVisImpact01 = 34;
    constexpr auto kVisSpike    = 35;
    constexpr auto kVisPart01Br = 36;

    auto Get_SeedForLayer(int32 InLayer, int32 InRepeat) -> int32
    {
        return InLayer + kNumLayers * InRepeat;
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

    // The source's own layer -> emitter partition (recipe §6.1, option (a)).
    struct FBand { int32 First; int32 Count; float Delay; float Life; int32 VisTag; const TCHAR* Name; };

    auto Get_Bands() -> TArrayView<const FBand>
    {
        static const FBand Bands[] =
        {
            {  0, 1, 0.0f,        0.1f,  kVisPart01,   TEXT("Glow_01")     },
            {  1, 1, 0.0f,        0.1f,  kVisPart01,   TEXT("Glow_02")     },
            {  2, 5, kDelayEarly, 0.05f, kVisPart02,   TEXT("Glow_03")     },
            {  7, 5, kDelayLate,  0.3f,  kVisPart04,   TEXT("Sparkles_02") }, // lifetime is random 0.3..0.6
            { 12, 5, kDelayLate,  0.2f,  kVisPart01,   TEXT("Glow_04")     },
            { 17, 3, kDelayLate,  0.1f,  kVisPart03Br, TEXT("Glow_05")     },
            { 20, 1, kDelayLate,  0.2f,  kVisStar01,   TEXT("Star01")      },
            { 21, 6, kDelayLate,  0.2f,  kVisImpact02, TEXT("Impact_01")   },
            { 27, 1, kDelayLate,  0.05f, kVisImpact01, TEXT("FlareImpact") },
            { 28, 5, kDelayLate,  0.1f,  kVisSpike,    TEXT("Spike01")     },
            { 33, 7, kDelayLate,  0.3f,  kVisPart01Br, TEXT("Sparkles_01") }, // lifetime is random 0.3..0.6
        };
        return MakeArrayView(Bands);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Particles_GunshotHitBehavior,
    "CkTests.UnitTests.CkParticles.GunshotHitBehavior",
    kCkUnitTestFlags)

bool FCkTest_Particles_GunshotHitBehavior::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_gunshot_hit;

    // ---- The cadence row ----
    {
        TestEqual(TEXT("behavior 22 routes to the GunshotHit row"),
            ck::particles::Get_BehaviorTemplateSystemObjectPath(kBehaviorId),
            ck::particles::Get_GunshotHitTemplateSystemObjectPath());

        TestEqual(TEXT("behavior 22 binds no CkUsf look — all nine of its looks ride the row's renderers"),
            ck::particles::Get_BehaviorLookName(kBehaviorId), NAME_None);

        const auto* RowSpec = static_cast<const ck::particles::FCk_ParticlesTemplateSpec*>(nullptr);
        for (const auto& Spec : ck::particles::Get_TemplateSpecs())
        {
            if (FString(Spec.AssetName) == FString(kRowAssetName))
            { RowSpec = &Spec; break; }
        }

        if (TestNotNull(TEXT("the cadence table declares a PS_CkParticles_Template_GunshotHit row"), RowSpec))
        {
            TestEqual(TEXT("row loop duration matches the source SYSTEM's Loop-Once 2.0 s"),
                RowSpec->LoopDuration, kLoop, kTolerance);
            TestEqual(TEXT("row particle lifetime covers the 0.05 s spawn beat plus the 0.6 s sparkle life"),
                RowSpec->ParticleLifetime, kLifetime, kTolerance);
            TestEqual(TEXT("row burst count is the source's full enabled particle count"),
                RowSpec->BurstCount, kNumLayers);

            // Impact_01 is the one sub-UV renderer here and the effect's dominant element; a dropped grid is silent.
            auto SawImpactSheet = false;
            for (const auto& Renderer : RowSpec->RendererOverrides)
            {
                if (Renderer.VisTag == kVisImpact02)
                { SawImpactSheet = Renderer.SubImageSize == FIntPoint(2, 2); }
            }
            TestTrue(TEXT("the Impact_01 row renderer declares the source's 2x2 sub-UV grid"), SawImpactSheet);
        }
    }

    // ---- The 40-slot partition maps every layer onto its source emitter's renderer ----
    // A drifted band boundary silently collapses two source emitters onto one look.
    {
        const auto RosterMax = ck::particles::Get_RosterVisTag_Max();
        TestTrue(TEXT("the roster VisTag maximum covers the GunshotHit row's renderers"),
            RosterMax >= kVisPart01Br);

        auto Covered = 0;
        for (const auto& Band : Get_Bands())
        {
            Covered += Band.Count;
            for (auto Index = 0; Index < Band.Count; ++Index)
            {
                const auto Layer = Band.First + Index;
                const auto Out   = Evaluate(Band.Delay + Band.Life * 0.5f, Get_SeedForLayer(Layer, 0));

                TestEqual(*FString::Printf(TEXT("layer %d (%s) draws through its own renderer"), Layer, Band.Name),
                    Out.VisTag, Band.VisTag);

                for (const auto Repeat : { 3, 11, 907 })
                {
                    TestEqual(*FString::Printf(TEXT("layer %d is stable across bursts (burst %d)"), Layer, Repeat),
                        Evaluate(Band.Delay + Band.Life * 0.5f, Get_SeedForLayer(Layer, Repeat)).VisTag, Band.VisTag);
                }
            }
        }
        TestEqual(TEXT("the bands partition all 40 slots with no gap and no overlap"), Covered, kNumLayers);
    }

    // ---- CURVE-S, the impact ramp, and its 4x alpha over-brighten ----
    // Three emitters wear it, which is what makes the hit read as ONE flash; any clamp added later would flatten
    // the three brightest layers of the system, so the alpha is asserted ABOVE 1 deliberately.
    {
        struct FCurveSLayer { int32 Layer; float Life; float Delay; };
        const FCurveSLayer Wearers[] = { { 2, 0.05f, kDelayEarly }, { 27, 0.05f, kDelayLate }, { 28, 0.1f, kDelayLate } };

        for (const auto& Wearer : Wearers)
        {
            const auto Seed = Get_SeedForLayer(Wearer.Layer, 0);

            const auto AtSpawn = Evaluate(Wearer.Delay, Seed);
            TestEqual(*FString::Printf(TEXT("layer %d opens on CURVE-S red 0.715694"), Wearer.Layer),
                AtSpawn.Color.R, 0.715694f, kTolerance);
            TestEqual(*FString::Printf(TEXT("layer %d opens on CURVE-S blue 1.0"), Wearer.Layer),
                AtSpawn.Color.B, 1.0f, kTolerance);
            TestEqual(*FString::Printf(TEXT("layer %d carries the source's 4x alpha over-brighten"), Wearer.Layer),
                AtSpawn.Color.A, 4.0f, kTolerance);

            // By t ~ 0.708 the ramp has crushed to near-black.
            const auto Late = Evaluate(Wearer.Delay + Wearer.Life * 0.85f, Seed);
            TestTrue(*FString::Printf(TEXT("layer %d crushes to near-black late in life"), Wearer.Layer),
                Late.Color.R < 0.05f && Late.Color.G < 0.05f && Late.Color.B < 0.05f);
        }
    }

    // ---- Impact_01: the dominant element. A 5x blue-white flashbulb on a 2x2 sheet ----
    {
        const auto Seed    = Get_SeedForLayer(21, 0);
        const auto AtSpawn = Evaluate(kDelayLate, Seed);

        TestEqual(TEXT("Impact_01 opens at the source's 3.57847 red key"), AtSpawn.Color.R, 3.57847f, kTolerance);
        TestEqual(TEXT("Impact_01 opens at the source's 4.48135 green key"), AtSpawn.Color.G, 4.48135f, kTolerance);
        TestEqual(TEXT("Impact_01 opens at the source's 5x blue key"),       AtSpawn.Color.B, 5.0f,     kTolerance);
        TestEqual(TEXT("Impact_01 dissolve opens at 1 and is driven to -1"), AtSpawn.Dynamic.X, 1.0f,   kTolerance);
        TestEqual(TEXT("Impact_01 dissolve reaches -1 at the end of life"),
            Evaluate(kDelayLate + 0.2f, Seed).Dynamic.X, -1.0f, kTolerance);

        auto SeenFrames = TSet<int32>{};
        for (auto Step = 0; Step <= 20; ++Step)
        {
            const auto Out = Evaluate(kDelayLate + 0.2f * static_cast<float>(Step) / 20.0f, Seed);
            TestTrue(TEXT("Impact_01 sub-image index stays inside the 2x2 sheet"),
                Out.SubImageIndex >= 0.0f && Out.SubImageIndex <= 3.0f);
            SeenFrames.Add(FMath::FloorToInt32(Out.SubImageIndex));
        }
        TestTrue(TEXT("the Impact_01 flipbook actually advances over life"), SeenFrames.Num() > 1);
    }

    // ---- Glow_05: HDR RGB that does NOT move, and an alpha that does ----
    {
        const auto Seed = Get_SeedForLayer(17, 0);
        for (const auto Frac : { 0.0f, 0.4f, 0.9f })
        {
            const auto Out = Evaluate(kDelayLate + 0.1f * Frac, Seed);
            TestEqual(TEXT("Glow_05 red is a constant 3x key"),   Out.Color.R, 3.0f,      kTolerance);
            TestEqual(TEXT("Glow_05 green is a constant key"),    Out.Color.G, 1.49184f,  kTolerance);
            TestEqual(TEXT("Glow_05 blue is a constant key"),     Out.Color.B, 0.509197f, kTolerance);
        }
        TestTrue(TEXT("Glow_05's only animation is its alpha fade"),
            Evaluate(kDelayLate + 0.099f, Seed).Color.A < Evaluate(kDelayLate + 0.04f, Seed).Color.A);
    }

    // ---- Sparkles_01 carries the batch's largest constant dissolve, and Sparkles_02 none at all ----
    TestEqual(TEXT("Sparkles_01 pins dissolve at the source's 3"),
        Evaluate(kDelayLate + 0.1f, Get_SeedForLayer(33, 0)).Dynamic.X, 3.0f, kTolerance);
    TestEqual(TEXT("Sparkles_02 writes no dissolve at all"),
        Evaluate(kDelayLate + 0.1f, Get_SeedForLayer(7, 0)).Dynamic.X, 0.0f, kTolerance);

    // ---- Kinematics: this system is OMNIDIRECTIONAL, the one structural difference from the Cast variant ----
    // Every moving layer must fly radially from the impact point, so a batch of seeds has to spread over the
    // sphere rather than share a cone. A directed port would pass every per-layer check above and still be wrong.
    {
        auto Sum   = FVector3f::ZeroVector;
        auto Count = 0;
        for (auto Burst = 0; Burst < 24; ++Burst)
        {
            const auto Out = Evaluate(kDelayLate + 0.05f, Get_SeedForLayer(7, Burst));
            if (Is_Hidden(Out) || Out.Velocity.IsNearlyZero())
            { continue; }

            Sum += Out.Velocity.GetSafeNormal();
            ++Count;
        }

        TestTrue(TEXT("the sparkle spray produced samples to average"), Count > 8);
        TestTrue(TEXT("Sparkles_02 fires radially, not down a cone"),
            (Sum / static_cast<float>(Count)).Size() < 0.5f);
    }

    // Spike01's mesh layer must carry a normalized orientation and a nonzero mesh scale — its renderer faces
    // velocity in the source, which the behavior reproduces by writing the orientation itself.
    {
        const auto Out = Evaluate(kDelayLate + 0.02f, Get_SeedForLayer(28, 0));
        TestTrue(TEXT("Spike01 writes a normalized mesh orientation"), Out.Orientation.IsNormalized());
        TestTrue(TEXT("Spike01 writes a nonzero mesh scale"), NOT Out.Scale.IsNearlyZero());
        TestTrue(TEXT("Spike01 draws no sprite quad"), Out.Size.IsNearlyZero());
        TestTrue(TEXT("Spike01's orientation points down its own velocity"),
            FVector3f::DotProduct(Out.Orientation.RotateVector(FVector3f(0.0f, 0.0f, 1.0f)),
                                  Out.Velocity.GetSafeNormal()) > 0.99f);
    }

    // ---- Anti-vacuity: every layer contributes visible light somewhere in its life ----
    for (const auto& Band : Get_Bands())
    {
        for (auto Index = 0; Index < Band.Count; ++Index)
        {
            const auto Layer = Band.First + Index;
            auto PeakLuminance = 0.0f;

            for (auto Step = 0; Step <= 60; ++Step)
            {
                const auto Out = Evaluate(kLifetime * static_cast<float>(Step) / 60.0f, Get_SeedForLayer(Layer, 0));
                const auto Extent = FMath::Max(Out.Size.X, Out.Scale.GetMax());
                PeakLuminance = FMath::Max(PeakLuminance,
                    (Out.Color.R + Out.Color.G + Out.Color.B) * Out.Color.A * Extent);
            }

            TestTrue(*FString::Printf(TEXT("layer %d (%s) emits nonzero light somewhere in its life"),
                Layer, Band.Name), PeakLuminance > kTolerance);
        }
    }

    // ---- Spawn beats and death ----
    for (const auto& Band : Get_Bands())
    {
        if (Band.Delay <= 0.0f)
        { continue; }

        TestTrue(*FString::Printf(TEXT("%s hides before its %.2f s spawn beat"), Band.Name, Band.Delay),
            Is_Hidden(Evaluate(Band.Delay - 0.001f, Get_SeedForLayer(Band.First, 0))));
    }

    // The last spawn is at 0.05 s and the longest life 0.6 s, so nothing survives past the row's own lifetime.
    for (auto Layer = 0; Layer < kNumLayers; ++Layer)
    {
        for (auto Burst = 0; Burst < 8; ++Burst)
        {
            TestTrue(*FString::Printf(TEXT("layer %d is dead past the row's 0.65 s lifetime"), Layer),
                Is_Hidden(Evaluate(kLifetime + 0.001f, Get_SeedForLayer(Layer, Burst))));
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
