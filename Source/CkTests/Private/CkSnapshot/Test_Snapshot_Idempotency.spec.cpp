// Loading is idempotent, and so is the save/load cycle.
//
// Neither question had a single assertion anywhere. Repeated loads of one slot must produce the same world and
// the same report; a save taken AFTER a load must load back to the same numbers as the original. Both are how
// duplication and leak show up first — the 2026-07-29 inflation incident (+77 NPCs and a doubled driver family in
// one save->load->save cycle) is exactly the second question going unasked.
// Surface in Session Frontend: Ck.Snapshot.Idempotency.RepeatedLoadSameSlot
//                              Ck.Snapshot.Idempotency.SaveAfterLoadThenLoad

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel

#include "CkEcs/EntityScript/CkEntityScript_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkTests/Snapshot/CkAutoTest_Snapshot_ApplyClosure.h"
#include "CkTests/Snapshot/CkSnapshot_TestHarness_Common.h"

namespace ck_test_snapshot_idempotency
{
    const auto RepeatedLoad_SlotName = FName{TEXT("CkSnapshot_RepeatedLoadSameSlot_GateSlot")};
    const auto SaveAfterLoad_SlotName = FName{TEXT("CkSnapshot_SaveAfterLoadThenLoad_GateSlot")};

    // The report numbers that must not move between cycles. Deliberately the whole partition rather than a
    // summary: a duplication that inflates one bucket and deflates another would net out in a total.
    struct FCycleFingerprint
    {
        int32 _EntitiesTotal = -1;
        int32 _EntitiesRestored = -1;
        int32 _EntitiesSkipped = -1;
        int32 _EntitiesOrphaned = -1;
        int32 _PayloadsTotal = -1;
        int32 _PayloadsApplied = -1;
        int32 _PayloadsRejected = -1;
        int32 _PayloadsDroppedNoHandler = -1;
        int32 _PayloadsDroppedTimeout = -1;
        int32 _PayloadsDestroyedWithEntries = -1;
        int32 _PayloadsUnappliedAtFinish = -1;
        int32 _PayloadsOnSkippedEntities = -1;
        int32 _PayloadsOnOrphanedEntities = -1;
        int32 _PayloadsOnUnresolvedOwner = -1;
        int32 _PayloadsDropped = -1;

        auto Get_IsRecorded() const -> bool { return _EntitiesTotal >= 0; }

        auto Get_Description() const -> FString
        {
            return FString::Printf(
                TEXT("entities %d/%d/%d/%d payloads %d = %d+%d+%d+%d+%d+%d+%d+%d+%d+%d"),
                _EntitiesTotal, _EntitiesRestored, _EntitiesSkipped, _EntitiesOrphaned,
                _PayloadsTotal, _PayloadsApplied, _PayloadsRejected, _PayloadsDroppedNoHandler,
                _PayloadsDroppedTimeout, _PayloadsDestroyedWithEntries, _PayloadsUnappliedAtFinish,
                _PayloadsOnSkippedEntities, _PayloadsOnOrphanedEntities, _PayloadsOnUnresolvedOwner,
                _PayloadsDropped);
        }

        auto operator==(const FCycleFingerprint& InOther) const -> bool
        {
            return Get_Description() == InOther.Get_Description();
        }
    };

    auto Make_Fingerprint(const FCk_Snapshot_LoadReport& InReport) -> FCycleFingerprint
    {
        auto Out = FCycleFingerprint{};
        Out._EntitiesTotal                = InReport.Get_EntitiesTotal();
        Out._EntitiesRestored             = InReport.Get_EntitiesRestored();
        Out._EntitiesSkipped              = InReport.Get_EntitiesSkipped();
        Out._EntitiesOrphaned             = InReport.Get_EntitiesOrphaned();
        Out._PayloadsTotal                = InReport.Get_PayloadsTotal();
        Out._PayloadsApplied              = InReport.Get_PayloadsApplied();
        Out._PayloadsRejected             = InReport.Get_PayloadsRejected();
        Out._PayloadsDroppedNoHandler     = InReport.Get_PayloadsDroppedNoHandler();
        Out._PayloadsDroppedTimeout       = InReport.Get_PayloadsDroppedTimeout();
        Out._PayloadsDestroyedWithEntries = InReport.Get_PayloadsDestroyedWithEntries();
        Out._PayloadsUnappliedAtFinish    = InReport.Get_PayloadsUnappliedAtFinish();
        Out._PayloadsOnSkippedEntities    = InReport.Get_PayloadsOnSkippedEntities();
        Out._PayloadsOnOrphanedEntities   = InReport.Get_PayloadsOnOrphanedEntities();
        Out._PayloadsOnUnresolvedOwner    = InReport.Get_PayloadsOnUnresolvedOwner();
        Out._PayloadsDropped              = InReport.Get_PayloadsDropped();
        return Out;
    }

    auto ResolveProbe(UWorld* InWorld) -> FCk_Handle
    {
        if (InWorld == nullptr)
        { return {}; }
        return ck::auto_test::snapshot::ResolveEntityBySpawnRecipe(
            InWorld, UCk_AutoTest_Snapshot_ApplyClosureProbe_EntityScript_UE::StaticClass());
    }

    auto Spawn_Probe(UWorld* InServer) -> void
    {
        if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
        { CVar->Set(1, ECVF_SetByCode); }

        auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
        UCk_Utils_EntityScript_UE::Request_SpawnEntity(
            Transient, UCk_AutoTest_Snapshot_ApplyClosureProbe_EntityScript_UE::StaticClass(), FInstancedStruct{}, {});
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_RepeatedLoadSameSlot_Gate,
    "Ck.Snapshot.Idempotency.RepeatedLoadSameSlot",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_RepeatedLoadSameSlot_Gate::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_snapshot_idempotency;
    using namespace ck_autotest_snapshot_applyclosure;

    const auto First = MakeShared<FCycleFingerprint>();

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = RepeatedLoad_SlotName;

    // ONE save, TWO loads of it. Saving between loads would ask the other question (which SaveAfterLoadThenLoad
    // asks) and would hide a second load that behaved differently from the first.
    Spec.NumCycles = 2;
    Spec.SaveEveryCycle = false;

    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    {
        Spawn_Probe(InServer);
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

        auto& Values = Probe.Get<ck::FFragment_AutoTest_ApplyClosure_Values>();
        Values._ValueA = MutatedValueA;
        Values._ValueB = MutatedValueB;
    });

    Spec.Assert = FCk_NetAutoTest_Assertion::CreateLambda([this, First]() -> bool
    {
        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
        auto AllGood = TestTrue(TEXT("post-load server world resolves"), Server != nullptr);
        if (Server == nullptr)
        { return false; }

        auto* Subsystem = ck::auto_test::snapshot::Get_SnapshotSubsystem(Server);
        if (NOT TestTrue(TEXT("snapshot subsystem present post-reload"), Subsystem != nullptr))
        { return false; }

        const auto Probe = ResolveProbe(Server);
        AllGood &= TestTrue(TEXT("the probe was restored"), ck::IsValid(Probe));

        if (ck::IsValid(Probe))
        {
            const auto& Values = Probe.Get<ck::FFragment_AutoTest_ApplyClosure_Values>();
            AllGood &= TestEqual(TEXT("the restored value is the SAVED one, every time"),
                Values._ValueA, MutatedValueA);
            AllGood &= TestEqual(TEXT("...for both payloads"), Values._ValueB, MutatedValueB);
        }

        const auto Fingerprint = Make_Fingerprint(Subsystem->Get_LastLoadReport());

        if (NOT First->Get_IsRecorded())
        {
            *First = Fingerprint;
            return AllGood;
        }

        // The second load of the SAME slot must be indistinguishable from the first — same rows read, same
        // entities restored, same payloads applied. A world that accreted on the first load reads differently
        // here even when every individual value still looks right.
        AllGood &= TestTrue(
            FString::Printf(TEXT("loading the same slot twice reports identically (first: %s | second: %s)"),
                *First->Get_Description(), *Fingerprint.Get_Description()),
            Fingerprint == *First);

        return AllGood;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_SaveAfterLoadThenLoad_Gate,
    "Ck.Snapshot.Idempotency.SaveAfterLoadThenLoad",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_SaveAfterLoadThenLoad_Gate::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_snapshot_idempotency;
    using namespace ck_autotest_snapshot_applyclosure;

    const auto First = MakeShared<FCycleFingerprint>();

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = SaveAfterLoad_SlotName;

    // The default shape: save -> load -> save -> load. Cycle 2's save is taken from a world that a load built,
    // so its numbers answer "does a restored world capture the way the original did".
    Spec.NumCycles = 2;

    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    {
        Spawn_Probe(InServer);
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

        auto& Values = Probe.Get<ck::FFragment_AutoTest_ApplyClosure_Values>();
        Values._ValueA = MutatedValueA;
        Values._ValueB = MutatedValueB;
    });

    Spec.Assert = FCk_NetAutoTest_Assertion::CreateLambda([this, First]() -> bool
    {
        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
        auto AllGood = TestTrue(TEXT("post-load server world resolves"), Server != nullptr);
        if (Server == nullptr)
        { return false; }

        auto* Subsystem = ck::auto_test::snapshot::Get_SnapshotSubsystem(Server);
        if (NOT TestTrue(TEXT("snapshot subsystem present post-reload"), Subsystem != nullptr))
        { return false; }

        const auto Probe = ResolveProbe(Server);
        AllGood &= TestTrue(TEXT("the probe survived the cycle"), ck::IsValid(Probe));

        if (ck::IsValid(Probe))
        {
            const auto& Values = Probe.Get<ck::FFragment_AutoTest_ApplyClosure_Values>();
            AllGood &= TestEqual(TEXT("its value round-trips unchanged, not doubled or reset"),
                Values._ValueA, MutatedValueA);
            AllGood &= TestEqual(TEXT("...for both payloads"), Values._ValueB, MutatedValueB);
        }

        const auto Fingerprint = Make_Fingerprint(Subsystem->Get_LastLoadReport());

        if (NOT First->Get_IsRecorded())
        {
            *First = Fingerprint;
            return AllGood;
        }

        // Duplication and leak in ONE number each: a world that gained rows across the cycle raises
        // EntitiesTotal/PayloadsTotal, and one that lost them lowers Applied. Both are invisible to a
        // value-only assertion, which is how the 2026-07-29 inflation shipped.
        AllGood &= TestTrue(
            FString::Printf(TEXT("a save taken after a load loads back identically (cycle 1: %s | cycle 2: %s)"),
                *First->Get_Description(), *Fingerprint.Get_Description()),
            Fingerprint == *First);

        return AllGood;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
