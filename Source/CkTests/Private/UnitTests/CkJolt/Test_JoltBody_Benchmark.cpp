#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkCore/Format/CkFormat.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkEcsExt/Transform/CkTransform_Utils.h"

#include "CkJolt/Body/CkJoltBody_Utils.h"

#include "CkTests/CkTests_Log.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include <Components/StaticMeshComponent.h>
#include <Engine/StaticMesh.h>
#include <Engine/StaticMeshActor.h>
#include <Engine/World.h>
#include <HAL/PlatformTime.h>

// --------------------------------------------------------------------------------------------------------------------
// JoltBody benchmark harness (jolt-collision-world Phase 5, item 4). NON-GATING: the test always passes; its product
// is a ready-to-paste markdown table logged via the CkTests module log. It measures per-frame wall-clock (frame-delta
// between consecutive latent-command Update() calls — the engine ticks the PIE world with physics between them) across
// an empty control and a matrix of body counts / engines / island layouts, then reports p50/p95/max per config.
//
// The new STAT_CkJolt_WorldStep/_Writeback/_KinematicPush cycle stats (added in CkJolt this phase) time the same
// regions on the CkJolt side; this harness measures wall-clock deltas directly (never reads STAT values) per the
// dispatch. Thread-count is a STARTUP-ONLY knob (jolt.EnableParallelPhysics / NumPhysicsThreads) — this run uses the
// project default; the manual 1-thread procedure is documented in the executor report.
//
// Timing caveats (headless PIE): frame-delta timing is inherently noisy (the whole engine frame is measured, not just
// physics); the delta-vs-control column isolates the body load. The "pile" island layouts are a free-fall contact-clump
// proxy (boxes spawned just-touching fall together maintaining contact — one connected island) rather than a
// floor-settled pile; the 10k Chaos config is the slowest/noisiest cell. Numbers are directional, not authoritative.
// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_jolt_benchmark
{
    enum class EEngine : uint8 { Jolt, Chaos };
    enum class ELayout : uint8 { Spread, OnePile, TenPiles };

    struct FBenchRow
    {
        FString Label;
        int32   N = 0;
        double  P50 = 0.0;
        double  P95 = 0.0;
        double  Max = 0.0;
    };

    // Cross-latent-command state (mirrors the lifecycle spec pattern). Reset per config / per test.
    static TArray<double>            GSamples;
    static TArray<FBenchRow>         GRows;
    static TArray<FCk_Handle>        GJoltEntities;
    static TArray<AStaticMeshActor*> GChaosActors;
    static double                    GControlP50 = -1.0;

    const auto EntryMapPath = FString{TEXT("/Engine/Maps/Entry")};

    constexpr int32 WarmupFrames   = 60;
    constexpr int32 MeasuredFrames = 600;
    constexpr double ClumpSpacing  = 100.0; // == a scale-1 box's full extent: bodies spawn just-touching (one island)

    constexpr auto kTestFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;
    // Generous settle between configs so a heavy config's batched adds land and its deferred destroys fully drain
    // before the next config measures (a residual body would inflate the next config's frame cost).
    constexpr int32 SettleFrames = 30;

    // ----------------------------------------------------------------------------------------------------------------

    // Spread: a coarse grid high up so bodies free-fall without ever contacting (N tiny islands). Matches the
    // lifecycle spec's Grid_Location so the "spread" cost is comparable across tests.
    static auto Spread_Location(int32 InIndex) -> FVector
    {
        constexpr auto Stride = 200.0;
        constexpr auto PerRow = 32;
        return FVector{(InIndex % PerRow) * Stride, (InIndex / PerRow) * Stride, 5000.0};
    }

    // A compact cube of bodies at a clump origin: spawned just-touching so uniform gravity keeps them a connected
    // contact clump (one solver island) rather than a spread of independent bodies. A fixed 32-wide cube holds up
    // to 32^3 = 32768 bodies per clump (>= any clump size this harness spawns).
    static auto Clump_Location(int32 InLocalIndex, const FVector& InClumpOrigin) -> FVector
    {
        constexpr int32 Side = 32;
        const auto X = InLocalIndex % Side;
        const auto Y = (InLocalIndex / Side) % Side;
        const auto Z = InLocalIndex / (Side * Side);
        return InClumpOrigin + FVector{X * ClumpSpacing, Y * ClumpSpacing, Z * ClumpSpacing};
    }

    static auto Location_For(int32 InIndex, int32 InTotal, ELayout InLayout) -> FVector
    {
        switch (InLayout)
        {
            case ELayout::Spread:
                return Spread_Location(InIndex);

            case ELayout::OnePile:
            {
                // One clump centered high up.
                const auto Origin = FVector{0.0, 0.0, 8000.0};
                return Clump_Location(InIndex, Origin);
            }

            case ELayout::TenPiles:
            default:
            {
                constexpr int32 NumPiles = 10;
                const auto PerPile = FMath::Max(1, InTotal / NumPiles);
                const auto PileIndex = FMath::Min(InIndex / PerPile, NumPiles - 1);
                const auto LocalIndex = InIndex - PileIndex * PerPile;
                const auto Origin = FVector{PileIndex * 6000.0, 0.0, 8000.0};
                return Clump_Location(LocalIndex, Origin);
            }
        }
    }

    // ----------------------------------------------------------------------------------------------------------------

    static auto Spawn_JoltBox(UWorld* InWorld, const FVector& InLocation) -> FCk_Handle
    {
        auto* Ecs = InWorld->GetSubsystem<UCk_EcsWorld_Subsystem_UE>();
        if (ck::Is_NOT_Valid(Ecs))
        { return {}; }

        auto Entity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Ecs->Get_Registry());
        UCk_Utils_Transform_UE::Add(Entity, FTransform{InLocation}, ECk_Replication::DoesNotReplicate);

        auto Params = FCk_JoltBody_Spec{ECk_JoltBody_ShapeSource::ExplicitShape};
        Params.Set_ShapeDimensions(FCk_Jolt_ShapeDimensions{ECk_Jolt_ShapeType::Box});
        Params.Set_MotionType(ECk_MotionType::Dynamic);
        Params.Set_InitialSleepState(ECk_Jolt_SleepState::Awake);

        UCk_Utils_JoltBody_UE::Add(Entity, Params);
        return Entity;
    }

    static auto Spawn_ChaosBox(UWorld* InWorld, UStaticMesh* InMesh, const FVector& InLocation) -> AStaticMeshActor*
    {
        auto* Actor = InWorld->SpawnActor<AStaticMeshActor>(AStaticMeshActor::StaticClass(), FTransform{InLocation});
        if (Actor == nullptr)
        { return nullptr; }

        auto* Comp = Actor->GetStaticMeshComponent();
        Comp->SetMobility(EComponentMobility::Movable);
        Comp->SetStaticMesh(InMesh);
        Comp->SetCollisionProfileName(TEXT("PhysicsActor"));
        Comp->SetSimulatePhysics(true);
        return Actor;
    }

    static auto Spawn_Config(UWorld* InWorld, int32 InN, EEngine InEngine, ELayout InLayout) -> void
    {
        GSamples.Reset();
        GJoltEntities.Reset();
        GChaosActors.Reset();

        if (InEngine == EEngine::Jolt)
        {
            GJoltEntities.Reserve(InN);
            for (auto Index = 0; Index < InN; ++Index)
            {
                auto Entity = Spawn_JoltBox(InWorld, Location_For(Index, InN, InLayout));
                if (ck::IsValid(Entity))
                { GJoltEntities.Emplace(Entity); }
            }
        }
        else
        {
            auto* Mesh = LoadObject<UStaticMesh>(nullptr, TEXT("/Engine/BasicShapes/Cube.Cube"));
            if (Mesh == nullptr)
            { return; }

            GChaosActors.Reserve(InN);
            for (auto Index = 0; Index < InN; ++Index)
            {
                auto* Actor = Spawn_ChaosBox(InWorld, Mesh, Location_For(Index, InN, InLayout));
                if (Actor != nullptr)
                { GChaosActors.Emplace(Actor); }
            }
        }
    }

    static auto Destroy_Config(UWorld* /*InWorld*/) -> void
    {
        if (GJoltEntities.Num() > 0)
        { UCk_Utils_EntityLifetime_UE::Request_DestroyEntities(GJoltEntities); }
        GJoltEntities.Reset();

        for (auto* Actor : GChaosActors)
        {
            if (Actor != nullptr)
            { Actor->Destroy(); }
        }
        GChaosActors.Reset();
    }

    // ----------------------------------------------------------------------------------------------------------------

    // Percentile from an ascending-sorted array (nearest-rank). Fraction in [0,1].
    static auto Percentile(const TArray<double>& InSorted, double InFraction) -> double
    {
        if (InSorted.Num() == 0)
        { return 0.0; }
        const auto Rank = FMath::Clamp(FMath::FloorToInt(InFraction * InSorted.Num()), 0, InSorted.Num() - 1);
        return InSorted[Rank];
    }

    static auto Record_Row(const FString& InLabel, int32 InN, bool InIsControl) -> void
    {
        auto Sorted = GSamples;
        Sorted.Sort();

        auto Row = FBenchRow{};
        Row.Label = InLabel;
        Row.N = InN;
        Row.P50 = Percentile(Sorted, 0.50);
        Row.P95 = Percentile(Sorted, 0.95);
        Row.Max = (Sorted.Num() > 0) ? Sorted.Last() : 0.0;

        if (InIsControl)
        { GControlP50 = Row.P50; }

        GRows.Emplace(MoveTemp(Row));
    }

    static auto Log_Table() -> void
    {
        ck::tests::Display(TEXT("=== JoltBody benchmark (per-frame wall-clock ms; frame-delta method; warmup {} / measured {}) ==="),
            WarmupFrames, MeasuredFrames);
        ck::tests::Display(TEXT("| Config | N | p50 (ms) | p95 (ms) | max (ms) | p50 - control (ms) |"));
        ck::tests::Display(TEXT("|---|---:|---:|---:|---:|---:|"));

        for (const auto& Row : GRows)
        {
            const auto Delta = (GControlP50 >= 0.0) ? (Row.P50 - GControlP50) : 0.0;
            ck::tests::Display(TEXT("| {} | {} | {} | {} | {} | {} |"),
                Row.Label, Row.N,
                FString::Printf(TEXT("%.3f"), Row.P50),
                FString::Printf(TEXT("%.3f"), Row.P95),
                FString::Printf(TEXT("%.3f"), Row.Max),
                FString::Printf(TEXT("%+.3f"), Delta));
        }
        ck::tests::Display(TEXT("=== end JoltBody benchmark ==="));
    }

    // ----------------------------------------------------------------------------------------------------------------

    // Custom latent command: one engine frame per Update(); records per-frame wall-clock deltas (after a warmup) into
    // the shared GSamples until MeasuredFrames are collected. The engine ticks the PIE world (with physics) between
    // Update() calls, so each delta is a full frame's wall-clock cost.
    class FCk_Latent_JoltBench_Sample final : public IAutomationLatentCommand
    {
    public:
        FCk_Latent_JoltBench_Sample(int32 InWarmup, int32 InMeasured)
            : _Warmup(InWarmup), _Measured(InMeasured) {}

        virtual ~FCk_Latent_JoltBench_Sample() = default;

        virtual bool Update() override
        {
            const auto Now = FPlatformTime::Seconds();

            if (_LastTime < 0.0)
            {
                _LastTime = Now;
                ++_FrameIndex;
                return false;
            }

            const auto DeltaMs = (Now - _LastTime) * 1000.0;
            _LastTime = Now;
            ++_FrameIndex;

            if (_FrameIndex > _Warmup)
            { GSamples.Emplace(DeltaMs); }

            // Heartbeat: the heavy configs (10k single pile ~250ms/frame) run for minutes with no other
            // output, and the toolbox's idle watchdog kills a silent editor as HUNG. Keep the log warm.
            if ((_FrameIndex % 100) == 0)
            {
                ck::tests::Display(TEXT("[Jolt benchmark] heartbeat: frame {}/{} ({} samples)"),
                    _FrameIndex, _Warmup + _Measured, GSamples.Num());
            }

            return GSamples.Num() >= _Measured;
        }

    private:
        int32  _Warmup = 0;
        int32  _Measured = 0;
        double _LastTime = -1.0;
        int32  _FrameIndex = 0;
    };

    // Enqueue the full latent sequence for one benchmark config (spawn -> sample -> record+destroy). Replicates
    // ADD_LATENT_AUTOMATION_COMMAND's enqueue so the config matrix can be built in a loop.
    static auto Enqueue_Config(const FString& InLabel, int32 InN, EEngine InEngine, ELayout InLayout, bool InIsControl) -> void
    {
        auto& Framework = FAutomationTestFramework::Get();

        Framework.EnqueueLatentCommand(MakeShareable(new FCk_Latent_RunOnServer(
            FCk_NetAutoTest_ServerAction::CreateLambda([InLabel, InN, InEngine, InLayout](UWorld* InServer) -> void
            {
                ck::tests::Display(TEXT("[Jolt benchmark] === config START: '{}' N={} ==="), InLabel, InN);
                Spawn_Config(InServer, InN, InEngine, InLayout);
            }))));

        // Let the Setup processor batch-add the bodies before measuring (warmup also absorbs this, kept for clarity).
        Framework.EnqueueLatentCommand(MakeShareable(new FCk_Latent_TickWorlds(SettleFrames)));

        Framework.EnqueueLatentCommand(MakeShareable(new FCk_Latent_JoltBench_Sample(WarmupFrames, MeasuredFrames)));

        Framework.EnqueueLatentCommand(MakeShareable(new FCk_Latent_RunOnServer(
            FCk_NetAutoTest_ServerAction::CreateLambda([InLabel, InN, InIsControl](UWorld* InServer) -> void
            {
                Record_Row(InLabel, InN, InIsControl);
                Destroy_Config(InServer);
            }))));

        // Drain destruction so the next config starts from a clean world.
        Framework.EnqueueLatentCommand(MakeShareable(new FCk_Latent_TickWorlds(SettleFrames)));
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_JoltBody_Benchmark_FrameCostMatrix,
    "Ck.Jolt.Body.Benchmark.FrameCostMatrix",
    ck_test_jolt_benchmark::kTestFlags)

bool FCkTest_JoltBody_Benchmark_FrameCostMatrix::RunTest(const FString& Parameters)
{
    using namespace ck_test_jolt_benchmark;

    bSuppressLogWarnings = true;
    AddExpectedError(TEXT("BodySetup"), EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);
    // Heavy contact configs (10k piles especially) deliberately push more contacts than the world's configured
    // MaxBodyPairs / MaxContactConstraints buffers hold; CkJolt's step then fires CK_ENSURE(errors == None) each
    // overflowing Update. That is the product correctly reporting an over-capacity world under stress (not a defect),
    // and this benchmark is non-gating — whitelist it so the harness does not escalate. The affected configs' numbers
    // reflect a capacity-saturated solver (noted in the report); raising the buffers is a project-settings knob.
    AddExpectedError(TEXT("EPhysicsUpdateError"), EAutomationExpectedErrorFlags::Contains, /*Occurrences=*/-1);

    GSamples.Reset();
    GRows.Reset();
    GJoltEntities.Reset();
    GChaosActors.Reset();
    GControlP50 = -1.0;

    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr int32 NumClients = 1;
    constexpr int32 ExpectedWorlds = 1;

    const int32 BodyCounts[] = {500, 2000, 10000};

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumClients, EntryMapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedWorlds, ReadyTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(SettleFrames));

    // Control (empty world) first, so every other row can report its delta against this baseline.
    Enqueue_Config(TEXT("control (empty)"), 0, EEngine::Jolt, ELayout::Spread, /*IsControl=*/true);

    // Jolt dynamic-box sweep (spread).
    for (const auto N : BodyCounts)
    { Enqueue_Config(FString{TEXT("Jolt spread")}, N, EEngine::Jolt, ELayout::Spread, false); }

    // Chaos simulate-physics comparison (spread).
    for (const auto N : BodyCounts)
    { Enqueue_Config(FString{TEXT("Chaos spread")}, N, EEngine::Chaos, ELayout::Spread, false); }

    // Island variants at N=10000 (Jolt). Spread@10k above is the third data point.
    Enqueue_Config(TEXT("Jolt 1 pile"),  10000, EEngine::Jolt, ELayout::OnePile,  false);
    Enqueue_Config(TEXT("Jolt 10x1k"),   10000, EEngine::Jolt, ELayout::TenPiles, false);

    // Emit the table + always-pass.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* /*InServer*/) -> void
        {
            Log_Table();
            TestTrue(TEXT("benchmark harness ran (non-gating)"), true);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
