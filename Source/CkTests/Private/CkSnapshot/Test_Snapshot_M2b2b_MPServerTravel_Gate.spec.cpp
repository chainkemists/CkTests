// CkSnapshot M2b-2b GATE — multiplayer SEAMLESS ServerTravel + client re-derivation.
// Server-side: the M2b-2a contract (restore + respawn + re-bridge + driver re-establish), now under NM_ListenServer
// after a seamless travel. Client-side: the connected client rides the seamless travel (preserved UNetConnection)
// and independently re-derives the restored entity + actor + replicated state, purely via replication, with no
// client-side snapshot code.
// Surface in Session Frontend: Ck.Snapshot.M2b2b.MPServerTravel

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Engine/GameInstance.h"
#include "EngineUtils.h" // TActorIterator
#include "HAL/IConsoleManager.h" // net.AllowPIESeamlessTravel

#include "CkAttribute/FloatAttribute/CkFloatAttribute_Utils.h"
#include "CkAttribute/FloatAttribute/CkFloatAttribute_Fragment.h"

#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/OwningActor/CkOwningActor_Utils.h"
#include "CkEcs/Net/EntityReplicationDriver/CkEntityReplicationDriver_Utils.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "CkTests/Net/CkAutoTest_NetSubject_M2bProbe_Replicated.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

namespace
{
    constexpr auto M2b2b_MapPath          = TEXT("/Engine/Maps/Entry");
    constexpr auto M2b2b_AttributeTagName = TEXT("FloatAttribute.Health");
    constexpr auto M2b2b_ExpectedFinal    = 42.5f;
    const auto     M2b2b_SlotName         = FName{TEXT("CkSnapshot_M2b2b_GateSlot")};
    const auto     M2b2b_SavedLocation    = FVector{100.0, 200.0, 300.0};

    static TWeakObjectPtr<UWorld> GM2b2b_PreServerWorld;
    static TWeakObjectPtr<UWorld> GM2b2b_PreClientWorld;

    auto M2b2b_MapNameOf(UWorld* InWorld) -> FString
    {
        return InWorld != nullptr ? InWorld->RemovePIEPrefix(InWorld->GetOutermost()->GetName()) : FString{};
    }

    auto M2b2b_Subsystem(UWorld* InWorld) -> UCk_Snapshot_Subsystem_UE*
    {
        if (InWorld == nullptr || InWorld->GetGameInstance() == nullptr) { return nullptr; }
        return InWorld->GetGameInstance()->GetSubsystem<UCk_Snapshot_Subsystem_UE>();
    }

    auto M2b2b_FindProbe(UWorld* InWorld) -> ACk_AutoTest_NetSubject_M2bProbe_Replicated*
    {
        if (InWorld == nullptr) { return nullptr; }
        for (auto It = TActorIterator<ACk_AutoTest_NetSubject_M2bProbe_Replicated>(InWorld); It; ++It) { return *It; }
        return nullptr;
    }

    auto M2b2b_CountProbes(UWorld* InWorld) -> int32
    {
        auto Count = 0;
        if (InWorld == nullptr) { return 0; }
        for (auto It = TActorIterator<ACk_AutoTest_NetSubject_M2bProbe_Replicated>(InWorld); It; ++It) { ++Count; }
        return Count;
    }

    auto M2b2b_ResolveEntity(AActor* InProbe) -> FCk_Handle
    {
        if (InProbe == nullptr) { return {}; }
        return UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(InProbe);
    }

    auto M2b2b_ResolveAttribute(AActor* InProbe) -> FCk_Handle_FloatAttribute
    {
        const auto Entity = M2b2b_ResolveEntity(InProbe);
        if (ck::Is_NOT_Valid(Entity)) { return {}; }
        return UCk_Utils_FloatAttribute_UE::TryGet(Entity, FGameplayTag::RequestGameplayTag(FName{M2b2b_AttributeTagName}));
    }

    // Reads the LIVE FloatAttribute.Health final value straight from a world's registry (independent of the
    // actor<->entity bridge). Mirrors the proven M2b-2a gate helper. OutCount = how many FloatAttribute entities.
    auto M2b2b_LiveFinalFromRawView(UWorld* InWorld, int32& OutCount) -> float
    {
        OutCount = 0;
        auto Final = -1.0f;
        auto* Ecs = InWorld ? InWorld->GetSubsystem<UCk_EcsWorld_Subsystem_UE>() : nullptr;
        if (ck::Is_NOT_Valid(Ecs)) { return Final; }
        auto& CkRegistry = Ecs->Get_Registry();
        auto* Raw = ck::registry_table::TryResolve(CkRegistry.Get_RegistryHandle());
        if (Raw == nullptr) { return Final; }
        for (const auto Entity : Raw->view<ck::FFragment_FloatAttribute_Current>())
        {
            ++OutCount;
            auto Handle = ck::MakeHandle(FCk_Entity{Entity}, CkRegistry);
            auto AttrHandle = UCk_Utils_FloatAttribute_UE::Cast(Handle);
            Final = static_cast<float>(UCk_Utils_FloatAttribute_UE::Get_FinalValue(AttrHandle));
        }
        return Final;
    }

    // UE_LOG (lands in the toolbox log, unlike AddInfo) the full bridge/attribute state of the probe in a world,
    // PLUS the probe ACTOR's identity. Comparing the client probe pre- vs post-reload bisects the failure: same
    // name+uid => stale actor carried across seamless travel (no fresh spawn/construct); different name+uid => a
    // fresh replicated actor (begunPlay/bridgeValid then show whether its WithActor::Construct ran + bound).
    auto M2b2b_LogState(const TCHAR* InWhen, const TCHAR* InRole, UWorld* InWorld) -> void
    {
        auto* Probe = M2b2b_FindProbe(InWorld);
        const auto Entity = M2b2b_ResolveEntity(Probe);
        auto AttrCount = 0;
        const auto Final = M2b2b_LiveFinalFromRawView(InWorld, AttrCount);

        auto ProbeName  = FString{TEXT("none")};
        auto ProbeUid   = uint32{0};
        auto ProbeBegun = 0;
        auto ProbeRole  = -1;
        auto ProbeLoc   = FString{TEXT("n/a")};
        if (Probe != nullptr)
        {
            ProbeName  = Probe->GetName();
            ProbeUid   = Probe->GetUniqueID();
            ProbeBegun = Probe->HasActorBegunPlay() ? 1 : 0;
            ProbeRole  = static_cast<int32>(Probe->GetLocalRole());
            ProbeLoc   = Probe->GetActorLocation().ToString();
        }

        UE_LOG(LogTemp, Display,
            TEXT("DIAG M2b2b [%s] %s: world=[%s] map=[%s] netmode=[%d] probeCount=[%d] bridgeValid=[%d] attrCount=[%d] attrFinal=[%f] | probeName=[%s] probeUid=[%u] begunPlay=[%d] localRole=[%d] loc=[%s]"),
            InWhen, InRole,
            InWorld ? *InWorld->GetName() : TEXT("null"), *M2b2b_MapNameOf(InWorld),
            InWorld ? static_cast<int32>(InWorld->GetNetMode()) : -99,
            M2b2b_CountProbes(InWorld), ck::IsValid(Entity) ? 1 : 0, AttrCount, Final,
            *ProbeName, ProbeUid, ProbeBegun, ProbeRole, *ProbeLoc);
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_M2b2b_MPServerTravel_Gate,
    "Ck.Snapshot.M2b2b.MPServerTravel",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_M2b2b_MPServerTravel_Gate::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;        // server window + 1 real connected client
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesPerSettle = 30;
    constexpr auto ReloadTimeoutSeconds = 60.0f; // seamless: ~4s ServerTravelPause + transition + restore + replication
    constexpr auto FramesPostReconnect = 60;     // converge replicated attribute + position on the client

    GM2b2b_PreServerWorld = nullptr;
    GM2b2b_PreClientWorld = nullptr;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, FString{M2b2b_MapPath}));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // Stage 1 — open the PIE seamless-travel gate + spawn the REPLICATED bridged probe on the server.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
            { CVar->Set(1, ECVF_SetByCode); }

            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
            auto* Probe = InServer->SpawnActor<ACk_AutoTest_NetSubject_M2bProbe_Replicated>(
                ACk_AutoTest_NetSubject_M2bProbe_Replicated::StaticClass(), FTransform{M2b2b_SavedLocation}, SpawnInfo);
            if (Probe == nullptr) { AddError(TEXT("Stage 1: replicated probe spawn returned null")); }
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 2 — sanity: the client has the replicated copy BEFORE the reload.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            return Client != nullptr && M2b2b_FindProbe(Client) != nullptr;
        }),
        ReadyTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr) { AddError(TEXT("Stage 2: no client world pre-reload")); return false; }
            M2b2b_LogState(TEXT("pre-reload"), TEXT("server"), ck::auto_test::net::Get_ServerWorld());
            M2b2b_LogState(TEXT("pre-reload"), TEXT("client"), Client);
            TestTrue(TEXT("pre-reload: client has the replicated probe"), M2b2b_FindProbe(Client) != nullptr);
            return true;
        }),
        TEXT("pre-reload client baseline: replicated probe present on the client")));

    // Stage 3 — pre-save sanity + Save on the server; stash pre-travel worlds.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Probe = M2b2b_FindProbe(InServer);
            const auto Attr = M2b2b_ResolveAttribute(Probe);
            if (ck::Is_NOT_Valid(Attr)) { AddError(TEXT("Stage 3: could not resolve attribute pre-save")); return; }
            TestEqual(TEXT("pre-save server Final == 42.5"),
                static_cast<float>(UCk_Utils_FloatAttribute_UE::Get_FinalValue(Attr)), M2b2b_ExpectedFinal);

            GM2b2b_PreServerWorld = InServer;
            GM2b2b_PreClientWorld = ck::auto_test::net::Get_ClientWorld(0);

            auto* Sub = M2b2b_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 3: no snapshot subsystem")); return; }
            Sub->Request_Save(M2b2b_SlotName, FCk_Delegate_OnSaveComplete{});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 4 — fire the async load (triggers seamless ServerTravel internally) + assert non-blocking.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Sub = M2b2b_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 4: no snapshot subsystem")); return; }
            Sub->Request_Load(M2b2b_SlotName, FCk_Delegate_OnLoadComplete{});
            TestTrue(TEXT("Stage 4: Request_Load non-blocking — load in progress after return"),
                Sub->Get_IsLoadInProgress());
        })));

    // Stage 5 — poll until the server finished the load AND the client rode the seamless travel to the restored probe.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            if (Server == nullptr || Server == GM2b2b_PreServerWorld.Get() || !Server->HasBegunPlay()) { return false; }
            if (M2b2b_MapNameOf(Server) != M2b2b_MapPath) { return false; } // skip the seamless transition map
            auto* Sub = M2b2b_Subsystem(Server);
            if (Sub == nullptr || Sub->Get_IsLoadInProgress()) { return false; }
            if (M2b2b_FindProbe(Server) == nullptr) { return false; }

            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr || Client == GM2b2b_PreClientWorld.Get() || !Client->HasBegunPlay()) { return false; }
            if (M2b2b_MapNameOf(Client) != M2b2b_MapPath) { return false; }
            auto* ClientProbe = M2b2b_FindProbe(Client);
            if (ClientProbe == nullptr) { return false; }
            // Wait for FULL client re-derivation (bridge + replicated attribute), not just the actor — rules out a
            // too-early assert. If this never becomes true the poll times out (ReloadTimeoutSeconds) and Stage 7
            // reports the gap, with the post-reload DIAG showing the exact client state.
            if (ck::Is_NOT_Valid(M2b2b_ResolveEntity(ClientProbe))) { return false; }
            auto ClientAttrCount = 0;
            M2b2b_LiveFinalFromRawView(Client, ClientAttrCount);
            return ClientAttrCount >= 1;
        }),
        ReloadTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPostReconnect));

    // Stage 6 — SERVER assertions (the M2b-2a contract, now under NM_ListenServer after seamless travel).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            if (Server == nullptr) { AddError(TEXT("Stage 6: no post-travel server world (Get_ServerWorld null)")); return false; }
            TestTrue(TEXT("server: real travel happened — world instance changed"), Server != GM2b2b_PreServerWorld.Get());
            TestTrue(TEXT("server: on the destination map"), M2b2b_MapNameOf(Server) == M2b2b_MapPath);
            TestTrue(TEXT("server: still NM_ListenServer post-travel"), Server->GetNetMode() == NM_ListenServer);

            auto* Sub = M2b2b_Subsystem(Server);
            if (Sub == nullptr) { AddError(TEXT("Stage 6: no snapshot subsystem")); return false; }
            TestFalse(TEXT("server: load flag cleared after completion"), Sub->Get_IsLoadInProgress());

            TestEqual(TEXT("server: exactly one probe actor (no duplicate)"), M2b2b_CountProbes(Server), 1);

            auto* Probe = M2b2b_FindProbe(Server);
            if (Probe == nullptr) { AddError(TEXT("Stage 6: probe was not re-spawned on the server")); return false; }

            const auto Entity = M2b2b_ResolveEntity(Probe);
            TestTrue(TEXT("server: actor<->entity bridge resolves (re-bridge worked)"), ck::IsValid(Entity));
            TestTrue(TEXT("server: replication driver re-established on the restored entity"),
                ck::IsValid(Entity) && UCk_Utils_EntityReplicationDriver_UE::Has(Entity));

            const auto RespawnedLoc = Probe->GetActorLocation();
            AddInfo(FString::Printf(TEXT("DIAG M2b2b server position: respawned actor at %s (saved %s)"),
                *RespawnedLoc.ToString(), *M2b2b_SavedLocation.ToString()));
            TestTrue(TEXT("server: respawned actor restored to its saved world location"),
                RespawnedLoc.Equals(M2b2b_SavedLocation, 1.0));

            auto AttrCount = 0;
            const auto Final = M2b2b_LiveFinalFromRawView(Server, AttrCount);
            AddInfo(FString::Printf(TEXT("DIAG M2b2b server Stage 6: FloatAttribute entities=%d | Final=%f"), AttrCount, Final));
            TestTrue(TEXT("server: at least one float attribute survived restore"), AttrCount >= 1);
            if (AttrCount >= 1)
            { TestEqual(TEXT("server: restored attribute Final == 42.5"), Final, M2b2b_ExpectedFinal); }
            return true;
        }),
        TEXT("M2b-2b server: restore + respawn + re-bridge + driver re-establish under NM_ListenServer, no duplicate")));

    // Stage 7 — CLIENT assertions (the M2b-2b differentiator: cross-world re-derivation via replication only).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr) { AddError(TEXT("Stage 7: no post-travel client world")); return false; }
            M2b2b_LogState(TEXT("post-reload"), TEXT("server"), ck::auto_test::net::Get_ServerWorld());
            M2b2b_LogState(TEXT("post-reload"), TEXT("client"), Client);
            TestTrue(TEXT("client: rode the travel to a fresh world"), Client != GM2b2b_PreClientWorld.Get());
            TestTrue(TEXT("client: on the destination map"), M2b2b_MapNameOf(Client) == M2b2b_MapPath);
            TestTrue(TEXT("client: NM_Client"), Client->GetNetMode() == NM_Client);

            TestEqual(TEXT("client: exactly one probe actor (no duplicate)"), M2b2b_CountProbes(Client), 1);

            auto* Probe = M2b2b_FindProbe(Client);
            if (Probe == nullptr) { AddError(TEXT("Stage 7: replicated probe not present on the client")); return false; }

            // Client-side reverse lookup requires WithActor::Construct to have run client-side (the reconstitution
            // abstention is server-only) — proves the client independently bridged the replicated actor.
            const auto Entity = M2b2b_ResolveEntity(Probe);
            TestTrue(TEXT("client: actor<->entity bridge resolves (client-side Construct ran, no abstention)"),
                ck::IsValid(Entity));

            auto AttrCount = 0;
            const auto Final = M2b2b_LiveFinalFromRawView(Client, AttrCount);
            AddInfo(FString::Printf(TEXT("DIAG M2b2b client Stage 7: FloatAttribute entities=%d | Final=%f (expected %f)"),
                AttrCount, Final, M2b2b_ExpectedFinal));
            TestTrue(TEXT("client: at least one float attribute replicated to the client"), AttrCount >= 1);
            if (AttrCount >= 1)
            { TestEqual(TEXT("client: replicated attribute Final == 42.5"), Final, M2b2b_ExpectedFinal); }

            const auto ClientLoc = Probe->GetActorLocation();
            AddInfo(FString::Printf(TEXT("DIAG M2b2b client position: actor at %s (saved %s)"),
                *ClientLoc.ToString(), *M2b2b_SavedLocation.ToString()));
            TestTrue(TEXT("client: replicated actor position matches saved location"),
                ClientLoc.Equals(M2b2b_SavedLocation, 1.0));
            return true;
        }),
        TEXT("M2b-2b client: re-derived entity + actor + replicated attribute + position via replication, no duplicate")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
