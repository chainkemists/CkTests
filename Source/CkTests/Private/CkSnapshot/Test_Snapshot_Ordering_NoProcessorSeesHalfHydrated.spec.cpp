// The half-hydrated read. A restored entity's payloads apply over several passes, and every gameplay processor
// runs between them — so without the load holding the entity back, a processor is handed an entity carrying one
// restored value and one construct default, and whatever it computes from that pair is wrong in a way nothing
// reports. The probe here carries two payloads and the second one refuses to apply for three passes, so the
// half-hydrated state is real; three observers, one per admission surface that builds a view, record whether they
// were ever handed it in that state.
// Surface in Session Frontend: Ck.Snapshot.Ordering.NoProcessorSeesHalfHydrated

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

namespace ck_test_ordering_half_hydrated
{
    const auto SlotName = FName{TEXT("CkSnapshot_Ordering_HalfHydrated_GateSlot")};

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
    FCk_Snapshot_Ordering_NoProcessorSeesHalfHydrated_Gate,
    "Ck.Snapshot.Ordering.NoProcessorSeesHalfHydrated",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_Ordering_NoProcessorSeesHalfHydrated_Gate::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_ordering_half_hydrated;
    using namespace ck_autotest_snapshot_ordering;

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = SlotName;

    // ONE cycle: the stall is a one-shot budget, so a second cycle would apply both payloads on the same pass and
    // the half-hydrated window this test needs would not exist.
    Spec.NumCycles = 1;

    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    {
        if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
        { CVar->Set(1, ECVF_SetByCode); }

        auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
        UCk_Utils_EntityScript_UE::Request_SpawnEntity(
            Transient, UCk_AutoTest_Snapshot_OrderingProbe_EntityScript_UE::StaticClass(), FInstancedStruct{}, {});
    });

    Spec.SubjectReady = FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
    {
        return ck::IsValid(ResolveProbe(ck::auto_test::snapshot::Get_PostTravelServerWorld()));
    });

    Spec.Mutate = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    {
        auto Probe = ResolveProbe(InServer);
        if (ck::Is_NOT_Valid(Probe))
        { return; }

        auto& State = Probe.Get<ck::FFragment_AutoTest_Ordering_State>();
        State._ValueA = SavedValueA;
        State._ValueB = SavedValueB;

        // Everything below is measured across the LOAD, so the record starts here — after the save's own
        // construction traffic and before the load exists.
        Reset_Observations();
    });

    Spec.Assert = FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
    {
        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
        auto AllGood = TestTrue(TEXT("post-load server world resolves"), Server != nullptr);
        if (Server == nullptr)
        { return false; }

        const auto Probe = ResolveProbe(Server);
        AllGood &= TestTrue(TEXT("the probe was restored (the load ran)"), ck::IsValid(Probe));

        const auto& Observations = Get_Observations();

        // Positive control FIRST: without a stall there is no half-hydrated window, and every zero below would be
        // zero for the wrong reason.
        AllGood &= TestTrue(
            FString::Printf(TEXT("the second payload really stalled, so a half-hydrated window existed (stalls=%d)"),
                Observations.StallReturns),
            Observations.StallReturns >= 1);

        // Second positive control: each observer really did tick and really was handed the probe — once the load
        // had let go of it.
        AllGood &= TestTrue(
            FString::Printf(TEXT("the ck::TProcessor observer saw the probe after release (%d)"),
                Observations.SawReleasedProbe_Ck),
            Observations.SawReleasedProbe_Ck >= 1);
        AllGood &= TestTrue(
            FString::Printf(TEXT("the ck_exp::TProcessor observer saw the probe after release (%d)"),
                Observations.SawReleasedProbe_CkExp),
            Observations.SawReleasedProbe_CkExp >= 1);
        AllGood &= TestTrue(
            FString::Printf(TEXT("the TParallelProcessor observer saw the probe after release (%d)"),
                Observations.SawReleasedProbe_Parallel),
            Observations.SawReleasedProbe_Parallel >= 1);

        // The invariant, one sub-assert per surface so a failure names which admission path leaked.
        AllGood &= TestEqual(
            TEXT("ck::TProcessor was never handed an entity the load was still holding"),
            Observations.SawHeldProbe_Ck, 0);
        AllGood &= TestEqual(
            TEXT("ck_exp::TProcessor was never handed an entity the load was still holding"),
            Observations.SawHeldProbe_CkExp, 0);
        AllGood &= TestEqual(
            TEXT("TParallelProcessor was never handed an entity the load was still holding"),
            Observations.SawHeldProbe_Parallel, 0);

        // And the values really did arrive, so the whole thing is not a load that restored nothing.
        if (ck::IsValid(Probe))
        {
            const auto& State = Probe.Get<ck::FFragment_AutoTest_Ordering_State>();
            AllGood &= TestEqual(TEXT("the first payload restored its value"), State._ValueA, SavedValueA);
            AllGood &= TestEqual(TEXT("the stalling payload restored its value too"), State._ValueB, SavedValueB);
        }

        return AllGood;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
