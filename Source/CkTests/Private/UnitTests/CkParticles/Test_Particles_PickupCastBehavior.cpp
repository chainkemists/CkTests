// Behavior-math gate for CkParticles BehaviorId 30 (PickupCast) — the Vefects NS_PickupCast recreation.
//
// Drives UCkParticles_DataInterface::Execute_Stage_CPU, the SAME CPU mirror a CPU sim runs, so it needs no
// Niagara system, no template asset, no RHI and no forked engine.
//
// Expected values are the SOURCE's own values as transcribed in
// CkFoundation/Source/CkParticles/Cookbook/NS_PickupCast.md §2/§5 — not values read back out of the
// implementation. The clamped-key lerp and the 22-slot partition are both re-implemented here on purpose:
// the keys and the per-emitter counts are the fidelity claim.
//
// This is the batch's BURST-ONLY port: every source emitter spawns through Spawn Burst Instantaneous and
// nothing streams, so the row declares no rate and the partition is an exact modulo rather than a draw. The
// test asserts that exactness rather than a share, which is the difference between this port and its two
// siblings.
//
// Cannot pass vacuously: behavior 30's VisTags are 97..104 and the pre-switch default is 0.

#include "Misc/AutomationTest.h"

#include "CkParticles/DataInterface/CkParticles_DataInterface.h"
#include "CkParticles/ScriptDefinition/CkParticles_ScriptDefinition_Naming.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_particles_pickup_cast
{
    constexpr auto kBehaviorId = 30;
    constexpr auto kTolerance  = 1.0e-4f;

    // Source facts (recipe §2/§6.1 against corpus v3).
    constexpr auto kLoop     = 2.0f;  // the SYSTEM's Loop Once / 2.0 s
    constexpr auto kLifetime = 1.05f; // Sparkles' 0.05 s beat plus its resolved 1.0 s maximum
    constexpr auto kBurst    = 22;    // 1+1+3+1+10+1+1+1+1+1+1

    constexpr auto kRowAssetName = TEXT("PS_CkParticles_Template_PickupCast");

    constexpr auto kVisPart01   =  97;
    constexpr auto kVisPart02   =  98;
    constexpr auto kVisRainbow  =  99;
    constexpr auto kVisPart01Br = 100;
    constexpr auto kVisRing01   = 101;
    constexpr auto kVisPart03Br = 102;
    constexpr auto kVisStar01   = 103;
    constexpr auto kVisStar02   = 104;

    // Slot -> (source emitter, its spawn beat, its longest life, its renderer). The slot RANGES are the source's
    // own per-emitter burst counts, which is what a modulo partition preserves and a probability band would not.
    struct FLayer { int32 FirstSlot; int32 Count; float Delay; float Life; int32 VisTag; const TCHAR* Name; };

    auto Get_Layers() -> TArrayView<const FLayer>
    {
        static const FLayer Layers[] =
        {
            {  0,  1, 0.0f,  1.0f, kVisPart01,   TEXT("Bomb_Glow_01")  },
            {  1,  1, 0.0f,  1.0f, kVisPart01,   TEXT("Bomb_Glow_02")  },
            {  2,  3, 0.05f, 0.5f, kVisPart02,   TEXT("Bomb_Glow_03")  },
            {  5,  1, 0.0f,  0.5f, kVisRainbow,  TEXT("Raimbow")       },
            {  6, 10, 0.05f, 1.0f, kVisPart01Br, TEXT("Sparkles")      },
            { 16,  1, 0.0f,  1.0f, kVisRing01,   TEXT("Ring01")        },
            { 17,  1, 0.05f, 0.2f, kVisPart01,   TEXT("Flash_Glow_01") },
            { 18,  1, 0.05f, 0.1f, kVisPart03Br, TEXT("Flash_Glow_02") },
            { 19,  1, 0.2f,  0.3f, kVisStar01,   TEXT("Star01")        },
            { 20,  1, 0.1f,  0.3f, kVisStar02,   TEXT("Star02")        },
            { 21,  1, 0.0f,  1.0f, kVisRing01,   TEXT("Ring02")        },
        };
        return MakeArrayView(Layers);
    }

    auto Evaluate(float InAge, int32 InSeed) -> FCk_Particles_StageResult
    {
        constexpr auto DeltaTime = 1.0f / 60.0f;

        // Every particle in this system is a burst particle, so its spawn phase is zero by construction.
        return UCkParticles_DataInterface::Execute_Stage_CPU(
            kBehaviorId, DeltaTime, InAge, kLifetime,
            FVector3f::ZeroVector, FVector3f::ZeroVector, InSeed, InAge);
    }

    auto Is_Hidden(const FCk_Particles_StageResult& InOut) -> bool
    {
        return InOut.Color.A == 0.0f && InOut.Color.R == 0.0f && InOut.Color.G == 0.0f && InOut.Color.B == 0.0f
            && InOut.Size.IsNearlyZero() && InOut.Scale.IsNearlyZero();
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Particles_PickupCastBehavior,
    "CkTests.UnitTests.CkParticles.PickupCastBehavior",
    kCkUnitTestFlags)

bool FCkTest_Particles_PickupCastBehavior::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_pickup_cast;

    // ---- The cadence row ----
    {
        TestEqual(TEXT("behavior 30 routes to the PickupCast row"),
            ck::particles::Get_BehaviorTemplateSystemObjectPath(kBehaviorId),
            ck::particles::Get_PickupCastTemplateSystemObjectPath());

        TestEqual(TEXT("behavior 30 binds no CkUsf look — all eight of its looks ride the row's renderers"),
            ck::particles::Get_BehaviorLookName(kBehaviorId), NAME_None);

        const auto* RowSpec = static_cast<const ck::particles::FCk_ParticlesTemplateSpec*>(nullptr);
        for (const auto& Spec : ck::particles::Get_TemplateSpecs())
        {
            if (FString(Spec.AssetName) == FString(kRowAssetName))
            { RowSpec = &Spec; break; }
        }

        if (TestNotNull(TEXT("the cadence table declares a PS_CkParticles_Template_PickupCast row"), RowSpec))
        {
            TestEqual(TEXT("row loop duration matches the source SYSTEM's Loop Once 2.0 s"),
                RowSpec->LoopDuration, kLoop, kTolerance);
            TestEqual(TEXT("row particle lifetime is the longest (spawn delay + resolved lifetime)"),
                RowSpec->ParticleLifetime, kLifetime, kTolerance);
            TestEqual(TEXT("row burst is the source's exact per-firing particle count"),
                RowSpec->BurstCount, kBurst);
            TestEqual(TEXT("row declares NO spawn rate — every source emitter bursts and none streams"),
                RowSpec->SpawnRate, 0.0f, kTolerance);

            TestEqual(TEXT("the row declares one renderer per distinct source material"),
                RowSpec->RendererOverrides.Num(), 8);

            auto CameraFacing = 0;
            for (const auto& Renderer : RowSpec->RendererOverrides)
            {
                if (Renderer.Kind == ck::particles::ECk_ParticlesRenderer_Kind::CameraFacingSprite)
                { ++CameraFacing; }
                TestTrue(TEXT("no renderer on this row declares a sub-UV sheet — the source has no flipbook"),
                    Renderer.SubImageSize == FIntPoint(0, 0));
            }
            TestEqual(TEXT("every renderer is camera-facing, like all eleven source emitters"), CameraFacing, 8);
        }

        TestTrue(TEXT("the roster VisTag maximum covers the PickupCast row's renderers"),
            ck::particles::Get_RosterVisTag_Max() >= kVisStar02);
    }

    // ---- The partition is an exact modulo: every slot resolves to the emitter the source burst it from ----
    {
        auto SlotCounts = TArray<int32>{};
        SlotCounts.AddZeroed(kBurst);

        for (const auto& Layer : Get_Layers())
        {
            for (auto Slot = Layer.FirstSlot; Slot < Layer.FirstSlot + Layer.Count; ++Slot)
            { ++SlotCounts[Slot]; }
        }

        for (auto Slot = 0; Slot < kBurst; ++Slot)
        {
            TestEqual(*FString::Printf(TEXT("slot %d belongs to exactly one source emitter"), Slot),
                SlotCounts[Slot], 1);
        }

        // The partition is stable per Seed and covers every residue class, so a 22-particle burst reproduces
        // the source's counts exactly rather than in expectation.
        for (auto Seed = 0; Seed < 220; ++Seed)
        {
            const auto Slot  = ((Seed % kBurst) + kBurst) % kBurst;
            const auto* Layer = static_cast<const FLayer*>(nullptr);
            for (const auto& Candidate : Get_Layers())
            {
                if (Slot >= Candidate.FirstSlot && Slot < Candidate.FirstSlot + Candidate.Count)
                { Layer = &Candidate; break; }
            }

            if (Layer == nullptr)
            { continue; }

            const auto Mid = Evaluate(Layer->Delay + Layer->Life * 0.4f, Seed);
            TestEqual(*FString::Printf(TEXT("%s (seed %d) draws through its own renderer"), Layer->Name, Seed),
                Mid.VisTag, Layer->VisTag);
        }
    }

    // ---- Every layer is hidden before its own spawn beat ----
    // Six of the eleven emitters fire late. Dropping the beat would start the whole effect on frame 0, which is
    // the single most invisible way to get this port wrong.
    {
        for (const auto& Layer : Get_Layers())
        {
            if (Layer.Delay <= 0.0f)
            { continue; }

            for (auto Slot = Layer.FirstSlot; Slot < Layer.FirstSlot + Layer.Count; ++Slot)
            {
                TestTrue(*FString::Printf(TEXT("%s is hidden before its %.2f s beat"), Layer.Name, Layer.Delay),
                    Is_Hidden(Evaluate(Layer.Delay - 0.001f, Slot)));
                TestTrue(*FString::Printf(TEXT("%s is visible just after its beat"), Layer.Name),
                    NOT Is_Hidden(Evaluate(Layer.Delay + Layer.Life * 0.4f, Slot)));
            }
        }
    }

    // ---- Flash_Glow_02 keeps its HDR colour ----
    // The source initializes it at RGBA(3, 1.91279, 0.458779, 1). A saturate() anywhere on the colour path
    // silently costs a 3x overbright flash and nothing else in the effect would look wrong.
    {
        auto PeakRed = 0.0f;
        for (auto Step = 0; Step <= 20; ++Step)
        { PeakRed = FMath::Max(PeakRed, Evaluate(0.05f + 0.1f * static_cast<float>(Step) / 20.0f, 18).Color.R); }

        TestTrue(*FString::Printf(TEXT("Flash_Glow_02 stays HDR (peak red %f)"), PeakRed),
            FMath::IsNearlyEqual(PeakRed, 3.0f, 1.0e-3f));
    }

    // ---- The two rings never FADE — they dissolve ----
    // Both carry a single alpha key, so their only disappearance mechanism is the dissolve channel sliding
    // 1 -> -1. An alpha envelope added "to make them fade out" would break the source's read.
    {
        for (const auto Slot : {16, 21})
        {
            const auto Early = Evaluate(0.02f, Slot);
            const auto Late  = Evaluate(0.95f, Slot);

            TestEqual(*FString::Printf(TEXT("ring slot %d holds its alpha for the whole life"), Slot),
                Late.Color.A, Early.Color.A, kTolerance);
            TestTrue(*FString::Printf(TEXT("ring slot %d dissolves from 1 to -1"), Slot),
                Early.Dynamic.X > 0.9f && Late.Dynamic.X < -0.85f);
        }

        // Ring02's Color module scales its alpha by 0.2 where Ring01's leaves it at 1 — that scalar IS the
        // difference between the two rings, and they share a renderer.
        TestTrue(TEXT("Ring02 is a fifth of Ring01's opacity"),
            FMath::IsNearlyEqual(Evaluate(0.5f, 21).Color.A, 0.2f * Evaluate(0.5f, 16).Color.A, kTolerance));
    }

    // ---- Sparkles hold WHITE for the first three fifths of their life ----
    // Their colour curve's first key sits at t = 0.6158, so a clamped lerp holds white until then and only
    // afterwards crosses to blue. A curve evaluated from t = 0 instead would tint them immediately.
    {
        auto Checked = 0;
        for (auto Slot = 6; Slot < 16; ++Slot)
        {
            const auto Early = Evaluate(0.05f + 0.10f, Slot); // well inside the clamped head
            if (Is_Hidden(Early))
            { continue; }

            TestTrue(TEXT("Sparkles are white before their colour curve's first key"),
                FMath::IsNearlyEqual(Early.Color.R, 1.0f, 1.0e-3f) && Early.Color.B < 0.25f);
            ++Checked;
        }
        TestTrue(TEXT("at least one sparkle slot was sampled inside its clamped head"), Checked > 0);
    }

    // ---- Bomb_Glow_03's three particles are IDENTICAL ----
    // The source emitter has no randomness of any kind, so its three bursts overlay exactly. A per-Seed size or
    // position draw added "for variety" would show up here.
    {
        const auto A = Evaluate(0.25f, 2);
        const auto B = Evaluate(0.25f, 3);
        const auto C = Evaluate(0.25f, 4);

        TestEqual(TEXT("Bomb_Glow_03 slots 2 and 3 are identical in size"), B.Size.X, A.Size.X, kTolerance);
        TestEqual(TEXT("Bomb_Glow_03 slots 2 and 4 are identical in size"), C.Size.X, A.Size.X, kTolerance);
        TestTrue(TEXT("Bomb_Glow_03 slots overlay at the same position"),
            (B.Position - A.Position).IsNearlyZero() && (C.Position - A.Position).IsNearlyZero());
    }

    // ---- Anti-vacuity: every layer contributes visible light somewhere in its life ----
    {
        for (const auto& Layer : Get_Layers())
        {
            auto PeakLuminance = 0.0f;

            for (auto Slot = Layer.FirstSlot; Slot < Layer.FirstSlot + Layer.Count; ++Slot)
            {
                for (auto Step = 0; Step <= 80; ++Step)
                {
                    const auto Out = Evaluate(kLifetime * static_cast<float>(Step) / 80.0f, Slot);
                    PeakLuminance = FMath::Max(PeakLuminance,
                        (Out.Color.R + Out.Color.G + Out.Color.B) * Out.Color.A * Out.Size.X);
                }
            }

            TestTrue(*FString::Printf(TEXT("%s emits nonzero light somewhere in its life"), Layer.Name),
                PeakLuminance > kTolerance);
        }
    }

    // ---- Death: nothing survives the row's lifetime ----
    {
        for (auto Seed = 0; Seed < kBurst * 4; ++Seed)
        {
            TestTrue(*FString::Printf(TEXT("seed %d is dead past the row's 1.05 s lifetime"), Seed),
                Is_Hidden(Evaluate(kLifetime + 0.001f, Seed)));
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
