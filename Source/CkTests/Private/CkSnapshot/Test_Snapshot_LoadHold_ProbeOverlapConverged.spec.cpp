// T-C6-2 — ready-to-resume implies the probe overlaps have converged.
//
// The framework reduction of the G1-D46 failure: a restored occupant standing inside a restored trigger, and the
// trigger not knowing it yet. Both entities are separately persisted; each one's Construct creates a probe, and
// the two probes are coincident, so the only question is WHEN the overlap becomes knowable. Before C6 the load's
// promise fired ~37 ms after the lift while Jolt had not stepped and the contact router had not run, so a
// consumer waking on Promise_OnLoadComplete read an empty overlap set and concluded the occupant was elsewhere —
// the whole class of bug the convergence phase exists to remove.
//
// The reading is taken INSIDE the promise callback, deliberately. An assertion made from the harness's Assert
// lambda runs sixty settle frames later, by which time physics has stepped anyway and the test would pass on
// every build, including the one that shipped the bug.
//
// RED before C6: no convergence phase exists, so the promise fires while Jolt has taken zero steps against the
// rebuilt bodies and FGroup_Overlap has not routed a contact.
// Surface in Session Frontend: Ck.Snapshot.LoadHold.ReadyToResumeImpliesProbeOverlapConverged

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel
#include "Misc/ScopeExit.h"
#include "StructUtils/InstancedStruct.h"

#include "CkEcs/EntityScript/CkEntityScript_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Signal/CkSignal_Macros.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Signals.h"

#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkTests/Snapshot/CkAutoTest_Snapshot_LoadHold.h"
#include "CkTests/Snapshot/CkSnapshot_TestHarness_Common.h"

namespace ck_test_loadhold_overlap
{
    const auto Overlap_SlotName = FName{TEXT("CkSnapshot_LoadHoldProbeOverlap_GateSlot")};

    auto Resolve_Trigger(UWorld* InWorld) -> FCk_Handle
    {
        return ck::auto_test::snapshot::ResolveEntityBySpawnRecipe(
            InWorld, UCk_AutoTest_Snapshot_LoadHoldTrigger_EntityScript_UE::StaticClass());
    }

    auto Resolve_Occupant(UWorld* InWorld) -> FCk_Handle
    {
        return ck::auto_test::snapshot::ResolveEntityBySpawnRecipe(
            InWorld, UCk_AutoTest_Snapshot_LoadHoldOccupant_EntityScript_UE::StaticClass());
    }

    auto PairReady() -> bool
    {
        auto* World = ck::auto_test::snapshot::Get_PostTravelServerWorld();
        return ck::IsValid(ck_autotest_snapshot_loadhold::TryGet_TriggerProbe(World))
            && ck::IsValid(ck_autotest_snapshot_loadhold::TryGet_OccupantProbe(World));
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_LoadHold_ReadyToResumeImpliesProbeOverlapConverged,
    "Ck.Snapshot.LoadHold.ReadyToResumeImpliesProbeOverlapConverged",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_LoadHold_ReadyToResumeImpliesProbeOverlapConverged::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_loadhold_overlap;

    auto* Witness = NewObject<UCk_AutoTest_Snapshot_LoadHoldWitness_UE>();
    Witness->AddToRoot();
    Witness->_SampleOverlap = true;

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = Overlap_SlotName;
    Spec.NumPIEClients = 1;
    Spec.NumCycles = 1;

    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([Witness](UWorld* InServer) -> void
    {
        if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
        { CVar->Set(1, ECVF_SetByCode); }

        auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
        UCk_Utils_EntityScript_UE::Request_SpawnEntity(
            Transient, UCk_AutoTest_Snapshot_LoadHoldTrigger_EntityScript_UE::StaticClass(), FInstancedStruct{}, {});
        UCk_Utils_EntityScript_UE::Request_SpawnEntity(
            Transient, UCk_AutoTest_Snapshot_LoadHoldOccupant_EntityScript_UE::StaticClass(), FInstancedStruct{}, {});

        auto Source = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
        auto Delegate = FCk_Delegate_Snapshot_OnPreLoad{};
        Delegate.BindUFunction(Witness, TEXT("OnPreLoad"));
        CK_SIGNAL_BIND(ck::UUtils_Signal_Snapshot_OnPreLoad, Source, Delegate,
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);
    });

    // Both probes have to exist AND be overlapping before the save, or the post-load reading is measuring a pair
    // that was never in contact rather than one whose contact had to be re-established.
    Spec.SubjectReady = FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
    {
        return PairReady()
            && ck_autotest_snapshot_loadhold::Get_TriggerContainsOccupant(
                ck::auto_test::snapshot::Get_PostTravelServerWorld());
    });

    Spec.Mutate = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* /*InServer*/) -> void
    {
        ck_autotest_snapshot_loadhold::Reset_Observations();
    });

    Spec.ReloadSettled = FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool { return PairReady(); });

    Spec.Assert = FCk_NetAutoTest_Assertion::CreateLambda([this, Witness]() -> bool
    {
        ON_SCOPE_EXIT { Witness->RemoveFromRoot(); };

        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();

        // Positive controls: both halves of the pair came back, and the promise fired once. Without them "the
        // overlap was known" could be true of a world that restored neither entity.
        auto AllGood = TestTrue(TEXT("the trigger came back"), ck::IsValid(Resolve_Trigger(Server)));
        AllGood &= TestTrue(TEXT("the occupant came back"), ck::IsValid(Resolve_Occupant(Server)));

        const auto& Observations = ck_autotest_snapshot_loadhold::Get_Observations();
        AllGood &= TestEqual(TEXT("the promise fired exactly once"), Observations.FireCount, 1);

        if (Observations.FireCount == 0)
        { return false; }

        // The assertion, read at the promise edge rather than here.
        AllGood &= TestTrue(
            TEXT("at ready-to-resume the trigger's overlap set already NAMES the occupant — physics had stepped "
                 "and the contact had been routed before the world was handed back"),
            Witness->_OverlapHeldAtFire);

        // And the world the test leaves behind agrees, so a pass above cannot come from a stale reading.
        AllGood &= TestTrue(TEXT("...and it still does once the world is running"),
            ck_autotest_snapshot_loadhold::Get_TriggerContainsOccupant(Server));

        return AllGood;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
