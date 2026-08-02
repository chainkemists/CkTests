// Behavior-math gate for CkParticles BehaviorId 45 (LightningHit) — the Vefects NS_Lightning_Hit recreation,
// the widest system in the cookbook and the campaign's last port.
//
// Drives UCkParticles_DataInterface::Execute_Stage_CPU, the SAME CPU mirror a CPU sim runs, so it needs no
// Niagara system, no template asset, no RHI and no forked engine.
//
// Expected values are the SOURCE's own values as transcribed in
// CkFoundation/Source/CkParticles/Cookbook/NS_Lightning_Hit.md §2/§5.
//
// The load-bearing claims specific to this port:
//   - the burst partition is the source's per-emitter counts exactly, over 84 slots — twenty emitters' own
//     counts plus Lightning_02's three SOLVED release points, and NOT the arcs' six, which are ribbon
//     particles on the row's second emitter;
//   - LIGHTNING_02's spawn inversion. Its source emitter has no burst module at all: a Spawn Rate falling
//     10 -> 0 over 0.5 s, integrating to 2.5 particles. The three points are pinned at the times that rate
//     releases them, and the third sits at the window edge;
//   - THE INVERTED LIFETIME RANGE ([P0-D7]). Sparkles' Lifetime Min is 1.0 and its Max is 0.5. Niagara's
//     Random Range lerps Min -> Max whichever way round they sit, so the range is [0.5, 1.0] and BOTH ends
//     must be reachable — a reading that silently swapped them would be indistinguishable here, which is
//     exactly why the assertion pins the span rather than one draw;
//   - the sparkle STROBE: a seven-key alpha with two flat-zero plateaus, so the motes blink out twice
//     mid-life. All the turning points are pinned;
//   - BOTH sub-UV modes on one row. Lightning runs LINEAR from frame 0 on every particle; Flames runs
//     RANDOM, so its start frame varies per seed. The pair is asserted against each other;
//   - the four delayed layers gate on their own beats (0.05 s on Raimbow/Ring/Flames, 0.1 s on
//     Flare_01/FlareImpact/GroundCrack_01) and run their curves on (age - delay);
//   - the arc pair is TWO ribbons on ONE renderer, split 13 / 17 by ribbon id, with the same solved release
//     times as NS_Lightning_Muzzle's — the two emitters are byte-identical in the corpus;
//   - the row declares no spawn rate, so behavior 45 must stay INDEPENDENT of the emitter clock.
//
// The partition census reads each slot while it is ALIVE, swept across the loop: a layer outside its own
// window leaves through the early Hide() before its branch assigns VisTag, so a single-instant read buckets
// every beat-carrying layer at the switch's pre-branch default of 0 (the batch-H lesson).
//
// Cannot pass vacuously: behavior 45's VisTags are 225..241 and the pre-switch default is 0.

#include "Misc/AutomationTest.h"

#include "CkParticles/DataInterface/CkParticles_DataInterface.h"
#include "CkParticles/ScriptDefinition/CkParticles_ScriptDefinition_Naming.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_particles_lightning_hit
{
    constexpr auto kBehaviorId = 45;
    constexpr auto kTolerance  = 1.0e-4f;

    // Source facts (recipe §2/§6.1 against corpus v3). Loop Once / 2.0 s system; the longest layer is Star02
    // at its resolved 1.3 s maximum.
    constexpr auto kLoop     = 2.0f;
    constexpr auto kLifetime = 1.3f;
    constexpr auto kBurst    = 84;

    constexpr auto kRowAssetName = TEXT("PS_CkParticles_Template_LightningHit");

    constexpr auto kVisGroundGlow = 225;
    constexpr auto kVisPart01     = 226;
    constexpr auto kVisPart01Br   = 227;
    constexpr auto kVisFlare      = 228;
    constexpr auto kVisPart04     = 229;
    constexpr auto kVisLightning  = 230;
    constexpr auto kVisSpike      = 231;
    constexpr auto kVisStrip      = 232;
    constexpr auto kVisImpact     = 233;
    constexpr auto kVisRainbow    = 234;
    constexpr auto kVisRing       = 235;
    constexpr auto kVisCrack      = 236;
    constexpr auto kVisStar       = 237;
    constexpr auto kVisBubble     = 238;
    constexpr auto kVisSpike01    = 239;
    constexpr auto kVisFlames     = 240;
    constexpr auto kVisArc        = 241;

    // The arc ribbon: 1 + 12 for LightningArc_01, then 5 + 12 for LightningArc_02.
    constexpr auto kArcPoints    = 30;
    constexpr auto kArc1Count    = 13;
    constexpr auto kArc2Count    = 17;
    constexpr auto kArcWindow    = 0.3f;
    constexpr auto kArcRatePoint = 12;

    // The layers' own slot bands, in the §2 emitter order.
    constexpr auto kSlotGroundGlow01 = 0;
    constexpr auto kSlotGroundGlow02 = 1;
    constexpr auto kSlotGlow01       = 2;
    constexpr auto kSlotSparkles     = 3;   // .. 22
    constexpr auto kSlotFlare01      = 23;
    constexpr auto kSlotStretched    = 24;  // .. 33
    constexpr auto kSlotLightning01  = 34;  // .. 36
    constexpr auto kSlotSpikes       = 37;  // .. 41
    constexpr auto kSlotStrip        = 42;  // .. 44
    constexpr auto kSlotLightning02  = 45;  // .. 47
    constexpr auto kSlotFlareImpact  = 48;
    constexpr auto kSlotRaimbow      = 49;
    constexpr auto kSlotRing         = 50;
    constexpr auto kSlotCrack        = 51;
    constexpr auto kSlotStar02       = 52;  // .. 56
    constexpr auto kSlotGlow02       = 57;
    constexpr auto kSlotBubble       = 58;
    constexpr auto kSlotSpike01      = 59;  // .. 63
    constexpr auto kSlotFlames01     = 64;  // .. 73
    constexpr auto kSlotFlames02     = 74;  // .. 83

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

    // ---- Reading the partition while each slot is ALIVE ---------------------------------------------------
    //
    // Past the longest layer's death: Star02 reaches 1.3 s, GroundCrack_01's 0.1 s beat plus its flat 1 s
    // reaches 1.1, and Lightning_02's last solved point spawns at 0.5 and can live 0.5 more. The step is
    // finer than the SHORTEST window in the system (FlareImpact's 0.05 s), so no layer can be missed.
    constexpr auto kCensusSpan  = 1.4f;
    constexpr auto kCensusSteps = 400;

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

    // The first and last loop ages at which a slot draws anything.
    struct FLiveSpan
    {
        float First = -1.0f;
        float Last  = -1.0f;
    };

    auto Get_LiveSpan(int32 InSeed, float InSpan, int32 InSteps) -> FLiveSpan
    {
        auto Result = FLiveSpan{};

        for (auto Step = 0; Step <= InSteps; ++Step)
        {
            const auto Age = InSpan * float(Step) / float(InSteps);

            if (Is_Hidden(Evaluate(Age, InSeed)))
            { continue; }

            if (Result.First < 0.0f) { Result.First = Age; }
            Result.Last = Age;
        }
        return Result;
    }

    auto Find_ArcSpawnTime(int32 InLocalSeed) -> float
    {
        constexpr auto Steps = 3000;

        for (auto Step = 0; Step <= Steps; ++Step)
        {
            const auto Age = kArcWindow * float(Step) / float(Steps);

            if (NOT Is_Hidden(Evaluate_Ribbon(Age, InLocalSeed)))
            { return Age; }
        }
        return kArcWindow;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Particles_LightningHitBehavior,
    "CkTests.UnitTests.CkParticles.LightningHitBehavior",
    kCkUnitTestFlags)

bool FCkTest_Particles_LightningHitBehavior::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_lightning_hit;

    // ---- The cadence row, its sixteen renderers and the ribbon emitter it declares ----
    {
        TestEqual(TEXT("behavior 45 routes to the LightningHit row"),
            ck::particles::Get_BehaviorTemplateSystemObjectPath(kBehaviorId),
            ck::particles::Get_LightningHitTemplateSystemObjectPath());

        TestEqual(TEXT("behavior 45 binds no CkUsf look — all sixteen looks ride the row's renderers"),
            ck::particles::Get_BehaviorLookName(kBehaviorId), NAME_None);

        const auto* RowSpec = static_cast<const ck::particles::FCk_ParticlesTemplateSpec*>(nullptr);
        for (const auto& Spec : ck::particles::Get_TemplateSpecs())
        {
            if (FString(Spec.AssetName) == FString(kRowAssetName))
            { RowSpec = &Spec; break; }
        }

        if (TestNotNull(TEXT("the cadence table declares a PS_CkParticles_Template_LightningHit row"), RowSpec))
        {
            TestEqual(TEXT("row loop duration is the system's Loop Once / 2.0 s"),
                RowSpec->LoopDuration, kLoop, kTolerance);
            TestEqual(TEXT("row particle lifetime is Star02's resolved 1.3 s maximum"),
                RowSpec->ParticleLifetime, kLifetime, kTolerance);
            TestEqual(TEXT("row burst is the twenty sprite/mesh emitters plus Lightning_02's solved trio"),
                RowSpec->BurstCount, kBurst);
            TestEqual(TEXT("the row declares NO spawn rate — every streamed layer is inverted into the burst"),
                RowSpec->SpawnRate, 0.0f, kTolerance);

            TestEqual(TEXT("the row declares sixteen renderers — the cookbook's widest spread"),
                RowSpec->RendererOverrides.Num(), 16);

            const auto& Ribbon = RowSpec->RibbonEmitter;
            TestTrue(TEXT("the row declares a ribbon emitter"), Ribbon.Get_IsDeclared());
            TestEqual(TEXT("the ribbon emitter bursts both arcs' burst and solved rate points"),
                Ribbon.BurstCount, kArcPoints);
            TestEqual(TEXT("the ribbon emitter declares no RATE — a falling rate is not a row constant"),
                Ribbon.SpawnRate, 0.0f, kTolerance);
            TestEqual(TEXT("the arc PAIR shares ONE renderer, separated by ribbon id"),
                Ribbon.Renderers.Num(), 1);

            if (Ribbon.Renderers.Num() == 1)
            {
                const auto& Renderer = Ribbon.Renderers[0];
                TestTrue(TEXT("the ribbon renderer is the Ribbon kind"),
                    Renderer.Kind == ck::particles::ECk_ParticlesRenderer_Kind::Ribbon);
                TestEqual(TEXT("the ribbon renderer draws the FlatAdd02Ribbon look"),
                    FString(Renderer.LookName), FString(TEXT("FlatAdd02Ribbon")));
                TestEqual(TEXT("the ribbon renderer's VisTag is the one the behavior writes"),
                    Renderer.VisTag, kVisArc);
                TestNull(TEXT("a ribbon has no carrier mesh"), Renderer.MeshName);
            }

            // The bubble carrier takes the source's per-emitter Mesh Uniform Scale as a RENDERER constant;
            // the two pyramid renderers keep unit scale because theirs is per-particle random. The pyramid
            // carrier is declared TWICE, which is the row's own structural claim.
            auto SphereScale = FVector::ZeroVector;
            auto SpikeRows   = 0;
            auto SheetRows   = 0;
            auto CustomRows  = 0;
            for (const auto& Renderer : RowSpec->RendererOverrides)
            {
                if (Renderer.VisTag == kVisBubble) { SphereScale = Renderer.MeshScale; }
                if (Renderer.MeshName != nullptr && FString(Renderer.MeshName) == FString(TEXT("Spike")))
                { ++SpikeRows; }
                if (Renderer.SubImageSize.X == 2 && Renderer.SubImageSize.Y == 2)
                { ++SheetRows; }
                if (Renderer.Kind == ck::particles::ECk_ParticlesRenderer_Kind::CustomFacingSprite)
                { ++CustomRows; }
            }
            TestEqual(TEXT("the bubble carrier takes the source's Mesh Uniform Scale 0.8"),
                static_cast<float>(SphereScale.X), 0.8f, KINDA_SMALL_NUMBER);
            TestEqual(TEXT("the pyramid carrier is declared twice — once per source spike emitter"),
                SpikeRows, 2);
            TestEqual(TEXT("two of the sixteen renderers are 2x2 sub-UV sheets"), SheetRows, 2);
            TestEqual(TEXT("two of them are custom-facing ground quads"), CustomRows, 2);
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

        TestEqual(TEXT("every one of the 84 burst slots draws at some point in the loop"), NeverDrawn, 0);
        TestEqual(TEXT("...and each slot keeps ONE renderer for its whole life"), Inconsistent, 0);

        TestEqual(TEXT("the custom-facing Part01 quad draws both GroundGlows"), Tags.FindRef(kVisGroundGlow), 2);
        TestEqual(TEXT("the camera Part01 quad draws Glow_01 and Glow_02"),     Tags.FindRef(kVisPart01),     2);
        TestEqual(TEXT("Sparkles bursts twenty"),                               Tags.FindRef(kVisPart01Br),  20);
        TestEqual(TEXT("Flare_01 is one particle"),                             Tags.FindRef(kVisFlare),      1);
        TestEqual(TEXT("Sparkles_Stretched bursts ten"),                        Tags.FindRef(kVisPart04),    10);
        TestEqual(TEXT("the bolt sheet draws Lightning_01's three AND Lightning_02's solved three"),
            Tags.FindRef(kVisLightning), 6);
        TestEqual(TEXT("Spikes bursts five"),                                   Tags.FindRef(kVisSpike),      5);
        TestEqual(TEXT("LightningStrip bursts three"),                          Tags.FindRef(kVisStrip),      3);
        TestEqual(TEXT("FlareImpact is one particle"),                          Tags.FindRef(kVisImpact),     1);
        TestEqual(TEXT("Raimbow is one particle"),                              Tags.FindRef(kVisRainbow),    1);
        TestEqual(TEXT("Ring is one particle"),                                 Tags.FindRef(kVisRing),       1);
        TestEqual(TEXT("GroundCrack_01 is one particle"),                       Tags.FindRef(kVisCrack),      1);
        TestEqual(TEXT("Star02 bursts five"),                                   Tags.FindRef(kVisStar),       5);
        TestEqual(TEXT("Bubble_First_Explo is one mesh"),                       Tags.FindRef(kVisBubble),     1);
        TestEqual(TEXT("Spike01 bursts five meshes"),                           Tags.FindRef(kVisSpike01),    5);
        TestEqual(TEXT("both Flames emitters burst ten each"),                  Tags.FindRef(kVisFlames),    20);

        // The modulus holds beyond one period, and no main-bank particle ever reaches the ribbon renderer.
        auto WideSpikes    = 0;
        auto MainReachedArc = false;
        for (auto Seed = 0; Seed < kBurst * 60; ++Seed)
        {
            const auto Out = Evaluate(0.05f, Seed);
            if (Out.VisTag == kVisSpike) { ++WideSpikes; }
            if (Out.VisTag == kVisArc)   { MainReachedArc = true; }
        }
        TestEqual(TEXT("the partition holds across 60 moduli"), WideSpikes, 5 * 60);
        TestFalse(TEXT("no main-bank particle reaches the arc renderer"), MainReachedArc);
    }

    // ---- Every drawing sample sits in the row's own VisTag band, and every hidden one is fully inert ----
    {
        const auto RosterMax = ck::particles::Get_RosterVisTag_Max();

        auto OutOfBand = 0;
        auto LiveCount = 0;
        auto Leaky     = 0;

        for (auto Seed = 0; Seed < kBurst; ++Seed)
        {
            for (auto Step = 0; Step <= 60; ++Step)
            {
                const auto Out = Evaluate(kCensusSpan * float(Step) / 60.0f, Seed);

                if (Is_Hidden(Out))
                {
                    if (Out.Color.A != 0.0f || NOT Out.Size.IsNearlyZero() || NOT Out.Scale.IsNearlyZero())
                    { ++Leaky; }
                    continue;
                }

                ++LiveCount;
                if (Out.VisTag < kVisGroundGlow || Out.VisTag > RosterMax)
                { ++OutOfBand; }
            }
        }

        TestTrue(*FString::Printf(TEXT("the band sweep is non-vacuous (%d live samples)"), LiveCount),
            LiveCount > 500);
        TestEqual(TEXT("every drawing sample sits inside the roster's VisTag ledger"), OutOfBand, 0);
        TestEqual(TEXT("every hidden sample is fully inert"), Leaky, 0);
        TestEqual(TEXT("the roster ceiling is this port's ribbon renderer"), RosterMax, kVisArc);
    }

    // ---- LIGHTNING_02: three points at the times a falling 10 -> 0 rate releases them ----
    {
        // Lightning_01 is a burst at t = 0, so its three slots draw from the first frame.
        TestEqual(TEXT("Lightning_01 draws from t = 0"),
            Evaluate(0.0f, kSlotLightning01).VisTag, kVisLightning);

        // 0.5 * (1 - sqrt(1 - (i + 0.5)/2.5)) for i = 0, 1, 2. The third lands exactly at the window edge,
        // because the source's own integral over the window is 2.5 rather than 3.
        const float Expected[] = { 0.0527864f, 0.1837722f, 0.5f };

        for (auto Point = 0; Point < 3; ++Point)
        {
            const auto Span = Get_LiveSpan(kSlotLightning02 + Point, 1.2f, 4800);

            TestEqual(*FString::Printf(TEXT("Lightning_02 point %d is released at its solved time"), Point),
                Span.First, Expected[Point], 6.0e-4f);
        }

        TestTrue(TEXT("Lightning_02's first point is hidden before its release"),
            Is_Hidden(Evaluate(0.04f, kSlotLightning02)));
        TestTrue(TEXT("Lightning_02's last point is hidden through the whole first half of the window"),
            Is_Hidden(Evaluate(0.49f, kSlotLightning02 + 2)));
    }

    // ---- THE INVERTED LIFETIME RANGE ([P0-D7]): Min 1.0, Max 0.5, so the span is [0.5, 1.0] ----
    {
        auto Shortest = 10.0f;
        auto Longest  = 0.0f;

        for (auto Repeat = 0; Repeat < 40; ++Repeat)
        {
            const auto Seed = kSlotSparkles + Repeat * kBurst;
            const auto Span = Get_LiveSpan(Seed, 1.2f, 2400);

            Shortest = FMath::Min(Shortest, Span.Last);
            Longest  = FMath::Max(Longest,  Span.Last);
        }

        TestTrue(*FString::Printf(TEXT("no sparkle outlives the range's upper end of 1.0 s (longest %f)"),
            Longest), Longest <= 1.0f + 2.0e-3f);
        TestTrue(*FString::Printf(TEXT("no sparkle dies before the range's lower end of 0.5 s (shortest %f)"),
            Shortest), Shortest >= 0.5f - 2.0e-3f);
        TestTrue(*FString::Printf(TEXT("both ends of the inverted range are reached (%f .. %f)"),
            Shortest, Longest), Shortest < 0.6f && Longest > 0.9f);
    }

    // ---- The sparkle STROBE: two flat-zero plateaus inside one life, and the shared lightning ramp ----
    {
        const auto Sparkle = Evaluate(0.0f, kSlotSparkles);
        TestEqual(TEXT("a sparkle draws the fine paint"), Sparkle.VisTag, kVisPart01Br);

        // Corpus-derived at BOTH ends of the ramp, sampled on the layer's own normalized life.
        const auto Life = Get_LiveSpan(kSlotSparkles, 1.2f, 4800).Last;

        const auto Open = Evaluate(0.0f, kSlotSparkles);
        TestEqual(TEXT("the ramp opens white on red"),   Open.Color.R, 1.0f,      kTolerance);
        TestEqual(TEXT("...at its 0.745404 green key"),  Open.Color.G, 0.745404f, kTolerance);
        TestEqual(TEXT("...and its 0.304987 blue key"),  Open.Color.B, 0.304987f, kTolerance);

        const auto Peak = Evaluate(Life * 0.504679f, kSlotSparkles);
        TestEqual(TEXT("the strobe returns to full alpha at its 0.504679 key"), Peak.Color.A, 1.0f, 2.0e-2f);

        const auto Trough1 = Evaluate(Life * 0.32f, kSlotSparkles);
        const auto Trough2 = Evaluate(Life * 0.73f, kSlotSparkles);
        TestEqual(TEXT("the sparkle blinks out on the first plateau"), Trough1.Color.A, 0.0f, 1.0e-3f);
        TestEqual(TEXT("...and again on the second"),                  Trough2.Color.A, 0.0f, 1.0e-3f);

        // Counting the turning points is what tells a strobe from a fade.
        auto Peaks    = 0;
        auto Troughs  = 0;
        auto Previous = -1.0f;
        auto Rising   = true;

        for (auto Step = 0; Step <= 600; ++Step)
        {
            const auto Out = Evaluate(Life * float(Step) / 600.0f, kSlotSparkles);

            if (Is_Hidden(Out))
            { break; }

            if (Previous >= 0.0f)
            {
                const auto NowRising = Out.Color.A > Previous;
                if (NowRising != Rising)
                {
                    if (Rising) { ++Peaks; } else { ++Troughs; }
                    Rising = NowRising;
                }
            }
            Previous = Out.Color.A;
        }

        TestTrue(*FString::Printf(TEXT("the sparkle alpha strobes twice — %d peaks and %d troughs"),
            Peaks, Troughs), Peaks >= 2 && Troughs >= 2);
    }

    // ---- BOTH sub-UV modes on one row: Lightning is LINEAR, Flames is RANDOM ----
    {
        // Linear: every particle starts on frame 0 and walks all four frames.
        auto LightningStarts = TSet<int32>{};
        auto LightningFrames = TSet<int32>{};

        for (auto Repeat = 0; Repeat < 30; ++Repeat)
        {
            const auto Seed = kSlotLightning01 + Repeat * kBurst;
            LightningStarts.Add(FMath::RoundToInt(Evaluate(0.0f, Seed).SubImageIndex));

            for (auto Step = 0; Step <= 200; ++Step)
            { LightningFrames.Add(FMath::RoundToInt(Evaluate(0.3f * float(Step) / 200.0f, Seed).SubImageIndex)); }
        }

        TestEqual(TEXT("every bolt starts on frame 0 — Sub UV Animation is LINEAR"), LightningStarts.Num(), 1);
        TestTrue(TEXT("...and frame 0 is that start"), LightningStarts.Contains(0));
        TestEqual(TEXT("the bolts walk all four frames of the 2x2 sheet"), LightningFrames.Num(), 4);

        // Random: the start frame varies per seed. Sampled just past the 0.05 s beat.
        auto FlamesStarts = TSet<int32>{};
        for (auto Repeat = 0; Repeat < 60; ++Repeat)
        {
            const auto Seed = kSlotFlames01 + Repeat * kBurst;
            const auto Out  = Evaluate(0.06f, Seed);

            if (NOT Is_Hidden(Out))
            { FlamesStarts.Add(FMath::RoundToInt(Out.SubImageIndex)); }
        }

        TestTrue(*FString::Printf(TEXT("the flames pick a RANDOM start frame (%d distinct)"),
            FlamesStarts.Num()), FlamesStarts.Num() >= 3);
    }

    // ---- The four beat-carrying layers gate on their own delays ----
    {
        // Raimbow and Ring open at 0.05; Flare_01, FlareImpact and GroundCrack_01 at 0.1.
        TestTrue(TEXT("Raimbow is hidden before its 0.05 s beat"),  Is_Hidden(Evaluate(0.04f, kSlotRaimbow)));
        TestTrue(TEXT("Ring is hidden before its 0.05 s beat"),     Is_Hidden(Evaluate(0.04f, kSlotRing)));
        TestTrue(TEXT("Flare_01 is hidden before its 0.1 s beat"),  Is_Hidden(Evaluate(0.09f, kSlotFlare01)));
        TestTrue(TEXT("FlareImpact is hidden before its beat"),     Is_Hidden(Evaluate(0.09f, kSlotFlareImpact)));
        TestTrue(TEXT("GroundCrack_01 is hidden before its beat"),  Is_Hidden(Evaluate(0.09f, kSlotCrack)));
        TestTrue(TEXT("both Flames layers are hidden before 0.05"),
            Is_Hidden(Evaluate(0.04f, kSlotFlames01)) && Is_Hidden(Evaluate(0.04f, kSlotFlames02)));

        TestFalse(TEXT("Raimbow draws just past its beat"),  Is_Hidden(Evaluate(0.06f, kSlotRaimbow)));
        TestFalse(TEXT("Flare_01 draws just past its beat"), Is_Hidden(Evaluate(0.11f, kSlotFlare01)));

        // FlareImpact is the shortest window in the system: 0.1 .. 0.15, and its alpha HOLDS at one until
        // t = 0.237851 rather than falling from the first frame.
        const auto ImpactOpen = Evaluate(0.11f, kSlotFlareImpact);
        TestEqual(TEXT("FlareImpact draws its own paint"), ImpactOpen.VisTag, kVisImpact);
        TestEqual(TEXT("FlareImpact's alpha still holds at one a fifth into its life"),
            ImpactOpen.Color.A, 1.0f, kTolerance);
        TestEqual(TEXT("FlareImpact holds its authored violet"), ImpactOpen.Color.R, 0.644888f, kTolerance);
        TestEqual(TEXT("...falling to zero at death"),
            Evaluate(0.15f, kSlotFlareImpact).Color.A, 0.0f, kTolerance);
        TestTrue(TEXT("FlareImpact is gone past 0.15 s"), Is_Hidden(Evaluate(0.16f, kSlotFlareImpact)));

        // GroundCrack_01 is the longest deterministic layer: 0.1 .. 1.1.
        TestFalse(TEXT("GroundCrack_01 is still drawing at 1.05 s"), Is_Hidden(Evaluate(1.05f, kSlotCrack)));
        TestTrue(TEXT("...and gone past 1.1 s"),                     Is_Hidden(Evaluate(1.12f, kSlotCrack)));
    }

    // ---- The two ground decals, and the crack's white -> blue -> black collapse ----
    {
        const auto Glow = Evaluate(0.0f, kSlotGroundGlow01);
        TestEqual(TEXT("GroundGlow_01 draws the custom-facing quad"), Glow.VisTag, kVisGroundGlow);
        TestEqual(TEXT("its alignment is the sim-space Y axis"),  Glow.SpriteAlignment.Y, 1.0f, kTolerance);
        TestEqual(TEXT("its facing is the sim-space Z axis"),     Glow.SpriteFacing.Z,    1.0f, kTolerance);
        TestEqual(TEXT("it opens on the ground-glow curve's 0.752942 red"),
            Glow.Color.R, 0.752942f, kTolerance);
        TestEqual(TEXT("...and closes on its 0.327778"),
            Evaluate(0.2f, kSlotGroundGlow01).Color.R, 0.327778f, kTolerance);
        TestEqual(TEXT("GroundGlow_01 opens at half its 2600-unit size"), Glow.Size.X, 1300.0f, kTolerance);

        // GroundGlow_02 has NO Color module: it holds its Initialize colour and only fades.
        const auto Glow02Open = Evaluate(0.0f, kSlotGroundGlow02);
        const auto Glow02Half = Evaluate(0.1f, kSlotGroundGlow02);
        TestEqual(TEXT("GroundGlow_02 holds its authored blue at spawn"),
            Glow02Open.Color.B, 1.0f, kTolerance);
        TestEqual(TEXT("...and the SAME blue at half life — it carries no Color module"),
            Glow02Half.Color.B, 1.0f, kTolerance);
        TestEqual(TEXT("its alpha halves by half life off its authored 0.5"),
            Glow02Half.Color.A, 0.25f, kTolerance);
        TestEqual(TEXT("GroundGlow_02 is the largest sprite in the cookbook at 4000 units"),
            Evaluate(0.1f, kSlotGroundGlow02).Size.X, 4000.0f, kTolerance);

        // The crack's whole colour read happens in the first 13 % of a flat one-second life.
        const auto Crack = Evaluate(0.1f, kSlotCrack);
        TestEqual(TEXT("GroundCrack_01 draws its own custom-facing decal"), Crack.VisTag, kVisCrack);
        TestEqual(TEXT("it opens white"), Crack.Color.R, 1.0f, kTolerance);

        const auto CrackBlue = Evaluate(0.1f + 0.0494285f, kSlotCrack);
        TestEqual(TEXT("it turns BLUE at its 0.0494285 key — blue rises where red and green fall"),
            CrackBlue.Color.B, 1.0f, 2.0e-3f);
        TestTrue(TEXT("...and red has already collapsed by then"), CrackBlue.Color.R < 0.4f);

        const auto CrackBlack = Evaluate(0.1f + 0.12975f, kSlotCrack);
        TestEqual(TEXT("it is black by its 0.12975 key"), CrackBlack.Color.B, 0.00913406f, 2.0e-3f);
        TestEqual(TEXT("...with alpha still most of the way up"), CrackBlack.Color.A, 0.87025f, 2.0e-3f);
    }

    // ---- Ring holds its colour and leaves entirely through the dissolve ----
    {
        const auto Open = Evaluate(0.05f, kSlotRing);
        const auto End  = Evaluate(0.35f, kSlotRing);

        TestEqual(TEXT("Ring draws its own paint"), Open.VisTag, kVisRing);
        TestEqual(TEXT("Ring's alpha is its authored 0.608 at spawn"), Open.Color.A, 0.608f, kTolerance);
        TestEqual(TEXT("...and STILL 0.608 at death — it has no colour animation at all"),
            End.Color.A, 0.608f, kTolerance);
        TestEqual(TEXT("Ring's dissolve opens at 0"),  Open.Dynamic.X,  0.0f, kTolerance);
        TestEqual(TEXT("...and reaches -1 at death"),  End.Dynamic.X,  -1.0f, kTolerance);
        TestTrue(TEXT("Ring is gone past its 0.35 s"), Is_Hidden(Evaluate(0.36f, kSlotRing)));
    }

    // ---- The three meshes ----
    {
        // Spikes fly point-first and FLATTEN: X and Y collapse while Z has no third key.
        const auto SpikePeak = Evaluate(0.15f * 0.2f, kSlotSpikes);
        TestEqual(TEXT("a spike draws through the velocity-pointed pyramid renderer"),
            SpikePeak.VisTag, kVisSpike);
        TestTrue(TEXT("a spike writes no sprite quad"), SpikePeak.Size.IsNearlyZero());
        TestTrue(TEXT("a spike's orientation is a unit quaternion"), SpikePeak.Orientation.IsNormalized());
        TestEqual(TEXT("a spike's cross-section is the source's pinned tenth at its peak"),
            SpikePeak.Scale.X, 0.1f, kTolerance);
        TestEqual(TEXT("a spike holds its violet — it carries no Color module"),
            SpikePeak.Color.R, 0.871367f, kTolerance);

        const auto SpikeEnd = Evaluate(0.15f, kSlotSpikes);
        TestEqual(TEXT("a spike's X collapses to zero by death"), SpikeEnd.Scale.X, 0.0f, kTolerance);
        TestTrue(*FString::Printf(TEXT("a spike's LENGTH holds at death (%f) — its Z curve has no third key"),
            SpikeEnd.Scale.Z), SpikeEnd.Scale.Z > 0.35f);
        TestEqual(TEXT("...and its violet is unchanged there too"), SpikeEnd.Color.R, 0.871367f, kTolerance);

        // Spike01 never moves: its Cone Location is DISABLED, so all five sit at the origin.
        auto Spike01Moved = 0;
        for (auto Point = 0; Point < 5; ++Point)
        {
            const auto Out = Evaluate(0.1f, kSlotSpike01 + Point);
            if (NOT Out.Position.IsNearlyZero())
            { ++Spike01Moved; }
        }
        TestEqual(TEXT("all five Spike01 meshes sit at the origin — their spawn shape is disabled"),
            Spike01Moved, 0);

        const auto Spike01End = Evaluate(0.15f, kSlotSpike01);
        TestEqual(TEXT("Spike01's X collapses to zero by death"), Spike01End.Scale.X, 0.0f, kTolerance);
        TestTrue(*FString::Printf(TEXT("Spike01's Z HOLDS at 1.5x (%f) — its Z curve has no third key"),
            Spike01End.Scale.Z), Spike01End.Scale.Z > 0.7f);
        TestTrue(TEXT("Spike01's orientation is a unit quaternion"), Spike01End.Orientation.IsNormalized());

        // LightningStrip is static too — its Sphere Location is disabled and it adds no velocity — and its
        // Color.Scale Alpha is 0.3 (the [P2-D2] class), pinned at the peak of its own alpha curve.
        auto StripPeak = 0.0f;
        for (auto Step = 0; Step <= 2000; ++Step)
        {
            const auto Out = Evaluate(0.3f * float(Step) / 2000.0f, kSlotStrip);
            if (Out.VisTag == kVisStrip)
            { StripPeak = FMath::Max(StripPeak, Out.Color.A); }
        }
        TestTrue(*FString::Printf(TEXT("LightningStrip's alpha peaks at THREE TENTHS (observed %f)"),
            StripPeak), StripPeak > 0.295f && StripPeak <= 0.3f + kTolerance);

        const auto Strip = Evaluate(0.1f, kSlotStrip);
        TestTrue(TEXT("a strip sits at the origin — its spawn shape is disabled"),
            Strip.Position.IsNearlyZero());
        TestTrue(TEXT("a strip's orientation is a unit quaternion"), Strip.Orientation.IsNormalized());
        TestEqual(TEXT("a strip holds its single-key blue"), Strip.Color.B, 1.0f, kTolerance);
        TestTrue(TEXT("a strip writes no sprite quad"), Strip.Size.IsNearlyZero());

        // Three strips, three DIFFERENT random orientations.
        auto Orientations = TSet<uint32>{};
        for (auto Point = 0; Point < 3; ++Point)
        {
            const auto Out = Evaluate(0.1f, kSlotStrip + Point);
            Orientations.Add(GetTypeHash(FString::Printf(TEXT("%.5f/%.5f/%.5f"),
                Out.Orientation.X, Out.Orientation.Y, Out.Orientation.Z)));
        }
        TestEqual(TEXT("each strip carries its own random Orientation Vector"), Orientations.Num(), 3);

        // The bubble OVERSHOOTS to 1.5x at a fifth of its life and settles back to 1.
        const auto BubblePeak = Evaluate(0.15f * 0.2f, kSlotBubble);
        const auto BubbleEnd  = Evaluate(0.15f, kSlotBubble);
        TestEqual(TEXT("the bubble draws through the sphere carrier"), BubblePeak.VisTag, kVisBubble);
        TestEqual(TEXT("the bubble overshoots to 1.5x at a fifth of its life"),
            BubblePeak.Scale.X, 1.5f, 2.0e-3f);
        TestEqual(TEXT("...and settles back to 1 by death"), BubbleEnd.Scale.X, 1.0f, kTolerance);
        TestTrue(TEXT("the bubble is gone past 0.15 s"), Is_Hidden(Evaluate(0.16f, kSlotBubble)));
    }

    // ---- Sparkles_Stretched: the streak layer, whose three size modules multiply ----
    {
        const auto Streak = Evaluate(0.1f, kSlotStretched);
        TestEqual(TEXT("a streak draws the velocity-aligned quad"), Streak.VisTag, kVisPart04);
        TestTrue(*FString::Printf(TEXT("a streak is LONGER than it is wide (%f x %f)"),
            Streak.Size.X, Streak.Size.Y), Streak.Size.Y > Streak.Size.X);
        TestEqual(TEXT("a streak's alpha is a SINGLE key — it never fades"), Streak.Color.A, 1.0f, kTolerance);
        TestEqual(TEXT("...and it is still one at the end of life"),
            Evaluate(0.19f, kSlotStretched).Color.A, 1.0f, kTolerance);

        // The speed stretch is live: a fast streak is longer than a slow one at the same point in its life.
        auto FastLength = 0.0f;
        auto SlowLength = 1.0e9f;
        for (auto Repeat = 0; Repeat < 40; ++Repeat)
        {
            const auto Out = Evaluate(0.06f, kSlotStretched + Repeat * kBurst);

            if (Is_Hidden(Out))
            { continue; }

            FastLength = FMath::Max(FastLength, Out.Size.Y);
            SlowLength = FMath::Min(SlowLength, Out.Size.Y);
        }
        TestTrue(*FString::Printf(TEXT("Scale Sprite Size by Speed stretches the fast streaks (%f vs %f)"),
            FastLength, SlowLength), FastLength > SlowLength * 1.2f);
    }

    // ---- Flames: the only live `distortion` write in the cookbook, and a halved Color.Scale Alpha ----
    {
        const auto Flame = Evaluate(0.05f + 0.2f * 0.455177f, kSlotFlames01);
        TestEqual(TEXT("a flame draws the sub-UV sheet renderer"), Flame.VisTag, kVisFlames);
        TestEqual(TEXT("its distortion channel carries the source's 10"), Flame.Dynamic.Y, 10.0f, kTolerance);

        auto FlamePeak = 0.0f;
        for (auto Step = 0; Step <= 1200; ++Step)
        {
            const auto Out = Evaluate(0.05f + 0.8f * float(Step) / 1200.0f, kSlotFlames01);
            if (Out.VisTag == kVisFlames)
            { FlamePeak = FMath::Max(FlamePeak, Out.Color.A); }
        }
        TestTrue(*FString::Printf(TEXT("the flames' alpha peaks at a HALF (observed %f)"), FlamePeak),
            FlamePeak > 0.495f && FlamePeak <= 0.5f + kTolerance);

        // Flames_02 is the upward jet; Flames_01 pushes off the spawn shape. Compared on the same beat.
        auto JetUp    = 0;
        auto JetTotal = 0;
        for (auto Point = 0; Point < 10; ++Point)
        {
            const auto Out = Evaluate(0.12f, kSlotFlames02 + Point);

            if (Is_Hidden(Out))
            { continue; }

            ++JetTotal;
            if (Out.Velocity.Z > 0.0f && FMath::Abs(Out.Velocity.X) < 1.0e-3f)
            { ++JetUp; }
        }
        TestTrue(*FString::Printf(TEXT("Flames_02 is a straight upward jet (%d of %d)"), JetUp, JetTotal),
            JetTotal > 0 && JetUp == JetTotal);

        // The two emitters' colour tables differ only in their first key's time and one green tail value.
        const auto F01 = Evaluate(0.05f + 0.01f, kSlotFlames01);
        const auto F02 = Evaluate(0.05f + 0.01f, kSlotFlames02);
        TestEqual(TEXT("both flame layers open on the same warm red"), F01.Color.R, F02.Color.R, 5.0e-2f);
    }

    // ---- The arc pair, transcribed from NS_Lightning_Muzzle's byte-identical emitters ----
    {
        auto Ribbons = TMap<int32, int32>{};
        auto Tags    = TSet<int32>{};

        for (auto Local = 0; Local < kArcPoints; ++Local)
        {
            const auto Out = Evaluate_Ribbon(0.25f, Local);
            Ribbons.FindOrAdd(Out.MeshIndex) += 1;
            Tags.Add(Out.VisTag);
        }

        TestEqual(TEXT("the arc emitter carries exactly two ribbons"), Ribbons.Num(), 2);
        TestEqual(TEXT("LightningArc_01 is one burst point plus twelve solved ones"),
            Ribbons.FindRef(0), kArc1Count);
        TestEqual(TEXT("LightningArc_02 is five burst points plus twelve solved ones"),
            Ribbons.FindRef(1), kArc2Count);
        TestEqual(TEXT("every ribbon-bank particle reaches the arc renderer and nothing else"), Tags.Num(), 1);
        TestTrue(TEXT("the arc branch writes the arc VisTag"), Tags.Contains(kVisArc));

        auto FirstHalf = 0;
        auto Previous  = -1.0f;
        auto Monotone  = true;

        for (auto Point = 1; Point <= kArcRatePoint; ++Point)
        {
            const auto SpawnTime = Find_ArcSpawnTime(Point);

            if (SpawnTime <= Previous)
            { Monotone = false; }
            Previous = SpawnTime;

            if (SpawnTime <= 0.5f * kArcWindow)
            { ++FirstHalf; }
        }

        TestTrue(TEXT("the arc's solved release times are strictly increasing along the ribbon"), Monotone);
        // N(0.15) = 80*0.15 - (400/3)*0.15^2 = 9 of the 12. A uniform or averaged rate lands 6.
        TestEqual(TEXT("nine of the twelve arc points land in the first half of the 0.3 s window"),
            FirstHalf, 9);
        TestEqual(TEXT("the first solved arc point is released at 0.00632 s"),
            Find_ArcSpawnTime(1), 0.00632f, 2.0e-4f);
        TestEqual(TEXT("the last one is released at 0.23876 s"),
            Find_ArcSpawnTime(kArcRatePoint), 0.23876f, 2.0e-4f);

        // Arc_02 is the dimmer of the pair, and both are BENT off the barrel axis by the curl force.
        const auto Arc01 = Evaluate_Ribbon(0.05f, 0);
        const auto Arc02 = Evaluate_Ribbon(0.05f, kArc1Count);
        TestTrue(TEXT("Arc_02 is dimmer than Arc_01 on red — 0.135751 against 1.0"),
            Arc02.Color.R < Arc01.Color.R);
        TestEqual(TEXT("both arcs hold saturated blue"), Arc01.Color.B, 1.0f, kTolerance);

        auto Bent = 0;
        for (auto Local = 0; Local < kArcPoints; ++Local)
        {
            const auto Early = Evaluate_Ribbon(0.26f, Local);
            if (FMath::Abs(Early.Position.Y) > 1.0f || FMath::Abs(Early.Position.Z) > 1.0f)
            { ++Bent; }
        }
        TestTrue(*FString::Printf(TEXT("the curl force bends the arcs off the barrel axis (%d of %d points)"),
            Bent, kArcPoints), Bent > kArcPoints / 2);
    }

    // ---- No spawn rate on the row, so the emitter clock must be inert for this behavior ----
    {
        auto Moved = 0;

        for (auto Seed = 0; Seed < 400; ++Seed)
        {
            const auto Reference = Evaluate(0.12f, Seed, 0.0f);

            for (const auto EmitterAge : { 0.37f, 2.5f, 41.0f })
            {
                const auto Shifted = Evaluate(0.12f, Seed, EmitterAge);

                if (Reference.VisTag != Shifted.VisTag || Reference.Color != Shifted.Color
                    || Reference.Size != Shifted.Size || Reference.Position != Shifted.Position)
                { ++Moved; }
            }
        }

        TestEqual(TEXT("behavior 45 ignores the emitter clock — its row declares one population per emitter"),
            Moved, 0);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
