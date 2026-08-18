// Holding an entity out of a view is only half a guarantee. Around thirty Ck features wipe their dirty marker for
// the WHOLE registry from a shadowing DoTick, on the very pass whose view just skipped the entities a load is
// holding — so a naive exclusion would skip the entity and then destroy the very marker it was waiting to be
// processed with. It would come back released and inert: composed, visible, and never set up. Worse where the
// wiped type is the request queue, because there the queued work is destroyed rather than merely deferred.
//
// The probe here is sat next to both shapes — a marker wipe and a request-fragment wipe, both running every tick —
// and still has to end up set up exactly once with its Construct-time request drained.
// Surface in Session Frontend: Ck.Snapshot.Ordering.MarkerClearCannotSkipSetup

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

namespace ck_test_ordering_marker_clear
{
    const auto SlotName = FName{TEXT("CkSnapshot_Ordering_MarkerClear_GateSlot")};

    auto ResolveProbe(UWorld* InWorld) -> FCk_Handle
    {
        if (InWorld == nullptr)
        { return {}; }
        return ck::auto_test::snapshot::ResolveEntityBySpawnRecipe(
            InWorld, UCk_AutoTest_Snapshot_OrderingClearProbe_EntityScript_UE::StaticClass());
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Ordering_MarkerClearCannotSkipSetup_Gate,
    "Ck.Snapshot.Ordering.MarkerClearCannotSkipSetup",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_Ordering_MarkerClearCannotSkipSetup_Gate::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_ordering_marker_clear;
    using namespace ck_autotest_snapshot_ordering;

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = SlotName;

    // ONE cycle: the drained-request count is recorded process-wide (the fragment carrying it is the one being
    // wiped), so it is only unambiguous for a single load.
    Spec.NumCycles = 1;

    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    {
        if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
        { CVar->Set(1, ECVF_SetByCode); }

        auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
        UCk_Utils_EntityScript_UE::Request_SpawnEntity(
            Transient, UCk_AutoTest_Snapshot_OrderingClearProbe_EntityScript_UE::StaticClass(),
            FInstancedStruct{}, {});
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

        Probe.Get<ck::FFragment_AutoTest_Ordering_State>()._ValueA = SavedValueClearProbe;

        Reset_Observations();
    });

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
            TEXT("Setup still ran, despite a registry-wide wipe of its marker running every tick"),
            Log._RunCount, 1);

        AllGood &= TestEqual(
            TEXT("and it read the RESTORED value"), Log._ObservedA, SavedValueClearProbe);

        // The harder half: a request enqueued during Construct survived a registry-wide wipe of the request
        // fragment itself, and was drained rather than destroyed.
        AllGood &= TestEqual(
            FString::Printf(TEXT("the Construct-time request survived the wipe and drained (drained=%d)"),
                Get_Observations().ClearProbe_RequestsDrained),
            Get_Observations().ClearProbe_RequestsDrained, 1);

        return AllGood;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
