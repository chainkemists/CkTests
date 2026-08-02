// Behavior-math gate for CkParticles BehaviorId 38 (BuffCast) — the Vefects NS_BuffCast recreation, and the
// cookbook's first consumer of the EVENT-COLLAPSE translation (C6c).
//
// Drives UCkParticles_DataInterface::Execute_Stage_CPU, the SAME CPU mirror a CPU sim runs, so it needs no
// Niagara system, no template asset, no RHI and no forked engine.
//
// Expected values are the SOURCE's own values as transcribed in
// CkFoundation/Source/CkParticles/Cookbook/NS_BuffCast.md §2/§5.
//
// The load-bearing claims specific to this port:
//   - THE EVENT COLLAPSE. A trail point is a sample of the leader's trajectory taken at the instant the
//     source's location event fired. So the point for strand k / step s must sit EXACTLY where the sparkle
//     layer draws sparkle k at age s/60 — asserted as an identity, not a tolerance, because both sides
//     evaluate the same closed form;
//   - the trail's colour is indexed by the EMITTER clock, not by the point's own age. Two points with
//     different spawn times, sampled at the same instant, must carry the SAME colour — an implementation
//     that indexed per-particle age fails this and nothing else;
//   - a point past its own leader's death was never sent, and a point outside its 0.2 s window is gone;
//   - the burst partition is the source's per-emitter counts exactly, and the ribbon bank is disjoint from
//     the main one in BOTH directions;
//   - Ring carries a Color.Scale Alpha of 0.25, so its alpha PEAKS at a quarter — the [P2-D2] class of
//     defect (a missing Scale Alpha reads 4x too bright) pinned at the peak and on the ramp;
//   - the row declares no spawn rate, so behavior 38 must stay INDEPENDENT of the emitter clock.
//
// Cannot pass vacuously: behavior 38's VisTags are 167..174 and the pre-switch default is 0.

#include "Misc/AutomationTest.h"

#include "CkParticles/DataInterface/CkParticles_DataInterface.h"
#include "CkParticles/ScriptDefinition/CkParticles_ScriptDefinition_Naming.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_particles_buff_cast
{
    constexpr auto kBehaviorId = 38;
    constexpr auto kTolerance  = 1.0e-4f;

    // Source facts (recipe §2/§6.1 against corpus v3). Loop Once / 2.0 s system; the longest layer is the
    // Arrow pair at 1.5 s.
    constexpr auto kLoop     = 2.0f;
    constexpr auto kLifetime = 1.5f;
    constexpr auto kBurst    = 23;  // 1+1+1+1+1+1+7+7+3

    constexpr auto kRowAssetName = TEXT("PS_CkParticles_Template_BuffCast");

    constexpr auto kVisPart01  = 167;
    constexpr auto kVisPart02  = 168;
    constexpr auto kVisRainbow = 169;
    constexpr auto kVisArrows  = 170;
    constexpr auto kVisStar01  = 171;
    constexpr auto kVisPart04  = 172;
    constexpr auto kVisRing01  = 173;
    constexpr auto kVisTrail   = 174;

    // The trail: seven strands (one per sparkle), 43 steps each at the reference 60 Hz the source's
    // every-frame location events are quoted against.
    constexpr auto kStrands      = 7;
    constexpr auto kTrailSteps   = 43;
    constexpr auto kTrailPoints  = 301;
    constexpr auto kTrailHz      = 60.0f;
    constexpr auto kTrailLife    = 0.2f;
    constexpr auto kTrailWidth   = 15.0f;
    constexpr auto kSparkleDelay = 0.05f;
    constexpr auto kSparkleSlot  = 6;

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

    auto Evaluate_Ribbon(float InAge, int32 InLocalSeed) -> FCk_Particles_StageResult
    {
        return Evaluate(InAge, ck::particles::RibbonSeedBase + InLocalSeed);
    }

    auto Is_Hidden(const FCk_Particles_StageResult& InOut) -> bool
    {
        return InOut.Color.A == 0.0f && InOut.Color.R == 0.0f && InOut.Color.G == 0.0f && InOut.Color.B == 0.0f
            && InOut.Size.IsNearlyZero() && InOut.Scale.IsNearlyZero();
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Particles_BuffCastBehavior,
    "CkTests.UnitTests.CkParticles.BuffCastBehavior",
    kCkUnitTestFlags)

bool FCkTest_Particles_BuffCastBehavior::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_buff_cast;

    // ---- The cadence row, and the ribbon emitter it declares ----
    {
        TestEqual(TEXT("behavior 38 routes to the BuffCast row"),
            ck::particles::Get_BehaviorTemplateSystemObjectPath(kBehaviorId),
            ck::particles::Get_BuffCastTemplateSystemObjectPath());

        TestEqual(TEXT("behavior 38 binds no CkUsf look — all eight looks ride the row's renderers"),
            ck::particles::Get_BehaviorLookName(kBehaviorId), NAME_None);

        const auto* RowSpec = static_cast<const ck::particles::FCk_ParticlesTemplateSpec*>(nullptr);
        for (const auto& Spec : ck::particles::Get_TemplateSpecs())
        {
            if (FString(Spec.AssetName) == FString(kRowAssetName))
            { RowSpec = &Spec; break; }
        }

        if (TestNotNull(TEXT("the cadence table declares a PS_CkParticles_Template_BuffCast row"), RowSpec))
        {
            TestEqual(TEXT("row loop duration is the system's Loop Once / 2.0 s"),
                RowSpec->LoopDuration, kLoop, kTolerance);
            TestEqual(TEXT("row particle lifetime is the Arrow pair's 1.5 s"),
                RowSpec->ParticleLifetime, kLifetime, kTolerance);
            TestEqual(TEXT("row burst is the source's nine sprite emitters' counts"), RowSpec->BurstCount, kBurst);
            TestEqual(TEXT("the row declares NO spawn rate — every sprite emitter bursts"),
                RowSpec->SpawnRate, 0.0f, kTolerance);

            const auto& Ribbon = RowSpec->RibbonEmitter;
            TestTrue(TEXT("the row declares a ribbon emitter"), Ribbon.Get_IsDeclared());
            TestEqual(TEXT("the ribbon emitter bursts 43 event samples for each of the seven sparkles"),
                Ribbon.BurstCount, kTrailPoints);
            TestEqual(TEXT("the ribbon emitter declares no RATE — its points are solved samples, not a stream"),
                Ribbon.SpawnRate, 0.0f, kTolerance);
            TestEqual(TEXT("the seven strands share ONE renderer, separated by ribbon id"),
                Ribbon.Renderers.Num(), 1);

            if (Ribbon.Renderers.Num() == 1)
            {
                const auto& Renderer = Ribbon.Renderers[0];
                TestTrue(TEXT("the ribbon renderer is the Ribbon kind"),
                    Renderer.Kind == ck::particles::ECk_ParticlesRenderer_Kind::Ribbon);
                TestEqual(TEXT("the ribbon renderer draws the TrailDisAdd03 look"),
                    FString(Renderer.LookName), FString(TEXT("TrailDisAdd03")));
                TestEqual(TEXT("the ribbon renderer's VisTag is the one the behavior writes"),
                    Renderer.VisTag, kVisTrail);
                TestNull(TEXT("a ribbon has no carrier mesh"), Renderer.MeshName);
            }
        }
    }

    // ---- The burst partition IS the source's per-emitter counts ----
    {
        auto Tags = TMap<int32, int32>{};
        for (auto Seed = 0; Seed < kBurst; ++Seed)
        { Tags.FindOrAdd(Evaluate(0.1f, Seed).VisTag) += 1; }

        TestEqual(TEXT("Part01 draws both large support glows"),  Tags.FindRef(kVisPart01),  2);
        TestEqual(TEXT("Part02 draws the third, dissolved glow"), Tags.FindRef(kVisPart02),  1);
        TestEqual(TEXT("the rainbow lens ring is one particle"),  Tags.FindRef(kVisRainbow), 1);
        TestEqual(TEXT("the Arrows paint draws both chevrons"),   Tags.FindRef(kVisArrows),  2);
        TestEqual(TEXT("Sparkles_02 bursts seven"),               Tags.FindRef(kVisStar01),  7);
        TestEqual(TEXT("Sparkles_01 bursts seven"),               Tags.FindRef(kVisPart04),  7);
        TestEqual(TEXT("Ring bursts three"),                      Tags.FindRef(kVisRing01),  3);

        auto WideSparkles = 0;
        for (auto Seed = 0; Seed < kBurst * 500; ++Seed)
        {
            if (Evaluate(0.1f, Seed).VisTag == kVisStar01)
            { ++WideSparkles; }
        }
        TestEqual(TEXT("the partition holds across 500 moduli"), WideSparkles, 7 * 500);
    }

    // ---- THE EVENT COLLAPSE: every trail point sits on its leader's path, at its own event time ----
    {
        auto Compared = 0;
        auto Worst    = 0.0f;

        for (auto Strand = 0; Strand < kStrands; ++Strand)
        {
            for (const auto Step : { 0, 5, 17, 30, 42 })
            {
                const auto EventTime = kSparkleDelay + float(Step) / kTrailHz;

                const auto Trail   = Evaluate_Ribbon(EventTime, Strand * kTrailSteps + Step);
                const auto Sparkle = Evaluate(EventTime, kSparkleSlot + Strand);

                // A step past the leader's death has no event to compare against — the trail hides it and
                // the sparkle is already gone.
                if (Is_Hidden(Trail) && Is_Hidden(Sparkle))
                { continue; }

                ++Compared;
                Worst = FMath::Max(Worst, (Trail.Position - Sparkle.Position).Size());

                TestEqual(*FString::Printf(
                    TEXT("trail point (strand %d, step %d) draws the sparkle's own layer at the same instant"),
                    Strand, Step), Sparkle.VisTag, kVisStar01);
            }
        }

        TestTrue(TEXT("the collapse comparison is not vacuous — live points were compared"), Compared >= 20);
        // Both sides evaluate the same closed form on the same leader identity, so this is an IDENTITY, not
        // an approximation. A tolerance here would let a re-derived leader path drift through.
        TestEqual(TEXT("a trail point sits EXACTLY on its leader's path at its event time"),
            Worst, 0.0f);
    }

    // ---- The trail's colour rides the EMITTER clock, not the point's own age ----
    {
        // Two points with different spawn times, both live at the same instant.
        const auto Early = Evaluate_Ribbon(0.30f, 0 * kTrailSteps + 10); // spawned at 0.2167
        const auto Late  = Evaluate_Ribbon(0.30f, 3 * kTrailSteps + 14); // spawned at 0.2833

        TestFalse(TEXT("the early sample point is live at 0.30 s"), Is_Hidden(Early));
        TestFalse(TEXT("the later sample point is live at 0.30 s too"), Is_Hidden(Late));

        TestEqual(TEXT("two trail points of different ages carry the SAME green at one instant"),
            Early.Color.G, Late.Color.G, kTolerance);
        TestEqual(TEXT("...and the same alpha — the curve is indexed by Emitter.Age"),
            Early.Color.A, Late.Color.A, kTolerance);

        // Corpus-derived, at both ends of the ramp: G runs 0.708376 -> 0.341915 -> 0.109462 over the
        // emitter's own second. The earliest event lands at 0.05, so the head of the ramp is sampled ON it.
        TestEqual(TEXT("trail green is 0.664387 at emitter age 0.05 — the head of the 0.708376 ramp"),
            Evaluate_Ribbon(kSparkleDelay, 0).Color.G, 0.664387f, kTolerance);
        TestEqual(TEXT("trail green reaches its middle key exactly at emitter age 0.416541"),
            Evaluate_Ribbon(0.416541f, 21).Color.G, 0.341915f, kTolerance);
        TestEqual(TEXT("trail alpha holds 1 at emitter age 0.05 — it does not open at zero"),
            Evaluate_Ribbon(kSparkleDelay, 0).Color.A, 1.0f, kTolerance);

        // Width tapers 15 -> 0 across the point's own 0.2 s, which IS its own age.
        const auto Head = Evaluate_Ribbon(kSparkleDelay, 0);
        const auto Mid  = Evaluate_Ribbon(kSparkleDelay + 0.5f * kTrailLife, 0);
        TestEqual(TEXT("a trail point opens at the source's 15-unit ribbon width"),
            Head.Size.X, kTrailWidth, kTolerance);
        TestEqual(TEXT("...and is half that at half its own life"),
            Mid.Size.X, 0.5f * kTrailWidth, kTolerance);
        TestTrue(TEXT("...and is gone once its 0.2 s is up"),
            Is_Hidden(Evaluate_Ribbon(kSparkleDelay + kTrailLife + 0.01f, 0)));
    }

    // ---- Strand partition, and a seed bank that is disjoint in BOTH directions ----
    {
        auto Strands = TMap<int32, int32>{};
        auto Tags    = TSet<int32>{};

        for (auto Local = 0; Local < kTrailPoints; ++Local)
        {
            const auto Out = Evaluate_Ribbon(0.30f, Local);
            Strands.FindOrAdd(Out.MeshIndex) += 1;
            Tags.Add(Out.VisTag);
        }

        TestEqual(TEXT("one ribbon burst carries exactly seven strands"), Strands.Num(), kStrands);
        for (auto Strand = 0; Strand < kStrands; ++Strand)
        {
            TestEqual(*FString::Printf(TEXT("strand %d carries its 43 event samples"), Strand),
                Strands.FindRef(Strand), kTrailSteps);
        }

        TestEqual(TEXT("every ribbon-bank particle reaches the trail renderer and nothing else"), Tags.Num(), 1);
        TestTrue(TEXT("the trail branch writes the trail VisTag"), Tags.Contains(kVisTrail));

        auto MainReachedTrail = false;
        for (auto Seed = 0; Seed < 5000; ++Seed)
        {
            if (Evaluate(0.30f, Seed).VisTag == kVisTrail)
            { MainReachedTrail = true; }
        }
        TestFalse(TEXT("no main-bank particle reaches the trail renderer"), MainReachedTrail);
    }

    // ---- A trail point past its own leader's death was never sent ----
    {
        // Slot 6's leader lives 0.435304 s, so its steps past 26 have no event behind them.
        auto Live = 0;
        for (auto Step = 0; Step < kTrailSteps; ++Step)
        {
            const auto EventTime = kSparkleDelay + float(Step) / kTrailHz;
            if (NOT Is_Hidden(Evaluate_Ribbon(EventTime, Step)))
            { ++Live; }
        }

        TestTrue(TEXT("strand 0 places fewer points than its capacity — its leader dies first"),
            Live > 0 && Live < kTrailSteps);
    }

    // ---- Ring: the layer whose Color.Scale Alpha is a QUARTER, and the only animated dissolve ----
    {
        constexpr auto RingSeed = 20;

        // Its alpha curve peaks at 1 at t = 0.076064 of its own life and is scaled by the emitter's
        // Color.Scale Alpha of 0.25. The bound is two-sided on purpose: an implementation that dropped the
        // Scale Alpha peaks at 1 (4x too bright) and one that dropped the curve peaks at 0.
        auto Peak = 0.0f;
        for (auto Step = 0; Step <= 2000; ++Step)
        {
            const auto Out = Evaluate(0.3f * float(Step) / 2000.0f, RingSeed);
            if (Out.VisTag == kVisRing01)
            { Peak = FMath::Max(Peak, Out.Color.A); }
        }
        TestTrue(*FString::Printf(TEXT("Ring's alpha peaks at a QUARTER — its Color.Scale Alpha is 0.25 "
            "(observed %f)"), Peak), Peak > 0.24f && Peak <= 0.25f + kTolerance);

        const auto Open = Evaluate(0.0f, RingSeed);
        TestEqual(TEXT("Ring's dissolve threshold opens at -0.325"), Open.Dynamic.X, -0.325f, kTolerance);
        TestEqual(TEXT("Ring's red opens at its first key"), Open.Color.R, 1.0f, kTolerance);
    }

    // ---- Arrow / BigArrow: corpus-derived colour at BOTH ends of the ramp ----
    {
        constexpr auto ArrowSeed    = 4;
        constexpr auto BigArrowSeed = 5;

        const auto Open = Evaluate(0.0f, ArrowSeed);
        TestEqual(TEXT("Arrow opens white-hot on red"), Open.Color.R, 1.0f, kTolerance);
        TestEqual(TEXT("Arrow opens at its 0.913099 green key"), Open.Color.G, 0.913099f, kTolerance);
        TestEqual(TEXT("Arrow starts a metre below the cast point"), Open.Position.Z, -119.316f, 1.0e-2f);

        const auto End = Evaluate(kLifetime * 0.947781f, ArrowSeed);
        TestEqual(TEXT("Arrow's red reaches its last key exactly"), End.Color.R, 0.223228f, kTolerance);
        TestEqual(TEXT("Arrow's green reaches zero at the same key"), End.Color.G, 0.0f, kTolerance);

        // A point ON the ramp, so a behavior that stepped between keys instead of lerping fails.
        TestEqual(TEXT("Arrow's green is 0.250205 at t = 0.2 — the ramp is running"),
            Evaluate(kLifetime * 0.2f, ArrowSeed).Color.G, 0.250205f, kTolerance);
        TestEqual(TEXT("BigArrow's green is 0.254641 at t = 0.2 — a DIFFERENT curve, not a copy"),
            Evaluate(kLifetime * 0.2f, BigArrowSeed).Color.G, 0.254641f, kTolerance);

        // BigArrow carries no Scale Sprite Size module at all, so its quad never moves.
        const auto BigOpen = Evaluate(0.0f, BigArrowSeed);
        const auto BigLate = Evaluate(kLifetime * 0.9f, BigArrowSeed);
        TestEqual(TEXT("BigArrow holds its authored 150-unit width for life"), BigOpen.Size.X, 150.0f, kTolerance);
        TestEqual(TEXT("BigArrow holds its authored 240-unit length for life"), BigLate.Size.Y, 240.0f, kTolerance);

        TestTrue(TEXT("both chevrons are gone past the row's 1.5 s"),
            Is_Hidden(Evaluate(1.6f, ArrowSeed)) && Is_Hidden(Evaluate(1.6f, BigArrowSeed)));
    }

    // ---- Raimbow: its Scale Color carries a SINGLE RGB key, so the tint is flat, not a ramp ----
    {
        constexpr auto RainbowSeed = 3;

        const auto Early = Evaluate(0.1f, RainbowSeed);
        const auto Late  = Evaluate(0.9f, RainbowSeed);

        TestEqual(TEXT("Raimbow's tint is a flat half of its authored grey"), Early.Color.R, 0.4565495f, kTolerance);
        TestEqual(TEXT("...and it does not ramp"), Late.Color.R, 0.4565495f, kTolerance);
        TestEqual(TEXT("Raimbow drives the family's half dissolve"), Early.Dynamic.X, 0.5f, kTolerance);
        TestEqual(TEXT("Raimbow draws through the rainbow lens renderer"), Early.VisTag, kVisRainbow);
    }

    // ---- No spawn rate on the row, so the emitter clock must be inert for this behavior ----
    {
        auto Moved = 0;

        for (auto Seed = 0; Seed < 400; ++Seed)
        {
            const auto Reference = Evaluate(0.7f, Seed, 0.0f);

            for (const auto EmitterAge : { 0.37f, 2.5f, 41.0f })
            {
                const auto Shifted = Evaluate(0.7f, Seed, EmitterAge);

                if (Reference.VisTag != Shifted.VisTag || Reference.Color != Shifted.Color
                    || Reference.Size != Shifted.Size || Reference.Position != Shifted.Position)
                { ++Moved; }
            }
        }

        TestEqual(TEXT("behavior 38 ignores the emitter clock — its row declares one population per emitter"),
            Moved, 0);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
