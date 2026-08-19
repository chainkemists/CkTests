// T-C6-1b — the LoadKernel scope holds every non-kernel processor, in EVERY tick-group partition.
//
// Ck.Snapshot.LoadGate.GatedSkipsKernelTicks already pins the scope filter, but its fixture keeps the FIRST
// non-empty partition the graph builder produced and discards the rest. FGroup_Overlap is the one group that
// declares TG_PostPhysics, so it lands in its OWN partition — which that fixture throws away. Its arm of the
// assertion was therefore vacuous: the counter it read had never been dispatched at all, under either scope.
//
// This fixture builds a scheduler PER partition and ticks all of them, with one counting processor in each of
// three groups: a kernel processor, an ordinary gameplay processor, and an Overlap processor in the separate
// TG_PostPhysics partition. The load's convergence phase pumps every partition, and physics contacts are routed
// into probe overlaps by processors in exactly that group — so "the hold reaches the Overlap partition" is a
// statement C6 depends on rather than a completeness flourish.
//
// RED before C6: the assertions here hold pre-range too WHERE THE FIXTURE COULD REACH — what was missing is the
// Overlap arm, which no pre-range fixture dispatched. Kept in the C6 set because the convergence phase is what
// made that partition load-bearing.
// Surface in Session Frontend: Ck.Snapshot.LoadHold.NoNonKernelTickUnderRebuild

#include "CkCore/Macros/CkMacros.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Processor/CkProcessor.h"
#include "CkEcs/Scheduler/CkProcessorDescriptor.h" // ECk_ProcessorLoadPolicy
#include "CkEcs/Scheduler/CkProcessorGraph.h"
#include "CkEcs/Scheduler/CkProcessorGroups.h"
#include "CkEcs/Scheduler/CkProcessorScheduler.h"  // ECk_SchedulerTickScope
#include "CkEcs/Scheduler/CkProcessorTraits.inl.h"
#include "CkEcs/Tag/CkTag.h"
#include "CkEcs/World/CkEcsWorld.h"

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace ck
{
    CK_DEFINE_ECS_TAG(FTag_LoadHoldScopeTest_Marker);
}

namespace ck_test_loadhold_scope
{
    constexpr auto kFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::ProductFilter;

    // Default LoadPolicy (GatedDuringLoad), FGroup_Gameplay: the ordinary feature-processor case.
    class FProcessor_LoadHoldScopeTest_Gameplay
        : public ck::TProcessor<FProcessor_LoadHoldScopeTest_Gameplay, ck::FTag_LoadHoldScopeTest_Marker>
    {
    public:
        using Super = ck::TProcessor<FProcessor_LoadHoldScopeTest_Gameplay, ck::FTag_LoadHoldScopeTest_Marker>;
        using Super::Super;
        using Group = ck::FGroup_Gameplay;

        static inline int32 Count = 0;
        static auto Reset() -> void { Count = 0; }

        auto ForEachEntity(TimeType, HandleType) -> void { ++Count; }
    };

    // The partition the old fixture discarded: FGroup_Overlap is the only TG_PostPhysics group repo-wide.
    class FProcessor_LoadHoldScopeTest_Overlap
        : public ck::TProcessor<FProcessor_LoadHoldScopeTest_Overlap, ck::FTag_LoadHoldScopeTest_Marker>
    {
    public:
        using Super = ck::TProcessor<FProcessor_LoadHoldScopeTest_Overlap, ck::FTag_LoadHoldScopeTest_Marker>;
        using Super::Super;
        using Group = ck::FGroup_Overlap;

        static inline int32 Count = 0;
        static auto Reset() -> void { Count = 0; }

        auto ForEachEntity(TimeType, HandleType) -> void { ++Count; }
    };

    // Load-gate kernel: ticks under BOTH scopes. Its non-zero count under LoadKernel is the load-bearing half —
    // over-gating a kernel processor manifests as a silent HANG rather than a wrong value.
    class FProcessor_LoadHoldScopeTest_Kernel
        : public ck::TProcessor<FProcessor_LoadHoldScopeTest_Kernel, ck::FTag_LoadHoldScopeTest_Marker>
    {
    public:
        using Super = ck::TProcessor<FProcessor_LoadHoldScopeTest_Kernel, ck::FTag_LoadHoldScopeTest_Marker>;
        using Super::Super;
        using Group = ck::FGroup_Gameplay;
        static constexpr auto LoadPolicy = ECk_ProcessorLoadPolicy::RunsDuringLoad;

        static inline int32 Count = 0;
        static auto Reset() -> void { Count = 0; }

        auto ForEachEntity(TimeType, HandleType) -> void { ++Count; }
    };

    // Hermetic, mirroring Test_Snapshot_LoadGate_Scope.cpp — the processors are fed to the graph builder directly
    // and never appear in a real world's graph. The one difference is that EVERY partition is kept.
    struct FLoadHoldScopeFixture
    {
        ck::FEcsWorld World;
        TArray<TUniquePtr<ck::FProcessorScheduler>> Schedulers;

        auto Build() -> int32
        {
            const auto TransientHandle = UCk_Utils_EntityLifetime_UE::Get_TransientEntity(World.Get_Registry());

            auto Descriptors = TArray<ck::FProcessorDescriptor>{};
            Descriptors.Add(ck::BuildDescriptor<FProcessor_LoadHoldScopeTest_Gameplay>(
                [](const FCk_Registry& InRegistry) -> ck::concepts::FTickableType
                { return FProcessor_LoadHoldScopeTest_Gameplay{InRegistry}; }));
            Descriptors.Add(ck::BuildDescriptor<FProcessor_LoadHoldScopeTest_Overlap>(
                [](const FCk_Registry& InRegistry) -> ck::concepts::FTickableType
                { return FProcessor_LoadHoldScopeTest_Overlap{InRegistry}; }));
            Descriptors.Add(ck::BuildDescriptor<FProcessor_LoadHoldScopeTest_Kernel>(
                [](const FCk_Registry& InRegistry) -> ck::concepts::FTickableType
                { return FProcessor_LoadHoldScopeTest_Kernel{InRegistry}; }));

            auto Builder = ck::FProcessorGraphBuilder{};
            auto Graph = Builder.Build(Descriptors, World.Get_Registry(), TransientHandle);

            for (auto& Kvp : Graph._Partitions)
            {
                if (Kvp.Value._Nodes.Num() == 0)
                { continue; }

                Schedulers.Emplace(MakeUnique<ck::FProcessorScheduler>(MoveTemp(Kvp.Value)));
            }

            return Schedulers.Num();
        }

        auto Tick(ck::ECk_SchedulerTickScope InScope) -> void
        {
            for (auto& Scheduler : Schedulers)
            { Scheduler->Tick(FCk_Time{1.0 / 60.0}, World.Get_Registry(), InScope); }
        }

        auto CreateEntity() -> FCk_Handle
        {
            return UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
        }

        auto ResetCounters() -> void
        {
            FProcessor_LoadHoldScopeTest_Gameplay::Reset();
            FProcessor_LoadHoldScopeTest_Overlap::Reset();
            FProcessor_LoadHoldScopeTest_Kernel::Reset();
        }
    };
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_LoadHold_NoNonKernelTickUnderRebuild,
    "Ck.Snapshot.LoadHold.NoNonKernelTickUnderRebuild",
    ck_test_loadhold_scope::kFlags)

bool FCk_Snapshot_LoadHold_NoNonKernelTickUnderRebuild::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_loadhold_scope;

    auto Fixture = FLoadHoldScopeFixture{};
    const auto PartitionCount = Fixture.Build();

    // Two partitions, not one: TG_PrePhysics for the gameplay/kernel pair and TG_PostPhysics for Overlap. A
    // single partition here means the Overlap arm below is measuring nothing.
    if (NOT TestTrue(
        FString::Printf(TEXT("the fixture kept BOTH tick-group partitions (built %d)"), PartitionCount),
        PartitionCount >= 2))
    { return false; }

    auto Entity = Fixture.CreateEntity();
    Entity.Add<ck::FTag_LoadHoldScopeTest_Marker>();

    constexpr auto NumFrames = 3;

    auto AllGood = true;

    // ---- Full scope: everything ticks, including the TG_PostPhysics partition. -----------------------------------
    Fixture.ResetCounters();
    for (auto Frame = 0; Frame < NumFrames; ++Frame)
    { Fixture.Tick(ck::ECk_SchedulerTickScope::Full); }

    AllGood &= TestEqual(TEXT("Full scope ticks the gameplay processor every frame"),
        FProcessor_LoadHoldScopeTest_Gameplay::Count, NumFrames);
    AllGood &= TestEqual(TEXT("Full scope ticks the FGroup_Overlap processor every frame (its partition IS dispatched)"),
        FProcessor_LoadHoldScopeTest_Overlap::Count, NumFrames);
    AllGood &= TestEqual(TEXT("Full scope ticks the kernel processor every frame"),
        FProcessor_LoadHoldScopeTest_Kernel::Count, NumFrames);

    // ---- LoadKernel scope: both non-kernel processors are held, in both partitions. ------------------------------
    Fixture.ResetCounters();
    for (auto Frame = 0; Frame < NumFrames; ++Frame)
    { Fixture.Tick(ck::ECk_SchedulerTickScope::LoadKernel); }

    AllGood &= TestEqual(TEXT("LoadKernel scope does NOT tick the gameplay processor"),
        FProcessor_LoadHoldScopeTest_Gameplay::Count, 0);
    AllGood &= TestEqual(TEXT("LoadKernel scope does NOT tick the FGroup_Overlap processor — the hold reaches the "
                              "TG_PostPhysics partition too, which is the partition the convergence phase pumps"),
        FProcessor_LoadHoldScopeTest_Overlap::Count, 0);
    AllGood &= TestEqual(TEXT("LoadKernel scope STILL ticks the RunsDuringLoad kernel processor (not over-gated)"),
        FProcessor_LoadHoldScopeTest_Kernel::Count, NumFrames);

    // ---- Back to Full: the hold is a scope, not a latch. ---------------------------------------------------------
    Fixture.ResetCounters();
    Fixture.Tick(ck::ECk_SchedulerTickScope::Full);

    AllGood &= TestEqual(TEXT("the gameplay processor resumes once the scope widens"),
        FProcessor_LoadHoldScopeTest_Gameplay::Count, 1);
    AllGood &= TestEqual(TEXT("the Overlap processor resumes once the scope widens"),
        FProcessor_LoadHoldScopeTest_Overlap::Count, 1);

    Fixture.ResetCounters();

    return AllGood;
}

#endif // WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
