// Behavior-math gate for CkParticles BehaviorId 41 (ExplosionGroundIce) — the Vefects NS_ExplosionIceGround
// recreation, and the FIRST of the cookbook's two palette twins.
//
// This test exists to prove one claim, and it is a claim about the IMPLEMENTATION rather than about the
// source: behaviors 40 and 41 share every line of layer math (Behavior_ExplosionShared.ush + its one CPU
// mirror) and differ ONLY by a palette id. So it drives BOTH behaviors over the same seeds and the same
// ages and asserts that every output field is bit-identical EXCEPT the ones the corpus diff says a recolour
// touches.
//
// That corpus diff is the ground truth (NS_ExplosionIceGround.md §5.0 + §5.1-5.18, re-run at implementation
// against the .txt exports): a full textual diff of NS_ExplosionGround against NS_ExplosionIceGround
// produces ZERO renderer, material, mesh, spawn-shape, count, lifetime, spawn-time or module-structure
// differences. What it produces is twelve colour tables, three scalars and one curve-index binding.
//
// The two directions this test fails in are both real defects:
//   - a field that SHOULD be identical differs => the twins are not sharing their math after all, which is
//     the [P4-D1] fence;
//   - a field that SHOULD differ does not => the palette table was not wired, and the ice port renders the
//     fire colours.
//
// Cannot pass vacuously: behavior 41 draws on VisTags 185..197 and the pre-switch default is 0.

#include "Misc/AutomationTest.h"

#include "CkParticles/DataInterface/CkParticles_DataInterface.h"
#include "CkParticles/ScriptDefinition/CkParticles_ScriptDefinition_Naming.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_particles_explosion_ground_ice
{
    constexpr auto kFireId    = 40;
    constexpr auto kIceId     = 41;
    constexpr auto kTolerance = 1.0e-4f;

    constexpr auto kLoop     = 2.0f;
    constexpr auto kLifetime = 1.5f;
    constexpr auto kBurst    = 70;

    constexpr auto kRowAssetName = TEXT("PS_CkParticles_Template_ExplosionGroundIce");

    constexpr auto kVisPart01Cam    = 185;
    constexpr auto kVisFlare        = 186;
    constexpr auto kVisStar         = 187;
    constexpr auto kVisSmoke        = 188;
    constexpr auto kVisRing         = 189;
    constexpr auto kVisRainbow      = 190;
    constexpr auto kVisFlames       = 191;
    constexpr auto kVisPart04       = 192;
    constexpr auto kVisPart01Custom = 193;
    constexpr auto kVisMark         = 194;
    constexpr auto kVisSphere       = 195;
    constexpr auto kVisSpike        = 196;
    constexpr auto kVisRibbon       = 197;

    // Burst slots the Ground partition assigns to Glow_02 — the ONE layer whose non-colour output the
    // recolour moves (its dissolve channel, 0.4 -> 0.6).
    constexpr auto kGlow02SlotFirst = 46;
    constexpr auto kGlow02SlotLast  = 48;

    auto Evaluate(int32 InBehaviorId, float InAge, int32 InSeed) -> FCk_Particles_StageResult
    {
        constexpr auto DeltaTime = 1.0f / 60.0f;

        return UCkParticles_DataInterface::Execute_Stage_CPU(
            InBehaviorId, DeltaTime, InAge, kLifetime,
            FVector3f::ZeroVector, FVector3f::ZeroVector, InSeed, InAge);
    }

    auto Is_Hidden(const FCk_Particles_StageResult& InOut) -> bool
    {
        return InOut.Color.A == 0.0f && InOut.Color.R == 0.0f && InOut.Color.G == 0.0f && InOut.Color.B == 0.0f
            && InOut.Size.IsNearlyZero() && InOut.Scale.IsNearlyZero();
    }

    auto Colors_Differ(const FCk_Particles_StageResult& InA, const FCk_Particles_StageResult& InB) -> bool
    {
        return NOT InA.Color.Equals(InB.Color, kTolerance);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Particles_ExplosionGroundIceBehavior,
    "CkTests.UnitTests.CkParticles.ExplosionGroundIceBehavior",
    kCkUnitTestFlags)

bool FCkTest_Particles_ExplosionGroundIceBehavior::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_explosion_ground_ice;

    // ---- The twin has its OWN template path — that path is the spawn contract — and the SAME row shape ----
    {
        TestEqual(TEXT("behavior 41 routes to its own ExplosionGroundIce row"),
            ck::particles::Get_BehaviorTemplateSystemObjectPath(kIceId),
            ck::particles::Get_ExplosionGroundIceTemplateSystemObjectPath());

        TestNotEqual(TEXT("...which is NOT the fire original's template"),
            ck::particles::Get_BehaviorTemplateSystemObjectPath(kIceId),
            ck::particles::Get_BehaviorTemplateSystemObjectPath(kFireId));

        const auto* FireRow = static_cast<const ck::particles::FCk_ParticlesTemplateSpec*>(nullptr);
        const auto* IceRow  = static_cast<const ck::particles::FCk_ParticlesTemplateSpec*>(nullptr);
        for (const auto& Spec : ck::particles::Get_TemplateSpecs())
        {
            if (FString(Spec.AssetName) == FString(TEXT("PS_CkParticles_Template_ExplosionGround")))
            { FireRow = &Spec; }
            if (FString(Spec.AssetName) == FString(kRowAssetName))
            { IceRow = &Spec; }
        }

        if (TestNotNull(TEXT("the cadence table declares the twin's row"), IceRow)
            && TestNotNull(TEXT("...and the fire original's"), FireRow))
        {
            TestEqual(TEXT("the twin's loop matches its original's"),
                IceRow->LoopDuration, FireRow->LoopDuration, kTolerance);
            TestEqual(TEXT("the twin's lifetime matches its original's"),
                IceRow->ParticleLifetime, FireRow->ParticleLifetime, kTolerance);
            TestEqual(TEXT("the twin's burst matches its original's"),
                IceRow->BurstCount, FireRow->BurstCount);
            TestEqual(TEXT("the twin's loop is the system's 2.0 s"), IceRow->LoopDuration, kLoop, kTolerance);
            TestEqual(TEXT("the twin's lifetime is Ground_Mark's 1.5 s"),
                IceRow->ParticleLifetime, kLifetime, kTolerance);
            TestEqual(TEXT("the twin's burst is 70"), IceRow->BurstCount, kBurst);

            TestEqual(TEXT("the twin declares the SAME renderer count as its original"),
                IceRow->RendererOverrides.Num(), FireRow->RendererOverrides.Num());
            TestTrue(TEXT("...and literally the same renderer array — one function serves both rows"),
                IceRow->RendererOverrides.GetData() == FireRow->RendererOverrides.GetData());
            TestTrue(TEXT("...and the same ribbon renderer array"),
                IceRow->RibbonEmitter.Renderers.GetData() == FireRow->RibbonEmitter.Renderers.GetData());
        }
    }

    // ---- The twins agree on EVERYTHING structural, over the whole burst and the whole loop ----
    {
        auto Compared          = 0;
        auto VisTagMismatch    = 0;
        auto PositionMismatch  = 0;
        auto VelocityMismatch  = 0;
        auto SizeMismatch      = 0;
        auto ScaleMismatch     = 0;
        auto RotationMismatch  = 0;
        auto MeshIndexMismatch = 0;
        auto FacingMismatch    = 0;
        auto SubImageMismatch  = 0;
        auto DynamicMismatch   = 0;

        for (auto Seed = 0; Seed < kBurst; ++Seed)
        {
            const auto IsGlow02 = Seed >= kGlow02SlotFirst && Seed <= kGlow02SlotLast;

            for (auto Step = 0; Step <= 60; ++Step)
            {
                const auto Age  = 1.6f * float(Step) / 60.0f;
                const auto Fire = Evaluate(kFireId, Age, Seed);
                const auto Ice  = Evaluate(kIceId,  Age, Seed);

                ++Compared;

                if (Fire.VisTag != Ice.VisTag)                             { ++VisTagMismatch;    }
                if (NOT Fire.Position.Equals(Ice.Position, kTolerance))    { ++PositionMismatch;  }
                if (NOT Fire.Velocity.Equals(Ice.Velocity, kTolerance))    { ++VelocityMismatch;  }
                if (NOT Fire.Size.Equals(Ice.Size, kTolerance))            { ++SizeMismatch;      }
                if (NOT Fire.Scale.Equals(Ice.Scale, kTolerance))          { ++ScaleMismatch;     }
                if (FMath::Abs(Fire.Rotation - Ice.Rotation) > kTolerance) { ++RotationMismatch;  }
                if (Fire.MeshIndex != Ice.MeshIndex)                       { ++MeshIndexMismatch; }
                if (NOT Fire.SpriteFacing.Equals(Ice.SpriteFacing, kTolerance)
                 || NOT Fire.SpriteAlignment.Equals(Ice.SpriteAlignment, kTolerance))
                { ++FacingMismatch; }
                if (FMath::Abs(Fire.SubImageIndex - Ice.SubImageIndex) > kTolerance)
                { ++SubImageMismatch; }

                if (NOT IsGlow02 && NOT Fire.Dynamic.Equals(Ice.Dynamic, kTolerance))
                { ++DynamicMismatch; }
            }
        }

        TestTrue(TEXT("the sweep compared the whole burst across the whole loop"), Compared == kBurst * 61);

        TestEqual(TEXT("a recolour moves NO renderer assignment"),   VisTagMismatch,    0);
        TestEqual(TEXT("a recolour moves NO position"),              PositionMismatch,  0);
        TestEqual(TEXT("a recolour moves NO velocity"),              VelocityMismatch,  0);
        TestEqual(TEXT("a recolour moves NO sprite size"),           SizeMismatch,      0);
        TestEqual(TEXT("a recolour moves NO mesh scale"),            ScaleMismatch,     0);
        TestEqual(TEXT("a recolour moves NO sprite rotation"),       RotationMismatch,  0);
        TestEqual(TEXT("a recolour moves NO carrier index"),         MeshIndexMismatch, 0);
        TestEqual(TEXT("a recolour moves NO sprite facing pair"),    FacingMismatch,    0);
        TestEqual(TEXT("a recolour moves NO flipbook frame"),        SubImageMismatch,  0);
        TestEqual(TEXT("a recolour moves NO dynamic parameter outside Glow_02"), DynamicMismatch, 0);
    }

    // ---- ...and they differ on colour EXACTLY where the sheets' palette diff says ----
    {
        // Every layer in the source's own diff carries a different colour table. Raimbow does NOT: its
        // Color module has no override in either variant, so its particle colour is a constant white the
        // Scale Color halves, identically in both.
        auto ByTag = TMap<int32, int32>{};   // VisTag -> number of sampled instants whose colour differs
        auto Seen  = TMap<int32, int32>{};

        for (auto Seed = 0; Seed < kBurst; ++Seed)
        {
            for (auto Step = 0; Step <= 40; ++Step)
            {
                const auto Age  = 1.6f * float(Step) / 40.0f;
                const auto Fire = Evaluate(kFireId, Age, Seed);
                const auto Ice  = Evaluate(kIceId,  Age, Seed);

                if (Is_Hidden(Fire) && Is_Hidden(Ice))
                { continue; }

                Seen.FindOrAdd(Fire.VisTag) += 1;
                if (Colors_Differ(Fire, Ice))
                { ByTag.FindOrAdd(Fire.VisTag) += 1; }
            }
        }

        const int32 MustDiffer[] = { kVisPart01Cam, kVisFlare, kVisStar, kVisSmoke, kVisRing, kVisFlames,
                                     kVisPart04, kVisPart01Custom, kVisMark, kVisSphere, kVisSpike };
        for (const auto Tag : MustDiffer)
        {
            TestTrue(FString::Printf(TEXT("VisTag %d was drawn by the sweep"), Tag), Seen.FindRef(Tag) > 0);
            TestTrue(FString::Printf(TEXT("VisTag %d carries a DIFFERENT colour in the ice palette"), Tag),
                ByTag.FindRef(Tag) > 0);
        }

        TestTrue(TEXT("the Raimbow layer was drawn by the sweep"), Seen.FindRef(kVisRainbow) > 0);
        TestEqual(TEXT("Raimbow is the ONE layer a recolour leaves alone — it has no Color override"),
            ByTag.FindRef(kVisRainbow), 0);
    }

    // ---- The three non-colour palette scalars, each pinned to its own source value ----
    {
        // Glow_02's dissolve channel: 0.4 in fire, 0.6 in ice, and nothing else about the layer moves.
        const auto Fire = Evaluate(kFireId, 0.05f, kGlow02SlotFirst);
        const auto Ice  = Evaluate(kIceId,  0.05f, kGlow02SlotFirst);

        TestEqual(TEXT("Glow_02 draws on the custom-facing Part01 quad in both"), Fire.VisTag, kVisPart01Custom);
        TestEqual(TEXT("the fire Glow_02's dissolve is 0.4"), Fire.Dynamic.X, 0.4f, kTolerance);
        TestEqual(TEXT("the ice Glow_02's dissolve is 0.6"),  Ice.Dynamic.X,  0.6f, kTolerance);
        TestEqual(TEXT("its size is untouched by the recolour"), Fire.Size.X, Ice.Size.X, kTolerance);
    }
    {
        // Flames' module-level Color.Scale Alpha: 1 in fire, 0.4 in ice. Pinned at the layer's alpha PEAK,
        // because a missing scale reads 2.5x too bright and nothing else would catch it.
        int32 FlamesSlot = INDEX_NONE;
        for (auto Seed = 0; Seed < kBurst; ++Seed)
        {
            if (Evaluate(kIceId, 0.30f, Seed).VisTag == kVisFlames)
            { FlamesSlot = Seed; break; }
        }

        if (TestTrue(TEXT("a Flames slot exists"), FlamesSlot != INDEX_NONE))
        {
            auto FirePeak = 0.0f;
            auto IcePeak  = 0.0f;
            for (auto Step = 0; Step <= 400; ++Step)
            {
                const auto Age = 0.1f + 0.7f * float(Step) / 400.0f;
                FirePeak = FMath::Max(FirePeak, Evaluate(kFireId, Age, FlamesSlot).Color.A);
                IcePeak  = FMath::Max(IcePeak,  Evaluate(kIceId,  Age, FlamesSlot).Color.A);
            }

            TestEqual(TEXT("the fire flames peak at full alpha"), FirePeak, 1.0f, 1.0e-2f);
            TestEqual(TEXT("the ice flames peak at 0.4 — the Color.Scale Alpha the recolour introduces"),
                IcePeak, 0.4f, 1.0e-2f);
        }
    }
    {
        // The ribbon's curve index: Emitter.Age in fire, particle age in ice. Under the fire binding two
        // points of different ages carry the SAME colour at one instant; under the ice binding they do not.
        constexpr auto Instant  = 0.30f;
        constexpr auto StepsPer = 43;

        const auto FireEarly = Evaluate(kFireId, Instant, ck::particles::RibbonSeedBase + 0 * StepsPer + 6);
        const auto FireLate  = Evaluate(kFireId, Instant, ck::particles::RibbonSeedBase + 0 * StepsPer + 12);
        const auto IceEarly  = Evaluate(kIceId,  Instant, ck::particles::RibbonSeedBase + 0 * StepsPer + 6);
        const auto IceLate   = Evaluate(kIceId,  Instant, ck::particles::RibbonSeedBase + 0 * StepsPer + 12);

        TestFalse(TEXT("all four sampled trail points are alive"),
            Is_Hidden(FireEarly) || Is_Hidden(FireLate) || Is_Hidden(IceEarly) || Is_Hidden(IceLate));

        TestEqual(TEXT("the FIRE trail is indexed by the emitter clock, so the whole strand fades together"),
            FireEarly.Color.A, FireLate.Color.A, kTolerance);
        TestTrue(TEXT("the ICE trail is indexed by particle age, so each point fades on its own clock"),
            FMath::Abs(IceEarly.Color.A - IceLate.Color.A) > kTolerance);

        TestEqual(TEXT("both trails still sit on the same VisTag"), FireEarly.VisTag, kVisRibbon);
        TestEqual(TEXT("...and the recolour does not move the trail's geometry"),
            (FireEarly.Position - IceEarly.Position).Size(), 0.0f);
    }

    return true;
}
