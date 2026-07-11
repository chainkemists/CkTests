#include "CkCore/Macros/CkMacros.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Processor/CkProcessor.h"
#include "CkEcs/Scheduler/CkProcessorDescriptor.h" // ECk_ProcessorLoadPolicy
#include "CkEcs/Scheduler/CkProcessorGraph.h"
#include "CkEcs/Scheduler/CkProcessorScheduler.h"  // ECk_SchedulerTickScope
#include "CkEcs/Scheduler/CkProcessorTraits.inl.h"
#include "CkEcs/Tag/CkTag.h"
#include "CkEcs/World/CkEcsWorld.h"

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
// Pins the Phase-2 load gate (spec §4.3): the scheduler's LoadKernel tick scope dispatches ONLY processors marked
// `static constexpr auto LoadPolicy = ECk_ProcessorLoadPolicy::RunsDuringLoad`, and the Full scope dispatches every
// processor. The inverse assertion (kernel counter > 0 under LoadKernel) is the load-bearing one — over-gating (a
// kernel-needed processor left gated) manifests as a silent HANG in a real load, so a test that only checked
// "gated == 0" could pass while the world froze.
//
// Hermetic (mirrors Test_Scheduler_PumpGating.cpp): two test processors are fed to the graph builder directly, so
// they never appear in a real world's graph (no CK_REGISTER_PROCESSOR), against a private ck::FEcsWorld.
// --------------------------------------------------------------------------------------------------------------------

namespace ck
{
    CK_DEFINE_ECS_TAG(FTag_LoadGateScopeTest_Marker);
}

namespace ck_test_loadgate_scope
{
    constexpr auto kFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::ProductFilter;

    // Default LoadPolicy (GatedDuringLoad): must NOT tick under LoadKernel scope. No MarkedDirtyBy, so it runs every
    // main pass (counting ticks) regardless of dirty state.
    class FProcessor_LoadGateScopeTest_Gated
        : public ck::TProcessor<FProcessor_LoadGateScopeTest_Gated, ck::FTag_LoadGateScopeTest_Marker>
    {
    public:
        using Super = ck::TProcessor<FProcessor_LoadGateScopeTest_Gated, ck::FTag_LoadGateScopeTest_Marker>;
        using Super::Super;

        static inline int32 Count = 0;
        static auto Reset() -> void { Count = 0; }

        auto ForEachEntity(TimeType, HandleType) -> void { ++Count; }
    };

    // Load-gate kernel (RunsDuringLoad): ticks under BOTH scopes.
    class FProcessor_LoadGateScopeTest_Kernel
        : public ck::TProcessor<FProcessor_LoadGateScopeTest_Kernel, ck::FTag_LoadGateScopeTest_Marker>
    {
    public:
        using Super = ck::TProcessor<FProcessor_LoadGateScopeTest_Kernel, ck::FTag_LoadGateScopeTest_Marker>;
        using Super::Super;
        static constexpr auto LoadPolicy = ECk_ProcessorLoadPolicy::RunsDuringLoad;

        static inline int32 Count = 0;
        static auto Reset() -> void { Count = 0; }

        auto ForEachEntity(TimeType, HandleType) -> void { ++Count; }
    };

    struct FLoadGateFixture
    {
        ck::FEcsWorld World;
        TUniquePtr<ck::FProcessorScheduler> Scheduler;

        auto Build() -> bool
        {
            const auto TransientHandle = UCk_Utils_EntityLifetime_UE::Get_TransientEntity(World.Get_Registry());

            auto Descriptors = TArray<ck::FProcessorDescriptor>{};
            Descriptors.Add(ck::BuildDescriptor<FProcessor_LoadGateScopeTest_Gated>(
                [](const FCk_Registry& InRegistry) -> ck::concepts::FTickableType
                { return FProcessor_LoadGateScopeTest_Gated{InRegistry}; }));
            Descriptors.Add(ck::BuildDescriptor<FProcessor_LoadGateScopeTest_Kernel>(
                [](const FCk_Registry& InRegistry) -> ck::concepts::FTickableType
                { return FProcessor_LoadGateScopeTest_Kernel{InRegistry}; }));

            auto Builder = ck::FProcessorGraphBuilder{};
            auto Graph = Builder.Build(Descriptors, World.Get_Registry(), TransientHandle);

            for (auto& Kvp : Graph._Partitions)
            {
                if (Kvp.Value._Nodes.Num() > 0)
                {
                    Scheduler = MakeUnique<ck::FProcessorScheduler>(MoveTemp(Kvp.Value));
                    return true;
                }
            }
            return false;
        }

        auto Tick(ck::ECk_SchedulerTickScope InScope) -> void
        {
            Scheduler->Tick(FCk_Time{1.0f / 60.0f}, World.Get_Registry(), InScope);
        }

        auto CreateEntity() -> FCk_Handle
        {
            return UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
        }
    };
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_LoadGate_GatedSkipsKernelTicks,
    "Ck.Snapshot.LoadGate.GatedSkipsKernelTicks",
    ck_test_loadgate_scope::kFlags)

bool FCk_Snapshot_LoadGate_GatedSkipsKernelTicks::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_loadgate_scope;

    auto Fixture = FLoadGateFixture{};
    if (NOT TestTrue(TEXT("fixture built a scheduler with both processors"), Fixture.Build()))
    { return false; }

    auto Entity = Fixture.CreateEntity();
    Entity.Add<ck::FTag_LoadGateScopeTest_Marker>();

    constexpr auto NumFrames = 3;

    // ---- Full scope: both the gated and the kernel processor tick every frame. ----------------------------------
    FProcessor_LoadGateScopeTest_Gated::Reset();
    FProcessor_LoadGateScopeTest_Kernel::Reset();
    for (auto Frame = 0; Frame < NumFrames; ++Frame)
    { Fixture.Tick(ck::ECk_SchedulerTickScope::Full); }

    TestEqual(TEXT("Full scope ticks the gated processor every frame"),
        FProcessor_LoadGateScopeTest_Gated::Count, NumFrames);
    TestEqual(TEXT("Full scope ticks the kernel processor every frame"),
        FProcessor_LoadGateScopeTest_Kernel::Count, NumFrames);

    // ---- LoadKernel scope: the gated processor is skipped; the kernel processor STILL ticks. ---------------------
    FProcessor_LoadGateScopeTest_Gated::Reset();
    FProcessor_LoadGateScopeTest_Kernel::Reset();
    for (auto Frame = 0; Frame < NumFrames; ++Frame)
    { Fixture.Tick(ck::ECk_SchedulerTickScope::LoadKernel); }

    TestEqual(TEXT("LoadKernel scope does NOT tick the gated processor"),
        FProcessor_LoadGateScopeTest_Gated::Count, 0);
    // The inverse assertion — over-gating (kernel-needed processor left gated) would hang a real load.
    TestEqual(TEXT("LoadKernel scope STILL ticks the RunsDuringLoad kernel processor (not over-gated)"),
        FProcessor_LoadGateScopeTest_Kernel::Count, NumFrames);

    // ---- Back to Full scope: the gated processor resumes. -------------------------------------------------------
    FProcessor_LoadGateScopeTest_Gated::Reset();
    FProcessor_LoadGateScopeTest_Kernel::Reset();
    Fixture.Tick(ck::ECk_SchedulerTickScope::Full);

    TestEqual(TEXT("gated processor resumes ticking once the gate is lifted"),
        FProcessor_LoadGateScopeTest_Gated::Count, 1);
    TestEqual(TEXT("kernel processor still ticks under Full"),
        FProcessor_LoadGateScopeTest_Kernel::Count, 1);

    FProcessor_LoadGateScopeTest_Gated::Reset();
    FProcessor_LoadGateScopeTest_Kernel::Reset();

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
