// Velocity and Acceleration both defer their LOCAL->world conversion to Setup, because the Transform to rotate
// against may not exist at Add time. Under the ordering contract Setup runs AFTER hydration, so Setup has to
// tell two situations apart: a freshly-constructed entity that still owes the conversion, and a restored one
// whose value is already world-space. Asking "is the value still equal to the starting param?" answers that
// wrong for the entity whose saved value IS the starting param — Setup converts a second time and the world
// comes back rotated. The debt is therefore tracked with a marker that Add stamps, Setup consumes, and
// hydration clears; this pins that, using the exact value a comparison cannot classify.
//
// Sibling to Ck.Snapshot.Parity.Velocity_RoundTrip rather than a clause inside it: the probe needs LOCAL
// coordinates under a rotated Transform, and Acceleration's own gate (Ck.Snapshot.Parity.Acceleration_MPReload)
// drives a replicated actor-bridged probe whose acceleration is world-coordinate by construction — giving it a
// local arm would mean changing the replicated probe actor and its wire shape for the same discrimination.
// Surface in Session Frontend: Ck.Snapshot.Parity.LocalCoordinateConversion_RoundTrip

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel

#include "CkEcs/EntityScript/CkEntityScript_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkPhysics/Acceleration/CkAcceleration_Utils.h"
#include "CkPhysics/Velocity/CkVelocity_Utils.h"

#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkTests/Snapshot/CkAutoTest_Snapshot_Ordering.h"
#include "CkTests/Snapshot/CkSnapshot_TestHarness_Common.h"

namespace ck_test_local_conversion_roundtrip
{
    const auto SlotName = FName{TEXT("CkSnapshot_LocalCoordinateConversion_GateSlot")};

    auto ResolveProbe(UWorld* InWorld) -> FCk_Handle
    {
        if (InWorld == nullptr)
        { return {}; }
        return ck::auto_test::snapshot::ResolveEntityBySpawnRecipe(
            InWorld, UCk_AutoTest_Snapshot_PhysicsLocalProbe_EntityScript_UE::StaticClass());
    }

    // What a SECOND conversion would produce. The assertion messages name it so a regression reads as "it was
    // rotated again" rather than "the number is wrong".
    auto DoubleConverted(const FVector& InLocalValue) -> FVector
    {
        using namespace ck_autotest_snapshot_ordering;
        return FRotator{0.0, LocalProbeYaw, 0.0}.RotateVector(InLocalValue);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_LocalCoordinateConversion_RoundTrip_Gate,
    "Ck.Snapshot.Parity.LocalCoordinateConversion_RoundTrip",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_LocalCoordinateConversion_RoundTrip_Gate::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_local_conversion_roundtrip;
    using namespace ck_autotest_snapshot_ordering;

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = SlotName;

    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    {
        if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
        { CVar->Set(1, ECVF_SetByCode); }

        auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
        UCk_Utils_EntityScript_UE::Request_SpawnEntity(
            Transient, UCk_AutoTest_Snapshot_PhysicsLocalProbe_EntityScript_UE::StaticClass(),
            FInstancedStruct{}, {});
    });

    Spec.SubjectReady = FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
    {
        const auto Probe = ResolveProbe(ck::auto_test::snapshot::Get_PostTravelServerWorld());
        return ck::IsValid(Probe)
            && UCk_Utils_Velocity_UE::Has(Probe)
            && UCk_Utils_Acceleration_UE::Has(Probe);
    });

    Spec.Mutate = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    {
        auto Probe = ResolveProbe(InServer);
        if (ck::Is_NOT_Valid(Probe))
        { return; }

        // Write back exactly the starting params. Setup has already converted them once by now, so this is a
        // real mutation of live state that happens to land on the seed value — the case the marker exists for.
        auto Velocity = UCk_Utils_Velocity_UE::Cast(Probe);
        UCk_Utils_Velocity_UE::Request_OverrideVelocity(Velocity, LocalProbeStartingVelocity, {});

        auto Acceleration = UCk_Utils_Acceleration_UE::Cast(Probe);
        UCk_Utils_Acceleration_UE::Request_OverrideAcceleration(Acceleration, LocalProbeStartingAcceleration, {});
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

        if (NOT TestTrue(TEXT("the restored probe still carries Velocity and Acceleration"),
            UCk_Utils_Velocity_UE::Has(Probe) && UCk_Utils_Acceleration_UE::Has(Probe)))
        { return false; }

        auto Velocity = UCk_Utils_Velocity_UE::Cast(Probe);
        const auto RestoredVelocity = UCk_Utils_Velocity_UE::Get_CurrentVelocity(Velocity);

        AllGood &= TestTrue(
            FString::Printf(TEXT("the restored velocity is untouched (got %s, saved %s) — it must NOT be ")
                            TEXT("re-converted to %s, which is what a second local->world pass produces"),
                *RestoredVelocity.ToString(), *LocalProbeStartingVelocity.ToString(),
                *DoubleConverted(LocalProbeStartingVelocity).ToString()),
            RestoredVelocity.Equals(LocalProbeStartingVelocity));

        auto Acceleration = UCk_Utils_Acceleration_UE::Cast(Probe);
        const auto RestoredAcceleration = UCk_Utils_Acceleration_UE::Get_CurrentAcceleration(Acceleration);

        AllGood &= TestTrue(
            FString::Printf(TEXT("the restored acceleration is untouched (got %s, saved %s) — it must NOT be ")
                            TEXT("re-converted to %s, which is what a second local->world pass produces"),
                *RestoredAcceleration.ToString(), *LocalProbeStartingAcceleration.ToString(),
                *DoubleConverted(LocalProbeStartingAcceleration).ToString()),
            RestoredAcceleration.Equals(LocalProbeStartingAcceleration));

        return AllGood;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
