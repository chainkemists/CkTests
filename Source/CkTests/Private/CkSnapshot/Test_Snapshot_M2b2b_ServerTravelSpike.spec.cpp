// CkSnapshot M2b-2b SPIKE (seamless) — verify a SEAMLESS ServerTravel carries the PIE client along inside the
// latent automation harness. HARD ServerTravel (iters 1-2) proved unworkable in one-process PIE: with "?listen"
// the server re-listed fine, but the client NEVER reconnected (the engine destroys the net driver and the client
// loses the reliable-ClientTravel-RPC-then-fresh-PendingNetGame reconnect race within ServerTravelPause; a Ck Iris
// DataStreamChannel ensure fires as the send pipeline wedges during teardown). SEAMLESS travel preserves the
// UNetConnection across the world swap (FSeamlessTravelHandler::CopyWorldData moves the net driver), so the client
// should ride along with no reconnect. This spike proves that empirically — the gate for the whole M2b-2b milestone.
// Surface in Session Frontend: Ck.Snapshot.M2b2b.ServerTravelSpike

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Engine/GameInstance.h"
#include "GameFramework/GameModeBase.h"
#include "HAL/IConsoleManager.h"

#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkTests/Net/CkNetAutomation_Common.h"

namespace
{
    // Same map for the reload. File-scope constant so the latent-command lambdas (which run AFTER RunTest returns)
    // can read it WITHOUT capturing a dangling stack local.
    constexpr auto TravelSpike_MapPath = TEXT("/Engine/Maps/Entry");

    // Process-global stash so a later latent command can compare against pre-travel state.
    static TWeakObjectPtr<UWorld>        GTravelSpike_PreServerWorld;
    static TWeakObjectPtr<UWorld>        GTravelSpike_PreClientWorld;
    static TWeakObjectPtr<UGameInstance> GTravelSpike_PreServerGI;

    auto TravelSpike_NetModeName(ENetMode InMode) -> const TCHAR*
    {
        switch (InMode)
        {
            case NM_Standalone:      return TEXT("Standalone");
            case NM_DedicatedServer: return TEXT("DedicatedServer");
            case NM_ListenServer:    return TEXT("ListenServer");
            case NM_Client:          return TEXT("Client");
            default:                 return TEXT("?");
        }
    }

    auto TravelSpike_MapNameOf(UWorld* InWorld) -> FString
    {
        return InWorld != nullptr ? InWorld->RemovePIEPrefix(InWorld->GetOutermost()->GetName()) : FString{};
    }

    // Dump every PIE world for diagnosis (netmode / begunPlay / map / pre-travel identity / has-ecs). The map name
    // distinguishes the destination world from the intermediate seamless TRANSITION map.
    auto TravelSpike_DumpWorlds(const TCHAR* InWhen) -> void
    {
        if (GEngine == nullptr) { return; }
        for (const auto& Context : GEngine->GetWorldContexts())
        {
            if (Context.WorldType != EWorldType::PIE) { continue; }
            auto* World = Context.World();
            if (World == nullptr) { continue; }
            auto* Ecs = World->GetSubsystem<UCk_EcsWorld_Subsystem_UE>();
            UE_LOG(LogTemp, Display,
                TEXT("DIAG TRAVELSPIKE [%s]: world=[%s] map=[%s] netmode=[%s] begunPlay=[%d] isPreServer=[%d] isPreClient=[%d] ecs=[%d]"),
                InWhen, *World->GetName(), *TravelSpike_MapNameOf(World), TravelSpike_NetModeName(World->GetNetMode()),
                World->HasBegunPlay() ? 1 : 0,
                World == GTravelSpike_PreServerWorld.Get() ? 1 : 0,
                World == GTravelSpike_PreClientWorld.Get() ? 1 : 0,
                Ecs != nullptr ? 1 : 0);
        }
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_M2b2b_ServerTravelSpike,
    "Ck.Snapshot.M2b2b.ServerTravelSpike",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_M2b2b_ServerTravelSpike::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;        // server window + 1 client
    constexpr auto ExpectedTotalWorlds = 2;  // server + client
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesPerSettle = 30;
    constexpr auto FramesForTravel = 300;    // seamless travel (transition map -> destination) needs generous frames
    constexpr auto FollowTimeoutSeconds = 30.0f;

    GTravelSpike_PreServerWorld = nullptr;
    GTravelSpike_PreClientWorld = nullptr;
    GTravelSpike_PreServerGI    = nullptr;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, FString{TravelSpike_MapPath}));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 1 — stash pre-travel server + client + GI, ENABLE seamless travel, then issue a SEAMLESS ServerTravel.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            GTravelSpike_PreServerWorld = InServer;
            GTravelSpike_PreServerGI    = InServer->GetGameInstance();
            GTravelSpike_PreClientWorld = ck::auto_test::net::Get_ClientWorld(0);

            const auto MapName = InServer->RemovePIEPrefix(InServer->GetOutermost()->GetName());
            UE_LOG(LogTemp, Display,
                TEXT("DIAG TRAVELSPIKE: pre-travel server=[%s] netmode=[%s] map=[%s] GI=[%s] preClient=[%s]"),
                *InServer->GetName(), TravelSpike_NetModeName(InServer->GetNetMode()), *MapName,
                *GetNameSafe(GTravelSpike_PreServerGI.Get()),
                *GetNameSafe(GTravelSpike_PreClientWorld.Get()));

            TravelSpike_DumpWorlds(TEXT("pre-travel"));

            // PIE force-disables seamless travel unless net.AllowPIESeamlessTravel=1 (ProcessServerTravel honors it).
            if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
            {
                CVar->Set(1, ECVF_SetByCode);
                UE_LOG(LogTemp, Display, TEXT("DIAG TRAVELSPIKE: set net.AllowPIESeamlessTravel=1"));
            }
            else
            {
                UE_LOG(LogTemp, Display, TEXT("DIAG TRAVELSPIKE: net.AllowPIESeamlessTravel CVar NOT FOUND"));
            }

            // Force this travel to be seamless so the engine keeps the UNetConnection and carries the client along.
            if (auto* GameMode = InServer->GetAuthGameMode())
            {
                GameMode->bUseSeamlessTravel = true;
                UE_LOG(LogTemp, Display, TEXT("DIAG TRAVELSPIKE: GameMode=[%s] bUseSeamlessTravel=true"),
                    *GetNameSafe(GameMode));
            }
            else
            {
                UE_LOG(LogTemp, Display, TEXT("DIAG TRAVELSPIKE: GetAuthGameMode() NULL — cannot force seamless"));
            }

            // "?listen" keeps the server a listen server; seamless preserves the client connection across the swap.
            constexpr auto AbsoluteTravel = true;
            InServer->ServerTravel(MapName + TEXT("?listen"), AbsoluteTravel);
        })));

    // Tick across the seamless travel — transition map then destination map; the client rides the kept connection.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesForTravel));

    // Stage 2 — poll until BOTH a fresh server world and a fresh client world are up, begun play, AND on the
    // DESTINATION map (not the transition map). Without the map filter we could match the transition world early.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            auto* NewServer = ck::auto_test::net::Get_ServerWorld();
            auto* NewClient = ck::auto_test::net::Get_ClientWorld(0);
            const auto ServerReady = NewServer != nullptr && NewServer->HasBegunPlay()
                && NewServer != GTravelSpike_PreServerWorld.Get()
                && TravelSpike_MapNameOf(NewServer) == TravelSpike_MapPath;
            const auto ClientReady = NewClient != nullptr && NewClient->HasBegunPlay()
                && NewClient != GTravelSpike_PreClientWorld.Get()
                && TravelSpike_MapNameOf(NewClient) == TravelSpike_MapPath;
            return ServerReady && ClientReady;
        }),
        FollowTimeoutSeconds));

    // Stage 3 — assert the three empirical gates.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            TravelSpike_DumpWorlds(TEXT("post-travel"));

            // (1) Fresh server world, begun play, on the destination map, STILL a ListenServer.
            auto* NewServer = ck::auto_test::net::Get_ServerWorld();
            if (NewServer == nullptr)
            { AddError(TEXT("SPIKE: no post-travel server world (Get_ServerWorld null — see DIAG dump)")); return false; }
            TestTrue(TEXT("SPIKE: server world instance changed (real travel happened)"),
                NewServer != GTravelSpike_PreServerWorld.Get());
            TestTrue(TEXT("SPIKE: post-travel server on the destination map"),
                TravelSpike_MapNameOf(NewServer) == TravelSpike_MapPath);
            TestTrue(TEXT("SPIKE: post-travel server is still NM_ListenServer"),
                NewServer->GetNetMode() == NM_ListenServer);

            // (2) GameInstance survived the travel (CkSnapshot GI-subsystem + FTSTicker survive).
            TestTrue(TEXT("SPIKE: GameInstance survived the travel (same object)"),
                NewServer->GetGameInstance() == GTravelSpike_PreServerGI.Get());
            auto* Ecs = NewServer->GetSubsystem<UCk_EcsWorld_Subsystem_UE>();
            if (ck::Is_NOT_Valid(Ecs)) { AddError(TEXT("SPIKE: post-travel server has no EcsWorld subsystem")); return false; }
            TestTrue(TEXT("SPIKE: post-travel server EcsWorld has a valid transient"),
                ck::IsValid(Ecs->Get_TransientEntity()));

            // (3) THE LOAD-BEARING UNKNOWN: the PIE client rode the seamless travel to a fresh destination world.
            auto* NewClient = ck::auto_test::net::Get_ClientWorld(0);
            if (NewClient == nullptr)
            { AddError(TEXT("SPIKE: client did NOT follow the seamless travel — no post-travel client world (see DIAG dump)")); return false; }
            TestTrue(TEXT("SPIKE: client world instance changed (client rode the travel to a fresh world)"),
                NewClient != GTravelSpike_PreClientWorld.Get());
            TestTrue(TEXT("SPIKE: post-travel client on the destination map"),
                TravelSpike_MapNameOf(NewClient) == TravelSpike_MapPath);
            TestTrue(TEXT("SPIKE: post-travel client begun play"), NewClient->HasBegunPlay());
            UE_LOG(LogTemp, Display, TEXT("DIAG TRAVELSPIKE: post-travel client=[%s] map=[%s] netmode=[%s]"),
                *NewClient->GetName(), *TravelSpike_MapNameOf(NewClient), TravelSpike_NetModeName(NewClient->GetNetMode()));
            TestTrue(TEXT("SPIKE: post-travel client is NM_Client (connection preserved across seamless travel)"),
                NewClient->GetNetMode() == NM_Client);
            return true;
        }),
        TEXT("Seamless ServerTravel: fresh ListenServer server + surviving GI + client rode along to the destination map")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
