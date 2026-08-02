// Behavior-math gate for CkParticles BehaviorId 32 (DebuffCast) — the Vefects NS_DebuffCast recreation.
//
// Drives UCkParticles_DataInterface::Execute_Stage_CPU, the SAME CPU mirror a CPU sim runs, so it needs no
// Niagara system, no template asset, no RHI and no forked engine.
//
// Expected values are the SOURCE's own values as transcribed in
// CkFoundation/Source/CkParticles/Cookbook/NS_DebuffCast.md §2/§3/§5. The clamped-key lerp, the 30-slot burst
// partition and the rate-weighted draw are re-implemented here on purpose.
//
// This is the batch's richest port and the cookbook's FIRST consumer of the curl-noise capability. The two
// claims that carry it are falsifiable in the strongest available form:
//
//   * The curl force. Both sparkle clouds move along a RADIAL line by construction — spawn is Dir*R and the
//     velocity is Dir*speed — so without the curl term a particle's direction from the origin is invariant
//     for its whole life. Any angular deviation at all is the curl and nothing else, which makes "remove the
//     force" a control that scores exactly zero rather than merely a smaller number.
//   * The two `Color Mode = Random Range` layers, keyed on the RECOVERED lerp parameter rather than on a
//     colour channel (the lesson NS_BuffLoop.md §14.7 records), with a dead control that pins the draw and
//     collapses to a single bucket.
//
// Cannot pass vacuously: behavior 32's VisTags are 113..118 and the pre-switch default is 0.

#include "Misc/AutomationTest.h"

#include "CkParticles/DataInterface/CkParticles_DataInterface.h"
#include "CkParticles/ScriptDefinition/CkParticles_ScriptDefinition_Naming.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_particles_debuff_cast
{
    constexpr auto kBehaviorId = 32;
    constexpr auto kTolerance  = 1.0e-4f;

    // Source facts (recipe §2/§6.1 against corpus v3).
    constexpr auto kLoop      = 2.0f;  // the SYSTEM's Loop Once / 2.0 s
    constexpr auto kLifetime  = 2.0f;  // Flames' resolved 2.0 s maximum, on a beat of 0
    constexpr auto kBurst     = 30;    // 1+7+3+7+5+7 over the SIX enabled emitters
    constexpr auto kSpawnRate = 65.0f; // 20+5+20+20
    constexpr auto kWindow    = 0.3f;  // every Self/Once emitter's own loop duration

    constexpr auto kRowAssetName = TEXT("PS_CkParticles_Template_DebuffCast");

    constexpr auto kVisArrows   = 113;
    constexpr auto kVisPart01Br = 114;
    constexpr auto kVisRing01   = 115;
    constexpr auto kVisPart03Br = 116;
    constexpr auto kVisFlames   = 117;
    constexpr auto kVisSlash    = 118;

    constexpr auto kLayerBigArrow  = 0;
    constexpr auto kLayerSparkDark = 1;
    constexpr auto kLayerRing      = 2;
    constexpr auto kLayerSparkBr   = 3;
    constexpr auto kLayerFlames    = 4;
    constexpr auto kLayerSlash     = 5;

    // Rate 0 marks a layer the source only ever BURSTS.
    struct FLayer { int32 BurstCount; float Rate; float Life; int32 VisTag; const TCHAR* Name; };

    auto Get_Layers() -> TArrayView<const FLayer>
    {
        static const FLayer Layers[] =
        {
            { 1,  0.0f, 1.5f, kVisArrows,   TEXT("BigArrow")        },
            { 7, 20.0f, 1.5f, kVisPart01Br, TEXT("Sparkles_Dark")   },
            { 3,  5.0f, 0.7f, kVisRing01,   TEXT("Ring")            },
            { 7, 20.0f, 1.5f, kVisPart03Br, TEXT("Sparkles_Bright") },
            { 5,  0.0f, 2.0f, kVisFlames,   TEXT("Flames")          },
            { 7, 20.0f, 1.5f, kVisSlash,    TEXT("Slash")           },
        };
        return MakeArrayView(Layers);
    }

    auto Layer_ForBurstSlot(int32 InSeed) -> int32
    {
        const auto S = ((InSeed % kBurst) + kBurst) % kBurst;

        if (S == 0)  { return kLayerBigArrow; }
        if (S < 8)   { return kLayerSparkDark; }
        if (S < 11)  { return kLayerRing; }
        if (S < 18)  { return kLayerSparkBr; }
        if (S < 23)  { return kLayerFlames; }
        return kLayerSlash;
    }

    // Re-implemented, not called: CkParticles_Rand's 24-bit avalanche IS what the rate draw claims to use.
    auto Rand(int32 InSeed, int32 InSalt) -> float
    {
        uint32 n = uint32(InSeed) * 747796405u + uint32(InSalt) * 2891336453u + 1u;
        n ^= n >> 16;
        n *= 2246822519u;
        n ^= n >> 13;
        n *= 3266489917u;
        n ^= n >> 16;
        return float(n & 0x00FFFFFFu) / 16777216.0f;
    }

    auto Layer_ForRateDraw(int32 InSeed) -> int32
    {
        const auto R = Rand(InSeed, 0) * kSpawnRate;

        auto Cumulative = 0.0f;
        auto Index      = 0;
        for (const auto& Layer : Get_Layers())
        {
            Cumulative += Layer.Rate;
            if (Layer.Rate > 0.0f && R < Cumulative)
            { return Index; }
            ++Index;
        }
        return kLayerSlash;
    }

    auto Get_SeedsForBurstLayer(int32 InLayer, int32 InCount) -> TArray<int32>
    {
        auto Seeds = TArray<int32>{};
        for (auto Seed = 0; Seed < 100000 && Seeds.Num() < InCount; ++Seed)
        {
            if (Layer_ForBurstSlot(Seed) == InLayer)
            { Seeds.Add(Seed); }
        }
        return Seeds;
    }

    auto Evaluate(float InAge, int32 InSeed, float InSpawnPhase) -> FCk_Particles_StageResult
    {
        constexpr auto DeltaTime = 1.0f / 60.0f;

        return UCkParticles_DataInterface::Execute_Stage_CPU(
            kBehaviorId, DeltaTime, InAge, kLifetime,
            FVector3f::ZeroVector, FVector3f::ZeroVector, InSeed, InAge + InSpawnPhase);
    }

    auto Evaluate_Burst(float InAge, int32 InSeed) -> FCk_Particles_StageResult
    {
        return Evaluate(InAge, InSeed, 0.0f);
    }

    auto Is_Hidden(const FCk_Particles_StageResult& InOut) -> bool
    {
        return InOut.Color.A == 0.0f && InOut.Color.R == 0.0f && InOut.Color.G == 0.0f && InOut.Color.B == 0.0f
            && InOut.Size.IsNearlyZero() && InOut.Scale.IsNearlyZero();
    }

    auto Get_AngleDegrees(const FVector3f& InA, const FVector3f& InB) -> float
    {
        const auto A = InA.GetSafeNormal();
        const auto B = InB.GetSafeNormal();
        return FMath::RadiansToDegrees(FMath::Acos(FMath::Clamp(FVector3f::DotProduct(A, B), -1.0f, 1.0f)));
    }

    // The Random Range analogue of NS_BuffLoop.md §14.7's recovered-hue key: `Color Channel Mode` is
    // Link RGB / Link A, so RGB is ONE lerp parameter and every channel is a function of it. Inverting the
    // widest-spread channel recovers that parameter directly, which is saturation- and brightness-independent
    // by construction and collapses to a single bucket the moment the draw stops varying.
    auto Get_LerpBucket(const FLinearColor& InColor, const FLinearColor& InMin, const FLinearColor& InMax) -> int32
    {
        const auto Spread = FVector3f(FMath::Abs(InMax.R - InMin.R),
                                      FMath::Abs(InMax.G - InMin.G),
                                      FMath::Abs(InMax.B - InMin.B));

        const auto Widest = Spread.X >= Spread.Y && Spread.X >= Spread.Z ? 0
                          : Spread.Y >= Spread.Z ? 1
                          : 2;

        const auto Value = Widest == 0 ? InColor.R : Widest == 1 ? InColor.G : InColor.B;
        const auto Low   = Widest == 0 ? InMin.R   : Widest == 1 ? InMin.G   : InMin.B;
        const auto High  = Widest == 0 ? InMax.R   : Widest == 1 ? InMax.G   : InMax.B;

        return FMath::RoundToInt32((Value - Low) / (High - Low) * 720.0f);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Particles_DebuffCastBehavior,
    "CkTests.UnitTests.CkParticles.DebuffCastBehavior",
    kCkUnitTestFlags)

bool FCkTest_Particles_DebuffCastBehavior::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_debuff_cast;

    // ---- The cadence row ----
    {
        TestEqual(TEXT("behavior 32 routes to the DebuffCast row"),
            ck::particles::Get_BehaviorTemplateSystemObjectPath(kBehaviorId),
            ck::particles::Get_DebuffCastTemplateSystemObjectPath());

        TestEqual(TEXT("behavior 32 binds no CkUsf look — all six of its looks ride the row's renderers"),
            ck::particles::Get_BehaviorLookName(kBehaviorId), NAME_None);

        const auto* RowSpec = static_cast<const ck::particles::FCk_ParticlesTemplateSpec*>(nullptr);
        for (const auto& Spec : ck::particles::Get_TemplateSpecs())
        {
            if (FString(Spec.AssetName) == FString(kRowAssetName))
            { RowSpec = &Spec; break; }
        }

        if (TestNotNull(TEXT("the cadence table declares a PS_CkParticles_Template_DebuffCast row"), RowSpec))
        {
            TestEqual(TEXT("row loop duration matches the source SYSTEM's Loop Once 2.0 s"),
                RowSpec->LoopDuration, kLoop, kTolerance);
            TestEqual(TEXT("row particle lifetime covers the Flames' 2.0 s resolved maximum"),
                RowSpec->ParticleLifetime, kLifetime, kTolerance);
            TestEqual(TEXT("row burst counts the ENABLED emitters only — four are disabled in the source"),
                RowSpec->BurstCount, kBurst);
            TestEqual(TEXT("row spawn rate is the sum of the four Spawn Rate modules"),
                RowSpec->SpawnRate, kSpawnRate, kTolerance);

            TestEqual(TEXT("the row declares one renderer per enabled source emitter"),
                RowSpec->RendererOverrides.Num(), 6);

            auto Meshes  = 0;
            auto Sheets  = 0;
            for (const auto& Renderer : RowSpec->RendererOverrides)
            {
                if (Renderer.Kind == ck::particles::ECk_ParticlesRenderer_Kind::Mesh)
                {
                    ++Meshes;
                    TestEqual(TEXT("the mesh row carries the generated claw carrier"),
                        FString(Renderer.MeshName), FString(TEXT("SlashClaw")));
                }
                if (Renderer.SubImageSize != FIntPoint(0, 0))
                {
                    ++Sheets;
                    TestTrue(TEXT("the flame sheet is the source's 2x2 grid"),
                        Renderer.SubImageSize == FIntPoint(2, 2));
                }
            }
            TestEqual(TEXT("exactly one renderer is a mesh"), Meshes, 1);
            TestEqual(TEXT("exactly one renderer declares a flipbook"), Sheets, 1);
        }

        TestTrue(TEXT("the roster VisTag maximum covers the DebuffCast row's renderers"),
            ck::particles::Get_RosterVisTag_Max() >= kVisSlash);
    }

    // ---- Burst particles take the source's exact per-emitter counts ----
    {
        auto Counts = TArray<int32>{};
        Counts.AddZeroed(Get_Layers().Num());

        for (auto Slot = 0; Slot < kBurst; ++Slot)
        { ++Counts[Layer_ForBurstSlot(Slot)]; }

        auto Index = 0;
        for (const auto& Layer : Get_Layers())
        {
            TestEqual(*FString::Printf(TEXT("%s takes its source burst count"), Layer.Name),
                Counts[Index], Layer.BurstCount);

            for (const auto Seed : Get_SeedsForBurstLayer(Index, 4))
            {
                TestEqual(*FString::Printf(TEXT("%s (burst seed %d) draws through its own renderer"), Layer.Name, Seed),
                    Evaluate_Burst(Layer.Life * 0.4f, Seed).VisTag, Layer.VisTag);
            }
            ++Index;
        }
    }

    // ---- Rate particles take the source's Spawn Rate shares, and NEVER a burst-only layer ----
    {
        constexpr auto SweepSize = 400000;

        auto Counts = TArray<int32>{};
        Counts.AddZeroed(Get_Layers().Num());

        for (auto Seed = 0; Seed < SweepSize; ++Seed)
        { ++Counts[Layer_ForRateDraw(Seed)]; }

        auto Index = 0;
        for (const auto& Layer : Get_Layers())
        {
            const auto Observed = static_cast<float>(Counts[Index]) / static_cast<float>(SweepSize);
            const auto Expected = Layer.Rate / kSpawnRate;

            TestTrue(*FString::Printf(TEXT("%s takes its source share of the stream (%.4f vs %.4f)"),
                Layer.Name, Observed, Expected), FMath::Abs(Observed - Expected) < 0.004f);
            ++Index;
        }

        TestEqual(TEXT("BigArrow never appears in the stream — it is system-governed and bursts once"),
            Counts[kLayerBigArrow], 0);
        TestEqual(TEXT("Flames never appears in the stream — it is the one Self/Once emitter with no rate"),
            Counts[kLayerFlames], 0);
    }

    // ---- The spawn-phase split ----
    {
        auto InsideWindowMatches = 0;
        auto HiddenPastWindow    = 0;

        for (auto Seed = 0; Seed < 2000; ++Seed)
        {
            const auto RateLayer = Layer_ForRateDraw(Seed);
            const auto AsRate    = Evaluate(0.02f, Seed, kWindow * 0.5f);
            const auto AsLate    = Evaluate(0.02f, Seed, kWindow + 0.25f);

            if (AsRate.VisTag == Get_Layers()[RateLayer].VisTag)
            { ++InsideWindowMatches; }

            if (Is_Hidden(AsLate))
            { ++HiddenPastWindow; }
        }

        TestEqual(TEXT("every rate particle born inside the window draws its rate layer"),
            InsideWindowMatches, 2000);
        TestEqual(TEXT("every rate particle born past the window is hidden"), HiddenPastWindow, 2000);
    }

    // ---- The curl force, and its structural control ----
    // Both sparkle clouds spawn on a sphere and are driven straight along that same direction, so their
    // BALLISTIC path never leaves the ray through the origin. Any angular deviation from the spawn direction
    // is therefore the curl term and nothing else: delete it and every number below is exactly zero.
    {
        for (const auto Layer : {kLayerSparkDark, kLayerSparkBr})
        {
            auto TotalDeviation = 0.0f;
            auto Deviated       = 0;
            auto Sampled        = 0;

            for (const auto Seed : Get_SeedsForBurstLayer(Layer, 16))
            {
                const auto Spawn = Evaluate_Burst(0.0f, Seed);
                const auto Late  = Evaluate_Burst(0.5f, Seed);

                if (Is_Hidden(Late) || Spawn.Position.IsNearlyZero())
                { continue; }

                const auto Deviation = Get_AngleDegrees(Spawn.Position, Late.Position);
                TotalDeviation += Deviation;
                if (Deviation > 1.0f) { ++Deviated; }
                ++Sampled;
            }

            TestTrue(*FString::Printf(TEXT("layer %d has curl-driven samples"), Layer), Sampled > 0);
            TestEqual(*FString::Printf(TEXT("every layer-%d particle is pushed off its radial line"), Layer),
                Deviated, Sampled);
            TestTrue(*FString::Printf(TEXT("layer %d's curl wander is a visible angle, not a rounding artefact (mean %f deg)"),
                Layer, TotalDeviation / static_cast<float>(FMath::Max(Sampled, 1))),
                TotalDeviation / static_cast<float>(FMath::Max(Sampled, 1)) > 5.0f);
        }

        // The curl path is stateless and re-integrated from the spawn point, so at Age 0 it contributes exactly
        // nothing: Sparkles_Dark must sit on the source's 200-unit shell to the last bit.
        for (const auto Seed : Get_SeedsForBurstLayer(kLayerSparkDark, 8))
        {
            TestEqual(TEXT("Sparkles_Dark spawns exactly on the source's 200-unit shell"),
                Evaluate_Burst(0.0f, Seed).Position.Size(), 200.0f, 1.0e-2f);
        }
    }

    // ---- The dark cloud IMPLODES and the bright one EXPLODES ----
    // The negative Velocity Strength is the Debuff signature and is the easiest thing in the system to get
    // backwards, because the two layers are otherwise near-identical.
    {
        auto DarkClosed = 0;
        auto DarkTotal  = 0;
        for (const auto Seed : Get_SeedsForBurstLayer(kLayerSparkDark, 16))
        {
            const auto Early = Evaluate_Burst(0.02f, Seed);
            const auto Late  = Evaluate_Burst(0.30f, Seed);
            if (Is_Hidden(Late)) { continue; }

            if (Late.Position.Size() < Early.Position.Size()) { ++DarkClosed; }
            TestTrue(TEXT("Sparkles_Dark travels toward the centre"),
                FVector3f::DotProduct(Late.Velocity, Early.Position) < 0.0f);
            ++DarkTotal;
        }
        TestEqual(TEXT("every dark sparkle closes on the origin"), DarkClosed, DarkTotal);

        auto BrightOpened = 0;
        auto BrightTotal  = 0;
        for (const auto Seed : Get_SeedsForBurstLayer(kLayerSparkBr, 16))
        {
            const auto Early = Evaluate_Burst(0.02f, Seed);
            const auto Late  = Evaluate_Burst(0.30f, Seed);
            if (Is_Hidden(Late)) { continue; }

            if (Late.Position.Size() > Early.Position.Size()) { ++BrightOpened; }
            ++BrightTotal;
        }
        TestEqual(TEXT("every bright sparkle opens away from the origin"), BrightOpened, BrightTotal);
    }

    // ---- The two Random Range colours, keyed on the recovered lerp parameter (NS_BuffLoop §14.7) ----
    {
        struct FRandomRange { int32 Layer; FLinearColor Minimum; FLinearColor Maximum; const TCHAR* Name; };

        const FRandomRange Ranges[] =
        {
            { kLayerSparkBr, FLinearColor(0.093059f, 0.181164f, 0.0953075f, 1.0f),
                             FLinearColor(0.111932f, 0.0409152f, 0.3564f,   1.0f), TEXT("Sparkles_Bright") },
            { kLayerSlash,   FLinearColor(0.0154102f, 0.03f,     0.0157825f, 0.45f),
                             FLinearColor(0.00942192f, 0.00344404f, 0.03f,  0.45f), TEXT("Slash")          },
        };

        for (const auto& Range : Ranges)
        {
            auto Live = TSet<int32>{};
            auto Dead = TSet<int32>{};

            // The dead control: the same key applied to a draw that does not vary. It collapses to exactly one
            // bucket, so an assertion that passes on it would be unfalsifiable.
            const auto Pinned = FMath::Lerp(Range.Minimum, Range.Maximum, 0.5f);

            for (const auto Seed : Get_SeedsForBurstLayer(Range.Layer, 120))
            {
                const auto Out = Evaluate_Burst(0.3f, Seed);
                if (Is_Hidden(Out))
                { continue; }

                Live.Add(Get_LerpBucket(Out.Color, Range.Minimum, Range.Maximum));
                Dead.Add(Get_LerpBucket(Pinned,    Range.Minimum, Range.Maximum));
            }

            TestTrue(*FString::Printf(TEXT("%s draws a per-particle colour (%d distinct buckets)"),
                Range.Name, Live.Num()), Live.Num() > 20);
            TestEqual(*FString::Printf(TEXT("%s's dead control collapses to one bucket"), Range.Name),
                Dead.Num(), 1);
        }
    }

    // ---- Flames: the shell that never moves, turns in place, and pins the distortion channel ----
    {
        for (const auto Seed : Get_SeedsForBurstLayer(kLayerFlames, 12))
        {
            const auto Early = Evaluate_Burst(0.01f, Seed);
            const auto Late  = Evaluate_Burst(0.90f, Seed);

            TestTrue(TEXT("Flames sit on the source's 20-unit shell"),
                FMath::IsNearlyEqual(Early.Position.Size(), 20.0f, 1.0e-2f));
            TestTrue(TEXT("Flames never move — the source gives them no velocity module at all"),
                (Late.Position - Early.Position).IsNearlyZero());

            const auto RatePerSecond = (Late.Rotation - Early.Rotation) / (0.90f - 0.01f);
            TestTrue(*FString::Printf(TEXT("Flames turn in place inside the source's +/-45 deg/s (%f)"), RatePerSecond),
                FMath::Abs(RatePerSecond) <= 45.0f + kTolerance);

            TestEqual(TEXT("Flames drive the distortion channel at the source's 10"),
                Late.Dynamic.Y, 10.0f, kTolerance);

            TestTrue(TEXT("the flame flipbook frame stays inside the 2x2 sheet"),
                Late.SubImageIndex >= 0.0f && Late.SubImageIndex <= 3.0f);
        }
    }

    // ---- Slash: the mesh layer ----
    {
        for (const auto Seed : Get_SeedsForBurstLayer(kLayerSlash, 12))
        {
            const auto Out = Evaluate_Burst(0.5f, Seed);

            TestTrue(TEXT("Slash writes no sprite size — it draws through a mesh renderer"),
                Out.Size.IsNearlyZero());
            TestTrue(TEXT("Slash's mesh scale keeps the source's pinned Y"),
                FMath::IsNearlyEqual(Out.Scale.Y, 1.0f, kTolerance));
            TestTrue(TEXT("Slash's mesh scale stays inside the source's 0.5..1.5 bounds"),
                Out.Scale.X >= 0.5f && Out.Scale.X <= 1.5f && Out.Scale.Z >= 0.5f && Out.Scale.Z <= 1.5f);
            TestTrue(TEXT("Slash sits at the cast point — its Sphere Location module is DISABLED"),
                Out.Position.IsNearlyZero());
            TestTrue(TEXT("Slash carries a per-particle orientation"),
                NOT FMath::IsNearlyEqual(Out.Orientation.W, 1.0f, 1.0e-6f));
        }

        // The offset channel is what sweeps the streak ALONG the claw's own u. Its three keys are the source's.
        const auto Seed  = Get_SeedsForBurstLayer(kLayerSlash, 1)[0];
        const auto Start = Evaluate_Burst(0.0001f, Seed);
        // 0.95 s is inside the layer's SHORTEST resolved life (1.0 s), so the sample is never a dead particle.
        const auto End   = Evaluate_Burst(0.95f, Seed);

        TestTrue(TEXT("the claw streak starts behind the mesh"), Start.Dynamic.Z < -0.45f);
        TestTrue(TEXT("the claw streak sweeps forward over the life"), End.Dynamic.Z > Start.Dynamic.Z + 0.8f);
        TestEqual(TEXT("Slash pins its dissolve channel at the source's 0.1"), Start.Dynamic.X, 0.1f, kTolerance);
    }

    // ---- BigArrow falls, where its Buff sibling rises ----
    {
        const auto Seed  = Get_SeedsForBurstLayer(kLayerBigArrow, 1)[0];
        const auto Start = Evaluate_Burst(0.0f, Seed);
        const auto Late  = Evaluate_Burst(1.0f, Seed);

        TestEqual(TEXT("BigArrow starts 50 units above the cast point"), Start.Position.Z, 50.0f, kTolerance);
        TestTrue(TEXT("BigArrow sinks"), Late.Position.Z < Start.Position.Z);
        TestTrue(TEXT("BigArrow's velocity points down"), Late.Velocity.Z < 0.0f);
        TestTrue(TEXT("BigArrow draws a taller-than-wide quad, as the source's (170, 240) authors"),
            Late.Size.Y > Late.Size.X);
    }

    // ---- Anti-vacuity: every layer contributes visible light somewhere in its life ----
    {
        auto Index = 0;
        for (const auto& Layer : Get_Layers())
        {
            auto PeakLuminance = 0.0f;

            for (const auto Seed : Get_SeedsForBurstLayer(Index, 4))
            {
                for (auto Step = 0; Step <= 40; ++Step)
                {
                    const auto Out   = Evaluate_Burst(kLifetime * static_cast<float>(Step) / 40.0f, Seed);
                    const auto Extent = FMath::Max(Out.Size.X, Out.Scale.X * 100.0f);
                    PeakLuminance = FMath::Max(PeakLuminance,
                        (Out.Color.R + Out.Color.G + Out.Color.B) * Out.Color.A * Extent);
                }
            }

            TestTrue(*FString::Printf(TEXT("%s emits nonzero light somewhere in its life"), Layer.Name),
                PeakLuminance > kTolerance);
            ++Index;
        }
    }

    // ---- Death: nothing survives the row's lifetime, on either spawn path ----
    {
        for (auto Seed = 0; Seed < 120; ++Seed)
        {
            TestTrue(*FString::Printf(TEXT("burst seed %d is dead past the row's 2.0 s lifetime"), Seed),
                Is_Hidden(Evaluate(kLifetime + 0.001f, Seed, 0.0f)));
            TestTrue(*FString::Printf(TEXT("streamed seed %d is dead past the row's 2.0 s lifetime"), Seed),
                Is_Hidden(Evaluate(kLifetime + 0.001f, Seed, 0.1f)));
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
