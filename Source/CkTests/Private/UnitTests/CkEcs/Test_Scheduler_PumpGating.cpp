#include "CkCore/Macros/CkMacros.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Processor/CkProcessor.h"
#include "CkEcs/Scheduler/CkProcessorGraph.h"
#include "CkEcs/Scheduler/CkProcessorScheduler.h"
#include "CkEcs/Scheduler/CkProcessorTraits.inl.h"
#include "CkEcs/Settings/CkEcs_Settings.h"
#include "CkEcs/Tag/CkTag.h"
#include "CkEcs/World/CkEcsWorld.h"

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
// Pins the scheduler's pump-pass gating semantics introduced with the persistent dirty-marker
// version cache and the Pump() visited-count contract:
//
//   1. A pump whose dirty check is satisfied only by tombstones (in_place_delete pools never
//      report empty() after first use) visits zero entities and must NOT count as work — no
//      phantom extra pump pass, LastFramePumpCount stays 0.
//   2. The per-node version cache PERSISTS across frames: an idle frame does not even re-run the
//      dirty checker for a node whose marker versions did not move.
//   3. Work enqueued mid-frame (after the consumer's main-pass tick) still drains within the SAME
//      scheduler Tick via a pump pass — the cascade guarantee the gating must not break.
//
// Hermetic: descriptors are built and fed to the graph builder directly (no CK_REGISTER_PROCESSOR,
// so the test processor never appears in real worlds' graphs), against a private ck::FEcsWorld
// registry whose constructor provides the transient-entity context.
// --------------------------------------------------------------------------------------------------------------------

namespace ck
{
    CK_DEFINE_ECS_TAG(FTag_SchedulerPumpTest_Marker);
}

namespace ck_test_scheduler_pump
{
    constexpr auto kSchedulerPumpTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::ProductFilter;

    class FProcessor_PumpTest_Consume
        : public ck::TProcessor<FProcessor_PumpTest_Consume, ck::FTag_SchedulerPumpTest_Marker>
    {
    public:
        using Super = ck::TProcessor<FProcessor_PumpTest_Consume, ck::FTag_SchedulerPumpTest_Marker>;
        using Super::Super;
        using MarkedDirtyBy = ck::FTag_SchedulerPumpTest_Marker;

        // Static because IMPLEMENT_SIMPLE_AUTOMATION_TEST bodies own no fixture object and the
        // processor instance lives type-erased inside the scheduler. Reset() runs per test.
        static inline int32 ConsumedCount = 0;
        static inline int32 DirtyCheckCount = 0;
        static inline bool CascadeArmed = false;
        static inline FCk_Handle CascadeTarget;

        static auto
        Reset() -> void
        {
            ConsumedCount = 0;
            DirtyCheckCount = 0;
            CascadeArmed = false;
            CascadeTarget = {};
        }

        auto
        ForEachEntity(
            TimeType InDeltaT,
            HandleType InHandle)
            -> void
        {
            ++ConsumedCount;
            InHandle.Remove<ck::FTag_SchedulerPumpTest_Marker>();

            if (CascadeArmed)
            {
                // One-shot: enqueue the next generation on a DIFFERENT entity, after this
                // processor's pass already started — only a pump pass can drain it this Tick.
                CascadeArmed = false;
                CascadeTarget.Add<ck::FTag_SchedulerPumpTest_Marker>();
            }
        }
    };

    // Hermetic registry + a single-processor scheduler whose dirty checker counts invocations.
    struct FPumpTestFixture
    {
        ck::FEcsWorld World;
        TUniquePtr<ck::FProcessorScheduler> Scheduler;

        auto
        Build() -> bool
        {
            const auto TransientHandle = UCk_Utils_EntityLifetime_UE::Get_TransientEntity(World.Get_Registry());

            auto Descriptor = ck::BuildDescriptor<FProcessor_PumpTest_Consume>(
                [](const FCk_Registry& InRegistry) -> ck::concepts::FTickableType
                {
                    return FProcessor_PumpTest_Consume{InRegistry};
                });

            // Wrap the generated checker so the tests can observe whether a pump pass
            // re-evaluated it (the persistence pin). Behavior is unchanged.
            const auto OriginalChecker = Descriptor._IsDirtyChecker;
            Descriptor._IsDirtyChecker = [OriginalChecker](const FCk_Registry& InRegistry) -> bool
            {
                ++FProcessor_PumpTest_Consume::DirtyCheckCount;
                return OriginalChecker(InRegistry);
            };

            auto Descriptors = TArray<ck::FProcessorDescriptor>{};
            Descriptors.Add(MoveTemp(Descriptor));

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

        auto
        Tick() -> void
        {
            Scheduler->Tick(FCk_Time{1.0f / 60.0f}, World.Get_Registry());
        }

        auto
        CreateEntity() -> FCk_Handle
        {
            return UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
        }
    };
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Scheduler_Pump_NoOpPumpDoesNotScheduleExtraPass,
    "CkTests.UnitTests.CkEcs.Scheduler.Pump_NoOpPumpDoesNotScheduleExtraPass",
    ck_test_scheduler_pump::kSchedulerPumpTestFlags)

bool FCkTest_Scheduler_Pump_NoOpPumpDoesNotScheduleExtraPass::RunTest(const FString& Parameters)
{
    using namespace ck_test_scheduler_pump;

    auto Fixture = FPumpTestFixture{};
    if (NOT TestTrue(TEXT("fixture built a scheduler"), Fixture.Build()))
    { return false; }

    auto Entity = Fixture.CreateEntity();
    Entity.Add<ck::FTag_SchedulerPumpTest_Marker>();

    FProcessor_PumpTest_Consume::Reset();
    Fixture.Tick();

    // Main pass drains the marker; the pump pass then sees a version change and a
    // tombstone-satisfied dirty check, dispatches a pump that visits zero entities — which must
    // NOT count as work, so no second pump pass is scheduled and the frame's pump count is zero.
    TestEqual(TEXT("marker consumed by the main pass"),
        FProcessor_PumpTest_Consume::ConsumedCount, 1);
    TestEqual(TEXT("zero-visited pump does not count as a productive pump pass"),
        Fixture.Scheduler->Get_LastFramePumpCount(), 0);
    TestEqual(TEXT("dirty checker evaluated exactly once (first pass after the version moved)"),
        FProcessor_PumpTest_Consume::DirtyCheckCount, 1);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Scheduler_Pump_IdleFramePersistentCacheSkipsDirtyCheck,
    "CkTests.UnitTests.CkEcs.Scheduler.Pump_IdleFramePersistentCacheSkipsDirtyCheck",
    ck_test_scheduler_pump::kSchedulerPumpTestFlags)

bool FCkTest_Scheduler_Pump_IdleFramePersistentCacheSkipsDirtyCheck::RunTest(const FString& Parameters)
{
    using namespace ck_test_scheduler_pump;

    auto Fixture = FPumpTestFixture{};
    if (NOT TestTrue(TEXT("fixture built a scheduler"), Fixture.Build()))
    { return false; }

    auto Entity = Fixture.CreateEntity();
    Entity.Add<ck::FTag_SchedulerPumpTest_Marker>();

    FProcessor_PumpTest_Consume::Reset();
    Fixture.Tick(); // frame 1: drains the marker, caches the observed version

    FProcessor_PumpTest_Consume::Reset();
    Fixture.Tick(); // frame 2: fully idle — no registry mutation of any kind

    TestEqual(TEXT("idle frame consumed nothing"),
        FProcessor_PumpTest_Consume::ConsumedCount, 0);
    TestEqual(TEXT("idle frame ran zero productive pump passes"),
        Fixture.Scheduler->Get_LastFramePumpCount(), 0);

    if (UCk_Utils_Ecs_Settings_UE::Get_EnableDirtyMarkerPumpShortCircuit())
    {
        // The persistence pin: the version cache survives across frames, so an idle frame skips
        // the Has_AnyEntityWith evaluation entirely (a per-frame cache reset would re-run it and,
        // with a tombstone-polluted marker pool, phantom-pump every frame).
        TestEqual(TEXT("idle frame did not re-evaluate the dirty checker"),
            FProcessor_PumpTest_Consume::DirtyCheckCount, 0);
    }
    else
    {
        AddInfo(TEXT("EnableDirtyMarkerPumpShortCircuit is disabled — persistence assertion skipped ")
                TEXT("(legacy path re-evaluates the checker every pass by design)"));
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Scheduler_Pump_MidFrameEnqueueDrainsSameTick,
    "CkTests.UnitTests.CkEcs.Scheduler.Pump_MidFrameEnqueueDrainsSameTick",
    ck_test_scheduler_pump::kSchedulerPumpTestFlags)

bool FCkTest_Scheduler_Pump_MidFrameEnqueueDrainsSameTick::RunTest(const FString& Parameters)
{
    using namespace ck_test_scheduler_pump;

    auto Fixture = FPumpTestFixture{};
    if (NOT TestTrue(TEXT("fixture built a scheduler"), Fixture.Build()))
    { return false; }

    auto First = Fixture.CreateEntity();
    auto Second = Fixture.CreateEntity();
    First.Add<ck::FTag_SchedulerPumpTest_Marker>();

    FProcessor_PumpTest_Consume::Reset();
    FProcessor_PumpTest_Consume::CascadeArmed = true;
    FProcessor_PumpTest_Consume::CascadeTarget = Second;

    Fixture.Tick();

    // First drains in the main pass and enqueues Second's marker mid-frame; only a pump pass can
    // drain Second within this Tick. This is the cascade guarantee the visited-count gating and
    // the persistent version cache must preserve.
    TestEqual(TEXT("both generations drained within one scheduler Tick"),
        FProcessor_PumpTest_Consume::ConsumedCount, 2);
    TestEqual(TEXT("exactly one productive pump pass"),
        Fixture.Scheduler->Get_LastFramePumpCount(), 1);

    // Cleanup of static handle state (entities die with the fixture's world).
    FProcessor_PumpTest_Consume::Reset();

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
