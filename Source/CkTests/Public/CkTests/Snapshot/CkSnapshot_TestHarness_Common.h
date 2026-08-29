#pragma once

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkEcs/Handle/CkHandle.h"

class UWorld;
class UCk_Snapshot_Subsystem_UE;
class UCk_EntityScript_UE;

// --------------------------------------------------------------------------------------------------------------------
//
// Save->load->assert round-trip harness for CkSnapshot AutoTests. A CKTESTS_API composition layer over the
// existing CkNetAutomation latent-command primitives (CkNetAutomation_Common.h) — NOT a new test framework and
// NOT a DEFINE_SPEC. ~21 snapshot tests hand-roll the identical StartPIE->spawn->mutate->save->load->wait->assert
// skeleton; this factors it so a round-trip test is a data-only FCk_SnapshotRoundTrip_Spec plus a handful of
// per-test stage lambdas.
//
// Usage (inside a standard IMPLEMENT_SIMPLE_AUTOMATION_TEST RunTest body):
//
//   auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
//   Spec.SlotName = FName{TEXT("MyTest_Slot")};
//   Spec.Spawn    = FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void { /* spawn subject */ });
//   Spec.Assert   = FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool { /* final checks */ return true; });
//   ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
//   return true;
//
// --------------------------------------------------------------------------------------------------------------------

namespace ck::auto_test::snapshot
{
    // One save->load->assert round-trip. All ServerAction/Assertion lambdas run on the (post-travel) server
    // world via the CkNetAutomation latent commands. Assert re-runs after EVERY cycle (two-cycle rule,
    // CkSnapshot/Claude.md section 5 — cycle 2 catches double-apply stacking).
    struct CKTESTS_API FCk_SnapshotRoundTrip_Spec
    {
        int32   NumPIEClients = 2;                        // 2 = listen-server window + 1 client
        FString MapPath = TEXT("/Engine/Maps/Entry");
        FName   SlotName;                                 // REQUIRED, unique per test
        float   ReloadTimeoutSeconds = 60.0f;
        int32   SettleFrames = 60;
        int32   NumCycles = 2;
        // false = save ONCE, before the first load, then load the same slot every cycle. That is a different
        // question from the default: repeated loads of one save must be identical to each other, whereas
        // save->load->save->load also asks whether a load leaves a world that captures the same way.
        bool    SaveEveryCycle = true;

        FCk_NetAutoTest_ServerAction Spawn;               // REQUIRED: spawn/compose the subject
        FCk_NetAutoTest_Assertion    SubjectReady;        // optional poll gate before Mutate (unset = skip)
        FCk_NetAutoTest_ServerAction Mutate;              // optional: drive to a non-default state
        // optional: runs on the server AFTER the save is written and BEFORE the load is issued, every cycle.
        // The window a test needs when the thing under test is what happens to state the save recorded but the
        // loading world can no longer reach - an asset renamed away, a runtime-minted object that a fresh
        // process would not have. Mutate cannot express that: it runs pre-save, so the save would record the
        // broken state rather than a good state that later becomes unreachable.
        FCk_NetAutoTest_ServerAction PostSave;
        FCk_NetAutoTest_Assertion    ReloadSettled;       // optional extra predicate ANDed onto the default
                                                          // (server world changed + on-map + HasBegunPlay + NOT IsLoadInProgress)
        FCk_NetAutoTest_Assertion    Assert;              // REQUIRED: final assertions
    };

    // Enqueues the full latent chain (StartPIE ... EndPIE). Call from RunTest, then return true.
    CKTESTS_API auto EnqueueRoundTrip(FAutomationTestBase* InTest, FCk_SnapshotRoundTrip_Spec InSpec) -> void;

    // Shared helpers (extracted from the ~21 per-file anon-namespace copies):
    CKTESTS_API auto Get_SnapshotSubsystem(UWorld* InWorld) -> UCk_Snapshot_Subsystem_UE*;
    CKTESTS_API auto Get_PostTravelServerWorld() -> UWorld*;
    CKTESTS_API auto ResolveEntityBySpawnRecipe(UWorld* InWorld, UClass* InScriptClass) -> FCk_Handle;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
