// Behavior-math gate for CkParticles BehaviorId 25 (BombSpawn) — the Vefects NS_Bomb_Spawn recreation.
//
// Drives UCkParticles_DataInterface::Execute_Stage_CPU, the SAME CPU mirror a CPU sim runs, so it needs no
// Niagara system, no template asset, no RHI and no forked engine.
//
// Expected values are the SOURCE's own values as transcribed in
// CkFoundation/Source/CkParticles/Cookbook/NS_Bomb_Spawn.md §2/§5 — not values read back out of the
// implementation. The clamped-key lerp is re-implemented here on purpose: the KEYS are the fidelity claim.
//
// This is the only port in the cookbook whose mesh layer is a PROP rather than a particle carrier, so the
// bomb's own assertions — the 5x flash, the pop, the decaying spin — carry most of the weight here.
//
// Cannot pass vacuously: behavior 25's VisTags are 62..70 and the pre-switch default is 0.

#include "Misc/AutomationTest.h"

#include "CkParticles/DataInterface/CkParticles_DataInterface.h"
#include "CkParticles/ScriptDefinition/CkParticles_ScriptDefinition_Naming.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_particles_bomb_spawn
{
    constexpr auto kBehaviorId = 25;
    constexpr auto kTolerance  = 1.0e-4f;

    // Source facts (recipe §2/§6.1 against corpus v3). The burst count is the SUM of the §2 count column: the
    // sheet's prose total of 27 is an arithmetic slip against its own itemization, which the corpus confirms
    // sums to 28 (recipe §14).
    constexpr auto kNumLayers = 28;
    constexpr auto kLifetime  = 1.05f; // the 1.0 s glows off the 0.05 s beat
    constexpr auto kLoop      = 2.0f;

    constexpr auto kDelayMid  = 0.05f;
    constexpr auto kDelayLate = 0.1f;

    constexpr auto kRowAssetName = TEXT("PS_CkParticles_Template_BombSpawn");

    constexpr auto kVisPart01   = 62;
    constexpr auto kVisRainbow  = 63;
    constexpr auto kVisPart01Br = 64;
    constexpr auto kVisRing01   = 65;
    constexpr auto kVisPart02   = 66;
    constexpr auto kVisBomb     = 67;
    constexpr auto kVisStar03   = 68;
    constexpr auto kVisPart03   = 69;
    constexpr auto kVisPart03Br = 70;

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

    struct FBand { int32 First; int32 Count; float Delay; float Life; int32 VisTag; const TCHAR* Name; };

    auto Get_Bands() -> TArrayView<const FBand>
    {
        static const FBand Bands[] =
        {
            {  0, 1,  0.0f,       1.0f,  kVisPart01,   TEXT("Glow_01")            },
            {  1, 1,  0.0f,       1.0f,  kVisPart01,   TEXT("Glow_02")            },
            {  2, 3,  kDelayMid,  1.0f,  kVisPart01,   TEXT("Glow_03")            },
            {  5, 1,  kDelayLate, 0.3f,  kVisRainbow,  TEXT("Raimbow")            },
            {  6, 10, kDelayMid,  0.5f,  kVisPart01Br, TEXT("Sparkles")           },
            { 16, 1,  kDelayMid,  0.75f, kVisRing01,   TEXT("Ring01")             },
            { 17, 1,  kDelayLate, 0.5f,  kVisPart02,   TEXT("Flash_Glow_01")      },
            { 18, 1,  kDelayLate, 0.5f,  kVisPart02,   TEXT("Flash_Glow_02")      },
            { 19, 3,  kDelayMid,  1.0f,  kVisPart01,   TEXT("Bomb_Glow")          },
            { 22, 1,  0.0f,       1.0f,  kVisBomb,     TEXT("Bomb")               },
            { 23, 1,  0.0f,       0.3f,  kVisStar03,   TEXT("Flare_Stretched_04") },
            { 24, 2,  0.0f,       0.7f,  kVisPart03,   TEXT("Flare_Stretched_03") },
            { 26, 1,  0.0f,       0.5f,  kVisPart03Br, TEXT("Flare_Stretched_02") },
            { 27, 1,  0.0f,       0.5f,  kVisPart01,   TEXT("Flare_Stretched_01") },
        };
        return MakeArrayView(Bands);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Particles_BombSpawnBehavior,
    "CkTests.UnitTests.CkParticles.BombSpawnBehavior",
    kCkUnitTestFlags)

bool FCkTest_Particles_BombSpawnBehavior::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_bomb_spawn;

    // ---- The cadence row ----
    {
        TestEqual(TEXT("behavior 25 routes to the BombSpawn row"),
            ck::particles::Get_BehaviorTemplateSystemObjectPath(kBehaviorId),
            ck::particles::Get_BombSpawnTemplateSystemObjectPath());

        TestEqual(TEXT("behavior 25 binds no CkUsf look — all nine of its renderers bind their own"),
            ck::particles::Get_BehaviorLookName(kBehaviorId), NAME_None);

        const auto* RowSpec = static_cast<const ck::particles::FCk_ParticlesTemplateSpec*>(nullptr);
        for (const auto& Spec : ck::particles::Get_TemplateSpecs())
        {
            if (FString(Spec.AssetName) == FString(kRowAssetName))
            { RowSpec = &Spec; break; }
        }

        if (TestNotNull(TEXT("the cadence table declares a PS_CkParticles_Template_BombSpawn row"), RowSpec))
        {
            TestEqual(TEXT("row loop duration matches the source SYSTEM's Loop-Once 2.0 s"),
                RowSpec->LoopDuration, kLoop, kTolerance);
            TestEqual(TEXT("row particle lifetime covers the 1.0 s glows from their 0.05 s beat"),
                RowSpec->ParticleLifetime, kLifetime, kTolerance);
            TestEqual(TEXT("row burst count is the source's per-firing particle count"),
                RowSpec->BurstCount, kNumLayers);

            // The prop is the only mesh in this system, and it is the cookbook's only OPAQUE one.
            auto MeshRenderers = 0;
            auto PropIsBanded  = false;
            for (const auto& Renderer : RowSpec->RendererOverrides)
            {
                if (Renderer.Kind != ck::particles::ECk_ParticlesRenderer_Kind::Mesh)
                { continue; }

                ++MeshRenderers;
                PropIsBanded = FString(Renderer.LookName) == TEXT("BombToon")
                            && FString(Renderer.MeshName) == TEXT("Bomb");
            }
            TestEqual(TEXT("the row carries exactly one mesh carrier — the prop"), MeshRenderers, 1);
            TestTrue(TEXT("the prop draws the toon-banded look on the generated bomb mesh"), PropIsBanded);
        }
    }

    // ---- The 28-slot partition maps every layer onto its source emitter's renderer ----
    {
        const auto RosterMax = ck::particles::Get_RosterVisTag_Max();
        TestTrue(TEXT("the roster VisTag maximum covers the BombSpawn row's renderers"),
            RosterMax >= kVisPart03Br);

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
        TestEqual(TEXT("the bands partition all 28 slots with no gap and no overlap"), Covered, kNumLayers);
    }

    // ---- The prop: a 5x white flash that collapses to a quarter, a pop from nothing, and a decaying spin ----
    {
        const auto Seed  = Get_SeedForLayer(22, 0);
        const auto Flash = Evaluate(0.1f,  Seed);  // inside the held 5x plateau
        const auto Settle= Evaluate(0.6f,  Seed);  // long past the 0.256 s drop

        TestEqual(TEXT("the prop holds the source's 5x white flash"), Flash.Color.R, 5.0f, kTolerance);
        TestEqual(TEXT("the prop is achromatic"), Flash.Color.R, Flash.Color.B, kTolerance);
        TestEqual(TEXT("the prop settles at the source's 0.25"), Settle.Color.R, 0.25f, kTolerance);

        const auto AtSpawn = Evaluate(0.0f, Seed);
        const auto AtPop   = Evaluate(0.2f, Seed);
        TestEqual(TEXT("the prop pops from nothing"), AtSpawn.Scale.X, 0.0f, kTolerance);
        TestEqual(TEXT("the prop reaches the source's 0.45 mesh scale"), AtPop.Scale.X, 0.45f, 1.0e-3f);
        TestTrue(TEXT("the prop scales uniformly"),
            FMath::IsNearlyEqual(AtPop.Scale.X, AtPop.Scale.Z, kTolerance));
        TestTrue(TEXT("the prop draws no sprite quad"), AtSpawn.Size.IsNearlyZero());

        // Rotation Rate runs 5 turns/s at spawn to a dead stop by half-life, so the yaw must advance early and
        // then hold. Integrating it stepwise instead would tie the spin to frame cadence.
        const auto Early = Evaluate(0.10f, Seed);
        const auto Mid   = Evaluate(0.55f, Seed);
        const auto Stop  = Evaluate(0.95f, Seed);
        TestTrue(TEXT("the prop's orientation is normalized"), Early.Orientation.IsNormalized());
        TestTrue(TEXT("the prop spins early"),
            FMath::Abs(Mid.Orientation.Z - Early.Orientation.Z) > kTolerance ||
            FMath::Abs(Mid.Orientation.W - Early.Orientation.W) > kTolerance);
        TestEqual(TEXT("the prop's spin has stopped by half-life (Z)"), Stop.Orientation.Z, Mid.Orientation.Z, 1.0e-3f);
        TestEqual(TEXT("the prop's spin has stopped by half-life (W)"), Stop.Orientation.W, Mid.Orientation.W, 1.0e-3f);
    }

    // ---- Bomb_Glow's Scale Color module is DISABLED, so its alpha never fades ----
    // Every other Part01 glow in the system runs the shared 1 -> 0 fade; implementing the disabled module would
    // dim the three sprites that hug the prop for the whole second.
    {
        const auto Seed  = Get_SeedForLayer(19, 0);
        const auto Early = Evaluate(kDelayMid + 0.05f, Seed);
        const auto Late  = Evaluate(kDelayMid + 0.95f, Seed);

        TestEqual(TEXT("Bomb_Glow holds the source's 0.5 alpha at the start"), Early.Color.A, 0.5f, kTolerance);
        TestEqual(TEXT("Bomb_Glow still holds it at death"),                   Late.Color.A,  0.5f, kTolerance);

        // Glow_01 is the control: same paint, same colour, but its Scale Color module is enabled.
        const auto ControlEarly = Evaluate(0.05f, Get_SeedForLayer(0, 0));
        const auto ControlLate  = Evaluate(0.95f, Get_SeedForLayer(0, 0));
        TestTrue(TEXT("Glow_01 by contrast DOES fade"), ControlLate.Color.A < ControlEarly.Color.A);
    }

    // ---- Ring01 is the only layer whose dissolve starts fully ERODED at +1 and assembles to -1 ----
    {
        const auto Seed  = Get_SeedForLayer(16, 0);
        const auto Start = Evaluate(kDelayMid + 0.0001f, Seed);
        const auto End   = Evaluate(kDelayMid + 0.7499f, Seed);

        TestEqual(TEXT("Ring01 opens at dissolve +1"), Start.Dynamic.X, 1.0f, 1.0e-3f);
        TestEqual(TEXT("Ring01 closes at dissolve -1"), End.Dynamic.X, -1.0f, 1.0e-3f);
        TestEqual(TEXT("Ring01's blue is pinned at 1 for its whole life"), End.Color.B, 1.0f, kTolerance);
        TestEqual(TEXT("Ring01's alpha is a single constant key"), End.Color.A, 1.0f, kTolerance);
    }

    // ---- The stretched flares: their LENGTH collapses to zero by t = 0.9 while their width holds ----
    {
        for (const auto Layer : { 23, 24, 26, 27 })
        {
            const auto Seed = Get_SeedForLayer(Layer, 0);
            const auto Life = Layer == 23 ? 0.3f : (Layer == 24 ? 0.7f : 0.5f);

            const auto Early = Evaluate(Life * 0.3f, Seed);
            const auto Gone  = Evaluate(Life * 0.9f, Seed);

            TestTrue(*FString::Printf(TEXT("flare layer %d is a wide streak, not a round quad"), Layer),
                Early.Size.X > Early.Size.Y * 2.0f);
            TestEqual(*FString::Printf(TEXT("flare layer %d collapses its length by t = 0.9"), Layer),
                Gone.Size.X, 0.0f, 1.0e-2f);
            TestTrue(*FString::Printf(TEXT("flare layer %d keeps its width past the collapse"), Layer),
                Gone.Size.Y > 1.0f);
        }

        // Flare_Stretched_03 is the widest thing in the system and the only flare driving a half dissolve.
        const auto Wide = Evaluate(0.1f, Get_SeedForLayer(24, 0));
        TestEqual(TEXT("Flare_Stretched_03 carries the source's 0.5 dissolve"), Wide.Dynamic.X, 0.5f, kTolerance);
    }

    // ---- Sparkles rise off a point source, radially ----
    {
        auto Sum   = FVector3f::ZeroVector;
        auto Count = 0;
        for (auto Burst = 0; Burst < 24; ++Burst)
        {
            const auto Out = Evaluate(kDelayMid + 0.1f, Get_SeedForLayer(6, Burst));
            if (Is_Hidden(Out) || Out.Velocity.IsNearlyZero())
            { continue; }

            TestTrue(TEXT("Sparkles never exceed the source's 500 units/s"), Out.Velocity.Size() <= 500.0f + kTolerance);
            Sum += Out.Velocity.GetSafeNormal();
            ++Count;
        }

        TestTrue(TEXT("Sparkles produced samples to average"), Count > 8);
        TestTrue(TEXT("Sparkles fire radially, not down a cone"), (Sum / static_cast<float>(Count)).Size() < 0.5f);
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
            TestTrue(*FString::Printf(TEXT("layer %d is dead past the row's 1.05 s lifetime"), Layer),
                Is_Hidden(Evaluate(kLifetime + 0.001f, Get_SeedForLayer(Layer, Burst))));
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
