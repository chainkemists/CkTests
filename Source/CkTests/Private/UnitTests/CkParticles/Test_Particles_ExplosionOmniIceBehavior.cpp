// Behavior-math gate for CkParticles BehaviorId 43 (ExplosionOmniIce) — the Vefects NS_ExplosionIceOmni
// recreation, and the SECOND of the cookbook's two palette twins.
//
// Same shape as the Ground twin's gate (behavior 41): it drives behaviors 42 and 43 over the same seeds and
// ages and asserts that every output field is identical EXCEPT where the corpus diff says a recolour
// touches. The Omni pair's diff (NS_ExplosionIceOmni.md §5.0, re-run at implementation) is eleven colour
// tables, TWO direct-set lifetimes, two scalars, one curve-index binding and one inert authored leftover.
//
// The two lifetimes are what makes this twin different from the Ground one, and they are the thing most
// likely to be lost in a recolour: Bubble_First_Explo and Spike01 live 0.1 s in the fire variant and 0.15 s
// in the ice one, so the ice shells persist 50 % longer. They are asserted directly.
//
// The inert leftover is asserted too, in the only way it can be: NS_ExplosionIceOmni exports a
// `Flare01.InitializeParticle.Mesh Uniform Scale = 1` that the other three variants do not, on a SPRITE
// emitter whose Mesh Scale Mode is Unset. If it were live the twin's Flare layer would carry a mesh scale;
// it must not.
//
// Cannot pass vacuously: behavior 43 draws on VisTags 198..209 and the pre-switch default is 0.

#include "Misc/AutomationTest.h"

#include "CkParticles/DataInterface/CkParticles_DataInterface.h"
#include "CkParticles/ScriptDefinition/CkParticles_ScriptDefinition_Naming.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_particles_explosion_omni_ice
{
    constexpr auto kFireId    = 42;
    constexpr auto kIceId     = 43;
    constexpr auto kTolerance = 1.0e-4f;

    constexpr auto kLoop     = 2.0f;
    constexpr auto kLifetime = 1.3f;
    constexpr auto kBurst    = 65;

    constexpr auto kRowAssetName = TEXT("PS_CkParticles_Template_ExplosionOmniIce");

    constexpr auto kVisPart01Cam    = 198;
    constexpr auto kVisFlare        = 199;
    constexpr auto kVisStar         = 200;
    constexpr auto kVisSmoke        = 201;
    constexpr auto kVisRing         = 202;
    constexpr auto kVisRainbow      = 203;
    constexpr auto kVisFlames       = 204;
    constexpr auto kVisPart04       = 205;
    constexpr auto kVisPart01Custom = 206;
    constexpr auto kVisSphere       = 207;
    constexpr auto kVisSpike        = 208;
    constexpr auto kVisRibbon       = 209;

    // The two layers whose LIFETIME the recolour moves, on the Omni partition (recipe §6.1).
    constexpr auto kBubbleSlot     = 0;
    constexpr auto kSpikeSlotFirst = 37;
    constexpr auto kSpikeSlotLast  = 41;

    constexpr auto kFireMeshLife = 0.1f;
    constexpr auto kIceMeshLife  = 0.15f;

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

    auto Is_MeshLifeLayer(int32 InSlot) -> bool
    {
        return InSlot == kBubbleSlot || (InSlot >= kSpikeSlotFirst && InSlot <= kSpikeSlotLast);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Particles_ExplosionOmniIceBehavior,
    "CkTests.UnitTests.CkParticles.ExplosionOmniIceBehavior",
    kCkUnitTestFlags)

bool FCkTest_Particles_ExplosionOmniIceBehavior::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_explosion_omni_ice;

    // ---- The twin has its OWN template path and the SAME row shape ----
    {
        TestEqual(TEXT("behavior 43 routes to its own ExplosionOmniIce row"),
            ck::particles::Get_BehaviorTemplateSystemObjectPath(kIceId),
            ck::particles::Get_ExplosionOmniIceTemplateSystemObjectPath());

        TestNotEqual(TEXT("...which is NOT the fire original's template"),
            ck::particles::Get_BehaviorTemplateSystemObjectPath(kIceId),
            ck::particles::Get_BehaviorTemplateSystemObjectPath(kFireId));

        const auto* FireRow = static_cast<const ck::particles::FCk_ParticlesTemplateSpec*>(nullptr);
        const auto* IceRow  = static_cast<const ck::particles::FCk_ParticlesTemplateSpec*>(nullptr);
        for (const auto& Spec : ck::particles::Get_TemplateSpecs())
        {
            if (FString(Spec.AssetName) == FString(TEXT("PS_CkParticles_Template_ExplosionOmni")))
            { FireRow = &Spec; }
            if (FString(Spec.AssetName) == FString(kRowAssetName))
            { IceRow = &Spec; }
        }

        if (TestNotNull(TEXT("the cadence table declares the twin's row"), IceRow)
            && TestNotNull(TEXT("...and the fire original's"), FireRow))
        {
            TestEqual(TEXT("the twin's loop is the system's 2.0 s"), IceRow->LoopDuration, kLoop, kTolerance);
            TestEqual(TEXT("the twin's lifetime is the smoke layers' 1.3 s"),
                IceRow->ParticleLifetime, kLifetime, kTolerance);
            TestEqual(TEXT("the twin's burst is 65"), IceRow->BurstCount, kBurst);
            TestEqual(TEXT("the twin's cadence matches its original's exactly"),
                IceRow->BurstCount, FireRow->BurstCount);
            TestTrue(TEXT("the twin declares literally the same renderer array — one function, two rows"),
                IceRow->RendererOverrides.GetData() == FireRow->RendererOverrides.GetData());
            TestTrue(TEXT("...and the same ribbon renderer array"),
                IceRow->RibbonEmitter.Renderers.GetData() == FireRow->RibbonEmitter.Renderers.GetData());
        }
    }

    // ---- The twins agree on everything structural, outside the two layers whose LIFETIME moves ----
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
            if (Is_MeshLifeLayer(Seed))
            { continue; }

            for (auto Step = 0; Step <= 60; ++Step)
            {
                const auto Age  = 1.4f * float(Step) / 60.0f;
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
                if (NOT Fire.Dynamic.Equals(Ice.Dynamic, kTolerance))
                { ++DynamicMismatch; }
            }
        }

        TestTrue(TEXT("the sweep compared a real population"), Compared >= (kBurst - 6) * 61);

        TestEqual(TEXT("a recolour moves NO renderer assignment"), VisTagMismatch,    0);
        TestEqual(TEXT("a recolour moves NO position"),            PositionMismatch,  0);
        TestEqual(TEXT("a recolour moves NO velocity"),            VelocityMismatch,  0);
        TestEqual(TEXT("a recolour moves NO sprite size"),         SizeMismatch,      0);
        TestEqual(TEXT("a recolour moves NO mesh scale"),          ScaleMismatch,     0);
        TestEqual(TEXT("a recolour moves NO sprite rotation"),     RotationMismatch,  0);
        TestEqual(TEXT("a recolour moves NO carrier index"),       MeshIndexMismatch, 0);
        TestEqual(TEXT("a recolour moves NO sprite facing pair"),  FacingMismatch,    0);
        TestEqual(TEXT("a recolour moves NO flipbook frame"),      SubImageMismatch,  0);
        TestEqual(TEXT("a recolour moves NO dynamic parameter on the Omni pair"), DynamicMismatch, 0);
    }

    // ---- The two lifetimes the recolour DOES move ----
    {
        // Just past the fire life and inside the ice one: the fire shell is gone and the ice one is not.
        constexpr auto Between = 0.5f * (kFireMeshLife + kIceMeshLife);

        const auto FireBubble = Evaluate(kFireId, Between, kBubbleSlot);
        const auto IceBubble  = Evaluate(kIceId,  Between, kBubbleSlot);

        TestTrue(TEXT("the FIRE bubble is gone by 0.125 s — its Direct-Set lifetime is 0.1"),
            Is_Hidden(FireBubble));
        TestFalse(TEXT("the ICE bubble is still drawing — its lifetime is 0.15"), Is_Hidden(IceBubble));
        TestEqual(TEXT("the ice bubble still draws on the sphere carrier"), IceBubble.VisTag, kVisSphere);

        auto FireSpikesAlive = 0;
        auto IceSpikesAlive  = 0;
        for (auto Seed = kSpikeSlotFirst; Seed <= kSpikeSlotLast; ++Seed)
        {
            if (NOT Is_Hidden(Evaluate(kFireId, Between, Seed))) { ++FireSpikesAlive; }
            if (NOT Is_Hidden(Evaluate(kIceId,  Between, Seed))) { ++IceSpikesAlive;  }
        }

        TestEqual(TEXT("every FIRE spike is gone by 0.125 s"), FireSpikesAlive, 0);
        TestEqual(TEXT("every ICE spike is still drawing"),     IceSpikesAlive, 5);

        // Inside BOTH lifetimes the layers still differ only by colour: the ice life is longer, so the
        // normalized age differs and the scale curve lands elsewhere. That is a consequence of the
        // lifetime, not a second difference, so it is asserted at the shared t = 0 instead.
        const auto FireAtZero = Evaluate(kFireId, 0.0f, kBubbleSlot);
        const auto IceAtZero  = Evaluate(kIceId,  0.0f, kBubbleSlot);
        TestEqual(TEXT("at t = 0 both bubbles carry the same (zero) scale"),
            (FireAtZero.Scale - IceAtZero.Scale).Size(), 0.0f);
        TestTrue(TEXT("...and different colours"), NOT FireAtZero.Color.Equals(IceAtZero.Color, kTolerance));
    }

    // ---- The inert authored leftover: Flare01 is a SPRITE and must carry no mesh scale in either twin ----
    {
        int32 FlareSlot = INDEX_NONE;
        for (auto Seed = 0; Seed < kBurst; ++Seed)
        {
            if (Evaluate(kIceId, 0.15f, Seed).VisTag == kVisFlare)
            { FlareSlot = Seed; break; }
        }

        if (TestTrue(TEXT("a Flare01 slot exists"), FlareSlot != INDEX_NONE))
        {
            const auto Fire = Evaluate(kFireId, 0.15f, FlareSlot);
            const auto Ice  = Evaluate(kIceId,  0.15f, FlareSlot);

            TestEqual(TEXT("the fire Flare01 leaves Scale at the pass-through default"),
                (Fire.Scale - FVector3f(1.0f, 1.0f, 1.0f)).Size(), 0.0f);
            TestEqual(TEXT("the ice Flare01's exported Mesh Uniform Scale is INERT — a sprite has none"),
                (Ice.Scale - Fire.Scale).Size(), 0.0f);
            TestTrue(TEXT("the two Flare01 colours DO differ — the leftover is inert, the palette is not"),
                NOT Fire.Color.Equals(Ice.Color, kTolerance));
        }
    }

    // ---- Colour differs everywhere except Raimbow ----
    {
        auto ByTag = TMap<int32, int32>{};
        auto Seen  = TMap<int32, int32>{};

        for (auto Seed = 0; Seed < kBurst; ++Seed)
        {
            for (auto Step = 0; Step <= 40; ++Step)
            {
                const auto Age  = 1.4f * float(Step) / 40.0f;
                const auto Fire = Evaluate(kFireId, Age, Seed);
                const auto Ice  = Evaluate(kIceId,  Age, Seed);

                if (Is_Hidden(Fire) && Is_Hidden(Ice))
                { continue; }

                Seen.FindOrAdd(Ice.VisTag) += 1;
                if (NOT Fire.Color.Equals(Ice.Color, kTolerance))
                { ByTag.FindOrAdd(Ice.VisTag) += 1; }
            }
        }

        const int32 MustDiffer[] = { kVisPart01Cam, kVisFlare, kVisStar, kVisSmoke, kVisRing, kVisFlames,
                                     kVisPart04, kVisPart01Custom, kVisSphere, kVisSpike };
        for (const auto Tag : MustDiffer)
        {
            TestTrue(FString::Printf(TEXT("VisTag %d was drawn by the sweep"), Tag), Seen.FindRef(Tag) > 0);
            TestTrue(FString::Printf(TEXT("VisTag %d carries a DIFFERENT colour in the ice palette"), Tag),
                ByTag.FindRef(Tag) > 0);
        }

        TestTrue(TEXT("the Raimbow layer was drawn by the sweep"), Seen.FindRef(kVisRainbow) > 0);
        TestEqual(TEXT("Raimbow is the ONE layer a recolour leaves alone"), ByTag.FindRef(kVisRainbow), 0);
    }

    // ---- The ribbon's curve index flips with the palette here too ----
    {
        constexpr auto Instant = 0.30f;

        const auto FireEarly = Evaluate(kFireId, Instant, ck::particles::RibbonSeedBase + 6);
        const auto FireLate  = Evaluate(kFireId, Instant, ck::particles::RibbonSeedBase + 12);
        const auto IceEarly  = Evaluate(kIceId,  Instant, ck::particles::RibbonSeedBase + 6);
        const auto IceLate   = Evaluate(kIceId,  Instant, ck::particles::RibbonSeedBase + 12);

        TestFalse(TEXT("all four sampled trail points are alive"),
            Is_Hidden(FireEarly) || Is_Hidden(FireLate) || Is_Hidden(IceEarly) || Is_Hidden(IceLate));

        TestEqual(TEXT("the FIRE trail is indexed by the emitter clock"),
            FireEarly.Color.A, FireLate.Color.A, kTolerance);
        TestTrue(TEXT("the ICE trail is indexed by particle age"),
            FMath::Abs(IceEarly.Color.A - IceLate.Color.A) > kTolerance);

        TestEqual(TEXT("both trails sit on the ribbon VisTag"), IceEarly.VisTag, kVisRibbon);
        TestEqual(TEXT("the recolour does not move the trail's geometry"),
            (FireEarly.Position - IceEarly.Position).Size(), 0.0f);
    }

    return true;
}
