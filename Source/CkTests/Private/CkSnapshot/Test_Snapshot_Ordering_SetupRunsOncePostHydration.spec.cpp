// What a feature's Setup is allowed to assume. The sanctioned shape is: composition stamps a Session NeedsSetup
// tag, a Setup processor consumes it once and builds the feature's session state from its inputs. On a load those
// inputs include the RESTORED values — which only holds if Setup runs after hydration and runs exactly once. Get
// either half wrong and the feature comes back structurally present and functionally wrong: Setup either reads a
// construct default and derives everything from it, or runs twice and doubles whatever it seeds.
// Surface in Session Frontend: Ck.Snapshot.Ordering.SetupRunsOncePostHydration

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

namespace ck_test_ordering_setup_once
{
    const auto SlotName = FName{TEXT("CkSnapshot_Ordering_SetupOnce_GateSlot")};

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
    FCk_Snapshot_Ordering_SetupRunsOncePostHydration_Gate,
    "Ck.Snapshot.Ordering.SetupRunsOncePostHydration",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_Ordering_SetupRunsOncePostHydration_Gate::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_ordering_setup_once;
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
    });

    // The run counter lives on the entity and is composed fresh by every construction, so post-load it counts the
    // LOAD's Setup runs and nothing from the session that saved it. That is what makes "exactly once" readable
    // after a second cycle too.
    Spec.Assert = FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
    {
        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
        auto AllGood = TestTrue(TEXT("post-load server world resolves"), Server != nullptr);
        if (Server == nullptr)
        { return false; }

        const auto Probe = ResolveProbe(Server);
        if (NOT TestTrue(TEXT("the probe was restored (the load ran)"), ck::IsValid(Probe)))
        { return false; }

        AllGood &= TestTrue(TEXT("the probe still carries its Setup record"),
            Probe.Has<ck::FFragment_AutoTest_Ordering_SetupLog>());
        if (NOT Probe.Has<ck::FFragment_AutoTest_Ordering_SetupLog>())
        { return false; }

        const auto& Log = Probe.Get<ck::FFragment_AutoTest_Ordering_SetupLog>();

        AllGood &= TestEqual(
            TEXT("Setup ran exactly once on the restored entity"), Log._RunCount, 1);

        AllGood &= TestEqual(
            TEXT("and what it read was the RESTORED value, not the construct default"),
            Log._ObservedA, SavedValueA);

        // The setup marker is a Session tag: composition stamps it, Setup consumes it, and hydration must never
        // put it back. A marker still present here would mean Setup is armed to run again.
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
