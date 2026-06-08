// CkSnapshot M2b-2b SPIKE — verify a hard ServerTravel (listen-server + 1 client) works inside the latent PIE
// automation harness: the server stays a fresh ListenServer, the GameInstance survives, AND the PIE client
// auto-follows (disconnect -> load -> reconnect) to a fresh client world. This last point is the #1 unknown
// gating the whole M2b-2b milestone.
// Surface in Session Frontend: Ck.Snapshot.M2b2b.ServerTravelSpike

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Engine/GameInstance.h"

#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkTests/Net/CkNetAutomation_Common.h"

namespace
{
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

    // Dump every PIE world for diagnosis (netmode / begunPlay / pre-travel identity / has-ecs).
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
                TEXT("DIAG TRAVELSPIKE [%s]: world=[%s] netmode=[%s] begunPlay=[%d] isPreServer=[%d] isPreClient=[%d] ecs=[%d]"),
                InWhen, *World->GetName(), TravelSpike_NetModeName(World->GetNetMode()),
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
    constexpr auto FramesForTravel = 300;    // hard ServerTravel + client disconnect/reconnect needs generous frames
    constexpr auto ReconnectTimeoutSeconds = 30.0f;
    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    GTravelSpike_PreServerWorld = nullptr;
    GTravelSpike_PreClientWorld = nullptr;
    GTravelSpike_PreServerGI    = nullptr;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 1 — stash pre-travel server + client + GI, then issue a hard ServerTravel to the SAME map.
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

            // This is EXACTLY what production DoInitiate_Travel will do on a server world. Bare map name first;
            // if the post-travel assert below shows the server dropped to Standalone, the production fallback is
            // to append "?listen".
            constexpr auto AbsoluteTravel = true;
            InServer->ServerTravel(MapName, AbsoluteTravel);
        })));

    // Tick across the hard travel — server world is destroyed+rebuilt, client disconnects+reconnects.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesForTravel));

    // Stage 2 — wait (poll) until BOTH a fresh server world and a fresh client world are up and begun play.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            auto* NewServer = ck::auto_test::net::Get_ServerWorld();
            auto* NewClient = ck::auto_test::net::Get_ClientWorld(0);
            const auto ServerReady = NewServer != nullptr && NewServer->HasBegunPlay()
                && NewServer != GTravelSpike_PreServerWorld.Get();
            const auto ClientReady = NewClient != nullptr && NewClient->HasBegunPlay()
                && NewClient != GTravelSpike_PreClientWorld.Get();
            return ServerReady && ClientReady;
        }),
        ReconnectTimeoutSeconds));

    // Stage 3 — assert the three empirical gates.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            TravelSpike_DumpWorlds(TEXT("post-travel"));

            // (1) Fresh server world, begun play, STILL a ListenServer (so Get_ServerWorld resolves it post-travel).
            auto* NewServer = ck::auto_test::net::Get_ServerWorld();
            if (NewServer == nullptr)
            { AddError(TEXT("SPIKE: no post-travel server world (Get_ServerWorld null — server may have dropped to Standalone; see DIAG dump)")); return false; }
            TestTrue(TEXT("SPIKE: server world instance changed (real travel happened)"),
                NewServer != GTravelSpike_PreServerWorld.Get());
            TestTrue(TEXT("SPIKE: post-travel server is still NM_ListenServer"),
                NewServer->GetNetMode() == NM_ListenServer);

            // (2) GameInstance survived the travel (CkSnapshot GI-subsystem + FTSTicker survive).
            TestTrue(TEXT("SPIKE: GameInstance survived the travel (same object)"),
                NewServer->GetGameInstance() == GTravelSpike_PreServerGI.Get());
            auto* Ecs = NewServer->GetSubsystem<UCk_EcsWorld_Subsystem_UE>();
            if (ck::Is_NOT_Valid(Ecs)) { AddError(TEXT("SPIKE: post-travel server has no EcsWorld subsystem")); return false; }
            TestTrue(TEXT("SPIKE: post-travel server EcsWorld has a valid transient"),
                ck::IsValid(Ecs->Get_TransientEntity()));

            // (3) THE LOAD-BEARING UNKNOWN: the PIE client auto-followed to a fresh client world.
            auto* NewClient = ck::auto_test::net::Get_ClientWorld(0);
            if (NewClient == nullptr)
            { AddError(TEXT("SPIKE: client did NOT auto-follow ServerTravel — no post-travel client world (see DIAG dump). STOP: pivot per spec.")); return false; }
            TestTrue(TEXT("SPIKE: client world instance changed (client reconnected to a fresh world)"),
                NewClient != GTravelSpike_PreClientWorld.Get());
            TestTrue(TEXT("SPIKE: post-travel client begun play"), NewClient->HasBegunPlay());
            UE_LOG(LogTemp, Display, TEXT("DIAG TRAVELSPIKE: post-travel client=[%s] netmode=[%s]"),
                *NewClient->GetName(), TravelSpike_NetModeName(NewClient->GetNetMode()));
            TestTrue(TEXT("SPIKE: post-travel client is NM_Client (fully reconnected)"),
                NewClient->GetNetMode() == NM_Client);
            return true;
        }),
        TEXT("ServerTravel: fresh ListenServer server + surviving GI + auto-followed reconnected client")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
