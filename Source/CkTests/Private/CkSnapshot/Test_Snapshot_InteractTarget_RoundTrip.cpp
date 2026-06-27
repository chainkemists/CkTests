// Registry-level round-trip for the InteractTarget config. Proves FFragment_InteractTarget_Params (the interaction
// channel / completion-policy / duration / concurrency) survives capture -> wipe -> restore. Previously these were
// dropped (the feature had no snapshotable registration and an empty Setup), so on a load the SM condition
// UBb_SmCondition_InteractedWith found its host was no longer an InteractTarget and ENSURED on As_InteractTarget().
// Hardening this fragment is what makes a restored interactable still BE an InteractTarget.
//
// Uses _InteractionDuration (an FCk_Time) as the distinctive field — same SerializeItem pass as the channel, but no
// GameplayTag registration needed in the test harness. FFragment_InteractTarget_Current registers too; the zero-skip
// assertion covers that it took.

#include "CkSnapshot/Snapshot/CkSnapshot_Capture.h"
#include "CkSnapshot/Snapshot/CkSnapshot_Restore.h"
#include "CkSnapshot/SaveGame/CkSnapshot_Header.h"
#include "CkSnapshot/Snapshot/CkSnapshot_LoadReport.h"

#include "CkInteraction/InteractTarget/CkInteractTarget_Fragment.h"
#include "CkInteraction/InteractTarget/CkInteractTarget_Fragment_Data.h"

#include "CkCore/Time/CkTime.h"

#include "CkEcs/World/CkEcsWorld.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"

#include "CkCore/Macros/CkMacros.h"

#include "Serialization/BufferArchive.h"
#include "Serialization/MemoryReader.h"

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_InteractTarget_RoundTrip_Test,
    "Ck.Snapshot.InteractTarget.RoundTrip",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_InteractTarget_RoundTrip_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    constexpr auto DurationSeconds = 7.5;
    constexpr auto Tolerance       = 0.001;

    // ---- Arrange ------------------------------------------------------------------------------------------------
    auto EcsWorld = ck::FEcsWorld{};

    auto* RawRegistry = ck::registry_table::TryResolve(EcsWorld.Get_Registry().Get_RegistryHandle());
    if (NOT TestNotNull(TEXT("Resolved raw entt registry from FEcsWorld"), RawRegistry))
    { return false; }

    auto TargetEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(EcsWorld.Get_Registry());
    if (NOT TestTrue(TEXT("InteractTarget entity is valid"), ck::IsValid(TargetEntity)))
    { return false; }

    auto ParamsData = FCk_Fragment_InteractTarget_ParamsData{};
    ParamsData.Set_InteractionDuration(FCk_Time{DurationSeconds});

    TargetEntity.Add<ck::FFragment_InteractTarget_Params>(ParamsData);
    TargetEntity.Add<ck::FFragment_InteractTarget_Current>(); // default _Enabled = Enable; registers + survives

    if (NOT TestTrue(TEXT("Pre-capture: live interaction duration == 7.5s"),
            FMath::IsNearlyEqual(
                TargetEntity.Get<ck::FFragment_InteractTarget_Params>().Get_Params().Get_InteractionDuration().Get_Seconds(),
                DurationSeconds, Tolerance)))
    { return false; }

    // ---- Act ----------------------------------------------------------------------------------------------------
    auto Buffer = FBufferArchive{};
    auto Header = FCk_Snapshot_Header{};

    if (NOT TestEqual(TEXT("Capture result is Success"),
            static_cast<uint8>(ck::snapshot::Run_Capture_Registry(*RawRegistry, Buffer, Header)),
            static_cast<uint8>(ECk_SnapshotResult::Success)))
    { return false; }

    auto Reader = FMemoryReader{Buffer, /*bIsPersistent=*/true};
    const auto Report = ck::snapshot::Run_Restore_Registry(*RawRegistry, Reader, Header);

    TestEqual(TEXT("Restore result is Success"),
        static_cast<uint8>(Report.Get_Result()), static_cast<uint8>(ECk_SnapshotResult::Success));
    // Catches a forgotten/failed registration for EITHER InteractTarget fragment.
    TestEqual(TEXT("No fragment types were skipped"), Report.Get_SkippedFragmentTypes().Num(), 0);

    // ---- Assert -------------------------------------------------------------------------------------------------
    auto FoundCount = 0;
    for (const auto Entity : RawRegistry->view<ck::FFragment_InteractTarget_Params>())
    {
        ++FoundCount;
        const auto& RestoredParams = RawRegistry->get<ck::FFragment_InteractTarget_Params>(Entity).Get_Params();

        TestTrue(TEXT("Restored interaction duration == 7.5s (Params fragment round-tripped; host is still an InteractTarget)"),
            FMath::IsNearlyEqual(RestoredParams.Get_InteractionDuration().Get_Seconds(), DurationSeconds, Tolerance));
    }

    TestEqual(TEXT("Exactly one entity carries the InteractTarget_Params fragment after restore"), FoundCount, 1);

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
