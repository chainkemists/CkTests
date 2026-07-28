// CkSnapshot Acceleration-Parity GATE — strict value round-trip of a replicated Acceleration through a listen-server
// SEAMLESS ServerTravel reload, asserted on the CLIENT. The server overrides the acceleration away from the
// entity-script Construct default (zero) before save; the client must show the override post-reload — proving the
// value survived save -> restore -> replication, not just Construct re-derivation. Acceleration is used (not
// Velocity) because nothing mutates it between override and assert — strict equality holds on both worlds.
// Surface in Session Frontend: Ck.Snapshot.Parity.Acceleration_MPReload

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Engine/GameInstance.h"
#include "EngineUtils.h"               // TActorIterator
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel

#include "CkPhysics/Acceleration/CkAcceleration_Utils.h"

#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/OwningActor/CkOwningActor_Utils.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "CkTests/Net/CkAutoTest_NetSubject_M2bProbe_Replicated.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

namespace
{
    constexpr auto AccelParity_MapPath  = TEXT("/Engine/Maps/Entry");
    const auto     AccelParity_SlotName = FName{TEXT("CkSnapshot_AccelParity_GateSlot")};
    const auto     AccelParity_Override = FVector{3.0, 4.0, 5.0};   // != Construct default {0,0,0}

    static TWeakObjectPtr<UWorld> GAccelParity_PreServerWorld;
    static TWeakObjectPtr<UWorld> GAccelParity_PreClientWorld;

    auto AccelParity_MapNameOf(UWorld* InWorld) -> FString
    {
        return InWorld != nullptr ? InWorld->RemovePIEPrefix(InWorld->GetOutermost()->GetName()) : FString{};
    }

    auto AccelParity_Subsystem(UWorld* InWorld) -> UCk_Snapshot_Subsystem_UE*
    {
        if (InWorld == nullptr || InWorld->GetGameInstance() == nullptr) { return nullptr; }
        return InWorld->GetGameInstance()->GetSubsystem<UCk_Snapshot_Subsystem_UE>();
    }

    auto AccelParity_FindProbe(UWorld* InWorld) -> ACk_AutoTest_NetSubject_M2bProbe_Replicated*
    {
        if (InWorld == nullptr) { return nullptr; }
        for (auto It = TActorIterator<ACk_AutoTest_NetSubject_M2bProbe_Replicated>(InWorld); It; ++It) { return *It; }
        return nullptr;
    }

    auto AccelParity_ResolveAccel(AActor* InProbe) -> FCk_Handle_Acceleration
    {
        if (InProbe == nullptr) { return {}; }
        auto Entity = UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(InProbe);
        if (ck::Is_NOT_Valid(Entity)) { return {}; }
        if (NOT UCk_Utils_Acceleration_UE::Has(Entity)) { return {}; }
        return UCk_Utils_Acceleration_UE::Cast(Entity);
    }

    auto AccelParity_Current(AActor* InProbe, bool& OutResolved) -> FVector
    {
        OutResolved = false;
        auto Accel = AccelParity_ResolveAccel(InProbe);
        if (ck::Is_NOT_Valid(Accel)) { return FVector::ZeroVector; }
        OutResolved = true;
        return UCk_Utils_Acceleration_UE::Get_CurrentAcceleration(Accel);
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_AccelerationParity_MPReload_Gate,
    "Ck.Snapshot.Parity.Acceleration_MPReload",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_AccelerationParity_MPReload_Gate::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;        // server window + 1 connected client
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesPerSettle = 30;
    constexpr auto ReloadTimeoutSeconds = 60.0f;
    constexpr auto FramesPostReconnect = 60;

    GAccelParity_PreServerWorld = nullptr;
    GAccelParity_PreClientWorld = nullptr;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, FString{AccelParity_MapPath}));
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

    // Stage 2 — pre-reload sanity: client has the probe AND its Acceleration resolves.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr) { return false; }
            return ck::IsValid(AccelParity_ResolveAccel(AccelParity_FindProbe(Client)));
        }),
        ReadyTimeoutSeconds));

    // Stage 3 — OVERRIDE the acceleration on the server (direct write; settle covers replication).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto Accel = AccelParity_ResolveAccel(AccelParity_FindProbe(InServer));
            if (ck::Is_NOT_Valid(Accel)) { AddError(TEXT("Stage 3: server Acceleration unresolved")); return; }

            UCk_Utils_Acceleration_UE::Request_OverrideAcceleration(Accel, AccelParity_Override, {});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 3b — assert the SERVER holds the override before saving.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto Resolved = false;
            const auto Current = AccelParity_Current(AccelParity_FindProbe(InServer), Resolved);
            TestTrue(TEXT("pre-save server: Acceleration resolved"), Resolved);
            TestTrue(TEXT("pre-save server: Acceleration == override"), Current.Equals(AccelParity_Override, 0.01));
        })));

    // Stage 4 — Save on the server; stash pre-travel worlds.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            GAccelParity_PreServerWorld = InServer;
            GAccelParity_PreClientWorld = ck::auto_test::net::Get_ClientWorld(0);
            auto* Sub = AccelParity_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 4: no snapshot subsystem")); return; }
            Sub->Request_Save(AccelParity_SlotName, FCk_Delegate_OnSaveComplete{});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 5 — fire async Load (triggers seamless ServerTravel) + assert non-blocking.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Sub = AccelParity_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 5: no snapshot subsystem")); return; }
            Sub->Request_Load(AccelParity_SlotName, FCk_Delegate_OnLoadComplete{});
            TestTrue(TEXT("Stage 5: Request_Load non-blocking"), Sub->Get_IsLoadInProgress());
        })));

    // Stage 6 — poll until server finished load AND client rode the travel AND the override CONVERGED on the client.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            if (Server == nullptr || Server == GAccelParity_PreServerWorld.Get() || !Server->HasBegunPlay()) { return false; }
            if (AccelParity_MapNameOf(Server) != AccelParity_MapPath) { return false; }
            auto* Sub = AccelParity_Subsystem(Server);
            if (Sub == nullptr || Sub->Get_IsLoadInProgress()) { return false; }
            if (AccelParity_FindProbe(Server) == nullptr) { return false; }

            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr || Client == GAccelParity_PreClientWorld.Get() || !Client->HasBegunPlay()) { return false; }
            if (AccelParity_MapNameOf(Client) != AccelParity_MapPath) { return false; }

            auto Resolved = false;
            const auto Current = AccelParity_Current(AccelParity_FindProbe(Client), Resolved);
            return Resolved && Current.Equals(AccelParity_Override, 0.01);
        }),
        ReloadTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPostReconnect));

    // Stage 7 — parity assertions on BOTH worlds: the override survived (NOT the zero Construct default).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            auto ServerResolved = false;
            const auto ServerCurrent = AccelParity_Current(AccelParity_FindProbe(Server), ServerResolved);
            TestTrue(TEXT("server: Acceleration resolved post-reload"), ServerResolved);
            TestTrue(TEXT("server: override survived the snapshot round-trip ({3,4,5})"),
                ServerCurrent.Equals(AccelParity_Override, 0.01));

            auto* Client = ck::auto_test::net::Get_ClientWorld(0);
            if (Client == nullptr) { AddError(TEXT("Stage 7: no post-travel client world")); return false; }

            auto ClientResolved = false;
            const auto ClientCurrent = AccelParity_Current(AccelParity_FindProbe(Client), ClientResolved);
            TestTrue(TEXT("client: Acceleration resolved post-reload"), ClientResolved);
            TestTrue(TEXT("client: override round-tripped ({3,4,5}, not default {0,0,0})"),
                ClientCurrent.Equals(AccelParity_Override, 0.01));
            return true;
        }),
        TEXT("Acceleration parity: server override survives save -> seamless reload -> client re-derivation")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
