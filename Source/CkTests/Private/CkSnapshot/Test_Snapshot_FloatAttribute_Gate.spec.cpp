// CkSnapshot Phase-8 GATE test — FloatAttribute round-trip through a full-world save/load.
//
// Decides whether the (deliberately unregistered) attribute->modifier RecordOfAttributeModifiers
// known-gap actually breaks restore. Risk: the modifier VALUE sub-fragments are captured, but the
// attribute->modifier linkage record is NOT — so if an attribute recompute processor runs after
// load and walks the empty record, FinalValue could clobber from 60 back to the base 42.5.
//
// Why a C++ .spec.cpp in a private PIE *server* world (and not an in-world AS AutoTest):
//   ck::snapshot::Run_Restore does a full registry.clear() (wipe-then-restore). An AS AutoTest
//   entity-script runs INSIDE that world and would be wiped mid-test. The C++ spec runner is not
//   an ECS entity, so the wipe only ever touches the private PIE world's registry — never the test.
//   The PIE world supplies the scheduler, so attribute processors actually run (FEcsWorld does not).
//
// Flow: spawn subject (Health=42.5) -> +17.5 revocable Add modifier -> tick -> assert Final==60
//   -> Run_Capture -> mutate base to 0 (Final drifts) -> tick -> assert Final!=60
//   -> Run_Restore -> tick (forces recompute over restored entities) -> re-discover the attribute
//   by raw-registry view (the actor<->entity bridge is severed by the wipe) -> assert Final==60.
//
// Surface in Session Frontend: Ck.Snapshot.FloatAttribute.Gate

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "Serialization/MemoryReader.h"
#include "Serialization/MemoryWriter.h"

#include "CkAttribute/FloatAttribute/CkFloatAttribute_Fragment.h"
#include "CkAttribute/FloatAttribute/CkFloatAttribute_Fragment_Data.h"
#include "CkAttribute/FloatAttribute/CkFloatAttribute_Utils.h"

#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/OwningActor/CkOwningActor_Utils.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkSnapshot/SaveGame/CkSnapshot_Header.h"
#include "CkSnapshot/Snapshot/CkSnapshot_Capture.h"
#include "CkSnapshot/Snapshot/CkSnapshot_LoadReport.h"
#include "CkSnapshot/Snapshot/CkSnapshot_Restore.h"

#include "CkTests/Net/CkAutoTest_NetSubject.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

// --------------------------------------------------------------------------------------------------------------------

namespace
{
    // Attribute the subject's entity-script Construct adds, with initial value 42.5 (matches the
    // existing CkAttribute_Float_* net specs that reuse ACk_AutoTest_NetSubject).
    constexpr auto Gate_AttributeTagName = TEXT("FloatAttribute.Health");

    // Reuse the same tag string for the modifier name (the modifier index is separate from the
    // attribute index within CkAttribute), as the modifier-add net spec does.
    constexpr auto Gate_ModifierTagName = TEXT("FloatAttribute.Health");

    // 42.5 (base) + 17.5 (revocable Add) = 60.0. Picked so it's distinct from the base and not at
    // the clamp boundary (Max=100).
    constexpr auto Gate_ModifierDelta = 17.5f;
    constexpr auto Gate_ExpectedFinal = 60.0f;

    // Helper: resolve the server-side float attribute handle via the still-bridged subject actor.
    // Valid only PRE-restore (the wipe severs the actor<->entity bridge).
    auto Gate_ResolveServerAttribute(UWorld* InServer) -> FCk_Handle_FloatAttribute
    {
        if (InServer == nullptr)
        { return {}; }

        auto* Subject = ACk_AutoTest_NetSubject::Find(InServer);
        if (Subject == nullptr)
        { return {}; }

        const auto OwnerEntity = UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(Subject);
        if (ck::Is_NOT_Valid(OwnerEntity))
        { return {}; }

        const auto AttributeTag = FGameplayTag::RequestGameplayTag(FName{Gate_AttributeTagName});
        return UCk_Utils_FloatAttribute_UE::TryGet(OwnerEntity, AttributeTag);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_FloatAttribute_Gate,
    "Ck.Snapshot.FloatAttribute.Gate",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_FloatAttribute_Gate::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    // Server-only: NumClients=1 == 1 server window + 0 additional clients. Snapshot is server-only.
    constexpr auto NumPIEClients = 1;
    constexpr auto ExpectedTotalWorlds = 1;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesPerSettle = 30;

    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    // Snapshot bytes + header survive across latent commands (the FArchive objects do not).
    auto SavedBytes = MakeShared<TArray<uint8>>();
    auto SavedHeader = MakeShared<FCk_Snapshot_Header>();
    auto RestoredCountSlot = MakeShared<int32>(0);

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // ---- Stage 1 — spawn subject (entity-script Construct adds FloatAttribute.Health = 42.5) ------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;

            auto* Subject = InServer->SpawnActor<ACk_AutoTest_NetSubject>(
                ACk_AutoTest_NetSubject::StaticClass(), FTransform::Identity, SpawnInfo);

            if (Subject == nullptr)
            { AddError(TEXT("Stage 1: server-side spawn of ACk_AutoTest_NetSubject returned null")); }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // ---- Stage 2 — add a revocable +17.5 Add modifier so Final == 60 ------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto AttributeHandle = Gate_ResolveServerAttribute(InServer);
            if (ck::Is_NOT_Valid(AttributeHandle))
            { AddError(TEXT("Stage 2: could not resolve the server-side float attribute")); return; }

            const auto ModifierTag = FGameplayTag::RequestGameplayTag(FName{Gate_ModifierTagName});
            const auto ModifierParams = FCk_Fragment_FloatAttributeModifier_ParamsData{
                Gate_ModifierDelta, ECk_MinMaxCurrent::Current};

            UCk_Utils_FloatAttributeModifier_UE::Add_Revocable(
                AttributeHandle,
                ModifierTag,
                ECk_AttributeModifier_Operation::Add,
                ModifierParams);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // ---- Stage 3 — pre-save sanity: Final == 60 --------------------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            auto AttributeHandle = Gate_ResolveServerAttribute(Server);
            if (ck::Is_NOT_Valid(AttributeHandle))
            { AddError(TEXT("Stage 3: could not resolve attribute for pre-save assertion")); return false; }

            const auto Final = UCk_Utils_FloatAttribute_UE::Get_FinalValue(AttributeHandle);
            TestEqual(TEXT("pre-save FinalValue reflects base + revocable modifier"), Final, Gate_ExpectedFinal);
            return true;
        }),
        TEXT("pre-save sanity: Final == 60")));

    // ---- Stage 4 — capture the whole server world ------------------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, SavedBytes, SavedHeader](UWorld* InServer) -> void
        {
            SavedBytes->Reset();
            *SavedHeader = FCk_Snapshot_Header{};

            auto Writer = FMemoryWriter{*SavedBytes, /*bIsPersistent=*/true};
            const auto Result = ck::snapshot::Run_Capture(*InServer, Writer, *SavedHeader);

            TestEqual(TEXT("Stage 4: capture result is Success"),
                static_cast<uint8>(Result), static_cast<uint8>(ECk_SnapshotResult::Success));
            TestTrue(TEXT("Stage 4: capture produced bytes"), SavedBytes->Num() > 0);
        })));

    // ---- Stage 5 — mutate live base so a successful restore visibly reverts it --------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto AttributeHandle = Gate_ResolveServerAttribute(InServer);
            if (ck::Is_NOT_Valid(AttributeHandle))
            { AddError(TEXT("Stage 5: could not resolve attribute to mutate")); return; }

            UCk_Utils_FloatAttribute_UE::Request_Override(AttributeHandle, 0.0f);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto AttributeHandle = Gate_ResolveServerAttribute(ck::auto_test::net::Get_ServerWorld());
            if (ck::Is_NOT_Valid(AttributeHandle))
            { AddError(TEXT("Stage 5: could not resolve attribute for post-mutate assertion")); return false; }

            const auto Final = UCk_Utils_FloatAttribute_UE::Get_FinalValue(AttributeHandle);
            TestNotEqual(TEXT("post-mutate FinalValue drifted away from 60"), Final, Gate_ExpectedFinal);
            return true;
        }),
        TEXT("post-mutate: Final != 60")));

    // ---- Stage 6 — restore (full wipe + rebuild from snapshot) ------------------------------------------------

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this, SavedBytes, SavedHeader, RestoredCountSlot](UWorld* InServer) -> void
        {
            auto Reader = FMemoryReader{*SavedBytes, /*bIsPersistent=*/true};
            const auto Report = ck::snapshot::Run_Restore(*InServer, Reader, *SavedHeader);

            *RestoredCountSlot = Report.Get_EntitiesRestored();
            AddInfo(FString::Printf(TEXT("DIAG Stage 6: restore reported EntitiesRestored=%d, SkippedFragmentTypes=%d"),
                Report.Get_EntitiesRestored(), Report.Get_SkippedFragmentTypes().Num()));

            TestEqual(TEXT("Stage 6: restore result is Success"),
                static_cast<uint8>(Report.Get_Result()), static_cast<uint8>(ECk_SnapshotResult::Success));
        })));

    // Tick AFTER restore so any attribute recompute processor runs over the restored entities —
    // this is what would clobber Final back to base if the missing modifier-record bites.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // ---- Stage 7 — GATE assertion: re-discover the restored attribute and check Final == 60 ------------------
    // The actor<->entity bridge is severed by the wipe, so find the attribute by raw-registry view
    // over its params fragment (mirrors the FEcsWorld core round-trip test's re-discovery pattern).

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this, RestoredCountSlot]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            if (Server == nullptr)
            { AddError(TEXT("Stage 7: server world unavailable")); return false; }

            auto* EcsWorld = Server->GetSubsystem<UCk_EcsWorld_Subsystem_UE>();
            if (EcsWorld == nullptr)
            { AddError(TEXT("Stage 7: no UCk_EcsWorld_Subsystem_UE on the server world")); return false; }

            auto& CkRegistry = EcsWorld->Get_Registry();
            auto* RawRegistry = ck::registry_table::TryResolve(CkRegistry.Get_RegistryHandle());
            if (RawRegistry == nullptr)
            { AddError(TEXT("Stage 7: could not resolve the raw entt registry")); return false; }

            // LIVE-NESS GATE: discover the restored attribute entity via its persistent value fragment to obtain a
            // raw entity, build a handle, then read through UCk_Utils_FloatAttribute_UE::Get_FinalValue — which Casts
            // and ensures on LifetimeOwner. With Layer-3 transient adoption the infra is restored, so this resolves to
            // a LIVE attribute (Final == 60). If liveness were still broken, Cast would ensure and fail the test.
            auto AttrEntityCount = 0;
            auto Final = -1.0f;

            auto View = RawRegistry->view<ck::FFragment_FloatAttribute_Current>();
            for (const auto Entity : View)
            {
                ++AttrEntityCount;
                auto Handle = ck::MakeHandle(FCk_Entity{Entity}, CkRegistry);
                // Cast (CastChecked typesafe) ensures on the attribute's infra incl. LifetimeOwner — this is the
                // live-ness check. With Layer-3 transient adoption it succeeds; pre-Layer-3 it ensured (the gap).
                auto AttrHandle = UCk_Utils_FloatAttribute_UE::Cast(Handle);
                Final = static_cast<float>(UCk_Utils_FloatAttribute_UE::Get_FinalValue(AttrHandle));
            }

            AddInfo(FString::Printf(
                TEXT("DIAG Stage 7 (LIVE): EntitiesRestored=%d | FloatAttribute_Current entities=%d | Final=%f"),
                *RestoredCountSlot, AttrEntityCount, Final));

            TestEqual(TEXT("Stage 7: exactly one float attribute survived restore"), AttrEntityCount, 1);

            if (AttrEntityCount > 0)
            {
                TestEqual(TEXT("GATE (LIVE): restored attribute is operational — Get_FinalValue == 60"),
                    Final, Gate_ExpectedFinal);
            }
            return true;
        }),
        TEXT("GATE: restored attribute Final == 60 (with zero-vs-cast-fail diagnostics)")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            FAutomationTestBase::bSuppressLogErrors = false;
            FAutomationTestBase::bSuppressLogWarnings = false;
            return true;
        }),
        TEXT("restore log suppression statics")));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
