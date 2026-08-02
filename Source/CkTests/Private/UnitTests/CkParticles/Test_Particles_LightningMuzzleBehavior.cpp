// Behavior-math gate for CkParticles BehaviorId 39 (LightningMuzzle) — the Vefects NS_Lightning_Muzzle
// recreation, the cookbook's widest renderer spread (sprites, a flipbook, three meshes and a ribbon pair)
// and the port that closes the trail phase.
//
// Drives UCkParticles_DataInterface::Execute_Stage_CPU, the SAME CPU mirror a CPU sim runs, so it needs no
// Niagara system, no template asset, no RHI and no forked engine.
//
// Expected values are the SOURCE's own values as transcribed in
// CkFoundation/Source/CkParticles/Cookbook/NS_Lightning_Muzzle.md §2/§5.
//
// The load-bearing claims specific to this port:
//   - THE ARC SPAWN INVERSION. Each arc's source Spawn Rate falls 80 -> 0 across a 0.3 s window, and the
//     behavior places its twelve points at the times that rate would have released them. The source's own
//     integral says NINE of the twelve land in the first half of the window; a uniform spread lands six, so
//     the assertion catches an averaged rate;
//   - the arc pair is TWO ribbons on ONE renderer, split 13 / 17 by ribbon id;
//   - the bolt STROBE. Lightning's alpha runs on-off-on-off-on across one life; a fade simplification
//     destroys the whole read, so all five key values are pinned;
//   - Spikes FLATTEN rather than shrink: their mesh-scale Z curve has no third key, so it holds while X and
//     Y collapse to zero. The assertion is two-sided at t = 1;
//   - the beam's alpha is a SINGLE key, so it never fades — it leaves entirely through its dissolve ramp;
//   - LightningSpot's Color.Scale Alpha is 0.1, the [P2-D2] class again, pinned at its peak;
//   - the row declares no spawn rate, so behavior 39 must stay INDEPENDENT of the emitter clock.
//
// Cannot pass vacuously: behavior 39's VisTags are 175..184 and the pre-switch default is 0.

#include "Misc/AutomationTest.h"

#include "CkParticles/DataInterface/CkParticles_DataInterface.h"
#include "CkParticles/ScriptDefinition/CkParticles_ScriptDefinition_Naming.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_particles_lightning_muzzle
{
    constexpr auto kBehaviorId = 39;
    constexpr auto kTolerance  = 1.0e-4f;

    // Source facts (recipe §2/§6.1 against corpus v3). Loop Once / 2.0 s system; the longest ENABLED layer is
    // Sparkles at its resolved 0.6 s maximum.
    constexpr auto kLoop     = 2.0f;
    constexpr auto kLifetime = 0.6f;
    constexpr auto kBurst    = 24;  // the thirteen enabled sprite/mesh emitters' own counts

    constexpr auto kRowAssetName = TEXT("PS_CkParticles_Template_LightningMuzzle");

    constexpr auto kVisPart01    = 175;
    constexpr auto kVisPart02    = 176;
    constexpr auto kVisPart01Br  = 177;
    constexpr auto kVisPart04    = 178;
    constexpr auto kVisLightning = 179;
    constexpr auto kVisPart03Br  = 180;
    constexpr auto kVisSpike     = 181;
    constexpr auto kVisSpot      = 182;
    constexpr auto kVisBeam      = 183;
    constexpr auto kVisArc       = 184;

    // The arc ribbon: 1 + 12 for LightningArc_01, then 5 + 12 for LightningArc_02.
    constexpr auto kArcPoints    = 30;
    constexpr auto kArc1Count    = 13;
    constexpr auto kArc2Count    = 17;
    constexpr auto kArcWindow    = 0.3f;
    constexpr auto kArcRatePoint = 12;

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

    // The first loop age at which an arc point draws anything — its solved release time.
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
    FCkTest_Particles_LightningMuzzleBehavior,
    "CkTests.UnitTests.CkParticles.LightningMuzzleBehavior",
    kCkUnitTestFlags)

bool FCkTest_Particles_LightningMuzzleBehavior::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_lightning_muzzle;

    // ---- The cadence row, and the ribbon emitter it declares ----
    {
        TestEqual(TEXT("behavior 39 routes to the LightningMuzzle row"),
            ck::particles::Get_BehaviorTemplateSystemObjectPath(kBehaviorId),
            ck::particles::Get_LightningMuzzleTemplateSystemObjectPath());

        TestEqual(TEXT("behavior 39 binds no CkUsf look — all ten looks ride the row's renderers"),
            ck::particles::Get_BehaviorLookName(kBehaviorId), NAME_None);

        const auto* RowSpec = static_cast<const ck::particles::FCk_ParticlesTemplateSpec*>(nullptr);
        for (const auto& Spec : ck::particles::Get_TemplateSpecs())
        {
            if (FString(Spec.AssetName) == FString(kRowAssetName))
            { RowSpec = &Spec; break; }
        }

        if (TestNotNull(TEXT("the cadence table declares a PS_CkParticles_Template_LightningMuzzle row"), RowSpec))
        {
            TestEqual(TEXT("row loop duration is the system's Loop Once / 2.0 s"),
                RowSpec->LoopDuration, kLoop, kTolerance);
            TestEqual(TEXT("row particle lifetime is Sparkles' resolved 0.6 s maximum"),
                RowSpec->ParticleLifetime, kLifetime, kTolerance);
            TestEqual(TEXT("row burst is the thirteen enabled sprite/mesh emitters' counts"),
                RowSpec->BurstCount, kBurst);
            TestEqual(TEXT("the row declares NO spawn rate — the arcs' rate is inverted into their burst"),
                RowSpec->SpawnRate, 0.0f, kTolerance);

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
        }
    }

    // ---- The burst partition IS the source's per-emitter counts ----
    {
        auto Tags = TMap<int32, int32>{};
        for (auto Seed = 0; Seed < kBurst; ++Seed)
        { Tags.FindOrAdd(Evaluate(0.05f, Seed).VisTag) += 1; }

        TestEqual(TEXT("Part01 draws Glow_01 and Glow_03"),                  Tags.FindRef(kVisPart01),    2);
        TestEqual(TEXT("Part02 draws Glow_02 and both Flares"),              Tags.FindRef(kVisPart02),    3);
        TestEqual(TEXT("Part01_Bright draws the four Sparkles and Flare_04"),Tags.FindRef(kVisPart01Br),  5);
        TestEqual(TEXT("Sparkles_Stretched bursts three"),                   Tags.FindRef(kVisPart04),    3);
        TestEqual(TEXT("the bolt sheet bursts three"),                       Tags.FindRef(kVisLightning), 3);
        TestEqual(TEXT("Flare_03 bursts two"),                               Tags.FindRef(kVisPart03Br),  2);
        TestEqual(TEXT("Spikes bursts four"),                                Tags.FindRef(kVisSpike),     4);
        TestEqual(TEXT("LightningSpot is one plane"),                        Tags.FindRef(kVisSpot),      1);
        TestEqual(TEXT("LightningBeam is one plane"),                        Tags.FindRef(kVisBeam),      1);

        auto WideSpikes = 0;
        for (auto Seed = 0; Seed < kBurst * 500; ++Seed)
        {
            if (Evaluate(0.05f, Seed).VisTag == kVisSpike)
            { ++WideSpikes; }
        }
        TestEqual(TEXT("the partition holds across 500 moduli"), WideSpikes, 4 * 500);
    }

    // ---- THE ARC SPAWN INVERSION: a falling rate, not an averaged one ----
    {
        // Arc_01's twelve solved points are local seeds 1..12; Arc_02's are 18..29.
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
        // The source's own integral: N(0.15) = 80*0.15 - (400/3)*0.15^2 = 9 of the 12. A uniform spread
        // lands 6, and an averaged constant rate lands 6 — this is the assertion that tells them apart.
        TestEqual(TEXT("nine of the twelve arc points land in the first half of the 0.3 s window"),
            FirstHalf, 9);

        // Both ends of the solved run, corpus-derived from the inversion.
        TestEqual(TEXT("the first solved arc point is released at 0.00632 s"),
            Find_ArcSpawnTime(1), 0.00632f, 2.0e-4f);
        TestEqual(TEXT("the last one is released at 0.23876 s"),
            Find_ArcSpawnTime(kArcRatePoint), 0.23876f, 2.0e-4f);
    }

    // ---- Two ribbons on one renderer, split by the source's own burst counts ----
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

        auto MainReachedArc = false;
        for (auto Seed = 0; Seed < 5000; ++Seed)
        {
            if (Evaluate(0.25f, Seed).VisTag == kVisArc)
            { MainReachedArc = true; }
        }
        TestFalse(TEXT("no main-bank particle reaches the arc renderer"), MainReachedArc);

        // Arc_02 is the dimmer of the pair — its Color.Scale Alpha is a half against Arc_01's one, and its
        // red opens an eighth as bright. Sampled on both, at the same point in their own lives.
        const auto Arc01 = Evaluate_Ribbon(0.05f, 0);
        const auto Arc02 = Evaluate_Ribbon(0.05f, kArc1Count);
        TestEqual(TEXT("Arc_01's burst point draws ribbon id 0"), Arc01.MeshIndex, 0);
        TestEqual(TEXT("Arc_02's burst point draws ribbon id 1"), Arc02.MeshIndex, 1);
        TestTrue(TEXT("Arc_02 is dimmer than Arc_01 on red — 0.135751 against 1.0"),
            Arc02.Color.R < Arc01.Color.R);
        TestEqual(TEXT("both arcs hold saturated blue"), Arc01.Color.B, 1.0f, kTolerance);

        // The arcs are BENT: the curl force must move them off the straight launch line.
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

    // ---- The bolt STROBE: on, off, on, off, on across one life ----
    {
        constexpr auto BoltSeed = 12;

        TestEqual(TEXT("the bolt slot draws the sub-UV sheet renderer"),
            Evaluate(0.0f, BoltSeed).VisTag, kVisLightning);

        // The alpha keys sit at fractions of the particle's own life, which is per-Seed, so the sweep finds
        // the turning points rather than sampling by absolute age. It runs to the layer's longest possible
        // life and stops at the first hidden sample, so the dead tail is never read as a trough.
        auto Peaks    = 0;
        auto Troughs  = 0;
        auto Previous = -1.0f;
        auto Rising   = true;

        for (auto Step = 0; Step <= 500; ++Step)
        {
            const auto Out = Evaluate(0.5f * float(Step) / 500.0f, BoltSeed);

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

        TestTrue(*FString::Printf(TEXT("the bolt alpha strobes — %d peaks and %d troughs over one life"),
            Peaks, Troughs), Peaks >= 2 && Troughs >= 2);

        // Corpus-derived at BOTH ends of the colour ramp.
        const auto Open = Evaluate(0.0f, BoltSeed);
        TestEqual(TEXT("the bolt opens white-hot on red"), Open.Color.R, 1.0f, kTolerance);
        TestEqual(TEXT("the bolt opens at its 0.745404 green key"), Open.Color.G, 0.745404f, kTolerance);
        TestEqual(TEXT("the bolt's dissolve opens at 1"), Open.Dynamic.X, 1.0f, kTolerance);

        // Every one of the four sheet frames is reached, and the run starts at 0 (Linear mode, not Random).
        auto Frames = TSet<int32>{};
        for (auto Step = 0; Step <= 400; ++Step)
        {
            const auto Out = Evaluate(0.5f * float(Step) / 400.0f, BoltSeed);
            Frames.Add(FMath::RoundToInt(Out.SubImageIndex));
        }
        TestEqual(TEXT("the bolt walks all four frames of its 2x2 sheet"), Frames.Num(), 4);
        TestEqual(TEXT("the run starts on frame 0 — Sub UV Animation is LINEAR, not Random"),
            FMath::RoundToInt(Open.SubImageIndex), 0);
    }

    // ---- Spikes: they FLATTEN, they do not shrink ----
    {
        constexpr auto SpikeSeed = 18;

        const auto Peak = Evaluate(0.15f * 0.2f, SpikeSeed);
        TestEqual(TEXT("a spike draws through the row's pyramid mesh"), Peak.VisTag, kVisSpike);
        TestTrue(TEXT("a spike writes no sprite quad"), Peak.Size.IsNearlyZero());
        TestTrue(TEXT("a spike's orientation is a unit quaternion"), Peak.Orientation.IsNormalized());
        TestEqual(TEXT("a spike's cross-section is the source's pinned tenth at its peak"),
            Peak.Scale.X, 0.1f, kTolerance);

        // At the end of life X and Y have collapsed but Z has NOT — its curve has no third key.
        const auto End = Evaluate(0.15f, SpikeSeed);
        TestEqual(TEXT("a spike's X collapses to zero by death"), End.Scale.X, 0.0f, kTolerance);
        TestEqual(TEXT("a spike's Y collapses to zero by death"), End.Scale.Y, 0.0f, kTolerance);
        TestTrue(*FString::Printf(TEXT("a spike's LENGTH holds at death (%f) — its Z curve has no third key"),
            End.Scale.Z), End.Scale.Z > 0.35f);

        // The colour never moves: this emitter carries no Color module at all.
        TestEqual(TEXT("a spike holds its violet at the start"), Peak.Color.R, 0.871367f, kTolerance);
        TestEqual(TEXT("...and at the end — no Color module runs on it"), End.Color.R, 0.871367f, kTolerance);
        TestEqual(TEXT("...including its authored half alpha"), End.Color.A, 0.5f, kTolerance);

        TestTrue(TEXT("a spike is gone past its 0.15 s"), Is_Hidden(Evaluate(0.16f, SpikeSeed)));
    }

    // ---- The two plane meshes ----
    {
        constexpr auto SpotSeed = 22;
        constexpr auto BeamSeed = 23;

        // LightningSpot's Color.Scale Alpha is a TENTH — the same class of defect Ring carries in NS_BuffCast.
        auto SpotPeak = 0.0f;
        for (auto Step = 0; Step <= 2000; ++Step)
        {
            const auto Out = Evaluate(0.3f * float(Step) / 2000.0f, SpotSeed);
            if (Out.VisTag == kVisSpot)
            { SpotPeak = FMath::Max(SpotPeak, Out.Color.A); }
        }
        TestTrue(*FString::Printf(TEXT("LightningSpot's alpha peaks at a TENTH (observed %f)"), SpotPeak),
            SpotPeak > 0.095f && SpotPeak <= 0.1f + kTolerance);

        const auto Spot = Evaluate(0.15f, SpotSeed);
        TestTrue(TEXT("LightningSpot's orientation is a unit quaternion"), Spot.Orientation.IsNormalized());
        TestTrue(TEXT("LightningSpot writes no sprite quad"), Spot.Size.IsNearlyZero());
        TestEqual(TEXT("LightningSpot holds its single-key blue"), Spot.Color.B, 1.0f, kTolerance);

        // The beam's alpha is a SINGLE key: it never fades, at either end of its life.
        const auto BeamOpen = Evaluate(0.0f, BeamSeed);
        const auto BeamEnd  = Evaluate(0.3f, BeamSeed);
        TestEqual(TEXT("the beam's alpha is 1 at spawn"), BeamOpen.Color.A, 1.0f, kTolerance);
        TestEqual(TEXT("the beam's alpha is STILL 1 at death — it leaves by dissolve, not by fading"),
            BeamEnd.Color.A, 1.0f, kTolerance);
        TestEqual(TEXT("the beam's dissolve runs 1 -> -1 across its life"),
            BeamOpen.Dynamic.X, 1.0f, kTolerance);
        TestEqual(TEXT("...reaching -1 at death"), BeamEnd.Dynamic.X, -1.0f, kTolerance);
        TestEqual(TEXT("the beam sits 30 units back down the barrel"), BeamOpen.Position.X, -30.0f, 1.0e-2f);
        TestEqual(TEXT("the beam's X scale HOLDS at death — its curve has no third key"),
            BeamEnd.Scale.X, 2.5f, kTolerance);
        TestEqual(TEXT("the beam draws through its own plane renderer"), BeamEnd.VisTag, kVisBeam);

        TestTrue(TEXT("both planes are gone past their 0.3 s"),
            Is_Hidden(Evaluate(0.31f, SpotSeed)) && Is_Hidden(Evaluate(0.31f, BeamSeed)));
    }

    // ---- Glow_01: the deep-blue shell that opens the flash, at both ends of its fade ----
    {
        constexpr auto GlowSeed = 0;

        const auto Open = Evaluate(0.0f, GlowSeed);
        TestEqual(TEXT("Glow_01 opens at full alpha"), Open.Color.A, 1.0f, kTolerance);
        TestEqual(TEXT("Glow_01 opens at half its authored size"), Open.Size.X, 275.0f, kTolerance);
        TestEqual(TEXT("Glow_01 holds the deep blue of the whole lightning palette"),
            Open.Color.B, 1.0f, kTolerance);

        const auto Half = Evaluate(0.2f, GlowSeed);
        TestEqual(TEXT("Glow_01's alpha is exactly half-way down at half life"), Half.Color.A, 0.5f, kTolerance);
        TestEqual(TEXT("Glow_01 is at its full 550 units by then"), Half.Size.X, 550.0f, kTolerance);

        TestTrue(TEXT("Glow_01 is gone past its 0.4 s"), Is_Hidden(Evaluate(0.41f, GlowSeed)));
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

        TestEqual(TEXT("behavior 39 ignores the emitter clock — its row declares one population per emitter"),
            Moved, 0);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
