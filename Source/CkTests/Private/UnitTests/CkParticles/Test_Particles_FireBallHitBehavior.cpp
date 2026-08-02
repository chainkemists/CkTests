// Behavior-math gate for CkParticles BehaviorId 21 (FireBallHit) — the Vefects NS_FireBall_Hit recreation.
//
// Drives UCkParticles_DataInterface::Execute_Stage_CPU, the SAME CPU mirror a CPU sim runs, so it needs no
// Niagara system, no template asset, no RHI and no forked engine.
//
// Expected values are the SOURCE's own values as transcribed in
// CkFoundation/Source/CkParticles/Cookbook/NS_FireBall_Hit.md §2/§5 — not values read back out of the
// implementation. The clamped-key lerp is re-implemented here on purpose: the KEYS are the fidelity claim.
//
// This is the widest port in the cookbook — seventeen enabled emitters over thirteen renderers — so the band
// table below is the test's centre of gravity: a drifted boundary silently collapses two source emitters onto
// one look, and reads as a missing layer rather than as an error.
//
// Cannot pass vacuously: behavior 21's VisTags are 15..27 and the pre-switch default is 0.

#include "Misc/AutomationTest.h"

#include "CkParticles/DataInterface/CkParticles_DataInterface.h"
#include "CkParticles/ScriptDefinition/CkParticles_ScriptDefinition_Naming.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_particles_fireball_hit
{
    constexpr auto kBehaviorId = 21;
    constexpr auto kTolerance  = 1.0e-4f;

    // Source facts (recipe §2/§5 against corpus v3).
    constexpr auto kNumLayers = 47;    // the ENABLED particle count; the three disabled emitters add 7 more
    constexpr auto kLifetime  = 1.34f; // Smokes' 1.3 s resolved life from a 0.04 s spawn beat
    constexpr auto kLoop      = 2.0f;

    constexpr auto kDelayEarly = 0.04f;
    constexpr auto kDelayLate  = 0.05f;

    constexpr auto kRowAssetName = TEXT("PS_CkParticles_Template_FireBallHit");

    constexpr auto kVisPart01   = 15;
    constexpr auto kVisPart01Br = 16;
    constexpr auto kVisPart03Br = 17;
    constexpr auto kVisPart04   = 18;
    constexpr auto kVisRing01   = 19;
    constexpr auto kVisRainbow  = 20;
    constexpr auto kVisStar01   = 21;
    constexpr auto kVisFlare01  = 22;
    constexpr auto kVisImpact01 = 23;
    constexpr auto kVisFlames01 = 24;
    constexpr auto kVisSmoke01  = 25;
    constexpr auto kVisSpike    = 26;
    constexpr auto kVisStrip    = 27;

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

    // The source's own layer -> emitter partition, in emitter order over the enabled set (recipe §2/§6.1).
    // Life is the SHORTEST the layer can resolve to, so a mid-life sample is always inside it.
    struct FBand { int32 First; int32 Count; float Delay; float Life; int32 VisTag; const TCHAR* Name; };

    auto Get_Bands() -> TArrayView<const FBand>
    {
        static const FBand Bands[] =
        {
            {  0, 1, 0.0f,        0.2f,  kVisRainbow,  TEXT("Raimbow")            },
            {  1, 1, 0.0f,        0.3f,  kVisRing01,   TEXT("Ring")               },
            {  2, 7, kDelayLate,  0.3f,  kVisPart01Br, TEXT("Sparkles")           },
            {  9, 1, 0.0f,        0.1f,  kVisPart01,   TEXT("Glow_01")            },
            { 10, 5, kDelayLate,  0.3f,  kVisPart04,   TEXT("Sparkles_Stretched") },
            { 15, 1, kDelayLate,  0.3f,  kVisStar01,   TEXT("Star_01")            },
            { 16, 1, 0.0f,        0.1f,  kVisPart01,   TEXT("Glow_02")            },
            { 17, 1, 0.0f,        0.1f,  kVisPart03Br, TEXT("SecondGlow")         },
            { 18, 3, kDelayLate,  0.1f,  kVisSpike,    TEXT("Spike01")            },
            { 21, 5, 0.0f,        0.2f,  kVisFlames01, TEXT("Flames01")           },
            { 26, 5, kDelayEarly, 0.7f,  kVisSmoke01,  TEXT("Smokes")             },
            { 31, 2, 0.0f,        0.2f,  kVisFlare01,  TEXT("Flare01")            },
            { 33, 4, kDelayEarly, 0.1f,  kVisPart03Br, TEXT("FirstFlash")         },
            { 37, 1, kDelayLate,  0.2f,  kVisPart01,   TEXT("FirstGlow")          },
            { 38, 1, kDelayLate,  0.05f, kVisImpact01, TEXT("FlareImpact")        },
            { 39, 5, 0.0f,        0.2f,  kVisStrip,    TEXT("LightningStrip")     },
            { 44, 3, kDelayLate,  0.1f,  kVisSpike,    TEXT("Spike02")            },
        };
        return MakeArrayView(Bands);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Particles_FireBallHitBehavior,
    "CkTests.UnitTests.CkParticles.FireBallHitBehavior",
    kCkUnitTestFlags)

bool FCkTest_Particles_FireBallHitBehavior::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_fireball_hit;

    // ---- The cadence row ----
    {
        TestEqual(TEXT("behavior 21 routes to the FireBallHit row"),
            ck::particles::Get_BehaviorTemplateSystemObjectPath(kBehaviorId),
            ck::particles::Get_FireBallHitTemplateSystemObjectPath());

        TestEqual(TEXT("behavior 21 binds no CkUsf look — all thirteen of its looks ride the row's renderers"),
            ck::particles::Get_BehaviorLookName(kBehaviorId), NAME_None);

        const auto* RowSpec = static_cast<const ck::particles::FCk_ParticlesTemplateSpec*>(nullptr);
        for (const auto& Spec : ck::particles::Get_TemplateSpecs())
        {
            if (FString(Spec.AssetName) == FString(kRowAssetName))
            { RowSpec = &Spec; break; }
        }

        if (TestNotNull(TEXT("the cadence table declares a PS_CkParticles_Template_FireBallHit row"), RowSpec))
        {
            TestEqual(TEXT("row loop duration matches the source SYSTEM's Loop-Once 2.0 s"),
                RowSpec->LoopDuration, kLoop, kTolerance);
            TestEqual(TEXT("row particle lifetime covers Smokes' 1.3 s life from its 0.04 s spawn beat"),
                RowSpec->ParticleLifetime, kLifetime, kTolerance);
            TestEqual(TEXT("row burst count is the source's ENABLED particle count"),
                RowSpec->BurstCount, kNumLayers);

            auto SawFlameSheet = false;
            auto MeshRenderers = 0;
            for (const auto& Renderer : RowSpec->RendererOverrides)
            {
                if (Renderer.VisTag == kVisFlames01)
                { SawFlameSheet = Renderer.SubImageSize == FIntPoint(2, 2); }
                if (Renderer.Kind == ck::particles::ECk_ParticlesRenderer_Kind::Mesh)
                { ++MeshRenderers; }
            }
            TestTrue(TEXT("the Flames01 row renderer declares the source's 2x2 sub-UV grid"), SawFlameSheet);
            TestEqual(TEXT("the row carries the source's two enabled mesh carriers"), MeshRenderers, 2);
        }
    }

    // ---- The 47-slot partition maps every layer onto its source emitter's renderer ----
    {
        const auto RosterMax = ck::particles::Get_RosterVisTag_Max();
        TestTrue(TEXT("the roster VisTag maximum covers the FireBallHit row's renderers"),
            RosterMax >= kVisStrip);

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
        TestEqual(TEXT("the bands partition all 47 slots with no gap and no overlap"), Covered, kNumLayers);
    }

    // ---- Raimbow is a SCALE COLOR module: its grey Initialize colour is halved, not replaced ----
    // Reading it as a Color-from-Curve layer would put a white ring where the source has a dim grey one.
    {
        const auto Out = Evaluate(0.1f, Get_SeedForLayer(0, 0));
        TestEqual(TEXT("Raimbow red is the Initialize grey scaled by 0.5"),
            Out.Color.R, 0.913099f * 0.5f, kTolerance);
        TestEqual(TEXT("Raimbow is achromatic"), Out.Color.R, Out.Color.B, kTolerance);
        TestEqual(TEXT("Raimbow pins dissolve at the source's 0.5"), Out.Dynamic.X, 0.5f, kTolerance);
    }

    // ---- SecondGlow is the one layer whose colour RISES over life, into a 3x HDR key ----
    {
        const auto Seed  = Get_SeedForLayer(17, 0);
        const auto Early = Evaluate(0.0f, Seed);
        const auto Late  = Evaluate(0.099f, Seed);

        TestEqual(TEXT("SecondGlow opens at the source's 2x red key"), Early.Color.R, 2.0f, kTolerance);
        TestTrue(TEXT("SecondGlow brightens rather than fades"), Late.Color.R > Early.Color.R);
        TestEqual(TEXT("SecondGlow reaches the source's 3x red key"),
            Late.Color.R, 3.0f, 1.0e-2f);
        TestEqual(TEXT("SecondGlow carries the batch's largest constant dissolve"),
            Early.Dynamic.X, 3.5f, kTolerance);
    }

    // ---- Flames01: HDR colour, a live distortion channel, and an advancing 2x2 flipbook ----
    {
        const auto Seed    = Get_SeedForLayer(21, 0);
        const auto AtSpawn = Evaluate(0.0f, Seed);

        TestEqual(TEXT("Flames01 red opens at the source's 5x HDR key"), AtSpawn.Color.R, 5.0f, kTolerance);
        TestEqual(TEXT("Flames01 distortion is the source's constant 5"), AtSpawn.Dynamic.Y, 5.0f, kTolerance);

        auto SeenFrames = TSet<int32>{};
        for (auto Step = 0; Step <= 20; ++Step)
        {
            const auto Out = Evaluate(0.2f * static_cast<float>(Step) / 20.0f, Seed);
            TestTrue(TEXT("Flames01 sub-image index stays inside the 2x2 sheet"),
                Out.SubImageIndex >= 0.0f && Out.SubImageIndex <= 3.0f);
            SeenFrames.Add(FMath::FloorToInt32(Out.SubImageIndex));
        }
        TestTrue(TEXT("the Flames01 flipbook actually advances over life"), SeenFrames.Num() > 1);
    }

    // ---- Smokes: the longest-lived layer, spreading along the GROUND PLANE ----
    // Its Sphere Location carries a Non Uniform Scale of (1, 1, 0), so the shell collapses to a ring in XY; a
    // port that ignored it would send smoke into a dome instead of outward across the floor.
    {
        for (auto Burst = 0; Burst < 12; ++Burst)
        {
            const auto Out = Evaluate(kDelayEarly + 0.3f, Get_SeedForLayer(26, Burst));
            if (Is_Hidden(Out))
            { continue; }

            TestEqual(TEXT("Smokes stays on the ground plane"), Out.Position.Z, 0.0f, kTolerance);
            TestEqual(TEXT("Smokes has no vertical velocity"), Out.Velocity.Z, 0.0f, kTolerance);
        }

        const auto Out = Evaluate(kDelayEarly + 0.3f, Get_SeedForLayer(26, 0));
        TestTrue(TEXT("Smokes drives the core_color channel the other layers leave alone"),
            FMath::Abs(Out.Dynamic.W) > kTolerance);
    }

    // ---- LightningStrip: five cards at the origin, each with its own facing ----
    // Its Sphere Location module is DISABLED in the source, so all five spawn at the impact point and are told
    // apart only by orientation — implementing the disabled module would fan them out into a shape the source
    // does not have.
    {
        auto Orientations = TSet<uint32>{};
        for (auto Index = 0; Index < 5; ++Index)
        {
            const auto Out = Evaluate(0.1f, Get_SeedForLayer(39 + Index, 0));

            TestTrue(TEXT("LightningStrip sits at the impact point"), Out.Position.IsNearlyZero());
            TestTrue(TEXT("LightningStrip writes a normalized mesh orientation"), Out.Orientation.IsNormalized());
            TestTrue(TEXT("LightningStrip draws no sprite quad"), Out.Size.IsNearlyZero());
            Orientations.Add(GetTypeHash(Out.Orientation.X) ^ GetTypeHash(Out.Orientation.Y));
        }
        TestEqual(TEXT("all five lightning cards face differently"), Orientations.Num(), 5);
    }

    // Both spike bands face their own velocity, and Spike02 is the larger of the two.
    {
        const auto Small = Evaluate(kDelayLate + 0.02f, Get_SeedForLayer(18, 0));
        const auto Large = Evaluate(kDelayLate + 0.02f, Get_SeedForLayer(44, 0));

        TestTrue(TEXT("Spike01's orientation points down its own velocity"),
            FVector3f::DotProduct(Small.Orientation.RotateVector(FVector3f(0.0f, 0.0f, 1.0f)),
                                  Small.Velocity.GetSafeNormal()) > 0.99f);
        TestTrue(TEXT("Spike02 is the larger pyramid"), Large.Scale.X > Small.Scale.X);
    }

    // ---- Kinematics: the hit is OMNIDIRECTIONAL — its sprays must cover the sphere, not a cone ----
    for (const auto Layer : { 2, 10, 21 })
    {
        auto Sum   = FVector3f::ZeroVector;
        auto Count = 0;
        for (auto Burst = 0; Burst < 24; ++Burst)
        {
            const auto Out = Evaluate(kDelayLate + 0.06f, Get_SeedForLayer(Layer, Burst));
            if (Is_Hidden(Out) || Out.Velocity.IsNearlyZero())
            { continue; }

            Sum += Out.Velocity.GetSafeNormal();
            ++Count;
        }

        TestTrue(*FString::Printf(TEXT("layer %d produced samples to average"), Layer), Count > 8);
        TestTrue(*FString::Printf(TEXT("layer %d fires radially, not down a cone"), Layer),
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
            TestTrue(*FString::Printf(TEXT("layer %d is dead past the row's 1.34 s lifetime"), Layer),
                Is_Hidden(Evaluate(kLifetime + 0.001f, Get_SeedForLayer(Layer, Burst))));
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
