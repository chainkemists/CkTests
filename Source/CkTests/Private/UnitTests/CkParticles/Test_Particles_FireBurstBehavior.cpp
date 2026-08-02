// Behavior-math gate for CkParticles BehaviorId 20 (FireBurst) — the Vefects NS_Fire recreation.
//
// Drives UCkParticles_DataInterface::Execute_Stage_CPU, the SAME CPU mirror a CPU sim runs, so it needs no
// Niagara system, no template asset, no RHI and no forked engine. Every other CkParticles gate on this behavior
// is an existence check, and an existence check passes just as happily against a behavior that outputs nothing.
//
// Expected values are the SOURCE's own values as transcribed in
// CkFoundation/Source/CkParticles/Cookbook/NS_Fire.md §2/§5 — not values read back out of the implementation.
// The clamped-key lerp is re-implemented here on purpose: the KEYS are the fidelity claim, not the lerp.
//
// Cannot pass vacuously: behavior 20's VisTags are 12..14 and the pre-switch default is 0, so every layer
// assertion here proves the switch actually reached case 20.

#include "Misc/AutomationTest.h"

#include "CkParticles/DataInterface/CkParticles_DataInterface.h"
#include "CkParticles/ScriptDefinition/CkParticles_ScriptDefinition_Naming.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

// Named (not anonymous) namespace: unity build fuses anonymous namespaces across concatenated TUs and two
// same-named constants collide.
namespace ck_test_particles_fire_burst
{
    constexpr auto kBehaviorId = 20;
    constexpr auto kTolerance  = 1.0e-4f;

    // Source facts (recipe §2/§5 against corpus v3), duplicated here on purpose: the test's job is to hold the
    // behavior to the SOURCE, so reading these out of the behavior's own header would make the gate tautological.
    constexpr auto kNumLayers = 10;
    constexpr auto kLifetime  = 1.0f;  // Sparkles' resolved Lifetime Max, the longest layer
    constexpr auto kLoop      = 2.0f;  // the system's Loop-Once duration
    constexpr auto kDelay     = 0.05f; // Spawn Time on all but the sparkles

    constexpr auto kRowAssetName = TEXT("PS_CkParticles_Template_FireBurst");

    constexpr auto kVisTagGlow    = 12;
    constexpr auto kVisTagFlame   = 13;
    constexpr auto kVisTagSparkle = 14;

    constexpr auto kFirstFlame   = 2;
    constexpr auto kFirstSparkle = 5;

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

    // The source's own curve interpolation: every key it authors is clamped or linear.
    auto Key2(float T, float T0, float V0, float T1, float V1) -> float
    {
        return FMath::Lerp(V0, V1, FMath::Clamp((T - T0) / FMath::Max(T1 - T0, 1.0e-6f), 0.0f, 1.0f));
    }

    auto Key3(float T, float T0, float V0, float T1, float V1, float T2, float V2) -> float
    {
        return T <= T1 ? Key2(T, T0, V0, T1, V1) : Key2(T, T1, V1, T2, V2);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Particles_FireBurstBehavior,
    "CkTests.UnitTests.CkParticles.FireBurstBehavior",
    kCkUnitTestFlags)

bool FCkTest_Particles_FireBurstBehavior::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_fire_burst;

    // ---- The cadence row IS the fidelity claim ----
    // Approximating a source's loop/lifetime/burst onto the nearest existing row was the mistake this campaign's
    // first port already paid for once.
    {
        TestEqual(TEXT("behavior 20 routes to the FireBurst row"),
            ck::particles::Get_BehaviorTemplateSystemObjectPath(kBehaviorId),
            ck::particles::Get_FireBurstTemplateSystemObjectPath());

        TestEqual(TEXT("behavior 20 binds no CkUsf look — all three of its looks ride the row's renderers"),
            ck::particles::Get_BehaviorLookName(kBehaviorId), NAME_None);

        const auto* RowSpec = static_cast<const ck::particles::FCk_ParticlesTemplateSpec*>(nullptr);
        for (const auto& Spec : ck::particles::Get_TemplateSpecs())
        {
            if (FString(Spec.AssetName) == FString(kRowAssetName))
            { RowSpec = &Spec; break; }
        }

        if (TestNotNull(TEXT("the cadence table declares a PS_CkParticles_Template_FireBurst row"), RowSpec))
        {
            TestEqual(TEXT("row loop duration matches the source SYSTEM's Loop-Once 2.0 s"),
                RowSpec->LoopDuration, kLoop, kTolerance);
            TestEqual(TEXT("row particle lifetime matches the longest resolved layer (Sparkles, 1.0 s)"),
                RowSpec->ParticleLifetime, kLifetime, kTolerance);
            TestEqual(TEXT("row burst count is the MAXIMUM per-loop count, 1 + 1 + 3 + 5"),
                RowSpec->BurstCount, kNumLayers);

            // The flame layer is the only sub-UV renderer in this system, and a renderer that declares no grid
            // divides nothing — so a dropped SubImageSize is silent, not loud.
            auto SawFlameSheet = false;
            for (const auto& Renderer : RowSpec->RendererOverrides)
            {
                if (Renderer.VisTag != kVisTagFlame)
                { continue; }

                SawFlameSheet = Renderer.SubImageSize == FIntPoint(2, 2);
            }
            TestTrue(TEXT("the flame row renderer declares the source's 2x2 sub-UV grid"), SawFlameSheet);
        }
    }

    // ---- The 10-slot partition: each burst draws one of every source emitter particle ----
    {
        for (auto Layer = 0; Layer < kFirstFlame; ++Layer)
        {
            TestEqual(*FString::Printf(TEXT("layer %d is a Bomb_Glow on the Part01 renderer"), Layer),
                Evaluate(kDelay + 0.01f, Get_SeedForLayer(Layer, 0)).VisTag, kVisTagGlow);
        }
        for (auto Layer = kFirstFlame; Layer < kFirstSparkle; ++Layer)
        {
            TestEqual(*FString::Printf(TEXT("layer %d is a Flame on the sub-UV renderer"), Layer),
                Evaluate(kDelay + 0.01f, Get_SeedForLayer(Layer, 0)).VisTag, kVisTagFlame);
        }

        // The partition is by residue, so seed + 10 lands on the same layer no matter which burst it came from.
        for (auto Layer = 0; Layer < kFirstSparkle; ++Layer)
        {
            for (const auto Repeat : { 3, 11, 907 })
            {
                TestEqual(*FString::Printf(TEXT("layer %d is stable across bursts (burst %d)"), Layer, Repeat),
                    Evaluate(kDelay + 0.01f, Get_SeedForLayer(Layer, 0)).VisTag,
                    Evaluate(kDelay + 0.01f, Get_SeedForLayer(Layer, Repeat)).VisTag);
            }
        }
    }

    // ---- Every VisTag the behavior writes is inside the roster's renderer set ----
    // A tag past the roster maximum draws with NO renderer, which is invisible and silent.
    {
        const auto RosterMax = ck::particles::Get_RosterVisTag_Max();
        TestTrue(TEXT("the roster VisTag maximum covers the FireBurst row's renderers"),
            RosterMax >= kVisTagSparkle);

        for (auto Layer = 0; Layer < kNumLayers; ++Layer)
        {
            for (const auto Age : { 0.0f, 0.06f, 0.3f, 0.9f })
            {
                const auto Out = Evaluate(Age, Get_SeedForLayer(Layer, 0));
                TestTrue(*FString::Printf(TEXT("layer %d writes a VisTag inside the roster set"), Layer),
                    Out.VisTag >= 0 && Out.VisTag <= RosterMax);
            }
        }
    }

    // ---- The two glows: a constant Initialize colour under an alpha ramp, and NOTHING else ----
    // The source has no Color-from-Curve module on either, so inventing an RGB curve for them is the failure
    // mode this section exists to catch (recipe §6.7).
    {
        struct FGlowFacts { int32 Layer; float R; float G; float B; float Life; float Size; float Dissolve; };
        const FGlowFacts Facts[] =
        {
            { 0, 1.0f, 0.0908417f, 0.043735f, 0.25f, 500.0f, 1.0f },
            { 1, 1.0f, 0.496933f,  0.043735f, 0.2f,  400.0f, 0.0f },
        };

        for (const auto& Fact : Facts)
        {
            for (const auto Frac : { 0.0f, 0.25f, 0.6f, 1.0f })
            {
                const auto t   = Frac;
                const auto Out = Evaluate(kDelay + Fact.Life * t, Get_SeedForLayer(Fact.Layer, 0));

                TestEqual(*FString::Printf(TEXT("glow %d red is the Initialize constant at t %.2f"), Fact.Layer, t),
                    Out.Color.R, Fact.R, kTolerance);
                TestEqual(*FString::Printf(TEXT("glow %d green is the Initialize constant at t %.2f"), Fact.Layer, t),
                    Out.Color.G, Fact.G, kTolerance);
                TestEqual(*FString::Printf(TEXT("glow %d blue is the Initialize constant at t %.2f"), Fact.Layer, t),
                    Out.Color.B, Fact.B, kTolerance);

                // Scale Color's alpha ramp 1 -> 0 over the module's own Initialize alpha of 0.5.
                TestEqual(*FString::Printf(TEXT("glow %d alpha ramps over 0.5 at t %.2f"), Fact.Layer, t),
                    Out.Color.A, 0.5f * Key2(t, 0.0f, 1.0f, 1.0f, 0.0f), kTolerance);

                const auto Grow = Key3(t, 0.0f, 0.5f, 0.1f, 1.0f, 1.0f, 1.0f);
                TestEqual(*FString::Printf(TEXT("glow %d sprite size at t %.2f"), Fact.Layer, t),
                    Out.Size.X, Fact.Size * Grow, 1.0e-2f);

                TestEqual(*FString::Printf(TEXT("glow %d dissolve channel at t %.2f"), Fact.Layer, t),
                    Out.Dynamic.X, Fact.Dissolve, kTolerance);
            }
        }

        // Exactly one of the two erodes — the whole difference between them beyond colour and size.
        TestTrue(TEXT("Bomb_Glow_01 erodes and Bomb_Glow_02 does not"),
            Evaluate(kDelay, Get_SeedForLayer(0, 0)).Dynamic.X > 0.5f &&
            Evaluate(kDelay, Get_SeedForLayer(1, 0)).Dynamic.X < kTolerance);
    }

    // ---- The flames: HDR colour, a live distortion channel, and a sub-UV frame that advances with age ----
    {
        const auto Seed = Get_SeedForLayer(kFirstFlame, 0);

        // Colour keys start at t > 0, so the first key's value holds before it — the red channel opens at 5.
        const auto AtSpawn = Evaluate(kDelay, Seed);
        TestEqual(TEXT("flame red opens at the source's 5x HDR key"), AtSpawn.Color.R, 5.0f, kTolerance);
        TestEqual(TEXT("flame green opens at the source's 3.43343 HDR key"), AtSpawn.Color.G, 3.43343f, kTolerance);
        TestEqual(TEXT("flame alpha opens at zero"), AtSpawn.Color.A, 0.0f, kTolerance);

        TestEqual(TEXT("flame distortion channel is the source's constant 5"),
            AtSpawn.Dynamic.Y, 5.0f, kTolerance);
        TestEqual(TEXT("flame dissolve channel opens at 0"), AtSpawn.Dynamic.X, 0.0f, kTolerance);

        // The frame index must MOVE, and must stay inside the 2x2 sheet's four frames.
        auto SeenFrames = TSet<int32>{};
        for (auto Step = 0; Step <= 20; ++Step)
        {
            const auto Out = Evaluate(kDelay + 0.2f * static_cast<float>(Step) / 20.0f, Seed);
            TestTrue(TEXT("flame sub-image index stays inside the 2x2 sheet"),
                Out.SubImageIndex >= 0.0f && Out.SubImageIndex <= 3.0f);
            SeenFrames.Add(FMath::FloorToInt32(Out.SubImageIndex));
        }
        TestTrue(TEXT("the flame flipbook actually advances over life"), SeenFrames.Num() > 1);

        // Sprite rotation drifts at the source's own randomized rate, so it must not be constant.
        TestNotEqual(TEXT("flame sprite rotation spins"),
            Evaluate(kDelay, Seed).Rotation, Evaluate(kDelay + 0.19f, Seed).Rotation);
    }

    // ---- The sparkles: the batch's one RANDOMIZED burst count, resolved inside the behavior ----
    // The row declares the maximum of five and the surplus slots hide; the roll is per-LOOP, so every particle of
    // one burst must agree on it, and different bursts must not all agree (or the randomization is dead).
    {
        auto Rolls = TSet<int32>{};
        for (auto Burst = 0; Burst < 64; ++Burst)
        {
            auto AliveThisBurst = 0;
            for (auto Slot = 0; Slot < 5; ++Slot)
            {
                const auto Seed = Get_SeedForLayer(kFirstSparkle + Slot, Burst);
                if (NOT Is_Hidden(Evaluate(0.05f, Seed)))
                { ++AliveThisBurst; }
            }

            TestTrue(*FString::Printf(TEXT("burst %d draws 3..5 sparkles, the source's Random Range Int"), Burst),
                AliveThisBurst >= 3 && AliveThisBurst <= 5);
            Rolls.Add(AliveThisBurst);
        }

        TestTrue(TEXT("the per-loop sparkle count actually varies across bursts"), Rolls.Num() > 1);

        // A slot that survives the roll must keep surviving it — the roll is a property of the LOOP, not of age.
        for (auto Slot = 0; Slot < 5; ++Slot)
        {
            const auto Seed  = Get_SeedForLayer(kFirstSparkle + Slot, 0);
            const auto Early = Is_Hidden(Evaluate(0.02f, Seed));
            const auto Later = Is_Hidden(Evaluate(0.25f, Seed));
            if (Early && NOT Later)
            { AddError(FString::Printf(TEXT("sparkle slot %d was hidden by the roll and then reappeared"), Slot)); }
        }
    }

    // ---- Kinematics: both moving layers decay radially outward and never reverse ----
    for (const auto Layer : { kFirstFlame, kFirstSparkle })
    {
        const auto Seed  = Get_SeedForLayer(Layer, 0);
        const auto Delay = Layer == kFirstFlame ? kDelay : 0.0f;

        const auto Early = Evaluate(Delay + 0.01f, Seed);
        const auto Late  = Evaluate(Delay + 0.15f, Seed);

        if (Is_Hidden(Early) || Is_Hidden(Late))
        { continue; }

        TestTrue(*FString::Printf(TEXT("layer %d slows down over life (Scale Velocity decays)"), Layer),
            Late.Velocity.Size() < Early.Velocity.Size());
        TestTrue(*FString::Printf(TEXT("layer %d travels outward from the spawn point"), Layer),
            Late.Position.Size() > Early.Position.Size());
        TestTrue(*FString::Printf(TEXT("layer %d keeps moving along its spawn direction"), Layer),
            FVector3f::DotProduct(Early.Velocity.GetSafeNormal(), Late.Velocity.GetSafeNormal()) > 0.99f);
    }

    // ---- Anti-vacuity: every layer contributes visible light somewhere in its life ----
    // A layer whose colour or alpha collapsed to zero would still satisfy every structural check above.
    for (auto Layer = 0; Layer < kNumLayers; ++Layer)
    {
        auto PeakLuminance = 0.0f;
        for (auto Burst = 0; Burst < 32; ++Burst)
        {
            for (auto Step = 0; Step <= 40; ++Step)
            {
                const auto Out = Evaluate(kLifetime * static_cast<float>(Step) / 40.0f,
                                          Get_SeedForLayer(Layer, Burst));
                PeakLuminance = FMath::Max(PeakLuminance,
                    (Out.Color.R + Out.Color.G + Out.Color.B) * Out.Color.A * Out.Size.X);
            }
        }
        TestTrue(*FString::Printf(TEXT("layer %d emits nonzero colour x alpha x size somewhere in its life"), Layer),
            PeakLuminance > kTolerance);
    }

    // ---- Spawn delay and death: three layers hide before t = 0.05, and every layer dies on its own clock ----
    for (auto Layer = 0; Layer < kFirstSparkle; ++Layer)
    {
        TestTrue(*FString::Printf(TEXT("layer %d is hidden before its 0.05 s spawn time"), Layer),
            Is_Hidden(Evaluate(0.0f, Get_SeedForLayer(Layer, 0))) &&
            Is_Hidden(Evaluate(kDelay - 0.001f, Get_SeedForLayer(Layer, 0))));
    }

    // The template particle outlives every layer, so a layer that kept drawing would hang in the air.
    for (auto Layer = 0; Layer < kNumLayers; ++Layer)
    {
        for (const auto Age : { kLifetime + 0.001f, kLifetime + 0.5f })
        {
            for (auto Burst = 0; Burst < 8; ++Burst)
            {
                TestTrue(*FString::Printf(TEXT("layer %d is dead at age %.3f, past every resolved lifetime"), Layer, Age),
                    Is_Hidden(Evaluate(Age, Get_SeedForLayer(Layer, Burst))));
            }
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
