// Behavior-math gate for CkParticles BehaviorId 40 (ExplosionGround) — the Vefects NS_ExplosionGround
// recreation, and the reference system of the four-variant explosion family.
//
// Drives UCkParticles_DataInterface::Execute_Stage_CPU, the SAME CPU mirror a CPU sim runs, so it needs no
// Niagara system, no template asset, no RHI and no forked engine.
//
// Expected values are the SOURCE's own values as transcribed in
// CkFoundation/Source/CkParticles/Cookbook/NS_ExplosionGround.md §2/§5.
//
// The load-bearing claims specific to this port:
//   - the burst partition is the source's per-emitter counts exactly, over 70 slots;
//   - THE EVENT COLLAPSE (C6c). A trail point is a sample of Sparkles_02's own trajectory taken at the
//     instant the source's location event fired, so the point for strand k / step s must sit EXACTLY where
//     the sparkle layer draws sparkle k at age s/60 — an identity, not a tolerance;
//   - the trail's colour is indexed by the EMITTER clock in the FIRE palette, so two points of different
//     ages sampled at one instant carry the SAME colour;
//   - Smokes carries the batch's brightest HDR overdrive (R and G peak at 5 and 2.33892) and its
//     Color.Scale Alpha of 0.4 must survive — the [P2-D2] class of defect;
//   - Ground_Mark is the longest-lived layer at 1.5 s, and it is the family's only six-key colour table;
//   - Glow_03 carries a 100x emissive multiplier on top of everything else;
//   - the row declares no spawn rate, so behavior 40 must stay INDEPENDENT of the emitter clock.
//
// Cannot pass vacuously: behavior 40's VisTags are 185..197 and the pre-switch default is 0.

#include "Misc/AutomationTest.h"

#include "CkParticles/DataInterface/CkParticles_DataInterface.h"
#include "CkParticles/ScriptDefinition/CkParticles_ScriptDefinition_Naming.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_particles_explosion_ground
{
    constexpr auto kBehaviorId = 40;
    constexpr auto kTolerance  = 1.0e-4f;

    // Source facts (recipe §2/§6.1 against corpus v3). Loop Once / 2.0 s system; the longest layer is
    // Ground_Mark at a Direct-Set 1.5 s.
    constexpr auto kLoop     = 2.0f;
    constexpr auto kLifetime = 1.5f;
    constexpr auto kBurst    = 70;

    constexpr auto kRowAssetName = TEXT("PS_CkParticles_Template_ExplosionGround");

    constexpr auto kVisPart01Cam    = 185;
    constexpr auto kVisFlare        = 186;
    constexpr auto kVisStar         = 187;
    constexpr auto kVisSmoke        = 188;
    constexpr auto kVisRing         = 189;
    constexpr auto kVisRainbow      = 190;
    constexpr auto kVisFlames       = 191;
    constexpr auto kVisPart04       = 192;
    constexpr auto kVisPart01Custom = 193;
    constexpr auto kVisMark         = 194;
    constexpr auto kVisSphere       = 195;
    constexpr auto kVisSpike        = 196;
    constexpr auto kVisRibbon       = 197;

    // The trail: seven strands (one per Sparkles_02 particle), 43 samples each at the reference 60 Hz the
    // source's every-frame location events are quoted against.
    constexpr auto kStrands      = 7;
    constexpr auto kTrailSteps   = 43;
    constexpr auto kTrailPoints  = 301;
    constexpr auto kTrailHz      = 60.0f;
    constexpr auto kTrailLife    = 0.2f;
    constexpr auto kSparkleDelay = 0.05f;
    constexpr auto kSparkleSlot  = 4;   // the first Sparkles_02 burst slot on the Ground partition

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

    // ---- Reading the partition, and the trap that made the first gate red -------------------------------
    //
    // A layer that has not reached its spawn beat yet, or has already outlived its own lifetime, leaves its
    // branch through the early `Hide(); return;` — which runs BEFORE that branch assigns `Out.VisTag`. The
    // result therefore carries the switch's pre-branch default of 0, not the layer's own tag. That is true
    // of every behavior in the cookbook and it is harmless on screen (a hidden particle has zero colour,
    // zero size and zero scale, so it draws nothing whichever renderer it is tagged for) — but it means a
    // partition census MUST read each slot while it is ALIVE, not at one convenient instant. Seven of this
    // system's seventeen layers carry a spawn beat of 0.05 or 0.1 s.
    //
    // Sweeping the whole loop instead is strictly stronger than the single-instant read it replaces: it
    // also proves every slot draws at some point, and that each keeps ONE renderer for its whole life.
    constexpr auto kCensusSpan  = 1.7f;   // past the longest layer's death (Ground_Mark, 1.5 s)
    constexpr auto kCensusSteps = 200;

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

            if (Result.Tag == INDEX_NONE)   { Result.Tag = Out.VisTag; }
            else if (Result.Tag != Out.VisTag) { Result.Consistent = false; }
        }
        return Result;
    }

    auto Find_Slot(int32 InVisTag) -> int32
    {
        for (auto Seed = 0; Seed < kBurst; ++Seed)
        {
            if (Get_LiveVisTag(Seed).Tag == InVisTag)
            { return Seed; }
        }
        return INDEX_NONE;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Particles_ExplosionGroundBehavior,
    "CkTests.UnitTests.CkParticles.ExplosionGroundBehavior",
    kCkUnitTestFlags)

bool FCkTest_Particles_ExplosionGroundBehavior::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_explosion_ground;

    // ---- The cadence row, and the ribbon emitter it declares ----
    {
        TestEqual(TEXT("behavior 40 routes to the ExplosionGround row"),
            ck::particles::Get_BehaviorTemplateSystemObjectPath(kBehaviorId),
            ck::particles::Get_ExplosionGroundTemplateSystemObjectPath());

        TestEqual(TEXT("behavior 40 binds no CkUsf look — every look rides the row's renderers"),
            ck::particles::Get_BehaviorLookName(kBehaviorId), NAME_None);

        const auto* RowSpec = static_cast<const ck::particles::FCk_ParticlesTemplateSpec*>(nullptr);
        for (const auto& Spec : ck::particles::Get_TemplateSpecs())
        {
            if (FString(Spec.AssetName) == FString(kRowAssetName))
            { RowSpec = &Spec; break; }
        }

        if (TestNotNull(TEXT("the cadence table declares a PS_CkParticles_Template_ExplosionGround row"), RowSpec))
        {
            TestEqual(TEXT("row loop duration is the system's Loop Once / 2.0 s"),
                RowSpec->LoopDuration, kLoop, kTolerance);
            TestEqual(TEXT("row particle lifetime is Ground_Mark's 1.5 s"),
                RowSpec->ParticleLifetime, kLifetime, kTolerance);
            TestEqual(TEXT("row burst is the seventeen non-ribbon emitters' counts"), RowSpec->BurstCount, kBurst);
            TestEqual(TEXT("the row declares NO spawn rate — every emitter bursts"),
                RowSpec->SpawnRate, 0.0f, kTolerance);

            const auto& Ribbon = RowSpec->RibbonEmitter;
            TestTrue(TEXT("the row declares a ribbon emitter"), Ribbon.Get_IsDeclared());
            TestEqual(TEXT("the ribbon emitter bursts 43 event samples for each of the seven sparkles"),
                Ribbon.BurstCount, kTrailPoints);
            TestEqual(TEXT("the ribbon emitter declares no RATE — its points are solved samples"),
                Ribbon.SpawnRate, 0.0f, kTolerance);
            TestEqual(TEXT("the seven strands share ONE renderer, separated by ribbon id"),
                Ribbon.Renderers.Num(), 1);

            // The two mesh renderers carry the source's per-emitter Mesh Uniform Scale as a RENDERER scale.
            auto SphereScale = FVector::ZeroVector;
            auto SpikeScale  = FVector::ZeroVector;
            for (const auto& Renderer : RowSpec->RendererOverrides)
            {
                if (Renderer.VisTag == kVisSphere) { SphereScale = Renderer.MeshScale; }
                if (Renderer.VisTag == kVisSpike)  { SpikeScale  = Renderer.MeshScale; }
            }
            TestEqual(TEXT("the bubble carrier takes the source's Mesh Uniform Scale 0.8"),
                static_cast<float>(SphereScale.X), 0.8f, KINDA_SMALL_NUMBER);
            TestEqual(TEXT("the spike carrier keeps unit renderer scale — its scale is per-particle random"),
                static_cast<float>(SpikeScale.X), 1.0f, KINDA_SMALL_NUMBER);
        }
    }

    // ---- The burst partition IS the source's per-emitter counts ----
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

        TestEqual(TEXT("every one of the 70 burst slots draws at some point in the loop"), NeverDrawn, 0);
        TestEqual(TEXT("...and each slot keeps ONE renderer for its whole life"), Inconsistent, 0);

        // Part01 draws Glow_04 and the Light emitter's sprite on the camera quad, and Glow_01/02/03 on the
        // custom-facing one — five emitters, two renderers.
        TestEqual(TEXT("the camera Part01 quad draws Glow_04 + the light sprite"), Tags.FindRef(kVisPart01Cam), 2);
        TestEqual(TEXT("the custom-facing Part01 quad draws Glow_01 x2, Glow_02 x3 and Glow_03"),
            Tags.FindRef(kVisPart01Custom), 6);
        TestEqual(TEXT("Flare01 is one particle"),                    Tags.FindRef(kVisFlare),   1);
        TestEqual(TEXT("Sparkles_02 bursts seven"),                   Tags.FindRef(kVisStar),    7);
        TestEqual(TEXT("Smokes and SmokesCenter burst five each"),    Tags.FindRef(kVisSmoke),   10);
        TestEqual(TEXT("Ring is one particle"),                       Tags.FindRef(kVisRing),    1);
        TestEqual(TEXT("Raimbow is one particle"),                    Tags.FindRef(kVisRainbow), 1);
        TestEqual(TEXT("Flames bursts five"),                         Tags.FindRef(kVisFlames),  5);
        TestEqual(TEXT("Sparkles_01 (20) and Sparkles_02001 (10) share the velocity-aligned quad"),
            Tags.FindRef(kVisPart04), 30);
        TestEqual(TEXT("Ground_Mark is one particle"),                Tags.FindRef(kVisMark),    1);
        TestEqual(TEXT("Bubble_First_Explo is one mesh"),             Tags.FindRef(kVisSphere),  1);
        TestEqual(TEXT("Spike01 bursts five meshes"),                 Tags.FindRef(kVisSpike),   5);

        // Sparkles_02 is alive from its 0.05 s beat until at least 0.45 s, so 0.12 reads every one of them.
        auto WideSparkles = 0;
        for (auto Seed = 0; Seed < kBurst * 200; ++Seed)
        {
            if (Evaluate(0.12f, Seed).VisTag == kVisStar)
            { ++WideSparkles; }
        }
        TestEqual(TEXT("the partition holds across 200 moduli"), WideSparkles, 7 * 200);
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

                if (Is_Hidden(Trail) && Is_Hidden(Sparkle))
                { continue; }

                ++Compared;
                Worst = FMath::Max(Worst, (Trail.Position - Sparkle.Position).Size());
            }
        }

        TestTrue(TEXT("the collapse compares a non-trivial number of points"), Compared >= 20);
        TestEqual(TEXT("a trail point sits EXACTLY on its leader's path — an identity, not a tolerance"),
            Worst, 0.0f);

        // Every ribbon-bank seed lands on the trail renderer and nothing else does.
        TestEqual(TEXT("a ribbon-bank particle draws through the trail renderer"),
            Evaluate_Ribbon(0.06f, 0).VisTag, kVisRibbon);
        TestTrue(TEXT("a trail point outside its own 0.2 s window is gone"),
            Is_Hidden(Evaluate_Ribbon(0.05f + kTrailLife + 0.01f, 0)));

        auto MainBankOnTrail = 0;
        for (auto Seed = 0; Seed < 5000; ++Seed)
        {
            if (Evaluate(0.06f, Seed).VisTag == kVisRibbon)
            { ++MainBankOnTrail; }
        }
        TestEqual(TEXT("no main-bank particle ever reaches the trail renderer"), MainBankOnTrail, 0);
    }

    // ---- The trail's colour rides the EMITTER clock, so the whole strand fades together ----
    {
        // Two points of the same strand with different event times, read at ONE instant.
        constexpr auto Instant = 0.30f;

        const auto Early = Evaluate_Ribbon(Instant, 0 * kTrailSteps + 6);   // event at 0.05 + 0.100
        const auto Late  = Evaluate_Ribbon(Instant, 0 * kTrailSteps + 12);  // event at 0.05 + 0.200

        TestFalse(TEXT("both sampled trail points are alive"), Is_Hidden(Early) || Is_Hidden(Late));
        TestEqual(TEXT("two trail points of different ages carry the same colour at one instant (R)"),
            Early.Color.R, Late.Color.R, kTolerance);
        TestEqual(TEXT("...and the same alpha — an emitter-age curve index, not a particle-age one"),
            Early.Color.A, Late.Color.A, kTolerance);
    }

    // ---- A trail point past its own leader's death was never sent ----
    {
        // Strand 0's leader lives lerp(0.4, 0.7, Rand(seed, 1)) at most 0.7 s, i.e. 42 samples at 60 Hz.
        // A sample whose time exceeds that life must be hidden at every age.
        auto HiddenPastDeath = 0;
        auto Checked         = 0;

        for (auto Strand = 0; Strand < kStrands; ++Strand)
        {
            const auto Step      = kTrailSteps - 1;
            const auto EventTime = kSparkleDelay + float(Step) / kTrailHz;
            const auto Leader    = Evaluate(EventTime, kSparkleSlot + Strand);

            if (NOT Is_Hidden(Leader))
            { continue; }

            ++Checked;
            if (Is_Hidden(Evaluate_Ribbon(EventTime, Strand * kTrailSteps + Step)))
            { ++HiddenPastDeath; }
        }

        TestTrue(TEXT("at least one strand's last sample falls past its leader's death"), Checked > 0);
        TestEqual(TEXT("a sample past its leader's death draws nothing"), HiddenPastDeath, Checked);
    }

    // ---- Smokes: the HDR overdrive and the Color.Scale Alpha that would otherwise read 2.5x too bright ----
    {
        const auto Slot = Find_Slot(kVisSmoke);
        if (TestTrue(TEXT("a Smokes slot exists"), Slot != INDEX_NONE))
        {
            // Its life is a random 0.7-1.3 s off a 0.05 s beat, so the peaks are found by sweeping the
            // widest possible window rather than by re-deriving the draw.
            auto PeakR = 0.0f;
            auto PeakA = 0.0f;
            for (auto Step = 0; Step <= 400; ++Step)
            {
                const auto Out = Evaluate(0.05f + 1.3f * float(Step) / 400.0f, Slot);
                PeakR = FMath::Max(PeakR, Out.Color.R);
                PeakA = FMath::Max(PeakA, Out.Color.A);
            }

            TestEqual(TEXT("Smokes' red peaks at the source's HDR 5.0"), PeakR, 5.0f, 1.0e-2f);
            TestEqual(TEXT("its alpha peaks at 0.4 — the module-level Color.Scale Alpha, not 1.0"),
                PeakA, 0.4f, 1.0e-2f);
        }
    }

    // ---- Ground_Mark: the six-key table, the 1.5 s life and the 0.4 alpha scale ----
    {
        const auto Slot = Find_Slot(kVisMark);
        if (TestTrue(TEXT("a Ground_Mark slot exists"), Slot != INDEX_NONE))
        {
            const auto Mid = Evaluate(0.75f, Slot);
            TestEqual(TEXT("Ground_Mark is still alive at 0.75 s — it is the 1.5 s layer"),
                Mid.VisTag, kVisMark);
            TestEqual(TEXT("its alpha at half life is the ramp scaled by 0.4"),
                Mid.Color.A, 0.200247f, kTolerance);

            const auto Early = Evaluate(0.075f, Slot); // t = 0.05 of a 1.5 s life
            TestEqual(TEXT("the fire scorch is still white at t = 0.05 (six-key table, first knee at 0.0518999)"),
                Early.Color.R, 1.0f, kTolerance);

            TestTrue(TEXT("Ground_Mark is gone past its own 1.5 s"), Is_Hidden(Evaluate(1.51f, Slot)));

            TestEqual(TEXT("it draws on the custom-facing decal quad"), Mid.VisTag, kVisMark);
            TestEqual(TEXT("its sprite facing is the ground plane normal"), Mid.SpriteFacing.Z, 1.0f, kTolerance);
            TestEqual(TEXT("and its alignment is perpendicular to that facing, not parallel to it"),
                Mid.SpriteAlignment.Z, 0.0f, kTolerance);
        }
    }

    // ---- Glow_03 carries a 100x emissive multiplier ----
    {
        // Glow_03 is burst slot 60 on the Ground partition.
        const auto Out = Evaluate(0.001f, 60);
        TestEqual(TEXT("Glow_03 draws on the custom-facing Part01 quad"), Out.VisTag, kVisPart01Custom);
        TestEqual(TEXT("its red is the initialize colour times the 100x Scale RGB"),
            Out.Color.R, 55.0f, 1.0e-2f);
    }

    // ---- The light layer is DROPPED, but its sprite is not: the 1e6 Scale RGB now drives only the bloom ----
    {
        const auto Out = Evaluate(0.001f, 64);
        TestEqual(TEXT("the light emitter's sprite draws on the camera Part01 quad"), Out.VisTag, kVisPart01Cam);
        TestEqual(TEXT("its size is the source's 9.16604, not a light radius"), Out.Size.X, 9.16604f, kTolerance);
        TestTrue(TEXT("its colour carries the 1e6 intensity channel unclamped"), Out.Color.R > 9.0e5f);
    }

    // ---- Emitter-clock independence: the row declares no rate, so nothing may read EmitterAge ----
    {
        auto Moved = 0;
        for (auto Seed = 0; Seed < 400; ++Seed)
        {
            const auto A = Evaluate(0.12f, Seed, 0.12f);
            const auto B = Evaluate(0.12f, Seed, 7.77f);

            if (NOT A.Position.Equals(B.Position) || NOT A.Color.Equals(B.Color)
                || NOT A.Size.Equals(B.Size) || A.VisTag != B.VisTag)
            { ++Moved; }
        }
        TestEqual(TEXT("behavior 40 is INDEPENDENT of the emitter clock"), Moved, 0);
    }

    return true;
}
