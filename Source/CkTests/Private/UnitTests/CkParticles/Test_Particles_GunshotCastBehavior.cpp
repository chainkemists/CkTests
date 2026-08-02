// Behavior-math gate for CkParticles BehaviorId 33 (GunshotCast) — the Vefects NS_Gunshot_Cast recreation.
//
// Drives UCkParticles_DataInterface::Execute_Stage_CPU, the SAME CPU mirror a CPU sim runs, so it needs no
// Niagara system, no template asset, no RHI and no forked engine.
//
// Expected values are the SOURCE's own values as transcribed in
// CkFoundation/Source/CkParticles/Cookbook/NS_Gunshot_Cast.md §2/§5. The clamped-key lerp and the 40-slot
// burst partition are re-implemented here on purpose: the keys and the per-emitter counts are the fidelity
// claim.
//
// The load-bearing claims specific to this port:
//   - the row folds the source's one `Life Cycle Mode = Self` emitter into the burst (33 + 7 = 40), which is
//     exact per firing because that emitter only ever bursts;
//   - the row declares NO spawn rate, so the behavior must be independent of the emitter clock;
//   - THREE renderers are 2x2 flipbooks and two of them declare End Frame 4 on a four-frame sheet, so their
//     index must stay inside 0..3 while still advancing.
//
// Cannot pass vacuously: behavior 33's VisTags are 119..130 and the pre-switch default is 0.

#include "Misc/AutomationTest.h"

#include "CkParticles/DataInterface/CkParticles_DataInterface.h"
#include "CkParticles/ScriptDefinition/CkParticles_ScriptDefinition_Naming.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_particles_gunshot_cast
{
    constexpr auto kBehaviorId = 33;
    constexpr auto kTolerance  = 1.0e-4f;

    // Source facts (recipe §2/§6.1 against corpus v3).
    constexpr auto kLoop     = 2.0f;  // the SYSTEM's Loop Once / 2.0 s
    constexpr auto kLifetime = 1.55f; // the Wind layers' 0.05 s beat plus their 1.5 s life
    constexpr auto kBurst    = 40;    // 33 system-governed + the 7 one-shot Sparkles_01
    constexpr auto kDelayEarly = 0.04f;
    constexpr auto kDelayLate  = 0.05f;

    constexpr auto kRowAssetName = TEXT("PS_CkParticles_Template_GunshotCast");

    constexpr auto kVisPart01     = 119;
    constexpr auto kVisPart02     = 120;
    constexpr auto kVisPart04     = 121;
    constexpr auto kVisPart03Br   = 122;
    constexpr auto kVisSpike      = 123;
    constexpr auto kVisStrip      = 124;
    constexpr auto kVisStar01     = 125;
    constexpr auto kVisWindMesh   = 126;
    constexpr auto kVisWindPuff   = 127;
    constexpr auto kVisWindStreak = 128;
    constexpr auto kVisImpact     = 129;
    constexpr auto kVisPart01Br   = 130;

    // First slot, count, spawn delay, layer life, renderer — the source's own §2 table, in emitter order.
    struct FLayer { int32 FirstSlot; int32 Count; float Delay; float Life; int32 VisTag; const TCHAR* Name; };

    auto Get_Layers() -> TArrayView<const FLayer>
    {
        static const FLayer Layers[] =
        {
            {  0, 1, 0.0f,        0.1f,  kVisPart01,     TEXT("Glow_01")        },
            {  1, 1, 0.0f,        0.1f,  kVisPart01,     TEXT("Glow_02")        },
            {  2, 5, kDelayEarly, 0.05f, kVisPart02,     TEXT("Glow_03")        },
            {  7, 3, kDelayLate,  0.2f,  kVisPart04,     TEXT("Sparkles_02")    },
            { 10, 5, kDelayLate,  0.2f,  kVisPart01,     TEXT("Glow_04")        },
            { 15, 3, kDelayLate,  0.1f,  kVisPart03Br,   TEXT("Glow_05")        },
            { 18, 3, kDelayLate,  0.15f, kVisSpike,      TEXT("Spike01")        },
            { 21, 1, kDelayLate,  0.2f,  kVisStrip,      TEXT("LightningStrip") },
            { 22, 1, kDelayLate,  0.2f,  kVisStar01,     TEXT("Star01")         },
            { 23, 1, kDelayLate,  1.5f,  kVisWindMesh,   TEXT("Wind_01")        },
            { 24, 6, kDelayLate,  1.5f,  kVisWindPuff,   TEXT("Wind_02")        },
            { 30, 2, kDelayLate,  1.5f,  kVisWindStreak, TEXT("Wind_03")        },
            { 32, 1, kDelayLate,  0.2f,  kVisImpact,     TEXT("Impact_01")      },
            { 33, 7, kDelayLate,  0.6f,  kVisPart01Br,   TEXT("Sparkles_01")    },
        };
        return MakeArrayView(Layers);
    }

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
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Particles_GunshotCastBehavior,
    "CkTests.UnitTests.CkParticles.GunshotCastBehavior",
    kCkUnitTestFlags)

bool FCkTest_Particles_GunshotCastBehavior::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_gunshot_cast;

    // ---- The cadence row ----
    {
        TestEqual(TEXT("behavior 33 routes to the GunshotCast row"),
            ck::particles::Get_BehaviorTemplateSystemObjectPath(kBehaviorId),
            ck::particles::Get_GunshotCastTemplateSystemObjectPath());

        TestEqual(TEXT("behavior 33 binds no CkUsf look — all twelve of its looks ride the row's renderers"),
            ck::particles::Get_BehaviorLookName(kBehaviorId), NAME_None);

        const auto* RowSpec = static_cast<const ck::particles::FCk_ParticlesTemplateSpec*>(nullptr);
        for (const auto& Spec : ck::particles::Get_TemplateSpecs())
        {
            if (FString(Spec.AssetName) == FString(kRowAssetName))
            { RowSpec = &Spec; break; }
        }

        if (TestNotNull(TEXT("the cadence table declares a PS_CkParticles_Template_GunshotCast row"), RowSpec))
        {
            TestEqual(TEXT("row loop duration matches the source SYSTEM's Loop Once 2.0 s"),
                RowSpec->LoopDuration, kLoop, kTolerance);
            TestEqual(TEXT("row particle lifetime is the longest (spawn delay + resolved lifetime)"),
                RowSpec->ParticleLifetime, kLifetime, kTolerance);
            TestEqual(TEXT("row burst folds the one-shot Sparkles_01 into the system total"),
                RowSpec->BurstCount, kBurst);
            TestEqual(TEXT("the row declares NO spawn rate — every source emitter bursts"),
                RowSpec->SpawnRate, 0.0f, kTolerance);

            TestEqual(TEXT("the row declares one renderer per distinct source material and carrier"),
                RowSpec->RendererOverrides.Num(), 12);

            auto Meshes          = 0;
            auto VelocityAligned = 0;
            auto SubUvSheets     = 0;
            for (const auto& Renderer : RowSpec->RendererOverrides)
            {
                if (Renderer.Kind == ck::particles::ECk_ParticlesRenderer_Kind::Mesh)
                { ++Meshes; }
                if (Renderer.Kind == ck::particles::ECk_ParticlesRenderer_Kind::VelocityAlignedSprite)
                { ++VelocityAligned; }
                if (Renderer.SubImageSize != FIntPoint(0, 0))
                {
                    ++SubUvSheets;
                    TestTrue(TEXT("every declared flipbook is the source's 2x2 grid"),
                        Renderer.SubImageSize == FIntPoint(2, 2));
                }
            }
            TestEqual(TEXT("two renderers are carrier meshes (the pyramid and the wind tube)"), Meshes, 2);
            TestEqual(TEXT("four renderers are velocity-aligned"), VelocityAligned, 4);
            TestEqual(TEXT("three renderers declare a flipbook — the heaviest sub-UV load in the cookbook"),
                SubUvSheets, 3);
        }

        TestTrue(TEXT("the roster VisTag maximum covers the GunshotCast row's renderers"),
            ck::particles::Get_RosterVisTag_Max() >= kVisPart01Br);
    }

    // ---- The 40-slot partition IS the source's per-emitter burst counts ----
    {
        auto Total = 0;
        for (const auto& Layer : Get_Layers())
        { Total += Layer.Count; }
        TestEqual(TEXT("the layer table sums to the row's burst count"), Total, kBurst);

        for (const auto& Layer : Get_Layers())
        {
            for (auto Offset = 0; Offset < Layer.Count; ++Offset)
            {
                const auto Seed = Layer.FirstSlot + Offset;
                const auto Out  = Evaluate(Layer.Delay + Layer.Life * 0.4f, Seed);

                TestEqual(*FString::Printf(TEXT("%s (slot %d) draws through its own renderer"), Layer.Name, Seed),
                    Out.VisTag, Layer.VisTag);
            }
        }

        // A seed past the partition wraps back onto it rather than falling through to a stray layer.
        TestEqual(TEXT("the partition wraps: slot 40 is slot 0 again"),
            Evaluate(0.02f, kBurst).VisTag, Evaluate(0.02f, 0).VisTag);
    }

    // ---- The spawn beats: nothing but the two opening glows exists before 40 ms ----
    {
        for (const auto& Layer : Get_Layers())
        {
            if (Layer.Delay <= 0.0f)
            { continue; }

            for (auto Offset = 0; Offset < Layer.Count; ++Offset)
            {
                const auto Seed = Layer.FirstSlot + Offset;
                TestTrue(*FString::Printf(TEXT("%s is hidden before its own %.2f s beat"), Layer.Name, Layer.Delay),
                    Is_Hidden(Evaluate(Layer.Delay - 0.001f, Seed)));
            }
        }

        TestTrue(TEXT("Glow_01 is alive at the very first frame"), NOT Is_Hidden(Evaluate(0.001f, 0)));
        TestTrue(TEXT("Glow_02 is alive at the very first frame"), NOT Is_Hidden(Evaluate(0.001f, 1)));
    }

    // ---- This row declares no rate, so its output must be INDEPENDENT of the emitter clock ----
    // The roster-wide sweep derives the same rule from the cadence table; asserting it here names the port.
    {
        auto Moved = 0;
        for (auto Seed = 0; Seed < 400; ++Seed)
        {
            for (const auto Age : { 0.02f, 0.2f, 0.9f })
            {
                const auto Reference = Evaluate(Age, Seed, 0.0f);
                const auto Shifted   = Evaluate(Age, Seed, 7.3f);

                if (Reference.VisTag != Shifted.VisTag || Reference.Color != Shifted.Color
                    || Reference.Size != Shifted.Size)
                { ++Moved; }
            }
        }
        TestEqual(TEXT("a burst-only row never reads EmitterAge"), Moved, 0);
    }

    // ---- The three flipbooks: in range, and actually advancing ----
    // Wind_03 and Impact_01 declare End Frame 4 on a four-frame sheet, which is the port's one recorded
    // reading — five steps with the last wrapping back onto the start frame. Whatever the reading, the index
    // may never leave 0..3 or the renderer samples off the sheet.
    {
        const int32 SheetLayers[] = {24, 30, 32};
        const float SheetLives[]  = {1.5f, 1.5f, 0.2f};

        auto Index = 0;
        for (const auto FirstSlot : SheetLayers)
        {
            auto SeenFrames = TSet<int32>{};
            auto Advanced   = 0;
            auto Sampled    = 0;

            for (auto Offset = 0; Offset < 6; ++Offset)
            {
                const auto Seed = FirstSlot + Offset * kBurst;

                auto First = -1.0f;
                auto Moved = false;

                for (auto Step = 0; Step <= 40; ++Step)
                {
                    const auto Out = Evaluate(
                        kDelayLate + SheetLives[Index] * static_cast<float>(Step) / 40.0f, Seed);
                    if (Is_Hidden(Out))
                    { continue; }

                    TestTrue(TEXT("a flipbook frame never leaves the 2x2 sheet"),
                        Out.SubImageIndex >= 0.0f && Out.SubImageIndex <= 3.0f);

                    SeenFrames.Add(FMath::RoundToInt32(Out.SubImageIndex));
                    if (First < 0.0f) { First = Out.SubImageIndex; }
                    else if (Out.SubImageIndex != First) { Moved = true; }
                }

                // The two End-Frame-4 sheets return to their START frame on the last step, so "it advanced"
                // has to mean "it left the first frame at some point", not "it ended somewhere else".
                if (Moved) { ++Advanced; }
                ++Sampled;
            }

            TestTrue(*FString::Printf(TEXT("sheet layer at slot %d uses all four frames (%d seen)"),
                FirstSlot, SeenFrames.Num()), SeenFrames.Num() == 4);
            TestTrue(*FString::Printf(TEXT("every sampled particle of sheet layer %d advances its flipbook"),
                FirstSlot), Advanced == Sampled);
            ++Index;
        }
    }

    // ---- The two mesh layers ----
    // Spike01's source renderer faces VELOCITY and a row-declared mesh renderer draws Facing Default, so the
    // behavior owes it an orientation aimed down its own travel; Wind_01 spins about world X for 1.5 s.
    {
        for (auto Offset = 0; Offset < 3; ++Offset)
        {
            const auto Seed = 18 + Offset;
            const auto Out  = Evaluate(kDelayLate + 0.05f, Seed);

            TestEqual(TEXT("Spike01 draws through the mesh renderer"), Out.VisTag, kVisSpike);
            TestTrue(TEXT("Spike01 travels down +X"), Out.Velocity.X > 0.0f);
            TestTrue(TEXT("Spike01 carries a normalized orientation"), Out.Orientation.IsNormalized());

            // The carrier is built along +Z, so the rotated +Z must land on the velocity direction.
            const auto Aimed = Out.Orientation.RotateVector(FVector3f(0.0f, 0.0f, 1.0f));
            TestTrue(TEXT("Spike01's apex points down its own velocity"),
                FVector3f::DotProduct(Aimed, Out.Velocity.GetSafeNormal()) > 0.999f);
        }

        const auto Early = Evaluate(kDelayLate + 0.01f, 23);
        const auto Late  = Evaluate(kDelayLate + 1.4f,  23);

        TestEqual(TEXT("Wind_01 draws through the tube renderer"), Early.VisTag, kVisWindMesh);
        TestTrue(TEXT("Wind_01 travels +X, the muzzle direction"), Early.Velocity.X > 0.0f);
        TestTrue(TEXT("Wind_01 spins over its life"),
            FMath::Abs(Early.Orientation.X - Late.Orientation.X)
            + FMath::Abs(Early.Orientation.W - Late.Orientation.W) > 0.05f);
        TestTrue(TEXT("Wind_01 stretches along Z as it travels"), Late.Scale.Z > Early.Scale.Z);
        TestTrue(TEXT("Wind_01 drives the distortion channel, the only layer that does"),
            Late.Dynamic.Y > 0.1f);
    }

    // ---- HDR: the two brightest layers carry their source keys through the mirror unclamped ----
    // Both assertions are the CORPUS VALUE at the exact sample point, not a rounded restatement of the key.
    // A rounded bar is not just imprecise here, it is wrong in the interesting direction: these curves fall
    // STEEPLY off their opening key, so "roughly the key" silently accepts a sample taken after the fall has
    // started — which is what the first version of this test did.
    //
    // Tolerance: both sides run the same clamped-lerp chain in float32 on quantities of order 5, so 1e-4 is
    // ~2e-5 relative — far above the ~1e-6 relative drift three float ops can accumulate, and far below the
    // smallest key delta in either curve (0.045), so it cannot absorb a transcription error.
    {
        // Glow_05 R (recipe §5 layer 5): (0.315122, 3)C (1, 1)C. Every sampled t is <= 0.3, i.e. BEFORE the
        // first key, so the clamped lerp returns the key verbatim and the sweep maximum is exactly 3.
        auto BrightestGlow05 = 0.0f;
        for (auto Offset = 0; Offset < 3; ++Offset)
        {
            for (auto Step = 0; Step <= 20; ++Step)
            {
                const auto Out = Evaluate(kDelayLate + 0.1f * static_cast<float>(Step) / 20.0f, 15 + Offset);
                BrightestGlow05 = FMath::Max(BrightestGlow05, Out.Color.R);
            }
        }
        TestEqual(TEXT("Glow_05's colour ramp holds its opening key of 3 until t = 0.315122"),
            BrightestGlow05, 3.0f, kTolerance);

        // Impact_01 (recipe §5 layer 14), the brightest layer in the system, sampled at BOTH ends of the
        // claim. Its blue channel is (0, 5)C (0.094174, 0.328386)L (...): a 5x blue-white flashbulb whose
        // first segment loses 4.671614 across only 0.094174 of the life.
        //
        //   at t = 0        -> the corpus key itself, 5.0 / 4.48135 / 3.57847 (B / G / R)
        //   at t = 0.0025   -> 5 + (0.328386 - 5) * (0.0025 / 0.094174) = 4.875976 (4.875984 in float32)
        //
        // The pair is what makes this discriminating: the first point proves nothing between the behavior
        // and Particles.Color clamps an HDR key, and the second proves the ramp is actually RUNNING rather
        // than holding a constant head.
        const auto AtKey    = Evaluate(kDelayLate, 32);
        const auto AtRampIn = Evaluate(kDelayLate + 0.0005f, 32);

        TestEqual(TEXT("Impact_01 opens on its exact corpus key — a 5x blue-white flashbulb, unclamped"),
            AtKey.Color.B, 5.0f, kTolerance);
        TestEqual(TEXT("Impact_01's green opens on its exact corpus key too"),
            AtKey.Color.G, 4.48135f, kTolerance);
        TestEqual(TEXT("Impact_01's blue has begun its fall 0.5 ms in, by exactly the source's slope"),
            AtRampIn.Color.B, 4.875984f, kTolerance);
    }

    // ---- Anti-vacuity: every layer contributes visible light somewhere in its life ----
    {
        for (const auto& Layer : Get_Layers())
        {
            auto PeakLuminance = 0.0f;

            for (auto Offset = 0; Offset < Layer.Count; ++Offset)
            {
                const auto Seed = Layer.FirstSlot + Offset;
                for (auto Step = 0; Step <= 80; ++Step)
                {
                    const auto Out = Evaluate(kLifetime * static_cast<float>(Step) / 80.0f, Seed);
                    const auto Extent = FMath::Max(Out.Size.X, Out.Scale.GetMax());
                    PeakLuminance = FMath::Max(PeakLuminance,
                        (Out.Color.R + Out.Color.G + Out.Color.B) * Out.Color.A * Extent);
                }
            }

            TestTrue(*FString::Printf(TEXT("%s emits nonzero light somewhere in its life"), Layer.Name),
                PeakLuminance > kTolerance);
        }
    }

    // ---- Death: nothing survives the row's lifetime ----
    {
        for (auto Seed = 0; Seed < 200; ++Seed)
        {
            TestTrue(*FString::Printf(TEXT("seed %d is dead past the row's 1.55 s lifetime"), Seed),
                Is_Hidden(Evaluate(kLifetime + 0.001f, Seed)));
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
