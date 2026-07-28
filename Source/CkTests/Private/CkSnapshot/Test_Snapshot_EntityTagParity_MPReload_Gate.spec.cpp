// CkSnapshot EntityTag-Parity GATE — strict value round-trip of an entity's counted FName EntityTag set through REAL
// OpenLevel reloads, asserted on the authority (single-world) after save -> restore.
//
// EntityTag is UNREPLICATED (no Replicate processor / RepData / MayRequireReplication) — its state is purely local and
// never reaches clients — so this gate drives the AUTHORITY/single-world reload path (NM_Standalone OpenLevel, one PIE
// client), NOT the listen-server seamless-travel path of the TagSet/TeamPlayer parity gates. The "MPReload" suffix is
// kept for suite naming consistency; there is no client convergence to assert.
//
// WHAT MAKES THIS THE MERGE-BUG PIN: both probes' Construct SEEDS one EntityTag tag (ConstructSeed). On a v3 load the
// rebuilt entity re-runs Construct — re-Adding the seed through the SAME deferred EntityTag request path that is
// GatedDuringLoad — at the same time HydrationApply reconstitutes the saved set. A broken applier that read the "live"
// set at HydrationApply time (before the construct-seed drained) and cleared-then-re-Added would MERGE the seed under
// the saved adds, inflating ConstructSeed's count once PER load cycle. The fix reconstitutes via a single composite
// FCk_Request_EntityTag_RestoreSet that diffs at DRAIN time, so the seed stays at exactly its saved count. This gate
// pins that across TWO real reload cycles (the monotonic-inflation signature the single-cycle case can miss), plus:
//   - counted multi-add round-trips (Beta x3 -> exactly 3, proven by 3 removes flipping it off),
//   - per-tag EnTT storage presence survives (ForEach_Entity / Has find a restored tag),
//   - values are readable at the load-complete/settle point,
//   - construct-seed RESURRECTION when the saved payload is UNSET (all tags removed pre-save) — chosen behavior.
// Surface in Session Frontend: Ck.Snapshot.Parity.EntityTag_MPReload

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Engine/GameInstance.h"
#include "EngineUtils.h" // TActorIterator

#include "CkEntityTag/CkEntityTag_Utils.h"
#include "CkEntityTag/CkEntityTag_Fragment.h" // ck::FFragment_EntityTag_Current (count read)

#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/OwningActor/CkOwningActor_Utils.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "CkTests/Net/CkAutoTest_EntityTagSeedProbe.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

namespace
{
    const auto     EntityTagParity_SlotName        = FName{TEXT("CkSnapshot_EntityTagParity_GateSlot")};
    const auto     EntityTagParity_SeedLocation    = FVector{100.0, 200.0, 300.0};
    const auto     EntityTagParity_ResurrectLocation = FVector{-400.0, 500.0, 300.0};

    // Raw FName tags (EntityTag::Add accepts any non-None FName — no DefaultGameplayTags.ini registration needed).
    // ConstructSeed (the seed both probes Add in Construct) comes from ck::auto_test::entity_tag_seed::Get_ConstructSeedTag().
    const auto     EntityTagParity_Alpha = FName{TEXT("EntityTag.Parity.Alpha")}; // count 1 — survives
    const auto     EntityTagParity_Beta  = FName{TEXT("EntityTag.Parity.Beta")};  // count 3 — counted round-trip
    const auto     EntityTagParity_Gamma = FName{TEXT("EntityTag.Parity.Gamma")}; // added then removed pre-save — stays gone

    // Post-OpenLevel the world is NM_Standalone, so the net harness's Get_ServerWorld() returns null. The current PIE
    // world is the one that HasBegunPlay (mirrors the M2a gate). Stateless — correct across N sequential reloads.
    auto EntityTagParity_CurrentWorld() -> UWorld*
    {
        for (auto* World : ck::auto_test::net::Get_AllPIEWorlds())
        { if (World != nullptr && World->HasBegunPlay()) { return World; } }
        return nullptr;
    }

    auto EntityTagParity_Subsystem(UWorld* InWorld) -> UCk_Snapshot_Subsystem_UE*
    {
        if (InWorld == nullptr || InWorld->GetGameInstance() == nullptr) { return nullptr; }
        return InWorld->GetGameInstance()->GetSubsystem<UCk_Snapshot_Subsystem_UE>();
    }

    // Two distinct probe classes so each instance is found unambiguously (the base Find assumes one subject per world).
    // They are siblings (both derive ACk_AutoTest_NetSubject_M2bProbe), so neither iterator picks up the other.
    template <typename T_Probe>
    auto EntityTagParity_FindProbe(UWorld* InWorld) -> T_Probe*
    {
        if (InWorld == nullptr) { return nullptr; }
        for (auto It = TActorIterator<T_Probe>(InWorld); It; ++It) { return *It; }
        return nullptr;
    }

    auto EntityTagParity_ResolveEntity(AActor* InProbe) -> FCk_Handle
    {
        if (InProbe == nullptr) { return {}; }
        return UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(InProbe);
    }

    // Refcount of a specific FName tag on the entity — read straight off the fragment (Get_AllTags is DevelopmentOnly).
    // 0 == absent.
    auto EntityTagParity_CountOf(const FCk_Handle& InEntity, FName InTag) -> int32
    {
        if (ck::Is_NOT_Valid(InEntity) || NOT InEntity.Has<ck::FFragment_EntityTag_Current>())
        { return 0; }
        for (const auto& TagCount : InEntity.Get<ck::FFragment_EntityTag_Current>().Get_Tags())
        {
            if (TagCount._Name == InTag)
            { return TagCount._Count; }
        }
        return 0;
    }

    // A restored tag must be discoverable through the per-tag EnTT storage view (ForEach_Entity), not just via the
    // count fragment — proves Set_StoragePresence ran on restore. Returns true iff InEntity is in the view for InTag.
    auto EntityTagParity_StorageViewFinds(const FCk_Handle& InEntity, FName InTag) -> bool
    {
        if (ck::Is_NOT_Valid(InEntity)) { return false; }
        auto Found = false;
        UCk_Utils_EntityTag_UE::ForEach_Entity(InEntity, InTag, [&](FCk_Handle InFound)
        {
            if (InFound == InEntity) { Found = true; }
        });
        return Found;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_EntityTagParity_MPReload_Gate,
    "Ck.Snapshot.Parity.EntityTag_MPReload",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_EntityTagParity_MPReload_Gate::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 1;        // single Standalone world (EntityTag is local — no client to converge)
    constexpr auto ExpectedTotalWorlds = 1;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesPerSettle = 30;
    constexpr auto FramesForReload = 240;    // teardown + OpenLevel + rebuild + hydrate + quiescence span frames
    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    const auto ConstructSeed = ck::auto_test::entity_tag_seed::Get_ConstructSeedTag();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // Stage 1 — spawn both snapshot-respawnable probes. Each probe's Construct seeds ConstructSeed (deferred Add).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;

            auto* Seed = InServer->SpawnActor<ACk_AutoTest_EntityTagSeedProbe>(
                ACk_AutoTest_EntityTagSeedProbe::StaticClass(), FTransform{EntityTagParity_SeedLocation}, SpawnInfo);
            if (Seed == nullptr) { AddError(TEXT("Stage 1: seed probe spawn returned null")); }

            auto* Resurrect = InServer->SpawnActor<ACk_AutoTest_EntityTagResurrectProbe>(
                ACk_AutoTest_EntityTagResurrectProbe::StaticClass(), FTransform{EntityTagParity_ResurrectLocation}, SpawnInfo);
            if (Resurrect == nullptr) { AddError(TEXT("Stage 1: resurrect probe spawn returned null")); }
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 2 — runtime-mutate (all deferred, FIFO).
    //   SeedProbe     : keep ConstructSeed, add Alpha x1, Beta x3 (counted), Gamma added-then-removed.
    //   ResurrectProbe: remove ConstructSeed (its only tag) -> Current auto-removed -> Produce will be UNSET.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, ConstructSeed](UWorld* InServer) -> void
        {
            auto SeedEntity = EntityTagParity_ResolveEntity(EntityTagParity_FindProbe<ACk_AutoTest_EntityTagSeedProbe>(InServer));
            if (ck::Is_NOT_Valid(SeedEntity)) { AddError(TEXT("Stage 2: seed probe entity unresolved")); return; }

            UCk_Utils_EntityTag_UE::Add(SeedEntity, EntityTagParity_Alpha);
            UCk_Utils_EntityTag_UE::Add(SeedEntity, EntityTagParity_Beta);
            UCk_Utils_EntityTag_UE::Add(SeedEntity, EntityTagParity_Beta);
            UCk_Utils_EntityTag_UE::Add(SeedEntity, EntityTagParity_Beta);  // Beta -> count 3
            UCk_Utils_EntityTag_UE::Add(SeedEntity, EntityTagParity_Gamma);
            UCk_Utils_EntityTag_UE::Request_TryRemove(SeedEntity, EntityTagParity_Gamma, {}); // Gamma back to absent

            auto ResurrectEntity = EntityTagParity_ResolveEntity(EntityTagParity_FindProbe<ACk_AutoTest_EntityTagResurrectProbe>(InServer));
            if (ck::Is_NOT_Valid(ResurrectEntity)) { AddError(TEXT("Stage 2: resurrect probe entity unresolved")); return; }

            UCk_Utils_EntityTag_UE::Request_TryRemove(ResurrectEntity, ConstructSeed, {}); // its only tag -> Current auto-removed
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 2b — pre-save sanity (mutations processed) THEN Save (cycle 1).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, ConstructSeed](UWorld* InServer) -> void
        {
            const auto SeedEntity = EntityTagParity_ResolveEntity(EntityTagParity_FindProbe<ACk_AutoTest_EntityTagSeedProbe>(InServer));
            if (ck::Is_NOT_Valid(SeedEntity)) { AddError(TEXT("Stage 2b: seed probe entity unresolved pre-save")); return; }

            TestEqual(TEXT("pre-save: ConstructSeed count == 1 (seeded in Construct)"), EntityTagParity_CountOf(SeedEntity, ConstructSeed), 1);
            TestEqual(TEXT("pre-save: Alpha count == 1"), EntityTagParity_CountOf(SeedEntity, EntityTagParity_Alpha), 1);
            TestEqual(TEXT("pre-save: Beta count == 3 (counted)"), EntityTagParity_CountOf(SeedEntity, EntityTagParity_Beta), 3);
            TestFalse(TEXT("pre-save: Gamma absent (added then removed)"),
                UCk_Utils_EntityTag_UE::Has(SeedEntity, EntityTagParity_Gamma));

            const auto ResurrectEntity = EntityTagParity_ResolveEntity(EntityTagParity_FindProbe<ACk_AutoTest_EntityTagResurrectProbe>(InServer));
            if (ck::Is_NOT_Valid(ResurrectEntity)) { AddError(TEXT("Stage 2b: resurrect probe entity unresolved pre-save")); return; }
            TestFalse(TEXT("pre-save: resurrect probe ConstructSeed removed (EntityTag Current gone -> Produce UNSET)"),
                UCk_Utils_EntityTag_UE::Has(ResurrectEntity, ConstructSeed));

            auto* Sub = EntityTagParity_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 2b: no snapshot subsystem")); return; }
            Sub->Request_Save(EntityTagParity_SlotName, FCk_Delegate_OnSaveComplete{});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 3 — fire the async load (cycle 1) on the pre-reload server world + assert non-blocking.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Sub = EntityTagParity_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 3: no snapshot subsystem")); return; }
            Sub->Request_Load(EntityTagParity_SlotName, FCk_Delegate_OnLoadComplete{});
            TestTrue(TEXT("Stage 3: Request_Load non-blocking — load in progress after return"),
                Sub->Get_IsLoadInProgress());
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesForReload));

    // Stage 4 — CYCLE-1 assertions (post-reload world is NM_Standalone -> use the current-world finder, not RunOnServer).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, ConstructSeed]() -> bool
        {
            auto* Server = EntityTagParity_CurrentWorld();
            if (Server == nullptr) { AddError(TEXT("Stage 4: no post-travel world")); return false; }

            auto* Sub = EntityTagParity_Subsystem(Server);
            if (Sub == nullptr) { AddError(TEXT("Stage 4: no snapshot subsystem")); return false; }
            // Load-complete/settle gate: read tag values only after the load flag has cleared (the settle phase has
            // pumped the request FIFO to quiescence). This is the harness's OnLoadComplete-equivalent read point.
            TestFalse(TEXT("cycle 1: load flag cleared after completion"), Sub->Get_IsLoadInProgress());

            auto* Seed = EntityTagParity_FindProbe<ACk_AutoTest_EntityTagSeedProbe>(Server);
            if (Seed == nullptr) { AddError(TEXT("Stage 4: seed probe was not re-spawned")); return false; }
            auto SeedEntity = EntityTagParity_ResolveEntity(Seed);
            TestTrue(TEXT("cycle 1: seed actor<->entity bridge resolves"), ck::IsValid(SeedEntity));
            if (ck::Is_NOT_Valid(SeedEntity)) { return false; }

            // THE MERGE-BUG PIN: the construct-seed converges with the restored set on load; it must REPLACE (stay 1),
            // not MERGE (buggy applier inflates to 2). Runtime tags round-trip with their exact counts; removed stays gone.
            TestEqual(TEXT("cycle 1: ConstructSeed count == 1 (NOT inflated — REPLACE, not MERGE)"),
                EntityTagParity_CountOf(SeedEntity, ConstructSeed), 1);
            TestEqual(TEXT("cycle 1: Alpha count == 1 (round-tripped)"),
                EntityTagParity_CountOf(SeedEntity, EntityTagParity_Alpha), 1);
            TestEqual(TEXT("cycle 1: Beta count == 3 (counted round-trip, not just presence)"),
                EntityTagParity_CountOf(SeedEntity, EntityTagParity_Beta), 3);
            TestFalse(TEXT("cycle 1: Gamma stays absent"),
                UCk_Utils_EntityTag_UE::Has(SeedEntity, EntityTagParity_Gamma));

            // Per-tag EnTT storage presence survived restore: ForEach_Entity + Has both find the restored tags.
            TestTrue(TEXT("cycle 1: ForEach_Entity view finds ConstructSeed on the restored entity"),
                EntityTagParity_StorageViewFinds(SeedEntity, ConstructSeed));
            TestTrue(TEXT("cycle 1: ForEach_Entity view finds Beta on the restored entity"),
                EntityTagParity_StorageViewFinds(SeedEntity, EntityTagParity_Beta));
            TestTrue(TEXT("cycle 1: Has() finds Alpha on the restored entity"),
                UCk_Utils_EntityTag_UE::Has(SeedEntity, EntityTagParity_Alpha));

            // RESURRECTION: the resurrect probe's saved EntityTag payload was UNSET (all tags removed pre-save), so
            // nothing is hydrated and the construct-seed re-Adds. Chosen behavior — "absence is ambiguous" (see
            // CkSnapshot/Claude.md §5): Produce UNSET cannot distinguish "never had it" from "removed pre-save".
            auto* Resurrect = EntityTagParity_FindProbe<ACk_AutoTest_EntityTagResurrectProbe>(Server);
            if (Resurrect == nullptr) { AddError(TEXT("Stage 4: resurrect probe was not re-spawned")); return false; }
            const auto ResurrectEntity = EntityTagParity_ResolveEntity(Resurrect);
            TestTrue(TEXT("cycle 1: resurrect actor<->entity bridge resolves"), ck::IsValid(ResurrectEntity));
            if (ck::Is_NOT_Valid(ResurrectEntity)) { return false; }
            TestEqual(TEXT("cycle 1: ConstructSeed RESURRECTS on the resurrect probe (Produce UNSET -> Construct re-seeds)"),
                EntityTagParity_CountOf(ResurrectEntity, ConstructSeed), 1);
            return true;
        }),
        TEXT("EntityTag cycle 1: construct-seed REPLACED not merged; counted set round-trips; storage presence survives; seed resurrects")));

    // Stage 5 — Save (cycle 2) on the current Standalone world (RunOnServer would find no server world here).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = EntityTagParity_CurrentWorld();
            auto* Sub = EntityTagParity_Subsystem(Server);
            if (Sub == nullptr) { AddError(TEXT("Stage 5: no snapshot subsystem for cycle-2 save")); return false; }
            Sub->Request_Save(EntityTagParity_SlotName, FCk_Delegate_OnSaveComplete{});
            return true;
        }),
        TEXT("EntityTag cycle 2: save the post-reload-1 state")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 6 — fire the async load (cycle 2).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = EntityTagParity_CurrentWorld();
            auto* Sub = EntityTagParity_Subsystem(Server);
            if (Sub == nullptr) { AddError(TEXT("Stage 6: no snapshot subsystem for cycle-2 load")); return false; }
            Sub->Request_Load(EntityTagParity_SlotName, FCk_Delegate_OnLoadComplete{});
            TestTrue(TEXT("Stage 6: cycle-2 Request_Load non-blocking"), Sub->Get_IsLoadInProgress());
            return true;
        }),
        TEXT("EntityTag cycle 2: fire the second reload")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesForReload));

    // Stage 7 — CYCLE-2 assertions: the two-cycle exactness pin. The merge bug inflates the seed monotonically per
    // cycle (1 -> 2 -> 3); a single cycle can miss subtler variants, so re-assert exactness after a SECOND reload.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, ConstructSeed]() -> bool
        {
            auto* Server = EntityTagParity_CurrentWorld();
            if (Server == nullptr) { AddError(TEXT("Stage 7: no post-travel world")); return false; }

            auto* Sub = EntityTagParity_Subsystem(Server);
            if (Sub == nullptr) { AddError(TEXT("Stage 7: no snapshot subsystem")); return false; }
            TestFalse(TEXT("cycle 2: load flag cleared after completion"), Sub->Get_IsLoadInProgress());

            auto* Seed = EntityTagParity_FindProbe<ACk_AutoTest_EntityTagSeedProbe>(Server);
            if (Seed == nullptr) { AddError(TEXT("Stage 7: seed probe was not re-spawned (cycle 2)")); return false; }
            auto SeedEntity = EntityTagParity_ResolveEntity(Seed);
            if (ck::Is_NOT_Valid(SeedEntity)) { AddError(TEXT("Stage 7: seed entity unresolved (cycle 2)")); return false; }

            TestEqual(TEXT("cycle 2: ConstructSeed STILL == 1 after a SECOND reload (no monotonic inflation)"),
                EntityTagParity_CountOf(SeedEntity, ConstructSeed), 1);
            TestEqual(TEXT("cycle 2: Alpha still == 1"),
                EntityTagParity_CountOf(SeedEntity, EntityTagParity_Alpha), 1);
            TestEqual(TEXT("cycle 2: Beta still == 3"),
                EntityTagParity_CountOf(SeedEntity, EntityTagParity_Beta), 3);
            TestFalse(TEXT("cycle 2: Gamma still absent"),
                UCk_Utils_EntityTag_UE::Has(SeedEntity, EntityTagParity_Gamma));

            // The resurrected seed, re-saved in cycle 1 and restored in cycle 2, must also stay at exactly 1.
            auto* Resurrect = EntityTagParity_FindProbe<ACk_AutoTest_EntityTagResurrectProbe>(Server);
            if (Resurrect == nullptr) { AddError(TEXT("Stage 7: resurrect probe was not re-spawned (cycle 2)")); return false; }
            const auto ResurrectEntity = EntityTagParity_ResolveEntity(Resurrect);
            if (ck::Is_NOT_Valid(ResurrectEntity)) { AddError(TEXT("Stage 7: resurrect entity unresolved (cycle 2)")); return false; }
            TestEqual(TEXT("cycle 2: resurrected ConstructSeed still == 1 (no inflation of the resurrected tag)"),
                EntityTagParity_CountOf(ResurrectEntity, ConstructSeed), 1);
            return true;
        }),
        TEXT("EntityTag two-cycle exactness: counts unchanged after a SECOND save/load — the merge-bug regression pin")));

    // Stage 8 — counted-multi-add flip check on the restored Beta (count 3): 2 removes leave it present, the 3rd flips
    // it off. Proves the restored count is EXACTLY 3, not merely present. Runs last — nothing else depends on Beta.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = EntityTagParity_CurrentWorld();
            auto* Seed = EntityTagParity_FindProbe<ACk_AutoTest_EntityTagSeedProbe>(Server);
            auto SeedEntity = EntityTagParity_ResolveEntity(Seed);
            if (ck::Is_NOT_Valid(SeedEntity)) { AddError(TEXT("Stage 8: seed entity unresolved for flip check")); return false; }
            UCk_Utils_EntityTag_UE::Request_TryRemove(SeedEntity, EntityTagParity_Beta, {});
            UCk_Utils_EntityTag_UE::Request_TryRemove(SeedEntity, EntityTagParity_Beta, {}); // 3 -> 1 (still present)
            return true;
        }),
        TEXT("EntityTag flip: remove Beta x2 (restored count was 3)")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = EntityTagParity_CurrentWorld();
            auto* Seed = EntityTagParity_FindProbe<ACk_AutoTest_EntityTagSeedProbe>(Server);
            auto SeedEntity = EntityTagParity_ResolveEntity(Seed);
            if (ck::Is_NOT_Valid(SeedEntity)) { AddError(TEXT("Stage 8b: seed entity unresolved for flip check")); return false; }
            TestTrue(TEXT("flip: Beta still present after 2 of 3 removes (count 3 -> 1)"),
                UCk_Utils_EntityTag_UE::Has(SeedEntity, EntityTagParity_Beta));
            UCk_Utils_EntityTag_UE::Request_TryRemove(SeedEntity, EntityTagParity_Beta, {}); // 1 -> 0 (flips off)
            return true;
        }),
        TEXT("EntityTag flip: Beta survives 2 removes, 3rd remove pending")));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = EntityTagParity_CurrentWorld();
            auto* Seed = EntityTagParity_FindProbe<ACk_AutoTest_EntityTagSeedProbe>(Server);
            auto SeedEntity = EntityTagParity_ResolveEntity(Seed);
            if (ck::Is_NOT_Valid(SeedEntity)) { AddError(TEXT("Stage 8c: seed entity unresolved for flip check")); return false; }
            TestFalse(TEXT("flip: Beta absent after exactly 3 removes (proves restored count was exactly 3)"),
                UCk_Utils_EntityTag_UE::Has(SeedEntity, EntityTagParity_Beta));
            return true;
        }),
        TEXT("EntityTag flip: exactly 3 removes flip Beta off")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    // Restore log-suppression statics (they are static on FAutomationTestBase; leaking them would silence later tests).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            FAutomationTestBase::bSuppressLogErrors = false;
            FAutomationTestBase::bSuppressLogWarnings = false;
            return true;
        }),
        TEXT("EntityTag: restore log suppression statics")));

    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
