// CkSnapshot Staged-Construction Adoption GATE — the gondola-shape fence, framework-pure. A parent script
// defer-spawns THREE children whose construction is completed by a GAME (GatedDuringLoad) processor, and stamps
// each child's slot GameplayLabel — the loader's (owner, label) adopt key — only in the OnConstructed promise
// callback. Each child composes a FloatAttribute (a labeled ConstructSpawned GRANDCHILD carrying the payload).
// The test overrides each attribute to a distinct per-slot value, then runs two full save->load cycles asserting:
//   - all three children ADOPT (labels resolve; zero StagedConstruction orphans) — impossible at kernel scope,
//     because their constructions can only finish under the ESCALATED full-scope rebuild,
//   - the per-slot attribute values hydrate back exactly (payload delivery through a three-deep adopted chain),
//   - the load report says so honestly: UsedEscalatedRebuild, zero UnresolvedAfterEscalation, Result == Success.
// Before the escalated rebuild existed, this exact shape orphaned 12 rows + 48 descendants on a real map load
// (the RetailGondola incident, 2026-07-29) while the whole suite stayed green — this is the missing fence.
// Surface in Session Frontend: Ck.Snapshot.StagedConstructionAdoption

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel

#include "CkAttribute/FloatAttribute/CkFloatAttribute_Utils.h"
#include "CkAttribute/IntegerAttribute/CkIntegerAttribute_Utils.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Fragment.h"
#include "CkEcs/EntityScript/CkEntityScript_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkLabel/CkLabel_Utils.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkTests/Snapshot/CkAutoTest_Snapshot_StagedConstruction.h"
#include "CkTests/Snapshot/CkSnapshot_TestHarness_Common.h"

namespace ck_test_staged_adoption
{
    const auto StagedAdoption_SlotName = FName{TEXT("CkSnapshot_StagedAdoption_GateSlot")};

    auto StagedAdoption_ExpectedValue(int32 InSlotIndex) -> float
    {
        return 10.0f * (InSlotIndex + 1) + 0.5f;
    }

    auto StagedAdoption_ExpectedRate(int32 InSlotIndex) -> float
    {
        return -1.0f * (InSlotIndex + 1) - 0.25f;
    }

    auto StagedAdoption_ResolveParent(UWorld* InWorld) -> FCk_Handle
    {
        if (InWorld == nullptr)
        { return {}; }
        return ck::auto_test::snapshot::ResolveEntityBySpawnRecipe(
            InWorld, UCk_AutoTest_Snapshot_StagedParent_EntityScript_UE::StaticClass());
    }

    auto StagedAdoption_FindChildBySlot(const FCk_Handle& InParent, int32 InSlotIndex) -> FCk_Handle
    {
        if (ck::Is_NOT_Valid(InParent) || NOT InParent.Has<ck::FFragment_LifetimeDependents>())
        { return {}; }

        const auto SlotLabel = ck_autotest_staged_construction::Get_SlotLabel(InSlotIndex);
        for (auto Child : InParent.Get<ck::FFragment_LifetimeDependents>().Get_Entities())
        {
            if (ck::Is_NOT_Valid(Child) || NOT UCk_Utils_GameplayLabel_UE::Has(Child))
            { continue; }
            if (UCk_Utils_GameplayLabel_UE::Get_Label(Child) == SlotLabel)
            { return Child; }
        }
        return {};
    }

    auto StagedAdoption_TryGet_ChildAttribute(const FCk_Handle& InChild) -> FCk_Handle_FloatAttribute
    {
        if (ck::Is_NOT_Valid(InChild))
        { return {}; }
        auto Child = InChild;
        return UCk_Utils_FloatAttribute_UE::TryGet(Child, ck_autotest_staged_construction::Get_ValueAttributeName());
    }

    // The equal-label sibling pair: the meter's refill child shares the meter's label, so these only resolve
    // correctly post-load if the adoption scan binds the pair apart (claimed-child exclusion).
    auto StagedAdoption_TryGet_MeterRefill(const FCk_Handle& InChild) -> FCk_Handle_IntegerAttributeRefill
    {
        if (ck::Is_NOT_Valid(InChild))
        { return {}; }
        auto Child = InChild;
        const auto Meter = UCk_Utils_IntegerAttribute_UE::TryGet(
            Child, ck_autotest_staged_construction::Get_MeterAttributeName());
        if (ck::Is_NOT_Valid(Meter))
        { return {}; }
        return UCk_Utils_IntegerAttribute_UE::TryGet_RefillAttribute(Meter);
    }

    // All three children constructed (their completion-stamped labels exist) and carry their attribute, and
    // the population keeper has topped up to exactly one — so every capture holds a deterministic keeper row.
    auto StagedAdoption_HierarchyReady(UWorld* InWorld) -> bool
    {
        const auto Parent = StagedAdoption_ResolveParent(InWorld);
        if (ck::Is_NOT_Valid(Parent))
        { return false; }

        for (auto SlotIndex = 0; SlotIndex < ck_autotest_staged_construction::NumSlots; ++SlotIndex)
        {
            const auto Child = StagedAdoption_FindChildBySlot(Parent, SlotIndex);
            if (ck::Is_NOT_Valid(Child) || ck::Is_NOT_Valid(StagedAdoption_TryGet_ChildAttribute(Child)))
            { return false; }
        }

        return ck_autotest_staged_construction::Get_KeeperChildCount(Parent) == 1;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_StagedConstructionAdoption_Gate,
    "Ck.Snapshot.StagedConstructionAdoption",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_StagedConstructionAdoption_Gate::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_staged_adoption;

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = StagedAdoption_SlotName;

    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    {
        // Non-seamless PIE ServerTravel destroys the client's PlayerState mid-teardown, and ActorRelay's
        // per-player channel cleanup then walks pending-kill channel actors (ensure storm). Every green
        // 2-window round-trip gate travels seamlessly — same here.
        if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
        { CVar->Set(1, ECVF_SetByCode); }

        auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
        UCk_Utils_EntityScript_UE::Request_SpawnEntity(
            Transient, UCk_AutoTest_Snapshot_StagedParent_EntityScript_UE::StaticClass(), FInstancedStruct{}, {});
    });

    Spec.SubjectReady = FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
    {
        return StagedAdoption_HierarchyReady(ck::auto_test::snapshot::Get_PostTravelServerWorld());
    });

    Spec.Mutate = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    {
        const auto Parent = StagedAdoption_ResolveParent(InServer);
        for (auto SlotIndex = 0; SlotIndex < ck_autotest_staged_construction::NumSlots; ++SlotIndex)
        {
            auto Attribute = StagedAdoption_TryGet_ChildAttribute(StagedAdoption_FindChildBySlot(Parent, SlotIndex));
            if (ck::Is_NOT_Valid(Attribute))
            { continue; } // SubjectReady proved presence; a miss here fails the value assert below loudly

            UCk_Utils_FloatAttribute_UE::Request_Override(
                Attribute, StagedAdoption_ExpectedValue(SlotIndex), ECk_MinMaxCurrent::Current, {});

            // Divergent state on BOTH payload kinds the equal-label refill child carries: run-state
            // (Paused -> Running) and its float VALUE (the fill rate).
            auto Refill = StagedAdoption_TryGet_MeterRefill(StagedAdoption_FindChildBySlot(Parent, SlotIndex));
            if (ck::Is_NOT_Valid(Refill))
            { continue; }
            UCk_Utils_IntegerAttributeRefill_UE::Request_Resume(Refill, {});
            auto RefillValue = UCk_Utils_FloatAttribute_UE::CastChecked(Refill);
            UCk_Utils_FloatAttribute_UE::Request_Override(
                RefillValue, StagedAdoption_ExpectedRate(SlotIndex), ECk_MinMaxCurrent::Current, {});
        }
    });

    // Cross-cycle row-count stability: cycle 2's capture reads the post-load-1 world, so any entity the world
    // spawned ON TOP of the loader's respawns (a policy processor acting on the mid-load census) shows up here
    // as save inflation. -1 == not yet recorded.
    const auto FirstCycleEntitiesTotal = MakeShared<int32>(-1);

    Spec.Assert = FCk_NetAutoTest_Assertion::CreateLambda([this, FirstCycleEntitiesTotal]() -> bool
    {
        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
        const auto Parent = StagedAdoption_ResolveParent(Server);
        if (NOT TestTrue(TEXT("restored parent resolves by spawn recipe"), ck::IsValid(Parent)))
        { return false; }

        auto AllGood = true;
        for (auto SlotIndex = 0; SlotIndex < ck_autotest_staged_construction::NumSlots; ++SlotIndex)
        {
            const auto Child = StagedAdoption_FindChildBySlot(Parent, SlotIndex);
            AllGood &= TestTrue(
                FString::Printf(TEXT("child slot %d ADOPTED (label resolves on the restored parent)"), SlotIndex),
                ck::IsValid(Child));

            const auto Attribute = StagedAdoption_TryGet_ChildAttribute(Child);
            AllGood &= TestTrue(
                FString::Printf(TEXT("child slot %d attribute grandchild adopted"), SlotIndex),
                ck::IsValid(Attribute));
            if (ck::Is_NOT_Valid(Attribute))
            { continue; }

            const auto Expected = StagedAdoption_ExpectedValue(SlotIndex);
            AllGood &= TestEqual(
                FString::Printf(TEXT("child slot %d attribute BASE hydrated"), SlotIndex),
                static_cast<float>(UCk_Utils_FloatAttribute_UE::Get_BaseValue(Attribute)), Expected);
            AllGood &= TestEqual(
                FString::Printf(TEXT("child slot %d attribute FINAL hydrated"), SlotIndex),
                static_cast<float>(UCk_Utils_FloatAttribute_UE::Get_FinalValue(Attribute)), Expected);

            // The equal-label sibling pair: refill run-state and rate can only land here if the loader bound
            // the meter row and the refill row to DIFFERENT children despite the shared (owner, label) key.
            const auto Refill = StagedAdoption_TryGet_MeterRefill(Child);
            AllGood &= TestTrue(
                FString::Printf(TEXT("child slot %d meter refill child adopted (equal-label sibling)"), SlotIndex),
                ck::IsValid(Refill));
            if (ck::Is_NOT_Valid(Refill))
            { continue; }

            AllGood &= TestTrue(
                FString::Printf(TEXT("child slot %d refill RUN-STATE hydrated (Paused -> Running)"), SlotIndex),
                UCk_Utils_IntegerAttributeRefill_UE::Get_RefillState(Refill) == ECk_Attribute_RefillState::Running);

            const auto RefillValue = UCk_Utils_FloatAttribute_UE::CastChecked(Refill);
            AllGood &= TestEqual(
                FString::Printf(TEXT("child slot %d refill RATE hydrated onto the equal-label sibling"), SlotIndex),
                static_cast<float>(UCk_Utils_FloatAttribute_UE::Get_FinalValue(RefillValue)),
                StagedAdoption_ExpectedRate(SlotIndex));
        }

        auto* Subsystem = ck::auto_test::snapshot::Get_SnapshotSubsystem(Server);
        if (NOT TestTrue(TEXT("snapshot subsystem present post-reload"), Subsystem != nullptr))
        { return false; }

        // The population-keeper leg: the every-tick keeper processor ran against the mid-load census (a lie)
        // and its top-up spawn must have been SUPPRESSED by the load gate — exactly one keeper may survive.
        // Two keepers means a policy spawn was admitted during the load; zero means the keeper row failed to
        // respawn (or post-load top-up broke).
        AllGood &= TestEqual(TEXT("exactly ONE population keeper survives the load (policy spawn suppressed, saved row respawned)"),
            ck_autotest_staged_construction::Get_KeeperChildCount(Parent), 1);

        const auto Report = Subsystem->Get_LastLoadReport();
        AllGood &= TestTrue(TEXT("load Result == Success"), Report.Get_Result() == ECk_SnapshotResult::Success);

        if (*FirstCycleEntitiesTotal < 0)
        { *FirstCycleEntitiesTotal = Report.Get_EntitiesTotal(); }
        else
        {
            AllGood &= TestEqual(
                TEXT("save row count is CYCLE-STABLE (a later cycle's capture holds exactly the rows the first did — no world-side inflation)"),
                Report.Get_EntitiesTotal(), *FirstCycleEntitiesTotal);

            // Deterministic probes of the load-gate spawn admission, on the FINAL cycle only (nothing is
            // captured after this, so the admitted probe entity cannot pollute the stability assert above).
            // The construction-window admission needs no probe — the staged children ARE mid-load spawns that
            // only that rule admits, so the whole fence fails if it breaks.
            if (auto* EcsWorld = Server->GetSubsystem<UCk_EcsWorld_Subsystem_UE>();
                TestTrue(TEXT("EcsWorld subsystem present for admission probes"), ck::IsValid(EcsWorld)))
            {
                EcsWorld->Set_IsLoadGateActive(true);

                auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(Server);
                const auto Suppressed = UCk_Utils_EntityScript_UE::Request_SpawnEntity(
                    Transient, UCk_AutoTest_Snapshot_PopulationKeeper_EntityScript_UE::StaticClass(), FInstancedStruct{}, {});
                AllGood &= TestTrue(
                    TEXT("a plain spawn under an ACTIVE load gate is suppressed (invalid pending)"),
                    ck::Is_NOT_Valid(Suppressed));

                {
                    const auto LoaderWindow = FCk_ScopedLoaderSpawnWindow{EcsWorld};
                    const auto Admitted = UCk_Utils_EntityScript_UE::Request_SpawnEntity(
                        Transient, UCk_AutoTest_Snapshot_PopulationKeeper_EntityScript_UE::StaticClass(), FInstancedStruct{}, {});
                    AllGood &= TestTrue(
                        TEXT("the same spawn inside the LOADER window is admitted"),
                        ck::IsValid(Admitted));
                }

                {
                    const auto RendezvousWindow = FCk_ScopedRendezvousSpawnWindow{EcsWorld};
                    const auto Admitted = UCk_Utils_EntityScript_UE::Request_SpawnEntity(
                        Transient, UCk_AutoTest_Snapshot_PopulationKeeper_EntityScript_UE::StaticClass(), FInstancedStruct{}, {});
                    AllGood &= TestTrue(
                        TEXT("a spawn inside a DECLARED rendezvous window is admitted (the world-bootstrap adopt-target class)"),
                        ck::IsValid(Admitted));
                }

                {
                    const auto ViaUFunction = UCk_Utils_EntityScript_UE::Request_SpawnEntity_LoadRendezvous(
                        Transient, UCk_AutoTest_Snapshot_PopulationKeeper_EntityScript_UE::StaticClass(), FInstancedStruct{}, {});
                    AllGood &= TestTrue(
                        TEXT("Request_SpawnEntity_LoadRendezvous is admitted under an active gate (the AS/BP-facing declared admission)"),
                        ck::IsValid(ViaUFunction));
                }

                EcsWorld->Set_IsLoadGateActive(false);
            }
        }
        AllGood &= TestTrue(
            TEXT("the load ESCALATED (kernel alone cannot finish staged constructions — a pass here without "
                 "escalation means the fixture went vacuous, e.g. its setup processor became RunsDuringLoad)"),
            Report.Get_UsedEscalatedRebuild());
        AllGood &= TestEqual(TEXT("zero rows unresolved after escalation"),
            Report.Get_UnresolvedAfterEscalation(), 0);

        for (const auto& Orphan : Report.Get_Orphans())
        {
            AllGood &= TestTrue(
                FString::Printf(TEXT("no StagedConstruction orphan (found: saved-id %u identity [%s])"),
                    Orphan.Get_SavedId(), *Orphan.Get_Identity()),
                NOT Orphan.Get_Identity().Contains(TEXT("StagedConstruction")));
        }

        return AllGood;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
