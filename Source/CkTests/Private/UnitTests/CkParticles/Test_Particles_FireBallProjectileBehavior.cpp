// Behavior-math gate for CkParticles BehaviorId 36 (FireBallProjectile) — the Vefects
// NS_FireBall_Projectile recreation, and the cookbook's FIRST ribbon-bearing port.
//
// Drives UCkParticles_DataInterface::Execute_Stage_CPU, the SAME CPU mirror a CPU sim runs, so it needs
// no Niagara system, no template asset, no RHI and no forked engine.
//
// Expected values are the SOURCE's own values as transcribed in
// CkFoundation/Source/CkParticles/Cookbook/NS_FireBall_Projectile.md §2/§5. The 15-slot burst partition
// and the rate-weighted draw are re-implemented here on purpose: the per-emitter counts and Spawn Rates
// ARE the fidelity claim.
//
// The load-bearing claims specific to this port:
//   - the SEED BANK partition. The row carries two emitters, and the only thing telling their particles
//     apart is a constant added to the ribbon emitter's UniqueID. The test asserts BOTH directions: no
//     main-bank id ever reaches the trail branch, and every ribbon-bank id reaches it and nothing else —
//     so the main emitter's output is bit-identical whether or not the ribbon emitter exists;
//   - the TWO RIBBONS on one renderer, separated by ribbon id (Particles.MeshIndex) and mirrored in the
//     sign of their curl, which a single-trail simplification would silently collapse;
//   - the burst BEATS: Smokes at 0.04 and FirstGlow at 0.05 apply to the burst population only — the
//     rate stream starts with the emitter, and a delay applied to both would empty the stream's head;
//   - corpus-derived colour values at BOTH ends of every ramp asserted, at a tolerance below the
//     smallest key delta in the curve.
//
// Cannot pass vacuously: behavior 36's VisTags are 157..163 and the pre-switch default is 0.

#include "Misc/AutomationTest.h"

#include "CkParticles/DataInterface/CkParticles_DataInterface.h"
#include "CkParticles/ScriptDefinition/CkParticles_ScriptDefinition_Naming.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_particles_fireball_projectile
{
    constexpr auto kBehaviorId = 36;
    constexpr auto kTolerance  = 1.0e-4f;

    // Source facts (recipe §2/§6.1 against corpus v3). Every emitter is Life Cycle Mode = Self on its own
    // 10 s loop and the system's own Infinite / 10 s agrees, so the two readings coincide.
    constexpr auto kLoop      = 10.0f;
    constexpr auto kLifetime  = 10.0f;  // the three Projectile_* cores live the whole flight
    constexpr auto kBurst     = 15;     // 1 + 5 + 5 + 1 + 1 + 1 + 1
    constexpr auto kSpawnRate = 408.0f; // 5 + 200 + 200 + 3
    constexpr auto kRibbonRate = 100.0f; // 50 + 50, on the row's SECOND emitter

    constexpr auto kRowAssetName = TEXT("PS_CkParticles_Template_FireBallProjectile");

    constexpr auto kVisPart04    = 157;
    constexpr auto kVisPart01Vel = 158;
    constexpr auto kVisPart03Br  = 159;
    constexpr auto kVisPart01Cam = 160;
    constexpr auto kVisFlames    = 161;
    constexpr auto kVisSmoke     = 162;
    constexpr auto kVisTrail     = 163;

    constexpr auto kLayerSecondGlow = 0;
    constexpr auto kLayerFlames     = 1;
    constexpr auto kLayerSmokes     = 2;
    constexpr auto kLayerFirstGlow  = 3;
    constexpr auto kLayerProj01     = 4;
    constexpr auto kLayerProj02     = 5;
    constexpr auto kLayerProj03     = 6;

    constexpr auto kDelaySmokes    = 0.04f;
    constexpr auto kDelayFirstGlow = 0.05f;

    constexpr auto kTrailLife = 0.25f;

    // Layer -> its source facts. Rate 0 marks a layer the source only ever BURSTS.
    struct FLayer { int32 BurstCount; float Rate; float Delay; float Life; int32 VisTag; const TCHAR* Name; };

    auto Get_Layers() -> TArrayView<const FLayer>
    {
        static const FLayer Layers[] =
        {
            { 1,   5.0f, 0.0f,            0.5f,  kVisPart03Br,  TEXT("SecondGlow")    },
            { 5, 200.0f, 0.0f,            0.3f,  kVisFlames,    TEXT("Flames01")      },
            { 5, 200.0f, kDelaySmokes,    0.4f,  kVisSmoke,     TEXT("Smokes")        },
            { 1,   3.0f, kDelayFirstGlow, 1.0f,  kVisPart01Cam, TEXT("FirstGlow")     },
            { 1,   0.0f, 0.0f,           10.0f,  kVisPart04,    TEXT("Projectile_01") },
            { 1,   0.0f, 0.0f,           10.0f,  kVisPart01Vel, TEXT("Projectile_02") },
            { 1,   0.0f, 0.0f,           10.0f,  kVisPart01Vel, TEXT("Projectile_03") },
        };
        return MakeArrayView(Layers);
    }

    // Burst slot -> layer. The RANGES are the source's own per-emitter burst counts.
    auto Layer_ForBurstSlot(int32 InSeed) -> int32
    {
        const auto S = ((InSeed % kBurst) + kBurst) % kBurst;

        if (S == 0)  { return kLayerSecondGlow; }
        if (S < 6)   { return kLayerFlames; }
        if (S < 11)  { return kLayerSmokes; }
        if (S == 11) { return kLayerFirstGlow; }
        if (S == 12) { return kLayerProj01; }
        if (S == 13) { return kLayerProj02; }
        return kLayerProj03;
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

        if (R < 5.0f)   { return kLayerSecondGlow; }
        if (R < 205.0f) { return kLayerFlames; }
        if (R < 405.0f) { return kLayerSmokes; }
        return kLayerFirstGlow;
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

    // InSpawnPhase is where in the loop the particle was born: 0 is the burst, anything else the rate stack.
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

    auto Evaluate_Ribbon(float InAge, int32 InLocalSeed) -> FCk_Particles_StageResult
    {
        return Evaluate(InAge, ck::particles::RibbonSeedBase + InLocalSeed, 0.0f);
    }

    auto Is_Hidden(const FCk_Particles_StageResult& InOut) -> bool
    {
        return InOut.Color.A == 0.0f && InOut.Color.R == 0.0f && InOut.Color.G == 0.0f && InOut.Color.B == 0.0f
            && InOut.Size.IsNearlyZero() && InOut.Scale.IsNearlyZero();
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Particles_FireBallProjectileBehavior,
    "CkTests.UnitTests.CkParticles.FireBallProjectileBehavior",
    kCkUnitTestFlags)

bool FCkTest_Particles_FireBallProjectileBehavior::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_fireball_projectile;

    // ---- The cadence row, and the ribbon emitter it declares ----
    {
        TestEqual(TEXT("behavior 36 routes to the FireBallProjectile row"),
            ck::particles::Get_BehaviorTemplateSystemObjectPath(kBehaviorId),
            ck::particles::Get_FireBallProjectileTemplateSystemObjectPath());

        TestEqual(TEXT("behavior 36 binds no CkUsf look — all seven of its looks ride the row's renderers"),
            ck::particles::Get_BehaviorLookName(kBehaviorId), NAME_None);

        const auto* RowSpec = static_cast<const ck::particles::FCk_ParticlesTemplateSpec*>(nullptr);
        for (const auto& Spec : ck::particles::Get_TemplateSpecs())
        {
            if (FString(Spec.AssetName) == FString(kRowAssetName))
            { RowSpec = &Spec; break; }
        }

        if (TestNotNull(TEXT("the cadence table declares a PS_CkParticles_Template_FireBallProjectile row"), RowSpec))
        {
            TestEqual(TEXT("row loop duration is the source's live Self / 10 s cycle"),
                RowSpec->LoopDuration, kLoop, kTolerance);
            TestEqual(TEXT("row particle lifetime is the Projectile cores' full 10 s"),
                RowSpec->ParticleLifetime, kLifetime, kTolerance);
            TestEqual(TEXT("row burst is the source's exact per-loop burst total"), RowSpec->BurstCount, kBurst);
            TestEqual(TEXT("row spawn rate is the sum of the four streaming emitters"),
                RowSpec->SpawnRate, kSpawnRate, kTolerance);

            // The itemization the totals are derived FROM, so a wrong total cannot hide behind a right sum.
            auto BurstSum = 0;
            auto RateSum  = 0.0f;
            for (const auto& Layer : Get_Layers())
            {
                BurstSum += Layer.BurstCount;
                RateSum  += Layer.Rate;
            }
            TestEqual(TEXT("the per-emitter burst counts sum to the row burst"), BurstSum, kBurst);
            TestEqual(TEXT("the per-emitter spawn rates sum to the row rate"), RateSum, kSpawnRate, kTolerance);

            const auto& Ribbon = RowSpec->RibbonEmitter;
            TestTrue(TEXT("the row declares a ribbon emitter"), Ribbon.Get_IsDeclared());
            TestEqual(TEXT("the ribbon emitter streams both trails' 50/s"), Ribbon.SpawnRate, kRibbonRate, kTolerance);
            TestEqual(TEXT("the ribbon emitter declares no burst — the source's trails are rate-only"),
                Ribbon.BurstCount, 0);
            TestEqual(TEXT("the two source ribbons share ONE renderer, separated by ribbon id"),
                Ribbon.Renderers.Num(), 1);

            if (Ribbon.Renderers.Num() == 1)
            {
                const auto& Renderer = Ribbon.Renderers[0];
                TestTrue(TEXT("the ribbon renderer is the Ribbon kind"),
                    Renderer.Kind == ck::particles::ECk_ParticlesRenderer_Kind::Ribbon);
                TestEqual(TEXT("the ribbon renderer draws the TrailFlatAdd look"),
                    FString(Renderer.LookName), FString(TEXT("TrailFlatAdd")));
                TestEqual(TEXT("the ribbon renderer's VisTag is the one the behavior writes"),
                    Renderer.VisTag, kVisTrail);
                TestNull(TEXT("a ribbon has no carrier mesh"), Renderer.MeshName);
            }
        }
    }

    // ---- The burst partition reproduces the source's per-emitter counts EXACTLY ----
    {
        auto Counts = TMap<int32, int32>{};
        for (auto Seed = 0; Seed < kBurst; ++Seed)
        { Counts.FindOrAdd(Layer_ForBurstSlot(Seed)) += 1; }

        const auto Layers = Get_Layers();
        for (auto Index = 0; Index < Layers.Num(); ++Index)
        {
            TestEqual(*FString::Printf(TEXT("one loop's burst carries exactly %d %s"),
                Layers[Index].BurstCount, Layers[Index].Name),
                Counts.FindRef(Index), Layers[Index].BurstCount);
        }
    }

    // ---- Every burst layer reaches its own renderer ----
    {
        const auto Layers = Get_Layers();
        for (auto Index = 0; Index < Layers.Num(); ++Index)
        {
            const auto Seeds = Get_SeedsForBurstLayer(Index, 3);
            for (const auto Seed : Seeds)
            {
                const auto Out = Evaluate_Burst(Layers[Index].Delay + Layers[Index].Life * 0.5f, Seed);
                TestEqual(*FString::Printf(TEXT("%s draws through VisTag %d"), Layers[Index].Name, Layers[Index].VisTag),
                    Out.VisTag, Layers[Index].VisTag);
            }
        }
    }

    // ---- The rate stream's per-layer share is the source's own rate share ----
    {
        constexpr auto Samples = 200000;
        auto Counts = TMap<int32, int32>{};
        for (auto Seed = 0; Seed < Samples; ++Seed)
        { Counts.FindOrAdd(Layer_ForRateDraw(Seed)) += 1; }

        const auto Layers = Get_Layers();
        for (auto Index = 0; Index < Layers.Num(); ++Index)
        {
            if (Layers[Index].Rate <= 0.0f)
            {
                TestEqual(*FString::Printf(TEXT("%s never appears in the rate stream — it only bursts"),
                    Layers[Index].Name), Counts.FindRef(Index), 0);
                continue;
            }

            const auto Share    = float(Counts.FindRef(Index)) / float(Samples);
            const auto Expected = Layers[Index].Rate / kSpawnRate;
            TestTrue(*FString::Printf(TEXT("%s takes %f of the stream against the source's %f"),
                Layers[Index].Name, Share, Expected), FMath::Abs(Share - Expected) < 0.004f);
        }
    }

    // ---- The two staggered burst BEATS, and the fact that the rate stream takes neither ----
    {
        const auto SmokeSeed = Get_SeedsForBurstLayer(kLayerSmokes, 1)[0];
        TestTrue(TEXT("a burst Smokes particle does not exist before its 0.04 s beat"),
            Is_Hidden(Evaluate_Burst(kDelaySmokes * 0.5f, SmokeSeed)));
        TestFalse(TEXT("a burst Smokes particle exists just after its beat"),
            Is_Hidden(Evaluate_Burst(kDelaySmokes + 0.01f, SmokeSeed)));

        const auto GlowSeed = Get_SeedsForBurstLayer(kLayerFirstGlow, 1)[0];
        TestTrue(TEXT("a burst FirstGlow particle does not exist before its 0.05 s beat"),
            Is_Hidden(Evaluate_Burst(kDelayFirstGlow * 0.5f, GlowSeed)));
        TestFalse(TEXT("a burst FirstGlow particle exists just after its beat"),
            Is_Hidden(Evaluate_Burst(kDelayFirstGlow + 0.01f, GlowSeed)));

        // The dead control: a spawn TIME belongs to the burst module, so a streamed particle of the same
        // layer is alive at an age the burst one is not.
        auto RateSmokeSeed = 0;
        for (auto Seed = 0; Seed < 200000; ++Seed)
        {
            if (Layer_ForRateDraw(Seed) != kLayerSmokes)
            { continue; }
            RateSmokeSeed = Seed;
            break;
        }
        const auto Streamed = Evaluate(0.01f, RateSmokeSeed, 3.0f);
        TestEqual(TEXT("a STREAMED Smokes particle takes no burst delay and draws immediately"),
            Streamed.VisTag, kVisSmoke);
        TestFalse(TEXT("a streamed Smokes particle at 0.01 s is not hidden"), Is_Hidden(Streamed));
    }

    // ---- Colour ramps, corpus-derived at BOTH ends. Tolerance 1e-4 is ~2e-5 relative on a quantity of
    // order 5 — above float drift, far below the smallest key delta in any of these curves ----
    {
        const auto GlowSeed = Get_SeedsForBurstLayer(kLayerSecondGlow, 1)[0];
        const auto Head     = Evaluate_Burst(0.0f, GlowSeed);
        TestEqual(TEXT("SecondGlow's red is CLAMPED to its first key's 2.0 before t=0.618"),
            Head.Color.R, 2.0f, kTolerance);
        TestEqual(TEXT("SecondGlow opens fully transparent"), Head.Color.A, 0.0f, kTolerance);

        const auto Peak = Evaluate_Burst(0.5f * 0.9634772f, GlowSeed);
        TestEqual(TEXT("SecondGlow's red reaches its last key's 3.0"), Peak.Color.R, 3.0f, kTolerance);
        TestEqual(TEXT("SecondGlow's green reaches its last key's 2.258827"), Peak.Color.G, 2.258827f, kTolerance);

        const auto Mid = Evaluate_Burst(0.5f * 0.8f, GlowSeed);
        TestEqual(TEXT("SecondGlow's red is on the ramp, not a step (2.5265734 at t=0.8)"),
            Mid.Color.R, 2.5265734f, kTolerance);

        const auto AlphaPeak = Evaluate_Burst(0.5f * 0.2463024f, GlowSeed);
        TestEqual(TEXT("SecondGlow's alpha reaches its 0.5 ceiling — the layer's Color.Scale Alpha"),
            AlphaPeak.Color.A, 0.5f, kTolerance);
    }
    {
        const auto FlameSeed = Get_SeedsForBurstLayer(kLayerFlames, 1)[0];
        const auto Life      = FMath::Lerp(0.2f, 0.3f, Rand(FlameSeed, 1));

        const auto Head = Evaluate_Burst(0.0f, FlameSeed);
        TestEqual(TEXT("Flames01 opens as an UNCLAMPED 5x red — the HDR head the additive pipeline exists for"),
            Head.Color.R, 5.0f, kTolerance);
        TestEqual(TEXT("Flames01's green head is 3.4334278"), Head.Color.G, 3.4334278f, kTolerance);

        const auto Knee = Evaluate_Burst(Life * 0.3682463f, FlameSeed);
        TestEqual(TEXT("Flames01's red falls to its middle key's 3.0"), Knee.Color.R, 3.0f, kTolerance);

        const auto Mid = Evaluate_Burst(Life * 0.2f, FlameSeed);
        TestEqual(TEXT("Flames01's red is on the ramp between them (4.1661088 at t=0.2)"),
            Mid.Color.R, 4.1661088f, kTolerance);

        const auto AlphaPeak = Evaluate_Burst(Life * 0.3030486f, FlameSeed);
        TestEqual(TEXT("Flames01's alpha reaches 1 — this layer carries no Color.Scale Alpha"),
            AlphaPeak.Color.A, 1.0f, kTolerance);
    }
    {
        const auto SmokeSeed = Get_SeedsForBurstLayer(kLayerSmokes, 1)[0];
        const auto Life      = FMath::Lerp(0.3f, 0.4f, Rand(SmokeSeed, 1));

        const auto Head = Evaluate_Burst(kDelaySmokes, SmokeSeed);
        TestEqual(TEXT("Smokes' alpha is clamped to its 0.6 ceiling before t=0.1267733"),
            Head.Color.A, 0.6f, kTolerance);
        TestEqual(TEXT("Smokes opens white — the source's duplicated t=0 key resolves to 1"),
            Head.Color.R, 1.0f, kTolerance);

        const auto Tail = Evaluate_Burst(kDelaySmokes + Life * 0.5143375f, SmokeSeed);
        TestEqual(TEXT("Smokes' alpha falls to 0.21 (0.35 under the layer's 0.6 scale)"),
            Tail.Color.A, 0.21f, kTolerance);

        const auto Knee = Evaluate_Burst(kDelaySmokes + Life * 0.3634169f, SmokeSeed);
        TestEqual(TEXT("Smokes' red reaches its 0.391573 key"), Knee.Color.R, 0.391573f, kTolerance);
    }
    {
        const auto GlowSeed = Get_SeedsForBurstLayer(kLayerFirstGlow, 1)[0];

        const auto Head = Evaluate_Burst(kDelayFirstGlow, GlowSeed);
        TestEqual(TEXT("FirstGlow opens fully transparent"), Head.Color.A, 0.0f, kTolerance);
        TestEqual(TEXT("FirstGlow's blue head is 0.7912982"), Head.Color.B, 0.7912982f, kTolerance);

        const auto Peak = Evaluate_Burst(kDelayFirstGlow + 0.2764866f, GlowSeed);
        TestEqual(TEXT("FirstGlow's alpha reaches its 0.1 ceiling — the layer's Color.Scale Alpha"),
            Peak.Color.A, 0.1f, kTolerance);

        const auto Knee = Evaluate_Burst(kDelayFirstGlow + 0.1328101f, GlowSeed);
        TestEqual(TEXT("FirstGlow's blue collapses to 0.1094617 by its second key"),
            Knee.Color.B, 0.1094617f, kTolerance);

        // Non-Uniform Curve mode: the Y curve runs to zero while X only reaches 0.4. Reading the inert
        // UNIFORM curve instead would leave a 500-unit square at the end of life.
        const auto End = Evaluate_Burst(kDelayFirstGlow + 1.0f, GlowSeed);
        TestEqual(TEXT("FirstGlow squeezes to a sliver: x -> 200 units"), End.Size.X, 200.0f, kTolerance);
        TestEqual(TEXT("FirstGlow squeezes to a sliver: y -> 0"), End.Size.Y, 0.0f, kTolerance);
    }

    // ---- The three core sprites: static, permanent, and each on its own paint ----
    {
        struct FCore { int32 Layer; int32 VisTag; FVector2f Size; FLinearColor Color; float Dissolve; const TCHAR* Name; };
        const FCore Cores[] =
        {
            { kLayerProj01, kVisPart04,    FVector2f(50.0f, 50.0f),   FLinearColor(1.0f, 0.672443f, 0.376262f, 1.0f),        0.0f, TEXT("Projectile_01") },
            { kLayerProj02, kVisPart01Vel, FVector2f(250.0f, 500.0f), FLinearColor(1.0f, 0.205079f, 0.0168074f, 0.3f),       3.0f, TEXT("Projectile_02") },
            { kLayerProj03, kVisPart01Vel, FVector2f(100.0f, 400.0f), FLinearColor(0.130136f, 0.00477695f, 0.00477695f, 0.5f), 2.0f, TEXT("Projectile_03") },
        };

        for (const auto& Core : Cores)
        {
            const auto Seed = Get_SeedsForBurstLayer(Core.Layer, 1)[0];

            for (const auto Age : { 0.0f, 5.0f, 9.9f })
            {
                const auto Out = Evaluate_Burst(Age, Seed);
                TestEqual(*FString::Printf(TEXT("%s holds its size at age %.1f — both its Scale Sprite Size modules are DISABLED"),
                    Core.Name, Age), Out.Size.X, Core.Size.X, kTolerance);
                TestEqual(*FString::Printf(TEXT("%s holds its stretch at age %.1f"), Core.Name, Age),
                    Out.Size.Y, Core.Size.Y, kTolerance);
                TestEqual(*FString::Printf(TEXT("%s holds its colour at age %.1f"), Core.Name, Age),
                    Out.Color.R, Core.Color.R, kTolerance);
                TestEqual(*FString::Printf(TEXT("%s holds its alpha at age %.1f"), Core.Name, Age),
                    Out.Color.A, Core.Color.A, kTolerance);
                TestEqual(*FString::Printf(TEXT("%s draws through VisTag %d"), Core.Name, Core.VisTag),
                    Out.VisTag, Core.VisTag);
                TestEqual(*FString::Printf(TEXT("%s drives dissolve %f"), Core.Name, Core.Dissolve),
                    Out.Dynamic.X, Core.Dissolve, kTolerance);
            }

            TestTrue(*FString::Printf(TEXT("%s is gone once its 10 s is up"), Core.Name),
                Is_Hidden(Evaluate_Burst(10.5f, Seed)));
        }
    }

    // ---- Every Flames particle plays all four sub-UV frames ----
    {
        const auto Seeds = Get_SeedsForBurstLayer(kLayerFlames, 200);
        auto SawAllFour = 0;
        auto InRange    = true;

        for (const auto Seed : Seeds)
        {
            const auto Life = FMath::Lerp(0.2f, 0.3f, Rand(Seed, 1));
            auto Frames = TSet<int32>{};

            for (auto Step = 0; Step < 24; ++Step)
            {
                const auto Out = Evaluate_Burst(Life * float(Step) / 23.0f, Seed);
                Frames.Add(FMath::FloorToInt32(Out.SubImageIndex));
                InRange = InRange && Out.SubImageIndex >= 0.0f && Out.SubImageIndex < 4.0f;
            }

            if (Frames.Num() == 4)
            { ++SawAllFour; }
        }

        TestTrue(TEXT("every sub-UV frame index stays inside the 2x2 sheet"), InRange);
        TestEqual(TEXT("every Flames particle plays all four frames of the sheet"), SawAllFour, Seeds.Num());
    }

    // ---- THE SEED BANK: the two emitters' populations, and the main one's independence from the ribbon ----
    {
        auto MainTags = TSet<int32>{};
        for (auto Seed = 0; Seed < 5000; ++Seed)
        { MainTags.Add(Evaluate_Burst(0.1f, Seed).VisTag); }

        TestFalse(TEXT("no main-emitter particle ever reaches the trail renderer"), MainTags.Contains(kVisTrail));
        TestTrue(TEXT("the main emitter reaches its own renderers"), MainTags.Contains(kVisPart03Br));

        // The same claim from the other side, and the one that would break if the bank leaked: a main-bank
        // id and its ribbon-bank twin must produce different populations, and the main-bank one must be
        // exactly what it is with no ribbon emitter in the picture (the trail branch is unreachable for it).
        for (auto Local = 0; Local < 40; ++Local)
        {
            const auto Ribbon = Evaluate_Ribbon(0.1f, Local);
            TestEqual(*FString::Printf(TEXT("ribbon-bank id %d draws through the trail renderer"), Local),
                Ribbon.VisTag, kVisTrail);
            TestEqual(*FString::Printf(TEXT("ribbon-bank id %d alternates between the two trails"), Local),
                Ribbon.MeshIndex, Local % 2);

            const auto Main = Evaluate_Burst(0.1f, Local);
            TestTrue(*FString::Printf(TEXT("main-bank id %d is a different population (VisTag %d)"),
                Local, Main.VisTag), Main.VisTag != kVisTrail);
        }
    }

    // ---- The trail's own curves ----
    {
        const auto Head = Evaluate_Ribbon(0.0f, 0);
        TestEqual(TEXT("the trail opens at its full 8-unit ribbon width"), Head.Size.X, 8.0f, kTolerance);
        TestEqual(TEXT("the trail's alpha opens at 0.3 — the layer's Color.Scale Alpha"),
            Head.Color.A, 0.3f, kTolerance);
        TestEqual(TEXT("the trail's red head is an unclamped 2.0"), Head.Color.R, 2.0f, kTolerance);
        TestEqual(TEXT("the trail's green head is 1.877372"), Head.Color.G, 1.877372f, kTolerance);

        const auto Mid = Evaluate_Ribbon(kTrailLife * 0.5f, 0);
        TestEqual(TEXT("the trail's width tapers linearly to half by mid-life"), Mid.Size.X, 4.0f, kTolerance);
        TestEqual(TEXT("the trail's alpha halves with it"), Mid.Color.A, 0.15f, kTolerance);

        const auto Knee = Evaluate_Ribbon(kTrailLife * 0.3597947f, 0);
        TestEqual(TEXT("the trail's red reaches its 1.0 key"), Knee.Color.R, 1.0f, kTolerance);

        const auto Tail = Evaluate_Ribbon(kTrailLife, 0);
        TestEqual(TEXT("the trail tapers to zero width by the end of its 0.25 s"), Tail.Size.X, 0.0f, kTolerance);

        TestTrue(TEXT("a trail point past its 0.25 s is hidden, not left streaming"),
            Is_Hidden(Evaluate_Ribbon(kTrailLife + 0.05f, 0)));

        // ...and frozen: the dead tail must stop travelling, or the ribbon would span the row's whole 10 s.
        const auto Frozen = Evaluate_Ribbon(5.0f, 0);
        TestEqual(TEXT("a dead trail point holds the position it died at"),
            Frozen.Position.X, Tail.Position.X, 0.01f);
    }

    // ---- The MIRRORED PAIR: equal-and-opposite curl on one shared linear run ----
    {
        for (const auto Age : { 0.05f, 0.125f, 0.25f })
        {
            const auto A = Evaluate_Ribbon(Age, 0);
            const auto B = Evaluate_Ribbon(Age, 1);

            const auto Linear  = FVector3f(-1000.0f * Age, 0.0f, 0.0f);
            const auto OffsetA = A.Position - Linear;
            const auto OffsetB = B.Position - Linear;

            TestTrue(*FString::Printf(TEXT("both trails share the same 1000 units/s backward run at age %.3f"), Age),
                OffsetA.Size() > 0.5f && OffsetB.Size() > 0.5f);

            const auto Cosine = FVector3f::DotProduct(OffsetA.GetSafeNormal(), OffsetB.GetSafeNormal());
            TestTrue(*FString::Printf(TEXT("the two trails bend to OPPOSITE sides at age %.3f (cos %f)"), Age, Cosine),
                Cosine < 0.0f);
        }

        // At a short age the two paths have barely diverged, so the mirror is near-exact — the assertion
        // that a single-signed curl (or a dropped second trail) would fail outright.
        const auto A = Evaluate_Ribbon(0.05f, 0);
        const auto B = Evaluate_Ribbon(0.05f, 1);
        const auto Linear = FVector3f(-1000.0f * 0.05f, 0.0f, 0.0f);
        const auto Cosine = FVector3f::DotProduct((A.Position - Linear).GetSafeNormal(),
                                                  (B.Position - Linear).GetSafeNormal());
        TestTrue(*FString::Printf(TEXT("early in life the mirror is near-exact (cos %f)"), Cosine), Cosine < -0.9f);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
