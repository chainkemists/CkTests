#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkCore/Format/CkFormat.h"

#include "CkJolt/Query/CkJoltQuery_Data.h"
#include "CkJolt/Query/CkJoltQuery_Utils.h"
#include "CkJolt/StaticWorld/CkJoltStaticWorld_Utils.h"

#include "CkTests/CkTests_Log.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include <CollisionQueryParams.h>
#include <Components/StaticMeshComponent.h>
#include <Engine/StaticMesh.h>
#include <Engine/StaticMeshActor.h>
#include <Engine/World.h>

// --------------------------------------------------------------------------------------------------------------------
// Geometry-parity fuzz sampler (jolt-collision-world Phase 5, item 2).
//
// Builds a field of engine-basic-shape static actors (Cube -> box AggGeom, Sphere -> sphere AggGeom), baked into the
// Jolt static world via Request_BakeActor and simultaneously present as Chaos bodies (same authored simple collision).
// A seeded FRandomStream then fires 1024 rays + 256 sweeps (box/sphere/capsule) + 256 overlaps (box/sphere/capsule),
// running each against BOTH engines and asserting parity: hit/miss agreement is EXACT, impact points agree, and hit
// normals are near-parallel. Mismatches are bucketed per query-primitive type; the test fails iff the total is non-zero,
// with the per-bucket breakdown in the message.
//
// Mirrors the AS parity seeds (CkAutoTest_CkJolt_StaticBake_SimpleBox_RaycastMatchesChaos /
// _Query_SweepByChannel_MatchesChaosSweep): same content (BasicShapes, Movable, BlockAll, Request_BakeActor), same
// ECC_Visibility channel, same Chaos-vs-Jolt comparison — scaled up into a randomized fuzz.
//
// Sample construction is guaranteed-answer by design (a HIT sample casts through solid geometry; a MISS sample stays in
// the far empty shell) so "hit/miss EXACT" fails only on a genuine parity gap, not on numerically-undefined grazing/
// tangent cases. Sweeps approach along a cardinal axis so contact lands on a flat face (clean normal), never an edge/
// corner (where the two engines' contact normals legitimately diverge). The field lives far from the origin so the
// map's own default content is never sampled.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_jolt_parity
{
    // Cross-latent-command state (mirrors the lifecycle spec's GEntities/GBaseline pattern): the field survives between
    // the build RunOnServer and the later sampling AssertCondition. Reset at test start.
    struct FParityPrim
    {
        ECk_Jolt_ShapeType _Type = ECk_Jolt_ShapeType::Box; // Box or Sphere only (the static geometry)
        FVector            _Center = FVector::ZeroVector;
        double             _HalfDim = 50.0;                 // box half-extent (uniform) or sphere radius, world-space
    };

    static TArray<FParityPrim>       GField;
    static TArray<AStaticMeshActor*> GActors;
    static int32                     GBakedBodies = 0;

    const auto EntryMapPath = FString{TEXT("/Engine/Maps/Entry")};

    // Field placement: far from origin so the /Engine/Maps/Entry default content is never in a sampled segment.
    const auto     FieldCenter = FVector{0.0, 40000.0, 1000.0};
    constexpr auto FieldRadius = 4000.0; // conservative bound on the whole field (used to place far starts/misses)

    constexpr int32 RayCount     = 1024;
    constexpr int32 SweepCount   = 256;
    constexpr int32 OverlapCount = 256;

    // Rays: exact impact-point parity (1uu) — a ray enters a convex primitive at a single well-defined point, so the
    // 3D impact point is unambiguous (validated: 1024 rays, 0 mismatches).
    //
    // Sweeps: parity is asserted on the STOP DISTANCE (how far the shape swept before contact) + the contact NORMAL,
    // NOT the raw 3D contact point. A swept SPHERE touches a box face at one point (both engines agree), but a swept
    // BOX/CAPSULE meets a flat face along a face/edge CONTACT REGION where the representative contact point is
    // mathematically ambiguous — the two engines legitimately pick different points on the SAME contact plane. The
    // physically-defined, engine-independent quantities are the sweep travel distance and the surface normal; those
    // are what parity means for a shape cast. (Diagnostics below print the observed max stop-distance delta / min
    // normal dot so the stop-distance parity is visible even on a clean run.)
    constexpr double RayImpactTolCm  = 1.0;
    constexpr double SweepStopTolCm  = 1.0;
    constexpr double NormalDotMin    = 0.95;

    // ~60% of samples target solid geometry, the rest are guaranteed misses — a mix that exercises both the "both hit"
    // impact/normal path and the "both miss" agreement path.
    constexpr float HitFraction = 0.6f;

    constexpr auto kTestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;
    constexpr int32 SettleFrames = 30;

    // ----------------------------------------------------------------------------------------------------------------

    static auto Get_JoltFilter() -> FCk_Jolt_QueryFilter
    {
        auto Filter = FCk_Jolt_QueryFilter{};
        Filter.Set_Channel(ECC_Visibility);
        Filter.Set_MinResponse(ECk_Jolt_PairInteraction::Block);
        return Filter;
    }

    static auto Get_ChaosQueryParams() -> FCollisionQueryParams
    {
        // Simple collision (bTraceComplex = false) matches the Jolt-side simple box/sphere shapes.
        auto Params = FCollisionQueryParams{SCENE_QUERY_STAT(CkJoltParitySampler), /*bTraceComplex=*/false};
        return Params;
    }

    // One of the six cardinal axes, chosen by the stream.
    static auto Random_CardinalAxis(FRandomStream& InRng) -> FVector
    {
        static const FVector Axes[] = {
            FVector::ForwardVector, -FVector::ForwardVector,
            FVector::RightVector,   -FVector::RightVector,
            FVector::UpVector,      -FVector::UpVector};
        return Axes[InRng.RandRange(0, 5)];
    }

    // Build a matched (FCollisionShape, FCk_Jolt_ShapeDimensions) pair for a sweep/overlap query primitive. Small
    // relative to the field geometry so a HIT contact resolves against the target primitive's surface. Capsule: UE's
    // MakeCapsule half-height is tip-to-tip/2 (cylinder-half + radius); the Jolt shape's _HalfHeight is the cylinder
    // section only (matching FKSphylElem) — so UE total = Jolt _HalfHeight + _Radius.
    static auto Make_QueryShapePair(int32 InTypeIndex, FCollisionShape& OutChaos, FCk_Jolt_ShapeDimensions& OutJolt)
        -> const TCHAR*
    {
        constexpr float BoxHalf     = 12.0f;
        constexpr float SphereR     = 12.0f;
        constexpr float CapsuleR    = 10.0f;
        constexpr float CapsuleCylH = 14.0f; // cylinder-section half-height (Jolt convention)

        switch (InTypeIndex)
        {
            case 0:
            {
                OutChaos = FCollisionShape::MakeBox(FVector{BoxHalf});
                OutJolt = FCk_Jolt_ShapeDimensions{ECk_Jolt_ShapeType::Box};
                OutJolt.Set_HalfExtents(FVector{BoxHalf});
                return TEXT("Box");
            }
            case 1:
            {
                OutChaos = FCollisionShape::MakeSphere(SphereR);
                OutJolt = FCk_Jolt_ShapeDimensions{ECk_Jolt_ShapeType::Sphere};
                OutJolt.Set_Radius(SphereR);
                return TEXT("Sphere");
            }
            default:
            {
                OutChaos = FCollisionShape::MakeCapsule(CapsuleR, CapsuleCylH + CapsuleR);
                OutJolt = FCk_Jolt_ShapeDimensions{ECk_Jolt_ShapeType::Capsule};
                OutJolt.Set_Radius(CapsuleR);
                OutJolt.Set_HalfHeight(CapsuleCylH);
                return TEXT("Capsule");
            }
        }
    }

    // ----------------------------------------------------------------------------------------------------------------

    static auto Build_Field(FRandomStream& InRng) -> void
    {
        GField.Reset();

        // A 4x3 lattice of well-separated primitives, alternating box/sphere with jittered size. Deterministic from
        // the seed. Separation is not required for correctness (parity is agreement, not identity) but keeps clean
        // empty regions for the miss samples.
        constexpr int32 Cols = 4;
        constexpr int32 Rows = 3;
        constexpr double Spacing = 1500.0;

        for (auto Row = 0; Row < Rows; ++Row)
        {
            for (auto Col = 0; Col < Cols; ++Col)
            {
                const auto Index = Row * Cols + Col;

                auto Prim = FParityPrim{};
                Prim._Type = (Index % 2 == 0) ? ECk_Jolt_ShapeType::Box : ECk_Jolt_ShapeType::Sphere;
                Prim._Center = FieldCenter + FVector{
                    (Col - (Cols - 1) * 0.5) * Spacing,
                    (Row - (Rows - 1) * 0.5) * Spacing,
                    InRng.FRandRange(-200.0, 200.0)};
                Prim._HalfDim = InRng.FRandRange(60.0, 140.0);

                GField.Emplace(Prim);
            }
        }
    }

    static auto Spawn_And_Bake(UWorld* InWorld) -> void
    {
        GActors.Reset();
        GBakedBodies = 0;

        auto* CubeMesh = LoadObject<UStaticMesh>(nullptr, TEXT("/Engine/BasicShapes/Cube.Cube"));
        auto* SphereMesh = LoadObject<UStaticMesh>(nullptr, TEXT("/Engine/BasicShapes/Sphere.Sphere"));
        if (CubeMesh == nullptr || SphereMesh == nullptr)
        { return; }

        for (const auto& Prim : GField)
        {
            // BasicShapes are 100uu -> half 50uu at scale 1; scale to reach the desired half-dim (uniform, so a sphere
            // stays a sphere and a box stays an axis-aligned box).
            const auto Scale = Prim._HalfDim / 50.0;

            auto SpawnXform = FTransform{FQuat::Identity, Prim._Center, FVector{Scale}};

            auto* Actor = InWorld->SpawnActor<AStaticMeshActor>(AStaticMeshActor::StaticClass(), SpawnXform);
            if (Actor == nullptr)
            { continue; }

            auto* Comp = Actor->GetStaticMeshComponent();
            Comp->SetMobility(EComponentMobility::Movable);
            Comp->SetStaticMesh(Prim._Type == ECk_Jolt_ShapeType::Box ? CubeMesh : SphereMesh);
            Comp->SetCollisionProfileName(TEXT("BlockAll"));

            GBakedBodies += UCk_Utils_JoltStaticWorld_UE::Request_BakeActor(Actor);
            GActors.Emplace(Actor);
        }
    }

    static auto Teardown_Field() -> void
    {
        for (auto* Actor : GActors)
        {
            if (Actor == nullptr)
            { continue; }
            UCk_Utils_JoltStaticWorld_UE::Request_RemoveActor(Actor);
            Actor->Destroy();
        }
        GActors.Reset();
        GField.Reset();
    }

    // ----------------------------------------------------------------------------------------------------------------

    struct FCounters
    {
        int32 Ray = 0;
        int32 SweepBox = 0, SweepSphere = 0, SweepCapsule = 0;
        int32 OverlapBox = 0, OverlapSphere = 0, OverlapCapsule = 0;

        // Diagnostics (not mismatches): the worst stop-distance disagreement and worst normal alignment seen across
        // all "both hit" sweeps — printed so stop-distance parity is visible even when the test is clean.
        double MaxSweepStopDeltaCm = 0.0;
        double MinSweepNormalDot = 1.0;

        auto Total() const -> int32
        {
            return Ray + SweepBox + SweepSphere + SweepCapsule + OverlapBox + OverlapSphere + OverlapCapsule;
        }

        auto Breakdown() const -> FString
        {
            return ck::Format_UE(TEXT("Ray={} SweepBox={} SweepSphere={} SweepCapsule={} OverlapBox={} OverlapSphere={} OverlapCapsule={}"),
                Ray, SweepBox, SweepSphere, SweepCapsule, OverlapBox, OverlapSphere, OverlapCapsule);
        }
    };

    static auto Sample_Rays(UWorld* InWorld, FRandomStream& InRng, FCounters& OutCounters) -> void
    {
        const auto Filter = Get_JoltFilter();

        for (auto Index = 0; Index < RayCount; ++Index)
        {
            const auto WantHit = InRng.FRand() < HitFraction;

            auto Start = FVector::ZeroVector;
            auto End = FVector::ZeroVector;

            if (WantHit)
            {
                const auto& Prim = GField[InRng.RandRange(0, GField.Num() - 1)];
                const auto Dir = InRng.GetUnitVector();
                // Vary the target within the primitive core so impacts land across the whole face, not just the center.
                const auto Target = Prim._Center + InRng.GetUnitVector() * (Prim._HalfDim * 0.3);
                Start = Prim._Center + Dir * (FieldRadius * 4.0);
                End = Target - (Start - Target).GetSafeNormal() * (Prim._HalfDim * 0.5); // through the core and just past
            }
            else
            {
                const auto Dir = InRng.GetUnitVector();
                Start = FieldCenter + Dir * (FieldRadius * 6.0);
                End = Start + Dir * (FieldRadius * 2.0); // outward into the empty shell
            }

            auto ChaosHit = FHitResult{};
            const auto bChaos = InWorld->LineTraceSingleByChannel(ChaosHit, Start, End, ECC_Visibility, Get_ChaosQueryParams());

            const auto JoltHit = UCk_Utils_JoltQuery_UE::Get_RayCast(InWorld, Start, End, Filter);
            const auto bJolt = JoltHit.Get_HasHit();

            if (bChaos != bJolt)
            {
                ++OutCounters.Ray;
                ck::tests::Display(TEXT("[Parity][Ray {}] hit/miss disagree: Chaos={} Jolt={} Start={} End={}"),
                    Index, bChaos, bJolt, Start, End);
                continue;
            }

            if (NOT bChaos)
            { continue; }

            const auto Dist = FVector::Dist(ChaosHit.ImpactPoint, JoltHit.Get_Position());
            const auto Dot = FVector::DotProduct(ChaosHit.ImpactNormal.GetSafeNormal(), JoltHit.Get_Normal().GetSafeNormal());

            if (Dist > RayImpactTolCm || Dot < NormalDotMin)
            {
                ++OutCounters.Ray;
                ck::tests::Verbose(TEXT("[Parity][Ray {}] impact/normal: dist={} dot={} ChaosPos={} JoltPos={}"),
                    Index, Dist, Dot, FVector{ChaosHit.ImpactPoint}, JoltHit.Get_Position());
            }
        }
    }

    static auto Sample_Sweeps(UWorld* InWorld, FRandomStream& InRng, FCounters& OutCounters) -> void
    {
        const auto Filter = Get_JoltFilter();

        for (auto Index = 0; Index < SweepCount; ++Index)
        {
            const auto TypeIndex = Index % 3;

            auto ChaosShape = FCollisionShape{};
            auto JoltShape = FCk_Jolt_ShapeDimensions{};
            Make_QueryShapePair(TypeIndex, ChaosShape, JoltShape);

            const auto WantHit = InRng.FRand() < HitFraction;

            auto Start = FVector::ZeroVector;
            auto End = FVector::ZeroVector;

            if (WantHit)
            {
                const auto& Prim = GField[InRng.RandRange(0, GField.Num() - 1)];
                // Approach along a cardinal axis so the contact lands on a flat face (box) or the sphere surface —
                // never an edge/corner where the two engines' contact normals legitimately diverge. The approach is
                // LOCAL (just outside the target, shorter than the 1500cm inter-primitive spacing) so the wide swept
                // shape only ever interacts with the intended primitive — never grazes intervening geometry mid-path.
                const auto Axis = Random_CardinalAxis(InRng);
                Start = Prim._Center + Axis * (Prim._HalfDim + 700.0);
                End = Prim._Center; // sweep into the core: the shape's leading surface contacts the primitive
            }
            else
            {
                const auto Dir = InRng.GetUnitVector();
                Start = FieldCenter + Dir * (FieldRadius * 6.0);
                End = Start + Dir * (FieldRadius * 2.0);
            }

            auto ChaosHit = FHitResult{};
            const auto bChaos = InWorld->SweepSingleByChannel(
                ChaosHit, Start, End, FQuat::Identity, ECC_Visibility, ChaosShape, Get_ChaosQueryParams());

            const auto JoltHit = UCk_Utils_JoltQuery_UE::Get_ShapeCast(
                InWorld, Start, End, FRotator::ZeroRotator, JoltShape, Filter);
            const auto bJolt = JoltHit.Get_HasHit();

            auto& Bucket = (TypeIndex == 0) ? OutCounters.SweepBox
                         : (TypeIndex == 1) ? OutCounters.SweepSphere
                                            : OutCounters.SweepCapsule;

            if (bChaos != bJolt)
            {
                ++Bucket;
                ck::tests::Display(TEXT("[Parity][Sweep {} type {}] hit/miss disagree: Chaos={} Jolt={} Start={} End={}"),
                    Index, TypeIndex, bChaos, bJolt, Start, End);
                continue;
            }

            if (NOT bChaos)
            { continue; }

            // Stop distance: how far the shape swept before contact. Chaos reports it directly; Jolt reports a fraction
            // of the sweep. This is the engine-independent "where does the sweep stop" quantity (unlike the 3D contact
            // point on a flat face, which each engine parameterizes differently).
            const auto SweepLen = FVector::Dist(Start, End);
            const auto StopDelta = FMath::Abs(static_cast<double>(ChaosHit.Distance) - JoltHit.Get_Fraction() * SweepLen);
            const auto Dot = FVector::DotProduct(ChaosHit.ImpactNormal.GetSafeNormal(), JoltHit.Get_Normal().GetSafeNormal());

            OutCounters.MaxSweepStopDeltaCm = FMath::Max(OutCounters.MaxSweepStopDeltaCm, StopDelta);
            OutCounters.MinSweepNormalDot = FMath::Min(OutCounters.MinSweepNormalDot, Dot);

            if (StopDelta > SweepStopTolCm || Dot < NormalDotMin)
            {
                ++Bucket;
                ck::tests::Verbose(TEXT("[Parity][Sweep {} type {}] stop/normal: stopDelta={} dot={} ChaosDist={} JoltDist={}"),
                    Index, TypeIndex, StopDelta, Dot, static_cast<double>(ChaosHit.Distance), JoltHit.Get_Fraction() * SweepLen);
            }
        }
    }

    static auto Sample_Overlaps(UWorld* InWorld, FRandomStream& InRng, FCounters& OutCounters) -> void
    {
        const auto Filter = Get_JoltFilter();

        for (auto Index = 0; Index < OverlapCount; ++Index)
        {
            const auto TypeIndex = Index % 3;

            auto ChaosShape = FCollisionShape{};
            auto JoltShape = FCk_Jolt_ShapeDimensions{};
            Make_QueryShapePair(TypeIndex, ChaosShape, JoltShape);

            const auto WantHit = InRng.FRand() < HitFraction;

            const auto Location = WantHit
                ? GField[InRng.RandRange(0, GField.Num() - 1)]._Center               // deep inside -> guaranteed overlap
                : FieldCenter + InRng.GetUnitVector() * (FieldRadius * 6.0);          // far empty -> guaranteed no overlap

            const auto bChaos = InWorld->OverlapBlockingTestByChannel(
                Location, FQuat::Identity, ECC_Visibility, ChaosShape, Get_ChaosQueryParams());

            const auto JoltHits = UCk_Utils_JoltQuery_UE::Get_Overlap(
                InWorld, Location, FRotator::ZeroRotator, JoltShape, Filter);
            const auto bJolt = JoltHits.Num() > 0;

            if (bChaos != bJolt)
            {
                auto& Bucket = (TypeIndex == 0) ? OutCounters.OverlapBox
                             : (TypeIndex == 1) ? OutCounters.OverlapSphere
                                                : OutCounters.OverlapCapsule;
                ++Bucket;
                ck::tests::Display(TEXT("[Parity][Overlap {} type {}] disagree: Chaos={} Jolt={} Loc={}"),
                    Index, TypeIndex, bChaos, bJolt, Location);
            }
        }
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Jolt_GeometryParitySampler_ChaosVsJolt,
    "Ck.Jolt.Query.GeometryParitySampler.ChaosVsJolt",
    ck_test_jolt_parity::kTestFlags)

bool FCkTest_Jolt_GeometryParitySampler_ChaosVsJolt::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_parity;

    bSuppressLogWarnings = true;
    // /Engine/Maps/Entry ships a default BrushComponent with collision but no runtime BrushBodySetup; the Jolt
    // static-world bake ensures on it at PIE start. Unrelated to the sampled field (which is far from origin) — whitelist.
    AddExpectedError(TEXT("BodySetup"), EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    GField.Reset();
    GActors.Reset();
    GBakedBodies = 0;

    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr int32 NumClients = 1;
    constexpr int32 ExpectedWorlds = 1;
    constexpr int32 Seed = 0x0C0FFEE7;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumClients, EntryMapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedWorlds, ReadyTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(SettleFrames));

    // Build the parity field + bake it into the Jolt static world.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto Rng = FRandomStream{Seed};
            Build_Field(Rng);
            Spawn_And_Bake(InServer);

            TestTrue(TEXT("parity field built"), GField.Num() > 0);
            TestEqual(TEXT("each basic-shape primitive bakes exactly one Jolt body"), GBakedBodies, GField.Num());
        })));

    // Settle: broadphase optimize after the bulk bake + Chaos body registration.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(SettleFrames));

    // Fire the fuzz against both engines and assert zero mismatches.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* World = ck::auto_test::net::Get_ServerWorld();
            if (World == nullptr)
            { return TestTrue(TEXT("server world available for sampling"), false); }

            // The sampler re-seeds from the SAME literal so the sample set is independent of the field-build RNG draws.
            auto Rng = FRandomStream{Seed};
            auto Counters = FCounters{};

            Sample_Rays(World, Rng, Counters);
            Sample_Sweeps(World, Rng, Counters);
            Sample_Overlaps(World, Rng, Counters);

            ck::tests::Display(TEXT("[Jolt geometry-parity sampler] {} rays + {} sweeps + {} overlaps vs {} baked bodies. Mismatches: {}"),
                RayCount, SweepCount, OverlapCount, GBakedBodies, Counters.Breakdown());
            ck::tests::Display(TEXT("[Jolt geometry-parity sampler] sweep diagnostics: max stop-distance delta = {} cm, min normal dot = {} (tol: stop <= {} cm, dot >= {})"),
                Counters.MaxSweepStopDeltaCm, Counters.MinSweepNormalDot, SweepStopTolCm, NormalDotMin);

            return TestEqual(
                *ck::Format_UE(TEXT("total Chaos-vs-Jolt parity mismatches == 0 ({})"), Counters.Breakdown()),
                Counters.Total(), 0);
        }),
        TEXT("geometry parity sampler: hit/miss exact, impact tol, normal dot")));

    // Cleanup: un-bake + destroy the field (shared-session hygiene, mirrors the AS parity tests).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* /*InServer*/) -> void
        {
            Teardown_Field();
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
