// Promise_OnHydrated is the per-entity readiness edge a load produces — the load-path twin of
// Promise_OnReplicationComplete. Three things have to hold for it to be usable, and each is a distinct way the
// same API fails:
//
//   1. It fires ONCE. It is broadcast from the quarantine lift, and a load can lift through three different
//      sites (the settle, the frame cap, the load-finish sweep). Without the once-guard — broadcast only for
//      entities whose quarantine tag THIS pass actually removed — a load that escapes through the cap and then
//      finishes delivers the same entity two edges, and a subscriber that is not itself idempotent acts twice.
//   2. It fires AFTER EVERY MAPPED ENTITY'S payloads, not just this entity's. The lift is global for exactly
//      this reason: a driver reading a subordinate, which is the shape most consumers have, must not be handed
//      a sibling that is still mid-hydration. Probe B stalls its payload for several passes after A's has
//      applied, so a per-entity edge would fire for A while B still held the construct default.
//   3. It fires even when nothing is pending — a bind made after the lift, and a bind on an entity no load ever
//      mapped. This is the half that is easy to get wrong in the safe-looking direction: a promise that stays
//      silent unless a load happens to be in flight strands every consumer on a fresh spawn, on a client, and
//      in any world with no save. That is the dead-HUD failure the whole contract exists to remove, reproduced
//      by the mechanism meant to fix it.
//
// Surface in Session Frontend: Ck.Snapshot.Ordering.OnHydratedFiresAfterAllPayloads

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/EntityScript/CkEntityScript_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkSnapshot/CkSnapshot_Utils.h"

#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkTests/Snapshot/CkAutoTest_Snapshot_Ordering.h"
#include "CkTests/Snapshot/CkSnapshot_TestHarness_Common.h"

namespace ck_test_ordering_onhydrated
{
    const auto SlotName = FName{TEXT("CkSnapshot_Ordering_OnHydrated_GateSlot")};

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
    FCk_Snapshot_Ordering_OnHydratedFiresAfterAllPayloads,
    "Ck.Snapshot.Ordering.OnHydratedFiresAfterAllPayloads",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_Ordering_OnHydratedFiresAfterAllPayloads::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_ordering_onhydrated;
    using namespace ck_autotest_snapshot_ordering;

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = SlotName;

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
        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
        const auto ProbeA = ResolveProbeA(Server);
        const auto ProbeB = ResolveProbeB(Server);
        return ck::IsValid(ProbeA) && ck::IsValid(ProbeB)
            && ProbeA.Has<ck::FFragment_AutoTest_Ordering_State>()
            && ProbeB.Has<ck::FFragment_AutoTest_Ordering_State>();
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

        auto ProbeA = ResolveProbeA(Server);
        if (NOT TestTrue(TEXT("probe A was restored (the load ran)"), ck::IsValid(ProbeA)))
        { return false; }

        auto& Obs = Get_Observations();

        AllGood &= TestTrue(
            TEXT("probe B's payload actually stalled — without a real half-hydrated window the ordering "
                 "assertions below are vacuous"),
            Obs.StallReturns > 0);

        AllGood &= TestEqual(
            TEXT("Promise_OnHydrated fired exactly ONCE for the entity — a second edge means the once-guard "
                 "(broadcast only what this pass released) is gone and an escape lift is double-firing"),
            Obs.OnHydratedFireCount, 1);

        AllGood &= TestEqual(
            TEXT("inside the callback, this entity's own Durable value was the restored one"),
            Obs.OnHydratedObservedA, SavedValueA);

        AllGood &= TestTrue(
            TEXT("and the stalling SIBLING was resolvable from inside the same callback"),
            Obs.OnHydratedSiblingResolved);

        AllGood &= TestEqual(
            TEXT("and the sibling's value was ALSO restored by then — the lift is global, so a driver reading "
                 "a subordinate from this callback cannot catch it mid-hydration"),
            Obs.OnHydratedObservedSiblingB, SavedValueB);

        // ---- Nothing pending: both binds must fire immediately, on this stack ------------------------------
        auto* Witness = NewObject<UCk_AutoTest_Snapshot_OnHydratedWitness_UE>(Server);
        Witness->AddToRoot();

        const auto LateBindsBefore = Obs.LateBindFireCount;
        UCk_Utils_Snapshot_UE::Promise_OnHydrated(ProbeA,
            FCk_Delegate_Hydration_OnHydrated::CreateUFunction(Witness, TEXT("OnLateBind")));

        AllGood &= TestEqual(
            TEXT("a bind made AFTER the lift fired immediately — the entity is hydrated, so there is nothing "
                 "left to wait for and silence would strand the consumer forever"),
            Obs.LateBindFireCount, LateBindsBefore + 1);

        AllGood &= TestEqual(
            TEXT("and it was handed the restored value, not a stale or default one"),
            Obs.LateBindObservedA, SavedValueA);

        auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(Server);
        auto FreshEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Transient);

        const auto FreshBindsBefore = Obs.FreshBindFireCount;
        UCk_Utils_Snapshot_UE::Promise_OnHydrated(FreshEntity,
            FCk_Delegate_Hydration_OnHydrated::CreateUFunction(Witness, TEXT("OnFreshBind")));

        AllGood &= TestEqual(
            TEXT("a bind on an entity no load ever mapped fired immediately too — 'nothing was restored' and "
                 "'restoration finished' are the same answer to a consumer asking whether it may read"),
            Obs.FreshBindFireCount, FreshBindsBefore + 1);

        UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(FreshEntity);
        Witness->RemoveFromRoot();

        return AllGood;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
