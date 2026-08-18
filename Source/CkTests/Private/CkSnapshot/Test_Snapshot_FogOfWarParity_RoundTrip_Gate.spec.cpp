// FogOfWar persists explored ground — the one thing a player would notice losing — and had no round-trip
// test at all. It is also the feature whose handler used to wait on its own Setup marker, which under the
// ordering contract is a wait that cannot end: a load holds a restored entity out of every non-kernel
// processor's view until its payloads have applied, so the payload burned the apply timeout and the map came
// back fully fogged. The handler now applies immediately and Setup allocates the grid before the saved cells
// are written into it. This pins the outcome: explored ground stays explored across a save and load.
// Surface in Session Frontend: Ck.Snapshot.Parity.FogOfWar_RoundTrip

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel

#include "CkEcs/EntityScript/CkEntityScript_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkMinimap/CkFogOfWar_Utils.h"

#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkTests/Snapshot/CkAutoTest_Snapshot_Ordering.h"
#include "CkTests/Snapshot/CkSnapshot_TestHarness_Common.h"

namespace ck_test_fogofwar_roundtrip
{
    const auto SlotName = FName{TEXT("CkSnapshot_FogOfWarRoundTrip_GateSlot")};

    auto ResolveProbe(UWorld* InWorld) -> FCk_Handle
    {
        if (InWorld == nullptr)
        { return {}; }
        return ck::auto_test::snapshot::ResolveEntityBySpawnRecipe(
            InWorld, UCk_AutoTest_Snapshot_PhysicsFogProbe_EntityScript_UE::StaticClass());
    }

    // Explored cells are bit-packed, so "how much ground is revealed" is a popcount over the payload bytes.
    auto Count_ExploredCells(const FCk_RepData_FogOfWar& InData) -> int32
    {
        auto Count = int32{0};
        for (const auto Byte : InData.Get_PackedCells())
        { Count += FMath::CountBits(static_cast<uint64>(Byte)); }
        return Count;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_FogOfWarParity_RoundTrip_Gate,
    "Ck.Snapshot.Parity.FogOfWar_RoundTrip",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_FogOfWarParity_RoundTrip_Gate::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_fogofwar_roundtrip;

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

    // The grid is allocated by FogOfWar's own Setup, so the probe is not ready to reveal anything until that
    // has run — waiting on a non-zero cell count is waiting for exactly that.
    Spec.SubjectReady = FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
    {
        auto Probe = ResolveProbe(ck::auto_test::snapshot::Get_PostTravelServerWorld());
        if (ck::Is_NOT_Valid(Probe) || NOT UCk_Utils_FogOfWar_UE::Has(Probe))
        { return false; }

        auto Fog = UCk_Utils_FogOfWar_UE::Cast(Probe);
        return UCk_Utils_FogOfWar_UE::Get_CellCounts(Fog).X > 0;
    });

    Spec.Mutate = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    {
        auto Probe = ResolveProbe(InServer);
        if (ck::Is_NOT_Valid(Probe))
        { return; }

        auto Fog = UCk_Utils_FogOfWar_UE::Cast(Probe);
        UCk_Utils_FogOfWar_UE::Request_RevealAll(Fog, {});
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

        if (NOT TestTrue(TEXT("the restored probe still carries the FogOfWar feature"),
            UCk_Utils_FogOfWar_UE::Has(Probe)))
        { return false; }

        auto Fog = UCk_Utils_FogOfWar_UE::Cast(Probe);
        const auto CellCounts = UCk_Utils_FogOfWar_UE::Get_CellCounts(Fog);

        // Positive control: a grid that never got allocated would report zero explored for the wrong reason.
        AllGood &= TestTrue(
            FString::Printf(TEXT("the restored grid was allocated (%dx%d cells)"), CellCounts.X, CellCounts.Y),
            CellCounts.X > 0 && CellCounts.Y > 0);

        const auto Restored = UCk_Utils_FogOfWar_UE::Get_ExploredData(Fog);
        const auto ExploredCount = Count_ExploredCells(Restored);

        // A fresh Setup zeroes the grid, so any explored cell at all can only have come from the payload —
        // and it can only still be there if Setup did not run after the value was written.
        AllGood &= TestTrue(
            FString::Printf(TEXT("the revealed ground survived the round-trip (explored %d cells of %d)"),
                ExploredCount, CellCounts.X * CellCounts.Y),
            ExploredCount > 0);

        return AllGood;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
