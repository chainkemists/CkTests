// Roster-wide sanity gate for CkParticles.
//
// Three claims, all roster-driven so adding a behavior does not need this file edited:
//   1. The roster METADATA is coherent — one size definition, every id routes to a template the cadence
//      table actually declares, and the behaviors that bind a CkUsf look bind the expected one.
//   2. Every behavior, across ages / lifetimes / seeds, produces RENDERABLE output — finite numbers, a
//      non-negative size, a VisTag the template has a renderer for, a mesh index the carrier set contains,
//      and (on the custom-facing tag) a non-degenerate alignment/facing pair.
//   3. Every behavior's output is INDEPENDENT of the emitter clock. The stage signature carries EmitterAge,
//      but no behavior on the roster today reads it, so shifting it must change nothing at all.
//
// Claim 2 is deliberately shallow: it is a "nothing here is nonsense" net, not a correctness check. Only
// the per-behavior math tests (LightningRangeBehavior) can tell a correct behavior from an inert one.
//
// No Niagara, no template asset, no RHI, no forked engine — this runs on the CPU mirror.

#include "Misc/AutomationTest.h"

#include "CkParticles/DataInterface/CkParticles_DataInterface.h"
#include "CkParticles/ScriptDefinition/CkParticles_ScriptDefinition_Naming.h"
#include "CkParticles/Utils/CkParticles_Utils.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_particles_roster_sanity
{
    // The roster's renderer set. The SHARED band is 0 camera sprite, 1 velocity-aligned, 2 smoke,
    // 3 carrier mesh, 4 custom-facing sprite; a cadence ROW may declare more above it. The bound is read
    // from ck::particles::Get_RosterVisTag_Max() rather than restated, so a new row-declared renderer
    // cannot quietly widen a literal here. A VisTag past it draws with NO renderer — invisible, and silent.

    // SM_CkParticles_ Sweep / Tube / Shell / Disc — the carrier meshes VisTag 3 indexes into.
    constexpr auto kMaxMeshIndex = 3;

    constexpr auto kCustomFacingVisTag = 4;
    constexpr auto kMeshVisTag         = 3;

    constexpr auto kTolerance = 1.0e-4f;

    // The emitter clock every sample is taken against, and the clocks the same sample is re-taken at. The
    // comparison is EXACT, not toleranced: a behavior that ignores an input cannot perturb its output by a
    // little. 41.0 sits far past every cadence row's loop duration, so a behavior that had started reading the
    // clock through a fmod would show up here rather than only near t=0.
    constexpr auto kReferenceEmitterAge = 0.0f;

    auto Is_Identical(const FCk_Particles_StageResult& InA, const FCk_Particles_StageResult& InB) -> bool
    {
        return InA.Position == InB.Position
            && InA.Velocity == InB.Velocity
            && InA.Color    == InB.Color
            && InA.Size     == InB.Size
            && InA.Scale    == InB.Scale
            && InA.Orientation.X == InB.Orientation.X
            && InA.Orientation.Y == InB.Orientation.Y
            && InA.Orientation.Z == InB.Orientation.Z
            && InA.Orientation.W == InB.Orientation.W
            && InA.Dynamic       == InB.Dynamic
            && InA.Rotation      == InB.Rotation
            && InA.MeshIndex     == InB.MeshIndex
            && InA.VisTag        == InB.VisTag
            && InA.SpriteAlignment == InB.SpriteAlignment
            && InA.SpriteFacing    == InB.SpriteFacing
            && InA.SubImageIndex   == InB.SubImageIndex;
    }

    auto Is_Finite(const FVector3f& InV) -> bool
    {
        return FMath::IsFinite(InV.X) && FMath::IsFinite(InV.Y) && FMath::IsFinite(InV.Z);
    }

    auto Is_Finite(const FVector2f& InV) -> bool
    {
        return FMath::IsFinite(InV.X) && FMath::IsFinite(InV.Y);
    }

    auto Is_Finite(const FVector4f& InV) -> bool
    {
        return FMath::IsFinite(InV.X) && FMath::IsFinite(InV.Y)
            && FMath::IsFinite(InV.Z) && FMath::IsFinite(InV.W);
    }

    auto Is_Finite(const FLinearColor& InC) -> bool
    {
        return FMath::IsFinite(InC.R) && FMath::IsFinite(InC.G)
            && FMath::IsFinite(InC.B) && FMath::IsFinite(InC.A);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Particles_RosterSanity,
    "CkTests.UnitTests.CkParticles.RosterSanity",
    kCkUnitTestFlags)

bool FCkTest_Particles_RosterSanity::RunTest(const FString& Parameters)
{
    using namespace ck_test_particles_roster_sanity;

    // ---- Roster size has ONE definition, and it is the one behavior 25 was added to ----
    TestEqual(TEXT("NumBehaviors is 40 (ids 0..39, LightningMuzzle last)"), ck::particles::NumBehaviors, 40);
    TestEqual(TEXT("LastBehaviorId is derived from NumBehaviors"),
        ck::particles::LastBehaviorId, ck::particles::NumBehaviors - 1);
    TestEqual(TEXT("the BP/AS-facing roster size agrees with the C++ constant"),
        UCk_Utils_Particles_UE::Get_NumBehaviors(), ck::particles::NumBehaviors);

    // ---- Behavior 17 routes to the single-burst cadence template and binds the RingDissolveAdd look ----
    TestEqual(TEXT("behavior 17 routes to PS_CkParticles_Template_Single"),
        ck::particles::Get_BehaviorTemplateSystemObjectPath(17),
        ck::particles::Get_SingleBurstTemplateSystemObjectPath());

    TestEqual(TEXT("behavior 17 binds the RingDissolveAdd CkUsf look"),
        ck::particles::Get_BehaviorLookName(17), FName(TEXT("RingDissolveAdd")));

    // ---- Behavior 7 routes to its own cadence row, whose renderer overrides raise the VisTag ceiling ----
    TestEqual(TEXT("behavior 7 routes to PS_CkParticles_Template_Slash"),
        ck::particles::Get_BehaviorTemplateSystemObjectPath(7),
        ck::particles::Get_SlashTemplateSystemObjectPath());

    TestEqual(TEXT("behavior 7 binds no CkUsf look — its looks ride the row's renderers"),
        ck::particles::Get_BehaviorLookName(7), NAME_None);

    const auto MaxVisTag = ck::particles::Get_RosterVisTag_Max();
    TestTrue(TEXT("the roster VisTag maximum is at least the shared renderer set"),
        MaxVisTag >= ck::particles::SharedRendererVisTag_Max);

    // Every row-declared renderer must sit ABOVE the shared band, or it would silently steal a shared tag
    // from every other template's behaviors.
    for (const auto& Spec : ck::particles::Get_TemplateSpecs())
    {
        for (const auto& Renderer : Spec.RendererOverrides)
        {
            TestTrue(*FString::Printf(TEXT("row [%s] renderer VisTag %d is above the shared set"),
                Spec.AssetName, Renderer.VisTag),
                Renderer.VisTag > ck::particles::SharedRendererVisTag_Max);
            TestNotNull(*FString::Printf(TEXT("row [%s] renderer VisTag %d names a CkUsf look"),
                Spec.AssetName, Renderer.VisTag), Renderer.LookName);

            // A ribbon renderer carries no RendererVisibility, so it cannot be tag-gated: one listed among the
            // shared emitter's overrides would link EVERY particle on that template into ribbons. Ribbons live
            // on the row's second emitter, and nowhere else.
            TestTrue(*FString::Printf(TEXT("row [%s] renderer VisTag %d is not a Ribbon — those belong to the "
                "row's ribbon emitter"), Spec.AssetName, Renderer.VisTag),
                Renderer.Kind != ck::particles::ECk_ParticlesRenderer_Kind::Ribbon);

            // Only the Mesh kind indexes a generated mesh; the three sprite kinds must NOT name one, or the
            // row reads as if it declared a carrier the builder will never load.
            const auto IsMeshKind  = Renderer.Kind == ck::particles::ECk_ParticlesRenderer_Kind::Mesh;
            const auto NamesAMesh  = Renderer.MeshName != nullptr;
            TestTrue(*FString::Printf(TEXT("row [%s] renderer VisTag %d names a mesh only when it is a mesh kind"),
                Spec.AssetName, Renderer.VisTag), NamesAMesh == IsMeshKind);

            // Facing mode and the constant carrier scale reach a MESH renderer and nothing else — the builder
            // never writes them anywhere on a sprite path, so a sprite row that sets either is stating an intent
            // the template will not carry. Same silent-inertness class as a SubImageSize on a ribbon.
            TestTrue(*FString::Printf(TEXT("row [%s] renderer VisTag %d declares a mesh facing mode only when it "
                "is a mesh kind"), Spec.AssetName, Renderer.VisTag),
                IsMeshKind || Renderer.MeshFacingMode == ck::particles::ECk_ParticlesRenderer_MeshFacing::Default);
            TestTrue(*FString::Printf(TEXT("row [%s] renderer VisTag %d declares a mesh scale only when it is a "
                "mesh kind"), Spec.AssetName, Renderer.VisTag),
                IsMeshKind || Renderer.MeshScale == FVector::OneVector);

            // A partially declared grid divides one axis and not the other — the renderer would draw a sliver
            // of every frame instead of one frame. Either both axes are declared or neither is.
            const auto& Sheet = Renderer.SubImageSize;
            const auto  SheetIsDeclared = Sheet.X > 0 && Sheet.Y > 0;
            const auto  SheetIsAbsent   = Sheet.X == 0 && Sheet.Y == 0;
            TestTrue(*FString::Printf(TEXT("row [%s] renderer VisTag %d declares a whole SubImageSize grid or none [%d x %d]"),
                Spec.AssetName, Renderer.VisTag, Sheet.X, Sheet.Y), SheetIsDeclared || SheetIsAbsent);
        }

        // ---- The row's ribbon emitter ----
        // A declared one must be able to spawn: its emitter is built from an EMPTY stack, so with neither a burst
        // nor a rate it holds a renderer over a population that never exists. The converse is the same claim from
        // the other side — a cadence stated with no ribbon renderer spawns particles nothing draws.
        const auto& RibbonSpec = Spec.RibbonEmitter;
        const auto  RibbonDeclaresSpawn = RibbonSpec.BurstCount > 0 || RibbonSpec.SpawnRate > 0.0f;

        TestTrue(*FString::Printf(TEXT("row [%s] declares a ribbon spawn stack exactly when it declares a ribbon "
            "renderer"), Spec.AssetName), RibbonDeclaresSpawn == RibbonSpec.Get_IsDeclared());

        for (const auto& Renderer : RibbonSpec.Renderers)
        {
            TestTrue(*FString::Printf(TEXT("row [%s] ribbon-emitter renderer VisTag %d is the Ribbon kind"),
                Spec.AssetName, Renderer.VisTag),
                Renderer.Kind == ck::particles::ECk_ParticlesRenderer_Kind::Ribbon);

            TestNotNull(*FString::Printf(TEXT("row [%s] ribbon-emitter renderer VisTag %d names a CkUsf look"),
                Spec.AssetName, Renderer.VisTag), Renderer.LookName);

            // Ribbons have no carrier mesh — MeshIndex is the ribbon-id carrier there, not a mesh selector.
            TestNull(*FString::Printf(TEXT("row [%s] ribbon-emitter renderer VisTag %d names no mesh"),
                Spec.AssetName, Renderer.VisTag), Renderer.MeshName);

            // A ribbon renderer has no SubImageSize at all, so a declared grid would be silently inert.
            TestTrue(*FString::Printf(TEXT("row [%s] ribbon-emitter renderer VisTag %d declares no SubImageSize "
                "grid [%d x %d]"), Spec.AssetName, Renderer.VisTag, Renderer.SubImageSize.X, Renderer.SubImageSize.Y),
                Renderer.SubImageSize.X == 0 && Renderer.SubImageSize.Y == 0);

            // Nor a carrier, so neither of the mesh-renderer properties can reach it either.
            TestTrue(*FString::Printf(TEXT("row [%s] ribbon-emitter renderer VisTag %d declares no mesh facing "
                "mode"), Spec.AssetName, Renderer.VisTag),
                Renderer.MeshFacingMode == ck::particles::ECk_ParticlesRenderer_MeshFacing::Default);
            TestTrue(*FString::Printf(TEXT("row [%s] ribbon-emitter renderer VisTag %d declares no mesh scale"),
                Spec.AssetName, Renderer.VisTag), Renderer.MeshScale == FVector::OneVector);

            // Ribbon renderers allocate from the same VisTag ledger as every other row renderer: Niagara does not
            // gate on the tag, but the particles drawn by one still write it.
            TestTrue(*FString::Printf(TEXT("row [%s] ribbon-emitter renderer VisTag %d is above the shared set"),
                Spec.AssetName, Renderer.VisTag),
                Renderer.VisTag > ck::particles::SharedRendererVisTag_Max);
        }
    }

    // ---- The seed bank that tells the two emitters' populations apart ----
    // A ribbon particle's Seed is its UniqueID plus this base, so the bank must sit above any id the emitter can
    // reach AND leave base + id a positive int32 — a negative seed would read as the main emitter's bank.
    TestTrue(TEXT("the ribbon seed bank is positive"), ck::particles::RibbonSeedBase > 0);
    TestTrue(TEXT("every id below the ribbon seed bank has a distinct, still-positive twin above it"),
        TNumericLimits<int32>::Max() - ck::particles::RibbonSeedBase >= ck::particles::RibbonSeedBase - 1);

    // ---- Every id resolves to a NON-EMPTY path the cadence table actually declares ----
    // Catches the failure mode where a behavior silently spawns through a template that was never emitted.
    auto DeclaredTemplatePaths = TSet<FString>{};
    for (const auto& Spec : ck::particles::Get_TemplateSpecs())
    { DeclaredTemplatePaths.Add(ck::particles::Get_TemplateSystemObjectPath(Spec.AssetName)); }

    TestTrue(TEXT("the cadence table declares at least one template"), DeclaredTemplatePaths.Num() > 0);

    for (auto BehaviorId = 0; BehaviorId < ck::particles::NumBehaviors; ++BehaviorId)
    {
        const auto Path = ck::particles::Get_BehaviorTemplateSystemObjectPath(BehaviorId);

        TestFalse(*FString::Printf(TEXT("behavior %d resolves a non-empty template path"), BehaviorId),
            Path.IsEmpty());
        TestTrue(*FString::Printf(TEXT("behavior %d routes to a template the cadence table declares [%s]"),
            BehaviorId, *Path), DeclaredTemplatePaths.Contains(Path));
    }

    // ---- Every behavior produces renderable output across ages / lifetimes / seeds ----
    // The sweep is a few thousand evaluations, so it reports by ADDING an error per violation rather than
    // by calling an assertion per sample — a per-sample TestTrue would format thousands of strings for a
    // green run and drown a red one in noise.
    auto NumViolations = 0;
    auto NumEmitterAgeDependencies = 0;

    // A behavior may read the emitter clock ONLY when its cadence row declares a burst AND a rate: that is the
    // one shape where two populations share a template and must be told apart by spawn phase. The exemption is
    // DERIVED from the table rather than listed, so adding such a row cannot silently widen it — and the
    // exempted behaviors are then required to be dependent, or their split is inert.
    const auto Get_RowUsesSpawnPhase = [](int32 InBehaviorId) -> bool
    {
        const auto Path = ck::particles::Get_BehaviorTemplateSystemObjectPath(InBehaviorId);
        for (const auto& Spec : ck::particles::Get_TemplateSpecs())
        {
            if (ck::particles::Get_TemplateSystemObjectPath(Spec.AssetName) != Path)
            { continue; }

            return Spec.BurstCount > 0 && Spec.SpawnRate > 0.0f;
        }
        return false;
    };

    auto SpawnPhaseBehaviorsObserved = TSet<int32>{};
    // HDR is the whole point of an additive VFX pipeline: the emissive keys the behaviors carry run far above
    // 1 and nothing between the CPU mirror and Particles.Color may clamp them. Observing the brightest channel
    // across the sweep proves the float path is intact — a clamp anywhere would pin this at exactly 1.
    auto BrightestChannel = 0.0f;
    const auto Report = [&](bool InOk, const FString& InWhat) -> void
    {
        if (InOk)
        { return; }

        ++NumViolations;
        AddError(InWhat);
    };

    for (auto BehaviorId = 0; BehaviorId < ck::particles::NumBehaviors; ++BehaviorId)
    {
        // One error per behavior is enough to name the offender; the count carries the scale.
        auto ReportedEmitterAgeDependency = false;

        for (const auto Lifetime : { 0.4f, 1.1f, 1.2f, 3.0f })
        {
            for (const auto Seed : { 0, 1, 17, 991, 65535 })
            {
                for (auto Step = 0; Step <= 10; ++Step)
                {
                    const auto NormalizedAge = static_cast<float>(Step) / 10.0f;

                    constexpr auto DeltaTime = 1.0f / 60.0f;
                    const auto Out = UCkParticles_DataInterface::Execute_Stage_CPU(
                        BehaviorId, DeltaTime, NormalizedAge * Lifetime, Lifetime,
                        FVector3f::ZeroVector, FVector3f::ZeroVector, Seed, kReferenceEmitterAge);

                    for (const auto EmitterAge : { 0.37f, 2.5f, 41.0f })
                    {
                        const auto Shifted = UCkParticles_DataInterface::Execute_Stage_CPU(
                            BehaviorId, DeltaTime, NormalizedAge * Lifetime, Lifetime,
                            FVector3f::ZeroVector, FVector3f::ZeroVector, Seed, EmitterAge);

                        if (Is_Identical(Out, Shifted))
                        { continue; }

                        if (Get_RowUsesSpawnPhase(BehaviorId))
                        {
                            SpawnPhaseBehaviorsObserved.Add(BehaviorId);
                            continue;
                        }

                        ++NumEmitterAgeDependencies;

                        if (ReportedEmitterAgeDependency)
                        { continue; }

                        ReportedEmitterAgeDependency = true;
                        AddError(FString::Printf(
                            TEXT("behavior %d (lifetime %.2f, seed %d, t %.1f): output moved when the emitter ")
                            TEXT("clock moved to %.2f — only a burst+rate row may read EmitterAge"),
                            BehaviorId, Lifetime, Seed, NormalizedAge, EmitterAge));
                    }

                    const auto Finite =
                        Is_Finite(Out.Position) && Is_Finite(Out.Velocity) && Is_Finite(Out.Color) &&
                        Is_Finite(Out.Size) && Is_Finite(Out.Scale) && Is_Finite(Out.Dynamic) &&
                        FMath::IsFinite(Out.Rotation) && FMath::IsFinite(Out.SubImageIndex);

                    BrightestChannel = FMath::Max(BrightestChannel,
                        FMath::Max3(Out.Color.R, Out.Color.G, Out.Color.B));

                    // A negative frame index samples off the front of the sheet; every renderer that reads it
                    // divides a grid whose frames start at 0.
                    const auto SubImageIsSane = Out.SubImageIndex >= 0.0f;

                    // A negative quad extent flips winding rather than shrinking — never intended.
                    const auto SizeIsSane = Out.Size.X >= 0.0f && Out.Size.Y >= 0.0f;

                    // Alpha is a blend factor: negative would SUBTRACT. The upper bound is deliberately not
                    // asserted — behavior 13's rare flash branch scales alpha by 1.5 (the renderer clamps it),
                    // so a <= 1 assertion would red on pre-existing, harmless behavior. Recorded in the recipe.
                    const auto AlphaIsSane = Out.Color.A >= 0.0f;

                    // A VisTag outside the renderer set draws with NO renderer — invisible, and silent.
                    const auto VisTagIsSane = Out.VisTag >= 0 && Out.VisTag <= MaxVisTag;

                    const auto MeshIndexIsSane = Out.VisTag != kMeshVisTag ||
                        (Out.MeshIndex >= 0 && Out.MeshIndex <= kMaxMeshIndex);

                    // A degenerate pair does not fail visibly: CustomAlignment silently falls back to
                    // Unaligned and the sprite collapses.
                    const auto SpriteVectorsAreSane = Out.VisTag != kCustomFacingVisTag ||
                        (Out.SpriteAlignment.SizeSquared() > kTolerance && Out.SpriteFacing.SizeSquared() > kTolerance);

                    const auto AllSane = Finite && SizeIsSane && AlphaIsSane && VisTagIsSane &&
                        MeshIndexIsSane && SpriteVectorsAreSane && SubImageIsSane &&
                        Out.Orientation.IsNormalized();

                    if (AllSane)
                    { continue; }

                    const auto Context = FString::Printf(
                        TEXT("behavior %d (lifetime %.2f, seed %d, t %.1f)"),
                        BehaviorId, Lifetime, Seed, NormalizedAge);

                    Report(Finite,                 FString::Printf(TEXT("%s: produced a non-finite output"), *Context));
                    Report(SizeIsSane,             FString::Printf(TEXT("%s: size is negative [%f, %f]"), *Context, Out.Size.X, Out.Size.Y));
                    Report(AlphaIsSane,            FString::Printf(TEXT("%s: alpha is negative [%f]"), *Context, Out.Color.A));
                    Report(VisTagIsSane,           FString::Printf(TEXT("%s: VisTag %d is outside the renderer set"), *Context, Out.VisTag));
                    Report(MeshIndexIsSane,        FString::Printf(TEXT("%s: MeshIndex %d is outside the carrier mesh set"), *Context, Out.MeshIndex));
                    Report(SpriteVectorsAreSane,   FString::Printf(TEXT("%s: degenerate sprite alignment/facing pair on VisTag 4"), *Context));
                    Report(SubImageIsSane,         FString::Printf(TEXT("%s: SubImageIndex %f is negative"), *Context, Out.SubImageIndex));
                    Report(Out.Orientation.IsNormalized(), FString::Printf(TEXT("%s: orientation quaternion is not normalized"), *Context));
                }
            }
        }
    }

    TestEqual(TEXT("no behavior produced unrenderable output across the age/lifetime/seed sweep"),
        NumViolations, 0);

    TestEqual(TEXT("no behavior outside a burst+rate row reads EmitterAge — for them it is threaded, not read"),
        NumEmitterAgeDependencies, 0);

    // The other half of the same claim: a row that declares BOTH stacks exists to split two populations by
    // spawn phase, so a behavior on one that is INDEPENDENT of the emitter clock has an inert split.
    for (auto BehaviorId = 0; BehaviorId < ck::particles::NumBehaviors; ++BehaviorId)
    {
        if (NOT Get_RowUsesSpawnPhase(BehaviorId))
        { continue; }

        TestTrue(*FString::Printf(
            TEXT("behavior %d rides a burst+rate row, so its output MUST move with the emitter clock"), BehaviorId),
            SpawnPhaseBehaviorsObserved.Contains(BehaviorId));
    }

    // Well above any plausible clamp point, and far below the brightest key the roster actually carries
    // (behavior 15 emits 135) — so this fails on a clamp, not on a behavior being retuned.
    constexpr auto HdrKeyFloor = 5.0f;
    TestTrue(*FString::Printf(TEXT("HDR colour keys survive the stage pipeline unclamped (brightest observed %f)"),
        BrightestChannel), BrightestChannel > HdrKeyFloor);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
