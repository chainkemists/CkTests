// Verify_AllStoredHandlesResolve is the only structural handle-integrity oracle the suite has: it reports every
// dangling HARD ref (LifetimeOwner / ContextOwner) and every live LifetimeDependent whose own owner names someone
// else. Until now it was called inline by two attribute parity specs, neither of which builds a subtree with
// labeled AND unlabeled children — so the registry-rehome / aliasing class it exists to catch had no gate of its
// own, only a side-effect of two tests about attribute values.
//
// This promotes it. The probe is a handle-rich subtree on purpose: a persisted owner, a LABELED child the load
// re-identifies, and an UNLABELED ConstructSpawned child it cannot. The unlabeled one is what makes the test
// non-trivial — the load must rebuild it fresh and leave nothing pointing at the entity it replaced.
//
// The second assertion is why an emptiness check alone is not enough. A stored handle can be VALID and WRONG:
// remapped to a live entity that is not the one it named. Comparing the Session-held child id across the load
// separates "the rebuild made a new child and the handle names it" from "the saved id was remapped onto
// something that happens to exist".
// Surface in Session Frontend: Ck.Snapshot.Restore.NoDanglingStoredHandles

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel

#include "CkDynamic/CkDynamic_Utils.h"

#include "CkEcs/EntityScript/CkEntityScript_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkSnapshot/Snapshot/CkSnapshot_RestoreInvariants.h"

#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkTests/Snapshot/CkAutoTest_Snapshot_Ordering.h"
#include "CkTests/Snapshot/CkSnapshot_TestHarness_Common.h"

namespace ck_test_no_dangling_handles
{
    const auto SlotName = FName{TEXT("CkSnapshot_NoDanglingStoredHandles_GateSlot")};

    auto ResolveProbe(UWorld* InWorld) -> FCk_Handle
    {
        if (InWorld == nullptr)
        { return {}; }
        return ck::auto_test::snapshot::ResolveEntityBySpawnRecipe(
            InWorld, UCk_AutoTest_Snapshot_HandleGraphProbe_EntityScript_UE::StaticClass());
    }

    auto Get_SessionChildId(const FCk_Handle& InProbe) -> int32
    {
        if (ck::Is_NOT_Valid(InProbe))
        { return 0; }

        if (NOT UCk_Utils_DynamicFragment_UE::Has_Fragment(
            InProbe, FCk_Test_Session_ChildRef::StaticStruct()))
        { return 0; }

        const auto& Ref = UCk_Utils_DynamicFragment_UE::Get_Fragment_TypeUnsafe(
            InProbe, FCk_Test_Session_ChildRef::StaticStruct()).Get<FCk_Test_Session_ChildRef>();

        return ck::IsValid(Ref.Child) ? static_cast<int32>(Ref.Child.Get_Entity().Get_ID()) : 0;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Restore_NoDanglingStoredHandles,
    "Ck.Snapshot.Restore.NoDanglingStoredHandles",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_Restore_NoDanglingStoredHandles::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_no_dangling_handles;
    using namespace ck_autotest_snapshot_ordering;

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = SlotName;

    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    {
        if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
        { CVar->Set(1, ECVF_SetByCode); }

        auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
        UCk_Utils_EntityScript_UE::Request_SpawnEntity(
            Transient, UCk_AutoTest_Snapshot_HandleGraphProbe_EntityScript_UE::StaticClass(),
            FInstancedStruct{}, {});
    });

    Spec.SubjectReady = FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
    {
        const auto Probe = ResolveProbe(ck::auto_test::snapshot::Get_PostTravelServerWorld());
        return ck::IsValid(Probe) && Get_SessionChildId(Probe) != 0;
    });

    Spec.Mutate = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    {
        Reset_Observations();
        Get_Observations().HandleGraph_PreSaveChildId = Get_SessionChildId(ResolveProbe(InServer));
    });

    Spec.Assert = FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
    {
        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
        auto AllGood = TestTrue(TEXT("post-load server world resolves"), Server != nullptr);
        if (Server == nullptr)
        { return false; }

        auto Probe = ResolveProbe(Server);
        if (NOT TestTrue(TEXT("the probe subtree was restored (the load ran)"), ck::IsValid(Probe)))
        { return false; }

        auto* Ecs = Server->GetSubsystem<UCk_EcsWorld_Subsystem_UE>();
        if (NOT TestNotNull(TEXT("the post-load ECS world subsystem resolves"), Ecs))
        { return false; }

        auto& Registry = Ecs->Get_Registry();
        auto* Raw = ck::registry_table::TryResolve(Registry.Get_RegistryHandle());
        if (NOT TestNotNull(TEXT("the post-load registry resolves"), Raw))
        { return false; }

        const auto Dangling = ck::snapshot::Verify_AllStoredHandlesResolve(*Raw);
        for (const auto& Entry : Dangling)
        { AddError(FString::Printf(TEXT("post-load dangling stored handle: %s"), *Entry)); }

        AllGood &= TestEqual(
            TEXT("no stored handle in the restored world's structural backbone dangles"),
            Dangling.Num(), 0);

        // ---- Identity, not just validity ------------------------------------------------------------------
        auto& Obs = Get_Observations();
        Obs.HandleGraph_PostLoadChildId = Get_SessionChildId(Probe);

        AllGood &= TestNotEqual(
            TEXT("the Session-held child handle is valid after the load (the rebuild re-created the child)"),
            Obs.HandleGraph_PostLoadChildId, 0);

        AllGood &= TestNotEqual(
            TEXT("and it names a DIFFERENT entity than before the save — an unlabeled ConstructSpawned child "
                 "has no identity the save can express, so a handle that came back with the SAME id was "
                 "restored from the payload and remapped, not rebuilt"),
            Obs.HandleGraph_PostLoadChildId, Obs.HandleGraph_PreSaveChildId);

        return AllGood;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
