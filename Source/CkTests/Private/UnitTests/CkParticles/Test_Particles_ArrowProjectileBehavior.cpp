// Behavior-math gate for CkParticles BehaviorId 19 (ArrowProjectile) — the Vefects NS_Arrow_Projectile
// recreation.
//
// This drives UCkParticles_DataInterface::Execute_Stage_CPU, the SAME CPU mirror a CPU sim runs, so it needs
// no Niagara system, no template asset, no RHI and no forked engine.
//
// Expected values are the SOURCE's own values as transcribed in
// CkFoundation/Source/CkParticles/Cookbook/NS_Arrow_Projectile.md §2/§5 — not values read back out of the
// implementation. Like its Gunshot sibling the source has NO age-driven curve, so constancy across the whole
// life is the strongest statement this gate can make.
//
// The one structural difference from behavior 18 is the reason this file exists separately: Glow_01 is
// Unaligned/FaceCamera, so it draws on the SHARED camera sprite (VisTag 0) with its look bound through
// User.SpriteMaterial, while the two tails ride the row's own velocity-aligned renderer. That split is
// asserted here — a Glow_01 that drifted onto a row renderer would lose its camera facing silently.

#include "Misc/AutomationTest.h"

#include "CkParticles/DataInterface/CkParticles_DataInterface.h"
#include "CkParticles/ScriptDefinition/CkParticles_ScriptDefinition_Naming.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

// Named (not anonymous) namespace: unity build fuses anonymous namespaces across concatenated TUs and two
// same-named constants collide.
namespace ck_test_particles_arrow_projectile
{
    constexpr auto kBehaviorId = 19;

    constexpr auto kTolerance = 1.0e-4f;

    // Source facts (recipe §2/§5 against corpus v3).
    constexpr auto kNumLayers = 3;
    constexpr auto kLifetime  = 10.0f; // Lifetime Mode = Direct Set, Lifetime 10 on all three emitters
    constexpr auto kDrift     = 0.01f; // Add Velocity (0.01, 0, 0) on the two Projectile emitters ONLY

    constexpr auto kVisTagGlow = 0;  // shared camera sprite — the source's Unaligned / FaceCamera billboard
    constexpr auto kVisTagPart = 11; // row renderer bound to PartDisAdd04, shared with behavior 18

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
    FCkTest_Particles_ArrowProjectileBehavior,
    "CkTests.UnitTests.CkParticles.ArrowProjectileBehavior",
    kCkUnitTestFlags)

bool FCkTest_Particles_ArrowProjectileBehavior::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_arrow_projectile;

    // ---- Routing: the shared cadence row, plus the ONE look this behavior binds itself ----
    // The row's numbers are gated in GunshotProjectileBehavior, which owns them; here what matters is that
    // this behavior reaches the same row and that its camera-facing head has a material to draw with.
    {
        TestEqual(TEXT("behavior 19 routes to the ProjectileTrio row"),
            ck::particles::Get_BehaviorTemplateSystemObjectPath(kBehaviorId),
            ck::particles::Get_ProjectileTrioTemplateSystemObjectPath());

        TestEqual(TEXT("behavior 19 binds PartDisAdd01 for its VisTag-0 head"),
            ck::particles::Get_BehaviorLookName(kBehaviorId), FName(TEXT("PartDisAdd01")));

        TestFalse(TEXT("the bound look resolves a non-empty generated master path"),
            ck::particles::Get_GeneratedLookMasterObjectPath(
                ck::particles::Get_BehaviorLookName(kBehaviorId)).IsEmpty());
    }

    // ---- The 3-slot partition, split across the SHARED camera sprite and the row's streak renderer ----
    {
        auto SeenVisTags = TSet<int32>{};
        for (auto Layer = 0; Layer < kNumLayers; ++Layer)
        { SeenVisTags.Add(Evaluate(1.0f, Get_SeedForLayer(Layer, 0)).VisTag); }

        TestTrue(TEXT("the three layers cover the camera sprite and the row's streak renderer"),
            SeenVisTags.Contains(kVisTagGlow) && SeenVisTags.Contains(kVisTagPart));
        TestEqual(TEXT("the three layers use exactly those two renderers and nothing else"),
            SeenVisTags.Num(), 2);

        for (auto Layer = 0; Layer < kNumLayers; ++Layer)
        {
            for (const auto Repeat : { 3, 11, 907 })
            {
                TestEqual(*FString::Printf(TEXT("layer %d is stable across bursts (burst %d)"), Layer, Repeat),
                    Evaluate(1.0f, Get_SeedForLayer(Layer, 0)).VisTag,
                    Evaluate(1.0f, Get_SeedForLayer(Layer, Repeat)).VisTag);
            }
        }

        // The head is the one layer that must NOT ride a row renderer: VisTag 0 is what makes it billboard.
        TestEqual(TEXT("Glow_01 draws on the shared camera sprite, not on a row renderer"),
            Evaluate(1.0f, Get_SeedForLayer(0, 0)).VisTag, kVisTagGlow);

        const auto RosterMax = ck::particles::Get_RosterVisTag_Max();
        for (auto Layer = 0; Layer < kNumLayers; ++Layer)
        {
            const auto Out = Evaluate(1.0f, Get_SeedForLayer(Layer, 0));
            TestTrue(*FString::Printf(TEXT("layer %d writes a VisTag inside the roster set"), Layer),
                Out.VisTag >= 0 && Out.VisTag <= RosterMax);
        }
    }

    // ---- Per-layer constants: colour, size, offset, dynamic params, VisTag ----
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
            { 0, FLinearColor(1.0f,  0.775394f,  0.257f,     0.3f), FVector2f(120.0f, 120.0f), FVector3f(-5.0f,     0.0f, 0.0f), 1.0f, kVisTagGlow },
            { 1, FLinearColor(1.0f,  0.558341f,  0.102242f,  0.5f), FVector2f(20.0f,   50.0f), FVector3f(-20.1693f, 0.0f, 0.0f), 0.0f, kVisTagPart },
            { 2, FLinearColor(0.06f, 0.0470123f, 0.0270472f, 0.2f), FVector2f(35.0f,  150.0f), FVector3f(-66.0904f, 0.0f, 0.0f), 0.0f, kVisTagPart },
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

        // Uniform Sprite Size 120 — the head is the only ROUND layer; both tails are stretched streaks.
        TestEqual(TEXT("the head is square (Sprite Size Mode = Uniform)"),
            Evaluate(1.0f, Get_SeedForLayer(0, 0)).Size.X,
            Evaluate(1.0f, Get_SeedForLayer(0, 0)).Size.Y, kTolerance);
        TestTrue(TEXT("both tails are stretched along the streak axis"),
            Evaluate(1.0f, Get_SeedForLayer(1, 0)).Size.Y > Evaluate(1.0f, Get_SeedForLayer(1, 0)).Size.X &&
            Evaluate(1.0f, Get_SeedForLayer(2, 0)).Size.Y > Evaluate(1.0f, Get_SeedForLayer(2, 0)).Size.X);

        // Only Glow_01 erodes — one dissolve channel on one layer, exactly as in the Gunshot sibling.
        TestEqual(TEXT("exactly one layer drives the dissolve channel"),
            (Evaluate(1.0f, Get_SeedForLayer(0, 0)).Dynamic.X > 0.0f ? 1 : 0) +
            (Evaluate(1.0f, Get_SeedForLayer(1, 0)).Dynamic.X > 0.0f ? 1 : 0) +
            (Evaluate(1.0f, Get_SeedForLayer(2, 0)).Dynamic.X > 0.0f ? 1 : 0), 1);

        // The arrow is the SHORT projectile: its dark tail sits 66 units back against the Gunshot's 195, which
        // is most of what separates an arrow from a bullet in this pack.
        TestTrue(TEXT("the dark tail sits further back than the bright one but well inside the Gunshot's reach"),
            Evaluate(1.0f, Get_SeedForLayer(2, 0)).Position.X < Evaluate(1.0f, Get_SeedForLayer(1, 0)).Position.X &&
            Evaluate(1.0f, Get_SeedForLayer(2, 0)).Position.X > -100.0f);
    }

    // ---- Nothing varies with age, and nothing varies with the particle's own seed ----
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

    // ---- Kinematics: the two tails drift along +X, the camera-facing head does not move at all ----
    // Glow_01 has no Add Velocity module in this system (it does in the Gunshot one); giving it a drift would
    // be inventing a value the source does not have.
    {
        const auto Head = Evaluate(1.0f, Get_SeedForLayer(0, 0)).Velocity;
        TestTrue(TEXT("the camera-facing head has no velocity — the source has no Add Velocity module on it"),
            Head.IsNearlyZero(kTolerance));

        for (const auto Layer : { 1, 2 })
        {
            const auto V = Evaluate(1.0f, Get_SeedForLayer(Layer, 0)).Velocity;

            TestEqual(*FString::Printf(TEXT("tail %d drifts at the source's 0.01 u/s"), Layer), V.X, kDrift, kTolerance);
            TestEqual(*FString::Printf(TEXT("tail %d has no Y velocity"), Layer), V.Y, 0.0f, kTolerance);
            TestEqual(*FString::Printf(TEXT("tail %d has no Z velocity"), Layer), V.Z, 0.0f, kTolerance);
        }
    }

    // ---- Anti-vacuity: every layer contributes visible light somewhere in its life ----
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
