// Behavior-math gate for CkParticles BehaviorId 34 (FireBallCast) — the Vefects NS_FireBall_Cast recreation.
//
// Drives UCkParticles_DataInterface::Execute_Stage_CPU, the SAME CPU mirror a CPU sim runs, so it needs no
// Niagara system, no template asset, no RHI and no forked engine.
//
// Expected values are the SOURCE's own values as transcribed in
// CkFoundation/Source/CkParticles/Cookbook/NS_FireBall_Cast.md §2/§5.
//
// The load-bearing claims specific to this port, the cookbook's largest:
//   - the TWO-ACT structure — eight charge-up layers at t = 0, forty-two release particles across the
//     0.5 / 0.54 / 0.55 beats — asserted in BOTH directions;
//   - the row lifetime EXCEEDS the loop (2.05 s against 2.0 s), because the wind layers spawn at 0.55 and
//     live 1.5 s;
//   - all twenty-six source emitters burst, so the row declares no rate and the behavior may not read the
//     emitter clock.
//
// Cannot pass vacuously: behavior 34's VisTags are 131..146 and the pre-switch default is 0.

#include "Misc/AutomationTest.h"

#include "CkParticles/DataInterface/CkParticles_DataInterface.h"
#include "CkParticles/ScriptDefinition/CkParticles_ScriptDefinition_Naming.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_particles_fireball_cast
{
    constexpr auto kBehaviorId = 34;
    constexpr auto kTolerance  = 1.0e-4f;

    // Source facts (recipe §2/§6.1 against corpus v3; the lifetime is the [P0-D5] ruling).
    constexpr auto kLoop     = 2.0f;
    constexpr auto kLifetime = 2.05f; // the Wind layers' 0.55 s beat plus their 1.5 s life
    constexpr auto kBurst    = 50;

    constexpr auto kDelayRelease   = 0.5f;
    constexpr auto kDelayTransient = 0.54f;
    constexpr auto kDelayLate      = 0.55f;

    constexpr auto kRowAssetName = TEXT("PS_CkParticles_Template_FireBallCast");

    constexpr auto kVisPart01   = 131;
    constexpr auto kVisPart01Br = 132;
    constexpr auto kVisPart03Br = 133;
    constexpr auto kVisPart04   = 134;
    constexpr auto kVisRainbow  = 135;
    constexpr auto kVisRing01   = 136;
    constexpr auto kVisStar01   = 137;
    constexpr auto kVisStar02   = 138;
    constexpr auto kVisStar03   = 139;
    constexpr auto kVisWindPuff = 140;
    constexpr auto kVisWindMesh = 141;
    constexpr auto kVisStrip    = 142;
    constexpr auto kVisSpike    = 143;
    constexpr auto kVisFlames   = 144;
    constexpr auto kVisSmoke    = 145;
    constexpr auto kVisFlare01  = 146;

    struct FLayer { int32 FirstSlot; int32 Count; float Delay; float Life; int32 VisTag; const TCHAR* Name; };

    auto Get_Layers() -> TArrayView<const FLayer>
    {
        static const FLayer Layers[] =
        {
            {  0,  1, kDelayRelease,   0.2f,  kVisRainbow,  TEXT("Raimbow")            },
            {  1,  1, kDelayRelease,   0.4f,  kVisRing01,   TEXT("Ring")               },
            {  2, 10, kDelayLate,      0.6f,  kVisPart01Br, TEXT("Sparkles")           },
            { 12,  1, 0.0f,            0.5f,  kVisPart01,   TEXT("Glow_01")            },
            { 13,  3, kDelayLate,      0.2f,  kVisPart04,   TEXT("Sparkles_Stretched") },
            { 16,  1, 0.0f,            0.5f,  kVisPart01,   TEXT("Flare_Stretched_01") },
            { 17,  1, 0.0f,            0.5f,  kVisPart03Br, TEXT("Flare_Stretched_02") },
            { 18,  1, 0.0f,            0.5f,  kVisPart03Br, TEXT("Flare_Stretched_03") },
            { 19,  1, 0.0f,            0.5f,  kVisStar03,   TEXT("Flare_Stretched_04") },
            { 20,  1, kDelayRelease,   0.2f,  kVisStar02,   TEXT("Star_02")            },
            { 21,  1, kDelayLate,      0.3f,  kVisStar01,   TEXT("Star_01")            },
            { 22,  1, 0.0f,            0.5f,  kVisPart01,   TEXT("Glow_02")            },
            { 23,  1, 0.0f,            0.5f,  kVisPart01,   TEXT("FirstGlow")          },
            { 24,  1, 0.0f,            0.5f,  kVisPart03Br, TEXT("SecondGlow")         },
            { 25,  1, kDelayRelease,   0.1f,  kVisPart01,   TEXT("ShootFlash_01")      },
            { 26,  1, kDelayRelease,   0.1f,  kVisPart01,   TEXT("ShootFlash_02")      },
            { 27,  4, kDelayTransient, 0.1f,  kVisPart03Br, TEXT("FirstFlash")         },
            { 31,  1, kDelayLate,      0.2f,  kVisPart01,   TEXT("SecondFlash_01")     },
            { 32,  1, kDelayRelease,   0.1f,  kVisPart01Br, TEXT("SecondFlash_02")     },
            { 33,  1, kDelayLate,      1.5f,  kVisWindMesh, TEXT("Wind_01")            },
            { 34,  5, kDelayLate,      1.5f,  kVisWindPuff, TEXT("Wind_02")            },
            { 39,  1, kDelayLate,      0.2f,  kVisStrip,    TEXT("LightningStrip")     },
            { 40,  3, kDelayLate,      0.15f, kVisSpike,    TEXT("Spike01")            },
            { 43,  4, kDelayRelease,   0.7f,  kVisFlames,   TEXT("Flames")             },
            { 47,  2, kDelayRelease,   1.3f,  kVisSmoke,    TEXT("Smokes")             },
            { 49,  1, kDelayRelease,   0.1f,  kVisFlare01,  TEXT("Flare01")            },
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
    FCkTest_Particles_FireBallCastBehavior,
    "CkTests.UnitTests.CkParticles.FireBallCastBehavior",
    kCkUnitTestFlags)

bool FCkTest_Particles_FireBallCastBehavior::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_fireball_cast;

    // ---- The cadence row ----
    {
        TestEqual(TEXT("behavior 34 routes to the FireBallCast row"),
            ck::particles::Get_BehaviorTemplateSystemObjectPath(kBehaviorId),
            ck::particles::Get_FireBallCastTemplateSystemObjectPath());

        TestEqual(TEXT("behavior 34 binds no CkUsf look — all sixteen of its looks ride the row's renderers"),
            ck::particles::Get_BehaviorLookName(kBehaviorId), NAME_None);

        const auto* RowSpec = static_cast<const ck::particles::FCk_ParticlesTemplateSpec*>(nullptr);
        for (const auto& Spec : ck::particles::Get_TemplateSpecs())
        {
            if (FString(Spec.AssetName) == FString(kRowAssetName))
            { RowSpec = &Spec; break; }
        }

        if (TestNotNull(TEXT("the cadence table declares a PS_CkParticles_Template_FireBallCast row"), RowSpec))
        {
            TestEqual(TEXT("row loop duration matches the source SYSTEM's Loop Once 2.0 s"),
                RowSpec->LoopDuration, kLoop, kTolerance);
            TestEqual(TEXT("row particle lifetime is spawn delay + resolved lifetime, not the lifetime alone"),
                RowSpec->ParticleLifetime, kLifetime, kTolerance);
            TestTrue(TEXT("this row's lifetime deliberately EXCEEDS its loop, as the source's does"),
                RowSpec->ParticleLifetime > RowSpec->LoopDuration);
            TestEqual(TEXT("row burst is the source's exact per-firing total"), RowSpec->BurstCount, kBurst);
            TestEqual(TEXT("the row declares NO spawn rate — all twenty-six source emitters burst"),
                RowSpec->SpawnRate, 0.0f, kTolerance);

            TestEqual(TEXT("the row declares one renderer per distinct source material and carrier"),
                RowSpec->RendererOverrides.Num(), 16);

            auto Meshes      = 0;
            auto SubUvSheets = 0;
            for (const auto& Renderer : RowSpec->RendererOverrides)
            {
                if (Renderer.Kind == ck::particles::ECk_ParticlesRenderer_Kind::Mesh)
                { ++Meshes; }
                if (Renderer.SubImageSize != FIntPoint(0, 0))
                {
                    ++SubUvSheets;
                    TestTrue(TEXT("every declared flipbook is the source's 2x2 grid"),
                        Renderer.SubImageSize == FIntPoint(2, 2));
                }
            }
            TestEqual(TEXT("two renderers are carrier meshes (the pyramid and the wind tube)"), Meshes, 2);
            TestEqual(TEXT("two renderers declare a flipbook (the wind puffs and the flames)"), SubUvSheets, 2);
        }

        TestTrue(TEXT("the roster VisTag maximum covers the FireBallCast row's renderers"),
            ck::particles::Get_RosterVisTag_Max() >= kVisFlare01);
    }

    // ---- The 50-slot partition IS the source's per-emitter burst counts ----
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
                // A fifth of the layer's MAXIMUM life keeps the sample inside even the shortest draw of a
                // randomized one (Flames runs 0.2 - 0.7 s).
                const auto Out = Evaluate(Layer.Delay + Layer.Life * 0.2f, Seed);

                TestEqual(*FString::Printf(TEXT("%s (slot %d) draws through its own renderer"), Layer.Name, Seed),
                    Out.VisTag, Layer.VisTag);
            }
        }
    }

    // ---- The two acts, asserted in BOTH directions ----
    // Reading either half as the whole effect is exactly the failure this port can have: at t = 0.1 only the
    // eight charge-up layers may exist, and at t = 0.6 none of them may.
    {
        auto ChargeUpAliveEarly = 0;
        auto ReleaseAliveEarly  = 0;
        auto ChargeUpAliveLate  = 0;

        for (const auto& Layer : Get_Layers())
        {
            const auto IsChargeUp = Layer.Delay <= 0.0f;

            for (auto Offset = 0; Offset < Layer.Count; ++Offset)
            {
                const auto Seed  = Layer.FirstSlot + Offset;
                const auto Early = Evaluate(0.1f, Seed);
                const auto Late  = Evaluate(0.6f, Seed);

                if (IsChargeUp)
                {
                    if (NOT Is_Hidden(Early)) { ++ChargeUpAliveEarly; }
                    if (NOT Is_Hidden(Late))  { ++ChargeUpAliveLate; }
                }
                else if (NOT Is_Hidden(Early))
                { ++ReleaseAliveEarly; }
            }
        }

        TestEqual(TEXT("all eight charge-up particles are alive a tenth of a second in"), ChargeUpAliveEarly, 8);
        TestEqual(TEXT("no release particle exists before the 0.5 s beat"), ReleaseAliveEarly, 0);
        TestEqual(TEXT("no charge-up particle survives past its own half-second"), ChargeUpAliveLate, 0);
    }

    // ---- Every release layer is hidden until its own beat, and the 0.54 s transient is its own ----
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

        // FirstFlash is the only spawn time between the two release beats.
        for (auto Offset = 0; Offset < 4; ++Offset)
        {
            TestTrue(TEXT("FirstFlash has not fired at the 0.5 s beat"),
                Is_Hidden(Evaluate(kDelayRelease + 0.001f, 27 + Offset)));
            TestTrue(TEXT("FirstFlash is alive by its own 0.54 s beat"),
                NOT Is_Hidden(Evaluate(kDelayTransient + 0.001f, 27 + Offset)));
        }
    }

    // ---- This row declares no rate, so its output must be INDEPENDENT of the emitter clock ----
    {
        auto Moved = 0;
        for (auto Seed = 0; Seed < 400; ++Seed)
        {
            for (const auto Age : { 0.2f, 0.6f, 1.4f })
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

    // ---- FirstGlow: the charge-up ramp, the only six-key colour curve in the cookbook ----
    // Near-black until t ~= 0.115, saturated red by 0.227, warming to near-white by death. A three-key
    // simplification would lose the dark head, which is the whole "gathering" read.
    {
        const auto Head = Evaluate(0.5f * 0.05f, 23);
        const auto Mid  = Evaluate(0.5f * 0.3f,  23);
        const auto Tail = Evaluate(0.5f * 0.99f, 23);

        TestTrue(TEXT("FirstGlow starts essentially black"), Head.Color.R < 0.02f);
        TestTrue(TEXT("FirstGlow reaches saturated red by a third of its life"), Mid.Color.R > 0.9f);
        TestTrue(TEXT("FirstGlow's blue only lifts at the very end"), Tail.Color.B > Mid.Color.B + 0.4f);
        TestTrue(TEXT("FirstGlow squeezes to a horizontal sliver as it brightens"), Tail.Size.Y < Head.Size.Y);
    }

    // ---- HDR: Flames opens at 5 and Star_02 at 2, both asserted as CORPUS VALUES ----
    // Same discipline as NS_Gunshot_Cast's HDR block: a rounded "> 4.9" bar accepts a sample taken after a
    // steep ramp has already started. Tolerance 1e-4 on quantities of order 5 is ~2e-5 relative — above
    // float32 drift, below the smallest key delta in either curve.
    {
        // Flames R (recipe §5.13): (0.0796861, 5)L (0.368246, 3)L (0.738907, 0.250158)L. Step 0 of the sweep
        // is t = 0, BEFORE the first key, so the clamped lerp returns 5 exactly regardless of the seed's
        // randomized life.
        auto BrightestFlame = 0.0f;
        for (auto Offset = 0; Offset < 4; ++Offset)
        {
            for (auto Step = 0; Step <= 30; ++Step)
            {
                const auto Out = Evaluate(kDelayRelease + 0.2f * static_cast<float>(Step) / 30.0f, 43 + Offset);
                BrightestFlame = FMath::Max(BrightestFlame, Out.Color.R);
            }
        }
        TestEqual(TEXT("the flame ramp holds its opening key of 5 until t = 0.0796861"),
            BrightestFlame, 5.0f, kTolerance);

        // Star_02 R (recipe §5.6): (0, 2)C (0.220948, 1)L (...). At t = 0 the key itself; 0.5 ms into a
        // 0.2 s life (t = 0.0025) it has fallen to 2 + (1 - 2) * (0.0025 / 0.220948) = 1.988685.
        TestEqual(TEXT("Star_02 opens on its exact corpus key of 2"),
            Evaluate(kDelayRelease, 20).Color.R, 2.0f, kTolerance);
        TestEqual(TEXT("Star_02 has begun its fall 0.5 ms in, by exactly the source's slope"),
            Evaluate(kDelayRelease + 0.0005f, 20).Color.R, 1.988685f, kTolerance);
    }

    // ---- Spike01 faces its own velocity; Wind_01 spins and stretches ----
    {
        for (auto Offset = 0; Offset < 3; ++Offset)
        {
            const auto Out = Evaluate(kDelayLate + 0.05f, 40 + Offset);

            TestEqual(TEXT("Spike01 draws through the mesh renderer"), Out.VisTag, kVisSpike);
            TestTrue(TEXT("Spike01 carries a normalized orientation"), Out.Orientation.IsNormalized());

            const auto Aimed = Out.Orientation.RotateVector(FVector3f(0.0f, 0.0f, 1.0f));
            TestTrue(TEXT("Spike01's apex points down its own velocity"),
                FVector3f::DotProduct(Aimed, Out.Velocity.GetSafeNormal()) > 0.999f);
        }

        const auto Early = Evaluate(kDelayLate + 0.01f, 33);
        const auto Late  = Evaluate(kDelayLate + 1.4f,  33);

        TestTrue(TEXT("Wind_01 travels -X, away from the caster"), Early.Velocity.X < 0.0f);
        TestTrue(TEXT("Wind_01 stretches to five times its length"), Late.Scale.Z > 4.0f * Early.Scale.Z);
    }

    // ---- The two flipbooks stay inside their sheet and advance ----
    {
        const int32 SheetLayers[] = {34, 43};
        const float SheetLives[]  = {1.5f, 0.7f};

        auto Index = 0;
        for (const auto FirstSlot : SheetLayers)
        {
            auto SeenFrames = TSet<int32>{};

            for (auto Offset = 0; Offset < 6; ++Offset)
            {
                const auto Seed = FirstSlot + Offset * kBurst;
                auto First = -1.0f;
                auto Moved = false;

                for (auto Step = 0; Step <= 40; ++Step)
                {
                    const auto Delay = Index == 0 ? kDelayLate : kDelayRelease;
                    const auto Out   = Evaluate(
                        Delay + SheetLives[Index] * static_cast<float>(Step) / 40.0f, Seed);
                    if (Is_Hidden(Out))
                    { continue; }

                    TestTrue(TEXT("a flipbook frame never leaves the 2x2 sheet"),
                        Out.SubImageIndex >= 0.0f && Out.SubImageIndex <= 3.0f);

                    SeenFrames.Add(FMath::RoundToInt32(Out.SubImageIndex));
                    if (First < 0.0f) { First = Out.SubImageIndex; }
                    else if (Out.SubImageIndex != First) { Moved = true; }
                }

                TestTrue(*FString::Printf(TEXT("sheet layer %d seed %d advances its flipbook"), FirstSlot, Seed),
                    Moved);
            }

            TestTrue(*FString::Printf(TEXT("sheet layer at slot %d uses all four frames (%d seen)"),
                FirstSlot, SeenFrames.Num()), SeenFrames.Num() == 4);
            ++Index;
        }
    }

    // ---- Anti-vacuity: every layer contributes visible light somewhere in its life ----
    {
        for (const auto& Layer : Get_Layers())
        {
            auto PeakLuminance = 0.0f;

            for (auto Offset = 0; Offset < Layer.Count; ++Offset)
            {
                const auto Seed = Layer.FirstSlot + Offset;
                for (auto Step = 0; Step <= 100; ++Step)
                {
                    const auto Out = Evaluate(kLifetime * static_cast<float>(Step) / 100.0f, Seed);
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
            TestTrue(*FString::Printf(TEXT("seed %d is dead past the row's 2.05 s lifetime"), Seed),
                Is_Hidden(Evaluate(kLifetime + 0.001f, Seed)));
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
