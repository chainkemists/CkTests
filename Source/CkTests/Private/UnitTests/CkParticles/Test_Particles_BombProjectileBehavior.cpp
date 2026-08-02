// Behavior-math gate for CkParticles BehaviorId 37 (BombProjectile) — the Vefects NS_Bomb_Projectile
// recreation, and the cookbook's only DISTANCE-driven trail.
//
// Drives UCkParticles_DataInterface::Execute_Stage_CPU, the SAME CPU mirror a CPU sim runs, so it needs
// no Niagara system, no template asset, no RHI and no forked engine.
//
// Expected values are the SOURCE's own values as transcribed in
// CkFoundation/Source/CkParticles/Cookbook/NS_Bomb_Projectile.md §2/§5.
//
// The load-bearing claims specific to this port:
//   - the FUSE. The prop's Scale Color holds RGB at a quarter for 91.4% of the flight and then ramps to
//     5x in the last 0.215 s. A "fade out" simplification inverts the whole read, so the assertion pins
//     both ends of the ramp AND a point on it;
//   - the glow shells are CONSTANT. Their Scale Color module is DISABLED in the source, so an
//     implementation that transcribed its authored alpha curve anyway would fade them out — asserted at
//     both ends of the 2.5 s life;
//   - the TRAIL emits nothing while the leader does not travel. `Spawn Per Unit` gates on the emitter's
//     own movement delta, so at a stationary spawn point the SOURCE draws no trail either; drawing one
//     here would be the parity error, not the fix. The assertion is two-sided: the trail branch is
//     reached (VisTag 166) and produces nothing;
//   - the row declares no spawn rate, so behavior 37 must stay INDEPENDENT of the emitter clock.
//
// Cannot pass vacuously: behavior 37's VisTags are 164..166 and the pre-switch default is 0.

#include "Misc/AutomationTest.h"

#include "CkParticles/DataInterface/CkParticles_DataInterface.h"
#include "CkParticles/ScriptDefinition/CkParticles_ScriptDefinition_Naming.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_particles_bomb_projectile
{
    constexpr auto kBehaviorId = 37;
    constexpr auto kTolerance  = 1.0e-4f;

    // Source facts (recipe §2/§6.1 against corpus v3). The system is Loop Once / 2.5 s — the only 2.5 in
    // the cookbook, and it matches this system's own 2.5 s particle lifetimes exactly.
    constexpr auto kLoop         = 2.5f;
    constexpr auto kLifetime     = 2.5f;
    constexpr auto kBurst        = 4;   // 3 Bomb_Glow + 1 Bomb
    constexpr auto kRibbonPoints = 17;  // one per arc-length sample of the leader's path

    constexpr auto kRowAssetName = TEXT("PS_CkParticles_Template_BombProjectile");

    constexpr auto kVisPart01 = 164;
    constexpr auto kVisBomb   = 165;
    constexpr auto kVisTrail  = 166;

    // The fuse: Scale Color's RGBA-together curve, (0.9139752, 0.25) -> (1, 5), clamped before the first key.
    constexpr auto kFuseKeyT   = 0.9139752f;
    constexpr auto kFuseHold   = 0.25f;
    constexpr auto kFuseFlash  = 5.0f;

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

    // The seed slots the source's per-emitter burst counts carve out: three glows, then the prop.
    auto Get_GlowSeed() -> int32 { return 0; }
    auto Get_BombSeed() -> int32 { return 3; }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Particles_BombProjectileBehavior,
    "CkTests.UnitTests.CkParticles.BombProjectileBehavior",
    kCkUnitTestFlags)

bool FCkTest_Particles_BombProjectileBehavior::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_bomb_projectile;

    // ---- The cadence row, and the ribbon emitter it declares ----
    {
        TestEqual(TEXT("behavior 37 routes to the BombProjectile row"),
            ck::particles::Get_BehaviorTemplateSystemObjectPath(kBehaviorId),
            ck::particles::Get_BombProjectileTemplateSystemObjectPath());

        TestEqual(TEXT("behavior 37 binds no CkUsf look — both its looks ride the row's renderers"),
            ck::particles::Get_BehaviorLookName(kBehaviorId), NAME_None);

        const auto* RowSpec = static_cast<const ck::particles::FCk_ParticlesTemplateSpec*>(nullptr);
        for (const auto& Spec : ck::particles::Get_TemplateSpecs())
        {
            if (FString(Spec.AssetName) == FString(kRowAssetName))
            { RowSpec = &Spec; break; }
        }

        if (TestNotNull(TEXT("the cadence table declares a PS_CkParticles_Template_BombProjectile row"), RowSpec))
        {
            TestEqual(TEXT("row loop duration is the system's Loop Once / 2.5 s"),
                RowSpec->LoopDuration, kLoop, kTolerance);
            TestEqual(TEXT("row particle lifetime is the burst emitters' own 2.5 s"),
                RowSpec->ParticleLifetime, kLifetime, kTolerance);
            TestEqual(TEXT("row burst is 3 glows + 1 prop"), RowSpec->BurstCount, kBurst);
            TestEqual(TEXT("the row declares NO spawn rate — nothing in this source streams"),
                RowSpec->SpawnRate, 0.0f, kTolerance);

            const auto& Ribbon = RowSpec->RibbonEmitter;
            TestTrue(TEXT("the row declares a ribbon emitter"), Ribbon.Get_IsDeclared());
            TestEqual(TEXT("the ribbon emitter bursts one point per arc-length sample"),
                Ribbon.BurstCount, kRibbonPoints);
            TestEqual(TEXT("the ribbon emitter declares no RATE — the source spawns per unit, not per second"),
                Ribbon.SpawnRate, 0.0f, kTolerance);
            TestEqual(TEXT("the source has one trail, so the row has one ribbon renderer"),
                Ribbon.Renderers.Num(), 1);

            if (Ribbon.Renderers.Num() == 1)
            {
                const auto& Renderer = Ribbon.Renderers[0];
                TestTrue(TEXT("the ribbon renderer is the Ribbon kind"),
                    Renderer.Kind == ck::particles::ECk_ParticlesRenderer_Kind::Ribbon);
                TestEqual(TEXT("the ribbon renderer draws the TrailDisAdd01 look"),
                    FString(Renderer.LookName), FString(TEXT("TrailDisAdd01")));
                TestEqual(TEXT("the ribbon renderer's VisTag is the one the behavior writes"),
                    Renderer.VisTag, kVisTrail);
                TestNull(TEXT("a ribbon has no carrier mesh"), Renderer.MeshName);
            }
        }
    }

    // ---- The burst partition: three glows and one prop, exactly, every loop ----
    {
        auto Glows = 0;
        auto Props = 0;

        for (auto Seed = 0; Seed < kBurst; ++Seed)
        {
            const auto Out = Evaluate(1.0f, Seed);

            if (Out.VisTag == kVisPart01) { ++Glows; }
            if (Out.VisTag == kVisBomb)   { ++Props; }
        }

        TestEqual(TEXT("one loop's burst carries exactly three Bomb_Glow shells"), Glows, 3);
        TestEqual(TEXT("one loop's burst carries exactly one Bomb prop"), Props, 1);

        // Over many moduli the ratio holds, so the partition is a real modulus and not a lucky prefix.
        auto WideGlows = 0;
        for (auto Seed = 0; Seed < kBurst * 500; ++Seed)
        {
            if (Evaluate(1.0f, Seed).VisTag == kVisPart01)
            { ++WideGlows; }
        }
        TestEqual(TEXT("the 3:1 partition holds across 500 moduli"), WideGlows, 3 * 500);
    }

    // ---- Bomb_Glow: identical, coincident, and CONSTANT for the whole 2.5 s ----
    {
        const auto Seed = Get_GlowSeed();

        for (const auto Age : { 0.0f, 1.25f, 2.5f })
        {
            const auto Out = Evaluate(Age, Seed);

            TestEqual(*FString::Printf(TEXT("Bomb_Glow holds its blue at age %.2f"), Age),
                Out.Color.B, 1.0f, kTolerance);
            TestEqual(*FString::Printf(TEXT("Bomb_Glow holds its red at age %.2f"), Age),
                Out.Color.R, 0.0368895f, kTolerance);
            TestEqual(*FString::Printf(TEXT("Bomb_Glow holds its green at age %.2f"), Age),
                Out.Color.G, 0.184475f, kTolerance);
            // The DISABLED Scale Color is the whole claim: its authored alpha curve runs 1 -> 0, so an
            // implementation that ran it would read 0 here at the end of life.
            TestEqual(*FString::Printf(TEXT("Bomb_Glow holds alpha 0.5 at age %.2f — its Scale Color is DISABLED"), Age),
                Out.Color.A, 0.5f, kTolerance);
            TestEqual(*FString::Printf(TEXT("Bomb_Glow holds its 300-unit size at age %.2f"), Age),
                Out.Size.X, 300.0f, kTolerance);
            TestEqual(*FString::Printf(TEXT("Bomb_Glow drives dissolve 2 at age %.2f"), Age),
                Out.Dynamic.X, 2.0f, kTolerance);
        }

        TestTrue(TEXT("Bomb_Glow is gone once its 2.5 s is up"), Is_Hidden(Evaluate(2.6f, Seed)));
    }

    // ---- Bomb: the prop, and the fuse burning down ----
    {
        const auto Seed = Get_BombSeed();

        const auto Held = Evaluate(kLoop * kFuseKeyT, Seed);
        TestEqual(TEXT("the prop sits at a quarter brightness right up to its 0.9139752 key"),
            Held.Color.R, kFuseHold, kTolerance);
        TestEqual(TEXT("the hold is flat, not a ramp — the same quarter at t=0"),
            Evaluate(0.0f, Seed).Color.R, kFuseHold, kTolerance);

        const auto Flash = Evaluate(kLoop, Seed);
        TestEqual(TEXT("the prop flashes to 5x by the end of the flight"), Flash.Color.R, kFuseFlash, kTolerance);
        TestEqual(TEXT("the flash is white — the curve drives RGB together"), Flash.Color.G, kFuseFlash, kTolerance);
        TestEqual(TEXT("the prop's alpha is a single key at 1 and never moves"), Flash.Color.A, 1.0f, kTolerance);

        // A point ON the ramp: 0.25 + 4.75 * (0.95 - 0.9139752) / (1 - 0.9139752).
        const auto Mid = Evaluate(kLoop * 0.95f, Seed);
        TestEqual(TEXT("the fuse is a linear ramp, not a step (2.2391682 at t=0.95)"),
            Mid.Color.R, 2.2391682f, kTolerance);

        TestEqual(TEXT("the prop draws through the mesh renderer"), Flash.VisTag, kVisBomb);
        TestEqual(TEXT("the prop rides the row's only carrier mesh"), Flash.MeshIndex, 0);
        TestEqual(TEXT("the prop's Mesh Uniform Scale is the source's 0.45"), Flash.Scale.X, 0.45f, kTolerance);
        TestTrue(TEXT("the prop's orientation is a unit quaternion"), Flash.Orientation.IsNormalized());
        TestTrue(TEXT("the prop writes no sprite quad"), Flash.Size.IsNearlyZero());

        // The yaw is per-particle and FIXED — this emitter carries no Update Mesh Orientation, unlike its
        // NS_Bomb_Spawn twin, so the same particle must not turn over its life.
        const auto Early = Evaluate(0.1f, Seed);
        const auto Late  = Evaluate(2.4f, Seed);
        TestEqual(TEXT("the prop's yaw is fixed at spawn and never spins"),
            Early.Orientation.Z, Late.Orientation.Z, kTolerance);

        TestTrue(TEXT("the prop is gone once its 2.5 s is up"), Is_Hidden(Evaluate(2.6f, Seed)));
    }

    // ---- The distance-driven trail ----
    {
        // The branch IS reached — this is not a dead code path hiding behind an unreachable seed bank.
        auto TrailTags = TSet<int32>{};
        for (auto Local = 0; Local < kRibbonPoints * 3; ++Local)
        { TrailTags.Add(Evaluate_Ribbon(1.0f, Local).VisTag); }

        TestEqual(TEXT("every ribbon-bank particle reaches the trail renderer and nothing else"),
            TrailTags.Num(), 1);
        TestTrue(TEXT("the trail branch writes the trail VisTag"), TrailTags.Contains(kVisTrail));

        // ...and produces nothing, because the leader does not travel. Spawn Per Unit gates on the
        // emitter's movement delta against a 0.5-unit tolerance, so the SOURCE emits no trail either at a
        // stationary spawn point. Both sides of the A/B pedestal draw no trail; that IS the parity.
        auto AnyDrawn = false;
        for (auto Local = 0; Local < kRibbonPoints * 3; ++Local)
        {
            for (const auto Age : { 0.0f, 0.3f, 0.6f, 1.25f, 2.5f })
            {
                if (NOT Is_Hidden(Evaluate_Ribbon(Age, Local)))
                { AnyDrawn = true; }
            }
        }
        TestFalse(TEXT("a trail whose leader never travels places no points — the source's own behaviour"),
            AnyDrawn);
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
                    || Reference.Size != Shifted.Size)
                { ++Moved; }
            }
        }

        TestEqual(TEXT("behavior 37 ignores the emitter clock — its row declares one population"), Moved, 0);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
