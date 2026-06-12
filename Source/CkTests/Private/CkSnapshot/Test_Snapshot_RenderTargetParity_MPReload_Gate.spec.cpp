// CkSnapshot RenderTarget-Parity GATE — a replicated RenderTarget's drawn instruction state survives a
// listen-server SEAMLESS ServerTravel reload, asserted on BOTH worlds. The server draws one 2-cmd batch
// (line + box) on a Replicates / InstructionsOnly target pre-save; post-reload both worlds must report the
// same latest-applied batch seq (1, NOT the Construct-default 0) — proving:
//   - the restored server re-derived the runtime fragments + drawable target and restored the author seq
//     watermark from the snapshotted FFragment_RenderTarget_AuthoredLog (the published instruction ring —
//     the owner-hosted FCk_RepData_RenderTarget container lives in the replication driver's FastArray, which
//     the snapshot can never capture),
//   - the restored server re-created the owner-hosted instruction container and re-published the restored
//     ring (FProcessor_RenderTarget_ReplicateOnRestore), so the fresh post-travel client reconverges through
//     the ordinary ApplyReplicatedBatches path.
// Asserts seq parity, not just existence.
// Surface in Session Frontend: Ck.Snapshot.Parity.RenderTarget_MPReload (IMPLEMENT_SIMPLE_AUTOMATION_TEST below).

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Engine/GameInstance.h"
#include "EngineUtils.h"               // TActorIterator
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel
#include "GameplayTagContainer.h"      // FGameplayTag::RequestGameplayTag

#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/OwningActor/CkOwningActor_Utils.h"

#include "CkRenderTarget/RenderTarget/CkRenderTarget_Fragment.h"   // ck::FFragment_RenderTarget_Current (resolved-guard)
#include "CkRenderTarget/RenderTarget/CkRenderTarget_Utils.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "CkTests/Net/CkAutoTest_NetSubject.h"
#include "CkTests/Net/CkAutoTest_NetSubject_RenderTarget.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

namespace
{
    constexpr auto RtParity_MapPath      = TEXT("/Engine/Maps/Entry");
    const auto     RtParity_SlotName     = FName{TEXT("CkSnapshot_RTParity_GateSlot")};
    constexpr auto RtParity_SyncTagName  = TEXT("RenderTarget.AutoTest.Net");   // entity-script's _SyncName
    constexpr auto RtParity_ExpectedSeq  = int32{1};                            // one drawn batch -> seq 1

    static TWeakObjectPtr<UWorld> GRtParity_PreServerWorld;
    static TWeakObjectPtr<UWorld> GRtParity_PreClientWorld;

    auto RtParity_MapNameOf(UWorld* InWorld) -> FString
    {
        return InWorld != nullptr ? InWorld->RemovePIEPrefix(InWorld->GetOutermost()->GetName()) : FString{};
    }

    auto RtParity_Subsystem(UWorld* InWorld) -> UCk_Snapshot_Subsystem_UE*
    {
        if (InWorld == nullptr || InWorld->GetGameInstance() == nullptr) { return nullptr; }
        return InWorld->GetGameInstance()->GetSubsystem<UCk_Snapshot_Subsystem_UE>();
    }

    auto RtParity_FindProbe(UWorld* InWorld) -> ACk_AutoTest_NetSubject_RenderTarget_UE*
    {
        if (InWorld == nullptr) { return nullptr; }
        for (auto It = TActorIterator<ACk_AutoTest_NetSubject_RenderTarget_UE>(InWorld); It; ++It) { return *It; }
        return nullptr;
    }

    // Resolved through the owner's RenderTarget RECORD (TryGet_RenderTarget by sync name), NOT the actor's
    // transient _TestRenderTarget field — that field is populated by Construct, which is ABSTAINED on the
    // restored server world.
    auto RtParity_ResolveRenderTarget(UWorld* InWorld) -> FCk_Handle_RenderTarget
    {
        auto* Probe = RtParity_FindProbe(InWorld);
        if (Probe == nullptr) { return {}; }

        auto OwnerEntity = UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(Probe);
        if (ck::Is_NOT_Valid(OwnerEntity)) { return {}; }

        const auto SyncName = FGameplayTag::RequestGameplayTag(FName{RtParity_SyncTagName});
        return UCk_Utils_RenderTarget_UE::TryGet_RenderTarget(OwnerEntity, SyncName);
    }

    // True when the world's RenderTarget is resolved, has had its runtime state re-derived (a restored
    // target whose FFragment_RenderTarget_Current has not yet been re-added must read as "not converged",
    // not ensure), and reports the expected latest-applied batch seq.
    auto RtParity_SeqMatches(UWorld* InWorld) -> bool
    {
        auto RenderTarget = RtParity_ResolveRenderTarget(InWorld);
        if (ck::Is_NOT_Valid(RenderTarget)) { return false; }

        if (NOT FCk_Handle{RenderTarget}.Has<ck::FFragment_RenderTarget_Current>()) { return false; }

        return UCk_Utils_RenderTarget_UE::Get_LatestAppliedBatchSeq(RenderTarget) == RtParity_ExpectedSeq;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_RenderTargetParity_MPReload_Gate,
    "Ck.Snapshot.Parity.RenderTarget_MPReload",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_RenderTargetParity_MPReload_Gate::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;        // server window + 1 connected client
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesPerSettle = 30;
    constexpr auto ReloadTimeoutSeconds = 60.0f;
    constexpr auto FramesPostReconnect = 60;

    GRtParity_PreServerWorld = nullptr;
    GRtParity_PreClientWorld = nullptr;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, FString{RtParity_MapPath}));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // Stage 1 — open the PIE seamless gate + spawn the replicated RenderTarget subject on the server.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
            { CVar->Set(1, ECVF_SetByCode); }

            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
            auto* Probe = InServer->SpawnActor<ACk_AutoTest_NetSubject_RenderTarget_UE>(
                ACk_AutoTest_NetSubject_RenderTarget_UE::StaticClass(), FTransform{FVector{100.0, 200.0, 300.0}}, SpawnInfo);
            if (Probe == nullptr) { AddError(TEXT("Stage 1: RenderTarget subject spawn returned null")); }
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 2 — pre-reload sanity: the RenderTarget resolves on BOTH worlds (symmetric Construct ran).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Server == nullptr || Client == nullptr) { return false; }
            return ck::IsValid(RtParity_ResolveRenderTarget(Server)) &&
                   ck::IsValid(RtParity_ResolveRenderTarget(Client));
        }),
        ReadyTimeoutSeconds));

    // Stage 3 — server draws one 2-cmd batch (line + box) in a single frame -> batch seq 1.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto RenderTarget = RtParity_ResolveRenderTarget(InServer);
            if (ck::Is_NOT_Valid(RenderTarget)) { AddError(TEXT("Stage 3: server RenderTarget unresolved")); return; }

            UCk_Utils_RenderTarget_UE::Request_DrawLine(RenderTarget,
                FCk_Request_RenderTarget_DrawLine{FVector2D{0.0, 0.0}, FVector2D{32.0, 32.0}});
            UCk_Utils_RenderTarget_UE::Request_DrawBox(RenderTarget,
                FCk_Request_RenderTarget_DrawBox{FVector2D{8.0, 8.0}, FVector2D{16.0, 16.0}});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 3b — pre-save parity on BOTH worlds (the live path must already deliver the batch to the
    // client — otherwise the post-reload assert wouldn't isolate the restore path).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            return RtParity_SeqMatches(ck::auto_test::net::Get_ServerWorld())
                && RtParity_SeqMatches(ck::auto_test::net::Get_ClientWorld(0));
        }),
        ReadyTimeoutSeconds));

    // Stage 4 — Save on the server; stash pre-travel worlds.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            GRtParity_PreServerWorld = InServer;
            GRtParity_PreClientWorld = ck::auto_test::net::Get_ClientWorld(0);
            auto* Sub = RtParity_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 4: no snapshot subsystem")); return; }
            Sub->Request_Save(RtParity_SlotName, FCk_Delegate_OnSaveComplete{});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 5 — fire async Load (triggers seamless ServerTravel) + assert non-blocking.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Sub = RtParity_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 5: no snapshot subsystem")); return; }
            Sub->Request_Load(RtParity_SlotName, FCk_Delegate_OnLoadComplete{});
            TestTrue(TEXT("Stage 5: Request_Load non-blocking"), Sub->Get_IsLoadInProgress());
        })));

    // Stage 6 — poll until server finished load AND client rode the travel AND the seq CONVERGED on the
    // client (re-publish on the server, ordinary SyncReplication to the client).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            if (Server == nullptr || Server == GRtParity_PreServerWorld.Get() || !Server->HasBegunPlay()) { return false; }
            if (RtParity_MapNameOf(Server) != RtParity_MapPath) { return false; }
            auto* Sub = RtParity_Subsystem(Server);
            if (Sub == nullptr || Sub->Get_IsLoadInProgress()) { return false; }
            if (RtParity_FindProbe(Server) == nullptr) { return false; }

            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr || Client == GRtParity_PreClientWorld.Get() || !Client->HasBegunPlay()) { return false; }
            if (RtParity_MapNameOf(Client) != RtParity_MapPath) { return false; }

            return RtParity_SeqMatches(Client);
        }),
        ReloadTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPostReconnect));

    // Stage 7 — parity assertions on BOTH worlds: the drawn batch seq survived (NOT a Construct-default
    // seq 0 target).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            TestTrue(TEXT("server: RenderTarget at batch seq 1 post-reload (target re-derived + ring restored)"),
                RtParity_SeqMatches(Server));

            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr) { AddError(TEXT("Stage 7: no post-travel client world")); return false; }
            TestTrue(TEXT("client: RenderTarget at batch seq 1 post-reload (ring re-published + replicated)"),
                RtParity_SeqMatches(Client));
            return true;
        }),
        TEXT("RenderTarget parity: drawn instruction seq survives save -> seamless reload -> client convergence")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
