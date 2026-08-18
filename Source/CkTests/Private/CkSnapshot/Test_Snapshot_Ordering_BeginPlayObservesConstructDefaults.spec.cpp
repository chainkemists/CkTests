// The ordering contract has two halves, and this pins both against the same probe:
//
//   DoConstruct and DoBeginPlay observe CONSTRUCT DEFAULTS.
//   Restored values are observable in a quarantine-gated Setup processor, and in Promise_OnHydrated.
//
// The polarity is deliberate. Holding DoBeginPlay until hydration was designed and rejected — features
// compose children and spawn from it, so a hold deadlocks against NotReady and orphans the rows it meant to
// protect. That makes "BeginPlay sees the construct default" a DECISION, and a decision nobody wrote a test
// for is one a future change reverses by accident: someone adds a TExclude<FTag_Hydration_Quarantine> to the
// BeginPlay processor to fix a symptom, every BeginPlay read starts returning restored values, and the
// deadlock arrives weeks later in a feature that composes from it.
//
// Asserting only the first half would be a trap of its own — it would read as "the restored value is
// unreachable". So the second half is asserted beside it: the same DoBeginPlay binds Promise_OnHydrated, and
// that promise delivers the restored value. The test says where the value ISN'T and where it IS.
// Surface in Session Frontend: Ck.Snapshot.Ordering.BeginPlayObservesConstructDefaults

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel

#include "CkEcs/EntityScript/CkEntityScript_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkTests/Snapshot/CkAutoTest_Snapshot_Ordering.h"
#include "CkTests/Snapshot/CkSnapshot_TestHarness_Common.h"

namespace ck_test_ordering_beginplay
{
    const auto SlotName = FName{TEXT("CkSnapshot_Ordering_BeginPlay_GateSlot")};

    auto ResolveProbe(UWorld* InWorld) -> FCk_Handle
    {
        if (InWorld == nullptr)
        { return {}; }
        return ck::auto_test::snapshot::ResolveEntityBySpawnRecipe(
            InWorld, UCk_AutoTest_Snapshot_OrderingProbe_EntityScript_UE::StaticClass());
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Ordering_BeginPlayObservesConstructDefaults,
    "Ck.Snapshot.Ordering.BeginPlayObservesConstructDefaults",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_Ordering_BeginPlayObservesConstructDefaults::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_ordering_beginplay;
    using namespace ck_autotest_snapshot_ordering;

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = SlotName;

    // ONE cycle, deliberately. Promise_OnHydrated fires once per LOAD, and the observation counters are reset in
    // Mutate — which the harness runs once, before the cycle loop — so under the default two cycles the count
    // below reads 2 for a framework that is behaving correctly. Resetting inside Assert is not the fix: Assert is
    // a polled predicate, re-run every tick until it passes. Once-ness ACROSS loads is pinned by
    // Ck.Snapshot.Ordering.QuarantineAlwaysLiftsAtFinish clause (c), which is where it belongs.
    Spec.NumCycles = 1;

    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    {
        if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
        { CVar->Set(1, ECVF_SetByCode); }

        auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
        UCk_Utils_EntityScript_UE::Request_SpawnEntity(
            Transient, UCk_AutoTest_Snapshot_OrderingProbe_EntityScript_UE::StaticClass(),
            FInstancedStruct{}, {});
        UCk_Utils_EntityScript_UE::Request_SpawnEntity(
            Transient, UCk_AutoTest_Snapshot_OrderingProbeB_EntityScript_UE::StaticClass(),
            FInstancedStruct{}, {});
    });

    Spec.SubjectReady = FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
    {
        const auto Probe = ResolveProbe(ck::auto_test::snapshot::Get_PostTravelServerWorld());
        return ck::IsValid(Probe) && Probe.Has<ck::FFragment_AutoTest_Ordering_State>();
    });

    Spec.Mutate = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    {
        auto Probe = ResolveProbe(InServer);
        if (ck::Is_NOT_Valid(Probe))
        { return; }

        Probe.Get<ck::FFragment_AutoTest_Ordering_State>()._ValueA = SavedValueA;

        // Reset immediately before the save so every count below describes the LOAD's construction, not the
        // spawn that produced the world being saved.
        Reset_Observations();
    });

    Spec.Assert = FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
    {
        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
        auto AllGood = TestTrue(TEXT("post-load server world resolves"), Server != nullptr);
        if (Server == nullptr)
        { return false; }

        auto Probe = ResolveProbe(Server);
        if (NOT TestTrue(TEXT("the probe was restored (the load ran)"), ck::IsValid(Probe)))
        { return false; }

        auto& Obs = Get_Observations();

        // Positive control. Without this, every assertion below passes for an entity whose BeginPlay never ran.
        if (NOT TestTrue(TEXT("the restored probe's DoBeginPlay ran"), Obs.BeginPlayRan))
        { return false; }

        AllGood &= TestEqual(
            TEXT("DoBeginPlay observed the CONSTRUCT DEFAULT, not the restored value — a restored value here "
                 "means something started holding BeginPlay for the load, which deadlocks features that "
                 "compose or spawn from it"),
            Obs.BeginPlayObservedA, 0);

        AllGood &= TestNotEqual(
            TEXT("and the construct default is genuinely distinguishable from the saved value (otherwise the "
                 "assertion above is vacuous)"),
            SavedValueA, 0);

        AllGood &= TestEqual(
            TEXT("Promise_OnHydrated, bound from that same DoBeginPlay, fired exactly once"),
            Obs.OnHydratedFireCount, 1);

        AllGood &= TestEqual(
            TEXT("and it delivered the RESTORED value — this is where a consumer without a Setup processor "
                 "reads restored state"),
            Obs.OnHydratedObservedA, SavedValueA);

        return AllGood;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
