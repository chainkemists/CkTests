#include <Misc/AutomationTest.h>

#include <Jolt/Jolt.h>

#if WITH_DEV_AUTOMATION_TESTS && JPH_DEBUG_RENDERER

#include "CkEcs/Handle/CkHandle.h"

#include "CkJolt/CkJolt_Utils.h"
#include "CkJolt/CollisionLayers/CkJoltCollisionLayerTable.h"
#include "CkJolt/CollisionLayers/CkJoltCollisionLayer_Utils.h"
#include "CkJolt/Subsystem/CkJolt_DebugDrawTarget.h"
#include "CkJolt/Subsystem/CkJolt_DebugRenderer.h"

#include "CkTests/CkTests_Log.h"

#include <Engine/World.h>
#include <HAL/PlatformTime.h>

#include <Jolt/Physics/PhysicsSystem.h>
#include <Jolt/Physics/Body/BodyCreationSettings.h>
#include <Jolt/Physics/Body/BodyInterface.h>
#include <Jolt/Physics/Collision/Shape/BoxShape.h>

// --------------------------------------------------------------------------------------------------------------------
// Scale measurement for the world-targetable Jolt debug-draw facility, against the same standalone PhysicsSystem +
// transient UWorld fixture the reconcile specs use — no PIE, no ECS registry, no simulation step. The world is a
// mostly-static scene (N static boxes sharing ONE shape) plus a fixed awake dynamic population, which is the shape
// the 100k scale bar describes.
//
// The PRODUCT is the logged per-case milliseconds; the assertions are deliberately loose sanity bounds, because a
// benchmark that gates on a tight number becomes a flake on a busy machine and gets deleted. Numbers land in
// CkJolt/CLAUDE.md.
//
// What this fixture does NOT measure, so the numbers are not over-read: the capture's baked-static classification
// walks the ECS registry per static body, and an INVALID transient entity short-circuits that walk. A live PIE world
// therefore pays a registry lookup per static body that does not appear here.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_jolt_debugdraw_benchmark
{
    constexpr auto TestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;

    constexpr auto BoxHalfExtent = 50.0f;

    constexpr int32 NumAwakeDynamics = 1000;
    constexpr int32 SteadyStateCaptures = 10;

    // Sanity bounds, not targets: wide enough that only a change of ALGORITHMIC class trips them.
    constexpr auto SteadyStateBudgetMs = 50.0;
    constexpr auto PassBudgetMs = 2000.0;

    // ----------------------------------------------------------------------------------------------------------------

    auto
        Log_Case(
            int32 InNumBodies,
            const FString& InCase,
            double InMilliseconds)
        -> void
    {
        ck::tests::Display(TEXT("[JoltDebugDrawBench] N={} case={} ms={}"),
            InNumBodies, InCase, FString::Printf(TEXT("%.3f"), InMilliseconds));
    }

    auto
        Time_Ms(
            TFunctionRef<void()> InMeasured)
        -> double
    {
        const auto StartSeconds = FPlatformTime::Seconds();
        InMeasured();
        return (FPlatformTime::Seconds() - StartSeconds) * 1000.0;
    }

    // ----------------------------------------------------------------------------------------------------------------

    // The reconcile fixture at scale: one shared BoxShape for every body, and the BATCH add path, because adding
    // 100k static bodies one at a time rebuilds the broadphase tree per body.
    struct FScopedBenchWorld
    {
        explicit FScopedBenchWorld(
            int32 InMaxBodies)
        {
            ck::jolt::Request_GlobalJoltInit();

            _LayerTable = MakeUnique<ck::jolt::FCk_Jolt_CollisionLayerTable>();
            _LayerTable->Build_FromCollisionProfiles();

            _BroadPhaseLayerInterface = MakeUnique<ck::jolt::FCk_Jolt_BroadPhaseLayerInterface_Table>(*_LayerTable);
            _ObjectVsBroadPhaseFilter = MakeUnique<ck::jolt::FCk_Jolt_ObjectVsBroadPhaseLayerFilter_Table>(*_LayerTable);
            _ObjectVsObjectFilter = MakeUnique<ck::jolt::FCk_Jolt_ObjectLayerPairFilter_Table>(*_LayerTable);

            // Pair/constraint buffers stay small: nothing here is ever stepped, so no contact is ever produced.
            constexpr JPH::uint ContactBuffers = 1024;

            _PhysicsSystem = MakeUnique<JPH::PhysicsSystem>();
            _PhysicsSystem->Init(static_cast<JPH::uint>(InMaxBodies), 0, ContactBuffers, ContactBuffers,
                *_BroadPhaseLayerInterface, *_ObjectVsBroadPhaseFilter, *_ObjectVsObjectFilter);

            _SharedBox = new JPH::BoxShape{JPH::Vec3{BoxHalfExtent, BoxHalfExtent, BoxHalfExtent}};
        }

        ~FScopedBenchWorld()
        {
            Remove_AllBodies();

            _SharedBox = nullptr;
            _PhysicsSystem.Reset();
            _ObjectVsObjectFilter.Reset();
            _ObjectVsBroadPhaseFilter.Reset();
            _BroadPhaseLayerInterface.Reset();
            _LayerTable.Reset();

            ck::jolt::Request_GlobalJoltShutdown();
        }

        FScopedBenchWorld(const FScopedBenchWorld&) = delete;
        auto operator=(const FScopedBenchWorld&) -> FScopedBenchWorld& = delete;

        auto Get_PhysicsSystem() -> JPH::PhysicsSystem& { return *_PhysicsSystem; }

        auto
        Get_Layer(
            ECk_Jolt_BodyDomain InDomain) -> JPH::ObjectLayer
        {
            const auto Signature = ck::jolt::TryDerive_SignatureFromProfile(FName{TEXT("BlockAll")}, InDomain);

            if (NOT Signature.IsSet())
            { return JPH::ObjectLayer{_LayerTable->Get_ProbeLayer()}; }

            return JPH::ObjectLayer{_LayerTable->Get_OrRegisterLayer(*Signature)};
        }

        /// Creates and batch-adds InCount boxes on a coarse grid. Returns how many were actually created — a
        /// body budget the platform could not honour comes back short rather than ensuring.
        auto
        Add_BoxGrid(
            int32 InCount,
            JPH::EMotionType InMotionType,
            float InOriginZ,
            bool InActivate) -> int32
        {
            const auto Domain = InMotionType == JPH::EMotionType::Static
                ? ECk_Jolt_BodyDomain::Static
                : ECk_Jolt_BodyDomain::Dynamic;

            const auto Layer = Get_Layer(Domain);

            auto Created = TArray<JPH::BodyID>{};
            Created.Reserve(InCount);

            auto& BodyInterface = _PhysicsSystem->GetBodyInterface();

            constexpr auto Stride = 200.0f;
            constexpr auto PerRow = 320;

            for (auto Index = 0; Index < InCount; ++Index)
            {
                const auto Location = JPH::RVec3{
                    static_cast<float>(Index % PerRow) * Stride,
                    static_cast<float>(Index / PerRow) * Stride,
                    InOriginZ};

                auto Settings = JPH::BodyCreationSettings{
                    _SharedBox.GetPtr(), Location, JPH::Quat::sIdentity(), InMotionType, Layer};

                auto* Body = BodyInterface.CreateBody(Settings);

                if (Body == nullptr)
                { break; }

                Created.Emplace(Body->GetID());
            }

            if (Created.IsEmpty())
            { return 0; }

            const auto AddState = BodyInterface.AddBodiesPrepare(Created.GetData(), Created.Num());
            BodyInterface.AddBodiesFinalize(Created.GetData(), Created.Num(), AddState,
                InActivate ? JPH::EActivation::Activate : JPH::EActivation::DontActivate);

            _BodyIds.Append(Created);
            return Created.Num();
        }

        auto
        Get_FirstBodyKey() const -> uint64
        {
            return _BodyIds.IsEmpty()
                ? 0
                : ck::jolt::debug_draw::Make_BodyKey(_BodyIds[0].GetIndexAndSequenceNumber());
        }

        auto
        Remove_AllBodies() -> void
        {
            if (_BodyIds.IsEmpty())
            { return; }

            auto& BodyInterface = _PhysicsSystem->GetBodyInterface();

            BodyInterface.RemoveBodies(_BodyIds.GetData(), _BodyIds.Num());
            BodyInterface.DestroyBodies(_BodyIds.GetData(), _BodyIds.Num());

            _BodyIds.Reset();
        }

    private:
        TUniquePtr<ck::jolt::FCk_Jolt_CollisionLayerTable> _LayerTable;
        TUniquePtr<ck::jolt::FCk_Jolt_BroadPhaseLayerInterface_Table> _BroadPhaseLayerInterface;
        TUniquePtr<ck::jolt::FCk_Jolt_ObjectVsBroadPhaseLayerFilter_Table> _ObjectVsBroadPhaseFilter;
        TUniquePtr<ck::jolt::FCk_Jolt_ObjectLayerPairFilter_Table> _ObjectVsObjectFilter;
        TUniquePtr<JPH::PhysicsSystem> _PhysicsSystem;
        JPH::Ref<JPH::Shape> _SharedBox;
        TArray<JPH::BodyID> _BodyIds;
    };

    // ----------------------------------------------------------------------------------------------------------------

    auto
        Run_Config(
            FAutomationTestBase& InTest,
            int32 InNumStatics)
        -> void
    {
        auto* World = UWorld::CreateWorld(EWorldType::Game, false);

        if (NOT InTest.TestNotNull(TEXT("transient world exists"), World))
        { return; }

        {
            const auto MaxBodies = InNumStatics + NumAwakeDynamics + 64;
            auto JoltWorld = FScopedBenchWorld{MaxBodies};

            constexpr auto DoNotActivate = false;
            constexpr auto Activate = true;
            constexpr auto StaticOriginZ = 0.0f;
            constexpr auto DynamicOriginZ = 5000.0f;

            const auto NumStaticsAdded = JoltWorld.Add_BoxGrid(InNumStatics, JPH::EMotionType::Static,
                StaticOriginZ, DoNotActivate);

            if (NumStaticsAdded < InNumStatics)
            {
                ck::tests::Display(
                    TEXT("[JoltDebugDrawBench] N={} SKIPPED — this environment allocated only {} of the requested bodies"),
                    InNumStatics, NumStaticsAdded);

                World->DestroyWorld(false);
                return;
            }

            JoltWorld.Add_BoxGrid(NumAwakeDynamics, JPH::EMotionType::Dynamic, DynamicOriginZ, Activate);

            auto& Renderer = FCk_Jolt_DebugRenderer::Get_OrCreate();
            auto Target = MakeShared<FCk_Jolt_DebugDrawTarget>(World);
            Target->Set_IsDesired(true);

            auto Revision = uint64{1};

            const auto FirstPassMs = Time_Ms([&]()
            {
                Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
                    ck::jolt::debug_draw::FCaptureRevisions{Revision}, FCk_Handle{});
            });
            Log_Case(InNumStatics, TEXT("first_full_pass"), FirstPassMs);

            // Steady state: the revision never moves, so only the awake dynamics are walked.
            auto SteadyTotalMs = 0.0;

            for (auto Index = 0; Index < SteadyStateCaptures; ++Index)
            {
                SteadyTotalMs += Time_Ms([&]()
                {
                    Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
                    ck::jolt::debug_draw::FCaptureRevisions{Revision}, FCk_Handle{});
                });
            }

            const auto SteadyMs = SteadyTotalMs / SteadyStateCaptures;
            Log_Case(InNumStatics, TEXT("steady_state_avg"), SteadyMs);

            ++Revision;

            const auto RevisionRerunMs = Time_Ms([&]()
            {
                Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
                    ck::jolt::debug_draw::FCaptureRevisions{Revision}, FCk_Handle{});
            });
            Log_Case(InNumStatics, TEXT("revision_rerun"), RevisionRerunMs);

            // A ray straight down the grid's first row, so it crosses real instances rather than empty space.
            const auto PickOrigin = FVector{-100000.0, 0.0, 0.0};
            const auto PickDirection = FVector{1.0, 0.0, 0.0};

            const auto PickMs = Time_Ms([&]()
            {
                Target->TryPick_Body(PickOrigin, PickDirection);
            });
            Log_Case(InNumStatics, TEXT("pick_body"), PickMs);

            // Selecting re-arms the full inactive pass, so this measures what one selection change costs.
            Target->Set_HighlightedBody(JoltWorld.Get_FirstBodyKey());

            const auto HighlightPassMs = Time_Ms([&]()
            {
                Renderer.Capture_JoltWorld(*Target, JoltWorld.Get_PhysicsSystem(),
                    ck::jolt::debug_draw::FCaptureRevisions{Revision}, FCk_Handle{});
            });
            Log_Case(InNumStatics, TEXT("highlight_rearmed_pass"), HighlightPassMs);

            InTest.TestTrue(TEXT("every static body drew an instance"),
                Target->Get_NumInstances() >= NumStaticsAdded);

            InTest.TestTrue(FString::Printf(
                TEXT("steady-state capture at N=%d stays under the sanity budget"), InNumStatics),
                SteadyMs < SteadyStateBudgetMs);

            InTest.TestTrue(FString::Printf(
                TEXT("the first full pass at N=%d stays under the sanity budget"), InNumStatics),
                FirstPassMs < PassBudgetMs);
            InTest.TestTrue(FString::Printf(
                TEXT("a revision re-run at N=%d stays under the sanity budget"), InNumStatics),
                RevisionRerunMs < PassBudgetMs);
            InTest.TestTrue(FString::Printf(
                TEXT("a pick at N=%d stays under the sanity budget"), InNumStatics),
                PickMs < PassBudgetMs);
            InTest.TestTrue(FString::Printf(
                TEXT("a re-armed pass after a selection at N=%d stays under the sanity budget"), InNumStatics),
                HighlightPassMs < PassBudgetMs);
        }

        World->DestroyWorld(false);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltDebugDraw_Benchmark_ScaleMatrix,
    "Ck.Jolt.DebugDraw.Benchmark.ScaleMatrix",
    ck_test_jolt_debugdraw_benchmark::TestFlags)

bool FCkTest_JoltDebugDraw_Benchmark_ScaleMatrix::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_debugdraw_benchmark;

    const int32 BodyCounts[] = {1000, 10000, 100000};

    for (const auto NumStatics : BodyCounts)
    { Run_Config(*this, NumStatics); }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif
