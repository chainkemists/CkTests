// Roster-wide sanity gate for CkParticles.
//
// Two claims, both roster-driven so adding a behavior does not need this file edited:
//   1. The roster METADATA is coherent — one size definition, every id routes to a template the cadence
//      table actually declares, and the behaviors that bind a CkUsf look bind the expected one.
//   2. Every behavior, across ages / lifetimes / seeds, produces RENDERABLE output — finite numbers, a
//      non-negative size, a VisTag the template has a renderer for, a mesh index the carrier set contains,
//      and (on the custom-facing tag) a non-degenerate alignment/facing pair.
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

    // ---- Roster size has ONE definition, and it is the one behavior 19 was added to ----
    TestEqual(TEXT("NumBehaviors is 20 (ids 0..19, ArrowProjectile last)"), ck::particles::NumBehaviors, 20);
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
        }
    }

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
    const auto Report = [&](bool InOk, const FString& InWhat) -> void
    {
        if (InOk)
        { return; }

        ++NumViolations;
        AddError(InWhat);
    };

    for (auto BehaviorId = 0; BehaviorId < ck::particles::NumBehaviors; ++BehaviorId)
    {
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
                        FVector3f::ZeroVector, FVector3f::ZeroVector, Seed);

                    const auto Finite =
                        Is_Finite(Out.Position) && Is_Finite(Out.Velocity) && Is_Finite(Out.Color) &&
                        Is_Finite(Out.Size) && Is_Finite(Out.Scale) && Is_Finite(Out.Dynamic) &&
                        FMath::IsFinite(Out.Rotation);

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
                        MeshIndexIsSane && SpriteVectorsAreSane && Out.Orientation.IsNormalized();

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
                    Report(Out.Orientation.IsNormalized(), FString::Printf(TEXT("%s: orientation quaternion is not normalized"), *Context));
                }
            }
        }
    }

    TestEqual(TEXT("no behavior produced unrenderable output across the age/lifetime/seed sweep"),
        NumViolations, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
