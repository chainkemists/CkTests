// Behavior-math gate for CkParticles BehaviorId 42 (ExplosionOmni) — the Vefects NS_ExplosionOmni
// recreation, the second structural variant of the explosion family.
//
// Drives UCkParticles_DataInterface::Execute_Stage_CPU, the SAME CPU mirror a CPU sim runs, so it needs no
// Niagara system, no template asset, no RHI and no forked engine.
//
// Expected values are the SOURCE's own values as transcribed in
// CkFoundation/Source/CkParticles/Cookbook/NS_ExplosionOmni.md §2/§5.
//
// The load-bearing claims specific to THIS variant, i.e. what the Ground/Omni axis actually changes:
//   - "Omni" is literal. Every hemispherical spawn in Ground opens to a FULL sphere here, so the spawn
//     cloud must straddle z = 0 instead of sitting entirely above it — the single most visible difference,
//     and the one a shared implementation would silently lose;
//   - the emitter list loses Glow_01, Glow_02 and Ground_Mark, so the burst is 65 rather than 70 and the
//     row's lifetime is the smoke layers' 1.3 s rather than the scorch decal's 1.5 s ([P0-D2] moved this
//     one: the pre-v3 reading was 0.4 s);
//   - Spike01's orientation is drawn from the FULL cube rather than a mostly-upward fan;
//   - Ring's dissolve starts NEGATIVE here (-0.1) where Ground's starts positive (+0.15), so the Omni ring
//     only ever intensifies. This is a Ground/Omni difference, not a fire/ice one;
//   - the event collapse and the emitter-clock independence hold exactly as on Ground.
//
// Cannot pass vacuously: behavior 42's VisTags are 198..209 and the pre-switch default is 0.

#include "Misc/AutomationTest.h"

#include "CkParticles/DataInterface/CkParticles_DataInterface.h"
#include "CkParticles/ScriptDefinition/CkParticles_ScriptDefinition_Naming.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_particles_explosion_omni
{
    constexpr auto kBehaviorId = 42;
    constexpr auto kGroundId   = 40;
    constexpr auto kTolerance  = 1.0e-4f;

    constexpr auto kLoop     = 2.0f;
    constexpr auto kLifetime = 1.3f;
    constexpr auto kBurst    = 65;

    constexpr auto kRowAssetName = TEXT("PS_CkParticles_Template_ExplosionOmni");

    constexpr auto kVisPart01Cam    = 198;
    constexpr auto kVisFlare        = 199;
    constexpr auto kVisStar         = 200;
    constexpr auto kVisSmoke        = 201;
    constexpr auto kVisRing         = 202;
    constexpr auto kVisRainbow      = 203;
    constexpr auto kVisFlames       = 204;
    constexpr auto kVisPart04       = 205;
    constexpr auto kVisPart01Custom = 206;
    constexpr auto kVisSphere       = 207;
    constexpr auto kVisSpike        = 208;
    constexpr auto kVisRibbon       = 209;

    constexpr auto kStrands      = 7;
    constexpr auto kTrailSteps   = 43;
    constexpr auto kTrailPoints  = 301;
    constexpr auto kTrailHz      = 60.0f;
    constexpr auto kSparkleDelay = 0.05f;
    constexpr auto kSparkleSlot  = 2;   // the first Sparkles_02 burst slot on the Omni partition

    auto Evaluate_Id(int32 InBehaviorId, float InAge, int32 InSeed, float InEmitterAge)
        -> FCk_Particles_StageResult
    {
        constexpr auto DeltaTime = 1.0f / 60.0f;

        return UCkParticles_DataInterface::Execute_Stage_CPU(
            InBehaviorId, DeltaTime, InAge, kLifetime,
            FVector3f::ZeroVector, FVector3f::ZeroVector, InSeed, InEmitterAge);
    }

    auto Evaluate(float InAge, int32 InSeed) -> FCk_Particles_StageResult
    {
        return Evaluate_Id(kBehaviorId, InAge, InSeed, InAge);
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

    // A layer that has not reached its spawn beat, or has outlived its own lifetime, leaves its branch
    // through the early `Hide(); return;` — which runs BEFORE that branch assigns `Out.VisTag`, so the
    // result carries the switch's pre-branch default of 0. Harmless on screen (a hidden particle has zero
    // colour, size and scale) but it means a partition census must read each slot while it is ALIVE. Six of
    // this variant's fourteen layers carry a 0.05 or 0.1 s beat, and two more live only 0.1 s.
    //
    // Sweeping the loop is strictly stronger than the single-instant read it replaces: it also proves every
    // slot draws at some point and that each keeps ONE renderer for its whole life.
    constexpr auto kCensusSpan  = 1.5f;   // past the longest layer's death (the smokes, 0.05 + 1.3 s)
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

            if (Result.Tag == INDEX_NONE)      { Result.Tag = Out.VisTag; }
            else if (Result.Tag != Out.VisTag) { Result.Consistent = false; }
        }
        return Result;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Particles_ExplosionOmniBehavior,
    "CkTests.UnitTests.CkParticles.ExplosionOmniBehavior",
    kCkUnitTestFlags)

bool FCkTest_Particles_ExplosionOmniBehavior::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_explosion_omni;

    // ---- The cadence row ----
    {
        TestEqual(TEXT("behavior 42 routes to the ExplosionOmni row"),
            ck::particles::Get_BehaviorTemplateSystemObjectPath(kBehaviorId),
            ck::particles::Get_ExplosionOmniTemplateSystemObjectPath());

        TestEqual(TEXT("behavior 42 binds no CkUsf look"),
            ck::particles::Get_BehaviorLookName(kBehaviorId), NAME_None);

        const auto* RowSpec = static_cast<const ck::particles::FCk_ParticlesTemplateSpec*>(nullptr);
        for (const auto& Spec : ck::particles::Get_TemplateSpecs())
        {
            if (FString(Spec.AssetName) == FString(kRowAssetName))
            { RowSpec = &Spec; break; }
        }

        if (TestNotNull(TEXT("the cadence table declares a PS_CkParticles_Template_ExplosionOmni row"), RowSpec))
        {
            TestEqual(TEXT("row loop duration is the system's Loop Once / 2.0 s"),
                RowSpec->LoopDuration, kLoop, kTolerance);
            TestEqual(TEXT("row particle lifetime is the smoke layers' resolved 1.3 s, not the pre-v3 0.4 s"),
                RowSpec->ParticleLifetime, kLifetime, kTolerance);
            TestEqual(TEXT("row burst is 65 — five fewer emitters than Ground"), RowSpec->BurstCount, kBurst);
            TestEqual(TEXT("the row declares NO spawn rate"), RowSpec->SpawnRate, 0.0f, kTolerance);
            TestTrue(TEXT("the row declares the same ribbon emitter shape as Ground"),
                RowSpec->RibbonEmitter.Get_IsDeclared());
            TestEqual(TEXT("the ribbon emitter bursts 301 solved samples"),
                RowSpec->RibbonEmitter.BurstCount, kTrailPoints);
            TestEqual(TEXT("the Omni row declares ELEVEN renderers — Ground's twelve minus the scorch decal"),
                RowSpec->RendererOverrides.Num(), 11);
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

        TestEqual(TEXT("every one of the 65 burst slots draws at some point in the loop"), NeverDrawn, 0);
        TestEqual(TEXT("...and each slot keeps ONE renderer for its whole life"), Inconsistent, 0);

        TestEqual(TEXT("Glow_04 (3) and the light sprite (1) share the camera Part01 quad"),
            Tags.FindRef(kVisPart01Cam), 4);
        TestEqual(TEXT("only Glow_03 draws on the custom-facing quad here, and it bursts two"),
            Tags.FindRef(kVisPart01Custom), 2);
        TestEqual(TEXT("Flare01 is one particle"),                 Tags.FindRef(kVisFlare),   1);
        TestEqual(TEXT("Sparkles_02 bursts seven"),                Tags.FindRef(kVisStar),    7);
        TestEqual(TEXT("Smokes bursts THREE here and SmokesCenter five"), Tags.FindRef(kVisSmoke), 8);
        TestEqual(TEXT("Ring is one particle"),                    Tags.FindRef(kVisRing),    1);
        TestEqual(TEXT("Raimbow is one particle"),                 Tags.FindRef(kVisRainbow), 1);
        TestEqual(TEXT("Flames bursts five"),                      Tags.FindRef(kVisFlames),  5);
        TestEqual(TEXT("Sparkles_01 (20) and Sparkles_02001 (10) share the velocity-aligned quad"),
            Tags.FindRef(kVisPart04), 30);
        TestEqual(TEXT("Bubble_First_Explo is one mesh"),          Tags.FindRef(kVisSphere),  1);
        TestEqual(TEXT("Spike01 bursts five meshes"),              Tags.FindRef(kVisSpike),   5);
        TestEqual(TEXT("there is NO scorch decal in the Omni variant"), Tags.FindRef(194),    0);
    }

    // ---- "Omni" is literal: the sparkle cloud straddles z = 0 where Ground's sits above it ----
    {
        auto OmniBelow   = 0;
        auto GroundBelow = 0;
        auto Sampled     = 0;

        for (auto Seed = 0; Seed < 4000; ++Seed)
        {
            const auto Omni = Evaluate(0.001f, Seed);
            if (Omni.VisTag != kVisPart04)
            { continue; }

            ++Sampled;
            if (Omni.Position.Z < -1.0f)
            { ++OmniBelow; }

            const auto Ground = Evaluate_Id(kGroundId, 0.001f, Seed, 0.001f);
            if (Ground.VisTag == 192 && Ground.Position.Z < -1.0f)
            { ++GroundBelow; }
        }

        TestTrue(TEXT("the sweep sampled a real population of streak particles"), Sampled > 500);
        TestTrue(TEXT("roughly half the Omni streaks spawn BELOW the origin plane"),
            OmniBelow > Sampled / 4);
        TestEqual(TEXT("and NONE of Ground's do — its spawns are hemispherical"), GroundBelow, 0);
    }

    // ---- Ring's dissolve starts NEGATIVE on Omni and POSITIVE on Ground ----
    {
        int32 OmniSlot = INDEX_NONE;
        for (auto Seed = 0; Seed < kBurst; ++Seed)
        {
            if (Evaluate(0.10f, Seed).VisTag == kVisRing)
            { OmniSlot = Seed; break; }
        }

        if (TestTrue(TEXT("a Ring slot exists"), OmniSlot != INDEX_NONE))
        {
            // Half-way through the ring's own 0.3 s life, off its 0.05 s beat.
            const auto Out = Evaluate(0.05f + 0.15f, OmniSlot);
            TestEqual(TEXT("the Omni ring's dissolve holds at -0.1 through the first half of its life"),
                Out.Dynamic.X, -0.1f, kTolerance);
            TestEqual(TEXT("its size is 400, not Ground's 500"), Out.Size.X, 400.0f * 0.975f, 1.0f);
        }
    }

    // ---- Spike01's orientation is isotropic here, and constrained on Ground ----
    {
        auto OmniOffAxis   = 0;
        auto GroundOffAxis = 0;
        auto Spikes        = 0;

        for (auto Seed = 0; Seed < 2000; ++Seed)
        {
            const auto Out = Evaluate(0.05f, Seed);
            if (Out.VisTag != kVisSpike)
            { continue; }

            ++Spikes;
            // QuatFromZTo builds its axis as cross(+Z, Dir) = (-Dir.y, Dir.x, 0), so the quaternion's Y
            // component is non-zero exactly when the rotation vector has an X component. The Ground fan's
            // rotation vector is authored with X = 0; the Omni one draws X from the full [-1, 1].
            if (FMath::Abs(Out.Orientation.Y) > 1.0e-3f)
            { ++OmniOffAxis; }
        }

        for (auto Seed = 0; Seed < 2000; ++Seed)
        {
            const auto Out = Evaluate_Id(kGroundId, 0.05f, Seed, 0.05f);
            if (Out.VisTag != 196)
            { continue; }

            if (FMath::Abs(Out.Orientation.Y) > 1.0e-3f)
            { ++GroundOffAxis; }
        }

        TestTrue(TEXT("the sweep sampled a real population of spikes"), Spikes > 100);
        TestTrue(TEXT("Omni spikes point out of the YZ plane"), OmniOffAxis > Spikes / 2);
        TestEqual(TEXT("Ground spikes never do — its rotation vector's X is exactly zero"), GroundOffAxis, 0);
    }

    // ---- THE EVENT COLLAPSE holds on this variant too ----
    {
        auto Compared = 0;
        auto Worst    = 0.0f;

        for (auto Strand = 0; Strand < kStrands; ++Strand)
        {
            for (const auto Step : { 0, 7, 19, 33, 42 })
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
        TestEqual(TEXT("a trail point sits EXACTLY on its leader's path"), Worst, 0.0f);

        TestEqual(TEXT("a ribbon-bank particle draws through the trail renderer"),
            Evaluate_Ribbon(0.06f, 0).VisTag, kVisRibbon);

        auto MainBankOnTrail = 0;
        for (auto Seed = 0; Seed < 5000; ++Seed)
        {
            if (Evaluate(0.06f, Seed).VisTag == kVisRibbon)
            { ++MainBankOnTrail; }
        }
        TestEqual(TEXT("no main-bank particle ever reaches the trail renderer"), MainBankOnTrail, 0);
    }

    // ---- Emitter-clock independence ----
    {
        auto Moved = 0;
        for (auto Seed = 0; Seed < 400; ++Seed)
        {
            const auto A = Evaluate_Id(kBehaviorId, 0.12f, Seed, 0.12f);
            const auto B = Evaluate_Id(kBehaviorId, 0.12f, Seed, 9.99f);

            if (NOT A.Position.Equals(B.Position) || NOT A.Color.Equals(B.Color)
                || NOT A.Size.Equals(B.Size) || A.VisTag != B.VisTag)
            { ++Moved; }
        }
        TestEqual(TEXT("behavior 42 is INDEPENDENT of the emitter clock"), Moved, 0);
    }

    return true;
}
