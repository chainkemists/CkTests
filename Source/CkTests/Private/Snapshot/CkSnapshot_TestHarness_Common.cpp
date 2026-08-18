#include "CkTests/Snapshot/CkSnapshot_TestHarness_Common.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Misc/AutomationTest.h"

#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Engine/GameInstance.h"

#include "CkEcs/Handle/CkHandle_Utils.h"                   // ck::MakeHandle
#include "CkEcs/Registry/CkRegistry.h"                     // FCk_Registry (Get_RegistryHandle completeness)
#include "CkEcs/Registry/CkRegistry_SlotTable.h"           // ck::registry_table::TryResolve
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"
#include "CkEcs/EntityScript/CkEntityScript_SpawnRecipe.h" // ck::FFragment_SpawnRecipe

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"     // Request_Save/Load + FCk_Delegate_OnSave/LoadComplete

#include "CkTests/Net/CkNetAutomation_Common.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck::auto_test::snapshot
{
    auto
        Get_SnapshotSubsystem(
            UWorld* InWorld)
        -> UCk_Snapshot_Subsystem_UE*
    {
        if (InWorld == nullptr || InWorld->GetGameInstance() == nullptr)
        { return nullptr; }
        return InWorld->GetGameInstance()->GetSubsystem<UCk_Snapshot_Subsystem_UE>();
    }

    // ----------------------------------------------------------------------------------------------------------------

    auto
        Get_PostTravelServerWorld()
        -> UWorld*
    {
        // Seamless-travel listen/dedicated server: the net harness's server accessor is authoritative and
        // survives the ServerTravel (netmode preserved).
        if (auto* Server = ck::auto_test::net::Get_ServerWorld())
        { return Server; }

        // Fallback for single-world OpenLevel travel, which demotes the world to NM_Standalone so
        // Get_ServerWorld() returns null. Enumerate PIE worlds netmode-agnostically and return the one that
        // HasBegunPlay. Mirrors Test_Snapshot_M2b_LevelReload_Gate.spec.cpp:39-52.
        if (GEngine == nullptr)
        { return nullptr; }

        auto* Best = static_cast<UWorld*>(nullptr);
        for (const auto& Context : GEngine->GetWorldContexts())
        {
            if (Context.WorldType != EWorldType::PIE)
            { continue; }

            auto* World = Context.World();
            if (World == nullptr)
            { continue; }

            if (World->HasBegunPlay())
            { Best = World; }
        }
        return Best;
    }

    // ----------------------------------------------------------------------------------------------------------------

    auto
        ResolveEntityBySpawnRecipe(
            UWorld* InWorld,
            UClass* InScriptClass)
        -> FCk_Handle
    {
        if (InWorld == nullptr || InScriptClass == nullptr)
        { return {}; }

        auto* Ecs = InWorld->GetSubsystem<UCk_EcsWorld_Subsystem_UE>();
        if (ck::Is_NOT_Valid(Ecs))
        { return {}; }

        auto& CkRegistry = Ecs->Get_Registry();
        auto* Raw = ck::registry_table::TryResolve(CkRegistry.Get_RegistryHandle());
        if (Raw == nullptr)
        { return {}; }

        // Every RuntimeSpawned entity retains its FFragment_SpawnRecipe; resolve by the recipe's script class.
        // Handle-independent across a reload (the restored entity is fresh). Mirrors M2b2a / TransformParity.
        for (const auto Entity : Raw->view<ck::FFragment_SpawnRecipe>())
        {
            auto Handle = ck::MakeHandle(FCk_Entity{Entity}, CkRegistry);
            if (ck::Is_NOT_Valid(Handle))
            { continue; }
            if (Handle.Get<ck::FFragment_SpawnRecipe>().Get_ScriptClass().Get() == InScriptClass)
            { return Handle; }
        }
        return {};
    }

    // ----------------------------------------------------------------------------------------------------------------

    auto
        EnqueueRoundTrip(
            FAutomationTestBase* InTest,
            FCk_SnapshotRoundTrip_Spec InSpec)
        -> void
    {
        // Mutable state shared across the whole latent-command chain — each ADD_LATENT_AUTOMATION_COMMAND is a
        // separate heap object, so cross-stage state (the pre-reload server world) rides a shared_ptr captured by
        // every stage lambda. Freed when the last latent command destructs (test end).
        struct FRoundTripState
        {
            TWeakObjectPtr<UWorld> PreReloadServerWorld;
        };
        const auto State = MakeShared<FRoundTripState>();

        constexpr auto ReadyTimeoutSeconds = 30.0f;

        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(InSpec.NumPIEClients, InSpec.MapPath));
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(InSpec.NumPIEClients, ReadyTimeoutSeconds));

        // Spawn / compose the subject on the server.
        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(InSpec.Spawn));

        if (InSpec.SubjectReady.IsBound())
        { ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(InSpec.SubjectReady, ReadyTimeoutSeconds)); }

        if (InSpec.Mutate.IsBound())
        { ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(InSpec.Mutate)); }

        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(InSpec.SettleFrames));

        const auto SaveEveryCycle       = InSpec.SaveEveryCycle;
        const auto SlotName             = InSpec.SlotName;
        const auto MapPath              = InSpec.MapPath;
        const auto SettleFrames         = InSpec.SettleFrames;
        const auto ReloadTimeoutSeconds = InSpec.ReloadTimeoutSeconds;
        const auto ReloadSettled        = InSpec.ReloadSettled;
        const auto Assert               = InSpec.Assert;

        for (auto Cycle = 0; Cycle < InSpec.NumCycles; ++Cycle)
        {
            const auto CycleNum = Cycle + 1;

            // The pre-reload server world is stashed on EVERY cycle — the reload predicate's "world changed" check
            // needs it whether or not this cycle saved.
            if (NOT SaveEveryCycle && Cycle > 0)
            {
                ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(InTest,
                    FCk_NetAutoTest_Assertion::CreateLambda([InTest, State]() -> bool
                    {
                        auto* Server = Get_PostTravelServerWorld();
                        if (Server == nullptr)
                        { InTest->AddError(TEXT("SnapshotRoundTrip: no server world before Load")); return true; }

                        State->PreReloadServerWorld = Server;
                        return true;
                    }),
                    TEXT("SnapshotRoundTrip: reload baseline stashed (no save this cycle)")));
            }

            // Save on the server; stash the pre-reload server world for the reload predicate's "world changed" check.
            // NOT FCk_Latent_RunOnServer: a single-world OpenLevel load demotes the world to NM_Standalone, so from
            // cycle 2 on it finds no server and DROPS its action — save and load never fire while Assert still
            // re-runs against the prior cycle's world, reporting two identical passes for one cycle of work.
            if (SaveEveryCycle || Cycle == 0)
            {
                ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(InTest,
                    FCk_NetAutoTest_Assertion::CreateLambda([InTest, State, SlotName]() -> bool
                    {
                        auto* Server = Get_PostTravelServerWorld();
                        if (Server == nullptr)
                        { InTest->AddError(TEXT("SnapshotRoundTrip: no server world at Save")); return true; }

                        State->PreReloadServerWorld = Server;
                        auto* Sub = Get_SnapshotSubsystem(Server);
                        if (Sub == nullptr)
                        { InTest->AddError(TEXT("SnapshotRoundTrip: no snapshot subsystem at Save")); return true; }
                        Sub->Request_Save(SlotName, FCk_Delegate_OnSaveComplete{});
                        return true;
                    }),
                    TEXT("SnapshotRoundTrip: save issued")));
                ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(SettleFrames));
            }

            // Fire async Load; assert non-blocking (completion is inferred by the wait predicate — house convention,
            // empty delegate).
            ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(InTest,
                FCk_NetAutoTest_Assertion::CreateLambda([InTest, SlotName]() -> bool
                {
                    auto* Server = Get_PostTravelServerWorld();
                    if (Server == nullptr)
                    { InTest->AddError(TEXT("SnapshotRoundTrip: no server world at Load")); return true; }

                    auto* Sub = Get_SnapshotSubsystem(Server);
                    if (Sub == nullptr)
                    { InTest->AddError(TEXT("SnapshotRoundTrip: no snapshot subsystem at Load")); return true; }
                    Sub->Request_Load(SlotName, FCk_Delegate_OnLoadComplete{});
                    InTest->TestTrue(TEXT("SnapshotRoundTrip: Request_Load non-blocking (load in progress)"),
                        Sub->Get_IsLoadInProgress());
                    return true;
                }),
                TEXT("SnapshotRoundTrip: load issued")));

            // Wait until the reload settled: server world changed + begun play + back on the target map + load flag
            // cleared, ANDed with the optional per-test ReloadSettled predicate. Mirrors the proven Timer/Transform
            // parity reload predicate.
            ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
                FCk_NetAutoTest_Assertion::CreateLambda([State, MapPath, ReloadSettled]() -> bool
                {
                    auto* Server = Get_PostTravelServerWorld();
                    if (Server == nullptr || Server == State->PreReloadServerWorld.Get() || NOT Server->HasBegunPlay())
                    { return false; }
                    if (Server->RemovePIEPrefix(Server->GetOutermost()->GetName()) != MapPath)
                    { return false; }
                    auto* Sub = Get_SnapshotSubsystem(Server);
                    if (Sub == nullptr || Sub->Get_IsLoadInProgress())
                    { return false; }
                    if (ReloadSettled.IsBound() && NOT ReloadSettled.Execute())
                    { return false; }
                    return true;
                }),
                ReloadTimeoutSeconds));
            ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(SettleFrames));

            // Final assertions for this cycle (two-cycle rule: cycle 2 catches double-apply stacking).
            ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(InTest, Assert,
                FString::Printf(TEXT("SnapshotRoundTrip cycle %d assert"), CycleNum)));
        }

        ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    }
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
