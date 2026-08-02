// Behavior-math gate for CkParticles BehaviorId 46 (Dash) — the Vefects NS_Dash recreation, and the port
// that completes the pack's Skills roster.
//
// Drives UCkParticles_DataInterface::Execute_Stage_CPU, the SAME CPU mirror a CPU sim runs, so it needs no
// Niagara system, no template asset, no RHI and no forked engine.
//
// Expected values are the SOURCE's own values as transcribed in
// CkFoundation/Source/CkParticles/Cookbook/NS_Dash.md §2/§5.
//
// The load-bearing claims specific to this port:
//   - the SPAWN-PHASE split. NS_Dash is the pack's only system with a `Life Cycle Mode = Self` emitter:
//     Add_Lines bursts 13 AND streams 50/s inside its own 0.3 s window while the three wind layers burst
//     once off the system's clock. A particle born at phase 0 takes the 19-slot burst partition, one born
//     mid-loop is always a line, and one born past 0.3 s never existed;
//   - the two BEATS. The tube and the speed cone fire at 50 ms and the smokes at 100 ms; each runs its
//     curves on (age - delay), and the lines carry no delay at all;
//   - the wind envelope. Three layers share one in-hold-out alpha, and the cone's hold is HALF as long —
//     the only thing separating its envelope from the other two, and a reading that shared one curve
//     across all three would be invisible without pinning the shorter hold;
//   - the tube's TWO-AXIS scale: X and Y hold at 2x past t = 0.2 while Z keeps growing to 5x, which is
//     what stretches the cylinder lengthwise rather than inflating it;
//   - CLOSED-FORM DRAG. Add_Lines is the cookbook's only linear-drag layer, and its position and velocity
//     must be functions of age alone — so the same evaluation at a different DeltaTime must agree to the
//     last float, which a step integration could not do;
//   - the cone velocity's 10 degree aperture, whose shaping inputs are [inferred] (recipe §13.4) but whose
//     APERTURE is not: every launch direction must sit within five degrees of -X.
//
// The partition census reads each slot while it is ALIVE, swept across the loop: a layer outside its own
// beat leaves through the early Hide() before its branch assigns VisTag, so a single-instant read buckets
// every beat-carrying layer at the switch's pre-branch default of 0 (the batch-H lesson).
//
// Cannot pass vacuously: behavior 46's VisTags are 242..245 and the pre-switch default is 0.

#include "Misc/AutomationTest.h"

#include "CkParticles/DataInterface/CkParticles_DataInterface.h"
#include "CkParticles/ScriptDefinition/CkParticles_ScriptDefinition_Naming.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_particles_dash
{
    constexpr auto kBehaviorId = 46;
    constexpr auto kTolerance  = 1.0e-4f;

    // Source facts (recipe §2/§6.1 against corpus v3). Loop Once / 2.0 s system; the longest layer is the
    // wind tube's 1.5 s off its own 0.05 s beat.
    constexpr auto kLoop      = 2.0f;
    constexpr auto kLifetime  = 1.55f;
    constexpr auto kBurst     = 19;    // 1 + 4 + 1 + 13
    constexpr auto kSpawnRate = 50.0f; // Add_Lines' own Spawn Rate — the system's only one
    constexpr auto kWindow    = 0.3f;  // Add_Lines' own Self/Once loop duration

    constexpr auto kDelayWind   = 0.05f;
    constexpr auto kDelaySmokes = 0.1f;

    constexpr auto kRowAssetName = TEXT("PS_CkParticles_Template_Dash");

    constexpr auto kVisTube   = 242;
    constexpr auto kVisSmokes = 243;
    constexpr auto kVisCone   = 244;
    constexpr auto kVisLines  = 245;

    constexpr auto kLayerTube   = 0;
    constexpr auto kLayerSmokes = 1;
    constexpr auto kLayerCone   = 2;
    constexpr auto kLayerLines  = 3;

    // Per-layer life and beat, straight off §2's emitter table. The lines' life is a RANGE.
    constexpr auto kLifeTube   = 1.5f;
    constexpr auto kLifeSmokes = 1.0f;
    constexpr auto kLifeCone   = 0.6f;
    constexpr auto kLifeLineLo = 0.8f;
    constexpr auto kLifeLineHi = 1.0f;

    // Add Velocity in Cone: a 10 degree APERTURE, so five degrees off the -X axis.
    constexpr auto kConeHalfCos = 0.99619469809f;
    constexpr auto kSpeedLo     = 350.0f;
    constexpr auto kSpeedHi     = 750.0f;
    constexpr auto kConeFalloff = 0.333f;

    // Add_Lines' Random Range Linear Color, as exported: the minimum's R and G sit ABOVE the maximum's.
    constexpr auto kLineRMin = 0.726575f;
    constexpr auto kLineRMax = 0.737095f;
    constexpr auto kLineGMin = 0.816055f;
    constexpr auto kLineGMax = 0.852379f;

    auto Evaluate(float InAge, int32 InSeed, float InSpawnPhase, float InDeltaTime) -> FCk_Particles_StageResult
    {
        return UCkParticles_DataInterface::Execute_Stage_CPU(
            kBehaviorId, InDeltaTime, InAge, kLifetime,
            FVector3f::ZeroVector, FVector3f::ZeroVector, InSeed, InAge + InSpawnPhase);
    }

    auto Evaluate(float InAge, int32 InSeed, float InSpawnPhase) -> FCk_Particles_StageResult
    {
        return Evaluate(InAge, InSeed, InSpawnPhase, 1.0f / 60.0f);
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

    // Burst slot -> layer. The RANGES are the source's own per-emitter burst counts.
    auto Layer_ForBurstSlot(int32 InSeed) -> int32
    {
        const auto S = ((InSeed % kBurst) + kBurst) % kBurst;

        if (S == 0) { return kLayerTube; }
        if (S < 5)  { return kLayerSmokes; }
        if (S == 5) { return kLayerCone; }
        return kLayerLines;
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

    // ---- Reading the partition while each slot is ALIVE ---------------------------------------------------
    //
    // Past the longest layer's death: the tube's 0.05 s beat plus its 1.5 s life. The step is finer than the
    // shortest beat in the system (0.05 s), so no layer can be missed.
    constexpr auto kCensusSpan  = 1.55f;
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
            const auto Out = Evaluate_Burst(kCensusSpan * float(Step) / float(kCensusSteps), InSeed);
            if (Is_Hidden(Out))
            { continue; }

            if (Result.Tag == INDEX_NONE)      { Result.Tag = Out.VisTag; }
            else if (Result.Tag != Out.VisTag) { Result.Consistent = false; }
        }
        return Result;
    }

    // The last age at which a slot still draws — the layer's own resolved lifetime plus its beat.
    auto Get_LastLiveAge(int32 InSeed, float InSpan, int32 InSteps) -> float
    {
        auto Last = -1.0f;

        for (auto Step = 0; Step <= InSteps; ++Step)
        {
            const auto Age = InSpan * float(Step) / float(InSteps);
            if (NOT Is_Hidden(Evaluate_Burst(Age, InSeed)))
            { Last = Age; }
        }
        return Last;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Particles_DashBehavior,
    "CkTests.UnitTests.CkParticles.DashBehavior",
    kCkUnitTestFlags)

bool FCkTest_Particles_DashBehavior::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_dash;

    // ---- The cadence row ----
    {
        TestEqual(TEXT("behavior 46 routes to the Dash row"),
            ck::particles::Get_BehaviorTemplateSystemObjectPath(kBehaviorId),
            ck::particles::Get_DashTemplateSystemObjectPath());

        TestEqual(TEXT("behavior 46 binds no CkUsf look — all four of its looks ride the row's renderers"),
            ck::particles::Get_BehaviorLookName(kBehaviorId), NAME_None);

        const auto* RowSpec = static_cast<const ck::particles::FCk_ParticlesTemplateSpec*>(nullptr);
        for (const auto& Spec : ck::particles::Get_TemplateSpecs())
        {
            if (FString(Spec.AssetName) == FString(kRowAssetName))
            { RowSpec = &Spec; break; }
        }

        if (TestNotNull(TEXT("the cadence table declares a PS_CkParticles_Template_Dash row"), RowSpec))
        {
            TestEqual(TEXT("row loop duration matches the source SYSTEM's Loop Once 2.0 s"),
                RowSpec->LoopDuration, kLoop, kTolerance);
            TestEqual(TEXT("row particle lifetime is the tube's 0.05 s beat plus its 1.5 s life"),
                RowSpec->ParticleLifetime, kLifetime, kTolerance);
            TestEqual(TEXT("row burst is the four emitters' own counts"), RowSpec->BurstCount, kBurst);
            TestEqual(TEXT("row spawn rate is Add_Lines' own Spawn Rate"),
                RowSpec->SpawnRate, kSpawnRate, kTolerance);

            TestFalse(TEXT("the row declares no ribbon emitter — the source has no ribbon renderer"),
                RowSpec->RibbonEmitter.Get_IsDeclared());

            TestEqual(TEXT("the row declares one renderer per source emitter"),
                RowSpec->RendererOverrides.Num(), 4);

            auto MeshRows   = 0;
            auto SheetRows  = 0;
            auto VelRows    = 0;
            auto Carriers   = TArray<FString>{};
            auto Looks      = TArray<FString>{};
            for (const auto& Renderer : RowSpec->RendererOverrides)
            {
                Looks.Add(FString(Renderer.LookName));

                if (Renderer.Kind == ck::particles::ECk_ParticlesRenderer_Kind::Mesh)
                {
                    ++MeshRows;
                    Carriers.Add(FString(Renderer.MeshName));
                }
                if (Renderer.Kind == ck::particles::ECk_ParticlesRenderer_Kind::VelocityAlignedSprite)
                { ++VelRows; }
                if (Renderer.SubImageSize == FIntPoint(2, 2))
                {
                    ++SheetRows;
                    TestEqual(TEXT("the sub-UV renderer is CAMERA-facing, as the source's smoke quads are"),
                        static_cast<int32>(Renderer.Kind),
                        static_cast<int32>(ck::particles::ECk_ParticlesRenderer_Kind::CameraFacingSprite));
                }
            }

            TestEqual(TEXT("two of the four renderers are meshes"), MeshRows, 2);
            TestEqual(TEXT("one is the velocity-aligned speed-line quad"), VelRows, 1);
            TestEqual(TEXT("exactly one renderer declares a flipbook"), SheetRows, 1);

            TestTrue(TEXT("the tube reuses the Cylinder carrier NS_Arrow_Cast already generated"),
                Carriers.Contains(TEXT("Cylinder")));
            TestTrue(TEXT("the speed cone takes this port's own Cone carrier"),
                Carriers.Contains(TEXT("Cone")));

            // Three of the four looks are reused instances; WindDisAdd03 is the port's only new one.
            TestTrue(TEXT("the tube reuses WindDisAdd02Mesh"),  Looks.Contains(TEXT("WindDisAdd02Mesh")));
            TestTrue(TEXT("the smokes reuse WindDisAdd01"),     Looks.Contains(TEXT("WindDisAdd01")));
            TestTrue(TEXT("the speed lines reuse PartDisAdd02"),Looks.Contains(TEXT("PartDisAdd02")));
            TestTrue(TEXT("the speed cone takes the new WindDisAdd03"), Looks.Contains(TEXT("WindDisAdd03")));
        }

        TestTrue(TEXT("the roster VisTag maximum covers the Dash row's renderers"),
            ck::particles::Get_RosterVisTag_Max() >= kVisLines);
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

        TestEqual(TEXT("every one of the 19 burst slots draws at some point in the loop"), NeverDrawn, 0);
        TestEqual(TEXT("...and each slot keeps ONE renderer for its whole life"), Inconsistent, 0);

        TestEqual(TEXT("Wind_01 is one tube"),          Tags.FindRef(kVisTube),    1);
        TestEqual(TEXT("Wind_Smokes bursts four"),      Tags.FindRef(kVisSmokes),  4);
        TestEqual(TEXT("Wind_Speed is one cone"),       Tags.FindRef(kVisCone),    1);
        TestEqual(TEXT("Add_Lines bursts thirteen"),    Tags.FindRef(kVisLines),  13);

        // The modulus holds beyond one period.
        for (auto Seed = kBurst; Seed < kBurst * 4; ++Seed)
        {
            const auto Live = Get_LiveVisTag(Seed);
            const auto Expected = Layer_ForBurstSlot(Seed) == kLayerTube   ? kVisTube
                                : Layer_ForBurstSlot(Seed) == kLayerSmokes ? kVisSmokes
                                : Layer_ForBurstSlot(Seed) == kLayerCone   ? kVisCone
                                                                           : kVisLines;

            TestEqual(*FString::Printf(TEXT("burst seed %d keeps its slot's renderer past one period"), Seed),
                Live.Tag, Expected);
        }
    }

    // ---- The spawn-phase split, asserted against its own opposite ----
    // One Seed, three spawn phases: at 0 it takes the burst partition, mid-window it is always a line
    // (Add_Lines carries the system's only Spawn Rate), and past 0.3 s it does not exist.
    {
        auto RateIsAlwaysALine = 0;
        auto HiddenPastWindow  = 0;
        auto BurstNotALine     = 0;
        auto Sampled           = 0;

        for (auto Seed = 0; Seed < 2000; ++Seed)
        {
            const auto AsRate = Evaluate(0.02f, Seed, kWindow * 0.5f);
            const auto AsLate = Evaluate(0.02f, Seed, kWindow + 0.05f);

            if (AsRate.VisTag == kVisLines)
            { ++RateIsAlwaysALine; }

            if (Is_Hidden(AsLate))
            { ++HiddenPastWindow; }

            // A burst slot that is NOT a line proves the two paths really do differ for the same seed.
            if (Layer_ForBurstSlot(Seed) != kLayerLines)
            { ++BurstNotALine; }

            ++Sampled;
        }

        TestEqual(TEXT("every streamed particle is one of Add_Lines' speed lines"),
            RateIsAlwaysALine, Sampled);
        TestEqual(TEXT("every particle born past Add_Lines' 0.3 s window is hidden"),
            HiddenPastWindow, Sampled);
        TestTrue(TEXT("the burst path is reachable and resolves to non-line layers too"),
            BurstNotALine > 0);

        // The wind layers exist ONLY on the burst path: a seed whose burst slot is the tube still streams
        // as a line, which is the composition's whole point.
        const auto TubeSeed = Get_SeedsForBurstLayer(kLayerTube, 1)[0];
        TestEqual(TEXT("the tube slot's seed draws the tube when it bursts"),
            Evaluate_Burst(kDelayWind + 0.1f, TubeSeed).VisTag, kVisTube);
        TestEqual(TEXT("...and a line when it streams"),
            Evaluate(0.02f, TubeSeed, 0.15f).VisTag, kVisLines);
    }

    // ---- The two beats ----
    {
        for (const auto Seed : Get_SeedsForBurstLayer(kLayerTube, 3))
        {
            TestTrue(TEXT("the wind tube is hidden before its 50 ms beat"),
                Is_Hidden(Evaluate_Burst(kDelayWind - 0.001f, Seed)));
            TestFalse(TEXT("...and alive just after it"),
                Is_Hidden(Evaluate_Burst(kDelayWind + 0.01f, Seed)));
        }

        for (const auto Seed : Get_SeedsForBurstLayer(kLayerCone, 3))
        {
            TestTrue(TEXT("the speed cone is hidden before its 50 ms beat"),
                Is_Hidden(Evaluate_Burst(kDelayWind - 0.001f, Seed)));
        }

        for (const auto Seed : Get_SeedsForBurstLayer(kLayerSmokes, 4))
        {
            TestTrue(TEXT("the smokes are hidden before their 100 ms beat"),
                Is_Hidden(Evaluate_Burst(kDelaySmokes - 0.001f, Seed)));
            TestFalse(TEXT("...and alive just after it"),
                Is_Hidden(Evaluate_Burst(kDelaySmokes + 0.01f, Seed)));
        }

        for (const auto Seed : Get_SeedsForBurstLayer(kLayerLines, 6))
        {
            TestFalse(TEXT("a burst speed line carries no delay at all"),
                Is_Hidden(Evaluate_Burst(0.001f, Seed)));
        }
    }

    // ---- Wind_01: the tube stretches lengthwise rather than inflating ----
    {
        const auto Seed = Get_SeedsForBurstLayer(kLayerTube, 1)[0];

        // t = 0.2, where the round cross-section reaches its 2x hold: Mesh Uniform Scale 0.3 x 2.
        const auto AtKnot = Evaluate_Burst(kDelayWind + kLifeTube * 0.2f, Seed);
        TestEqual(TEXT("the tube's cross-section reaches 0.3 x 2 at t = 0.2"),
            AtKnot.Scale.X, 0.6f, kTolerance);
        TestEqual(TEXT("...and stays round"), AtKnot.Scale.Y, AtKnot.Scale.X, kTolerance);

        // Z at the same instant: the renderer's own 5x times the 0.5 -> 3 -> 5 curve at t = 0.2.
        TestEqual(TEXT("the tube's length at t = 0.2 is the source curve times the renderer's 5x"),
            AtKnot.Scale.Z, 3.25f, kTolerance);

        const auto Late = Evaluate_Burst(kDelayWind + kLifeTube * 0.9f, Seed);
        TestEqual(TEXT("the cross-section HOLDS at 2x past t = 0.2"), Late.Scale.X, 0.6f, kTolerance);
        TestTrue(TEXT("...while the length keeps growing"), Late.Scale.Z > AtKnot.Scale.Z + 1.0f);

        // Colour is a flat near-black blue under the shared envelope; the hold plateau is exactly 0.3.
        TestEqual(TEXT("the tube's red channel is the source constant"),   AtKnot.Color.R, 0.0742136f, kTolerance);
        TestEqual(TEXT("the tube's green channel is the source constant"), AtKnot.Color.G, 0.0886556f, kTolerance);
        TestEqual(TEXT("the tube's blue channel is the source constant"),  AtKnot.Color.B, 0.111932f,  kTolerance);

        const auto MidHold = Evaluate_Burst(kDelayWind + kLifeTube * 0.5f, Seed);
        TestEqual(TEXT("the envelope plateaus at the layer's Scale Alpha of 0.3"),
            MidHold.Color.A, 0.3f, kTolerance);

        TestTrue(TEXT("the envelope opens from zero"),
            Evaluate_Burst(kDelayWind + 0.0005f, Seed).Color.A < 0.01f);
        TestTrue(TEXT("...and closes back to zero"),
            Evaluate_Burst(kDelayWind + kLifeTube * 0.999f, Seed).Color.A < 0.01f);

        // Dissolve slides -0.2 -> -1 across the life.
        TestEqual(TEXT("the tube's dissolve is the source's two-key slide"),
            AtKnot.Dynamic.X, -0.36f, kTolerance);

        // It travels -X, and it SPINS: two ages, two different orientations.
        TestTrue(TEXT("the tube travels -X"), Late.Position.X < 0.0f && Late.Velocity.X < 0.0f);

        const auto Early = Evaluate_Burst(kDelayWind + 0.2f, Seed);
        TestTrue(TEXT("the tube's orientation advances with age"),
            NOT FMath::IsNearlyEqual(Early.Orientation.X, Late.Orientation.X, 1.0e-3f)
            || NOT FMath::IsNearlyEqual(Early.Orientation.W, Late.Orientation.W, 1.0e-3f));

        TestEqual(TEXT("the tube draws no sprite"), Early.Size.X, 0.0f, kTolerance);
    }

    // ---- Wind_Speed: the speed cone never moves, and its hold is HALF the wind's ----
    {
        const auto Seed = Get_SeedsForBurstLayer(kLayerCone, 1)[0];

        for (auto Step = 0; Step <= 20; ++Step)
        {
            const auto Out = Evaluate_Burst(kDelayWind + kLifeCone * float(Step) / 20.0f, Seed);
            if (Is_Hidden(Out))
            { continue; }

            TestTrue(TEXT("the speed cone stays at its spawn point"),
                Out.Position.IsNearlyZero() && Out.Velocity.IsNearlyZero());
            TestEqual(TEXT("the speed cone's dissolve is a constant, not a curve"),
                Out.Dynamic.X, -0.92719f, kTolerance);
        }

        // t = 0.2: Mesh Scale (0.4, 0.4, 0.3) x the 1.5 -> 2 curve, with the renderer's 5x on Z.
        const auto AtKnot = Evaluate_Burst(kDelayWind + kLifeCone * 0.2f, Seed);
        TestEqual(TEXT("the cone's radius scale is the source's non-uniform 0.4 at 2x"),
            AtKnot.Scale.X, 0.8f, kTolerance);
        TestEqual(TEXT("...on both in-plane axes"), AtKnot.Scale.Y, 0.8f, kTolerance);
        TestEqual(TEXT("...and its length is 0.3 x the renderer's 5x at 2x"),
            AtKnot.Scale.Z, 3.0f, kTolerance);

        // The discriminator: at the same normalized age the wind envelope is still on its plateau while
        // the cone's, whose hold ends at 0.373076 rather than 0.676124, has already begun to fall.
        const auto ConeMid = Evaluate_Burst(kDelayWind + kLifeCone * 0.5f, Seed);
        TestEqual(TEXT("the cone's envelope has left its plateau by t = 0.5"),
            ConeMid.Color.A, 0.05f * 0.797544f, kTolerance);

        const auto TubeMid = Evaluate_Burst(kDelayWind + kLifeTube * 0.5f, Get_SeedsForBurstLayer(kLayerTube, 1)[0]);
        TestEqual(TEXT("...where the wind envelope is still on its own"), TubeMid.Color.A, 0.3f, kTolerance);

        TestEqual(TEXT("the cone's blue channel is the source constant"), AtKnot.Color.B, 1.0f, kTolerance);
        TestEqual(TEXT("the cone's red channel is the source constant"),  AtKnot.Color.R, 0.597202f, kTolerance);
    }

    // ---- Wind_Smokes: wide, short, sub-UV, and blown backwards off a 20-unit offset ----
    {
        auto SeenFrames  = TSet<int32>{};
        auto AdvancedFor = 0;
        auto Sampled     = 0;

        for (const auto Seed : Get_SeedsForBurstLayer(kLayerSmokes, 24))
        {
            const auto AtSpawn = Evaluate_Burst(kDelaySmokes, Seed);

            TestTrue(TEXT("the smokes spawn 20 units behind the origin"),
                FMath::IsNearlyEqual(AtSpawn.Position.X, -20.0f, kTolerance)
                && FMath::IsNearlyZero(AtSpawn.Position.Y, kTolerance));

            TestTrue(TEXT("the smokes are blown down -X"), AtSpawn.Velocity.X < 0.0f);
            TestTrue(TEXT("the smoke quads are far wider than they are tall"),
                AtSpawn.Size.X > AtSpawn.Size.Y * 2.0f);
            TestTrue(TEXT("the sprite rotation stays inside the source's +-30 degrees"),
                AtSpawn.Rotation >= -30.0f - kTolerance && AtSpawn.Rotation <= 30.0f + kTolerance);

            auto First = -1.0f;
            auto Last  = -1.0f;

            for (auto Step = 0; Step <= 40; ++Step)
            {
                const auto Out = Evaluate_Burst(kDelaySmokes + kLifeSmokes * float(Step) / 40.0f, Seed);
                if (Is_Hidden(Out))
                { continue; }

                TestTrue(TEXT("the smoke flipbook frame stays inside the source's 2x2 sheet"),
                    Out.SubImageIndex >= 0.0f && Out.SubImageIndex <= 3.0f);

                SeenFrames.Add(FMath::RoundToInt32(Out.SubImageIndex));
                if (First < 0.0f) { First = Out.SubImageIndex; }
                Last = Out.SubImageIndex;
            }

            if (Last != First) { ++AdvancedFor; }
            ++Sampled;
        }

        TestEqual(*FString::Printf(TEXT("the smoke sheet uses all four frames (%d seen)"), SeenFrames.Num()),
            SeenFrames.Num(), 4);
        TestEqual(TEXT("every sampled smoke puff advances its flipbook"), AdvancedFor, Sampled);

        const auto Seed = Get_SeedsForBurstLayer(kLayerSmokes, 1)[0];
        const auto Mid  = Evaluate_Burst(kDelaySmokes + kLifeSmokes * 0.5f, Seed);
        TestEqual(TEXT("the smokes' green channel is the source constant"), Mid.Color.G, 0.743954f, kTolerance);
        TestEqual(TEXT("the envelope plateaus at the layer's Scale Alpha of 0.2"),
            Mid.Color.A, 0.2f, kTolerance);

        // Uniform Curve 0.5 -> 1: the puffs only ever grow.
        const auto AtSpawn = Evaluate_Burst(kDelaySmokes, Seed);
        const auto Late    = Evaluate_Burst(kDelaySmokes + kLifeSmokes * 0.95f, Seed);
        TestTrue(TEXT("the puffs grow monotonically and never shrink"), Late.Size.X > AtSpawn.Size.X);
        TestEqual(TEXT("...on exactly the source's 0.5 -> 1 uniform curve"),
            Late.Size.X / AtSpawn.Size.X, 1.95f, 1.0e-3f);
    }

    // ---- Add_Lines: the cone aperture, the closed-form drag, and the speed-driven stretch ----
    {
        auto SpeedMin  = TNumericLimits<float>::Max();
        auto SpeedMax  = 0.0f;
        auto WorstDot  = 1.0f;
        auto RedMin    = TNumericLimits<float>::Max();
        auto RedMax    = 0.0f;
        auto GreenMin  = TNumericLimits<float>::Max();
        auto GreenMax  = 0.0f;
        auto AlphaMax  = 0.0f;

        for (const auto Seed : Get_SeedsForBurstLayer(kLayerLines, 400))
        {
            const auto AtSpawn = Evaluate_Burst(0.0f, Seed);

            // Sphere Location, radius 50, through the volume.
            TestTrue(TEXT("a speed line spawns inside the source's 50-unit sphere"),
                AtSpawn.Position.Size() <= 50.0f + kTolerance);

            const auto Speed = AtSpawn.Velocity.Size();
            SpeedMin = FMath::Min(SpeedMin, Speed);
            SpeedMax = FMath::Max(SpeedMax, Speed);

            const auto Dir = AtSpawn.Velocity.GetSafeNormal();
            WorstDot = FMath::Min(WorstDot, static_cast<float>(FVector3f::DotProduct(Dir, FVector3f(-1.0f, 0.0f, 0.0f))));

            RedMin   = FMath::Min(RedMin,   AtSpawn.Color.R);
            RedMax   = FMath::Max(RedMax,   AtSpawn.Color.R);
            GreenMin = FMath::Min(GreenMin, AtSpawn.Color.G);
            GreenMax = FMath::Max(GreenMax, AtSpawn.Color.G);
            AlphaMax = FMath::Max(AlphaMax, AtSpawn.Color.A);

            TestEqual(TEXT("a speed line's blue channel is pinned at 1"), AtSpawn.Color.B, 1.0f, kTolerance);

            // Linear drag is isotropic, so it may change the SPEED and never the direction.
            const auto Later = Evaluate_Burst(0.4f, Seed);
            TestTrue(TEXT("drag slows a speed line"), Later.Velocity.Size() < Speed);
            TestTrue(TEXT("...without bending it"),
                FVector3f::DotProduct(Later.Velocity.GetSafeNormal(), Dir) > 1.0f - 1.0e-4f);

            // Velocity-aligned streaks: the stretch is on the length axis.
            TestTrue(TEXT("a young speed line is far longer than it is wide"),
                AtSpawn.Size.Y > AtSpawn.Size.X * 4.0f);
            TestTrue(TEXT("a slowed speed line is shorter than a fast one"), Later.Size.Y < AtSpawn.Size.Y);
        }

        TestTrue(*FString::Printf(TEXT("every launch direction sits inside the source's 10 degree cone (worst dot %f)"),
            WorstDot), WorstDot >= kConeHalfCos - 1.0e-5f);

        // Speed is the source's 350..750 range, thinned at the rim by Velocity Falloff Away From Cone Axis.
        TestTrue(*FString::Printf(TEXT("launch speed stays inside the falloff-scaled source range (%f..%f)"),
            SpeedMin, SpeedMax),
            SpeedMin >= kSpeedLo * (1.0f - kConeFalloff) - kTolerance && SpeedMax <= kSpeedHi + kTolerance);
        // The top of the draw is thinned by whatever falloff its own direction earns, so the ceiling itself
        // is not reachable — the claim is that the range's upper reach is exercised, not that 750 is hit.
        TestTrue(*FString::Printf(TEXT("the fast end of the source range is exercised (saw %f)"), SpeedMax),
            SpeedMax > kSpeedHi * 0.9f);

        // Recovered colour keys: the exported minimum's R and G sit ABOVE the maximum's, and both ends of
        // each channel must be reachable — a reading that silently swapped the pair is invisible otherwise.
        // "Reached" is measured against each channel's OWN span, because green's is three times red's.
        const auto RedSpan   = kLineRMax - kLineRMin;
        const auto GreenSpan = kLineGMax - kLineGMin;

        TestTrue(*FString::Printf(TEXT("the recovered red range is the source's %f..%f (saw %f..%f)"),
            kLineRMin, kLineRMax, RedMin, RedMax),
            RedMin >= kLineRMin - kTolerance && RedMax <= kLineRMax + kTolerance
            && RedMin < kLineRMin + RedSpan * 0.01f && RedMax > kLineRMax - RedSpan * 0.01f);
        TestTrue(*FString::Printf(TEXT("the recovered green range is the source's %f..%f (saw %f..%f)"),
            kLineGMin, kLineGMax, GreenMin, GreenMax),
            GreenMin >= kLineGMin - kTolerance && GreenMax <= kLineGMax + kTolerance
            && GreenMin < kLineGMin + GreenSpan * 0.01f && GreenMax > kLineGMax - GreenSpan * 0.01f);

        // Random alpha 0.3..0.7 under a ramp whose first key sits a hair above 1.
        TestTrue(*FString::Printf(TEXT("the alpha draw tops out at the source's 0.7 (saw %f)"), AlphaMax),
            AlphaMax > 0.69f && AlphaMax < 0.71f);
    }

    // ---- Closed-form drag: the same age must give the same answer at ANY DeltaTime ----
    // A step integration would make position depend on the frame cadence that led there.
    {
        for (const auto Seed : Get_SeedsForBurstLayer(kLayerLines, 40))
        {
            const auto Fast = Evaluate(0.35f, Seed, 0.0f, 1.0f / 120.0f);
            const auto Slow = Evaluate(0.35f, Seed, 0.0f, 1.0f / 15.0f);

            TestTrue(TEXT("a speed line's position is a function of age alone"),
                Fast.Position.Equals(Slow.Position, 0.0f));
            TestTrue(TEXT("...and so is its velocity"),
                Fast.Velocity.Equals(Slow.Velocity, 0.0f));
        }
    }

    // ---- The lines' lifetime is a RANGE, and both of its ends are reachable ----
    {
        auto LifeMin = TNumericLimits<float>::Max();
        auto LifeMax = 0.0f;

        for (const auto Seed : Get_SeedsForBurstLayer(kLayerLines, 300))
        {
            const auto Last = Get_LastLiveAge(Seed, 1.05f, 420);
            LifeMin = FMath::Min(LifeMin, Last);
            LifeMax = FMath::Max(LifeMax, Last);
        }

        TestTrue(*FString::Printf(TEXT("every speed line dies inside the source's 0.8..1.0 range (saw %f..%f)"),
            LifeMin, LifeMax),
            LifeMin >= kLifeLineLo - 0.005f && LifeMax <= kLifeLineHi + 0.005f);
        TestTrue(TEXT("both ends of the lifetime range are reached"),
            LifeMin < kLifeLineLo + 0.01f && LifeMax > kLifeLineHi - 0.01f);
    }

    // ---- Anti-vacuity: every layer emits light and has extent somewhere in its life ----
    {
        const int32 Layers[]   = { kLayerTube, kLayerSmokes, kLayerCone, kLayerLines };
        const TCHAR* Names[]   = { TEXT("Wind_01"), TEXT("Wind_Smokes"), TEXT("Wind_Speed"), TEXT("Add_Lines") };

        for (auto Index = 0; Index < 4; ++Index)
        {
            auto PeakLight  = 0.0f;
            auto PeakExtent = 0.0f;

            for (const auto Seed : Get_SeedsForBurstLayer(Layers[Index], 4))
            {
                for (auto Step = 0; Step <= 80; ++Step)
                {
                    const auto Out = Evaluate_Burst(kLifetime * float(Step) / 80.0f, Seed);
                    PeakLight  = FMath::Max(PeakLight, (Out.Color.R + Out.Color.G + Out.Color.B) * Out.Color.A);
                    PeakExtent = FMath::Max(PeakExtent,
                        FMath::Max(FMath::Max(Out.Size.X, Out.Size.Y), FMath::Max(Out.Scale.X, Out.Scale.Z)));
                }
            }

            TestTrue(*FString::Printf(TEXT("%s emits nonzero light somewhere in its life"), Names[Index]),
                PeakLight > kTolerance);
            TestTrue(*FString::Printf(TEXT("%s has nonzero extent somewhere in its life"), Names[Index]),
                PeakExtent > kTolerance);
        }
    }

    // ---- Death: nothing survives the row's lifetime, on either spawn path ----
    {
        for (auto Seed = 0; Seed < 200; ++Seed)
        {
            TestTrue(*FString::Printf(TEXT("burst seed %d is dead past the row's 1.55 s lifetime"), Seed),
                Is_Hidden(Evaluate(kLifetime + 0.001f, Seed, 0.0f)));
            TestTrue(*FString::Printf(TEXT("streamed seed %d is dead past the row's 1.55 s lifetime"), Seed),
                Is_Hidden(Evaluate(kLifetime + 0.001f, Seed, 0.15f)));
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
