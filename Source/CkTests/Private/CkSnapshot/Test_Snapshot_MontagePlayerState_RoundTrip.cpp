// Registry-level round-trip for the MontagePlayer snapshot wiring (no UWorld / PIE / mesh).
//
// An MP parity gate is infeasible on the shared meshless probe: FProcessor_MontagePlayer_HandleRequests
// CK_ENSUREs on a missing SkeletalMeshComponent (an ensure fails AutoTests), so nothing can drive the
// Play path without a skeletal-mesh probe + montage asset. This test covers the SNAPSHOT half instead:
// FFragment_MontagePlayer_Params (presence — Has()/Cast are keyed on it) and
// FFragment_MontagePlayer_Current (the replicated FCk_MontagePlayer_State value) must survive
// capture -> wipe -> restore. The replication seed half (FProcessor_MontagePlayer_ReplicateOnRestore)
// stays gate-pending like Velocity.
//
// Surface in Session Frontend: Ck.Snapshot.MontagePlayer.StateRoundTrip

#include "CkSnapshot/Snapshot/CkSnapshot_Capture.h"
#include "CkSnapshot/Snapshot/CkSnapshot_Restore.h"
#include "CkEcs/Snapshot/CkSnapshot_Context.h"
#include "CkSnapshot/SaveGame/CkSnapshot_Header.h"
#include "CkSnapshot/Snapshot/CkSnapshot_LoadReport.h"

#include "CkAnimation/MontagePlayer/CkMontagePlayer_Fragment.h"

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
    FCk_Snapshot_MontagePlayerState_RoundTrip_Test,
    "Ck.Snapshot.MontagePlayer.StateRoundTrip",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_MontagePlayerState_RoundTrip_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    // ---- Arrange: stand up a private ECS world with one MontagePlayer-shaped entity ------------------------------
    auto EcsWorld = ck::FEcsWorld{};

    auto* RawRegistry = ck::registry_table::TryResolve(EcsWorld.Get_Registry().Get_RegistryHandle());
    if (NOT TestNotNull(TEXT("Resolved raw entt registry from FEcsWorld"), RawRegistry))
    { return false; }

    auto Entity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(EcsWorld.Get_Registry());
    if (NOT TestTrue(TEXT("Entity is valid"), ck::IsValid(Entity)))
    { return false; }

    // Fragments added directly (UCk_Utils_MontagePlayer_UE::Add ensures on a missing mesh component;
    // the snapshot contract under test is fragment-level, exactly what a restore reproduces).
    // The state carries a distinct non-default value in every serialized field except the montage
    // asset itself (no montage asset exists in this host project — the soft-path branch restores
    // null from an empty path; asset round-trip is covered by the future mesh-driven parity gate).
    auto SavedState = FCk_MontagePlayer_State{nullptr};
    SavedState
        .Set_SectionName(FName{TEXT("MontagePlayerRT_Section")})
        .Set_StartPosition(FCk_Time{1.25})
        .Set_PlayRate(1.5f)
        .Set_BlendInTime(FCk_Time{0.1})
        .Set_BlendOutTime(FCk_Time{0.4})
        .Set_ServerStartTime(FCk_Time{33.0})
        .Set_PlayInstanceId(7)
        .Set_Kind(ECk_MontagePlayer_StateKind::Pause);

    Entity.Add<ck::FFragment_MontagePlayer_Params>(FCk_Fragment_MontagePlayer_ParamsData{});
    Entity.Add<ck::FFragment_MontagePlayer_Current>(SavedState);

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

    // ---- Assert: both MontagePlayer fragments survived the wipe ---------------------------------------------------
    {
        auto ParamsCount = 0;
        for ([[maybe_unused]] const auto E : RawRegistry->view<ck::FFragment_MontagePlayer_Params>())
        { ++ParamsCount; }
        TestEqual(TEXT("Exactly one entity carries FFragment_MontagePlayer_Params post-restore (Has/Cast key)"),
            ParamsCount, 1);
    }

    {
        auto CurrentCount = 0;
        auto CurrentView = RawRegistry->view<ck::FFragment_MontagePlayer_Current>();

        for (const auto E : CurrentView)
        {
            ++CurrentCount;
            const auto& RestoredState = CurrentView.get<ck::FFragment_MontagePlayer_Current>(E).Get_State();

            TestEqual(TEXT("SectionName round-tripped"),
                RestoredState.Get_SectionName(), SavedState.Get_SectionName());
            TestEqual(TEXT("StartPosition round-tripped"),
                RestoredState.Get_StartPosition().Get_Seconds(), SavedState.Get_StartPosition().Get_Seconds());
            TestEqual(TEXT("PlayRate round-tripped"),
                RestoredState.Get_PlayRate(), SavedState.Get_PlayRate());
            TestEqual(TEXT("BlendInTime round-tripped"),
                RestoredState.Get_BlendInTime().Get_Seconds(), SavedState.Get_BlendInTime().Get_Seconds());
            TestEqual(TEXT("BlendOutTime round-tripped"),
                RestoredState.Get_BlendOutTime().Get_Seconds(), SavedState.Get_BlendOutTime().Get_Seconds());
            TestEqual(TEXT("ServerStartTime round-tripped"),
                RestoredState.Get_ServerStartTime().Get_Seconds(), SavedState.Get_ServerStartTime().Get_Seconds());
            TestEqual(TEXT("PlayInstanceId round-tripped"),
                RestoredState.Get_PlayInstanceId(), SavedState.Get_PlayInstanceId());
            TestTrue(TEXT("Kind round-tripped (Pause, not the Play default)"),
                RestoredState.Get_Kind() == ECk_MontagePlayer_StateKind::Pause);
            TestTrue(TEXT("Montage restored null from an empty soft path"),
                RestoredState.Get_Montage() == nullptr);
        }

        TestEqual(TEXT("Exactly one entity carries FFragment_MontagePlayer_Current post-restore"),
            CurrentCount, 1);
    }

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
