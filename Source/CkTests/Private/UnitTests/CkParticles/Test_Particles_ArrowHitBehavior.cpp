// Behavior-math gate for CkParticles BehaviorId 24 (ArrowHit) — the Vefects NS_Arrow_Hit recreation.
//
// Drives UCkParticles_DataInterface::Execute_Stage_CPU, the SAME CPU mirror a CPU sim runs, so it needs no
// Niagara system, no template asset, no RHI and no forked engine.
//
// Expected values are the SOURCE's own values as transcribed in
// CkFoundation/Source/CkParticles/Cookbook/NS_Arrow_Hit.md §2/§5 — not values read back out of the
// implementation. The clamped-key lerp is re-implemented here on purpose: the KEYS are the fidelity claim.
//
// The system is NS_Arrow_Cast with two emitters removed, one added and a dozen numbers changed, so the
// assertions below concentrate on the DELTAS: a port that copied the Cast variant wholesale would pass a
// partition check and fail every one of them.
//
// Cannot pass vacuously: behavior 24's VisTags are 50..61 and the pre-switch default is 0.

#include "Misc/AutomationTest.h"

#include "CkParticles/DataInterface/CkParticles_DataInterface.h"
#include "CkParticles/ScriptDefinition/CkParticles_ScriptDefinition_Naming.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_particles_arrow_hit
{
    constexpr auto kBehaviorId = 24;
    constexpr auto kTolerance  = 1.0e-4f;

    // Source facts (recipe §2/§6.1 against corpus v3).
    constexpr auto kNumLayers = 34;
    constexpr auto kLifetime  = 0.55f; // the ring pair's 0.5 s life off the 0.05 s beat
    constexpr auto kLoop      = 2.0f;

    constexpr auto kDelayEarly  = 0.04f;
    constexpr auto kDelayLate   = 0.05f;
    constexpr auto kDelayStar02 = 0.1f;

    constexpr auto kRowAssetName = TEXT("PS_CkParticles_Template_ArrowHit");

    constexpr auto kVisPart01   = 50;
    constexpr auto kVisPart02   = 51;
    constexpr auto kVisRainbow  = 52;
    constexpr auto kVisPart04   = 53;
    constexpr auto kVisRing01   = 54;
    constexpr auto kVisPart01Br = 55;
    constexpr auto kVisImpact01 = 56;
    constexpr auto kVisSpike    = 57;
    constexpr auto kVisStrip    = 58;
    constexpr auto kVisStar01   = 59;
    constexpr auto kVisStar02   = 60;
    constexpr auto kVisRingFlat = 61;

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
            { 13, 1, kDelayLate,   0.5f,  kVisRing01,   TEXT("Ring_01")        },
            { 14, 5, kDelayLate,   0.2f,  kVisPart01,   TEXT("Glow_04")        },
            { 19, 1, kDelayLate,   0.07f, kVisPart01Br, TEXT("Glow_05")        },
            { 20, 1, kDelayLate,   0.05f, kVisImpact01, TEXT("FlareImpact")    },
            { 21, 5, kDelayLate,   0.1f,  kVisSpike,    TEXT("Spike01")        },
            { 26, 5, kDelayLate,   0.1f,  kVisStrip,    TEXT("LightningStrip") },
            { 31, 1, kDelayLate,   0.3f,  kVisStar01,   TEXT("Star01")         },
            { 32, 1, kDelayStar02, 0.3f,  kVisStar02,   TEXT("Star02")         },
            { 33, 1, kDelayLate,   0.5f,  kVisRingFlat, TEXT("Ring_02")        },
        };
        return MakeArrayView(Bands);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Particles_ArrowHitBehavior,
    "CkTests.UnitTests.CkParticles.ArrowHitBehavior",
    kCkUnitTestFlags)

bool FCkTest_Particles_ArrowHitBehavior::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_arrow_hit;

    // ---- The cadence row ----
    {
        TestEqual(TEXT("behavior 24 routes to the ArrowHit row"),
            ck::particles::Get_BehaviorTemplateSystemObjectPath(kBehaviorId),
            ck::particles::Get_ArrowHitTemplateSystemObjectPath());

        TestEqual(TEXT("behavior 24 binds no CkUsf look — all twelve of its renderers bind their own"),
            ck::particles::Get_BehaviorLookName(kBehaviorId), NAME_None);

        const auto* RowSpec = static_cast<const ck::particles::FCk_ParticlesTemplateSpec*>(nullptr);
        for (const auto& Spec : ck::particles::Get_TemplateSpecs())
        {
            if (FString(Spec.AssetName) == FString(kRowAssetName))
            { RowSpec = &Spec; break; }
        }

        if (TestNotNull(TEXT("the cadence table declares a PS_CkParticles_Template_ArrowHit row"), RowSpec))
        {
            TestEqual(TEXT("row loop duration matches the source SYSTEM's Loop-Once 2.0 s"),
                RowSpec->LoopDuration, kLoop, kTolerance);
            TestEqual(TEXT("row particle lifetime covers the ring pair's 0.5 s life from its 0.05 s beat"),
                RowSpec->ParticleLifetime, kLifetime, kTolerance);
            TestEqual(TEXT("row burst count is the source's per-firing particle count"),
                RowSpec->BurstCount, kNumLayers);

            // The removed Wind layers are the reason this row declares no sub-UV grid at all, and the added
            // Ring_02 is the reason it declares a custom-facing sprite — both are structural claims.
            auto SawCustomFacing = false;
            auto SawAnySheet     = false;
            auto MeshRenderers   = 0;
            for (const auto& Renderer : RowSpec->RendererOverrides)
            {
                if (Renderer.Kind == ck::particles::ECk_ParticlesRenderer_Kind::CustomFacingSprite)
                { SawCustomFacing = Renderer.VisTag == kVisRingFlat; }
                if (Renderer.SubImageSize.X > 0 || Renderer.SubImageSize.Y > 0)
                { SawAnySheet = true; }
                if (Renderer.Kind == ck::particles::ECk_ParticlesRenderer_Kind::Mesh)
                { ++MeshRenderers; }
            }
            TestTrue(TEXT("Ring_02 draws through a row-declared CUSTOM-FACING sprite"), SawCustomFacing);
            TestFalse(TEXT("no row renderer declares a sub-UV grid — this system has no flipbook"), SawAnySheet);
            TestEqual(TEXT("the row carries the source's two mesh carriers"), MeshRenderers, 2);
        }
    }

    // ---- The 34-slot partition maps every layer onto its source emitter's renderer ----
    {
        const auto RosterMax = ck::particles::Get_RosterVisTag_Max();
        TestTrue(TEXT("the roster VisTag maximum covers the ArrowHit row's renderers"),
            RosterMax >= kVisRingFlat);

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
        TestEqual(TEXT("the bands partition all 34 slots with no gap and no overlap"), Covered, kNumLayers);
    }

    // ---- Ring_01 and Ring_02 are the SAME ring drawn twice ----
    // Same paint, same size, same colour and dissolve curves; one billboards and one lies flat. If they ever
    // stop matching, the source's whole reason for carrying a second emitter is gone.
    {
        const auto Billboard = Evaluate(kDelayLate + 0.25f, Get_SeedForLayer(13, 0));
        const auto Flat      = Evaluate(kDelayLate + 0.25f, Get_SeedForLayer(33, 0));

        TestEqual(TEXT("both rings run the same quad size"), Flat.Size.X, Billboard.Size.X, kTolerance);
        TestEqual(TEXT("both rings run the same red"),   Flat.Color.R, Billboard.Color.R, kTolerance);
        TestEqual(TEXT("both rings run the same green"), Flat.Color.G, Billboard.Color.G, kTolerance);
        TestEqual(TEXT("both rings run the same dissolve"), Flat.Dynamic.X, Billboard.Dynamic.X, kTolerance);

        // Align Sprite to Mesh Orientation under a quarter turn about X: alignment (0,0,1) -> (0,-1,0) and
        // facing (0,10,0) normalized -> (0,0,1), i.e. a quad lying flat with a +Z normal. A missing alignment
        // makes CustomAlignment silently fall back to Unaligned, so both vectors must be non-degenerate.
        TestEqual(TEXT("Ring_02's sprite alignment is the rotated up axis"), Flat.SpriteAlignment.Y, -1.0f, kTolerance);
        TestEqual(TEXT("Ring_02's sprite facing is the rotated plane normal"), Flat.SpriteFacing.Z, 1.0f, kTolerance);
        TestTrue(TEXT("Ring_02's alignment/facing pair is non-degenerate"),
            Flat.SpriteAlignment.SizeSquared() > kTolerance && Flat.SpriteFacing.SizeSquared() > kTolerance);
        TestEqual(TEXT("Ring_02's alignment and facing are perpendicular"),
            FVector3f::DotProduct(Flat.SpriteAlignment, Flat.SpriteFacing), 0.0f, kTolerance);
    }

    // ---- Glow_01 opens COOLER than the Cast variant's white ----
    {
        const auto Out = Evaluate(0.0f, Get_SeedForLayer(0, 0));
        TestEqual(TEXT("Glow_01's green opens at the hit's own 0.947307"), Out.Color.G, 0.947307f, kTolerance);
        TestEqual(TEXT("Glow_01's blue opens at the hit's own 0.665387"),  Out.Color.B, 0.665387f, kTolerance);
        TestTrue(TEXT("Glow_01 is not the Cast variant's flat white"), Out.Color.B < 0.9f);
    }

    // ---- Glow_02 gained a full colour curve where the Cast variant only faded ----
    // It opens blue-dominant and snaps to white by t ~= 0.097; a Direct-Set read would hold one warm colour.
    {
        const auto Seed  = Get_SeedForLayer(1, 0);
        const auto Open  = Evaluate(0.0f,     Seed);
        const auto Snap  = Evaluate(0.00966f, Seed);

        TestEqual(TEXT("Glow_02 opens at the source's 0.318547 red"), Open.Color.R, 0.318547f, kTolerance);
        TestTrue(TEXT("Glow_02 opens blue-dominant"), Open.Color.B > Open.Color.R);
        TestEqual(TEXT("Glow_02 reaches white by t ~= 0.097"), Snap.Color.R, 1.0f, 1.0e-2f);
        TestEqual(TEXT("Glow_02 runs the hit's 200-unit quad, not the cast's 300"),
            Evaluate(0.05f, Seed).Size.X, 200.0f, kTolerance);
    }

    // ---- Glow_04 is dimmer here, and Glow_05 is a single 0.07 s pip rather than three at 0.1 ----
    {
        const auto Glow04 = Evaluate(kDelayLate + 0.0001f, Get_SeedForLayer(14, 0));
        TestEqual(TEXT("Glow_04 carries the hit's 0.2 alpha scale"), Glow04.Color.A, 0.2f, 1.0e-3f);

        TestTrue(TEXT("Glow_05 is dead past its 0.07 s life"),
            Is_Hidden(Evaluate(kDelayLate + 0.0701f, Get_SeedForLayer(19, 0))));
        TestFalse(TEXT("Glow_05 is alive inside its 0.07 s life"),
            Is_Hidden(Evaluate(kDelayLate + 0.05f, Get_SeedForLayer(19, 0))));
    }

    // ---- Spike01's pop is UNIFORM here, and its X mesh-scale range is inverted in the source ----
    {
        const auto Seed = Get_SeedForLayer(21, 0);
        const auto Pop  = Evaluate(kDelayLate + 0.02f, Seed); // t = 0.2, the curve's peak key

        TestTrue(TEXT("Spike01's orientation points down its own velocity"),
            FVector3f::DotProduct(Pop.Orientation.RotateVector(FVector3f(0.0f, 0.0f, 1.0f)),
                                  Pop.Velocity.GetSafeNormal()) > 0.99f);

        // Every axis is multiplied by the same 1.5 at t = 0.2, so the SHAPE at the pop is the base range's
        // shape — the Cast variant's 0.5 / 0.4 / 1 would skew it.
        for (auto Burst = 0; Burst < 6; ++Burst)
        {
            const auto Out = Evaluate(kDelayLate + 0.02f, Get_SeedForLayer(21, Burst));
            TestTrue(TEXT("Spike01's X scale stays inside the source's inverted 0.05..0.1 range"),
                Out.Scale.X >= 0.05f * 1.5f - kTolerance && Out.Scale.X <= 0.1f * 1.5f + kTolerance);
            TestTrue(TEXT("Spike01's Z scale stays inside the source's 0.2..0.5 range"),
                Out.Scale.Z >= 0.2f * 1.5f - kTolerance && Out.Scale.Z <= 0.5f * 1.5f + kTolerance);
        }
    }

    // ---- LightningStrip is dimmer here (0.15 against the cast's 0.4) and sits at the impact point ----
    {
        auto Orientations = TSet<uint32>{};
        for (auto Index = 0; Index < 5; ++Index)
        {
            const auto Out = Evaluate(kDelayLate + 0.05f, Get_SeedForLayer(26 + Index, 0));

            TestTrue(TEXT("LightningStrip sits at the impact point"), Out.Position.IsNearlyZero());
            TestTrue(TEXT("LightningStrip writes a normalized mesh orientation"), Out.Orientation.IsNormalized());
            TestTrue(TEXT("LightningStrip never exceeds the hit's 0.15 alpha scale"), Out.Color.A <= 0.15f + kTolerance);
            Orientations.Add(GetTypeHash(Out.Orientation.X) ^ GetTypeHash(Out.Orientation.Y));
        }
        TestEqual(TEXT("all five lightning cards face differently"), Orientations.Num(), 5);
    }

    // ---- Kinematics: the hit's sparkle spray is OMNIDIRECTIONAL ----
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
            TestTrue(*FString::Printf(TEXT("layer %d is dead past the row's 0.55 s lifetime"), Layer),
                Is_Hidden(Evaluate(kLifetime + 0.001f, Get_SeedForLayer(Layer, Burst))));
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
