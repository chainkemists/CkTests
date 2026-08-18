// Velocity had no round-trip test, and that is exactly why its Setup could re-derive _CurrentVelocity from
// the params forever without anyone noticing: before the ordering contract, Setup ran BEFORE hydration, so
// the restored value landed last and won. Under the contract Setup runs AFTER hydration, and a Setup that
// re-derives a Durable fragment silently overwrites what the load just restored — the value comes back as
// the starting one, with no error anywhere. This pins the value, not the mechanism.
// Surface in Session Frontend: Ck.Snapshot.Parity.Velocity_RoundTrip

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel

#include "CkEcs/EntityScript/CkEntityScript_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkPhysics/Velocity/CkVelocity_Utils.h"

#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkTests/Snapshot/CkAutoTest_Snapshot_Ordering.h"
#include "CkTests/Snapshot/CkSnapshot_TestHarness_Common.h"

namespace ck_test_velocity_roundtrip
{
    const auto SlotName = FName{TEXT("CkSnapshot_VelocityRoundTrip_GateSlot")};

    auto ResolveProbe(UWorld* InWorld) -> FCk_Handle
    {
        if (InWorld == nullptr)
        { return {}; }
        return ck::auto_test::snapshot::ResolveEntityBySpawnRecipe(
            InWorld, UCk_AutoTest_Snapshot_PhysicsFogProbe_EntityScript_UE::StaticClass());
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_VelocityParity_RoundTrip_Gate,
    "Ck.Snapshot.Parity.Velocity_RoundTrip",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_VelocityParity_RoundTrip_Gate::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_velocity_roundtrip;
    using namespace ck_autotest_snapshot_ordering;

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = SlotName;

    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    {
        if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
        { CVar->Set(1, ECVF_SetByCode); }

        auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
        UCk_Utils_EntityScript_UE::Request_SpawnEntity(
            Transient, UCk_AutoTest_Snapshot_PhysicsFogProbe_EntityScript_UE::StaticClass(),
            FInstancedStruct{}, {});
    });

    Spec.SubjectReady = FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
    {
        const auto Probe = ResolveProbe(ck::auto_test::snapshot::Get_PostTravelServerWorld());
        return ck::IsValid(Probe) && UCk_Utils_Velocity_UE::Has(Probe);
    });

    Spec.Mutate = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    {
        auto Probe = ResolveProbe(InServer);
        if (ck::Is_NOT_Valid(Probe))
        { return; }

        auto Velocity = UCk_Utils_Velocity_UE::Cast(Probe);
        UCk_Utils_Velocity_UE::Request_OverrideVelocity(Velocity, SavedVelocity, {});
    });

    Spec.Assert = FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
    {
        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
        auto AllGood = TestTrue(TEXT("post-load server world resolves"), Server != nullptr);
        if (Server == nullptr)
        { return false; }

        auto Probe = ResolveProbe(Server);
        if (NOT TestTrue(TEXT("the probe was restored (the load ran)"), ck::IsValid(Probe)))
        { return false; }

        if (NOT TestTrue(TEXT("the restored probe still carries the Velocity feature"),
            UCk_Utils_Velocity_UE::Has(Probe)))
        { return false; }

        auto Velocity = UCk_Utils_Velocity_UE::Cast(Probe);
        const auto Restored = UCk_Utils_Velocity_UE::Get_CurrentVelocity(Velocity);

        AllGood &= TestTrue(
            FString::Printf(TEXT("the overridden velocity survived the round-trip (got %s, saved %s)"),
                *Restored.ToString(), *SavedVelocity.ToString()),
            Restored.Equals(SavedVelocity));

        // The failure this exists to catch is specific: Setup re-seeding from the params. Naming it makes a
        // regression self-diagnosing instead of "the number is wrong".
        AllGood &= TestFalse(
            FString::Printf(TEXT("and it is NOT the params' starting velocity %s — a Setup that re-derives ")
                            TEXT("a Durable fragment overwrites what hydration restored"),
                *StartingVelocity.ToString()),
            Restored.Equals(StartingVelocity));

        return AllGood;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
