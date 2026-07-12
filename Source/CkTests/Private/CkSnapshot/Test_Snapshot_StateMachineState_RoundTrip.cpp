// Registry-level round-trip for the StateMachine snapshot wiring (no UWorld / PIE).
//
// Covers the persisted DECISION RECORD of the SM restore design (docs/superpowers/specs/
// 2026-06-10-CkSnapshot-StateMachine-restore-design.md §2): FFragment_Sm_Params (Tier-A, all five
// fields via SaveGame metas) and FFragment_Sm_Current's persisted subset ({_RunStatus byte,
// _CurrentStateClass by soft class path}; _CurrentStateHandle is deliberately NOT persisted — the
// post-load redrive recreates the live state graph). The redrive half
// (FProcessor_Sm_HydrationResume) is covered by the Ck.Snapshot.Parity.StateMachine*_MPReload gates.
//
// Surface in Session Frontend: Ck.Snapshot.StateMachine.StateRoundTrip

#include "CkSnapshot/Snapshot/CkSnapshot_Capture.h"
#include "CkSnapshot/Snapshot/CkSnapshot_Restore.h"
#include "CkEcs/Snapshot/CkSnapshot_Context.h"
#include "CkSnapshot/SaveGame/CkSnapshot_Header.h"
#include "CkSnapshot/Snapshot/CkSnapshot_LoadReport.h"

#include "CkStateMachine/StateMachine/CkStateMachine_Fragment.h"
#include "CkStateMachine/StateMachine/CkStateMachine_Fragment_Data.h"

#include "CkTests/Net/CkAutoTest_Sm_RecordingState.h"

#include "CkEcs/World/CkEcsWorld.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"

#include "CkCore/Macros/CkMacros.h"

#include "Serialization/BufferArchive.h"
#include "Serialization/MemoryReader.h"

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_StateMachineState_RoundTrip_Test,
    "Ck.Snapshot.StateMachine.StateRoundTrip",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_StateMachineState_RoundTrip_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    // ---- Arrange: stand up a private ECS world with one StateMachine-shaped entity ---------------------------------
    auto EcsWorld = ck::FEcsWorld{};

    auto* RawRegistry = ck::registry_table::TryResolve(EcsWorld.Get_Registry().Get_RegistryHandle());
    if (NOT TestNotNull(TEXT("Resolved raw entt registry from FEcsWorld"), RawRegistry))
    { return false; }

    auto Entity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(EcsWorld.Get_Registry());
    if (NOT TestTrue(TEXT("Entity is valid"), ck::IsValid(Entity)))
    { return false; }

    // Fragments added directly (UCk_Utils_StateMachine_UE::Add also arms FTag_Sm_RequiresSetup and a
    // debug name; the snapshot contract under test is fragment-level, exactly what a restore reproduces).
    // Every persisted Params field carries a distinct NON-DEFAULT value so a silent
    // serialize-nothing regression (the Tier-A inert-marker trap) cannot pass.
    auto SavedParams = FCk_Fragment_StateMachine_ParamsData{UCk_AutoTest_Sm_RecordingState_A::StaticClass()};
    SavedParams
        .Set_AutoStart(ECk_SmAutoStart::Disabled)
        .Set_Replication(ECk_Replication::Replicates)
        .Set_AuthorityModel(ECk_Sm_AuthorityModel::OwningClientAuthoritative)
        .Set_ReplicationModel(ECk_Sm_ReplicationModel::WithoutHistory);

    // Current: non-default RunStatus (Paused) + a current state class that differs from the
    // initial state class — the exact decision record the post-load re-drive consumes.
    const auto SavedCurrentStateClass =
        TSubclassOf<UCk_SmState_EntityScript>{UCk_AutoTest_Sm_RecordingState_B::StaticClass()};

    Entity.Add<ck::FFragment_Sm_Params>(SavedParams);
    Entity.Add<ck::FFragment_Sm_Current>(
        ECk_SmRunStatus::Paused, FCk_Handle_SmState{}, SavedCurrentStateClass);

    // ---- Act: capture -> (registry is wiped by restore) -> restore ------------------------------------------------
    auto Buffer = FBufferArchive{};
    auto Header = FCk_Snapshot_Header{};

    const auto CaptureResult = ck::snapshot::Run_Capture_Registry(*RawRegistry, Buffer, Header);
    if (NOT TestEqual(TEXT("Capture result is Success"),
            static_cast<uint8>(CaptureResult), static_cast<uint8>(ECk_SnapshotResult::Success)))
    { return false; }

    auto Reader = FMemoryReader{Buffer, /*bIsPersistent=*/true};
    const auto Report = ck::snapshot::Run_Restore_Registry(*RawRegistry, Reader, Header);

    TestEqual(TEXT("Restore result is Success"),
        static_cast<uint8>(Report.Get_Result()), static_cast<uint8>(ECk_SnapshotResult::Success));

    // ---- Assert: Params survived with every field intact ----------------------------------------------------------
    {
        auto ParamsCount = 0;
        auto ParamsView = RawRegistry->view<ck::FFragment_Sm_Params>();

        for (const auto E : ParamsView)
        {
            ++ParamsCount;
            const auto& Restored = ParamsView.get<ck::FFragment_Sm_Params>(E);

            TestEqual(TEXT("InitialStateClass round-tripped (A)"),
                Restored.Get_InitialStateClass().Get(), SavedParams.Get_InitialStateClass().Get());
            TestTrue(TEXT("AutoStart round-tripped (Disabled, not the OnSetup default)"),
                Restored.Get_AutoStart() == ECk_SmAutoStart::Disabled);
            TestTrue(TEXT("Replication round-tripped (Replicates, not the DoesNotReplicate default)"),
                Restored.Get_Replication() == ECk_Replication::Replicates);
            TestTrue(TEXT("AuthorityModel round-tripped (OwningClientAuthoritative, not the AutoDetect default)"),
                Restored.Get_AuthorityModel() == ECk_Sm_AuthorityModel::OwningClientAuthoritative);
            TestTrue(TEXT("ReplicationModel round-tripped (WithoutHistory, not the WithHistory default)"),
                Restored.Get_ReplicationModel() == ECk_Sm_ReplicationModel::WithoutHistory);
        }

        TestEqual(TEXT("Exactly one entity carries FFragment_Sm_Params post-restore"),
            ParamsCount, 1);
    }

    // ---- Assert: Current's decision record survived; the live state handle did NOT --------------------------------
    {
        auto CurrentCount = 0;
        auto CurrentView = RawRegistry->view<ck::FFragment_Sm_Current>();

        for (const auto E : CurrentView)
        {
            ++CurrentCount;
            const auto& Restored = CurrentView.get<ck::FFragment_Sm_Current>(E);

            TestTrue(TEXT("RunStatus round-tripped (Paused, not the Stopped default)"),
                Restored.Get_RunStatus() == ECk_SmRunStatus::Paused);
            TestEqual(TEXT("CurrentStateClass round-tripped by soft class path (B)"),
                Restored.Get_CurrentStateClass().Get(), SavedCurrentStateClass.Get());
            TestTrue(TEXT("CurrentStateHandle is NOT persisted (re-drive recreates the live state graph)"),
                ck::Is_NOT_Valid(Restored.Get_CurrentStateHandle()));
        }

        TestEqual(TEXT("Exactly one entity carries FFragment_Sm_Current post-restore (Has/Cast key)"),
            CurrentCount, 1);
    }

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
