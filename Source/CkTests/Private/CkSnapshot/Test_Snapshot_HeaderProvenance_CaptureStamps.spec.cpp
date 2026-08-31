// Capture actually WRITES the build provenance into the save.
//
// The two byte-level specs beside FCk_Snapshot_HeaderV3 prove the serializer round-trips a stamp that is already
// set, and that an unstamped save stays loadable. Neither touches the capture path - delete the Set_ calls in
// Run_CaptureV3_Registry and both stay green. That is exactly how _PluginBuildHash died: declared, read back,
// exposed to Blueprint, and written by nobody, so every save ever produced carried a zero GUID and no test noticed.
// This gate closes that half: a REAL save->load must land a non-empty version and build id on the load report.
// Surface in Session Frontend: Ck.Snapshot.HeaderProvenance.CaptureStampsTheWritingBuild

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel

#include "CkCore/BuildId/CkBuildId.h"  // ck::Get_BuildId - what capture is expected to have stamped
#include "CkCore/IO/CkIO_Utils.h"      // Get_ProjectVersion - likewise

#include "CkEcs/EntityScript/CkEntityScript_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkTests/Snapshot/CkAutoTest_Snapshot_Ordering.h"
#include "CkTests/Snapshot/CkSnapshot_TestHarness_Common.h"

namespace ck_test_snapshot_header_provenance
{
    const auto SlotName = FName{TEXT("CkSnapshot_HeaderProvenance_CaptureStamps_GateSlot")};
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_HeaderProvenance_CaptureStampsTheWritingBuild_Gate,
    "Ck.Snapshot.HeaderProvenance.CaptureStampsTheWritingBuild",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_HeaderProvenance_CaptureStampsTheWritingBuild_Gate::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_snapshot_header_provenance;

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = SlotName;

    // Any persisted subject will do - the assertions are about the save's HEADER, not its contents. Reusing the
    // ordering probe keeps this gate from owning an entity script whose only purpose is to exist.
    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    {
        if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
        { CVar->Set(1, ECVF_SetByCode); }

        auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
        UCk_Utils_EntityScript_UE::Request_SpawnEntity(
            Transient, UCk_AutoTest_Snapshot_OrderingProbe_EntityScript_UE::StaticClass(), FInstancedStruct{}, {});
    });

    Spec.Assert = FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
    {
        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
        if (NOT TestTrue(TEXT("post-load server world resolves"), Server != nullptr))
        { return false; }

        auto* Subsystem = ck::auto_test::snapshot::Get_SnapshotSubsystem(Server);
        if (NOT TestTrue(TEXT("the snapshot subsystem resolves"), Subsystem != nullptr))
        { return false; }

        const auto Report = Subsystem->Get_LastLoadReport();

        // The report copies these verbatim from the header the load read off disk, so a non-empty value here can
        // only have come from capture having written one. Empty is the pre-stamp / unstamped reading, and is the
        // exact state a silently-missing capture stamp would produce.
        auto AllGood = TestFalse(TEXT("the load report carries a project version (capture stamped one)"),
            Report.Get_ProjectVersion().IsEmpty());

        AllGood &= TestFalse(TEXT("the load report carries a build id (capture stamped one)"),
            Report.Get_BuildId().IsEmpty());

        // Stronger than non-empty: it must be THIS build's provenance, not a stale value carried from somewhere
        // else. The save was written by the process running this test, so both must match it exactly.
        AllGood &= TestEqual(TEXT("the stamped version is this build's ProjectVersion"),
            Report.Get_ProjectVersion(), UCk_Utils_IO_UE::Get_ProjectVersion());

        AllGood &= TestEqual(TEXT("the stamped build id is this build's baked git hash"),
            Report.Get_BuildId(), ck::Get_BuildId());

        return AllGood;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
