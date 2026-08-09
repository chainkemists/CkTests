#include "CkCore/Macros/CkMacros.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Processor/CkProcessor.h"
#include "CkEcs/Processor/CkProcessor_CadenceBuckets.h"
#include "CkEcs/Scheduler/CkProcessorGraph.h"
#include "CkEcs/Scheduler/CkProcessorScheduler.h"
#include "CkEcs/Scheduler/CkProcessorTraits.inl.h"
#include "CkEcs/Settings/CkEcs_Settings.h"
#include "CkEcs/Tag/CkTag.h"
#include "CkEcs/World/CkEcsWorld.h"

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
// Pins the RUNTIME semantics of the compile-time TickRate trait (TProcessorBase, CkProcessor.h) and the
// bucketed-cadence primitive (CkProcessor_CadenceBuckets.h) — the behaviors the pure spec
// (CkEcs/Processor/CkProcessor_CadenceBuckets.spec.cpp) cannot reach:
//
//   1. A processor declaring `static constexpr FCk_Time TickRate = ck::time::Hz(4)` fires once per 0.25s of
//      accumulated scheduler time while a trait-LESS processor over the same view fires every tick.
//   2. TickCatchUpPolicy: after a multi-interval hitch, ReplayMissedTicks (default) replays DoTick per
//      whole interval with DeltaT = the interval; SampleLatestOnly fires ONCE with the summed elapsed.
//   2b. MaxReplayedTicks: the same hitch replayed by a clamped and an unclamped processor side by side —
//      the bound caps the burst, the absent trait preserves today's unbounded replay, and the excess is
//      DROPPED rather than left in the accumulator to replay again next frame.
//   3. Bucket immediate-first-eval: an entity quantized into a nonzero bucket is evaluated on the FIRST
//      tick after AddCadenceTags (via its transient bucket-0 membership), not an interval later, and the
//      transient tags are consumed by that evaluation.
//   4. The wake-alignment phase contract: a bucket's accumulator FREEZES while its view is provably
//      empty (the scheduler's empty-view skip bypasses the whole dispatch), so the first cadence fire
//      lands exactly one interval after the entity's arrival — NOT early out of a stale mid-phase
//      accumulator. This is the property Ck_AutoTest_VisibleRange_CadenceGatesUpdates depends on.
//
// Determinism: the step is 1/64 s — binary-exact, so accumulated sums hit the rated intervals EXACTLY
// (16 steps = 0.25s, 32 steps = 0.5s) with no float-drift flake in the fire counts.
//
// Hermetic: descriptors are built and fed to the graph builder directly (no CK_REGISTER_PROCESSOR, so
// these processors never appear in real worlds' graphs), against a private ck::FEcsWorld registry —
// the same fixture shape as Test_Scheduler_PumpGating.cpp.
// --------------------------------------------------------------------------------------------------------------------

namespace ck
{
    CK_DEFINE_ECS_TAG(FTag_TickRateTest_Subject);
}

namespace ck_test_tickrate_trait
{
    constexpr auto kTickRateTestFlags =
        EAutomationTestFlags::EditorContext |
        EAutomationTestFlags::ClientContext |
        EAutomationTestFlags::ProductFilter;

    // Binary-exact step (0.015625) — see the determinism note above.
    constexpr auto kStepSeconds = 1.0 / 64.0;

    // ----------------------------------------------------------------------------------------------------------------

    class FProcessor_TickRateTest_Unrated
        : public ck::TProcessor<FProcessor_TickRateTest_Unrated, ck::FTag_TickRateTest_Subject>
    {
    public:
        using Super = ck::TProcessor<FProcessor_TickRateTest_Unrated, ck::FTag_TickRateTest_Subject>;
        using Super::Super;

        static inline int32 FireCount = 0;

        auto
        ForEachEntity(
            TimeType InDeltaT,
            HandleType InHandle)
            -> void
        {
            ++FireCount;
        }
    };

    class FProcessor_TickRateTest_RatedReplay
        : public ck::TProcessor<FProcessor_TickRateTest_RatedReplay, ck::FTag_TickRateTest_Subject>
    {
    public:
        using Super = ck::TProcessor<FProcessor_TickRateTest_RatedReplay, ck::FTag_TickRateTest_Subject>;
        using Super::Super;

        // THE one-line author declaration under test. Default catch-up = ReplayMissedTicks.
        static constexpr auto TickRate = ck::time::Hz(4);

        static inline int32 FireCount = 0;
        static inline double LastDeltaSeconds = 0.0;

        auto
        ForEachEntity(
            TimeType InDeltaT,
            HandleType InHandle)
            -> void
        {
            ++FireCount;
            LastDeltaSeconds = InDeltaT.Get_Seconds();
        }
    };

    // Identical to RatedReplay except for the clamp, so a side-by-side hitch isolates the trait: same view,
    // same rate, same tick.
    class FProcessor_TickRateTest_RatedReplayClamped
        : public ck::TProcessor<FProcessor_TickRateTest_RatedReplayClamped, ck::FTag_TickRateTest_Subject>
    {
    public:
        using Super = ck::TProcessor<FProcessor_TickRateTest_RatedReplayClamped, ck::FTag_TickRateTest_Subject>;
        using Super::Super;

        static constexpr auto TickRate = ck::time::Hz(4);
        static constexpr int32 MaxReplayedTicks = 2;

        static inline int32 FireCount = 0;
        static inline double LastDeltaSeconds = 0.0;

        auto
        ForEachEntity(
            TimeType InDeltaT,
            HandleType InHandle)
            -> void
        {
            ++FireCount;
            LastDeltaSeconds = InDeltaT.Get_Seconds();
        }
    };

    class FProcessor_TickRateTest_RatedSample
        : public ck::TProcessor<FProcessor_TickRateTest_RatedSample, ck::FTag_TickRateTest_Subject>
    {
    public:
        using Super = ck::TProcessor<FProcessor_TickRateTest_RatedSample, ck::FTag_TickRateTest_Subject>;
        using Super::Super;

        static constexpr auto TickRate = ck::time::Seconds(0.25);
        static constexpr auto TickCatchUpPolicy = ECk_ProcessorTickCatchUp::SampleLatestOnly;

        static inline int32 FireCount = 0;
        static inline double LastDeltaSeconds = 0.0;

        auto
        ForEachEntity(
            TimeType InDeltaT,
            HandleType InHandle)
            -> void
        {
            ++FireCount;
            LastDeltaSeconds = InDeltaT.Get_Seconds();
        }
    };

    // ----------------------------------------------------------------------------------------------------------------
    // The bucket family under test — FCk_Handle doubles as the cadence key (no production consumer uses
    // the plain handle as a key, and the registry is private to each fixture anyway). Counters are shared
    // across the 7 instantiations via a non-template holder.

    struct FBucketTestState
    {
        static inline int32 TotalEvalCount = 0;

        static auto
        Reset() -> void
        {
            TotalEvalCount = 0;
        }
    };

    template <int32 T_BucketIndex>
    class FProcessor_TickRateTest_Bucket : public ck::TCadenceBucketProcessor<
        FProcessor_TickRateTest_Bucket<T_BucketIndex>,
        FProcessor_TickRateTest_Bucket,
        T_BucketIndex,
        FCk_Handle>
    {
    public:
        using BucketBase = typename FProcessor_TickRateTest_Bucket::TCadenceBucketProcessor;
        using BucketBase::BucketBase;

        static auto
        ForEachEntity(
            FCk_Time InDeltaT,
            FCk_Handle InHandle)
            -> void
        {
            ck::cadence::TryConsume_FirstEval<FCk_Handle>(InHandle);
            ++FBucketTestState::TotalEvalCount;
        }
    };

    // ----------------------------------------------------------------------------------------------------------------

    struct FTickRateTestFixture
    {
        ck::FEcsWorld World;
        TUniquePtr<ck::FProcessorScheduler> Scheduler;

        auto
        Build(TArray<ck::FProcessorDescriptor>&& InDescriptors) -> bool
        {
            const auto TransientHandle = UCk_Utils_EntityLifetime_UE::Get_TransientEntity(World.Get_Registry());

            auto Builder = ck::FProcessorGraphBuilder{};
            auto Graph = Builder.Build(InDescriptors, World.Get_Registry(), TransientHandle);

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
        TickWith(FCk_Time InDeltaT) -> void
        {
            Scheduler->Tick(InDeltaT, World.Get_Registry());
        }

        auto
        TickSteps(int32 InCount) -> void
        {
            for (auto Index = int32{0}; Index < InCount; ++Index)
            { TickWith(FCk_Time{kStepSeconds}); }
        }

        auto
        CreateEntity() -> FCk_Handle
        {
            return UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
        }
    };

    template <typename T_Processor>
    auto
    MakeDescriptor() -> ck::FProcessorDescriptor
    {
        return ck::BuildDescriptor<T_Processor>(
            [](const FCk_Registry& InRegistry) -> ck::concepts::FTickableType
            {
                return T_Processor{InRegistry};
            });
    }

    auto
    MakeRatedTrioDescriptors() -> TArray<ck::FProcessorDescriptor>
    {
        auto Descriptors = TArray<ck::FProcessorDescriptor>{};
        Descriptors.Add(MakeDescriptor<FProcessor_TickRateTest_Unrated>());
        Descriptors.Add(MakeDescriptor<FProcessor_TickRateTest_RatedReplay>());
        Descriptors.Add(MakeDescriptor<FProcessor_TickRateTest_RatedSample>());
        return Descriptors;
    }

    auto
    MakeClampPairDescriptors() -> TArray<ck::FProcessorDescriptor>
    {
        auto Descriptors = TArray<ck::FProcessorDescriptor>{};
        Descriptors.Add(MakeDescriptor<FProcessor_TickRateTest_RatedReplay>());
        Descriptors.Add(MakeDescriptor<FProcessor_TickRateTest_RatedReplayClamped>());
        return Descriptors;
    }

    template <int32... T_BucketIndices>
    auto
    DoMakeBucketDescriptors(std::integer_sequence<int32, T_BucketIndices...>) -> TArray<ck::FProcessorDescriptor>
    {
        auto Descriptors = TArray<ck::FProcessorDescriptor>{};
        (Descriptors.Add(MakeDescriptor<FProcessor_TickRateTest_Bucket<T_BucketIndices>>()), ...);
        return Descriptors;
    }

    auto
    MakeBucketFamilyDescriptors() -> TArray<ck::FProcessorDescriptor>
    {
        return DoMakeBucketDescriptors(std::make_integer_sequence<int32, ck::cadence::BucketCount>{});
    }

    auto
    ResetAllCounters() -> void
    {
        FProcessor_TickRateTest_Unrated::FireCount = 0;
        FProcessor_TickRateTest_RatedReplay::FireCount = 0;
        FProcessor_TickRateTest_RatedReplay::LastDeltaSeconds = 0.0;
        FProcessor_TickRateTest_RatedReplayClamped::FireCount = 0;
        FProcessor_TickRateTest_RatedReplayClamped::LastDeltaSeconds = 0.0;
        FProcessor_TickRateTest_RatedSample::FireCount = 0;
        FProcessor_TickRateTest_RatedSample::LastDeltaSeconds = 0.0;
        FBucketTestState::Reset();
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Processor_TickRateTrait_RatedFiresAtDeclaredRate,
    "CkTests.UnitTests.CkEcs.Processor.TickRateTrait_RatedFiresAtDeclaredRate",
    ck_test_tickrate_trait::kTickRateTestFlags)

bool FCkTest_Processor_TickRateTrait_RatedFiresAtDeclaredRate::RunTest(const FString& Parameters)
{
    using namespace ck_test_tickrate_trait;

    auto Fixture = FTickRateTestFixture{};
    if (NOT TestTrue(TEXT("fixture built a scheduler"), Fixture.Build(MakeRatedTrioDescriptors())))
    { return false; }

    auto Entity = Fixture.CreateEntity();
    Entity.Add<ck::FTag_TickRateTest_Subject>();

    ResetAllCounters();
    Fixture.TickSteps(64); // 64 * (1/64)s = exactly 1.0s of scheduler time

    TestEqual(TEXT("trait-less processor fired every tick"),
        FProcessor_TickRateTest_Unrated::FireCount, 64);
    TestEqual(TEXT("Hz{4} processor fired exactly 4 times over 1.0s"),
        FProcessor_TickRateTest_RatedReplay::FireCount, 4);
    TestEqual(TEXT("each rated fire received DeltaT = the 0.25s interval"),
        FProcessor_TickRateTest_RatedReplay::LastDeltaSeconds, 0.25);
    TestEqual(TEXT("Seconds{0.25} spelling fired at the same rate"),
        FProcessor_TickRateTest_RatedSample::FireCount, 4);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Processor_TickRateTrait_CatchUpPolicies,
    "CkTests.UnitTests.CkEcs.Processor.TickRateTrait_CatchUpPolicies",
    ck_test_tickrate_trait::kTickRateTestFlags)

bool FCkTest_Processor_TickRateTrait_CatchUpPolicies::RunTest(const FString& Parameters)
{
    using namespace ck_test_tickrate_trait;

    auto Fixture = FTickRateTestFixture{};
    if (NOT TestTrue(TEXT("fixture built a scheduler"), Fixture.Build(MakeRatedTrioDescriptors())))
    { return false; }

    auto Entity = Fixture.CreateEntity();
    Entity.Add<ck::FTag_TickRateTest_Subject>();

    ResetAllCounters();
    Fixture.TickWith(FCk_Time{1.0}); // one hitch frame spanning 4 whole 0.25s intervals

    TestEqual(TEXT("ReplayMissedTicks replayed DoTick once per elapsed interval"),
        FProcessor_TickRateTest_RatedReplay::FireCount, 4);
    TestEqual(TEXT("each replayed fire received the interval, not the hitch"),
        FProcessor_TickRateTest_RatedReplay::LastDeltaSeconds, 0.25);

    TestEqual(TEXT("SampleLatestOnly fired exactly once for the whole hitch"),
        FProcessor_TickRateTest_RatedSample::FireCount, 1);
    TestEqual(TEXT("the single sample received the summed elapsed intervals"),
        FProcessor_TickRateTest_RatedSample::LastDeltaSeconds, 1.0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Processor_TickRateTrait_ClampBoundsCatchUpReplay,
    "CkTests.UnitTests.CkEcs.Processor.TickRateTrait_ClampBoundsCatchUpReplay",
    ck_test_tickrate_trait::kTickRateTestFlags)

bool FCkTest_Processor_TickRateTrait_ClampBoundsCatchUpReplay::RunTest(const FString& Parameters)
{
    using namespace ck_test_tickrate_trait;

    auto Fixture = FTickRateTestFixture{};
    if (NOT TestTrue(TEXT("fixture built a scheduler"), Fixture.Build(MakeClampPairDescriptors())))
    { return false; }

    auto Entity = Fixture.CreateEntity();
    Entity.Add<ck::FTag_TickRateTest_Subject>();

    ResetAllCounters();
    Fixture.TickWith(FCk_Time{1.0}); // one hitch frame spanning 4 whole 0.25s intervals

    // The pair is the pin: the two processors differ ONLY by the trait, so the unclamped count is
    // simultaneously the clamp's control and the proof that declaring nothing preserves today's semantics.
    TestEqual(TEXT("a processor declaring no clamp still replays every elapsed interval"),
        FProcessor_TickRateTest_RatedReplay::FireCount, 4);
    TestEqual(TEXT("MaxReplayedTicks{2} replayed exactly its bound out of the 4 elapsed intervals"),
        FProcessor_TickRateTest_RatedReplayClamped::FireCount, 2);
    TestEqual(TEXT("a clamped fire still receives the interval, not the hitch"),
        FProcessor_TickRateTest_RatedReplayClamped::LastDeltaSeconds, 0.25);

    // Dropped, not deferred. Had the excess stayed in the accumulator it would sit at 0.5s here, and the very
    // next (1/64 s) tick would immediately replay the bound again.
    Fixture.TickSteps(1);
    TestEqual(TEXT("the intervals past the bound were drained, not carried into the next frame"),
        FProcessor_TickRateTest_RatedReplayClamped::FireCount, 2);

    // ...and the phase is intact: a clamped processor keeps ticking at its declared rate afterwards.
    Fixture.TickSteps(15); // 16 steps since the hitch = exactly 0.25s
    TestEqual(TEXT("the clamped processor resumes its declared cadence after the drop"),
        FProcessor_TickRateTest_RatedReplayClamped::FireCount, 3);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Processor_CadenceBuckets_ImmediateFirstEval,
    "CkTests.UnitTests.CkEcs.Processor.CadenceBuckets_ImmediateFirstEval",
    ck_test_tickrate_trait::kTickRateTestFlags)

bool FCkTest_Processor_CadenceBuckets_ImmediateFirstEval::RunTest(const FString& Parameters)
{
    using namespace ck_test_tickrate_trait;

    auto Fixture = FTickRateTestFixture{};
    if (NOT TestTrue(TEXT("fixture built a scheduler"), Fixture.Build(MakeBucketFamilyDescriptors())))
    { return false; }

    auto Entity = Fixture.CreateEntity();
    const auto BucketIndex = ck::cadence::AddCadenceTags<FCk_Handle>(Entity, FCk_Time{0.5});

    TestEqual(TEXT("0.5s quantized into bucket 3"), BucketIndex, 3);
    TestTrue(TEXT("armed: transient bucket-0 membership"),
        Entity.Has<ck::TTag_CadenceBucket<FCk_Handle, 0>>());
    TestTrue(TEXT("armed: pending first-eval marker"),
        Entity.Has<ck::TTag_CadenceFirstEval<FCk_Handle>>());

    FBucketTestState::Reset();
    Fixture.TickSteps(1);

    // The pin: evaluated on the FIRST tick after Add — not deferred a full 0.5s interval — and the
    // evaluation consumed both transient tags (exactly once: the pump pass must not double-fire).
    TestEqual(TEXT("first eval landed on the first tick after Add"),
        FBucketTestState::TotalEvalCount, 1);
    TestTrue(TEXT("first eval consumed the transient bucket-0 tag"),
        NOT Entity.Has<ck::TTag_CadenceBucket<FCk_Handle, 0>>());
    TestTrue(TEXT("first eval consumed the first-eval marker"),
        NOT Entity.Has<ck::TTag_CadenceFirstEval<FCk_Handle>>());
    TestTrue(TEXT("native bucket-3 membership remains"),
        Entity.Has<ck::TTag_CadenceBucket<FCk_Handle, 3>>());

    // Cadence gating: no re-eval until a full 0.5s of scheduler time has accumulated since the Add.
    Fixture.TickSteps(30); // 31 steps total = 0.484375s
    TestEqual(TEXT("no re-eval inside the 0.5s interval"),
        FBucketTestState::TotalEvalCount, 1);

    Fixture.TickSteps(1); // 32 steps total = exactly 0.5s
    TestEqual(TEXT("bucket 3 re-evaluated at exactly one interval after Add"),
        FBucketTestState::TotalEvalCount, 2);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Processor_CadenceBuckets_EmptyViewFreezeAlignsPhaseToWake,
    "CkTests.UnitTests.CkEcs.Processor.CadenceBuckets_EmptyViewFreezeAlignsPhaseToWake",
    ck_test_tickrate_trait::kTickRateTestFlags)

bool FCkTest_Processor_CadenceBuckets_EmptyViewFreezeAlignsPhaseToWake::RunTest(const FString& Parameters)
{
    using namespace ck_test_tickrate_trait;

    auto Fixture = FTickRateTestFixture{};
    if (NOT TestTrue(TEXT("fixture built a scheduler"), Fixture.Build(MakeBucketFamilyDescriptors())))
    { return false; }

    // 48 steps = 0.75s of scheduler time with EVERY bucket view empty. Under the empty-view skip the
    // whole dispatch (Tick included) is bypassed, so bucket 3's accumulator stays frozen at zero. If it
    // had kept accumulating, it would sit mid-phase (0.75s mod 0.5s = 0.25s) when the entity arrives.
    FBucketTestState::Reset();
    Fixture.TickSteps(48);
    TestEqual(TEXT("empty buckets evaluated nothing"), FBucketTestState::TotalEvalCount, 0);

    auto Entity = Fixture.CreateEntity();
    ck::cadence::AddCadenceTags<FCk_Handle>(Entity, FCk_Time{0.5});

    Fixture.TickSteps(1);
    TestEqual(TEXT("immediate first eval on arrival"), FBucketTestState::TotalEvalCount, 1);

    if (UCk_Utils_Ecs_Settings_UE::Get_EnableEmptyViewMainPassSkip())
    {
        // The wake-alignment pin (what Ck_AutoTest_VisibleRange_CadenceGatesUpdates leans on): the first
        // cadence fire lands one FULL interval after the entity's arrival. A mid-phase (unfrozen)
        // accumulator would fire early — at 0.25s after arrival in this arrangement.
        Fixture.TickSteps(30); // 31 steps since arrival = 0.484375s
        TestEqual(TEXT("frozen accumulator: no early fire from the pre-arrival idle time"),
            FBucketTestState::TotalEvalCount, 1);

        Fixture.TickSteps(1); // 32 steps since arrival = exactly 0.5s
        TestEqual(TEXT("first cadence fire exactly one interval after arrival"),
            FBucketTestState::TotalEvalCount, 2);
    }
    else
    {
        AddInfo(TEXT("EnableEmptyViewMainPassSkip is disabled — wake-alignment assertions skipped ")
                TEXT("(without the skip, bucket phase is world-aligned by design)"));
    }

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
