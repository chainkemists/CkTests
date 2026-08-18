// The cross-entity read, which is how nearly all driver/subordinate code is written: a processor iterates A and
// then reads B through a stored handle or a scan. A view filter can keep A out of an iteration; it cannot stop A's
// body from reading B directly. So releasing restored entities one at a time would leave a window where a released
// A reads a still-held B and latches its construct default — the dead-panel bug, arriving through a fix. Releasing
// the whole restored set at once closes it: the set is either all held or all released, never mixed.
// Surface in Session Frontend: Ck.Snapshot.Ordering.CrossEntityLiftIsAtomic

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

namespace ck_test_ordering_cross_entity
{
    const auto SlotName = FName{TEXT("CkSnapshot_Ordering_CrossEntity_GateSlot")};

    auto ResolveProbeA(UWorld* InWorld) -> FCk_Handle
    {
        if (InWorld == nullptr)
        { return {}; }
        return ck::auto_test::snapshot::ResolveEntityBySpawnRecipe(
            InWorld, UCk_AutoTest_Snapshot_OrderingProbe_EntityScript_UE::StaticClass());
    }

    auto ResolveProbeB(UWorld* InWorld) -> FCk_Handle
    {
        if (InWorld == nullptr)
        { return {}; }
        return ck::auto_test::snapshot::ResolveEntityBySpawnRecipe(
            InWorld, UCk_AutoTest_Snapshot_OrderingProbeB_EntityScript_UE::StaticClass());
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Ordering_CrossEntityLiftIsAtomic_Gate,
    "Ck.Snapshot.Ordering.CrossEntityLiftIsAtomic",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_Ordering_CrossEntityLiftIsAtomic_Gate::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_ordering_cross_entity;
    using namespace ck_autotest_snapshot_ordering;

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = SlotName;

    // ONE cycle: the sibling's stall is a one-shot budget, and without it the two entities hydrate on the same
    // pass and the ordering under test is never exercised.
    Spec.NumCycles = 1;

    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    {
        if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
        { CVar->Set(1, ECVF_SetByCode); }

        auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
        UCk_Utils_EntityScript_UE::Request_SpawnEntity(
            Transient, UCk_AutoTest_Snapshot_OrderingProbe_EntityScript_UE::StaticClass(), FInstancedStruct{}, {});
        UCk_Utils_EntityScript_UE::Request_SpawnEntity(
            Transient, UCk_AutoTest_Snapshot_OrderingProbeB_EntityScript_UE::StaticClass(), FInstancedStruct{}, {});
    });

    Spec.SubjectReady = FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
    {
        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
        return ck::IsValid(ResolveProbeA(Server)) && ck::IsValid(ResolveProbeB(Server));
    });

    Spec.Mutate = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    {
        auto ProbeA = ResolveProbeA(InServer);
        auto ProbeB = ResolveProbeB(InServer);
        if (ck::Is_NOT_Valid(ProbeA) || ck::Is_NOT_Valid(ProbeB))
        { return; }

        ProbeA.Get<ck::FFragment_AutoTest_Ordering_State>()._ValueA = SavedValueA;
        ProbeB.Get<ck::FFragment_AutoTest_Ordering_State>()._ValueB = SavedValueB;

        Reset_Observations();
    });

    Spec.Assert = FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
    {
        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
        auto AllGood = TestTrue(TEXT("post-load server world resolves"), Server != nullptr);
        if (Server == nullptr)
        { return false; }

        const auto ProbeA = ResolveProbeA(Server);
        const auto ProbeB = ResolveProbeB(Server);
        AllGood &= TestTrue(TEXT("both probes were restored (the load ran)"),
            ck::IsValid(ProbeA) && ck::IsValid(ProbeB));
        if (ck::Is_NOT_Valid(ProbeA) || ck::Is_NOT_Valid(ProbeB))
        { return false; }

        const auto& Observations = Get_Observations();

        // Positive control: the sibling really did lag, so A's Setup had something to be early for.
        AllGood &= TestTrue(
            FString::Printf(TEXT("the sibling's payload really stalled (stalls=%d)"), Observations.StallReturns),
            Observations.StallReturns >= 1);

        AllGood &= TestTrue(TEXT("A's Setup ran and recorded what it saw"),
            ProbeA.Has<ck::FFragment_AutoTest_Ordering_SetupLog>());
        if (NOT ProbeA.Has<ck::FFragment_AutoTest_Ordering_SetupLog>())
        { return false; }

        const auto& Log = ProbeA.Get<ck::FFragment_AutoTest_Ordering_SetupLog>();

        AllGood &= TestEqual(TEXT("A's Setup ran exactly once"), Log._RunCount, 1);

        AllGood &= TestTrue(
            TEXT("A's Setup could resolve its sibling at all"), Log._SiblingWasResolvable);

        // The assertion the per-entity release fails and the set-wide release passes.
        AllGood &= TestEqual(
            TEXT("A's Setup read the sibling's RESTORED value, so the sibling was released before A ran"),
            Log._ObservedSiblingB, SavedValueB);

        AllGood &= TestEqual(TEXT("the sibling really did restore that value"),
            ProbeB.Get<ck::FFragment_AutoTest_Ordering_State>()._ValueB, SavedValueB);

        return AllGood;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
