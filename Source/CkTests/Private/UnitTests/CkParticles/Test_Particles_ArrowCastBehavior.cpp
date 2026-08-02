// Behavior-math gate for CkParticles BehaviorId 23 (ArrowCast) — the Vefects NS_Arrow_Cast recreation.
//
// Drives UCkParticles_DataInterface::Execute_Stage_CPU, the SAME CPU mirror a CPU sim runs, so it needs no
// Niagara system, no template asset, no RHI and no forked engine.
//
// Expected values are the SOURCE's own values as transcribed in
// CkFoundation/Source/CkParticles/Cookbook/NS_Arrow_Cast.md §2/§5 — not values read back out of the
// implementation. The clamped-key lerp is re-implemented here on purpose: the KEYS are the fidelity claim.
//
// This is the longest-lived port in the cookbook: thirteen of its fifteen layers are dead by t ~= 0.55 s and
// the two Wind layers run to 1.55 s. The lifetime assertion below is therefore load-bearing — a row lifetime
// cut to the visible majority would silently truncate the wind.
//
// Cannot pass vacuously: behavior 23's VisTags are 37..49 and the pre-switch default is 0.

#include "Misc/AutomationTest.h"

#include "CkParticles/DataInterface/CkParticles_DataInterface.h"
#include "CkParticles/ScriptDefinition/CkParticles_ScriptDefinition_Naming.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_particles_arrow_cast
{
    constexpr auto kBehaviorId = 23;
    constexpr auto kTolerance  = 1.0e-4f;

    // Source facts (recipe §2/§6.1 against corpus v3).
    constexpr auto kNumLayers = 42;
    constexpr auto kLifetime  = 1.55f; // the Wind pair's 1.5 s life off the 0.05 s beat
    constexpr auto kLoop      = 2.0f;

    constexpr auto kDelayEarly  = 0.04f;
    constexpr auto kDelayLate   = 0.05f;
    constexpr auto kDelayStar02 = 0.1f;

    constexpr auto kRowAssetName = TEXT("PS_CkParticles_Template_ArrowCast");

    constexpr auto kVisPart01   = 37;
    constexpr auto kVisPart02   = 38;
    constexpr auto kVisRainbow  = 39;
    constexpr auto kVisPart04   = 40;
    constexpr auto kVisRing01   = 41;
    constexpr auto kVisPart01Br = 42;
    constexpr auto kVisImpact01 = 43;
    constexpr auto kVisSpike    = 44;
    constexpr auto kVisStrip    = 45;
    constexpr auto kVisStar01   = 46;
    constexpr auto kVisStar02   = 47;
    constexpr auto kVisWindMesh = 48;
    constexpr auto kVisWindPuff = 49;

    auto Get_SeedForLayer(int32 InLayer, int32 InRepeat) -> int32
    {
        return InLayer + kNumLayers * InRepeat;
    }

    auto Evaluate(float InAge, int32 InSeed) -> FCk_Particles_StageResult
    {
        constexpr auto DeltaTime = 1.0f / 60.0f;

        return UCkParticles_DataInterface::Execute_Stage_CPU(
            kBehaviorId, DeltaTime, InAge, kLifetime,
            FVector3f::ZeroVector, FVector3f::ZeroVector, InSeed);
    }

    auto Is_Hidden(const FCk_Particles_StageResult& InOut) -> bool
    {
        return InOut.Color.A == 0.0f && InOut.Color.R == 0.0f && InOut.Color.G == 0.0f && InOut.Color.B == 0.0f
            && InOut.Size.IsNearlyZero() && InOut.Scale.IsNearlyZero();
    }

    // The source's own layer -> emitter partition, in emitter order (recipe §2/§6.1). Life is the SHORTEST the
    // layer can resolve to, so a mid-life sample is always inside it.
    struct FBand { int32 First; int32 Count; float Delay; float Life; int32 VisTag; const TCHAR* Name; };

    auto Get_Bands() -> TArrayView<const FBand>
    {
        static const FBand Bands[] =
        {
            {  0, 1, 0.0f,         0.1f,  kVisPart01,   TEXT("Glow_01")        },
            {  1, 1, 0.0f,         0.1f,  kVisPart01,   TEXT("Glow_02")        },
            {  2, 5, kDelayEarly,  0.05f, kVisPart02,   TEXT("Glow_03")        },
            {  7, 1, kDelayLate,   0.1f,  kVisRainbow,  TEXT("Raimbow")        },
            {  8, 5, kDelayLate,   0.2f,  kVisPart04,   TEXT("Sparkles_01")    },
            { 13, 1, kDelayLate,   0.5f,  kVisRing01,   TEXT("Ring")           },
            { 14, 5, kDelayLate,   0.2f,  kVisPart01,   TEXT("Glow_04")        },
            { 19, 3, kDelayLate,   0.1f,  kVisPart01Br, TEXT("Glow_05")        },
            { 22, 1, kDelayLate,   0.05f, kVisImpact01, TEXT("FlareImpact")    },
            { 23, 5, kDelayLate,   0.1f,  kVisSpike,    TEXT("Spike01")        },
            { 28, 5, kDelayLate,   0.1f,  kVisStrip,    TEXT("LightningStrip") },
            { 33, 1, kDelayLate,   0.3f,  kVisStar01,   TEXT("Star01")         },
            { 34, 1, kDelayStar02, 0.3f,  kVisStar02,   TEXT("Star02")         },
            { 35, 1, kDelayLate,   1.5f,  kVisWindMesh, TEXT("Wind_01")        },
            { 36, 6, kDelayLate,   1.5f,  kVisWindPuff, TEXT("Wind_02")        },
        };
        return MakeArrayView(Bands);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Particles_ArrowCastBehavior,
    "CkTests.UnitTests.CkParticles.ArrowCastBehavior",
    kCkUnitTestFlags)

bool FCkTest_Particles_ArrowCastBehavior::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_arrow_cast;

    // ---- The cadence row ----
    {
        TestEqual(TEXT("behavior 23 routes to the ArrowCast row"),
            ck::particles::Get_BehaviorTemplateSystemObjectPath(kBehaviorId),
            ck::particles::Get_ArrowCastTemplateSystemObjectPath());

        TestEqual(TEXT("behavior 23 binds no CkUsf look — all thirteen of its looks ride the row's renderers"),
            ck::particles::Get_BehaviorLookName(kBehaviorId), NAME_None);

        const auto* RowSpec = static_cast<const ck::particles::FCk_ParticlesTemplateSpec*>(nullptr);
        for (const auto& Spec : ck::particles::Get_TemplateSpecs())
        {
            if (FString(Spec.AssetName) == FString(kRowAssetName))
            { RowSpec = &Spec; break; }
        }

        if (TestNotNull(TEXT("the cadence table declares a PS_CkParticles_Template_ArrowCast row"), RowSpec))
        {
            TestEqual(TEXT("row loop duration matches the source SYSTEM's Loop-Once 2.0 s"),
                RowSpec->LoopDuration, kLoop, kTolerance);
            TestEqual(TEXT("row particle lifetime covers the Wind pair's 1.5 s life from its 0.05 s beat"),
                RowSpec->ParticleLifetime, kLifetime, kTolerance);
            TestEqual(TEXT("row burst count is the source's per-firing particle count"),
                RowSpec->BurstCount, kNumLayers);

            auto SawWindSheet  = false;
            auto MeshRenderers = 0;
            for (const auto& Renderer : RowSpec->RendererOverrides)
            {
                if (Renderer.VisTag == kVisWindPuff)
                { SawWindSheet = Renderer.SubImageSize == FIntPoint(2, 2); }
                if (Renderer.Kind == ck::particles::ECk_ParticlesRenderer_Kind::Mesh)
                { ++MeshRenderers; }
            }
            TestTrue(TEXT("the Wind_02 row renderer declares the source's 2x2 sub-UV grid"), SawWindSheet);
            TestEqual(TEXT("the row carries the source's three mesh carriers"), MeshRenderers, 3);
        }
    }

    // ---- The 42-slot partition maps every layer onto its source emitter's renderer ----
    {
        const auto RosterMax = ck::particles::Get_RosterVisTag_Max();
        TestTrue(TEXT("the roster VisTag maximum covers the ArrowCast row's renderers"),
            RosterMax >= kVisWindPuff);

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
        TestEqual(TEXT("the bands partition all 42 slots with no gap and no overlap"), Covered, kNumLayers);
    }

    // ---- Raimbow runs a Color module AND a Scale Color module ----
    // The Color module writes white over the Initialize grey and Scale Color halves it, so the layer is a flat
    // 0.5 grey. Reading it as the FireBall_Hit variant does — Initialize grey scaled by 0.5 — would put
    // 0.4565 there instead, and reading only the Color module would put white.
    {
        const auto Out = Evaluate(kDelayLate + 0.05f, Get_SeedForLayer(7, 0));
        TestEqual(TEXT("Raimbow red is the Color module's white, halved"), Out.Color.R, 0.5f, kTolerance);
        TestEqual(TEXT("Raimbow is achromatic"), Out.Color.R, Out.Color.B, kTolerance);
        TestEqual(TEXT("Raimbow pins dissolve at the source's 0.5"), Out.Dynamic.X, 0.5f, kTolerance);
    }

    // ---- Glow_03 is the one layer in the system with NO size curve ----
    // Its quad must hold the source's flat 150 for its whole 50 ms rather than growing.
    {
        const auto Seed = Get_SeedForLayer(2, 0);
        for (const auto Fraction : { 0.05f, 0.5f, 0.95f })
        {
            const auto Out = Evaluate(kDelayEarly + 0.05f * Fraction, Seed);
            TestEqual(TEXT("Glow_03 holds a constant 150-unit quad"), Out.Size.X, 150.0f, kTolerance);
        }
    }

    // ---- Sparkles_01: velocity-aligned streaks whose LENGTH tapers independently of their width ----
    {
        const auto Seed  = Get_SeedForLayer(8, 0);
        const auto Early = Evaluate(kDelayLate + 0.02f, Seed);
        const auto Late  = Evaluate(kDelayLate + 0.19f, Seed);

        TestTrue(TEXT("Sparkles_01 fires outward at the source's 1300-2000 units/s"),
            Early.Velocity.Size() > 400.0f);
        TestTrue(TEXT("Sparkles_01 decelerates over life"), Late.Velocity.Size() < Early.Velocity.Size());

        // Non-Uniform Curve Sprite Scale 001 tapers Y to 0.6 and leaves X alone, so the aspect ratio must move.
        const auto EarlyAspect = Early.Size.Y / FMath::Max(Early.Size.X, kTolerance);
        const auto LateAspect  = Late.Size.Y / FMath::Max(Late.Size.X, kTolerance);
        TestTrue(TEXT("Sparkles_01's length tapers relative to its width"), LateAspect < EarlyAspect);
    }

    // ---- Wind_01: the travelling tube. The only layer that moves off the origin under a fixed velocity, the
    // only mesh that spins, and the one carrying the renderer's (1,1,5) scale in its own Z ----
    {
        const auto Seed  = Get_SeedForLayer(35, 0);
        const auto Early = Evaluate(kDelayLate + 0.05f, Seed);
        const auto Late  = Evaluate(kDelayLate + 1.4f,  Seed);

        TestTrue(TEXT("Wind_01 travels down -X"), Late.Position.X < Early.Position.X && Late.Position.X < 0.0f);
        TestEqual(TEXT("Wind_01 does not drift off the X axis"), Late.Position.Y, 0.0f, kTolerance);

        TestTrue(TEXT("Wind_01 writes a normalized mesh orientation"), Early.Orientation.IsNormalized());
        TestTrue(TEXT("Wind_01 keeps spinning"),
            FMath::Abs(Late.Orientation.X - Early.Orientation.X) > kTolerance ||
            FMath::Abs(Late.Orientation.W - Early.Orientation.W) > kTolerance);

        // Mesh uniform scale 0.3 x the renderer's 5 x the curve's final 5 = 7.5 along the tube's own axis.
        const auto End = Evaluate(kDelayLate + 1.499f, Seed);
        TestEqual(TEXT("Wind_01's Z carries the renderer's (1,1,5) mesh scale"), End.Scale.Z, 7.5f, 1.0e-2f);
        TestTrue(TEXT("Wind_01 stretches far more along its axis than across it"), End.Scale.Z > End.Scale.X * 3.0f);
    }

    // ---- Wind_02: six sub-UV puffs sharing Wind_01's alpha envelope, sprayed down -X ----
    {
        const auto Seed = Get_SeedForLayer(36, 0);

        auto SeenFrames = TSet<int32>{};
        for (auto Step = 0; Step <= 20; ++Step)
        {
            const auto Out = Evaluate(kDelayLate + 1.5f * static_cast<float>(Step) / 20.0f, Seed);
            TestTrue(TEXT("Wind_02 sub-image index stays inside the 2x2 sheet"),
                Out.SubImageIndex >= 0.0f && Out.SubImageIndex <= 3.0f);
            SeenFrames.Add(FMath::FloorToInt32(Out.SubImageIndex));
        }
        TestTrue(TEXT("the Wind_02 flipbook actually advances over life"), SeenFrames.Num() > 1);

        // The alpha envelope fades IN — at spawn the puff is invisible, which no other layer in the system does.
        const auto AtSpawn = Evaluate(kDelayLate + 0.001f, Seed);
        const auto AtHold  = Evaluate(kDelayLate + 0.75f,  Seed);
        TestTrue(TEXT("Wind_02 fades in rather than starting lit"), AtSpawn.Color.A < AtHold.Color.A);

        auto Sum   = FVector3f::ZeroVector;
        auto Count = 0;
        for (auto Burst = 0; Burst < 24; ++Burst)
        {
            const auto Out = Evaluate(kDelayLate + 0.2f, Get_SeedForLayer(36, Burst));
            if (Is_Hidden(Out) || Out.Velocity.IsNearlyZero())
            { continue; }

            Sum += Out.Velocity.GetSafeNormal();
            ++Count;
        }
        TestTrue(TEXT("Wind_02 produced samples to average"), Count > 8);
        TestTrue(TEXT("Wind_02 sprays down -X rather than radially"), (Sum / static_cast<float>(Count)).X < -0.8f);
    }

    // ---- Spike01 faces its own velocity and drifts off a 20-unit SHELL ----
    // Its Sphere Location is Surface Only, so every pyramid starts exactly 20 units out — not inside a volume.
    {
        for (auto Index = 0; Index < 5; ++Index)
        {
            const auto Out = Evaluate(kDelayLate + 0.001f, Get_SeedForLayer(23 + Index, 0));

            TestEqual(TEXT("Spike01 spawns on the 20-unit shell"), Out.Position.Size(), 20.0f, 5.0e-2f);
            TestTrue(TEXT("Spike01's orientation points down its own velocity"),
                FVector3f::DotProduct(Out.Orientation.RotateVector(FVector3f(0.0f, 0.0f, 1.0f)),
                                      Out.Velocity.GetSafeNormal()) > 0.99f);
            TestTrue(TEXT("Spike01 draws no sprite quad"), Out.Size.IsNearlyZero());
        }
    }

    // ---- LightningStrip: five cards at the cast point, told apart only by facing ----
    {
        auto Orientations = TSet<uint32>{};
        for (auto Index = 0; Index < 5; ++Index)
        {
            const auto Out = Evaluate(kDelayLate + 0.05f, Get_SeedForLayer(28 + Index, 0));

            TestTrue(TEXT("LightningStrip sits at the cast point"), Out.Position.IsNearlyZero());
            TestTrue(TEXT("LightningStrip writes a normalized mesh orientation"), Out.Orientation.IsNormalized());
            TestTrue(TEXT("LightningStrip draws no sprite quad"), Out.Size.IsNearlyZero());
            Orientations.Add(GetTypeHash(Out.Orientation.X) ^ GetTypeHash(Out.Orientation.Y));
        }
        TestEqual(TEXT("all five lightning cards face differently"), Orientations.Num(), 5);
    }

    // ---- The two stars share a colour ramp and a size curve but not their dissolve ----
    {
        const auto Star01 = Evaluate(kDelayLate + 0.15f, Get_SeedForLayer(33, 0));
        const auto Star02 = Evaluate(kDelayStar02 + 0.15f, Get_SeedForLayer(34, 0));

        TestEqual(TEXT("Star01 holds the source's constant dissolve of 1"), Star01.Dynamic.X, 1.0f, kTolerance);
        TestTrue(TEXT("Star02 assembles rather than holding"), Star02.Dynamic.X < 0.0f);
        TestTrue(TEXT("Star02 is the larger of the two"), Star02.Size.X > Star01.Size.X);
    }

    // ---- Kinematics: the cast's own sparkle spray is OMNIDIRECTIONAL ----
    {
        auto Sum   = FVector3f::ZeroVector;
        auto Count = 0;
        for (auto Burst = 0; Burst < 24; ++Burst)
        {
            const auto Out = Evaluate(kDelayLate + 0.06f, Get_SeedForLayer(8, Burst));
            if (Is_Hidden(Out) || Out.Velocity.IsNearlyZero())
            { continue; }

            Sum += Out.Velocity.GetSafeNormal();
            ++Count;
        }

        TestTrue(TEXT("Sparkles_01 produced samples to average"), Count > 8);
        TestTrue(TEXT("Sparkles_01 fires radially, not down a cone"),
            (Sum / static_cast<float>(Count)).Size() < 0.5f);
    }

    // ---- Anti-vacuity: every layer contributes visible light somewhere in its life ----
    for (const auto& Band : Get_Bands())
    {
        for (auto Index = 0; Index < Band.Count; ++Index)
        {
            const auto Layer = Band.First + Index;
            auto PeakLuminance = 0.0f;

            for (auto Step = 0; Step <= 80; ++Step)
            {
                const auto Out = Evaluate(kLifetime * static_cast<float>(Step) / 80.0f, Get_SeedForLayer(Layer, 0));
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

    for (auto Layer = 0; Layer < kNumLayers; ++Layer)
    {
        for (auto Burst = 0; Burst < 8; ++Burst)
        {
            TestTrue(*FString::Printf(TEXT("layer %d is dead past the row's 1.55 s lifetime"), Layer),
                Is_Hidden(Evaluate(kLifetime + 0.001f, Get_SeedForLayer(Layer, Burst))));
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
