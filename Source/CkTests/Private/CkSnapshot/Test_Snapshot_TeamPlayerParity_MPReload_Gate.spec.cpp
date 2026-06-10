// CkSnapshot Team/Player-Parity GATE — strict value round-trip of replicated Team + Player IDs through a
// listen-server SEAMLESS ServerTravel reload, asserted on the CLIENT. The server assigns both IDs away from the
// entity-script Construct default (Unassigned) before save; the client must show the assignments post-reload —
// proving the values survived save -> restore -> replication, not just Construct re-derivation. Team/Player are
// the inline-push shape (Assign calls TryUpdateContainerFragment directly — no trigger tag, no Replicate
// processor), so post-restore the SEEDED container entry is the only push; this gate proves that seed reaches
// the client. It also exercises the per-ID FTag_TeamID<>/FTag_PlayerID<> re-derivation: Get_ID reads those tags
// (not the value fragment) and would trip an ensure server-side if restore left them missing.
// Surface in Session Frontend: Ck.Snapshot.Parity.TeamPlayer_MPReload

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Engine/GameInstance.h"
#include "EngineUtils.h"               // TActorIterator
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel

#include "CkRelationship/Team/CkTeam_Utils.h"
#include "CkRelationship/Player/CkPlayer_Utils.h"

#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/OwningActor/CkOwningActor_Utils.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "CkTests/Net/CkAutoTest_NetSubject_M2bProbe_Replicated.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

namespace
{
    constexpr auto TeamPlayerParity_MapPath        = TEXT("/Engine/Maps/Entry");
    const auto     TeamPlayerParity_SlotName       = FName{TEXT("CkSnapshot_TeamPlayerParity_GateSlot")};
    constexpr auto TeamPlayerParity_TeamOverride   = ECk_Team_ID::Three;     // != Construct default Unassigned
    constexpr auto TeamPlayerParity_PlayerOverride = ECk_Player_ID::Two;     // != Construct default Unassigned

    static TWeakObjectPtr<UWorld> GTeamPlayerParity_PreServerWorld;
    static TWeakObjectPtr<UWorld> GTeamPlayerParity_PreClientWorld;

    auto TeamPlayerParity_MapNameOf(UWorld* InWorld) -> FString
    {
        return InWorld != nullptr ? InWorld->RemovePIEPrefix(InWorld->GetOutermost()->GetName()) : FString{};
    }

    auto TeamPlayerParity_Subsystem(UWorld* InWorld) -> UCk_Snapshot_Subsystem_UE*
    {
        if (InWorld == nullptr || InWorld->GetGameInstance() == nullptr) { return nullptr; }
        return InWorld->GetGameInstance()->GetSubsystem<UCk_Snapshot_Subsystem_UE>();
    }

    auto TeamPlayerParity_FindProbe(UWorld* InWorld) -> ACk_AutoTest_NetSubject_M2bProbe_Replicated*
    {
        if (InWorld == nullptr) { return nullptr; }
        for (auto It = TActorIterator<ACk_AutoTest_NetSubject_M2bProbe_Replicated>(InWorld); It; ++It) { return *It; }
        return nullptr;
    }

    auto TeamPlayerParity_ResolveEntity(AActor* InProbe) -> FCk_Handle
    {
        if (InProbe == nullptr) { return {}; }
        return UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(InProbe);
    }

    auto TeamPlayerParity_CurrentTeam(AActor* InProbe, bool& OutResolved) -> ECk_Team_ID
    {
        OutResolved = false;
        auto Entity = TeamPlayerParity_ResolveEntity(InProbe);
        if (ck::Is_NOT_Valid(Entity)) { return ECk_Team_ID::Unassigned; }
        if (NOT UCk_Utils_Team_UE::Has(Entity)) { return ECk_Team_ID::Unassigned; }
        OutResolved = true;
        return UCk_Utils_Team_UE::Get_ID(UCk_Utils_Team_UE::Cast(Entity));
    }

    auto TeamPlayerParity_CurrentPlayer(AActor* InProbe, bool& OutResolved) -> ECk_Player_ID
    {
        OutResolved = false;
        auto Entity = TeamPlayerParity_ResolveEntity(InProbe);
        if (ck::Is_NOT_Valid(Entity)) { return ECk_Player_ID::Unassigned; }
        if (NOT UCk_Utils_Player_UE::Has(Entity)) { return ECk_Player_ID::Unassigned; }
        OutResolved = true;
        return UCk_Utils_Player_UE::Get_ID(UCk_Utils_Player_UE::Cast(Entity));
    }

    auto TeamPlayerParity_BothMatchOverride(AActor* InProbe) -> bool
    {
        auto TeamResolved = false;
        auto PlayerResolved = false;
        const auto Team   = TeamPlayerParity_CurrentTeam(InProbe, TeamResolved);
        const auto Player = TeamPlayerParity_CurrentPlayer(InProbe, PlayerResolved);
        return TeamResolved && PlayerResolved &&
            Team == TeamPlayerParity_TeamOverride && Player == TeamPlayerParity_PlayerOverride;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_TeamPlayerParity_MPReload_Gate,
    "Ck.Snapshot.Parity.TeamPlayer_MPReload",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_TeamPlayerParity_MPReload_Gate::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;        // server window + 1 connected client
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesPerSettle = 30;
    constexpr auto ReloadTimeoutSeconds = 60.0f;
    constexpr auto FramesPostReconnect = 60;

    GTeamPlayerParity_PreServerWorld = nullptr;
    GTeamPlayerParity_PreClientWorld = nullptr;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, FString{TeamPlayerParity_MapPath}));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // Stage 1 — open the PIE seamless gate + spawn the replicated bridged probe on the server.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
            { CVar->Set(1, ECVF_SetByCode); }

            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
            auto* Probe = InServer->SpawnActor<ACk_AutoTest_NetSubject_M2bProbe_Replicated>(
                ACk_AutoTest_NetSubject_M2bProbe_Replicated::StaticClass(), FTransform{FVector{100.0, 200.0, 300.0}}, SpawnInfo);
            if (Probe == nullptr) { AddError(TEXT("Stage 1: replicated probe spawn returned null")); }
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 2 — pre-reload sanity: client has the probe AND both features resolve (Construct ran client-side).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr) { return false; }
            auto* Probe = TeamPlayerParity_FindProbe(Client);
            auto TeamResolved = false;
            auto PlayerResolved = false;
            TeamPlayerParity_CurrentTeam(Probe, TeamResolved);
            TeamPlayerParity_CurrentPlayer(Probe, PlayerResolved);
            return TeamResolved && PlayerResolved;
        }),
        ReadyTimeoutSeconds));

    // Stage 3 — ASSIGN Team + Player on the server (inline container push; settle covers replication).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto Entity = TeamPlayerParity_ResolveEntity(TeamPlayerParity_FindProbe(InServer));
            if (ck::Is_NOT_Valid(Entity)) { AddError(TEXT("Stage 3: server probe entity unresolved")); return; }
            if (NOT UCk_Utils_Team_UE::Has(Entity)) { AddError(TEXT("Stage 3: server Team unresolved")); return; }
            if (NOT UCk_Utils_Player_UE::Has(Entity)) { AddError(TEXT("Stage 3: server Player unresolved")); return; }

            auto TeamHandle = UCk_Utils_Team_UE::Cast(Entity);
            UCk_Utils_Team_UE::Assign(TeamHandle, TeamPlayerParity_TeamOverride);

            auto PlayerHandle = UCk_Utils_Player_UE::Cast(Entity);
            UCk_Utils_Player_UE::Assign(PlayerHandle, TeamPlayerParity_PlayerOverride, ECk_Replication::Replicates);
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 3b — assert the SERVER holds both assignments before saving.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Probe = TeamPlayerParity_FindProbe(InServer);
            auto TeamResolved = false;
            auto PlayerResolved = false;
            const auto Team   = TeamPlayerParity_CurrentTeam(Probe, TeamResolved);
            const auto Player = TeamPlayerParity_CurrentPlayer(Probe, PlayerResolved);
            TestTrue(TEXT("pre-save server: Team resolved"), TeamResolved);
            TestTrue(TEXT("pre-save server: Team == override (Three)"), Team == TeamPlayerParity_TeamOverride);
            TestTrue(TEXT("pre-save server: Player resolved"), PlayerResolved);
            TestTrue(TEXT("pre-save server: Player == override (Two)"), Player == TeamPlayerParity_PlayerOverride);
        })));

    // Stage 4 — Save on the server; stash pre-travel worlds.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            GTeamPlayerParity_PreServerWorld = InServer;
            GTeamPlayerParity_PreClientWorld = ck::auto_test::net::Get_ClientWorld(0);
            auto* Sub = TeamPlayerParity_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 4: no snapshot subsystem")); return; }
            Sub->Request_Save(TeamPlayerParity_SlotName, FCk_Delegate_OnSaveComplete{});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 5 — fire async Load (triggers seamless ServerTravel) + assert non-blocking.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Sub = TeamPlayerParity_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 5: no snapshot subsystem")); return; }
            Sub->Request_Load(TeamPlayerParity_SlotName, FCk_Delegate_OnLoadComplete{});
            TestTrue(TEXT("Stage 5: Request_Load non-blocking"), Sub->Get_IsLoadInProgress());
        })));

    // Stage 6 — poll until server finished load AND client rode the travel AND both IDs CONVERGED on the client.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            if (Server == nullptr || Server == GTeamPlayerParity_PreServerWorld.Get() || !Server->HasBegunPlay()) { return false; }
            if (TeamPlayerParity_MapNameOf(Server) != TeamPlayerParity_MapPath) { return false; }
            auto* Sub = TeamPlayerParity_Subsystem(Server);
            if (Sub == nullptr || Sub->Get_IsLoadInProgress()) { return false; }
            if (TeamPlayerParity_FindProbe(Server) == nullptr) { return false; }

            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr || Client == GTeamPlayerParity_PreClientWorld.Get() || !Client->HasBegunPlay()) { return false; }
            if (TeamPlayerParity_MapNameOf(Client) != TeamPlayerParity_MapPath) { return false; }

            return TeamPlayerParity_BothMatchOverride(TeamPlayerParity_FindProbe(Client));
        }),
        ReloadTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPostReconnect));

    // Stage 7 — parity assertions on BOTH worlds: the assignments survived (NOT the Unassigned Construct default).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            auto* ServerProbe = TeamPlayerParity_FindProbe(Server);
            auto ServerTeamResolved = false;
            auto ServerPlayerResolved = false;
            const auto ServerTeam   = TeamPlayerParity_CurrentTeam(ServerProbe, ServerTeamResolved);
            const auto ServerPlayer = TeamPlayerParity_CurrentPlayer(ServerProbe, ServerPlayerResolved);
            TestTrue(TEXT("server: Team resolved post-reload"), ServerTeamResolved);
            TestTrue(TEXT("server: Team assignment survived the snapshot round-trip (Three)"),
                ServerTeam == TeamPlayerParity_TeamOverride);
            TestTrue(TEXT("server: Player resolved post-reload"), ServerPlayerResolved);
            TestTrue(TEXT("server: Player assignment survived the snapshot round-trip (Two)"),
                ServerPlayer == TeamPlayerParity_PlayerOverride);

            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr) { AddError(TEXT("Stage 7: no post-travel client world")); return false; }

            auto* ClientProbe = TeamPlayerParity_FindProbe(Client);
            auto ClientTeamResolved = false;
            auto ClientPlayerResolved = false;
            const auto ClientTeam   = TeamPlayerParity_CurrentTeam(ClientProbe, ClientTeamResolved);
            const auto ClientPlayer = TeamPlayerParity_CurrentPlayer(ClientProbe, ClientPlayerResolved);
            TestTrue(TEXT("client: Team resolved post-reload"), ClientTeamResolved);
            TestTrue(TEXT("client: Team assignment round-tripped (Three, not default Unassigned)"),
                ClientTeam == TeamPlayerParity_TeamOverride);
            TestTrue(TEXT("client: Player resolved post-reload"), ClientPlayerResolved);
            TestTrue(TEXT("client: Player assignment round-tripped (Two, not default Unassigned)"),
                ClientPlayer == TeamPlayerParity_PlayerOverride);
            return true;
        }),
        TEXT("Team/Player parity: server assignments survive save -> seamless reload -> client re-derivation")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
