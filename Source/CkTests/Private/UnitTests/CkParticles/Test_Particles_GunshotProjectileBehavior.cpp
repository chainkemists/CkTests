// Behavior-math gate for CkParticles BehaviorId 18 (GunshotProjectile) — the Vefects NS_Gunshot_Projectile
// recreation.
//
// This drives UCkParticles_DataInterface::Execute_Stage_CPU, the SAME CPU mirror a CPU sim runs, so it needs
// no Niagara system, no template asset, no RHI and no forked engine. Every other CkParticles gate on this
// behavior is an existence check, and an existence check passes just as happily against a behavior that
// outputs nothing.
//
// Expected values are the SOURCE's own values as transcribed in
// CkFoundation/Source/CkParticles/Cookbook/NS_Gunshot_Projectile.md §2/§5 — not values read back out of the
// implementation. The source has NO age-driven curve anywhere, so the strongest statement this gate can make
// is that each layer is CONSTANT across its whole life; a drifting value is the failure it exists to catch.
//
// Cannot pass vacuously: behavior 18's VisTags are 10 and 11 and the pre-switch default is 0, so every layer
// assertion here proves the switch actually reached case 18.

#include "Misc/AutomationTest.h"

#include "CkParticles/DataInterface/CkParticles_DataInterface.h"
#include "CkParticles/ScriptDefinition/CkParticles_ScriptDefinition_Naming.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

// Named (not anonymous) namespace: unity build fuses anonymous namespaces across concatenated TUs and two
// same-named constants collide.
namespace ck_test_particles_gunshot_projectile
{
    constexpr auto kBehaviorId = 18;

    constexpr auto kTolerance = 1.0e-4f;

    // Source facts (recipe §2/§5 against corpus v3), duplicated here on purpose: the test's job is to hold the
    // behavior to the SOURCE, so reading these out of the behavior's own header would make the gate tautological.
    constexpr auto kNumLayers = 3;
    constexpr auto kLifetime  = 10.0f; // Lifetime Mode = Direct Set, Lifetime 10 on all three emitters
    constexpr auto kDrift     = 0.01f; // Add Velocity (0.01, 0, 0) — direction load-bearing, magnitude not

    // The shared cadence row: system Loop Behavior Once / Loop Duration 10 s, three emitters bursting one
    // particle each at t=0. NS_Arrow_Projectile resolves to the identical numbers, which is why one row serves both.
    constexpr auto kRowAssetName       = TEXT("PS_CkParticles_Template_ProjectileTrio");
    constexpr auto kSourceLoopDuration = 10.0f;
    constexpr auto kSourceBurstCount   = 3;

    constexpr auto kVisTagGlow = 10; // row renderer bound to PartDisAdd01
    constexpr auto kVisTagPart = 11; // row renderer bound to PartDisAdd04, shared by both tails

    // A seed whose layer is InLayer. Seeds are Particles.UniqueID and the partition is Seed % 3, so any
    // representative of the residue class works — and every representative must behave identically here,
    // because this system has no per-particle randomness at all.
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
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Particles_GunshotProjectileBehavior,
    "CkTests.UnitTests.CkParticles.GunshotProjectileBehavior",
    kCkUnitTestFlags)

bool FCkTest_Particles_GunshotProjectileBehavior::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_gunshot_projectile;

    // ---- The cadence row IS the fidelity claim, and it is SHARED with behavior 19 ----
    // Approximating a 10 s Loop-Once system onto the nearest existing row was the mistake this campaign's
    // first port already paid for once.
    {
        TestEqual(TEXT("behavior 18 routes to the ProjectileTrio row"),
            ck::particles::Get_BehaviorTemplateSystemObjectPath(kBehaviorId),
            ck::particles::Get_ProjectileTrioTemplateSystemObjectPath());

        TestEqual(TEXT("behavior 19 routes to the SAME row — the two projectiles share one cadence"),
            ck::particles::Get_BehaviorTemplateSystemObjectPath(19),
            ck::particles::Get_ProjectileTrioTemplateSystemObjectPath());

        TestEqual(TEXT("behavior 18 binds no CkUsf look — both its looks ride the row's renderers"),
            ck::particles::Get_BehaviorLookName(kBehaviorId), NAME_None);

        const auto* RowSpec = static_cast<const ck::particles::FCk_ParticlesTemplateSpec*>(nullptr);
        for (const auto& Spec : ck::particles::Get_TemplateSpecs())
        {
            if (FString(Spec.AssetName) == FString(kRowAssetName))
            { RowSpec = &Spec; break; }
        }

        if (TestNotNull(TEXT("the cadence table declares a PS_CkParticles_Template_ProjectileTrio row"), RowSpec))
        {
            TestEqual(TEXT("row loop duration matches the source SYSTEM's 10 s"),
                RowSpec->LoopDuration, kSourceLoopDuration, kTolerance);
            TestEqual(TEXT("row particle lifetime matches the source's resolved 10 s"),
                RowSpec->ParticleLifetime, kLifetime, kTolerance);
            TestEqual(TEXT("row burst count matches the source's three emitters at Spawn Time 0"),
                RowSpec->BurstCount, kSourceBurstCount);
        }
    }

    // ---- The 3-slot partition: every burst draws exactly one particle per source emitter ----
    // A drifted modulo would silently collapse two source emitters onto one layer, which reads as a missing
    // streak rather than as an error.
    {
        auto SeenVisTags = TSet<int32>{};
        for (auto Layer = 0; Layer < kNumLayers; ++Layer)
        { SeenVisTags.Add(Evaluate(1.0f, Get_SeedForLayer(Layer, 0)).VisTag); }

        TestTrue(TEXT("the three layers cover both row renderers"),
            SeenVisTags.Contains(kVisTagGlow) && SeenVisTags.Contains(kVisTagPart));
        TestEqual(TEXT("the three layers use exactly the two row renderers and nothing else"),
            SeenVisTags.Num(), 2);

        // The partition is by residue, so seed + 3 lands on the same layer no matter which burst it came from.
        for (auto Layer = 0; Layer < kNumLayers; ++Layer)
        {
            for (const auto Repeat : { 3, 11, 907 })
            {
                TestEqual(*FString::Printf(TEXT("layer %d is stable across bursts (burst %d)"), Layer, Repeat),
                    Evaluate(1.0f, Get_SeedForLayer(Layer, 0)).VisTag,
                    Evaluate(1.0f, Get_SeedForLayer(Layer, Repeat)).VisTag);
            }
        }
    }

    // ---- Every VisTag the behavior writes is inside the roster's renderer set ----
    // Row-declared renderers live above the shared 0..4 band; a tag past the roster maximum draws with NO
    // renderer, which is invisible and silent.
    {
        const auto RosterMax = ck::particles::Get_RosterVisTag_Max();
        TestTrue(TEXT("the roster VisTag maximum covers the ProjectileTrio row's renderers"),
            RosterMax >= kVisTagPart);

        for (auto Layer = 0; Layer < kNumLayers; ++Layer)
        {
            const auto Out = Evaluate(1.0f, Get_SeedForLayer(Layer, 0));
            TestTrue(*FString::Printf(TEXT("layer %d writes a VisTag inside the roster set"), Layer),
                Out.VisTag >= 0 && Out.VisTag <= RosterMax);
        }
    }

    // ---- Per-layer constants: colour, size, offset, dynamic params, VisTag ----
    // The source's three Initialize Particle modules, verbatim. Sampled at several ages because the ONLY
    // correct answer is "the same at every age" — see the constancy sweep below.
    {
        struct FLayerFacts
        {
            int32        Layer;
            FLinearColor Color;
            FVector2f    Size;
            FVector3f    Position;
            float        Dissolve;
            int32        VisTag;
        };

        const FLayerFacts Facts[] =
        {
            { 0, FLinearColor(1.0f, 0.194618f,  0.021219f,   0.5f), FVector2f(80.0f, 300.0f), FVector3f(-52.048f,  0.0f, 0.0f), 1.0f, kVisTagGlow },
            { 1, FLinearColor(1.0f, 0.552046f,  0.147f,      1.0f), FVector2f(20.0f, 200.0f), FVector3f(-77.6262f, 0.0f, 0.0f), 0.0f, kVisTagPart },
            { 2, FLinearColor(0.1f, 0.0171441f, 0.00865005f, 0.2f), FVector2f(35.0f, 500.0f), FVector3f(-194.751f, 0.0f, 0.0f), 0.0f, kVisTagPart },
        };

        for (const auto& Fact : Facts)
        {
            for (const auto Age : { 0.0f, 0.5f, 4.9f, 9.9f })
            {
                const auto Out = Evaluate(Age, Get_SeedForLayer(Fact.Layer, 0));

                TestTrue(*FString::Printf(TEXT("layer %d colour at age %.1f"), Fact.Layer, Age),
                    Out.Color.Equals(Fact.Color, kTolerance));
                TestTrue(*FString::Printf(TEXT("layer %d sprite size at age %.1f"), Fact.Layer, Age),
                    Out.Size.Equals(Fact.Size, kTolerance));
                TestTrue(*FString::Printf(TEXT("layer %d position offset at age %.1f"), Fact.Layer, Age),
                    Out.Position.Equals(Fact.Position, 1.0e-3f));
                TestEqual(*FString::Printf(TEXT("layer %d dissolve channel at age %.1f"), Fact.Layer, Age),
                    Out.Dynamic.X, Fact.Dissolve, kTolerance);
                TestEqual(*FString::Printf(TEXT("layer %d distortion channel is 0 at age %.1f"), Fact.Layer, Age),
                    Out.Dynamic.Y, 0.0f, kTolerance);
                TestEqual(*FString::Printf(TEXT("layer %d offset channel is 0 at age %.1f"), Fact.Layer, Age),
                    Out.Dynamic.Z, 0.0f, kTolerance);
                TestEqual(*FString::Printf(TEXT("layer %d core_color channel is 0 at age %.1f"), Fact.Layer, Age),
                    Out.Dynamic.W, 0.0f, kTolerance);
                TestEqual(*FString::Printf(TEXT("layer %d VisTag at age %.1f"), Fact.Layer, Age),
                    Out.VisTag, Fact.VisTag);
            }
        }

        // Only Glow_01 erodes: the whole system's dissolve authoring is one channel on one layer.
        TestEqual(TEXT("exactly one layer drives the dissolve channel"),
            (Evaluate(1.0f, Get_SeedForLayer(0, 0)).Dynamic.X > 0.0f ? 1 : 0) +
            (Evaluate(1.0f, Get_SeedForLayer(1, 0)).Dynamic.X > 0.0f ? 1 : 0) +
            (Evaluate(1.0f, Get_SeedForLayer(2, 0)).Dynamic.X > 0.0f ? 1 : 0), 1);

        // The dark tail is the longest and the glow head the widest — the silhouette read of the whole effect.
        TestTrue(TEXT("the dark tail is the longest streak"),
            Evaluate(1.0f, Get_SeedForLayer(2, 0)).Size.Y > Evaluate(1.0f, Get_SeedForLayer(1, 0)).Size.Y);
        TestTrue(TEXT("the dark tail sits furthest back along -X"),
            Evaluate(1.0f, Get_SeedForLayer(2, 0)).Position.X < Evaluate(1.0f, Get_SeedForLayer(1, 0)).Position.X);
    }

    // ---- Nothing varies with age, and nothing varies with the particle's own seed ----
    // The recipe's single most useful fact: not one age-driven curve exists in this system. A per-particle
    // random or a stray curve would read as a shimmering trail the source never has.
    for (auto Layer = 0; Layer < kNumLayers; ++Layer)
    {
        const auto Reference = Evaluate(0.0f, Get_SeedForLayer(Layer, 0));

        for (auto Step = 1; Step <= 40; ++Step)
        {
            const auto Age = kLifetime * static_cast<float>(Step) / 41.0f;
            for (const auto Repeat : { 0, 1, 12, 333 })
            {
                const auto Out = Evaluate(Age, Get_SeedForLayer(Layer, Repeat));

                if (Out.Color.Equals(Reference.Color, kTolerance) && Out.Size.Equals(Reference.Size, kTolerance) &&
                    Out.Position.Equals(Reference.Position, 1.0e-3f) && Out.VisTag == Reference.VisTag &&
                    FMath::IsNearlyEqual(Out.Dynamic.X, Reference.Dynamic.X, kTolerance))
                { continue; }

                AddError(FString::Printf(
                    TEXT("layer %d is not constant: age %.3f / burst %d differs from the spawn sample"),
                    Layer, Age, Repeat));
                break;
            }
        }
    }

    // ---- Kinematics: every layer drifts along local +X so VelocityAligned has a defined axis ----
    // The magnitude is irrelevant and the direction is not: drop it and Niagara's velocity alignment degenerates.
    for (auto Layer = 0; Layer < kNumLayers; ++Layer)
    {
        const auto V = Evaluate(1.0f, Get_SeedForLayer(Layer, 0)).Velocity;

        TestEqual(*FString::Printf(TEXT("layer %d drifts at the source's 0.01 u/s"), Layer), V.X, kDrift, kTolerance);
        TestEqual(*FString::Printf(TEXT("layer %d has no Y velocity"), Layer), V.Y, 0.0f, kTolerance);
        TestEqual(*FString::Printf(TEXT("layer %d has no Z velocity"), Layer), V.Z, 0.0f, kTolerance);
    }

    // ---- Anti-vacuity: every layer contributes visible light somewhere in its life ----
    // A layer whose colour or alpha collapsed to zero would still satisfy a constancy check; this is what says
    // the layer is actually drawn.
    for (auto Layer = 0; Layer < kNumLayers; ++Layer)
    {
        auto PeakLuminance = 0.0f;
        for (auto Step = 0; Step <= 20; ++Step)
        {
            const auto Out = Evaluate(kLifetime * static_cast<float>(Step) / 20.0f, Get_SeedForLayer(Layer, 0));
            PeakLuminance = FMath::Max(PeakLuminance, (Out.Color.R + Out.Color.G + Out.Color.B) * Out.Color.A);
        }
        TestTrue(*FString::Printf(TEXT("layer %d emits nonzero colour x alpha somewhere in its life"), Layer),
            PeakLuminance > kTolerance);

        TestFalse(*FString::Printf(TEXT("layer %d is alive at the last instant of its 10 s life"), Layer),
            Is_Hidden(Evaluate(kLifetime, Get_SeedForLayer(Layer, 0))));
    }

    // ---- Past the source's own lifetime every layer outputs nothing ----
    // The source's Particle State kills on elapse; a layer that kept drawing would leave a bullet trail hanging
    // in the air if the cadence row is ever retuned longer than the source's 10 s.
    for (auto Layer = 0; Layer < kNumLayers; ++Layer)
    {
        for (const auto Age : { kLifetime + 0.001f, kLifetime + 5.0f })
        {
            TestTrue(*FString::Printf(TEXT("layer %d is dead past its 10 s life (age %.3f)"), Layer, Age),
                Is_Hidden(Evaluate(Age, Get_SeedForLayer(Layer, 0))));
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
