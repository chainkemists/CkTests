// The teardown tripwire. Holding a restored entity out of every non-kernel processor's view means holding it out
// of the destruction pipeline too — and that pipeline is 143 processors across 60+ features, so exempting them
// one by one is not a list anyone could keep honest. Instead, entering destruction LEAVES the hold: the tag is
// dropped where destruction is initiated. Two things then follow, and this test pins both — an entity destroyed
// mid-load still runs its EndPlay bodies, and it cannot end up holding the tag forever with nothing left to
// release it.
//
// The probe destroys itself from inside its own hydration, which is precisely the window in question.
// Surface in Session Frontend: Ck.Snapshot.Ordering.DestroyWhileQuarantinedRunsEndPlay

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel

#include "CkEcs/EntityScript/CkEntityScript_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"
#include "CkEcs/Tag/CkTag_HydrationQuarantine.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkTests/Snapshot/CkAutoTest_Snapshot_Ordering.h"
#include "CkTests/Snapshot/CkSnapshot_TestHarness_Common.h"

namespace ck_test_ordering_destroy_while_held
{
    const auto SlotName = FName{TEXT("CkSnapshot_Ordering_DestroyWhileHeld_GateSlot")};

    auto ResolveProbe(UWorld* InWorld) -> FCk_Handle
    {
        if (InWorld == nullptr)
        { return {}; }
        return ck::auto_test::snapshot::ResolveEntityBySpawnRecipe(
            InWorld, UCk_AutoTest_Snapshot_OrderingDestroyProbe_EntityScript_UE::StaticClass());
    }

    auto AnyEntityStillHeld(UWorld* InWorld) -> bool
    {
        if (InWorld == nullptr)
        { return false; }

        auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InWorld);
        if (ck::Is_NOT_Valid(Transient))
        { return false; }

        return Transient.Get_RegistryView().Has_AnyLiveEntityWith<ck::FTag_Hydration_Quarantine>();
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Ordering_DestroyWhileQuarantinedRunsEndPlay_Gate,
    "Ck.Snapshot.Ordering.DestroyWhileQuarantinedRunsEndPlay",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_Ordering_DestroyWhileQuarantinedRunsEndPlay_Gate::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_ordering_destroy_while_held;
    using namespace ck_autotest_snapshot_ordering;

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = SlotName;

    // ONE cycle: the probe deletes itself on the first load, so a second cycle would have nothing to save.
    Spec.NumCycles = 1;

    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    {
        if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
        { CVar->Set(1, ECVF_SetByCode); }

        auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
        UCk_Utils_EntityScript_UE::Request_SpawnEntity(
            Transient, UCk_AutoTest_Snapshot_OrderingDestroyProbe_EntityScript_UE::StaticClass(),
            FInstancedStruct{}, {});
    });

    Spec.SubjectReady = FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
    {
        return ck::IsValid(ResolveProbe(ck::auto_test::snapshot::Get_PostTravelServerWorld()));
    });

    Spec.Mutate = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld*) -> void
    {
        // The EndPlay witness is measured across the LOAD only — the save's own session must not colour it.
        Reset_Observations();
    });

    Spec.Assert = FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
    {
        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
        auto AllGood = TestTrue(TEXT("post-load server world resolves"), Server != nullptr);
        if (Server == nullptr)
        { return false; }

        auto* Subsystem = ck::auto_test::snapshot::Get_SnapshotSubsystem(Server);
        if (NOT TestTrue(TEXT("snapshot subsystem present post-reload"), Subsystem != nullptr))
        { return false; }

        // Positive control: the probe really was restored and really was handed a payload, so the destruction
        // below happened inside the load rather than instead of it.
        const auto& Report = Subsystem->Get_LastLoadReport();
        AllGood &= TestTrue(
            FString::Printf(TEXT("the load enqueued payloads (enqueued=%d)"), Report.Get_PayloadsEnqueued()),
            Report.Get_PayloadsEnqueued() >= 1);

        // The invariant: destruction that begins while the load is holding the entity still runs the feature's
        // EndPlay bodies. A destruction pipeline that could not see held entities would silently skip them.
        AllGood &= TestTrue(
            TEXT("the destroyed-mid-load entity still ran its EndPlay body"),
            Get_Observations().DestroyProbe_EndPlayRan);

        AllGood &= TestFalse(
            TEXT("and the entity is actually gone afterwards"),
            ck::IsValid(ResolveProbe(Server)));

        // The second half of B6: nothing is left holding a tag with no one to release it.
        AllGood &= TestFalse(
            TEXT("no live entity still carries the hydration quarantine once the load has finished"),
            AnyEntityStillHeld(Server));

        return AllGood;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
