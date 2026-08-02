// Behavior-math gate for CkParticles BehaviorId 44 (BombExplosion) — the Vefects NS_Bomb_Explosion
// recreation, and the cookbook's largest single burst at 162 particles over 23 emitters.
//
// Drives UCkParticles_DataInterface::Execute_Stage_CPU, the SAME CPU mirror a CPU sim runs, so it needs no
// Niagara system, no template asset, no RHI and no forked engine.
//
// Expected values are the SOURCE's own values as transcribed in
// CkFoundation/Source/CkParticles/Cookbook/NS_Bomb_Explosion.md §2/§5.
//
// The load-bearing claims specific to this port:
//   - the 162-particle partition IS the source's per-emitter counts, and it holds across moduli. 162 is
//     1.7x the largest burst any earlier row declared, so the partition is the first thing to check;
//   - the three spawn beats (0 / 0.05 / 0.1 s) gate their layers, and the whole effect is over by 0.5 s;
//   - the row consumes every C8 facing mode: the lightning card faces VELOCITY and all five bubbles face
//     CAMERAPOSITION. Those are RENDERER facts, so they are asserted on the row's renderer specs — the one
//     thing a behavior cannot express and therefore the one thing worth pinning;
//   - Sparkles_02 is the DEBRIS pass: gravity -7000, a 0.7 XY damping, and a Random Range Linear Color
//     under Link RGB / Link A, i.e. ONE draw lerping the whole triple rather than three independent ones;
//   - Sparkles_01's Color module is live and Sparkles_02's is DISABLED, so only one of the two ramps;
//   - Bubble_First_Explo's alpha ramps UP over life — the shell assembles rather than fading;
//   - Bubble_Out's scale curve has no third key, so it HOLDS at 1.5x past t = 0.7 instead of settling;
//   - the row declares no spawn rate and no ribbon, so behavior 44 must stay INDEPENDENT of the emitter
//     clock and must never write a ribbon VisTag.
//
// Cannot pass vacuously: behavior 44's VisTags are 210..224 and the pre-switch default is 0.

#include "Misc/AutomationTest.h"

#include "CkParticles/DataInterface/CkParticles_DataInterface.h"
#include "CkParticles/ScriptDefinition/CkParticles_ScriptDefinition_Naming.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_particles_bomb_explosion
{
    constexpr auto kBehaviorId = 44;
    constexpr auto kTolerance  = 1.0e-4f;

    // Source facts (recipe §2/§6.1 against corpus v3). Loop Once / 2.0 s system; the longest resolved
    // lifetime is Sparkles_01's 0.5 s ([P0-D2] moved this one from the pre-v3 0.3 s).
    constexpr auto kLoop     = 2.0f;
    constexpr auto kLifetime = 0.5f;
    constexpr auto kBurst    = 162;

    constexpr auto kRowAssetName = TEXT("PS_CkParticles_Template_BombExplosion");

    constexpr auto kVisPart01     = 210;
    constexpr auto kVisPart03     = 211;
    constexpr auto kVisPart02     = 212;
    constexpr auto kVisFlare      = 213;
    constexpr auto kVisRing       = 214;
    constexpr auto kVisImpact     = 215;
    constexpr auto kVisGroundGlow = 216;
    constexpr auto kVisPart04     = 217;
    constexpr auto kVisSpike      = 218;
    constexpr auto kVisStrip      = 219;
    constexpr auto kVisBubNoise01 = 220;
    constexpr auto kVisBubFirst   = 221;
    constexpr auto kVisBubOut     = 222;
    constexpr auto kVisBubNoise02 = 223;
    constexpr auto kVisBubFresnel = 224;

    // Burst slots, from the §2 emitter order.
    constexpr auto kSlotRing01     = 4;
    constexpr auto kSlotSpike03    = 26;   // the only spike band with a colour ramp
    constexpr auto kSlotGlow05     = 38;
    constexpr auto kSlotImpact     = 40;
    constexpr auto kSlotSparkles01 = 46;
    constexpr auto kSlotSparkles02 = 96;
    constexpr auto kSlotBubNoise01 = 157;
    constexpr auto kSlotBubFirst   = 158;
    constexpr auto kSlotBubOut     = 159;
    constexpr auto kSlotBubNoise02 = 160;
    constexpr auto kSlotBubFresnel = 161;

    auto Evaluate(float InAge, int32 InSeed, float InEmitterAge) -> FCk_Particles_StageResult
    {
        constexpr auto DeltaTime = 1.0f / 60.0f;

        return UCkParticles_DataInterface::Execute_Stage_CPU(
            kBehaviorId, DeltaTime, InAge, kLifetime,
            FVector3f::ZeroVector, FVector3f::ZeroVector, InSeed, InEmitterAge);
    }

    auto Evaluate(float InAge, int32 InSeed) -> FCk_Particles_StageResult
    {
        return Evaluate(InAge, InSeed, InAge);
    }

    auto Is_Hidden(const FCk_Particles_StageResult& InOut) -> bool
    {
        return InOut.Color.A == 0.0f && InOut.Color.R == 0.0f && InOut.Color.G == 0.0f && InOut.Color.B == 0.0f
            && InOut.Size.IsNearlyZero() && InOut.Scale.IsNearlyZero();
    }

    // A layer that has not reached its spawn beat, or has outlived its own lifetime, leaves its branch
    // through the early Hide()/return - which runs BEFORE that branch assigns Out.VisTag, so the result
    // carries the switch's pre-branch default of 0. Harmless on screen (a hidden particle has zero colour,
    // size and scale) but it means a partition census must read each slot while it is ALIVE. This system is
    // the worst case in the cookbook for it: three spawn beats, a 0.05 s layer, a 0.1 s layer, and five
    // cards whose lifetime is a random 0.1-0.15 s, so NO single instant sees all 23 emitters.
    //
    // Sweeping the loop is strictly stronger than the single-instant read it replaces: it also proves every
    // slot draws at some point and that each keeps ONE renderer for its whole life.
    constexpr auto kCensusSpan  = 0.6f;   // past the longest layer's death (Sparkles_01, 0.05 + 0.5 s)
    constexpr auto kCensusSteps = 240;

    struct FLiveTag
    {
        int32 Tag        = INDEX_NONE;
        bool  Consistent = true;
    };

    auto Get_LiveVisTag(int32 InSeed) -> FLiveTag
    {
        auto Result = FLiveTag{};

        for (auto Step = 0; Step <= kCensusSteps; ++Step)
        {
            const auto Out = Evaluate(kCensusSpan * float(Step) / float(kCensusSteps), InSeed);
            if (Is_Hidden(Out))
            { continue; }

            if (Result.Tag == INDEX_NONE)      { Result.Tag = Out.VisTag; }
            else if (Result.Tag != Out.VisTag) { Result.Consistent = false; }
        }
        return Result;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Particles_BombExplosionBehavior,
    "CkTests.UnitTests.CkParticles.BombExplosionBehavior",
    kCkUnitTestFlags)

bool FCkTest_Particles_BombExplosionBehavior::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_bomb_explosion;

    // ---- The cadence row, and the facing modes only a RENDERER can carry ----
    {
        TestEqual(TEXT("behavior 44 routes to the BombExplosion row"),
            ck::particles::Get_BehaviorTemplateSystemObjectPath(kBehaviorId),
            ck::particles::Get_BombExplosionTemplateSystemObjectPath());

        TestEqual(TEXT("behavior 44 binds no CkUsf look — all fifteen ride the row's renderers"),
            ck::particles::Get_BehaviorLookName(kBehaviorId), NAME_None);

        const auto* RowSpec = static_cast<const ck::particles::FCk_ParticlesTemplateSpec*>(nullptr);
        for (const auto& Spec : ck::particles::Get_TemplateSpecs())
        {
            if (FString(Spec.AssetName) == FString(kRowAssetName))
            { RowSpec = &Spec; break; }
        }

        if (TestNotNull(TEXT("the cadence table declares a PS_CkParticles_Template_BombExplosion row"), RowSpec))
        {
            TestEqual(TEXT("row loop duration is the system's Loop Once / 2.0 s"),
                RowSpec->LoopDuration, kLoop, kTolerance);
            TestEqual(TEXT("row particle lifetime is Sparkles_01's resolved 0.5 s"),
                RowSpec->ParticleLifetime, kLifetime, kTolerance);
            TestEqual(TEXT("row burst is 162 — every emitter is a Spawn Burst Instantaneous"),
                RowSpec->BurstCount, kBurst);
            TestEqual(TEXT("the row declares NO spawn rate"), RowSpec->SpawnRate, 0.0f, kTolerance);
            TestFalse(TEXT("the row declares NO ribbon emitter — this source has no trail"),
                RowSpec->RibbonEmitter.Get_IsDeclared());
            TestEqual(TEXT("the row declares fifteen renderers"), RowSpec->RendererOverrides.Num(), 15);

            using EKind   = ck::particles::ECk_ParticlesRenderer_Kind;
            using EFacing = ck::particles::ECk_ParticlesRenderer_MeshFacing;

            auto Meshes         = 0;
            auto CameraPosition = 0;
            auto VelocityFacing = 0;
            auto NonMeshFacing  = 0;

            for (const auto& Renderer : RowSpec->RendererOverrides)
            {
                if (Renderer.Kind == EKind::Mesh)
                {
                    ++Meshes;
                    if (Renderer.MeshFacingMode == EFacing::CameraPosition) { ++CameraPosition; }
                    if (Renderer.MeshFacingMode == EFacing::Velocity)       { ++VelocityFacing; }
                }
                else if (Renderer.MeshFacingMode != EFacing::Default
                      || NOT Renderer.MeshScale.Equals(FVector::OneVector))
                {
                    ++NonMeshFacing;
                }

                if (Renderer.VisTag == kVisStrip)
                {
                    TestTrue(TEXT("the lightning card faces VELOCITY"),
                        Renderer.MeshFacingMode == EFacing::Velocity);
                    TestEqual(TEXT("...on the Card carrier"), FString(Renderer.MeshName), FString(TEXT("Card")));
                }
                if (Renderer.VisTag == kVisBubOut)
                {
                    TestTrue(TEXT("the shock ring faces CAMERAPOSITION — a flat annulus edge-on is invisible"),
                        Renderer.MeshFacingMode == EFacing::CameraPosition);
                    TestEqual(TEXT("...on the FlatAnnulus carrier"),
                        FString(Renderer.MeshName), FString(TEXT("FlatAnnulus")));
                    TestEqual(TEXT("...at the source's Mesh Uniform Scale 3"),
                        static_cast<float>(Renderer.MeshScale.X), 3.0f, KINDA_SMALL_NUMBER);
                }
            }

            TestEqual(TEXT("seven of the fifteen renderers are meshes — the cookbook's heaviest mesh load"),
                Meshes, 7);
            TestEqual(TEXT("all five bubbles face CameraPosition"), CameraPosition, 5);
            TestEqual(TEXT("exactly one renderer faces Velocity"),  VelocityFacing, 1);
            TestEqual(TEXT("no sprite renderer states a facing mode or a mesh scale"), NonMeshFacing, 0);
        }
    }

    // ---- The 162-particle partition IS the source's per-emitter counts ----
    {
        auto Tags         = TMap<int32, int32>{};
        auto NeverDrawn   = 0;
        auto Inconsistent = 0;

        for (auto Seed = 0; Seed < kBurst; ++Seed)
        {
            const auto Live = Get_LiveVisTag(Seed);

            if (Live.Tag == INDEX_NONE)
            { ++NeverDrawn; continue; }

            if (NOT Live.Consistent)
            { ++Inconsistent; }

            Tags.FindOrAdd(Live.Tag) += 1;
        }

        TestEqual(TEXT("every one of the 162 burst slots draws at some point in the loop"), NeverDrawn, 0);
        TestEqual(TEXT("...and each slot keeps ONE renderer for its whole life"), Inconsistent, 0);

        TestEqual(TEXT("Part01 draws Glow_01/02/03/04 — six particles over four emitters"),
            Tags.FindRef(kVisPart01), 6);
        TestEqual(TEXT("Part03 draws Glow_05 alone"),          Tags.FindRef(kVisPart03),     1);
        TestEqual(TEXT("Part02 draws both five-pip flares"),   Tags.FindRef(kVisPart02),     10);
        TestEqual(TEXT("Flare01 draws the one warm pip"),      Tags.FindRef(kVisFlare),      1);
        TestEqual(TEXT("Ring01 is one particle"),              Tags.FindRef(kVisRing),       1);
        TestEqual(TEXT("FlareImpact is one particle"),         Tags.FindRef(kVisImpact),     1);
        TestEqual(TEXT("both ground decals share one quad"),   Tags.FindRef(kVisGroundGlow), 2);
        TestEqual(TEXT("the two sparkle bursts are 100 of the 162"), Tags.FindRef(kVisPart04), 100);
        TestEqual(TEXT("the three spike bands are 30 meshes"), Tags.FindRef(kVisSpike),      30);
        TestEqual(TEXT("LightningStrip bursts five"),          Tags.FindRef(kVisStrip),      5);
        TestEqual(TEXT("each bubble is exactly one particle (Noise01)"),  Tags.FindRef(kVisBubNoise01), 1);
        TestEqual(TEXT("each bubble is exactly one particle (First)"),    Tags.FindRef(kVisBubFirst),   1);
        TestEqual(TEXT("each bubble is exactly one particle (Out)"),      Tags.FindRef(kVisBubOut),     1);
        TestEqual(TEXT("each bubble is exactly one particle (Noise02)"),  Tags.FindRef(kVisBubNoise02), 1);
        TestEqual(TEXT("each bubble is exactly one particle (Fresnel)"),  Tags.FindRef(kVisBubFresnel), 1);

        auto Total = 0;
        for (const auto& Pair : Tags)
        {
            TestTrue(TEXT("every populated bucket is one of behavior 44's own VisTags"),
                Pair.Key >= kVisPart01 && Pair.Key <= kVisBubFresnel);
            Total += Pair.Value;
        }
        TestEqual(TEXT("every one of the 162 slots draws through a declared renderer"), Total, kBurst);

        auto WideSparkles = 0;
        for (auto Seed = 0; Seed < kBurst * 40; ++Seed)
        {
            if (Evaluate(0.12f, Seed).VisTag == kVisPart04)
            { ++WideSparkles; }
        }
        TestEqual(TEXT("the partition holds across 40 moduli"), WideSparkles, 100 * 40);
    }

    // ---- The three spawn beats gate their layers, and the whole effect is over by 0.5 s ----
    {
        // FlareImpact fires at t = 0 and lives 0.05 s; Glow_05 waits for the 0.05 s beat; the Flare pips
        // wait for the 0.1 s one.
        TestFalse(TEXT("FlareImpact is alive at t = 0.01"), Is_Hidden(Evaluate(0.01f, kSlotImpact)));
        TestTrue(TEXT("...and gone by t = 0.06"),           Is_Hidden(Evaluate(0.06f, kSlotImpact)));

        TestTrue(TEXT("Glow_05 has not spawned at t = 0.01"),  Is_Hidden(Evaluate(0.01f, kSlotGlow05)));
        TestFalse(TEXT("...and is alive just past its beat"),  Is_Hidden(Evaluate(0.08f, kSlotGlow05)));

        // The row's 0.5 s lifetime IS Sparkles_01's resolved Lifetime Max (§6.1), and Sparkles_01 fires off
        // the 0.05 s beat — so the effect's true tail is 0.55 s and the ONLY thing alive at 0.45 s is that
        // one layer. Everything else is a 0.3 s bubble off a 0.1 s beat, or shorter.
        auto AliveAtLateAge = 0;
        auto NonSparkleLate = 0;
        for (auto Seed = 0; Seed < kBurst; ++Seed)
        {
            const auto Out = Evaluate(0.45f, Seed);
            if (Is_Hidden(Out))
            { continue; }

            ++AliveAtLateAge;
            if (Out.VisTag != kVisPart04)
            { ++NonSparkleLate; }
        }

        TestTrue(TEXT("something IS still alive at 0.45 s — the row's 0.5 s lifetime is not decorative"),
            AliveAtLateAge > 0);
        TestEqual(TEXT("...and it is ONLY Sparkles_01, whose resolved life reaches 0.5 s off a 0.05 s beat"),
            NonSparkleLate, 0);

        auto AlivePastTail = 0;
        for (auto Seed = 0; Seed < kBurst; ++Seed)
        {
            if (NOT Is_Hidden(Evaluate(0.56f, Seed)))
            { ++AlivePastTail; }
        }
        TestEqual(TEXT("nothing at all survives past 0.55 s — the 0.05 s beat plus the 0.5 s max life"),
            AlivePastTail, 0);
    }

    // ---- Ring01: 0.1 s of life and a dissolve that runs the full +1 -> -1 sweep inside it ----
    {
        const auto Head = Evaluate(0.0f, kSlotRing01);
        const auto Tail = Evaluate(0.0999f, kSlotRing01);

        TestEqual(TEXT("Ring01 draws on the ring quad"), Head.VisTag, kVisRing);
        TestEqual(TEXT("its dissolve opens fully intact"), Head.Dynamic.X, 1.0f, kTolerance);
        TestEqual(TEXT("...and ends fully dissolved"),     Tail.Dynamic.X, -1.0f, 1.0e-2f);
        TestEqual(TEXT("its alpha is the module-level Color.Scale Alpha 0.6, not 1.0"),
            Head.Color.A, 0.6f, kTolerance);
        TestEqual(TEXT("its green at half life is the corpus ramp"),
            Evaluate(0.05f, kSlotRing01).Color.G, 0.492756f, 1.0e-3f);
        TestTrue(TEXT("Ring01 is gone past its own 0.1 s"), Is_Hidden(Evaluate(0.11f, kSlotRing01)));
    }

    // ---- Spike03 is the only spike band with a colour ramp, and it opens at 2x ----
    {
        const auto Head = Evaluate(0.0f, kSlotSpike03);
        const auto Mid  = Evaluate(0.15f * 0.2f, kSlotSpike03);

        TestEqual(TEXT("Spike03 draws on the spike carrier"), Head.VisTag, kVisSpike);
        TestEqual(TEXT("its ramp opens at 2x white-blue"),    Head.Color.R, 2.0f, kTolerance);
        TestEqual(TEXT("its blue at t = 0.2 is the corpus ramp"), Mid.Color.B, 1.48556f, 1.0e-3f);
        TestTrue(TEXT("a spike writes no sprite quad"), Head.Size.IsNearlyZero());

        // The Z curve has no third key, so it HOLDS at 1.5 while X and Y collapse to zero by death.
        const auto Death = Evaluate(0.1499f, kSlotSpike03);
        TestTrue(TEXT("the spike's cross-section has collapsed at death"), Death.Scale.X < 1.0e-3f);
        TestTrue(TEXT("...while its length is still held at 1.5x its base"), Death.Scale.Z > 1.0f);
    }

    // ---- Sparkles_02 is the debris pass: gravity, XY damping, and a LINKED random colour ----
    {
        auto Bright = 0;
        auto Ramped = 0;

        // Sparkles_01's Color module ramps its red down; Sparkles_02's is DISABLED, so its red is a
        // per-particle random constant. Sampling one layer's red at two ages discriminates them.
        for (auto Seed = kSlotSparkles01; Seed < kSlotSparkles01 + 20; ++Seed)
        {
            const auto Early = Evaluate(0.06f, Seed);
            const auto Late  = Evaluate(0.30f, Seed);
            if (Early.VisTag == kVisPart04 && NOT Is_Hidden(Late)
                && FMath::Abs(Early.Color.R - Late.Color.R) > 1.0e-3f)
            { ++Ramped; }
        }
        TestTrue(TEXT("Sparkles_01's colour ramps over life"), Ramped > 5);

        for (auto Seed = kSlotSparkles02; Seed < kSlotSparkles02 + 20; ++Seed)
        {
            const auto Early = Evaluate(0.06f, Seed);
            const auto Late  = Evaluate(0.20f, Seed);
            if (Early.VisTag != kVisPart04 || Is_Hidden(Late))
            { continue; }

            ++Bright;
            TestEqual(TEXT("Sparkles_02's colour is CONSTANT — its Color module is disabled"),
                Early.Color.R, Late.Color.R, kTolerance);
            TestEqual(TEXT("...and its blue is pinned at 1 by the linked random range"),
                Early.Color.B, 1.0f, kTolerance);
        }
        TestTrue(TEXT("the debris sweep sampled a real population"), Bright > 5);

        // Link RGB / Link A: ONE draw lerps the whole triple, so R and G move together.
        auto Linked = 0;
        for (auto Seed = kSlotSparkles02; Seed < kSlotSparkles02 + 50; ++Seed)
        {
            const auto Out = Evaluate(0.06f, Seed);
            if (Out.VisTag != kVisPart04 || Is_Hidden(Out))
            { continue; }

            const auto K = Out.Color.R;                      // the draw itself: lerp(0, 1, K)
            const auto G = FMath::Lerp(0.136094f, 1.0f, K);  // the same K on the green channel
            if (FMath::Abs(Out.Color.G - G) < 1.0e-3f)
            { ++Linked; }
        }
        TestTrue(TEXT("every debris colour is ONE linked draw, not three independent ones"), Linked > 20);

        // Gravity: the debris arcs and falls, so it sits lower than the flash pass at the same age.
        auto DebrisBelow = 0;
        for (auto Seed = kSlotSparkles02; Seed < kSlotSparkles02 + 50; ++Seed)
        {
            const auto Out = Evaluate(0.25f, Seed);
            if (Out.VisTag == kVisPart04 && NOT Is_Hidden(Out) && Out.Velocity.Z < 0.0f)
            { ++DebrisBelow; }
        }
        TestTrue(TEXT("gravity pulls the debris pass' velocity down"), DebrisBelow > 10);
    }

    // ---- Bubble_First_Explo assembles: its alpha ramps UP and its scale grows from nothing ----
    {
        const auto Head = Evaluate(0.001f, kSlotBubFirst);
        const auto Tail = Evaluate(0.1499f, kSlotBubFirst);

        TestEqual(TEXT("Bubble_First_Explo draws on its own Fresnel renderer"), Head.VisTag, kVisBubFirst);
        TestTrue(TEXT("its alpha ramps UP over life — the shell assembles"), Tail.Color.A > Head.Color.A);
        TestTrue(TEXT("its scale grows from nothing"), Tail.Scale.X > Head.Scale.X);
        TestEqual(TEXT("its dissolve opens at -0.4"), Head.Dynamic.X, -0.4f, 1.0e-2f);
        TestEqual(TEXT("...and closes to 0 by half life"),
            Evaluate(0.075f, kSlotBubFirst).Dynamic.X, 0.0f, 1.0e-2f);
    }

    // ---- Bubble_Out HOLDS at 1.5x past t = 0.7: its scale curve has no third key ----
    {
        const auto Peak = Evaluate(0.1f + 0.2f * 0.7f, kSlotBubOut);
        const auto Late = Evaluate(0.1f + 0.2f * 0.95f, kSlotBubOut);

        TestEqual(TEXT("Bubble_Out draws on the annulus renderer"), Peak.VisTag, kVisBubOut);
        TestEqual(TEXT("its scale reaches 1.5x"), Peak.Scale.X, 1.5f, 1.0e-2f);
        TestEqual(TEXT("...and HOLDS there — the curve has no third key"), Late.Scale.X, 1.5f, 1.0e-2f);
        TestTrue(TEXT("its dissolve drives past -1 to clear the ring"), Late.Dynamic.X < -1.0f);
    }

    // ---- Bubble_Noise01 carries a STATIC dissolve rather than a curve ----
    {
        const auto Early = Evaluate(0.11f, kSlotBubNoise01);
        const auto Late  = Evaluate(0.28f, kSlotBubNoise01);

        TestEqual(TEXT("Bubble_Noise01 holds a static dissolve of -0.5 early"),
            Early.Dynamic.X, -0.5f, kTolerance);
        TestEqual(TEXT("...and the same value late — it is a value, not a curve"),
            Late.Dynamic.X, -0.5f, kTolerance);
    }

    // ---- Bubble_Noise02 fades its RGB to black while its alpha ramps up ----
    {
        const auto Out = Evaluate(0.1f + 0.3f * 0.4f, kSlotBubNoise02);
        TestEqual(TEXT("Bubble_Noise02 draws on its own Fresnel renderer"), Out.VisTag, kVisBubNoise02);
        TestEqual(TEXT("its blue at t = 0.4 is the initialize 2.0 scaled by the fading ramp"),
            Out.Color.B, 2.0f * 0.465645f, 1.0e-2f);
        TestTrue(TEXT("its RGB is fully black past t = 0.749"),
            Evaluate(0.1f + 0.3f * 0.9f, kSlotBubNoise02).Color.B < 1.0e-4f);
    }

    // ---- Bubble_Fresnel REPLACES its initialize colour rather than scaling it ----
    {
        const auto Head = Evaluate(0.101f, kSlotBubFresnel);
        TestEqual(TEXT("Bubble_Fresnel draws on the outermost shell renderer"), Head.VisTag, kVisBubFresnel);
        TestEqual(TEXT("its colour curve opens at white, not at the 2.0 blue initialize colour"),
            Head.Color.B, 1.0f, 1.0e-2f);
        TestEqual(TEXT("...and its alpha opens at zero"), Head.Color.A, 0.0f, 1.0e-2f);
    }

    // ---- No ribbon VisTag is ever written, and the emitter clock is never read ----
    {
        auto RibbonTags      = 0;
        auto Moved           = 0;
        auto LiveSamples     = 0;
        auto InertViolations = 0;

        for (auto Seed = 0; Seed < kBurst; ++Seed)
        {
            for (const auto Age : { 0.01f, 0.08f, 0.16f, 0.32f })
            {
                const auto Out = Evaluate(Age, Seed);

                // A hidden sample carries the switch's pre-branch default tag, which is not a draw — it is
                // asserted INERT instead, which is the property that actually matters.
                if (Is_Hidden(Out))
                {
                    if (Out.Color.A != 0.0f || NOT Out.Size.IsNearlyZero() || NOT Out.Scale.IsNearlyZero())
                    { ++InertViolations; }
                    continue;
                }

                if (Out.VisTag < kVisPart01 || Out.VisTag > kVisBubFresnel)
                { ++RibbonTags; }
                else
                { ++LiveSamples; }
            }

            const auto A = Evaluate(0.12f, Seed, 0.12f);
            const auto B = Evaluate(0.12f, Seed, 5.55f);
            if (NOT A.Position.Equals(B.Position) || NOT A.Color.Equals(B.Color)
                || NOT A.Size.Equals(B.Size) || A.VisTag != B.VisTag)
            { ++Moved; }
        }

        TestTrue(TEXT("the band sweep saw a real population of DRAWING particles"), LiveSamples > 200);
        TestEqual(TEXT("every DRAWING particle draws inside behavior 44's own VisTag band"), RibbonTags, 0);
        TestEqual(TEXT("every hidden particle is fully inert — zero alpha, zero size, zero scale"),
            InertViolations, 0);
        TestEqual(TEXT("behavior 44 is INDEPENDENT of the emitter clock"), Moved, 0);
    }

    return true;
}
