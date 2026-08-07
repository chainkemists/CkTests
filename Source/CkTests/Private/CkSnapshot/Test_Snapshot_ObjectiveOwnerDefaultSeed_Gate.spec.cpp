// CkSnapshot GATE — an ObjectiveOwner's _DefaultObjectives must not be re-seeded by a v3 rebuild+hydrate load.
// Surface in Session Frontend: Ck.Snapshot.ObjectiveOwner.DefaultSeed_NoDuplicateOnReload
//
// The defect: FProcessor_ObjectiveOwner_Setup materializes _DefaultObjectives from a NeedsSetup marker, and a
// load replays the owner's construction by design — which re-stamps that marker. The processor is
// GatedDuringLoad, so it fired the moment the gate lifted and created a second copy of every default child
// beside the ones the loader had already respawned from their own recipes. Found in BusterBlock, where the
// objective feed rendered every card twice after a load (it keys cards on FCk_Handle_Objective).
//
// What this measures, and why each assertion is not redundant:
//   1. COUNT PER NAME — exactly one objective per _ObjectiveName under the owner. Two same-named siblings is
//      the defect in its most direct form, and the name is what TryGet_Objective and any consumer dedup key on.
//   2. IDENTITY — the owner is resolved by retained spawn recipe post-travel, so the counts are read off the
//      rebuilt owner rather than whatever happens to carry an ObjectiveOwner.
//   3. TWO CYCLES — EnqueueRoundTrip re-runs Assert after every cycle (NumCycles = 2). Deliberate: a one-cycle
//      gate cannot distinguish "restored correctly" from "re-seeded, and the second seed has not landed yet".
//
// Deliberately NOT asserted: the load report's entity total. Measured on a knowingly broken build, the
// duplication is bounded at 2x rather than compounding and the save does not inflate — total read identically
// on both cycles while the world held double the objectives. An entity-count check passes red here; only the
// per-name counts catch it.
//
// Fixture: CkTests/Snapshot/CkAutoTest_Snapshot_ObjectiveOwnerProbe_EntityScript.h — its Construct is
// deliberately ungated on the load, because that replay IS the input under test.

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"

#include "GameplayTagContainer.h"

#include <InstancedStruct.h>

#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/EntityScript/CkEntityScript_Utils.h"

#include "CkObjective/Objective/CkObjective_Utils.h"
#include "CkObjective/ObjectiveOwner/CkObjectiveOwner_Utils.h"

#include "CkSnapshot/CkSnapshot_Utils.h"

#include "CkTests/Snapshot/CkAutoTest_Snapshot_ObjectiveOwnerProbe_EntityScript.h"
#include "CkTests/Snapshot/CkSnapshot_TestHarness_Common.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_snapshot_objectiveowner_defaultseed_gate
{
    // Natively registered by the fixture TU (UE_DEFINE_GAMEPLAY_TAG_STATIC is file-local, so they are
    // re-resolved by name here rather than shared through a header).
    const auto LeafAName = TEXT("Test.Objective.ProbeLeafA");
    const auto LeafBName = TEXT("Test.Objective.ProbeLeafB");

    constexpr auto ExpectedPerName = 1;
    constexpr auto ExpectedTotal   = 2;

    struct FReadout
    {
        bool  OwnerFound = false;
        bool  OwnerIsOwner = false;
        int32 NumObjectives = 0;
        int32 NumA = 0;
        int32 NumB = 0;
    };

    auto Read_Owner(UWorld* InWorld, FReadout& OutReadout) -> void
    {
        OutReadout = FReadout{};

        auto Owner = ck::auto_test::snapshot::ResolveEntityBySpawnRecipe(
            InWorld, UCk_AutoTest_Snapshot_ObjectiveOwnerProbe_EntityScript_UE::StaticClass());

        if (ck::Is_NOT_Valid(Owner))
        { return; }

        OutReadout.OwnerFound = true;
        OutReadout.OwnerIsOwner = UCk_Utils_ObjectiveOwner_UE::Has(Owner);
        if (NOT OutReadout.OwnerIsOwner)
        { return; }

        const auto TagA = FGameplayTag::RequestGameplayTag(FName{LeafAName}, false);
        const auto TagB = FGameplayTag::RequestGameplayTag(FName{LeafBName}, false);

        const auto OwnerTyped = UCk_Utils_ObjectiveOwner_UE::CastChecked(Owner);
        for (const auto& Objective : UCk_Utils_ObjectiveOwner_UE::ForEach_Objective(OwnerTyped))
        {
            if (ck::Is_NOT_Valid(Objective))
            { continue; }

            ++OutReadout.NumObjectives;

            const auto Name = UCk_Utils_Objective_UE::Get_Name(Objective);
            if (Name == TagA) { ++OutReadout.NumA; }
            else if (Name == TagB) { ++OutReadout.NumB; }
        }
    }

    auto Diagnose(FAutomationTestBase& InTest, const TCHAR* InStage, const FReadout& InReadout) -> void
    {
        const auto Message = FString::Printf(
            TEXT("[CkObjectiveOwnerSeedGate] %s: found=%d composed=%d objectives=%d A=%d B=%d"),
            InStage, InReadout.OwnerFound, InReadout.OwnerIsOwner,
            InReadout.NumObjectives, InReadout.NumA, InReadout.NumB);

        InTest.AddInfo(Message);
        UE_LOG(LogTemp, Display, TEXT("%s"), *Message);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_ObjectiveOwner_DefaultSeed_NoDuplicateOnReload,
    "Ck.Snapshot.ObjectiveOwner.DefaultSeed_NoDuplicateOnReload",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_ObjectiveOwner_DefaultSeed_NoDuplicateOnReload::RunTest(const FString& Parameters)
{
    using namespace ck_snapshot_objectiveowner_defaultseed_gate;

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = FName{TEXT("CkSnapshot_ObjectiveOwnerDefaultSeed_Slot")};

    // Listen server only. Objective composition hardcodes Replicates on its status ByteAttribute and the owner's
    // EntityCollection (CkObjective_Utils.cpp), so a transient-owned probe with a client world present drives
    // replication through an entity that has no owning actor and floods ck::IsValid(EntityOwningActorComp).
    // Seeding is authority-side, so a client adds no coverage here.
    Spec.NumPIEClients = 1;

    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
    {
        auto Anchor = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InServer);
        if (ck::Is_NOT_Valid(Anchor))
        { AddError(TEXT("spawn: could not create a transient-owned anchor for the objective owner probe")); return; }

        const auto Pending = UCk_Utils_EntityScript_UE::Request_SpawnEntity(
            Anchor, UCk_AutoTest_Snapshot_ObjectiveOwnerProbe_EntityScript_UE::StaticClass(), FInstancedStruct{}, {});

        TestTrue(TEXT("spawn: objective owner probe returned a valid pending handle"), ck::IsValid(Pending));
    });

    // The defaults are materialized a tick or more after construction closes, so the pre-save baseline has to be
    // waited for rather than assumed — otherwise the save could capture a half-seeded owner and every post-load
    // count below would be comparing against a fixture that never worked.
    Spec.SubjectReady = FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
    {
        auto Readout = FReadout{};
        Read_Owner(ck::auto_test::snapshot::Get_PostTravelServerWorld(), Readout);
        return Readout.NumObjectives == ExpectedTotal;
    });

    Spec.Mutate = FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
    {
        auto Readout = FReadout{};
        Read_Owner(InServer, Readout);
        Diagnose(*this, TEXT("pre-save"), Readout);

        TestTrue(TEXT("pre-save: the probe composed its ObjectiveOwner"), Readout.OwnerIsOwner);
        TestEqual(TEXT("pre-save: exactly one objective named A"), Readout.NumA, ExpectedPerName);
        TestEqual(TEXT("pre-save: exactly one objective named B"), Readout.NumB, ExpectedPerName);
    });

    Spec.Assert = FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
    {
        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();

        auto Readout = FReadout{};
        Read_Owner(Server, Readout);
        Diagnose(*this, TEXT("post-load"), Readout);

        if (NOT Readout.OwnerFound)
        {
            AddError(TEXT("post-load: the objective owner did not survive the load at all"));
            return true;
        }

        TestTrue(TEXT("post-load: the restored owner still carries its ObjectiveOwner"), Readout.OwnerIsOwner);

        // The defect, stated as an assertion: the replayed construction must not have re-seeded the defaults on
        // top of the children the loader respawned.
        TestEqual(TEXT("post-load: exactly one objective named A (no re-seeded duplicate)"),
            Readout.NumA, ExpectedPerName);
        TestEqual(TEXT("post-load: exactly one objective named B (no re-seeded duplicate)"),
            Readout.NumB, ExpectedPerName);
        TestEqual(TEXT("post-load: the owner still holds exactly its two defaults"),
            Readout.NumObjectives, ExpectedTotal);

        return true;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
