#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkJolt/CkJolt_Utils.h"
#include "CkJolt/StaticWorld/CkJoltBakeExtraction.h"

#include "Components/StaticMeshComponent.h"
#include "Engine/StaticMesh.h"
#include "Engine/StaticMeshActor.h"
#include "Engine/World.h"
#include "PhysicsEngine/BodySetup.h"
#include "Renderers/Text3DRendererBase.h"
#include "Text3DComponent.h"
#include "Tests/AutomationCommon.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_jolt_text3d_glyph_exclusion
{
    constexpr auto kTestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;

    static auto Spawn_AuthoredMeshActor(UWorld& InWorld) -> AStaticMeshActor*
    {
        auto* Cube = LoadObject<UStaticMesh>(nullptr, TEXT("/Engine/BasicShapes/Cube.Cube"));
        if (Cube == nullptr)
        { return nullptr; }

        auto* Actor = InWorld.SpawnActor<AStaticMeshActor>();
        if (Actor == nullptr)
        { return nullptr; }

        auto* Mesh = Actor->GetStaticMeshComponent();
        Mesh->SetMobility(EComponentMobility::Static);
        Mesh->SetStaticMesh(Cube);
        Mesh->SetCollisionProfileName(TEXT("BlockAll"));
        Actor->RegisterAllComponents();
        return Actor;
    }

    static auto Add_RealText3DGlyph(AStaticMeshActor& InActor) -> UStaticMeshComponent*
    {
        auto* Text = NewObject<UText3DComponent>(&InActor, TEXT("Text3D"));
        InActor.AddInstanceComponent(Text);
        Text->SetMobility(EComponentMobility::Static);
        Text->SetupAttachment(InActor.GetRootComponent());
        Text->RegisterComponent();
        Text->SetText(FText::FromString(TEXT("A")));
        Text->RequestUpdate(EText3DRendererFlags::All, /*bInImmediate*/ true);

        auto* const Renderer = Text->GetTextRenderer();
        if (Renderer == nullptr)
        { return nullptr; }

        auto* Glyph = static_cast<UStaticMeshComponent*>(nullptr);
        InActor.ForEachComponent<UStaticMeshComponent>(false,
            [&Glyph, Renderer](UStaticMeshComponent* InComponent)
            {
                if (InComponent != nullptr && InComponent->GetOuter() == Renderer)
                { Glyph = InComponent; }
            });

        return Glyph;
    }

    static auto Extract(
        AActor& InActor,
        TArray<ck::jolt::bake::FCk_Jolt_ExtractedBody>& OutBodies,
        ck::jolt::bake::FCk_Jolt_ExtractionStats& OutStats,
        const ck::jolt::bake::ECk_Jolt_ExtractionPolicy InPolicy) -> int32
    {
        auto Cache = ck::jolt::bake::FCk_Jolt_ShapeCache{};
        return ck::jolt::bake::ExtractActor(InActor, Cache, OutBodies, {}, InPolicy, &OutStats);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Jolt_BakeExtraction_Text3DGlyphExclusion,
    "Ck.Jolt.BakeExtraction.Text3DGlyphExclusion",
    ck_test_jolt_text3d_glyph_exclusion::kTestFlags)

bool FCkTest_Jolt_BakeExtraction_Text3DGlyphExclusion::RunTest(const FString& Parameters)
{
    using namespace ck::jolt::bake;
    using namespace ck_test_jolt_text3d_glyph_exclusion;

    const ck::jolt::FCk_Jolt_ScopedGlobalInit ScopedJolt{};

    auto WorldWrapper = FTestWorldWrapper{};
    if (NOT TestTrue(TEXT("temporary editor world is created"), WorldWrapper.CreateTestWorld(EWorldType::Editor)))
    { return false; }

    auto* const Actor = Spawn_AuthoredMeshActor(*WorldWrapper.GetTestWorld());
    if (NOT TestNotNull(TEXT("authored mesh actor is created"), Actor))
    { return false; }

    const auto Filter = FCk_Jolt_BakeFilter{};
    const auto SourceBeforeGlyph = ComputeSourceHash(*Actor, Filter);
    const auto RuntimeBeforeGlyph = ComputeRuntimeCheckHash(*Actor, Filter);

    auto* const Glyph = Add_RealText3DGlyph(*Actor);
    if (NOT TestNotNull(TEXT("Text3D generated a real renderer-owned glyph"), Glyph))
    { return false; }

    auto* const Renderer = Glyph->GetTypedOuter<UText3DRendererBase>();
    TestNotNull(TEXT("glyph has a Text3D renderer outer"), Renderer);
    TestTrue(TEXT("glyph is registered"), Glyph->IsRegistered());
    TestTrue(TEXT("glyph has collision enabled"),
        Glyph->GetCollisionEnabled() != ECollisionEnabled::NoCollision);
    TestFalse(TEXT("glyph does not simulate physics"), Glyph->IsSimulatingPhysics());
    TestNotNull(TEXT("glyph has generated static-mesh geometry"), Glyph->GetStaticMesh().Get());
    const auto* const GlyphBodySetup = Glyph->GetStaticMesh() != nullptr
        ? Glyph->GetStaticMesh()->GetBodySetup()
        : nullptr;
    if (TestNotNull(TEXT("glyph mesh has collision geometry"), GlyphBodySetup))
    {
        TestEqual(TEXT("glyph mesh uses the renderer-generated complex collision"),
            static_cast<uint8>(GlyphBodySetup->GetCollisionTraceFlag()),
            static_cast<uint8>(ECollisionTraceFlag::CTF_UseComplexAsSimple));
    }

    const auto SourceAfterGlyph = ComputeSourceHash(*Actor, Filter);
    const auto RuntimeAfterGlyph = ComputeRuntimeCheckHash(*Actor, Filter);
    TestEqual(TEXT("source hash ignores renderer-owned glyph generation"), SourceBeforeGlyph, SourceAfterGlyph);
    TestEqual(TEXT("runtime hash ignores renderer-owned glyph generation"), RuntimeBeforeGlyph, RuntimeAfterGlyph);

    auto GlyphBodies = TArray<FCk_Jolt_ExtractedBody>{};
    auto GlyphCache = FCk_Jolt_ShapeCache{};
    TestEqual(TEXT("direct component extraction excludes the glyph"), ExtractComponent(*Glyph, GlyphCache, GlyphBodies, Filter), 0);
    TestEqual(TEXT("direct component extraction produces no glyph body"), GlyphBodies.Num(), 0);

    auto Bodies = TArray<FCk_Jolt_ExtractedBody>{};
    auto Stats = FCk_Jolt_ExtractionStats{};
    TestEqual(TEXT("level sweep retains only the authored mesh"), Extract(*Actor, Bodies, Stats,
        ECk_Jolt_ExtractionPolicy::LevelSweep), 1);
    TestEqual(TEXT("authored mesh and generated glyph are considered"), Stats._NumComponentsConsidered, 2);
    if (NOT TestEqual(TEXT("one level-sweep body is retained"), Bodies.Num(), 1))
    { return false; }
    TestTrue(TEXT("level-sweep body belongs to the authored mesh"),
        Bodies[0]._SourceComponent.Get() == static_cast<const UPrimitiveComponent*>(Actor->GetStaticMeshComponent()));

    auto ExplicitBodies = TArray<FCk_Jolt_ExtractedBody>{};
    auto ExplicitStats = FCk_Jolt_ExtractionStats{};
    TestEqual(TEXT("explicit actor extraction also excludes the glyph"), Extract(*Actor, ExplicitBodies, ExplicitStats,
        ECk_Jolt_ExtractionPolicy::ExplicitActor), 1);
    if (NOT TestEqual(TEXT("one explicit-actor body is retained"), ExplicitBodies.Num(), 1))
    { return false; }
    TestTrue(TEXT("explicit-actor body belongs to the authored mesh"),
        ExplicitBodies[0]._SourceComponent.Get() == static_cast<const UPrimitiveComponent*>(Actor->GetStaticMeshComponent()));

    Actor->GetStaticMeshComponent()->SetRelativeLocation(FVector{100.0f, 0.0f, 0.0f});
    TestNotEqual(TEXT("authored mesh transform still changes source hash"),
        SourceAfterGlyph, ComputeSourceHash(*Actor, Filter));
    TestNotEqual(TEXT("authored mesh transform still changes runtime hash"),
        RuntimeAfterGlyph, ComputeRuntimeCheckHash(*Actor, Filter));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif
