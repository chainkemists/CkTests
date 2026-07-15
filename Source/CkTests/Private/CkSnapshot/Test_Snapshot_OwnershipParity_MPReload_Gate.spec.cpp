#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "HAL/IConsoleManager.h"
#include "StructUtils/InstancedStruct.h"

#include "CkEcs/ContextOwner/CkContextOwner_Utils.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/EntityScript/CkEntityScript_Utils.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkTests/Snapshot/CkAutoTest_Snapshot_OwnershipProbe_EntityScript.h"
#include "CkTests/Snapshot/CkSnapshot_TestHarness_Common.h"

namespace
{
    const auto Ownership_SlotName = FName{TEXT("CkSnapshot_OwnershipParity_GateSlot")};

    auto ResolveTarget(UWorld* InWorld) -> FCk_Handle
    {
        return ck::auto_test::snapshot::ResolveEntityBySpawnRecipe(
            InWorld, UCk_AutoTest_Snapshot_OwnershipProbe_Target_EntityScript_UE::StaticClass());
    }

    auto ResolveLifetimeOwner(UWorld* InWorld) -> FCk_Handle
    {
        return ck::auto_test::snapshot::ResolveEntityBySpawnRecipe(
            InWorld, UCk_AutoTest_Snapshot_OwnershipProbe_LifetimeOwner_EntityScript_UE::StaticClass());
    }

    auto ResolveContextOwner(UWorld* InWorld) -> FCk_Handle
    {
        return ck::auto_test::snapshot::ResolveEntityBySpawnRecipe(
            InWorld, UCk_AutoTest_Snapshot_OwnershipProbe_ContextOwner_EntityScript_UE::StaticClass());
    }

    auto AllProbesResolve(UWorld* InWorld) -> bool
    {
        return ck::IsValid(ResolveTarget(InWorld))
            && ck::IsValid(ResolveLifetimeOwner(InWorld))
            && ck::IsValid(ResolveContextOwner(InWorld));
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_OwnershipParity_MPReload_Gate,
    "Ck.Snapshot.Parity.OwnershipAndTransientRoot_MPReload",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_OwnershipParity_MPReload_Gate::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = Ownership_SlotName;

    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
    {
        if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
        { CVar->Set(1, ECVF_SetByCode); }

        auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
        if (ck::Is_NOT_Valid(Transient))
        {
            AddError(TEXT("Ownership parity: transient entity unavailable at spawn"));
            return;
        }

        UCk_Utils_EntityScript_UE::Request_SpawnEntity(
            Transient,
            UCk_AutoTest_Snapshot_OwnershipProbe_Target_EntityScript_UE::StaticClass(),
            FInstancedStruct{});
        UCk_Utils_EntityScript_UE::Request_SpawnEntity(
            Transient,
            UCk_AutoTest_Snapshot_OwnershipProbe_LifetimeOwner_EntityScript_UE::StaticClass(),
            FInstancedStruct{});
        UCk_Utils_EntityScript_UE::Request_SpawnEntity(
            Transient,
            UCk_AutoTest_Snapshot_OwnershipProbe_ContextOwner_EntityScript_UE::StaticClass(),
            FInstancedStruct{});
    });

    Spec.SubjectReady = FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
    {
        return AllProbesResolve(ck::auto_test::snapshot::Get_PostTravelServerWorld());
    });

    Spec.Mutate = FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
    {
        auto Target = ResolveTarget(InServer);
        const auto LifetimeOwner = ResolveLifetimeOwner(InServer);
        const auto ContextOwner = ResolveContextOwner(InServer);
        if (ck::Is_NOT_Valid(Target) || ck::Is_NOT_Valid(LifetimeOwner) || ck::Is_NOT_Valid(ContextOwner))
        {
            AddError(TEXT("Ownership parity: probe unresolved before ownership mutation"));
            return;
        }

        UCk_Utils_EntityLifetime_UE::Request_TransferLifetimeOwner(Target, LifetimeOwner);
        UCk_Utils_ContextOwner_UE::Request_Override(Target, ContextOwner);
    });

    Spec.ReloadSettled = FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
    {
        return AllProbesResolve(ck::auto_test::snapshot::Get_PostTravelServerWorld());
    });

    Spec.Assert = FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
    {
        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
        auto Target = ResolveTarget(Server);
        const auto LifetimeOwner = ResolveLifetimeOwner(Server);
        const auto ContextOwner = ResolveContextOwner(Server);

        const auto bTargetResolved = ck::IsValid(Target);
        const auto bLifetimeOwnerResolved = ck::IsValid(LifetimeOwner);
        const auto bContextOwnerResolved = ck::IsValid(ContextOwner);
        TestTrue(TEXT("transient-root target respawned"), bTargetResolved);
        TestTrue(TEXT("transient-root lifetime-owner probe respawned"), bLifetimeOwnerResolved);
        TestTrue(TEXT("transient-root context-owner probe respawned"), bContextOwnerResolved);
        if (NOT bTargetResolved || NOT bLifetimeOwnerResolved || NOT bContextOwnerResolved)
        { return false; }

        TestTrue(TEXT("saved lifetime owner restored exactly"),
            UCk_Utils_EntityLifetime_UE::Get_LifetimeOwner(Target) == LifetimeOwner);
        TestTrue(TEXT("saved context owner restored exactly"),
            UCk_Utils_ContextOwner_UE::Get_ContextOwner(Target) == ContextOwner);
        return true;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
