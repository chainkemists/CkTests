// The same contract as Ck.Snapshot.Ordering.SetupRunsOncePostHydration, asked on the path that actually happens
// in a real project's world: the ESCALATED rebuild. When the rebuild kernel quiesces with rows it cannot resolve
// — because the identity they are resolved by is stamped by a GAME processor the kernel scope never runs — the
// loader escalates to full-scope ticks. That opens every gameplay processor onto a world whose payloads are still
// un-enqueued, so a feature's one-shot Setup can run, consume its marker and derive everything from a construct
// default long before the value it was supposed to read arrives. The sibling test cannot see this: its probe
// resolves on the first rebuild tick, so it never escalates.
// Surface in Session Frontend: Ck.Snapshot.Ordering.SetupRunsOncePostHydrationEscalated

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel

#include "CkEcs/EntityScript/CkEntityScript_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkTests/Snapshot/CkAutoTest_Snapshot_Ordering.h"
#include "CkTests/Snapshot/CkSnapshot_TestHarness_Common.h"

namespace ck_test_ordering_setup_once_escalated
{
    const auto SlotName = FName{TEXT("CkSnapshot_Ordering_SetupOnceEscalated_GateSlot")};

    auto ResolveProbe(UWorld* InWorld) -> FCk_Handle
    {
        if (InWorld == nullptr)
        { return {}; }
        return ck::auto_test::snapshot::ResolveEntityBySpawnRecipe(
            InWorld, UCk_AutoTest_Snapshot_OrderingProbe_EntityScript_UE::StaticClass());
    }

    auto ResolveStaller(UWorld* InWorld) -> FCk_Handle
    {
        if (InWorld == nullptr)
        { return {}; }
        return ck::auto_test::snapshot::ResolveEntityBySpawnRecipe(
            InWorld, UCk_AutoTest_Snapshot_EscalationStaller_EntityScript_UE::StaticClass());
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Ordering_SetupRunsOncePostHydrationEscalated_Gate,
    "Ck.Snapshot.Ordering.SetupRunsOncePostHydrationEscalated",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_Ordering_SetupRunsOncePostHydrationEscalated_Gate::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_ordering_setup_once_escalated;
    using namespace ck_autotest_snapshot_ordering;

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = SlotName;

    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    {
        if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
        { CVar->Set(1, ECVF_SetByCode); }

        auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);

        UCk_Utils_EntityScript_UE::Request_SpawnEntity(
            Transient, UCk_AutoTest_Snapshot_OrderingProbe_EntityScript_UE::StaticClass(), FInstancedStruct{}, {});

        // The only reason this test differs from its sibling: this entity's labeled child is what the rebuild
        // kernel cannot resolve, and therefore what makes the loader escalate.
        UCk_Utils_EntityScript_UE::Request_SpawnEntity(
            Transient, UCk_AutoTest_Snapshot_EscalationStaller_EntityScript_UE::StaticClass(), FInstancedStruct{}, {});
    });

    // Both must exist before the save, and the staller's child must already carry its label — a save taken before
    // the labeler ran would capture an UNLABELED child, which is a save the loader has nothing to stall on.
    Spec.SubjectReady = FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
    {
        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
        return ck::IsValid(ResolveProbe(Server)) && ck::IsValid(ResolveStaller(Server));
    });

    Spec.Mutate = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    {
        auto Probe = ResolveProbe(InServer);
        if (ck::Is_NOT_Valid(Probe))
        { return; }

        auto& State = Probe.Get<ck::FFragment_AutoTest_Ordering_State>();
        State._ValueA = SavedValueA;
        State._ValueB = SavedValueB;
    });

    Spec.Assert = FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
    {
        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
        auto AllGood = TestTrue(TEXT("post-load server world resolves"), Server != nullptr);
        if (Server == nullptr)
        { return false; }

        // The load-bearing precondition. Without it every assertion below is the sibling test again, and the
        // escalated path — the one every real project load takes — stays uncovered.
        auto* Subsystem = ck::auto_test::snapshot::Get_SnapshotSubsystem(Server);
        if (NOT TestTrue(TEXT("the snapshot subsystem resolves"), Subsystem != nullptr))
        { return false; }

        AllGood &= TestTrue(
            TEXT("the load actually took the ESCALATED rebuild path (else this test is vacuous)"),
            Subsystem->Get_LastLoadReport().Get_UsedEscalatedRebuild());

        AllGood &= TestEqual(
            TEXT("and the escalation resolved the staller's child rather than orphaning it"),
            Subsystem->Get_LastLoadReport().Get_UnresolvedAfterEscalation(), 0);

        const auto Probe = ResolveProbe(Server);
        if (NOT TestTrue(TEXT("the probe was restored (the load ran)"), ck::IsValid(Probe)))
        { return false; }

        AllGood &= TestTrue(TEXT("the probe still carries its Setup record"),
            Probe.Has<ck::FFragment_AutoTest_Ordering_SetupLog>());
        if (NOT Probe.Has<ck::FFragment_AutoTest_Ordering_SetupLog>())
        { return false; }

        const auto& Log = Probe.Get<ck::FFragment_AutoTest_Ordering_SetupLog>();

        AllGood &= TestEqual(
            TEXT("Setup ran exactly once on the restored entity, across the escalated full-scope ticks too"),
            Log._RunCount, 1);

        AllGood &= TestEqual(
            TEXT("and what it read was the RESTORED value, not the construct default the escalated ticks expose"),
            Log._ObservedA, SavedValueA);

        AllGood &= TestFalse(
            TEXT("the setup marker was consumed and not re-added by the load"),
            Probe.Has<ck::FTag_AutoTest_Ordering_NeedsSetup>());

        return AllGood;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
